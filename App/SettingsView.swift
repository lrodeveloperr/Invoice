import InvoiceDomain
import InvoiceEntitlements
import SwiftUI
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
    @State private var showPro = false
    @State private var showAddCustomer = false
    @State private var showAddSite = false
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var deletePhrase = ""
    @State private var showDelete = false

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
                    Button(language.text("action.saveIssuer")) { saveBusiness() }
                        .disabled(issuerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section(language.text("settings.customers")) {
                    ForEach(model.customers) { customer in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(customer.name)
                            if !customer.billingAddress.isEmpty {
                                Text(customer.billingAddress).font(.caption).foregroundStyle(.secondary)
                            }
                        }
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
        .sheet(isPresented: $showPro) {
            ProSheet(language: language).environmentObject(store)
        }
        .sheet(isPresented: $showAddCustomer) {
            AddCustomerView(language: language).environmentObject(model).environmentObject(store)
        }
        .sheet(isPresented: $showAddSite) {
            AddSiteView(language: language).environmentObject(model)
        }
        .sheet(isPresented: $showDelete) {
            DeleteDataView(language: language, phrase: $deletePhrase) {
                Task { await model.deleteAllData(); showDelete = false }
            }
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
            case .success(let url): Task { await model.restoreBackup(from: url) }
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
            taxRounding: model.business?.taxRounding ?? .floor
        )
        Task { await model.saveBusiness(profile) }
    }

    private func exportBackup() {
        Task {
            do {
                exportDocument = BackupDocument(wrapper: try await model.exportBackup())
                showExporter = true
            } catch {
                model.errorMessage = String(describing: error)
            }
        }
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

    var body: some View {
        NavigationStack {
            Form {
                TextField(language.text("field.customerName"), text: $name)
                TextField(language.text("field.billingAddress"), text: $address, axis: .vertical)
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
                _ = try await model.addCustomer(name: name, address: address, hasPro: store.hasPro)
                dismiss()
            } catch let error as InvoiceError where error == .entitlementRequired {
                showPro = true
            } catch {
                model.errorMessage = String(describing: error)
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
