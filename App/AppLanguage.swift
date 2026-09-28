import Foundation
import InvoiceDomain

enum AppLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case english = "en"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue == "ja" ? "ja_JP" : "en_US") }
    var displayName: String { self == .japanese ? "日本語" : "English" }

    func text(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func errorText(_ error: Error) -> String {
        errorText(id: String(describing: error))
    }

    func errorText(id: String?) -> String {
        guard let id, !id.isEmpty else { return text("error.generic") }
        if id == "invalid_money" { return text("error.invalidMoney") }
        if id == "invalid_quantity" { return text("error.invalidQuantity") }
        if id == "invalid_date" { return text("error.invalidDate") }
        if id == "invalid_tax_rate" { return text("error.invalidTax") }
        if id == "entitlement_required" { return text("error.proRequired") }
        if id.hasPrefix("missing_required_field:") { return text("error.missingField") }
        if id.hasPrefix("corrupt_data:") { return text("error.dataIntegrity") }
        if id == "visit_not_unbilled" || id == "invalid_transition" {
            return text("error.stateChanged")
        }
        if id.contains(" ") || id.contains("。") { return id }
        return text("error.generic")
    }
}
