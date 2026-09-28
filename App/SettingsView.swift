import InvoiceDomain
import InvoiceEntitlements
import InvoiceBackup
import InvoicePersistence
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UTType {
    static let datedInvoiceBackup = UTType(
        exportedAs: "com.worksbienstudios.datedinvoicebackup",
        conformingTo: .package
    )
}

struct BackupDocument: FileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.datedInvoiceBackup] }
    let wrapper: FileWrapper

    init(wrapper: FileWrapper) { self.wrapper = wrapper }

    init(configuration: ReadConfiguration) throws {
        wrapper = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: StoreKitEntitlementStore
    @Binding var languageCode: String
    let language: AppLanguage
    @State private var issuerName = ""
    @State private var address = ""
    @State private var registration = ""
    @State private var bank = ""
    @State private var prefix = ""
    @State private var pdfStyle: PDFStyle = .classic
    @State private var logoPNGData: Data?
    @State private var logoItem: PhotosPickerItem?
    @State private var showPro = false
    @State private var showAddCustomer = false
    @State private var showAddSite = false
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var deletePhrase = ""
    @State private var showDelete = false
    @State private var restorePreview: RestorePreview?
    @State private var showResetSample = false
    @State private var editingCustomer: Customer?
    @State private var showAddTemplate = false

    var body: some View {
        NavigationStack {
            Form {
                Section(language.text("settings.language")) {
                    Picker(language.text("settings.language"), selection: $languageCode) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(language.text("settings.issuer")) {
                    TextField(language.text("field.issuerName"), text: $issuerName)
                    TextField(language.text("field.address"), text: $address, axis: .vertical)
                    TextField(language.text("field.registration"), text: $registration)
                        .textInputAutocapitalization(.characters)
                    TextField(language.text("field.bank"), text: $bank, axis: .vertical)
                    TextField(language.text("field.prefix"), text: $prefix)
                        .textInputAutocapitalization(.characters)
                    if store.hasPro {
                        Picker(language.text("pdf.style"), selection: $pdfStyle) {
                            ForEach(PDFStyle.allCases, id: \.self) { style in
                                Text(language.text("pdf.style.\(style.rawValue)")).tag(style)
                            }
                        }
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Label(
                                logoPNGData == nil
                                    ? language.text("logo.choose")
                                    : language.text("logo.replace"),
                                systemImage: "photo.badge.plus"
                            )
                        }
                        if logoPNGData != nil {
                            Button(language.text("logo.remove"), role: .destructive) {
                                logoPNGData = nil
                                logoItem = nil
                            }
                        }
                    } else {
                        Button {
                            showPro = true
                        } label: {
                            Label(language.text("branding.pro"), systemImage: "paintbrush")
                        }
                    }
                    Button(language.text("action.saveIssuer")) { saveBusiness() }
                        .disabled(issuerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section(language.text("settings.customers")) {
                    ForEach(model.customers) { customer in
                        Button {
                            editingCustomer = customer
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(customer.name).foregroundStyle(.primary)
                                if !customer.billingAddress.isEmpty {
                                    Text(customer.billingAddress).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        showAddCustomer = true
                    } label: {
                        Label(language.text("customer.add"), systemImage: "person.badge.plus")
                    }
                    Button {
                        showAddSite = true
                    } label: {
                        Label(language.text("site.add"), systemImage: "mappin.and.ellipse")
                    }
                    .disabled(model.customers.isEmpty)
                }

                Section(language.text("settings.templates")) {
                    ForEach(model.serviceTemplates.filter(\.isActive)) { template in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.title)
                            Text("\(template.unit) · \(yenText(template.unitPrice)) · \(template.taxRate.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        if store.hasPro { showAddTemplate = true } else { showPro = true }
                    } label: {
                        Label(language.text("template.add"), systemImage: "list.bullet.rectangle")
                    }
                }

                Section(language.text("settings.pro")) {
                    LabeledContent(language.text("pro.status"), value: store.hasPro ? language.text("pro.active") : language.text("pro.free"))
                    if !store.hasPro {
                        Button {
                            showPro = true
                        } label: {
                            Label(language.text("pro.view"), systemImage: "checkmark.seal")
                        }
                    }
                }

                Section(language.text("settings.data")) {
                    Button {
                        exportBackup()
                    } label: {
                        Label(language.text("backup.export"), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label(language.text("backup.restore"), systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showResetSample = true
                    } label: {
                        Label(language.text("sample.reset"), systemImage: "arrow.counterclockwise")
                    }
                    Button(role: .destructive) {
                        deletePhrase = ""
                        showDelete = true
                    } label: {
                        Label(language.text("data.delete"), systemImage: "trash")
                    }
                }

                Section(language.text("settings.support")) {
                    Link(language.text("support.help"), destination: URL(string: "https://worksbienstudios.com/apps/dated-service-invoice/support/")!)
                    Link(language.text("support.privacy"), destination: URL(string: "https://worksbienstudios.com/apps/dated-service-invoice/privacy/")!)
                }

                Section {
                    LabeledContent(language.text("settings.version"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                } footer: {
                    Text(language.text("settings.offlineNote"))
                }
            }
            .navigationTitle(language.text("settings.title"))
        }
        .onAppear(perform: loadBusiness)
        .onChange(of: model.business?.id) { _, _ in loadBusiness() }
        .onChange(of: logoItem) { _, item in
            Task {
                guard store.hasPro, let item else { return }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let png = normalizedLogoPNG(image) else { return }
                    logoPNGData = png
                } catch {
                    model.errorMessage = language.errorText(error)
                }
            }
        }
        .sheet(isPresented: $showPro) {
            ProSheet(language: language).environmentObject(store)
        }
        .sheet(isPresented: $showAddCustomer) {
            AddCustomerView(language: language).environmentObject(model).environmentObject(store)
        }
        .sheet(isPresented: $showAddSite) {
            AddSiteView(language: language).environmentObject(model)
        }
        .sheet(item: $editingCustomer) { customer in
            EditCustomerView(customer: customer, language: language)
                .environmentObject(model)
                .environmentObject(store)
        }
        .sheet(isPresented: $showAddTemplate) {
            AddTemplateView(language: language)
                .environmentObject(model)
                .environmentObject(store)
        }
        .sheet(isPresented: $showDelete) {
            DeleteDataView(language: language, phrase: $deletePhrase) {
                Task { await model.deleteAllData(); showDelete = false }
            }
        }
        .sheet(item: $restorePreview) { preview in
            RestoreConfirmationView(preview: preview, language: language) { mode in
                Task {
                    await model.restoreBackup(from: preview.url, mode: mode)
                    restorePreview = nil
                }
            }
        }
        .confirmationDialog(language.text("sample.reset.title"), isPresented: $showResetSample) {
            Button(language.text("sample.reset.confirm"), role: .destructive) {
                Task { await model.resetSampleData() }
            }
            Button(language.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("sample.reset.message"))
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .datedInvoiceBackup,
            defaultFilename: "Invoice-Backup"
        ) { result in
            if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
            exportDocument = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.datedInvoiceBackup]) { result in
            switch result {
            case .success(let url):
                Task {
                    do { restorePreview = try await model.preflightRestore(from: url) }
                    catch { model.errorMessage = language.errorText(error) }
                }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
    }

    private func loadBusiness() {
        guard let business = model.business else { return }
        issuerName = business.issuerName
        address = business.postalAddress
        registration = business.registrationNumber ?? ""
        bank = business.bankDetails
        prefix = business.invoicePrefix
        pdfStyle = business.effectivePDFStyle
        logoPNGData = business.logoPNGData
    }

    private func saveBusiness() {
        let profile = BusinessProfile(
            id: model.business?.id ?? UUID(),
            issuerName: issuerName.trimmingCharacters(in: .whitespacesAndNewlines),
            postalAddress: address,
            registrationNumber: registration.isEmpty ? nil : registration,
            bankDetails: bank,
            invoicePrefix: prefix,
            lineRounding: model.business?.lineRounding ?? .halfUp,
            taxRounding: model.business?.taxRounding ?? .floor,
            pdfStyle: store.hasPro ? pdfStyle : model.business?.pdfStyle,
            logoPNGData: store.hasPro ? logoPNGData : model.business?.logoPNGData
        )
        Task { await model.saveBusiness(profile, hasPro: store.hasPro) }
    }

    private func normalizedLogoPNG(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 512 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.pngData()
    }

    private func exportBackup() {
        Task {
            do {
                exportDocument = BackupDocument(wrapper: try await model.exportBackup())
                showExporter = true
            } catch {
                model.errorMessage = language.errorText(error)
            }
        }
    }
}

private struct RestoreConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    let preview: RestorePreview
    let language: AppLanguage
    let restore: (RestoreMode) -> Void

    private var mergeReport: DatabaseMergeReport? { preview.merge.databaseMerge }

    var body: some View {
        NavigationStack {
            Form {
                Section(language.text("restore.verified")) {
                    LabeledContent(language.text("restore.pdfsAdded"), value: String(preview.replace.pdfsAdded))
                    LabeledContent(language.text("restore.pdfsReused"), value: String(preview.replace.pdfsReused))
                }
                if let counts = mergeReport?.counts {
                    Section(language.text("restore.mergeChanges")) {
                        LabeledContent(language.text("field.customer"), value: String(counts.customers))
                        LabeledContent(language.text("tab.work"), value: String(counts.visits))
                        LabeledContent(language.text("tab.invoices"), value: String(counts.invoices))
                    }
                }
                Section {
                    Button(language.text("restore.merge")) { restore(.merge) }
                        .disabled(mergeReport?.canCommit != true)
                    Button(language.text("restore.replace"), role: .destructive) { restore(.replace) }
                } footer: {
                    Text(language.text("restore.safetyNote"))
                }
            }
            .navigationTitle(language.text("restore.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("action.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AddCustomerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: StoreKitEntitlementStore
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    @State private var name = ""
    @State private var address = ""
    @State private var saving = false
    @State private var showPro = false
    @State private var closingDay = 0
    @State private var paymentTermDays = 30

    var body: some View {
        NavigationStack {
            Form {
                TextField(language.text("field.customerName"), text: $name)
                TextField(language.text("field.billingAddress"), text: $address, axis: .vertical)
                if store.hasPro {
                    Picker(language.text("field.closingDay"), selection: $closingDay) {
                        Text(language.text("field.none")).tag(0)
                        ForEach(1...31, id: \.self) { day in
                            Text(String(format: language.text("field.dayFormat"), day)).tag(day)
                        }
                    }
                    Picker(language.text("field.paymentTerm"), selection: $paymentTermDays) {
                        ForEach([0, 7, 15, 30, 45, 60], id: \.self) { days in
                            Text(String(format: language.text("field.daysFormat"), days)).tag(days)
                        }
                    }
                } else {
                    Button {
                        showPro = true
                    } label: {
                        Label(language.text("customer.termsPro"), systemImage: "checkmark.seal")
                    }
                }
            }
            .navigationTitle(language.text("customer.add"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.text("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("action.add")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
        }
        .sheet(isPresented: $showPro) {
            ProSheet(language: language).environmentObject(store)
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                _ = try await model.addCustomer(
                    name: name,
                    address: address,
                    closingDay: closingDay == 0 ? nil : closingDay,
                    paymentTermDays: paymentTermDays,
                    hasPro: store.hasPro
                )
                dismiss()
            } catch let error as InvoiceError where error == .entitlementRequired {
                showPro = true
            } catch {
                model.errorMessage = String(describing: error)
            }
        }
    }
}

private struct EditCustomerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: StoreKitEntitlementStore
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    let language: AppLanguage
    @State private var name: String
    @State private var address: String
    @State private var closingDay: Int
    @State private var paymentTermDays: Int
    @State private var showPro = false

    init(customer: Customer, language: AppLanguage) {
        self.customer = customer
        self.language = language
        _name = State(initialValue: customer.name)
        _address = State(initialValue: customer.billingAddress)
        _closingDay = State(initialValue: customer.closingDay ?? 0)
        _paymentTermDays = State(initialValue: customer.paymentTermDays)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(language.text("field.customerName"), text: $name)
                TextField(language.text("field.billingAddress"), text: $address, axis: .vertical)
                if store.hasPro {
                    Picker(language.text("field.closingDay"), selection: $closingDay) {
                        Text(language.text("field.none")).tag(0)
                        ForEach(1...31, id: \.self) { day in
                            Text(String(format: language.text("field.dayFormat"), day)).tag(day)
                        }
                    }
                    Picker(language.text("field.paymentTerm"), selection: $paymentTermDays) {
                        ForEach([0, 7, 15, 30, 45, 60], id: \.self) { days in
                            Text(String(format: language.text("field.daysFormat"), days)).tag(days)
                        }
                    }
                } else {
                    Button { showPro = true } label: {
                        Label(language.text("customer.termsPro"), systemImage: "checkmark.seal")
                    }
                }
            }
            .navigationTitle(language.text("customer.edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("action.save")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .sheet(isPresented: $showPro) {
            ProSheet(language: language).environmentObject(store)
        }
    }

    private func save() {
        var edited = customer
        edited.name = name
        edited.billingAddress = address
        if store.hasPro {
            edited.closingDay = closingDay == 0 ? nil : closingDay
            edited.paymentTermDays = paymentTermDays
        }
        Task {
            do {
                try await model.saveCustomer(edited, hasPro: store.hasPro)
                dismiss()
            } catch {
                model.errorMessage = language.errorText(error)
            }
        }
    }
}

private struct AddTemplateView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: StoreKitEntitlementStore
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    @State private var title = ""
    @State private var unit = "回"
    @State private var unitPrice = ""
    @State private var taxBasisPoints = TaxRate.standard10.basisPoints

    var body: some View {
        NavigationStack {
            Form {
                TextField(language.text("field.service"), text: $title)
                TextField(language.text("field.unit"), text: $unit)
                TextField(language.text("field.unitPrice"), text: $unitPrice)
                    .keyboardType(.numberPad)
                Picker(language.text("field.tax"), selection: $taxBasisPoints) {
                    ForEach(TaxRate.launchCatalog, id: \.basisPoints) { rate in
                        Text(rate.label).tag(rate.basisPoints)
                    }
                }
            }
            .navigationTitle(language.text("template.add"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("action.add")) { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        Task {
            do {
                guard let yen = Int64(unitPrice),
                      let tax = TaxRate.launchCatalog.first(where: { $0.basisPoints == taxBasisPoints }) else {
                    throw InvoiceError.invalidMoney
                }
                try await model.saveServiceTemplate(
                    ServiceTemplate(
                        title: title,
                        unit: unit,
                        unitPrice: try Money(yen: yen),
                        taxRate: tax
                    ),
                    hasPro: store.hasPro
                )
                dismiss()
            } catch {
                model.errorMessage = language.errorText(error)
            }
        }
    }
}

private struct AddSiteView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    @State private var customerID: UUID?
    @State private var name = ""
    @State private var address = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker(language.text("field.customer"), selection: $customerID) {
                    ForEach(model.customers.filter(\.isActive)) { customer in
                        Text(customer.name).tag(Optional(customer.id))
                    }
                }
                TextField(language.text("field.siteName"), text: $name)
                TextField(language.text("field.address"), text: $address, axis: .vertical)
            }
            .navigationTitle(language.text("site.add"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.text("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("action.add")) { save() }
                        .disabled(customerID == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { customerID = customerID ?? model.customers.first(where: \.isActive)?.id }
        }
    }

    private func save() {
        guard let customerID else { return }
        Task {
            do {
                _ = try await model.addSite(customerID: customerID, name: name, address: address)
                dismiss()
            } catch {
                model.errorMessage = String(describing: error)
            }
        }
    }
}

private struct DeleteDataView: View {
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    @Binding var phrase: String
    let confirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(language.text("data.delete.warning"))
                    TextField(language.text("data.delete.placeholder"), text: $phrase)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text(language.text("data.delete.phrase"))
                }
                Button(language.text("data.delete.confirm"), role: .destructive, action: confirm)
                    .disabled(phrase != "DELETE")
            }
            .navigationTitle(language.text("data.delete"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.text("action.cancel")) { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
