import InvoiceDomain
import SwiftUI

private enum WorkDestination: Hashable {
    case visit(UUID)
    case newVisit
    case builder
    case preview
}

struct WorkSplitView: View {
    @EnvironmentObject private var model: AppModel
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
                        columnVisibility = .detailOnly
                    } label: {
                        Label(language.text("work.buildInvoice"), systemImage: "doc.badge.plus")
                    }
                    Button {
                        selection = .newVisit
                        columnVisibility = .detailOnly
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
    let language: AppLanguage
    let onSaved: () -> Void
    @State private var customerID: UUID?
    @State private var siteID: UUID?
    @State private var workDate = Date()
    @State private var description = ""
    @State private var quantity = "1"
    @State private var unit = "回"
    @State private var unitPrice = ""
    @State private var taxBasisPoints = 1_000
    @State private var note = ""
    @State private var saving = false

    private var availableSites: [Site] {
        guard let customerID else { return [] }
        return model.sites(for: customerID)
    }

    var body: some View {
        Form {
            Section(language.text("visit.whereWhen")) {
                Picker(language.text("field.customer"), selection: $customerID) {
                    Text(language.text("field.choose")).tag(UUID?.none)
                    ForEach(model.customers.filter(\.isActive)) { customer in
                        Text(customer.name).tag(Optional(customer.id))
                    }
                }
                Picker(language.text("field.site"), selection: $siteID) {
                    Text(language.text("field.choose")).tag(UUID?.none)
                    ForEach(availableSites) { site in
                        Text(site.name).tag(Optional(site.id))
                    }
                }
                DatePicker(language.text("field.date"), selection: $workDate, displayedComponents: .date)
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
            if customerID == nil { customerID = model.customers.first(where: \.isActive)?.id }
            if siteID == nil, let customerID { siteID = model.sites(for: customerID).first?.id }
        }
        .onChange(of: customerID) { _, newValue in
            siteID = newValue.flatMap { model.sites(for: $0).first?.id }
        }
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
    @State private var customerID: UUID?
    @State private var start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var end = Date()
    @State private var selected: Set<UUID> = []
    @State private var loading = false

    private var eligible: [Visit] {
        guard let customerID else { return [] }
        return model.visits.filter {
            $0.customerID == customerID && $0.state == .unbilled &&
            dateValue($0.workDate) >= Calendar.current.startOfDay(for: start) &&
            dateValue($0.workDate) <= Calendar.current.startOfDay(for: end)
        }
    }

    var body: some View {
        Form {
            Section(language.text("builder.period")) {
                Picker(language.text("field.customer"), selection: $customerID) {
                    Text(language.text("field.choose")).tag(UUID?.none)
                    ForEach(model.customers.filter(\.isActive)) { customer in
                        Text(customer.name).tag(Optional(customer.id))
                    }
                }
                DatePicker(language.text("field.startDate"), selection: $start, displayedComponents: .date)
                DatePicker(language.text("field.endDate"), selection: $end, in: start..., displayedComponents: .date)
            }
            Section(language.text("builder.unbilled")) {
                if eligible.isEmpty {
                    Text(language.text("builder.empty")).foregroundStyle(.secondary)
                } else {
                    ForEach(eligible) { visit in
                        Button {
                            if selected.contains(visit.id) { selected.remove(visit.id) }
                            else { selected.insert(visit.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(visit.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(visit.id) ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading) {
                                    Text(localDateText(visit.workDate))
                                    Text(visit.lines.first?.description ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("¥" + visit.lines.reduce(0) { $0 + $1.net.yen }.formatted(.number.grouping(.automatic)))
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
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
        if customerID == nil { customerID = model.customers.first(where: \.isActive)?.id }
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
