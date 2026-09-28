import InvoiceDomain
import InvoiceEntitlements
import SwiftUI

private enum WorkDestination: Hashable {
    case visit(UUID)
    case newVisit
    case builder
    case preview
}

struct WorkSplitView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let language: AppLanguage
    @State private var selection: WorkDestination?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var previewPackage: PreviewPackage?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                if model.customers.isEmpty {
                    ContentUnavailableView(
                        language.text("work.empty.title"),
                        systemImage: "wrench.and.screwdriver",
                        description: Text(language.text("work.empty.message"))
                    )
                } else {
                    ForEach(model.customers.filter(\.isActive)) { customer in
                        let rows = model.visits.filter {
                            $0.customerID == customer.id && $0.state == .unbilled
                        }
                        if !rows.isEmpty {
                            Section(customer.name) {
                                ForEach(rows) { visit in
                                    NavigationLink(value: WorkDestination.visit(visit.id)) {
                                        VisitRow(visit: visit, language: language)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(language.text("work.title"))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        selection = .builder
                        if horizontalSizeClass == .compact { columnVisibility = .detailOnly }
                    } label: {
                        Label(language.text("work.buildInvoice"), systemImage: "doc.badge.plus")
                    }
                    Button {
                        selection = .newVisit
                        if horizontalSizeClass == .compact { columnVisibility = .detailOnly }
                    } label: {
                        Label(language.text("work.record"), systemImage: "plus")
                    }
                }
            }
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .visit(let id):
            if let visit = model.visits.first(where: { $0.id == id }) {
                VisitDetailView(visit: visit, language: language)
            } else {
                EmptyDetailView(
                    title: language.text("work.select.title"),
                    systemImage: "wrench.and.screwdriver",
                    description: language.text("work.select.message")
                )
            }
        case .newVisit:
            VisitEditorView(language: language) {
                selection = nil
                columnVisibility = .automatic
            }
        case .builder:
            InvoiceBuilderView(language: language) { package in
                previewPackage = package
                selection = .preview
            }
        case .preview:
            if let previewPackage {
                PDFPreviewIssueView(package: previewPackage, language: language) {
                    self.previewPackage = nil
                    selection = nil
                    columnVisibility = .automatic
                }
            } else {
                EmptyDetailView(
                    title: language.text("preview.title"),
                    systemImage: "doc.richtext",
                    description: language.text("preview.empty")
                )
            }
        case nil:
            EmptyDetailView(
                title: language.text("work.select.title"),
                systemImage: "wrench.and.screwdriver",
                description: language.text("work.select.message")
            )
        }
    }
}

private struct VisitRow: View {
    @EnvironmentObject private var model: AppModel
    let visit: Visit
    let language: AppLanguage

    private var amount: Int64 { visit.lines.reduce(0) { $0 + $1.net.yen } }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(localDateText(visit.workDate))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("¥" + amount.formatted(.number.grouping(.automatic)))
                    .font(.subheadline.monospacedDigit())
            }
            Text(visit.lines.first?.description ?? language.text("work.noDescription"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let site = model.sites.first(where: { $0.id == visit.siteID }) {
                Label(site.name, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            StateBadge(text: language.text("state.unbilled"), color: .orange)
        }
        .padding(.vertical, 4)
    }
}

private struct VisitDetailView: View {
    @EnvironmentObject private var model: AppModel
    let visit: Visit
    let language: AppLanguage

    var body: some View {
        List {
            Section {
                LabeledContent(language.text("field.date"), value: localDateText(visit.workDate))
                if let site = model.sites.first(where: { $0.id == visit.siteID }) {
                    LabeledContent(language.text("field.site"), value: site.name)
                }
            }
            Section(language.text("visit.lines")) {
                ForEach(visit.lines) { line in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(line.description).font(.headline)
                        HStack {
                            Text("\(line.quantity.description) \(line.unit) × \(yenText(line.unitPrice))")
                            Spacer()
                            Text(yenText(line.net)).font(.body.monospacedDigit())
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if !visit.note.isEmpty {
                Section(language.text("field.note")) { Text(visit.note) }
            }
        }
        .navigationTitle(language.text("visit.detail.title"))
    }
}

private struct VisitEditorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: StoreKitEntitlementStore
    let language: AppLanguage
    let onSaved: () -> Void
    @AppStorage("visitDraft.customerID") private var customerIDValue = ""
    @AppStorage("visitDraft.siteID") private var siteIDValue = ""
    @AppStorage("visitDraft.workDate") private var workDateValue = Date().timeIntervalSince1970
    @AppStorage("visitDraft.description") private var description = ""
    @AppStorage("visitDraft.quantity") private var quantity = "1"
    @AppStorage("visitDraft.unit") private var unit = "回"
    @AppStorage("visitDraft.unitPrice") private var unitPrice = ""
    @AppStorage("visitDraft.tax") private var taxBasisPoints = 1_000
    @AppStorage("visitDraft.note") private var note = ""
    @State private var saving = false
    @State private var showPro = false
    @State private var templateID: UUID?

    private var previousVisit: Visit? {
        model.visits
            .filter { visit in
                if case .draft = visit.state { return false }
                return true
            }
            .max { $0.workDate < $1.workDate }
    }

    private var availableSites: [Site] {
        guard let customerID else { return [] }
        return model.sites(for: customerID)
    }

    private var customerID: UUID? {
        get { UUID(uuidString: customerIDValue) }
        nonmutating set { customerIDValue = newValue?.uuidString ?? "" }
    }

    private var siteID: UUID? {
        get { UUID(uuidString: siteIDValue) }
        nonmutating set { siteIDValue = newValue?.uuidString ?? "" }
    }

    private var workDate: Date {
        get { Date(timeIntervalSince1970: workDateValue) }
        nonmutating set { workDateValue = newValue.timeIntervalSince1970 }
    }

    private var customerBinding: Binding<UUID?> {
        Binding(get: { customerID }, set: { customerID = $0 })
    }

    private var siteBinding: Binding<UUID?> {
        Binding(get: { siteID }, set: { siteID = $0 })
    }

    private var workDateBinding: Binding<Date> {
        Binding(get: { workDate }, set: { workDate = $0 })
    }

    var body: some View {
        Form {
            if !model.serviceTemplates.filter(\.isActive).isEmpty {
                Section(language.text("template.use")) {
                    Picker(language.text("template.choose"), selection: $templateID) {
                        Text(language.text("field.choose")).tag(UUID?.none)
                        ForEach(model.serviceTemplates.filter(\.isActive)) { template in
                            Text(template.title).tag(Optional(template.id))
                        }
                    }
                } footer: {
                    Text(store.hasPro ? language.text("template.useNote") : language.text("template.pro"))
                }
            }
            if previousVisit != nil {
                Section {
                    Button {
                        if store.hasPro { copyPrevious() } else { showPro = true }
                    } label: {
                        Label(language.text("visit.copyPrevious"), systemImage: "doc.on.doc")
                    }
                } footer: {
                    Text(store.hasPro ? language.text("visit.copyPrevious.note") : language.text("visit.copyPrevious.pro"))
                }
            }
            Section(language.text("visit.whereWhen")) {
                Picker(language.text("field.customer"), selection: customerBinding) {
                    Text(language.text("field.choose")).tag(UUID?.none)
                    ForEach(model.customers.filter(\.isActive)) { customer in
                        Text(customer.name).tag(Optional(customer.id))
                    }
                }
                Picker(language.text("field.site"), selection: siteBinding) {
                    Text(language.text("field.choose")).tag(UUID?.none)
                    ForEach(availableSites) { site in
                        Text(site.name).tag(Optional(site.id))
                    }
                }
                DatePicker(language.text("field.date"), selection: workDateBinding, displayedComponents: .date)
            }
            Section(language.text("visit.service")) {
                TextField(language.text("field.service"), text: $description)
                TextField(language.text("field.quantity"), text: $quantity)
                    .keyboardType(.decimalPad)
                TextField(language.text("field.unit"), text: $unit)
                TextField(language.text("field.unitPrice"), text: $unitPrice)
                    .keyboardType(.numberPad)
                Picker(language.text("field.tax"), selection: $taxBasisPoints) {
                    Text("10%").tag(1_000)
                    Text("8%").tag(800)
                    Text("0%").tag(0)
                }
                TextField(language.text("field.note"), text: $note, axis: .vertical)
            }
            Section {
                Button {
                    save()
                } label: {
                    if saving { ProgressView() } else { Text(language.text("action.saveVisit")) }
                }
                .disabled(
                    customerID == nil || siteID == nil ||
                    description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    unitPrice.isEmpty || saving
                )
            } footer: {
                Text(language.text("visit.autosaveNote"))
            }
        }
        .navigationTitle(language.text("visit.editor.title"))
        .onAppear {
            if customerID == nil || !model.customers.contains(where: { $0.id == customerID && $0.isActive }) {
                customerID = model.customers.first(where: \.isActive)?.id
            }
            if let customerID,
               siteID == nil || !model.sites(for: customerID).contains(where: { $0.id == siteID }) {
                siteID = model.sites(for: customerID).first?.id
            }
        }
        .onChange(of: customerID) { _, newValue in
            siteID = newValue.flatMap { model.sites(for: $0).first?.id }
        }
        .sheet(isPresented: $showPro) {
            ProSheet(language: language).environmentObject(store)
        }
        .onChange(of: templateID) { _, id in
            guard let id,
                  let template = model.serviceTemplates.first(where: { $0.id == id }) else { return }
            guard store.hasPro else {
                templateID = nil
                showPro = true
                return
            }
            description = template.title
            unit = template.unit
            unitPrice = String(template.unitPrice.yen)
            taxBasisPoints = template.taxRate.basisPoints
        }
    }

    private func copyPrevious() {
        guard let visit = previousVisit, let line = visit.lines.first else { return }
        customerID = visit.customerID
        siteID = visit.siteID
        description = line.description
        quantity = line.quantity.description
        unit = line.unit
        unitPrice = String(line.unitPrice.yen)
        taxBasisPoints = line.taxRate.basisPoints
        note = visit.note
    }

    private func save() {
        guard let customerID, let siteID else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let rate = TaxRate.launchCatalog.first(where: { $0.basisPoints == taxBasisPoints }) ?? .standard10
                try await model.recordVisit(
                    customerID: customerID,
                    siteID: siteID,
                    date: workDate,
                    description: description,
                    quantity: quantity,
                    unit: unit,
                    unitPrice: unitPrice,
                    taxRate: rate,
                    note: note
                )
                description = ""
                quantity = "1"
                unit = "回"
                unitPrice = ""
                note = ""
                workDate = Date()
                onSaved()
            } catch {
                model.errorMessage = String(describing: error)
            }
        }
    }
}

private struct InvoiceBuilderView: View {
    @EnvironmentObject private var model: AppModel
    let language: AppLanguage
    let onPreview: (PreviewPackage) -> Void
    @AppStorage("invoiceDraft.customerID") private var customerIDValue = ""
    @AppStorage("invoiceDraft.start") private var startValue = (
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    ).timeIntervalSince1970
    @AppStorage("invoiceDraft.end") private var endValue = Date().timeIntervalSince1970
    @AppStorage("invoiceDraft.selected") private var selectedValue = ""
    @State private var loading = false

    private var customerID: UUID? {
        get { UUID(uuidString: customerIDValue) }
        nonmutating set { customerIDValue = newValue?.uuidString ?? "" }
    }

    private var start: Date {
        get { Date(timeIntervalSince1970: startValue) }
        nonmutating set { startValue = newValue.timeIntervalSince1970 }
    }

    private var end: Date {
        get { Date(timeIntervalSince1970: endValue) }
        nonmutating set { endValue = newValue.timeIntervalSince1970 }
    }

    private var selected: Set<UUID> {
        get { Set(selectedValue.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }
        nonmutating set {
            selectedValue = newValue.map(\.uuidString).sorted().joined(separator: ",")
        }
    }

    private var customerBinding: Binding<UUID?> {
        Binding(get: { customerID }, set: { customerID = $0 })
    }

    private var startBinding: Binding<Date> {
        Binding(get: { start }, set: { start = $0 })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { end }, set: { end = $0 })
    }

    private var eligible: [Visit] {
        guard let customerID else { return [] }
        return model.visits.filter {
            $0.customerID == customerID && $0.state == .unbilled &&
            dateValue($0.workDate) >= Calendar.current.startOfDay(for: start) &&
            dateValue($0.workDate) <= Calendar.current.startOfDay(for: end)
        }
    }

    private var selectedVisits: [Visit] { eligible.filter { selected.contains($0.id) } }

    private var estimatedTotals: (subtotal: Int64, tax: Int64, total: Int64) {
        let subtotal = selectedVisits.flatMap(\.lines).reduce(Int64(0)) { $0 + $1.net.yen }
        let groups = Dictionary(grouping: selectedVisits.flatMap(\.lines), by: { $0.taxRate.basisPoints })
        let tax = groups.values.reduce(Int64(0)) { partial, lines in
            let taxable = lines.reduce(Int64(0)) { $0 + $1.net.yen }
            guard let money = try? Money(yen: taxable),
                  let rate = lines.first?.taxRate,
                  let amount = try? InvoiceCalculator.tax(
                    for: money,
                    rate: rate,
                    rounding: model.business?.taxRounding ?? .floor
                  ) else { return partial }
            return partial + amount.yen
        }
        return (subtotal, tax, subtotal + tax)
    }

    var body: some View {
        Form {
            Section(language.text("builder.period")) {
                Picker(language.text("field.customer"), selection: customerBinding) {
                    Text(language.text("field.choose")).tag(UUID?.none)
                    ForEach(model.customers.filter(\.isActive)) { customer in
                        Text(customer.name).tag(Optional(customer.id))
                    }
                }
                DatePicker(language.text("field.startDate"), selection: startBinding, displayedComponents: .date)
                DatePicker(language.text("field.endDate"), selection: endBinding, in: start..., displayedComponents: .date)
            }
            Section(language.text("builder.unbilled")) {
                if eligible.isEmpty {
                    Text(language.text("builder.empty")).foregroundStyle(.secondary)
                } else {
                    ForEach(eligible) { visit in
                        Button {
                            var updated = selected
                            if updated.contains(visit.id) { updated.remove(visit.id) }
                            else { updated.insert(visit.id) }
                            selected = updated
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(visit.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(visit.id) ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading) {
                                    Text(localDateText(visit.workDate))
                                    Text(visit.lines.first?.description ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let site = model.sites.first(where: { $0.id == visit.siteID }) {
                                        Text(site.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("¥" + visit.lines.reduce(0) { $0 + $1.net.yen }.formatted(.number.grouping(.automatic)))
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(
                            language.text(
                                selected.contains(visit.id)
                                    ? "accessibility.selected"
                                    : "accessibility.notSelected"
                            )
                        )
                        .accessibilityAddTraits(selected.contains(visit.id) ? .isSelected : [])
                    }
                }
            }
            if !selected.isEmpty {
                Section(language.text("builder.summary")) {
                    LabeledContent(
                        language.text("builder.selectedCount"),
                        value: String(selectedVisits.count)
                    )
                    LabeledContent(
                        language.text("builder.subtotal"),
                        value: "¥" + estimatedTotals.subtotal.formatted(.number.grouping(.automatic))
                    )
                    LabeledContent(
                        language.text("builder.tax"),
                        value: "¥" + estimatedTotals.tax.formatted(.number.grouping(.automatic))
                    )
                    LabeledContent(
                        language.text("builder.total"),
                        value: "¥" + estimatedTotals.total.formatted(.number.grouping(.automatic))
                    )
                    .fontWeight(.semibold)
                    if model.business?.registrationNumberIsValid != true {
                        Label(language.text("builder.registrationWarning"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section {
                Button {
                    prepare()
                } label: {
                    if loading { ProgressView() } else { Text(language.text("builder.preview")) }
                }
                .disabled(customerID == nil || selected.isEmpty || loading)
            } footer: {
                Text(language.text("builder.previewNote"))
            }
        }
        .navigationTitle(language.text("builder.title"))
        .onAppear { initializeSelection() }
        .onChange(of: customerID) { _, _ in selectAllEligible() }
        .onChange(of: start) { _, _ in selectAllEligible() }
        .onChange(of: end) { _, _ in selectAllEligible() }
    }

    private func initializeSelection() {
        if customerID == nil || !model.customers.contains(where: { $0.id == customerID && $0.isActive }) {
            customerID = model.customers.first(where: \.isActive)?.id
        }
        let calendar = Calendar.current
        if let range = calendar.range(of: .day, in: .month, for: start) {
            end = calendar.date(bySetting: .day, value: range.count, of: start) ?? Date()
        }
        selectAllEligible()
    }

    private func selectAllEligible() {
        selected = Set(eligible.map(\.id))
    }

    private func prepare() {
        guard let customerID else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let package = try await model.preparePreview(
                    customerID: customerID,
                    selectedVisitIDs: selected,
                    coveredStart: start,
                    coveredEnd: end
                )
                onPreview(package)
            } catch {
                model.errorMessage = String(describing: error)
            }
        }
    }
}
