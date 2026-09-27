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
        let entitlement = try await database.entitlementUsage(hasPro: hasPro)
        guard entitlement.permitsCleanIssue else { throw InvoiceError.entitlementRequired }
        let number = try await database.proposedNumber(issueDate: draft.issueDate, prefix: business.invoicePrefix)
        var invoice = try InvoiceCalculator.snapshot(number: number, draft: draft, business: business, customer: customer, sites: sites, visits: visits)
        let pdfData = try await renderer(invoice)
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
        invoice.pdfRelativePath = finalRelative
        invoice.pdfSHA256 = hash
        return invoice
    }

    public func recoverPendingFileOperations() async throws {
        let operations = try await database.pendingFileOperations()
        for operation in operations {
            let stagedURL = filesRoot.appendingPathComponent(operation.stagedPath)
            let finalURL = filesRoot.appendingPathComponent(operation.finalPath)
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

    private func matchesHash(url: URL, expected: String) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actual == expected
    }
}
