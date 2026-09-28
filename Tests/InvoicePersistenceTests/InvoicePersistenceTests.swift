import CryptoKit
import Foundation
import GRDB
import XCTest
@testable import InvoiceBackup
@testable import InvoiceDomain
@testable import InvoicePDF
@testable import InvoicePersistence

final class InvoicePersistenceTests: XCTestCase {
    func testIssueIsAtomicAndConsumesOnlyFirstFreeIssue() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let service = IssueService(database: database, filesRoot: root) { invoice in
            Data("%PDF-fixture-\(invoice.number)".utf8)
        }

        let invoice = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: false
        )
        let invoices = try await database.invoices()
        XCTAssertEqual(invoices.map(\.id), [invoice.id])
        let visits = try await database.visits()
        let storedVisit = try XCTUnwrap(visits.first)
        XCTAssertEqual(storedVisit.state, .billed(invoiceID: invoice.id))
        let entitlement = try await database.entitlementUsage(hasPro: false)
        XCTAssertEqual(entitlement.firstCleanInvoiceID, invoice.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(try XCTUnwrap(invoice.pdfRelativePath)).path))
    }

    func testFreeCustomerLimitCountsOnlyActiveCustomers() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        try await database.saveCustomer(Customer(name: "一"))
        try await database.saveCustomer(Customer(name: "二"))
        await XCTAssertThrowsErrorAsync { try await database.saveCustomer(Customer(name: "三")) }
        try await database.saveCustomer(Customer(name: "保管", isActive: false))
        let count = try await database.activeCustomerCount()
        XCTAssertEqual(count, 2)
    }

    func testVoidReturnsOnlyItsCurrentlyBilledVisits() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let service = IssueService(database: database, filesRoot: root) { _ in Data("pdf".utf8) }
        let invoice = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: true
        )
        try await database.voidInvoice(id: invoice.id, returnVisitsToUnbilled: true)
        let storedInvoice = try await database.invoice(id: invoice.id)
        let storedVisits = try await database.visits()
        XCTAssertEqual(storedInvoice?.status, .voided)
        XCTAssertEqual(storedVisits.first?.state, .unbilled)
    }

    func testStaleVisitSaveCannotReopenBilledWork() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let service = IssueService(database: database, filesRoot: root) { _ in Data("pdf".utf8) }
        let invoice = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: true
        )

        await XCTAssertThrowsErrorAsync {
            try await database.saveVisit(fixture.visit)
        }
        let storedVisits = try await database.visits()
        let storedVisit = try XCTUnwrap(storedVisits.first)
        XCTAssertEqual(storedVisit.state, .billed(invoiceID: invoice.id))
        let storedInvoices = try await database.invoices()
        XCTAssertEqual(storedInvoices.count, 1)
    }

    func testBackupRejectsMissingOrChangedCanonicalPDF() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let service = IssueService(database: database, filesRoot: root) { _ in Data("canonical-pdf".utf8) }
        let invoice = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: true
        )
        let pdfURL = root.appendingPathComponent(try XCTUnwrap(invoice.pdfRelativePath))
        try Data("changed-pdf".utf8).write(to: pdfURL, options: .atomic)

        let package = root.appendingPathComponent("Invalid.invoicebackup", isDirectory: true)
        await XCTAssertThrowsErrorAsync {
            try await BackupService(database: database, filesRoot: root).export(to: package, appBuild: "tests")
        }
        try FileManager.default.removeItem(at: pdfURL)
        await XCTAssertThrowsErrorAsync {
            try await BackupService(database: database, filesRoot: root).export(to: package, appBuild: "tests")
        }
    }

    func testReplaceRestoreNeverDecrementsInvoiceSequence() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let service = IssueService(database: database, filesRoot: root) { invoice in
            Data("pdf-\(invoice.number)".utf8)
        }
        _ = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: true
        )
        let package = root.appendingPathComponent("Earlier.invoicebackup", isDirectory: true)
        let backup = BackupService(database: database, filesRoot: root)
        try await backup.export(to: package, appBuild: "tests")

        var secondVisit = fixture.visit
        secondVisit.id = UUID()
        secondVisit.workDate = try LocalDate(year: 2026, month: 9, day: 11)
        secondVisit.updatedAt = Date()
        try await database.saveVisit(secondVisit)
        let secondDraft = InvoiceDraft(
            customerID: fixture.customer.id,
            selectedVisitIDs: [secondVisit.id],
            coveredStart: try LocalDate(year: 2026, month: 9, day: 1),
            coveredEnd: try LocalDate(year: 2026, month: 9, day: 30),
            issueDate: try LocalDate(year: 2026, month: 9, day: 30),
            dueDate: try LocalDate(year: 2026, month: 10, day: 31)
        )
        _ = try await service.issue(
            draft: secondDraft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [secondVisit], hasPro: true
        )

        _ = try await backup.restore(packageURL: package, mode: .replace)
        let next = try await database.proposedNumber(
            issueDate: try LocalDate(year: 2026, month: 9, day: 30),
            prefix: ""
        )
        XCTAssertEqual(next, "2026-0003")
    }

    func testReplaceRestoreCopiesSourceBeforeReplacingInvoiceDirectory() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let service = IssueService(database: database, filesRoot: root) { _ in Data("canonical".utf8) }
        let invoice = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: true
        )
        let invoiceDirectory = root.appendingPathComponent("Invoices", isDirectory: true)
        let package = invoiceDirectory.appendingPathComponent("Import.invoicebackup", isDirectory: true)
        let backup = BackupService(database: database, filesRoot: root)
        try await backup.export(to: package, appBuild: "tests")

        _ = try await backup.restore(packageURL: package, mode: .replace)
        let restoredInvoice = try await database.invoice(id: invoice.id)
        let restored = try XCTUnwrap(restoredInvoice)
        let restoredPDF = root.appendingPathComponent(try XCTUnwrap(restored.pdfRelativePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredPDF.path))
        try await database.integrityCheck()
    }

    func testRecoveryDoesNotReactivateVoidedInvoiceBesideReplacement() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let failingService = IssueService(database: database, filesRoot: root) { invoice in
            let final = root
                .appendingPathComponent("Invoices", isDirectory: true)
                .appendingPathComponent(invoice.id.uuidString.lowercased() + ".pdf")
            try FileManager.default.createDirectory(
                at: final.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("conflict".utf8).write(to: final)
            return Data("invoice-a".utf8)
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await failingService.issue(
                draft: fixture.draft, business: fixture.business, customer: fixture.customer,
                sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: true
            )
        }
        let invoicesAfterFailure = try await database.invoices()
        let invoiceA = try XCTUnwrap(invoicesAfterFailure.first)
        try await database.voidInvoice(id: invoiceA.id, returnVisitsToUnbilled: true)

        let visitsAfterVoid = try await database.visits()
        let replacementVisit = try XCTUnwrap(visitsAfterVoid.first)
        let replacementService = IssueService(database: database, filesRoot: root) { _ in Data("invoice-b".utf8) }
        let invoiceB = try await replacementService.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [replacementVisit], hasPro: true
        )
        let pendingOperations = try await database.pendingFileOperations()
        let operation = try XCTUnwrap(pendingOperations.first)
        let staged = root.appendingPathComponent(operation.stagedPath)
        if FileManager.default.fileExists(atPath: staged.path) {
            try FileManager.default.removeItem(at: staged)
        }
        try await failingService.recoverPendingFileOperations()

        let storedInvoiceA = try await database.invoice(id: invoiceA.id)
        let storedInvoiceB = try await database.invoice(id: invoiceB.id)
        XCTAssertEqual(storedInvoiceA?.status, .voided)
        XCTAssertEqual(storedInvoiceB?.status, .issued)
        try await database.integrityCheck()
    }

    func testBackupValidationRejectsDuplicateActiveVisitLinks() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let service = IssueService(database: database, filesRoot: root) { invoice in
            Data("pdf-\(invoice.number)".utf8)
        }
        let invoiceA = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: true
        )
        try await database.voidInvoice(id: invoiceA.id, returnVisitsToUnbilled: true)
        let visitsAfterVoid = try await database.visits()
        let visit = try XCTUnwrap(visitsAfterVoid.first)
        _ = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [visit], hasPro: true
        )
        let package = root.appendingPathComponent("Hostile.invoicebackup", isDirectory: true)
        let backup = BackupService(database: database, filesRoot: root)
        try await backup.export(to: package, appBuild: "tests")

        let databaseURL = package.appendingPathComponent("data.sqlite")
        let hostile = try DatabaseQueue(path: databaseURL.path)
        try await hostile.write { db in
            try db.execute(sql: "DROP TRIGGER prevent_duplicate_active_invoice_reactivation")
            try db.execute(
                sql: "UPDATE issued_invoice SET status = 'issued' WHERE id = ?",
                arguments: [invoiceA.id.uuidString.lowercased()]
            )
        }
        try hostile.close()
        try refreshDatabaseManifestHash(package: package)

        await XCTAssertThrowsErrorAsync {
            _ = try await backup.validate(packageURL: package)
        }
    }

    func testBackupValidationRejectsUnsafeRecoveryJournalPaths() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let service = IssueService(database: database, filesRoot: root) { _ in Data("pdf".utf8) }
        let invoice = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: true
        )
        let package = root.appendingPathComponent("UnsafeJournal.invoicebackup", isDirectory: true)
        let backup = BackupService(database: database, filesRoot: root)
        try await backup.export(to: package, appBuild: "tests")

        let hostile = try DatabaseQueue(path: package.appendingPathComponent("data.sqlite").path)
        let pdfRelativePath = try XCTUnwrap(invoice.pdfRelativePath)
        let pdfHash = try XCTUnwrap(invoice.pdfSHA256)
        try await hostile.write { db in
            try db.execute(sql: """
                INSERT INTO file_operation_journal(
                    id, invoice_id, staged_path, final_path, sha256, state, created_at
                ) VALUES (?, ?, ?, ?, ?, 'pending', ?)
                """, arguments: [
                    UUID().uuidString.lowercased(),
                    invoice.id.uuidString.lowercased(),
                    pdfRelativePath,
                    "../escaped.pdf",
                    pdfHash,
                    Date().timeIntervalSince1970
                ])
        }
        try hostile.close()
        try refreshDatabaseManifestHash(package: package)

        await XCTAssertThrowsErrorAsync {
            _ = try await backup.validate(packageURL: package)
        }
    }

    func testExactRollbackRestoresSequenceWithoutForwardRestorePolicy() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let service = IssueService(database: database, filesRoot: root) { invoice in
            Data("pdf-\(invoice.number)".utf8)
        }
        _ = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: true
        )
        let rollbackDatabase = root.appendingPathComponent("rollback.sqlite")
        try await database.exportDatabase(to: rollbackDatabase.path)

        var secondVisit = fixture.visit
        secondVisit.id = UUID()
        secondVisit.workDate = try LocalDate(year: 2026, month: 9, day: 12)
        try await database.saveVisit(secondVisit)
        let secondDraft = InvoiceDraft(
            customerID: fixture.customer.id,
            selectedVisitIDs: [secondVisit.id],
            coveredStart: try LocalDate(year: 2026, month: 9, day: 1),
            coveredEnd: try LocalDate(year: 2026, month: 9, day: 30),
            issueDate: try LocalDate(year: 2026, month: 9, day: 30),
            dueDate: try LocalDate(year: 2026, month: 10, day: 31)
        )
        _ = try await service.issue(
            draft: secondDraft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [secondVisit], hasPro: true
        )
        try await database.replaceContentsExactly(from: rollbackDatabase.path)
        let next = try await database.proposedNumber(
            issueDate: try LocalDate(year: 2026, month: 9, day: 30),
            prefix: ""
        )
        XCTAssertEqual(next, "2026-0002")
    }

    func testBackupReplaceAndMergePreflight() async throws {
        let sourceRoot = try temporaryDirectory()
        let targetRoot = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let sourceDatabase = try AppDatabase(path: sourceRoot.appendingPathComponent("data.sqlite").path)
        _ = try await seed(database: sourceDatabase)
        let package = sourceRoot.appendingPathComponent("Export.invoicebackup", isDirectory: true)
        try await BackupService(database: sourceDatabase, filesRoot: sourceRoot).export(to: package, appBuild: "tests")
        let packageEntries = try FileManager.default.contentsOfDirectory(atPath: package.path)
        XCTAssertEqual(Set(packageEntries), Set(["data.sqlite", "manifest.json", "pdfs"]))

        let targetDatabase = try AppDatabase(path: targetRoot.appendingPathComponent("data.sqlite").path)
        let backup = BackupService(database: targetDatabase, filesRoot: targetRoot)
        let preflight = try await backup.preflightRestore(packageURL: package, mode: .replace)
        XCTAssertEqual(preflight.mode, .replace)
        _ = try await backup.restore(packageURL: package, mode: .replace)
        let restoredCustomers = try await targetDatabase.customers()
        XCTAssertEqual(restoredCustomers.count, 1)

        let merge = try await backup.preflightRestore(packageURL: package, mode: .merge)
        XCTAssertTrue(try XCTUnwrap(merge.databaseMerge).canCommit)
        XCTAssertEqual(try XCTUnwrap(merge.databaseMerge).counts.customers, 0)
    }

    func testPDFLayoutKeepsMinimumBodyFontContract() throws {
        let fixture = try Fixture.make()
        let invoice = try InvoiceCalculator.snapshot(
            number: "2026-0001", draft: fixture.draft, business: fixture.business,
            customer: fixture.customer, sites: [fixture.site.id: fixture.site], visits: [fixture.visit]
        )
        let plan = try PDFLayoutPlanner.plan(invoice: invoice)
        XCTAssertFalse(plan.pages.isEmpty)
        XCTAssertTrue(plan.pages.flatMap(\.blocks).contains { $0.text.contains("2026-09-10") })
    }

    func testPDFLayoutPaginatesLongJapaneseDescriptionWithinPageBounds() throws {
        let fixture = try Fixture.make()
        var visit = fixture.visit
        visit.lines[0].description = String(repeating: "長い作業説明", count: 500)
        let invoice = try InvoiceCalculator.snapshot(
            number: "2026-0001", draft: fixture.draft, business: fixture.business,
            customer: fixture.customer, sites: [fixture.site.id: fixture.site], visits: [visit]
        )
        let plan = try PDFLayoutPlanner.plan(invoice: invoice)
        XCTAssertGreaterThan(plan.pages.count, 1)
        for block in plan.pages.flatMap(\.blocks) where block.style != .caption {
            XCTAssertLessThanOrEqual(
                block.frame.y + block.frame.height,
                PDFLayoutPlan.pageHeight - PDFLayoutPlan.margin - 24
            )
        }
        for block in plan.pages.flatMap(\.blocks) {
            XCTAssertLessThanOrEqual(
                block.frame.y + block.frame.height,
                PDFLayoutPlan.pageHeight - PDFLayoutPlan.margin
            )
        }
    }

    func testDraftQueriesReturnNewestAndExactDraft() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        try await database.saveDraft(fixture.draft)

        let drafts = try await database.drafts()
        XCTAssertEqual(drafts.map(\.id), [fixture.draft.id])
        let exactDraft = try await database.draft(id: fixture.draft.id)
        let missingDraft = try await database.draft(id: UUID())
        XCTAssertEqual(exactDraft, fixture.draft)
        XCTAssertNil(missingDraft)
    }

    func testCanonicalPDFReadVerifiesStoredHash() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let expected = Data("canonical-pdf".utf8)
        let service = IssueService(database: database, filesRoot: root) { _ in expected }
        let invoice = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: true
        )
        let canonicalData = try await service.canonicalPDFData(for: invoice)
        XCTAssertEqual(canonicalData, expected)

        let path = try XCTUnwrap(invoice.pdfRelativePath)
        try Data("tampered".utf8).write(to: root.appendingPathComponent(path), options: .atomic)
        await XCTAssertThrowsErrorAsync {
            _ = try await service.canonicalPDFData(for: invoice)
        }
    }

    func testDeleteAllDomainDataClearsBusinessRecordsAndEntitlement() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try await seed(database: database)
        let service = IssueService(database: database, filesRoot: root) { _ in Data("pdf".utf8) }
        _ = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: [fixture.visit], hasPro: false
        )

        try await database.deleteAllDomainData()
        let business = try await database.business()
        let customers = try await database.customers()
        let visits = try await database.visits()
        let invoices = try await database.invoices()
        let entitlement = try await database.entitlementUsage(hasPro: false)
        XCTAssertNil(business)
        XCTAssertTrue(customers.isEmpty)
        XCTAssertTrue(visits.isEmpty)
        XCTAssertTrue(invoices.isEmpty)
        XCTAssertNil(entitlement.firstCleanInvoiceID)
        try await database.integrityCheck()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("invoice-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func seed(database: AppDatabase) async throws -> Fixture {
        let fixture = try Fixture.make()
        try await database.saveBusiness(fixture.business)
        try await database.saveCustomer(fixture.customer)
        try await database.saveSite(fixture.site)
        try await database.saveVisit(fixture.visit)
        return fixture
    }

    private func refreshDatabaseManifestHash(package: URL) throws {
        let manifestURL = package.appendingPathComponent("manifest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(BackupManifest.self, from: Data(contentsOf: manifestURL))
        let databaseData = try Data(contentsOf: package.appendingPathComponent("data.sqlite"))
        let databaseRecord = BackupFile(
            relativePath: "data.sqlite",
            byteCount: databaseData.count,
            sha256: SHA256.hash(data: databaseData).map { String(format: "%02x", $0) }.joined()
        )
        let updated = BackupManifest(
            schemaVersion: manifest.schemaVersion,
            appBuild: manifest.appBuild,
            createdAt: manifest.createdAt,
            files: manifest.files.map { $0.relativePath == "data.sqlite" ? databaseRecord : $0 }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(updated).write(to: manifestURL, options: .atomic)
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync(
        _ expression: @escaping () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected an error", file: file, line: line)
        } catch {}
    }
}

private struct Fixture {
    let business: BusinessProfile
    let customer: Customer
    let site: Site
    let visit: Visit
    let draft: InvoiceDraft

    static func make() throws -> Fixture {
        let business = BusinessProfile(issuerName: "青空メンテナンス", registrationNumber: "T1234567890123")
        let customer = Customer(name: "山田商事")
        let site = Site(customerID: customer.id, name: "本店")
        let line = try VisitLine(
            position: 0, description: "定期清掃", quantity: Quantity(decimalString: "1"), unit: "回",
            unitPrice: Money(yen: 10_000), taxRate: .standard10, lineRounding: .halfUp
        )
        var visit = Visit(
            customerID: customer.id, siteID: site.id,
            workDate: try LocalDate(year: 2026, month: 9, day: 10), lines: [line]
        )
        try visit.complete()
        let draft = InvoiceDraft(
            customerID: customer.id, selectedVisitIDs: [visit.id],
            coveredStart: try LocalDate(year: 2026, month: 9, day: 1),
            coveredEnd: try LocalDate(year: 2026, month: 9, day: 30),
            issueDate: try LocalDate(year: 2026, month: 9, day: 30),
            dueDate: try LocalDate(year: 2026, month: 10, day: 31)
        )
        return Fixture(business: business, customer: customer, site: site, visit: visit, draft: draft)
    }
}
