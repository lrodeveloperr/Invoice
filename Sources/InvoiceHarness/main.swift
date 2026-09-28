import Foundation
import InvoiceBackup
import InvoiceDomain
import InvoicePDF
import InvoicePersistence

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct InvoiceHarness {
    static func main() async {
        do {
            let configuration = try Configuration(arguments: Array(CommandLine.arguments.dropFirst()))
            switch configuration.command {
            case "demo": try await runDemo(root: configuration.root)
            case "inspect": try await inspect(root: configuration.root)
            case "property": try runPropertyCheck()
            case "reset": try reset(root: configuration.root); print("RESET_OK \(configuration.root.path)")
            default: printHelp()
            }
        } catch {
            fputs("HARNESS_ERROR \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runDemo(root: URL) async throws {
        try reset(root: root)
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        let fixture = try makeFixture()
        try await database.saveBusiness(fixture.business)
        try await database.saveCustomer(fixture.customer)
        try await database.saveSite(fixture.site)
        for visit in fixture.visits { try await database.saveVisit(visit) }
        try await database.saveDraft(fixture.draft)

        let number = try await database.proposedNumber(issueDate: fixture.draft.issueDate, prefix: fixture.business.invoicePrefix)
        let preview = try InvoiceCalculator.snapshot(
            number: number, draft: fixture.draft, business: fixture.business,
            customer: fixture.customer, sites: [fixture.site.id: fixture.site], visits: fixture.visits
        )
        let plan = try PDFLayoutPlanner.plan(invoice: preview)
        print("PREVIEW_OK number=\(number) visits=\(fixture.visits.count) subtotal=\(preview.subtotal.yen) tax=\(preview.totalTax.yen) total=\(preview.grandTotal.yen) pages=\(plan.pages.count)")

        let service = IssueService(database: database, filesRoot: root) { invoice in
            Data("%PDF-HARNESS\n\(invoice.number)\n\(invoice.grandTotal.yen)\n".utf8)
        }
        let issued = try await service.issue(
            draft: fixture.draft, business: fixture.business, customer: fixture.customer,
            sites: [fixture.site.id: fixture.site], visits: fixture.visits, hasPro: false
        )
        print("ISSUE_OK id=\(issued.id.uuidString.lowercased()) status=\(issued.status.rawValue) path=\(issued.pdfRelativePath ?? "missing")")

        let backupURL = root.appendingPathComponent("Demo.invoicebackup", isDirectory: true)
        try await BackupService(database: database, filesRoot: root).export(to: backupURL, appBuild: "harness")
        print("BACKUP_OK \(backupURL.path)")
        try await database.integrityCheck()
        print("INVARIANTS_OK")
    }

    private static func inspect(root: URL) async throws {
        let database = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
        try await database.integrityCheck()
        let customers = try await database.customers()
        let visits = try await database.visits()
        let invoices = try await database.invoices()
        let entitlement = try await database.entitlementUsage(hasPro: false)
        print("STATE customers=\(customers.count) visits=\(visits.count) invoices=\(invoices.count) free_used=\(entitlement.firstCleanInvoiceID != nil)")
        for invoice in invoices {
            print("INVOICE \(invoice.number) \(invoice.status.rawValue) ¥\(invoice.grandTotal.yen)")
        }
    }

    private static func runPropertyCheck() throws {
        var state: UInt64 = 0xD471_5EED
        for _ in 0..<10_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let money = try Money(yen: Int64((state >> 12) % 10_000_000))
            for rate in TaxRate.launchCatalog {
                let floorTax = try InvoiceCalculator.tax(for: money, rate: rate, rounding: .floor)
                let halfTax = try InvoiceCalculator.tax(for: money, rate: rate, rounding: .halfUp)
                let ceilingTax = try InvoiceCalculator.tax(for: money, rate: rate, rounding: .ceiling)
                guard floorTax <= halfTax, halfTax <= ceilingTax,
                      ceilingTax.yen - floorTax.yen <= 1 else {
                    throw InvoiceError.corruptData("property_tax_order")
                }
            }
        }
        print("PROPERTY_OK seed=0xD4715EED sequences=10000")
    }

    private static func reset(root: URL) throws {
        let standardized = root.standardizedFileURL
        guard standardized.path != "/", standardized.path.count > 8 else {
            throw InvoiceError.corruptData("unsafe_reset_path")
        }
        if FileManager.default.fileExists(atPath: standardized.path) {
            try FileManager.default.removeItem(at: standardized)
        }
        try FileManager.default.createDirectory(at: standardized, withIntermediateDirectories: true)
    }

    private static func makeFixture() throws -> DemoFixture {
        let business = BusinessProfile(
            issuerName: "青空メンテナンス", postalAddress: "東京都千代田区1-2-3",
            registrationNumber: "T1234567890123", bankDetails: "青空銀行 本店 普通 1234567",
            invoicePrefix: "AOZORA"
        )
        let customer = Customer(name: "山田商事株式会社", billingAddress: "東京都新宿区4-5-6", closingDay: 31)
        let site = Site(customerID: customer.id, name: "新宿本店", address: "東京都新宿区4-5-6")
        let dates = [10, 17, 24]
        let visits = try dates.enumerated().map { index, day -> Visit in
            let line = try VisitLine(
                position: 0, description: "定期清掃", quantity: Quantity(decimalString: "1"), unit: "回",
                unitPrice: Money(yen: 12_000), taxRate: .standard10, lineRounding: .halfUp
            )
            var visit = Visit(
                customerID: customer.id, siteID: site.id,
                workDate: try LocalDate(year: 2026, month: 9, day: day), note: "訪問\(index + 1)", lines: [line]
            )
            try visit.complete()
            return visit
        }
        let draft = InvoiceDraft(
            customerID: customer.id, selectedVisitIDs: visits.map(\.id),
            coveredStart: try LocalDate(year: 2026, month: 9, day: 1),
            coveredEnd: try LocalDate(year: 2026, month: 9, day: 30),
            issueDate: try LocalDate(year: 2026, month: 9, day: 30),
            dueDate: try LocalDate(year: 2026, month: 10, day: 31)
        )
        return DemoFixture(business: business, customer: customer, site: site, visits: visits, draft: draft)
    }

    private static func printHelp() {
        print("""
        invoice-harness demo [--root PATH]      Reset, load Japanese fixtures, preview, issue and back up.
        invoice-harness inspect [--root PATH]   Show authoritative stored state and integrity.
        invoice-harness property                Run 10,000 deterministic tax invariant sequences.
        invoice-harness reset [--root PATH]     Remove only the selected harness directory.
        """)
    }
}

private struct DemoFixture {
    let business: BusinessProfile
    let customer: Customer
    let site: Site
    let visits: [Visit]
    let draft: InvoiceDraft
}

private struct Configuration {
    let command: String
    let root: URL

    init(arguments: [String]) throws {
        command = arguments.first ?? "help"
        if let index = arguments.firstIndex(of: "--root") {
            guard arguments.indices.contains(index + 1) else {
                throw InvoiceError.missingRequiredField("root")
            }
            root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".invoice-harness", isDirectory: true)
        }
    }
}
