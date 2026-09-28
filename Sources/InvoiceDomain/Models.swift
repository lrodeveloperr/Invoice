import Foundation

public struct LocalDate: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else {
            throw InvoiceError.invalidDate
        }
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

public enum PDFStyle: String, CaseIterable, Codable, Sendable {
    case classic
    case modern
    case compact
}

public struct BusinessProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var issuerName: String
    public var postalAddress: String
    public var registrationNumber: String?
    public var bankDetails: String
    public var invoicePrefix: String
    public var lineRounding: RoundingRule
    public var taxRounding: RoundingRule
    public var pdfStyle: PDFStyle?
    public var logoPNGData: Data?

    public init(
        id: UUID = UUID(), issuerName: String, postalAddress: String = "",
        registrationNumber: String? = nil, bankDetails: String = "",
        invoicePrefix: String = "", lineRounding: RoundingRule = .halfUp,
        taxRounding: RoundingRule = .floor,
        pdfStyle: PDFStyle? = nil,
        logoPNGData: Data? = nil
    ) {
        self.id = id
        self.issuerName = issuerName
        self.postalAddress = postalAddress
        self.registrationNumber = registrationNumber
        self.bankDetails = bankDetails
        self.invoicePrefix = invoicePrefix
        self.lineRounding = lineRounding
        self.taxRounding = taxRounding
        self.pdfStyle = pdfStyle
        self.logoPNGData = logoPNGData
    }

    public var registrationNumberIsValid: Bool {
        guard let registrationNumber, registrationNumber.count == 14,
              registrationNumber.first == "T" else { return registrationNumber == nil }
        return registrationNumber.dropFirst().allSatisfy(\.isNumber)
    }

    public var effectivePDFStyle: PDFStyle { pdfStyle ?? .classic }
}

public struct ServiceTemplate: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var unit: String
    public var unitPrice: Money
    public var taxRate: TaxRate
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        unit: String,
        unitPrice: Money,
        taxRate: TaxRate,
        isActive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.unit = unit
        self.unitPrice = unitPrice
        self.taxRate = taxRate
        self.isActive = isActive
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InvoiceError.missingRequiredField("template.title")
        }
    }
}

public struct Customer: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var billingAddress: String
    public var closingDay: Int?
    public var paymentTermDays: Int
    public var isActive: Bool

    public init(id: UUID = UUID(), name: String, billingAddress: String = "", closingDay: Int? = nil, paymentTermDays: Int = 30, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.billingAddress = billingAddress
        self.closingDay = closingDay
        self.paymentTermDays = paymentTermDays
        self.isActive = isActive
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InvoiceError.missingRequiredField("customer.name")
        }
        if let closingDay, !(1...31).contains(closingDay) {
            throw InvoiceError.invalidDate
        }
        guard (0...365).contains(paymentTermDays) else { throw InvoiceError.invalidDate }
    }
}

public struct Site: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var customerID: UUID
    public var name: String
    public var address: String
    public var isActive: Bool

    public init(id: UUID = UUID(), customerID: UUID, name: String, address: String = "", isActive: Bool = true) {
        self.id = id
        self.customerID = customerID
        self.name = name
        self.address = address
        self.isActive = isActive
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InvoiceError.missingRequiredField("site.name")
        }
    }
}

public struct VisitLine: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var position: Int
    public var description: String
    public var quantity: Quantity
    public var unit: String
    public var unitPrice: Money
    public var taxRate: TaxRate
    public var net: Money

    public init(id: UUID = UUID(), position: Int, description: String, quantity: Quantity, unit: String, unitPrice: Money, taxRate: TaxRate, lineRounding: RoundingRule) throws {
        guard position >= 0,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InvoiceError.missingRequiredField("line.description")
        }
        self.id = id
        self.position = position
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.taxRate = taxRate
        self.net = try quantity.multiplied(by: unitPrice, rounding: lineRounding)
    }
}

public enum VisitState: Hashable, Codable, Sendable {
    case draft
    case unbilled
    case billed(invoiceID: UUID)
}

public struct Visit: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var customerID: UUID
    public var siteID: UUID
    public var workDate: LocalDate
    public var note: String
    public var lines: [VisitLine]
    public var state: VisitState
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), customerID: UUID, siteID: UUID, workDate: LocalDate, note: String = "", lines: [VisitLine] = [], state: VisitState = .draft, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.customerID = customerID
        self.siteID = siteID
        self.workDate = workDate
        self.note = note
        self.lines = lines.sorted { $0.position < $1.position }
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func complete() throws {
        guard state == .draft, !lines.isEmpty,
              Set(lines.map(\.position)).count == lines.count else {
            throw InvoiceError.invalidTransition
        }
        state = .unbilled
        updatedAt = Date()
    }
}

public struct InvoiceDraft: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var customerID: UUID
    public var selectedVisitIDs: [UUID]
    public var coveredStart: LocalDate
    public var coveredEnd: LocalDate
    public var issueDate: LocalDate
    public var dueDate: LocalDate
    public var updatedAt: Date

    public init(id: UUID = UUID(), customerID: UUID, selectedVisitIDs: [UUID], coveredStart: LocalDate, coveredEnd: LocalDate, issueDate: LocalDate, dueDate: LocalDate, updatedAt: Date = Date()) {
        self.id = id
        self.customerID = customerID
        self.selectedVisitIDs = selectedVisitIDs
        self.coveredStart = coveredStart
        self.coveredEnd = coveredEnd
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.updatedAt = updatedAt
    }
}

public struct IssuedInvoiceLine: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let sourceVisitID: UUID
    public let workDate: LocalDate
    public let siteName: String
    public let siteAddress: String
    public let position: Int
    public let description: String
    public let quantity: Quantity
    public let unit: String
    public let unitPrice: Money
    public let taxRate: TaxRate
    public let net: Money
}

public struct InvoiceCorrectionLine: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sourceVisitID: UUID
    public var workDate: LocalDate
    public var siteName: String
    public var siteAddress: String
    public var description: String
    public var quantity: Quantity
    public var unit: String
    public var unitPrice: Money
    public var taxRate: TaxRate

    public init(
        id: UUID = UUID(),
        sourceVisitID: UUID,
        workDate: LocalDate,
        siteName: String,
        siteAddress: String,
        description: String,
        quantity: Quantity,
        unit: String,
        unitPrice: Money,
        taxRate: TaxRate
    ) {
        self.id = id
        self.sourceVisitID = sourceVisitID
        self.workDate = workDate
        self.siteName = siteName
        self.siteAddress = siteAddress
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.taxRate = taxRate
    }

    public init(invoiceLine: IssuedInvoiceLine) {
        self.init(
            sourceVisitID: invoiceLine.sourceVisitID,
            workDate: invoiceLine.workDate,
            siteName: invoiceLine.siteName,
            siteAddress: invoiceLine.siteAddress,
            description: invoiceLine.description,
            quantity: invoiceLine.quantity,
            unit: invoiceLine.unit,
            unitPrice: invoiceLine.unitPrice,
            taxRate: invoiceLine.taxRate
        )
    }
}

public struct InvoiceTaxTotal: Hashable, Codable, Sendable {
    public let taxRate: TaxRate
    public let taxable: Money
    public let tax: Money
}

public enum InvoiceStatus: String, Codable, Sendable {
    case issued
    case paid
    case voided
    case corrected
    case needsRecovery
}

public struct IssuedInvoice: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let number: String
    public let issueDate: LocalDate
    public let dueDate: LocalDate
    public let coveredStart: LocalDate
    public let coveredEnd: LocalDate
    public let issuer: BusinessProfile
    public let customerID: UUID
    public let customerName: String
    public let customerAddress: String
    public let lines: [IssuedInvoiceLine]
    public let taxTotals: [InvoiceTaxTotal]
    public let subtotal: Money
    public let totalTax: Money
    public let grandTotal: Money
    public let lineRounding: RoundingRule
    public let taxRounding: RoundingRule
    public var status: InvoiceStatus
    public var paidDate: LocalDate?
    public var replacesInvoiceID: UUID?
    public var replacesInvoiceNumber: String?
    public var replacedByInvoiceID: UUID?
    public var pdfRelativePath: String?
    public var pdfSHA256: String?
    public let issuedAt: Date
}

public struct EntitlementState: Hashable, Codable, Sendable {
    public var hasPro: Bool
    public var firstCleanInvoiceID: UUID?

    public init(hasPro: Bool = false, firstCleanInvoiceID: UUID? = nil) {
        self.hasPro = hasPro
        self.firstCleanInvoiceID = firstCleanInvoiceID
    }

    public func permits(activeCustomerCount: Int) -> Bool { hasPro || activeCustomerCount < 2 }
    public var permitsCleanIssue: Bool { hasPro || firstCleanInvoiceID == nil }
}
