import Foundation

public enum InvoiceError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidMoney
    case invalidQuantity
    case invalidDate
    case invalidTaxRate
    case arithmeticOverflow
    case invoiceTotalExceeded
    case emptyInvoice
    case mixedCustomers
    case visitNotUnbilled
    case duplicateVisit
    case duplicateInvoiceNumber
    case missingRequiredField(String)
    case entitlementRequired
    case invalidTransition
    case corruptData(String)

    public var description: String {
        switch self {
        case .invalidMoney: "invalid_money"
        case .invalidQuantity: "invalid_quantity"
        case .invalidDate: "invalid_date"
        case .invalidTaxRate: "invalid_tax_rate"
        case .arithmeticOverflow: "arithmetic_overflow"
        case .invoiceTotalExceeded: "invoice_total_exceeded"
        case .emptyInvoice: "empty_invoice"
        case .mixedCustomers: "mixed_customers"
        case .visitNotUnbilled: "visit_not_unbilled"
        case .duplicateVisit: "duplicate_visit"
        case .duplicateInvoiceNumber: "duplicate_invoice_number"
        case .missingRequiredField(let field): "missing_required_field:\(field)"
        case .entitlementRequired: "entitlement_required"
        case .invalidTransition: "invalid_transition"
        case .corruptData(let reason): "corrupt_data:\(reason)"
        }
    }
}

public enum RoundingRule: String, Codable, CaseIterable, Sendable {
    case floor
    case halfUp
    case ceiling
}

public struct Money: Hashable, Codable, Comparable, Sendable {
    public static let zero = Money(uncheckedYen: 0)
    public static let maximumInvoice = Money(uncheckedYen: 9_999_999_999_999)

    public let yen: Int64

    public init(yen: Int64) throws {
        guard yen >= 0 else { throw InvoiceError.invalidMoney }
        self.yen = yen
    }

    private init(uncheckedYen: Int64) { self.yen = uncheckedYen }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.yen < rhs.yen }

    public func adding(_ other: Money) throws -> Money {
        let result = yen.addingReportingOverflow(other.yen)
        guard !result.overflow else { throw InvoiceError.arithmeticOverflow }
        guard result.partialValue <= Self.maximumInvoice.yen else {
            throw InvoiceError.invoiceTotalExceeded
        }
        return Money(uncheckedYen: result.partialValue)
    }

    public func subtracting(_ other: Money) throws -> Money {
        guard yen >= other.yen else { throw InvoiceError.invalidMoney }
        return Money(uncheckedYen: yen - other.yen)
    }
}

public struct Quantity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let mantissa: Int64
    public let scale: Int

    public init(mantissa: Int64, scale: Int) throws {
        guard mantissa > 0, (0...3).contains(scale) else { throw InvoiceError.invalidQuantity }
        let limit = 999_999_999 // 999999.999 at scale 3
        let normalized = mantissa.multipliedReportingOverflow(by: Self.powerOfTen(3 - scale))
        guard !normalized.overflow, normalized.partialValue <= Int64(limit) else {
            throw InvoiceError.invalidQuantity
        }
        self.mantissa = mantissa
        self.scale = scale
    }

    public init(decimalString input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("-"), !value.hasPrefix("+") else {
            throw InvoiceError.invalidQuantity
        }
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2,
              let whole = pieces.first,
              !whole.isEmpty,
              whole.allSatisfy(\.isNumber) else { throw InvoiceError.invalidQuantity }
        let fraction = pieces.count == 2 ? String(pieces[1]) : ""
        guard fraction.count <= 3, fraction.allSatisfy(\.isNumber) else {
            throw InvoiceError.invalidQuantity
        }
        let digits = String(whole) + fraction
        guard let mantissa = Int64(digits) else { throw InvoiceError.invalidQuantity }
        try self.init(mantissa: mantissa, scale: fraction.count)
    }

    public var description: String {
        guard scale > 0 else { return String(mantissa) }
        let divisor = Self.powerOfTen(scale)
        let fraction = String(mantissa % divisor)
        let paddedFraction = String(repeating: "0", count: scale - fraction.count) + fraction
        return "\(mantissa / divisor).\(paddedFraction)"
    }

    public func multiplied(by unitPrice: Money, rounding: RoundingRule) throws -> Money {
        let product = mantissa.multipliedReportingOverflow(by: unitPrice.yen)
        guard !product.overflow else { throw InvoiceError.arithmeticOverflow }
        let rounded = try Self.roundedDivision(
            numerator: product.partialValue,
            denominator: Self.powerOfTen(scale),
            rule: rounding
        )
        return try Money(yen: rounded)
    }

    public static func roundedDivision(
        numerator: Int64,
        denominator: Int64,
        rule: RoundingRule
    ) throws -> Int64 {
        guard numerator >= 0, denominator > 0 else { throw InvoiceError.invalidMoney }
        let quotient = numerator / denominator
        let remainder = numerator % denominator
        guard remainder != 0 else { return quotient }
        switch rule {
        case .floor: return quotient
        case .ceiling:
            let value = quotient.addingReportingOverflow(1)
            guard !value.overflow else { throw InvoiceError.arithmeticOverflow }
            return value.partialValue
        case .halfUp:
            return remainder >= (denominator + 1) / 2 ? quotient + 1 : quotient
        }
    }

    static func powerOfTen(_ exponent: Int) -> Int64 {
        switch exponent {
        case 0: 1
        case 1: 10
        case 2: 100
        default: 1_000
        }
    }
}

public struct TaxRate: Hashable, Codable, Sendable {
    public let id: String
    public let basisPoints: Int
    public let label: String

    public init(id: String, basisPoints: Int, label: String) throws {
        guard !id.isEmpty, (0...10_000).contains(basisPoints) else {
            throw InvoiceError.invalidTaxRate
        }
        self.id = id
        self.basisPoints = basisPoints
        self.label = label
    }

    public static let standard10 = try! TaxRate(id: "jp-10-v1", basisPoints: 1_000, label: "10%")
    public static let reduced8 = try! TaxRate(id: "jp-8-v1", basisPoints: 800, label: "8%")
    public static let zero = try! TaxRate(id: "jp-0-v1", basisPoints: 0, label: "0%")
    public static let launchCatalog = [standard10, reduced8, zero]
}
