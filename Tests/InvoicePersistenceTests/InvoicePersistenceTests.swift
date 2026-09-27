import Foundation
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
