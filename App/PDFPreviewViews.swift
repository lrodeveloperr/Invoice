import InvoiceDomain
import InvoiceEntitlements
import PDFKit
import SwiftUI
import UIKit

struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}

struct PDFPreviewIssueView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: StoreKitEntitlementStore
    let package: PreviewPackage
    let language: AppLanguage
    let onFinished: () -> Void
    @State private var issuing = false
    @State private var showPro = false
    @State private var sharedFile: SharedFile?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.invoice.number)
                        .font(.headline.monospacedDigit())
                    Text(package.customer.name)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(yenText(package.invoice.grandTotal))
                        .font(.title3.bold().monospacedDigit())
                    Text(store.hasPro ? language.text("pro.active") : language.text("pro.freeStatus"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    issue()
                } label: {
                    if issuing {
                        ProgressView()
                    } else {
                        Label(language.text("preview.issue"), systemImage: "checkmark.seal.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(issuing)
            }
            .padding()
            Divider()
            ZStack {
                PDFKitView(data: package.pdfData)
                    .accessibilityLabel(language.text("preview.pdfAccessibility"))
                if !store.hasPro {
                    Text(language.text("preview.watermark"))
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.22))
                        .rotationEffect(.degrees(-24))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .navigationTitle(language.text("preview.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPro) {
            ProSheet(language: language)
                .environmentObject(store)
        }
        .sheet(item: $sharedFile) { file in
            ShareSheet(items: [file.url])
                .onDisappear { onFinished() }
        }
    }

    private func issue() {
        issuing = true
        Task {
            defer { issuing = false }
            do {
                let invoice = try await model.issue(package, hasPro: store.hasPro)
                let data = try await model.canonicalPDF(for: invoice)
                sharedFile = SharedFile(url: try temporaryPDFURL(data: data, filename: "\(invoice.number).pdf"))
            } catch let error as InvoiceError where error == .entitlementRequired {
                showPro = true
            } catch {
                model.errorMessage = String(describing: error)
            }
        }
    }
}

struct ProSheet: View {
    @EnvironmentObject private var store: StoreKitEntitlementStore
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    @State private var purchasing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(language.text("pro.title"))
                    .font(.largeTitle.bold())
                Text(language.text("pro.message"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Label(language.text("pro.feature.customers"), systemImage: "person.2")
                    Label(language.text("pro.feature.invoices"), systemImage: "doc.text")
                    Label(language.text("pro.feature.templates"), systemImage: "list.bullet.rectangle")
                    Label(language.text("pro.feature.branding"), systemImage: "paintbrush")
                    Label(language.text("pro.feature.once"), systemImage: "creditcard")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let errorID = store.lastErrorID {
                    Label(language.errorText(id: errorID), systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                Button {
                    purchasing = true
                    Task {
                        let purchased = await store.purchase()
                        purchasing = false
                        if purchased { dismiss() }
                    }
                } label: {
                    if purchasing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(String(format: language.text("pro.buyFormat"), store.displayPrice ?? language.text("pro.priceLoading")))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(purchasing || store.product == nil)
                if store.product == nil {
                    Button(language.text("store.retry")) {
                        Task { await store.load() }
                    }
                }
                Button(language.text("pro.restore")) {
                    Task {
                        await store.restorePurchase()
                        if store.hasPro { dismiss() }
                    }
                }
            }
            .padding(24)
            .navigationTitle(language.text("pro.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("action.close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

func temporaryPDFURL(data: Data, filename: String) throws -> URL {
    let safeName = filename.replacingOccurrences(of: "/", with: "-")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
    try data.write(to: url, options: .atomic)
    return url
}
