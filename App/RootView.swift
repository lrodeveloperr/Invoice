import SwiftUI

private enum AppTab: Hashable {
    case work
    case invoices
    case settings
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var languageCode: String
    @State private var selection: AppTab = .work

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .japanese
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(language.text("tab.work"), systemImage: "wrench.and.screwdriver", value: AppTab.work) {
                WorkSplitView(language: language)
            }
            Tab(language.text("tab.invoices"), systemImage: "doc.text", value: AppTab.invoices) {
                InvoiceSplitView(language: language)
            }
            Tab(language.text("tab.settings"), systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(languageCode: $languageCode, language: language)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .overlay {
            if model.isBusy {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel(language.text("status.working"))
            }
        }
        .alert(language.text("error.title"), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(language.text("action.ok"), role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? language.text("error.generic"))
        }
    }
}
