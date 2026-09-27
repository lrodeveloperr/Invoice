import Foundation

public enum InvoiceCalculator {
    public static func tax(for taxable: Money, rate: TaxRate, rounding: RoundingRule) throws -> Money {
        let product = taxable.yen.multipliedReportingOverflow(by: Int64(rate.basisPoints))
        guard !product.overflow else { throw InvoiceError.arithmeticOverflow }
        let value = try Quantity.roundedDivision(numerator: product.partialValue, denominator: 10_000, rule: rounding)
        return try Money(yen: value)
    }

    public static func totals(lines: [IssuedInvoiceLine], taxRounding: RoundingRule) throws -> (subtotal: Money, taxes: [InvoiceTaxTotal], totalTax: Money, grandTotal: Money) {
        guard !lines.isEmpty else { throw InvoiceError.emptyInvoice }
        var subtotals: [Int: (rate: TaxRate, taxable: Money)] = [:]
        var subtotal = Money.zero
        for line in lines {
            subtotal = try subtotal.adding(line.net)
            if var group = subtotals[line.taxRate.basisPoints] {
                group.taxable = try group.taxable.adding(line.net)
                if (line.taxRate.id, line.taxRate.label) < (group.rate.id, group.rate.label) {
                    group.rate = line.taxRate
                }
                subtotals[line.taxRate.basisPoints] = group
            } else {
                subtotals[line.taxRate.basisPoints] = (line.taxRate, line.net)
            }
        }

        var taxTotals: [InvoiceTaxTotal] = []
        var totalTax = Money.zero
        for (_, group) in subtotals.sorted(by: { $0.key > $1.key }) {
            let roundedTax = try tax(for: group.taxable, rate: group.rate, rounding: taxRounding)
            taxTotals.append(InvoiceTaxTotal(taxRate: group.rate, taxable: group.taxable, tax: roundedTax))
            totalTax = try totalTax.adding(roundedTax)
        }
        return (subtotal, taxTotals, totalTax, try subtotal.adding(totalTax))
    }

    public static func snapshot(
        id: UUID = UUID(),
        number: String,
        draft: InvoiceDraft,
        business: BusinessProfile,
        customer: Customer,
        sites: [UUID: Site],
        visits: [Visit],
        issuedAt: Date = Date()
    ) throws -> IssuedInvoice {
        guard !number.isEmpty else { throw InvoiceError.missingRequiredField("invoice.number") }
        guard !business.issuerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InvoiceError.missingRequiredField("business.issuerName")
        }
        guard business.registrationNumberIsValid else {
            throw InvoiceError.missingRequiredField("business.registrationNumber")
        }
        try customer.validate()
        guard customer.id == draft.customerID else { throw InvoiceError.mixedCustomers }
        guard draft.coveredStart <= draft.coveredEnd,
              draft.issueDate <= draft.dueDate else { throw InvoiceError.invalidDate }
        guard !visits.isEmpty else { throw InvoiceError.emptyInvoice }
        guard Set(visits.map(\.id)).count == visits.count else { throw InvoiceError.duplicateVisit }
        guard Set(draft.selectedVisitIDs).count == draft.selectedVisitIDs.count,
              Set(draft.selectedVisitIDs) == Set(visits.map(\.id)) else {
            throw InvoiceError.invalidTransition
        }

        var snapshotLines: [IssuedInvoiceLine] = []
        var position = 0
        let sortedVisits = visits.sorted { lhs, rhs in
            if lhs.workDate != rhs.workDate { return lhs.workDate < rhs.workDate }
            return lhs.siteID.uuidString < rhs.siteID.uuidString
        }
        for visit in sortedVisits {
            guard visit.customerID == customer.id else { throw InvoiceError.mixedCustomers }
            guard visit.state == .unbilled else { throw InvoiceError.visitNotUnbilled }
            guard visit.workDate >= draft.coveredStart,
                  visit.workDate <= draft.coveredEnd,
                  !visit.lines.isEmpty else { throw InvoiceError.invalidTransition }
            guard let site = sites[visit.siteID], site.customerID == customer.id else {
                throw InvoiceError.corruptData("site_customer_mismatch")
            }
            try site.validate()
            for line in visit.lines.sorted(by: { $0.position < $1.position }) {
                let issuedNet = try line.quantity.multiplied(
                    by: line.unitPrice,
                    rounding: business.lineRounding
                )
                snapshotLines.append(IssuedInvoiceLine(
                    id: UUID(), sourceVisitID: visit.id, workDate: visit.workDate,
                    siteName: site.name, siteAddress: site.address, position: position,
                    description: line.description, quantity: line.quantity, unit: line.unit,
                    unitPrice: line.unitPrice, taxRate: line.taxRate, net: issuedNet
                ))
                position += 1
            }
        }

        let totals = try totals(lines: snapshotLines, taxRounding: business.taxRounding)
        return IssuedInvoice(
            id: id, number: number, issueDate: draft.issueDate, dueDate: draft.dueDate,
            coveredStart: draft.coveredStart, coveredEnd: draft.coveredEnd,
            issuer: business, customerID: customer.id, customerName: customer.name,
            customerAddress: customer.billingAddress, lines: snapshotLines,
            taxTotals: totals.taxes, subtotal: totals.subtotal, totalTax: totals.totalTax,
            grandTotal: totals.grandTotal, lineRounding: business.lineRounding,
            taxRounding: business.taxRounding, status: .issued, paidDate: nil,
            replacesInvoiceID: nil, replacedByInvoiceID: nil,
            pdfRelativePath: nil, pdfSHA256: nil, issuedAt: issuedAt
        )
    }
}

public struct InvoiceNumberAllocator: Sendable {
    public init() {}

    public func number(issueDate: LocalDate, prefix: String, sequence: Int) throws -> String {
        guard sequence > 0, sequence <= 9_999 else { throw InvoiceError.invalidTransition }
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard trimmed.count <= 12,
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw InvoiceError.missingRequiredField("invoice.prefix")
        }
        let stem = String(format: "%04d-%04d", issueDate.year, sequence)
        return trimmed.isEmpty ? stem : "\(trimmed)-\(stem)"
    }
}
