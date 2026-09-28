import InvoiceDomain
import SwiftUI

struct InvoiceSplitView: View {
    @EnvironmentObject private var model: AppModel
    let language: AppLanguage
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if model.invoices.isEmpty {
                    ContentUnavailableView(
                        language.text("invoices.empty.title"),
                        systemImage: "doc.text",
                        description: Text(language.text("invoices.empty.message"))
                    )
                } else {
                    invoiceSection(.issued, key: "state.issued")
                    invoiceSection(.paid, key: "state.paid")
                    invoiceSection(.voided, key: "state.voided")
                    invoiceSection(.needsRecovery, key: "state.needsRecovery")
                }
            }
            .navigationTitle(language.text("invoices.title"))
            .refreshable { try? await model.refresh() }
        } detail: {
            if let selection,
               let invoice = model.invoices.first(where: { $0.id == selection }) {
                InvoiceDetailView(invoice: invoice, language: language)
            } else {
                EmptyDetailView(
                    title: language.text("invoices.select.title"),
                    systemImage: "doc.text.magnifyingglass",
                    description: language.text("invoices.select.message")
                )
            }
        }
    }

    @ViewBuilder
    private func invoiceSection(_ status: InvoiceStatus, key: String) -> some View {
        let rows = model.invoices.filter { $0.status == status }
        if !rows.isEmpty {
            Section(language.text(key)) {
                ForEach(rows) { invoice in
                    NavigationLink(value: invoice.id) {
                        InvoiceRow(invoice: invoice, language: language)
                    }
                }
            }
        }
    }
}

private struct InvoiceRow: View {
    let invoice: IssuedInvoice
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(invoice.number).font(.subheadline.weight(.semibold).monospacedDigit())
                Spacer()
                Text(yenText(invoice.grandTotal)).font(.subheadline.monospacedDigit())
            }
            Text(invoice.customerName).foregroundStyle(.secondary)
            Text(localDateText(invoice.issueDate))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct InvoiceDetailView: View {
    @EnvironmentObject private var model: AppModel
    let invoice: IssuedInvoice
    let language: AppLanguage
    @State private var pdfData: Data?
    @State private var sharedFile: SharedFile?
    @State private var confirmVoid = false

    var body: some View {
        Group {
            if let pdfData {
                PDFKitView(data: pdfData)
                    .accessibilityLabel(language.text("preview.pdfAccessibility"))
            } else {
                ProgressView(language.text("invoice.loading"))
            }
        }
        .navigationTitle(invoice.number)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if pdfData != nil {
                    Button {
                        share()
                    } label: {
                        Label(language.text("action.share"), systemImage: "square.and.arrow.up")
                    }
                }
                if invoice.status == .issued {
                    Button {
                        Task { await model.markPaid(invoice) }
                    } label: {
                        Label(language.text("invoice.markPaid"), systemImage: "checkmark.circle")
                    }
                }
                if invoice.status == .paid {
                    Button {
                        Task { await model.markUnpaid(invoice) }
                    } label: {
                        Label(language.text("invoice.markUnpaid"), systemImage: "arrow.uturn.backward.circle")
                    }
                }
                if invoice.status == .issued || invoice.status == .paid {
                    Button(role: .destructive) {
                        confirmVoid = true
                    } label: {
                        Label(language.text("invoice.void"), systemImage: "xmark.circle")
                    }
                }
            }
        }
        .task(id: invoice.id) { await loadPDF() }
        .sheet(item: $sharedFile) { ShareSheet(items: [$0.url]) }
        .confirmationDialog(language.text("invoice.void.confirmTitle"), isPresented: $confirmVoid) {
            Button(language.text("invoice.void"), role: .destructive) {
                Task { await model.void(invoice) }
            }
            Button(language.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("invoice.void.confirmMessage"))
        }
    }

    private func loadPDF() async {
        do { pdfData = try await model.canonicalPDF(for: invoice) }
        catch { model.errorMessage = String(describing: error) }
    }

    private func share() {
        guard let pdfData else { return }
        do { sharedFile = SharedFile(url: try temporaryPDFURL(data: pdfData, filename: "\(invoice.number).pdf")) }
        catch { model.errorMessage = String(describing: error) }
    }
}
