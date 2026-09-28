import Foundation
import XCTest
@testable import InvoiceDomain

final class InvoiceDomainTests: XCTestCase {
    func testQuantityParsingAndRounding() throws {
        XCTAssertEqual(try Quantity(decimalString: "1.250").description, "1.250")
        XCTAssertEqual(try Quantity(decimalString: "0.5").multiplied(by: Money(yen: 101), rounding: .floor).yen, 50)
        XCTAssertEqual(try Quantity(decimalString: "0.5").multiplied(by: Money(yen: 101), rounding: .halfUp).yen, 51)
        XCTAssertEqual(try Quantity(decimalString: "0.5").multiplied(by: Money(yen: 101), rounding: .ceiling).yen, 51)
        XCTAssertThrowsError(try Quantity(decimalString: "0"))
        XCTAssertThrowsError(try Quantity(decimalString: "1.0001"))
    }

    func testTaxRoundsOncePerRateGroup() throws {
        let lines = try [
            line(position: 0, price: 101, rate: .standard10),
            line(position: 1, price: 104, rate: .standard10),
            line(position: 2, price: 101, rate: .reduced8)
        ].map { input in
            IssuedInvoiceLine(
                id: UUID(), sourceVisitID: UUID(), workDate: try LocalDate(year: 2026, month: 9, day: 1),
                siteName: "現場", siteAddress: "", position: input.position,
                description: "作業", quantity: try Quantity(decimalString: "1"), unit: "回",
                unitPrice: try Money(yen: input.price), taxRate: input.rate, net: try Money(yen: input.price)
            )
        }
        let totals = try InvoiceCalculator.totals(lines: lines, taxRounding: .floor)
        XCTAssertEqual(totals.subtotal.yen, 306)
        XCTAssertEqual(totals.totalTax.yen, 28)
        XCTAssertEqual(totals.grandTotal.yen, 334)
    }

    func testTaxGroupsEqualPercentagesDespiteDifferentRateMetadata() throws {
        let firstRate = try TaxRate(id: "jp-10-old", basisPoints: 1_000, label: "10%")
        let secondRate = try TaxRate(id: "jp-10-new", basisPoints: 1_000, label: "標準10%")
        let date = try LocalDate(year: 2026, month: 9, day: 1)
        let lines = try [firstRate, secondRate].enumerated().map { index, rate in
            IssuedInvoiceLine(
                id: UUID(), sourceVisitID: UUID(), workDate: date,
                siteName: "現場", siteAddress: "", position: index,
                description: "作業", quantity: try Quantity(decimalString: "1"), unit: "回",
                unitPrice: try Money(yen: 5), taxRate: rate, net: try Money(yen: 5)
            )
        }
        let totals = try InvoiceCalculator.totals(lines: lines, taxRounding: .floor)
        XCTAssertEqual(totals.taxes.count, 1)
        XCTAssertEqual(totals.taxes[0].taxable.yen, 10)
        XCTAssertEqual(totals.totalTax.yen, 1)
    }

    func testSnapshotRejectsSelectionMismatchAndOutOfRangeVisit() throws {
        let fixture = try Fixture.make()
        var mismatched = fixture.draft
        mismatched.selectedVisitIDs = []
        XCTAssertThrowsError(try InvoiceCalculator.snapshot(
            number: "2026-0001", draft: mismatched, business: fixture.business,
            customer: fixture.customer, sites: [fixture.site.id: fixture.site], visits: [fixture.visit]
        ))

        var outOfRange = fixture.visit
        outOfRange.workDate = try LocalDate(year: 2026, month: 8, day: 31)
        XCTAssertThrowsError(try InvoiceCalculator.snapshot(
            number: "2026-0001", draft: fixture.draft, business: fixture.business,
            customer: fixture.customer, sites: [fixture.site.id: fixture.site], visits: [outOfRange]
        ))
    }

    func testSnapshotRecalculatesLineUsingDeclaredIssueRoundingPolicy() throws {
        let fixture = try Fixture.make()
        var visit = fixture.visit
        visit.lines = [try VisitLine(
            position: 0,
            description: "端数のある作業",
            quantity: Quantity(decimalString: "0.5"),
            unit: "回",
            unitPrice: Money(yen: 101),
            taxRate: .standard10,
            lineRounding: .floor
        )]
        XCTAssertEqual(visit.lines[0].net.yen, 50)

        var business = fixture.business
        business.lineRounding = .halfUp
        let invoice = try InvoiceCalculator.snapshot(
            number: "2026-0001", draft: fixture.draft, business: business,
            customer: fixture.customer, sites: [fixture.site.id: fixture.site], visits: [visit]
        )
        XCTAssertEqual(invoice.lineRounding, .halfUp)
        XCTAssertEqual(invoice.lines[0].net.yen, 51)
    }

    func testEntitlementBoundary() {
        let free = EntitlementState()
        XCTAssertTrue(free.permits(activeCustomerCount: 0))
        XCTAssertTrue(free.permits(activeCustomerCount: 1))
        XCTAssertFalse(free.permits(activeCustomerCount: 2))
        XCTAssertTrue(free.permitsCleanIssue)
        XCTAssertFalse(EntitlementState(firstCleanInvoiceID: UUID()).permitsCleanIssue)
        XCTAssertTrue(EntitlementState(hasPro: true, firstCleanInvoiceID: UUID()).permits(activeCustomerCount: 999))
    }

    func testCorrectionRejectsWorkContextThatDoesNotMatchSourceVisit() throws {
        let fixture = try Fixture.make()
        var original = try InvoiceCalculator.snapshot(
            number: "2026-0001",
            draft: fixture.draft,
            business: fixture.business,
            customer: fixture.customer,
            sites: [fixture.site.id: fixture.site],
            visits: [fixture.visit]
        )
        original.pdfRelativePath = "Invoices/\(original.id.uuidString.lowercased()).pdf"
        original.pdfSHA256 = String(repeating: "a", count: 64)
        var lines = original.lines.map(InvoiceCorrectionLine.init(invoiceLine:))
        lines[0].workDate = try LocalDate(year: 2026, month: 9, day: 11)

        XCTAssertThrowsError(try InvoiceCalculator.correctionSnapshot(
            number: "2026-0002",
            original: original,
            issueDate: original.issueDate,
            dueDate: original.dueDate,
            lines: lines
        ))
    }

    func testTenThousandGeneratedTaxInvariants() throws {
        var state: UInt64 = 0xD471_5EED
        for _ in 0..<10_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let yen = Int64((state >> 16) % 1_000_000)
            let money = try Money(yen: yen)
            for rate in TaxRate.launchCatalog {
                let floorTax = try InvoiceCalculator.tax(for: money, rate: rate, rounding: .floor)
                let halfTax = try InvoiceCalculator.tax(for: money, rate: rate, rounding: .halfUp)
                let ceilingTax = try InvoiceCalculator.tax(for: money, rate: rate, rounding: .ceiling)
                XCTAssertLessThanOrEqual(floorTax.yen, halfTax.yen)
                XCTAssertLessThanOrEqual(halfTax.yen, ceilingTax.yen)
                XCTAssertLessThanOrEqual(ceilingTax.yen - floorTax.yen, 1)
            }
        }
    }

    private func line(position: Int, price: Int64, rate: TaxRate) throws -> (position: Int, price: Int64, rate: TaxRate) {
        _ = try Money(yen: price)
        return (position, price, rate)
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
