import Foundation
import InvoiceDomain

public actor DeletionCoordinator {
    private static let quarantinePrefix = ".Deletion-"

    private let database: AppDatabase
    private let filesRoot: URL
    private let fileManager: FileManager

    public init(database: AppDatabase, filesRoot: URL, fileManager: FileManager = .default) {
        self.database = database
        self.filesRoot = filesRoot
        self.fileManager = fileManager
    }

    public func deleteAll() async throws {
        try await reconcileInterruptedDeletion()
        let deletionID = UUID()
        let quarantine = filesRoot.appendingPathComponent(
            Self.quarantinePrefix + deletionID.uuidString.lowercased(),
            isDirectory: true
        )
        try fileManager.createDirectory(at: quarantine, withIntermediateDirectories: true)
        do {
            try moveLiveDirectories(into: quarantine)
            try await database.deleteAllDomainData(committedDeletionID: deletionID)
        } catch {
            let originalError = error
            do {
                try restoreDirectories(from: quarantine)
                try fileManager.removeItem(at: quarantine)
            } catch {
                // Keep the durable quarantine for reconciliation on the next launch.
                throw error
            }
            throw originalError
        }
        // A crash or cleanup failure here is reconciled as committed deletion on next launch.
        try? fileManager.removeItem(at: quarantine)
    }

    public func reconcileInterruptedDeletion() async throws {
        let quarantines = try quarantineDirectories()
        guard !quarantines.isEmpty else { return }
        let committedID = try await database.committedDeletionID()
        var interrupted: [URL] = []
        for quarantine in quarantines {
            if quarantineID(for: quarantine) == committedID {
                try fileManager.removeItem(at: quarantine)
            } else {
                interrupted.append(quarantine)
            }
        }
        guard !interrupted.isEmpty else { return }
        guard interrupted.count == 1 else {
            throw InvoiceError.corruptData("multiple_interrupted_deletions")
        }
        try restoreDirectories(from: interrupted[0])
        try fileManager.removeItem(at: interrupted[0])
    }

    private func quarantineDirectories() throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: filesRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ).filter { url in
            guard url.lastPathComponent.hasPrefix(Self.quarantinePrefix),
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
                return false
            }
            return values.isDirectory == true && values.isSymbolicLink != true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func quarantineID(for url: URL) -> UUID? {
        let name = url.lastPathComponent
        guard name.hasPrefix(Self.quarantinePrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(Self.quarantinePrefix.count)))
    }

    private func moveLiveDirectories(into quarantine: URL) throws {
        for name in ["Invoices", "Staging", "Recovery"] {
            let source = filesRoot.appendingPathComponent(name, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(
                at: source,
                to: quarantine.appendingPathComponent(name, isDirectory: true)
            )
        }
    }

    private func restoreDirectories(from quarantine: URL) throws {
        for name in ["Invoices", "Staging", "Recovery"] {
            let quarantined = quarantine.appendingPathComponent(name, isDirectory: true)
            guard fileManager.fileExists(atPath: quarantined.path) else { continue }
            let destination = filesRoot.appendingPathComponent(name, isDirectory: true)
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw InvoiceError.corruptData("deletion_restore_destination_exists")
            }
            try fileManager.moveItem(at: quarantined, to: destination)
        }
    }
}
