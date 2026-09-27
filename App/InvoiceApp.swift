import InvoiceEntitlements
import SwiftUI

@main
struct DatedServiceInvoiceApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var entitlementStore = StoreKitEntitlementStore(
        productID: "com.worksbien.serviceinvoice.pro.lifetime"
    )
    @AppStorage("appLanguage") private var languageCode = AppLanguage.japanese.rawValue

    var body: some Scene {
        WindowGroup {
            RootView(languageCode: $languageCode)
                .environmentObject(model)
                .environmentObject(entitlementStore)
                .environment(\.locale, AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.japanese.locale)
                .task {
                    await model.bootstrap()
                    await entitlementStore.load()
                }
        }
    }
}
