import CryptoKit
import Foundation
import InvoiceDomain
import InvoicePersistence

public struct BackupManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let appBuild: String
    public let createdAt: Date
    public let files: [BackupFile]
}

public struct BackupFile: Codable, Equatable, Sendable {
    public let relativePath: String
    public let byteCount: Int
    public let sha256: String
}

public enum RestoreMode: String, Codable, Sendable {
    case replace
    case merge
}

public struct RestoreReport: Hashable, Sendable {
    public let mode: RestoreMode
    public let databaseMerge: DatabaseMergeReport?
    public let pdfsAdded: Int
    public let pdfsReused: Int

    public init(mode: RestoreMode, databaseMerge: DatabaseMergeReport?, pdfsAdded: Int, pdfsReused: Int) {
        self.mode = mode
        self.databaseMerge = databaseMerge
        self.pdfsAdded = pdfsAdded
        self.pdfsReused = pdfsReused
    }
}

public actor BackupService {
    private let database: AppDatabase
    private let filesRoot: URL
    private let fileManager: FileManager

    public init(database: AppDatabase, filesRoot: URL, fileManager: FileManager = .default) {
        self.database = database
        self.filesRoot = filesRoot
        self.fileManager = fileManager
    }

    public func export(to packageURL: URL, appBuild: String) async throws {
        let temporary = packageURL.deletingLastPathComponent().appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporary) }

        let databaseURL = temporary.appendingPathComponent("data.sqlite")
        try await database.exportDatabase(to: databaseURL.path)
        let pdfSource = filesRoot.appendingPathComponent("Invoices", isDirectory: true)
        let pdfDestination = temporary.appendingPathComponent("pdfs", isDirectory: true)
        try fileManager.createDirectory(at: pdfDestination, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: pdfSource.path) {
            for url in try fileManager.contentsOfDirectory(at: pdfSource, includingPropertiesForKeys: nil) where url.pathExtension.lowercased() == "pdf" {
                try fileManager.copyItem(at: url, to: pdfDestination.appendingPathComponent(url.lastPathComponent))
            }
        }

        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw InvoiceError.corruptData("database_export_missing")
        }
        var fileRecords: [BackupFile] = []
        let databaseData = try Data(contentsOf: databaseURL, options: [.mappedIfSafe])
        fileRecords.append(BackupFile(relativePath: "data.sqlite", byteCount: databaseData.count, sha256: sha256(databaseData)))
        for url in try regularFiles(root: pdfDestination) {
            let relative = "pdfs/" + url.lastPathComponent
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            fileRecords.append(BackupFile(relativePath: relative, byteCount: data.count, sha256: sha256(data)))
        }
        let manifest = BackupManifest(schemaVersion: AppDatabase.schemaVersion, appBuild: appBuild, createdAt: Date(), files: fileRecords.sorted { $0.relativePath < $1.relativePath })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: temporary.appendingPathComponent("manifest.json"), options: .atomic)
        _ = try validate(packageURL: temporary)

        if fileManager.fileExists(atPath: packageURL.path) { try fileManager.removeItem(at: packageURL) }
        try fileManager.moveItem(at: temporary, to: packageURL)
    }

    @discardableResult
    public func validate(packageURL: URL) throws -> BackupManifest {
        let standardizedRoot = packageURL.standardizedFileURL
        let manifestURL = standardizedRoot.appendingPathComponent("manifest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(BackupManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.schemaVersion <= AppDatabase.schemaVersion else {
            throw InvoiceError.corruptData("newer_backup_schema")
        }
        guard manifest.files.contains(where: { $0.relativePath == "data.sqlite" }) else {
            throw InvoiceError.corruptData("missing_database")
        }
        guard Set(manifest.files.map(\.relativePath)).count == manifest.files.count else {
            throw InvoiceError.corruptData("duplicate_manifest_path")
        }
        for file in manifest.files {
            guard !file.relativePath.hasPrefix("/"), !file.relativePath.contains("..") else {
                throw InvoiceError.corruptData("path_traversal")
            }
            let url = standardizedRoot.appendingPathComponent(file.relativePath).standardizedFileURL
            guard url.path.hasPrefix(standardizedRoot.path + "/") else {
                throw InvoiceError.corruptData("path_escape")
            }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true else {
                throw InvoiceError.corruptData("unsupported_file_type")
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count == file.byteCount, sha256(data) == file.sha256 else {
                throw InvoiceError.corruptData("hash_mismatch")
            }
        }
        let actualFiles = Set(try regularFiles(root: standardizedRoot).map {
            let canonicalPath = $0.standardizedFileURL.path
            return String(canonicalPath.dropFirst(standardizedRoot.path.count + 1))
        }.filter { $0 != "manifest.json" })
        let expectedFiles = Set(manifest.files.map(\.relativePath))
        guard actualFiles == expectedFiles else {
            let actual = actualFiles.sorted().joined(separator: ",")
            let expected = expectedFiles.sorted().joined(separator: ",")
            throw InvoiceError.corruptData("unmanifested_file_actual=[\(actual)]_expected=[\(expected)]")
        }
        try AppDatabase.validateDatabaseFile(at: standardizedRoot.appendingPathComponent("data.sqlite").path)
        return manifest
    }

    public func preflightRestore(packageURL: URL, mode: RestoreMode) async throws -> RestoreReport {
        let manifest = try validate(packageURL: packageURL)
        let mergeReport: DatabaseMergeReport?
        if mode == .merge {
            mergeReport = try await database.mergeContents(
                from: packageURL.appendingPathComponent("data.sqlite").path,
                dryRun: true
            )
        } else {
            mergeReport = nil
        }
        let pdfCounts = try inspectPDFs(packageURL: packageURL, manifest: manifest, mode: mode)
        return RestoreReport(mode: mode, databaseMerge: mergeReport, pdfsAdded: pdfCounts.added, pdfsReused: pdfCounts.reused)
    }

    public func restore(packageURL: URL, mode: RestoreMode) async throws -> RestoreReport {
        let preflight = try await preflightRestore(packageURL: packageURL, mode: mode)
        if let merge = preflight.databaseMerge, !merge.canCommit {
            throw InvoiceError.corruptData("merge_conflict")
        }

        let rollbackRoot = filesRoot.appendingPathComponent(".restore-rollback-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rollbackRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rollbackRoot) }
        let rollbackDatabase = rollbackRoot.appendingPathComponent("data.sqlite")
        try await database.exportDatabase(to: rollbackDatabase.path)
        let liveInvoices = filesRoot.appendingPathComponent("Invoices", isDirectory: true)
        let rollbackInvoices = rollbackRoot.appendingPathComponent("Invoices", isDirectory: true)
        if fileManager.fileExists(atPath: liveInvoices.path) {
            try fileManager.copyItem(at: liveInvoices, to: rollbackInvoices)
        }

        do {
            let incomingDatabase = packageURL.appendingPathComponent("data.sqlite").path
            let committedMerge: DatabaseMergeReport?
            switch mode {
            case .replace:
                try await database.replaceContents(from: incomingDatabase)
                committedMerge = nil
                try replaceInvoiceDirectory(from: packageURL.appendingPathComponent("pdfs", isDirectory: true))
            case .merge:
                committedMerge = try await database.mergeContents(from: incomingDatabase)
                guard committedMerge?.canCommit == true else {
                    throw InvoiceError.corruptData("merge_conflict")
                }
                try mergeInvoiceDirectory(from: packageURL.appendingPathComponent("pdfs", isDirectory: true))
            }
            try await database.integrityCheck()
            return RestoreReport(
                mode: mode,
                databaseMerge: committedMerge,
                pdfsAdded: preflight.pdfsAdded,
                pdfsReused: preflight.pdfsReused
            )
        } catch {
            try? await database.replaceContents(from: rollbackDatabase.path)
            try? replaceInvoiceDirectory(from: rollbackInvoices)
            throw error
        }
    }

    private func regularFiles(root: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw InvoiceError.corruptData("symlink") }
            if values.isRegularFile == true { result.append(url) }
        }
        return result
    }

    private func inspectPDFs(packageURL: URL, manifest: BackupManifest, mode: RestoreMode) throws -> (added: Int, reused: Int) {
        let liveInvoices = filesRoot.appendingPathComponent("Invoices", isDirectory: true)
        var added = 0
        var reused = 0
        for record in manifest.files where record.relativePath.hasPrefix("pdfs/") {
            let filename = URL(fileURLWithPath: record.relativePath).lastPathComponent
            let destination = liveInvoices.appendingPathComponent(filename)
            guard mode == .merge, fileManager.fileExists(atPath: destination.path) else {
                added += 1
                continue
            }
            let data = try Data(contentsOf: destination, options: [.mappedIfSafe])
            guard sha256(data) == record.sha256 else {
                throw InvoiceError.corruptData("pdf_merge_conflict_\(filename)")
            }
            reused += 1
        }
        return (added, reused)
    }

    private func replaceInvoiceDirectory(from source: URL) throws {
        let destination = filesRoot.appendingPathComponent("Invoices", isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: source.path) else { return }
        for file in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey]) {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  file.pathExtension.lowercased() == "pdf" else { continue }
            try fileManager.copyItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent))
        }
    }

    private func mergeInvoiceDirectory(from source: URL) throws {
        let destination = filesRoot.appendingPathComponent("Invoices", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: source.path) else { return }
        for file in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey]) {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if !fileManager.fileExists(atPath: target.path) {
                try fileManager.copyItem(at: file, to: target)
            }
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
