import CryptoKit
import Foundation
import InvoiceDomain

public actor IssueService {
    public typealias Renderer = @Sendable (IssuedInvoice) async throws -> Data

    private let database: AppDatabase
    private let filesRoot: URL
    private let renderer: Renderer
    private let fileManager: FileManager

    public init(database: AppDatabase, filesRoot: URL, renderer: @escaping Renderer, fileManager: FileManager = .default) {
        self.database = database
        self.filesRoot = filesRoot
        self.renderer = renderer
        self.fileManager = fileManager
    }

    public func issue(
        draft: InvoiceDraft,
        business: BusinessProfile,
        customer: Customer,
        sites: [UUID: Site],
        visits: [Visit],
        hasPro: Bool
    ) async throws -> IssuedInvoice {
        let number = try await database.proposedNumber(issueDate: draft.issueDate, prefix: business.invoicePrefix)
        let invoice = try InvoiceCalculator.snapshot(
            number: number,
            draft: draft,
            business: business,
            customer: customer,
            sites: sites,
            visits: visits
        )
        let pdfData = try await renderer(invoice)
        return try await commit(
            invoice: invoice,
            pdfData: pdfData,
            visits: visits,
            hasPro: hasPro
        )
    }

    public func issuePrepared(
        invoice: IssuedInvoice,
        pdfData: Data,
        draft: InvoiceDraft,
        business: BusinessProfile,
        customer: Customer,
        sites: [UUID: Site],
        visits: [Visit],
        hasPro: Bool
    ) async throws -> IssuedInvoice {
        let expected = try InvoiceCalculator.snapshot(
            id: invoice.id,
            number: invoice.number,
            draft: draft,
            business: business,
            customer: customer,
            sites: sites,
            visits: visits,
            issuedAt: invoice.issuedAt
        )
        guard Self.equivalentForIssue(invoice, expected) else {
            throw InvoiceError.corruptData("prepared_invoice_mismatch")
        }
        return try await commit(
            invoice: invoice,
            pdfData: pdfData,
            visits: visits,
            hasPro: hasPro
        )
    }

    public func issueCorrectionPrepared(
        originalID: UUID,
        replacement: IssuedInvoice,
        pdfData: Data,
        hasPro: Bool
    ) async throws -> IssuedInvoice {
        guard let original = try await database.invoice(id: originalID),
              original.status == .issued || original.status == .paid,
              original.replacedByInvoiceID == nil else {
            throw InvoiceError.invalidTransition
        }
        let expected = try InvoiceCalculator.correctionSnapshot(
            id: replacement.id,
            number: replacement.number,
            original: original,
            issueDate: replacement.issueDate,
            dueDate: replacement.dueDate,
            lines: replacement.lines.map(InvoiceCorrectionLine.init(invoiceLine:)),
            issuer: replacement.issuer,
            customerName: replacement.customerName,
            customerAddress: replacement.customerAddress,
            coveredStart: replacement.coveredStart,
            coveredEnd: replacement.coveredEnd,
            issuedAt: replacement.issuedAt
        )
        guard Self.equivalentForCorrection(replacement, expected) else {
            throw InvoiceError.corruptData("prepared_correction_mismatch")
        }
        return try await commitCorrection(
            originalID: originalID,
            expectedOriginal: original,
            replacement: replacement,
            pdfData: pdfData,
            hasPro: hasPro
        )
    }

    private func commit(
        invoice: IssuedInvoice,
        pdfData: Data,
        visits: [Visit],
        hasPro: Bool
    ) async throws -> IssuedInvoice {
        let entitlement = try await database.entitlementUsage(hasPro: hasPro)
        guard entitlement.permitsCleanIssue else { throw InvoiceError.entitlementRequired }
        guard !pdfData.isEmpty else { throw InvoiceError.corruptData("empty_pdf") }
        let hash = SHA256.hash(data: pdfData).map { String(format: "%02x", $0) }.joined()

        let stagingDirectory = filesRoot.appendingPathComponent("Staging", isDirectory: true)
        let finalDirectory = filesRoot.appendingPathComponent("Invoices", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: finalDirectory, withIntermediateDirectories: true)
        let filename = invoice.id.uuidString.lowercased() + ".pdf"
        let stagedURL = stagingDirectory.appendingPathComponent(filename)
        let finalURL = finalDirectory.appendingPathComponent(filename)
        try pdfData.write(to: stagedURL, options: [.atomic, .completeFileProtection])

        let stagedRelative = "Staging/\(filename)"
        let finalRelative = "Invoices/\(filename)"
        let operationID: UUID
        do {
            operationID = try await database.commitIssue(
                invoice: invoice,
                sourceVisitIDs: visits.map(\.id),
                stagedPath: stagedRelative,
                finalPath: finalRelative,
                pdfHash: hash,
                consumeFreeAllowance: !hasPro && entitlement.firstCleanInvoiceID == nil
            )
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            throw error
        }

        do {
            guard !fileManager.fileExists(atPath: finalURL.path) else {
                throw InvoiceError.corruptData("unexpected_existing_pdf")
            }
            try fileManager.moveItem(at: stagedURL, to: finalURL)
            try await database.completeFileOperation(operationID)
        } catch {
            throw InvoiceError.corruptData("issued_pdf_needs_recovery")
        }
        var storedInvoice = invoice
        storedInvoice.pdfRelativePath = finalRelative
        storedInvoice.pdfSHA256 = hash
        return storedInvoice
    }

    private func commitCorrection(
        originalID: UUID,
        expectedOriginal: IssuedInvoice,
        replacement: IssuedInvoice,
        pdfData: Data,
        hasPro: Bool
    ) async throws -> IssuedInvoice {
        let entitlement = try await database.entitlementUsage(hasPro: hasPro)
        guard entitlement.permitsCleanIssue else { throw InvoiceError.entitlementRequired }
        guard !pdfData.isEmpty else { throw InvoiceError.corruptData("empty_pdf") }
        let hash = SHA256.hash(data: pdfData).map { String(format: "%02x", $0) }.joined()

        let stagingDirectory = filesRoot.appendingPathComponent("Staging", isDirectory: true)
        let finalDirectory = filesRoot.appendingPathComponent("Invoices", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: finalDirectory, withIntermediateDirectories: true)
        let filename = replacement.id.uuidString.lowercased() + ".pdf"
        let stagedURL = stagingDirectory.appendingPathComponent(filename)
        let finalURL = finalDirectory.appendingPathComponent(filename)
        try pdfData.write(to: stagedURL, options: [.atomic, .completeFileProtection])

        let stagedRelative = "Staging/\(filename)"
        let finalRelative = "Invoices/\(filename)"
        let operationID: UUID
        do {
            operationID = try await database.commitCorrection(
                originalID: originalID,
                expectedOriginal: expectedOriginal,
                replacement: replacement,
                stagedPath: stagedRelative,
                finalPath: finalRelative,
                pdfHash: hash,
                hasPro: hasPro
            )
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            throw error
        }

        do {
            guard !fileManager.fileExists(atPath: finalURL.path) else {
                throw InvoiceError.corruptData("unexpected_existing_pdf")
            }
            try fileManager.moveItem(at: stagedURL, to: finalURL)
            try await database.completeFileOperation(operationID)
        } catch {
            throw InvoiceError.corruptData("issued_pdf_needs_recovery")
        }
        var stored = replacement
        stored.pdfRelativePath = finalRelative
        stored.pdfSHA256 = hash
        return stored
    }

    public func recoverPendingFileOperations() async throws {
        let operations = try await database.pendingFileOperations()
        for operation in operations {
            let stagedURL = try recoveryURL(relativePath: operation.stagedPath, directory: "Staging")
            let finalURL = try recoveryURL(relativePath: operation.finalPath, directory: "Invoices")
            if try matchesHash(url: finalURL, expected: operation.sha256) {
                try await database.completeFileOperation(operation.id)
            } else if try matchesHash(url: stagedURL, expected: operation.sha256) {
                try fileManager.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: finalURL.path) {
                    let quarantine = filesRoot
                        .appendingPathComponent("Recovery", isDirectory: true)
                        .appendingPathComponent(operation.id.uuidString.lowercased() + "-conflict.pdf")
                    try fileManager.createDirectory(at: quarantine.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.moveItem(at: finalURL, to: quarantine)
                }
                try fileManager.moveItem(at: stagedURL, to: finalURL)
                try await database.completeFileOperation(operation.id)
            } else {
                try await database.markNeedsRecovery(
                    invoiceID: operation.invoiceID,
                    operationID: operation.id
                )
            }
        }
    }

    public func canonicalPDFData(for invoice: IssuedInvoice) async throws -> Data {
        let reference = try await database.canonicalPDFReference(invoiceID: invoice.id)
        let url = try recoveryURL(relativePath: reference.relativePath, directory: "Invoices")
        let canonicalRoot = filesRoot.appendingPathComponent("Invoices", isDirectory: true).standardizedFileURL
        let rootValues = try canonicalRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let fileValues = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              fileValues.isRegularFile == true,
              fileValues.isSymbolicLink != true,
              url.resolvingSymlinksInPath().deletingLastPathComponent() == canonicalRoot.resolvingSymlinksInPath() else {
            throw InvoiceError.corruptData("unsafe_canonical_pdf_file")
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actualHash == reference.sha256 else {
            throw InvoiceError.corruptData("canonical_pdf_hash_mismatch")
        }
        return data
    }

    private func matchesHash(url: URL, expected: String) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actual == expected
    }

    private func recoveryURL(relativePath: String, directory: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              components.first == Substring(directory),
              components.last?.isEmpty == false,
              relativePath.lowercased().hasSuffix(".pdf") else {
            throw InvoiceError.corruptData("unsafe_recovery_path")
        }
        let root = filesRoot.appendingPathComponent(directory, isDirectory: true).standardizedFileURL
        let url = filesRoot.appendingPathComponent(relativePath).standardizedFileURL
        guard url.deletingLastPathComponent() == root else {
            throw InvoiceError.corruptData("unsafe_recovery_path")
        }
        return url
    }

    private static func equivalentForIssue(_ lhs: IssuedInvoice, _ rhs: IssuedInvoice) -> Bool {
        guard lhs.id == rhs.id,
              lhs.number == rhs.number,
              lhs.issueDate == rhs.issueDate,
              lhs.dueDate == rhs.dueDate,
              lhs.coveredStart == rhs.coveredStart,
              lhs.coveredEnd == rhs.coveredEnd,
              lhs.issuer == rhs.issuer,
              lhs.customerID == rhs.customerID,
              lhs.customerName == rhs.customerName,
              lhs.customerAddress == rhs.customerAddress,
              lhs.taxTotals == rhs.taxTotals,
              lhs.subtotal == rhs.subtotal,
              lhs.totalTax == rhs.totalTax,
              lhs.grandTotal == rhs.grandTotal,
              lhs.lineRounding == rhs.lineRounding,
              lhs.taxRounding == rhs.taxRounding,
              lhs.status == .issued,
              lhs.paidDate == nil,
              lhs.replacesInvoiceID == nil,
              lhs.replacesInvoiceNumber == nil,
              lhs.replacedByInvoiceID == nil,
              lhs.pdfRelativePath == nil,
              lhs.pdfSHA256 == nil,
              lhs.issuedAt == rhs.issuedAt,
              lhs.lines.count == rhs.lines.count else { return false }
        return zip(lhs.lines, rhs.lines).allSatisfy { left, right in
            left.sourceVisitID == right.sourceVisitID &&
            left.workDate == right.workDate &&
            left.siteName == right.siteName &&
            left.siteAddress == right.siteAddress &&
            left.position == right.position &&
            left.description == right.description &&
            left.quantity == right.quantity &&
            left.unit == right.unit &&
            left.unitPrice == right.unitPrice &&
            left.taxRate == right.taxRate &&
            left.net == right.net
        }
    }

    private static func equivalentForCorrection(_ lhs: IssuedInvoice, _ rhs: IssuedInvoice) -> Bool {
        guard lhs.id == rhs.id,
              lhs.number == rhs.number,
              lhs.issueDate == rhs.issueDate,
              lhs.dueDate == rhs.dueDate,
              lhs.coveredStart == rhs.coveredStart,
              lhs.coveredEnd == rhs.coveredEnd,
              lhs.issuer == rhs.issuer,
              lhs.customerID == rhs.customerID,
              lhs.customerName == rhs.customerName,
              lhs.customerAddress == rhs.customerAddress,
              lhs.taxTotals == rhs.taxTotals,
              lhs.subtotal == rhs.subtotal,
              lhs.totalTax == rhs.totalTax,
              lhs.grandTotal == rhs.grandTotal,
              lhs.lineRounding == rhs.lineRounding,
              lhs.taxRounding == rhs.taxRounding,
              lhs.status == .issued,
              lhs.paidDate == nil,
              lhs.replacesInvoiceID == rhs.replacesInvoiceID,
              lhs.replacesInvoiceNumber == rhs.replacesInvoiceNumber,
              lhs.replacedByInvoiceID == nil,
              lhs.pdfRelativePath == nil,
              lhs.pdfSHA256 == nil,
              lhs.issuedAt == rhs.issuedAt,
              lhs.lines.count == rhs.lines.count else { return false }
        return zip(lhs.lines, rhs.lines).allSatisfy { left, right in
            left.sourceVisitID == right.sourceVisitID &&
            left.workDate == right.workDate &&
            left.siteName == right.siteName &&
            left.siteAddress == right.siteAddress &&
            left.position == right.position &&
            left.description == right.description &&
            left.quantity == right.quantity &&
            left.unit == right.unit &&
            left.unitPrice == right.unitPrice &&
            left.taxRate == right.taxRate &&
            left.net == right.net
        }
    }
}
