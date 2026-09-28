import InvoiceDomain
import InvoiceEntitlements
import SwiftUI

private struct CorrectionLineForm: Identifiable {
    let id: UUID
    let sourceVisitID: UUID
    let workDate: LocalDate
    let siteName: String
    let siteAddress: String
    var description: String
    var quantity: String
    var unit: String
    var unitPrice: String
    var taxBasisPoints: Int

    init(_ line: IssuedInvoiceLine) {
        id = line.id
        sourceVisitID = line.sourceVisitID
        workDate = line.workDate
        siteName = line.siteName
        siteAddress = line.siteAddress
        description = line.description
        quantity = line.quantity.description
        unit = line.unit
        unitPrice = String(line.unitPrice.yen)
        taxBasisPoints = line.taxRate.basisPoints
    }

    func correctionLine() throws -> InvoiceCorrectionLine {
        guard let yen = Int64(unitPrice) else { throw InvoiceError.invalidMoney }
        let taxRate = TaxRate.launchCatalog.first(where: { $0.basisPoints == taxBasisPoints })
        guard let taxRate else { throw InvoiceError.invalidTaxRate }
        return InvoiceCorrectionLine(
            sourceVisitID: sourceVisitID,
            workDate: workDate,
            siteName: siteName,
            siteAddress: siteAddress,
            description: description,
            quantity: try Quantity(decimalString: quantity),
            unit: unit,
            unitPrice: try Money(yen: yen),
            taxRate: taxRate
        )
    }
}

struct CorrectionFlowView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: StoreKitEntitlementStore
    @Environment(\.dismiss) private var dismiss
    let original: IssuedInvoice
    let language: AppLanguage
    @State private var issueDate: Date
    @State private var dueDate: Date
    @State private var lines: [CorrectionLineForm]
    @State private var preview: CorrectionPreviewPackage?
    @State private var preparing = false
    @State private var issuing = false
    @State private var showPro = false
    @State private var sharedFile: SharedFile?

    init(original: IssuedInvoice, language: AppLanguage) {
        self.original = original
        self.language = language
        let today = Date()
        let term = Calendar(identifier: .gregorian).date(byAdding: .day, value: 30, to: today) ?? today
        _issueDate = State(initialValue: today)
        _dueDate = State(initialValue: term)
        _lines = State(initialValue: original.lines.map(CorrectionLineForm.init))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let preview {
                    previewView(preview)
                } else {
                    editor
                }
            }
            .navigationTitle(language.text("correction.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("action.close")) { dismiss() }
                }
                if preview != nil {
                    ToolbarItem(placement: .secondaryAction) {
                        Button(language.text("correction.edit")) { self.preview = nil }
                    }
                }
            }
        }
        .sheet(isPresented: $showPro) {
            ProSheet(language: language).environmentObject(store)
        }
        .sheet(item: $sharedFile) { file in
            ShareSheet(items: [file.url]).onDisappear { dismiss() }
        }
    }

    private var editor: some View {
        Form {
            Section {
                LabeledContent(language.text("correction.original"), value: original.number)
                Text(language.text("correction.explanation"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section(language.text("correction.dates")) {
                DatePicker(language.text("correction.issueDate"), selection: $issueDate, displayedComponents: .date)
                DatePicker(language.text("correction.dueDate"), selection: $dueDate, in: issueDate..., displayedComponents: .date)
            }
            ForEach($lines) { $line in
                Section(language.text("correction.line")) {
                    LabeledContent(language.text("field.date"), value: localDateText(line.workDate))
                    LabeledContent(language.text("field.site"), value: line.siteName)
                    TextField(language.text("field.service"), text: $line.description, axis: .vertical)
                    TextField(language.text("field.quantity"), text: $line.quantity)
                        .keyboardType(.decimalPad)
                    TextField(language.text("field.unit"), text: $line.unit)
                    TextField(language.text("field.unitPrice"), text: $line.unitPrice)
                        .keyboardType(.numberPad)
                    Picker(language.text("field.tax"), selection: $line.taxBasisPoints) {
                        ForEach(TaxRate.launchCatalog, id: \.basisPoints) { rate in
                            Text(rate.label).tag(rate.basisPoints)
                        }
                    }
                }
            }
            Section {
                Button {
                    prepare()
                } label: {
                    if preparing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(language.text("correction.review"), systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(preparing || lines.isEmpty)
            } footer: {
                Text(language.text("correction.auditNote"))
            }
        }
    }

    private func previewView(_ package: CorrectionPreviewPackage) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.invoice.number).font(.headline.monospacedDigit())
                    Text(String(format: language.text("correction.replacesFormat"), original.number))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(yenText(package.invoice.grandTotal))
                    .font(.title3.bold().monospacedDigit())
                Button {
                    issue(package)
                } label: {
                    if issuing { ProgressView() }
                    else { Label(language.text("correction.issue"), systemImage: "checkmark.seal.fill") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(issuing)
            }
            .padding()
            Divider()
            PDFKitView(data: package.pdfData)
                .accessibilityLabel(language.text("preview.pdfAccessibility"))
        }
    }

    private func prepare() {
        preparing = true
        Task {
            defer { preparing = false }
            do {
                preview = try await model.prepareCorrection(
                    original: original,
                    issueDate: issueDate,
                    dueDate: dueDate,
                    lines: try lines.map { try $0.correctionLine() }
                )
            } catch {
                model.errorMessage = language.errorText(error)
            }
        }
    }

    private func issue(_ package: CorrectionPreviewPackage) {
        issuing = true
        Task {
            defer { issuing = false }
            do {
                let invoice = try await model.issueCorrection(package, hasPro: store.hasPro)
                let data = try await model.canonicalPDF(for: invoice)
                sharedFile = SharedFile(
                    url: try temporaryPDFURL(data: data, filename: "\(invoice.number).pdf")
                )
            } catch let error as InvoiceError where error == .entitlementRequired {
                showPro = true
            } catch {
                model.errorMessage = language.errorText(error)
            }
        }
    }
}
