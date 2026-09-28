import Foundation
import InvoiceBackup
import InvoiceDomain
import InvoicePDF
import InvoicePersistence

struct PreviewPackage: Identifiable {
    let id = UUID()
    let draft: InvoiceDraft
    let business: BusinessProfile
    let customer: Customer
    let sites: [UUID: Site]
    let visits: [Visit]
    let invoice: IssuedInvoice
    let pdfData: Data
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var business: BusinessProfile?
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var sites: [Site] = []
    @Published private(set) var visits: [Visit] = []
    @Published private(set) var invoices: [IssuedInvoice] = []
    @Published private(set) var drafts: [InvoiceDraft] = []
    @Published var isBusy = false
    @Published var errorMessage: String?

    private let root: URL
    private let database: AppDatabase?
    private let issueService: IssueService?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        root = base.appendingPathComponent("DatedServiceInvoice", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let createdDatabase = try AppDatabase(path: root.appendingPathComponent("data.sqlite").path)
            database = createdDatabase
            issueService = IssueService(database: createdDatabase, filesRoot: root) { invoice in
                try CanonicalPDFRenderer.render(invoice: invoice, language: "ja")
            }
        } catch {
            database = nil
            issueService = nil
            errorMessage = String(describing: error)
        }
    }

    func bootstrap() async {
        guard let database, let issueService else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            purgeCompletedDeletionQuarantines()
            try await issueService.recoverPendingFileOperations()
            let existingCustomers = try await database.customers()
            if existingCustomers.isEmpty,
               !UserDefaults.standard.bool(forKey: "didLoadJapaneseSample") {
                try await loadJapaneseSample(database: database)
                UserDefaults.standard.set(true, forKey: "didLoadJapaneseSample")
            }
            try await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func refresh() async throws {
        guard let database else { throw InvoiceError.corruptData("database_unavailable") }
        async let loadedBusiness = database.business()
        async let loadedCustomers = database.customers()
        async let loadedVisits = database.visits()
        async let loadedInvoices = database.invoices()
        async let loadedDrafts = database.drafts()
        let customerRows = try await loadedCustomers
        var siteRows: [Site] = []
        for customer in customerRows {
            siteRows.append(contentsOf: try await database.sites(customerID: customer.id))
        }
        business = try await loadedBusiness
        customers = customerRows
        sites = siteRows
        visits = try await loadedVisits
        invoices = try await loadedInvoices
        drafts = try await loadedDrafts
    }

    func sites(for customerID: UUID) -> [Site] {
        sites.filter { $0.customerID == customerID && $0.isActive }
    }

    func saveBusiness(_ profile: BusinessProfile) async {
        await perform {
            guard let database = self.database else { throw InvoiceError.corruptData("database_unavailable") }
            try await database.saveBusiness(profile)
            try await self.refresh()
        }
    }

    func addCustomer(name: String, address: String, hasPro: Bool) async throws -> Customer {
        guard let database else { throw InvoiceError.corruptData("database_unavailable") }
        let customer = Customer(name: name, billingAddress: address)
        try await database.saveCustomer(customer, hasPro: hasPro)
        try await refresh()
        return customer
    }

    func addSite(customerID: UUID, name: String, address: String) async throws -> Site {
        guard let database else { throw InvoiceError.corruptData("database_unavailable") }
        let site = Site(customerID: customerID, name: name, address: address)
        try await database.saveSite(site)
        try await refresh()
        return site
    }

    func recordVisit(
        customerID: UUID,
        siteID: UUID,
        date: Date,
        description: String,
        quantity: String,
        unit: String,
        unitPrice: String,
        taxRate: TaxRate,
        note: String
    ) async throws {
        guard let database else { throw InvoiceError.corruptData("database_unavailable") }
        let rounding = business?.lineRounding ?? .halfUp
        let line = try VisitLine(
            position: 0,
            description: description,
            quantity: Quantity(decimalString: quantity),
            unit: unit,
            unitPrice: Money(yen: Int64(unitPrice) ?? -1),
            taxRate: taxRate,
            lineRounding: rounding
        )
        var visit = Visit(
            customerID: customerID,
            siteID: siteID,
            workDate: try localDate(date),
            note: note,
            lines: [line]
        )
        try visit.complete()
        try await database.saveVisit(visit)
        try await refresh()
    }

    func preparePreview(
        customerID: UUID,
        selectedVisitIDs: Set<UUID>,
        coveredStart: Date,
        coveredEnd: Date
    ) async throws -> PreviewPackage {
        guard let database else { throw InvoiceError.corruptData("database_unavailable") }
        guard let business else { throw InvoiceError.missingRequiredField("business") }
        guard let customer = customers.first(where: { $0.id == customerID }) else {
            throw InvoiceError.missingRequiredField("customer")
        }
        let selected = visits.filter { selectedVisitIDs.contains($0.id) }
        let issueDate = try localDate(Date())
        let due = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: customer.paymentTermDays,
            to: Date()
        ) ?? Date()
        let draft = InvoiceDraft(
            customerID: customerID,
            selectedVisitIDs: selected.map(\.id),
            coveredStart: try localDate(coveredStart),
            coveredEnd: try localDate(coveredEnd),
            issueDate: issueDate,
            dueDate: try localDate(due)
        )
        try await database.saveDraft(draft)
        let number = try await database.proposedNumber(issueDate: issueDate, prefix: business.invoicePrefix)
        let siteMap = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0) })
        let invoice = try InvoiceCalculator.snapshot(
            number: number,
            draft: draft,
            business: business,
            customer: customer,
            sites: siteMap,
            visits: selected
        )
        let pdf = try CanonicalPDFRenderer.render(invoice: invoice, language: "ja")
        return PreviewPackage(
            draft: draft,
            business: business,
            customer: customer,
            sites: siteMap,
            visits: selected,
            invoice: invoice,
            pdfData: pdf
        )
    }

    func issue(_ package: PreviewPackage, hasPro: Bool) async throws -> IssuedInvoice {
        guard let issueService else { throw InvoiceError.corruptData("database_unavailable") }
        let invoice = try await issueService.issue(
            draft: package.draft,
            business: package.business,
            customer: package.customer,
            sites: package.sites,
            visits: package.visits,
            hasPro: hasPro
        )
        try await refresh()
        return invoice
    }

    func canonicalPDF(for invoice: IssuedInvoice) async throws -> Data {
        guard let issueService else { throw InvoiceError.corruptData("database_unavailable") }
        return try await issueService.canonicalPDFData(for: invoice)
    }

    func markPaid(_ invoice: IssuedInvoice) async {
        await perform {
            guard let database = self.database else { throw InvoiceError.corruptData("database_unavailable") }
            try await database.markInvoicePaid(id: invoice.id, paidDate: try self.localDate(Date()))
            try await self.refresh()
        }
    }

    func void(_ invoice: IssuedInvoice) async {
        await perform {
            guard let database = self.database else { throw InvoiceError.corruptData("database_unavailable") }
            try await database.voidInvoice(id: invoice.id, returnVisitsToUnbilled: true)
            try await self.refresh()
        }
    }

    func exportBackup() async throws -> FileWrapper {
        guard let database else { throw InvoiceError.corruptData("database_unavailable") }
        let package = FileManager.default.temporaryDirectory
            .appendingPathComponent("Invoice-Backup-\(UUID().uuidString).datedinvoicebackup", isDirectory: true)
        try await BackupService(database: database, filesRoot: root).export(to: package, appBuild: "1")
        defer { try? FileManager.default.removeItem(at: package) }
        return try FileWrapper(url: package, options: .immediate)
    }

    func restoreBackup(from url: URL) async {
        await perform {
            guard let database = self.database else { throw InvoiceError.corruptData("database_unavailable") }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            _ = try await BackupService(database: database, filesRoot: self.root)
                .restore(packageURL: url, mode: .replace)
            try await self.refresh()
        }
    }

    func deleteAllData() async {
        await perform {
            guard let database = self.database else { throw InvoiceError.corruptData("database_unavailable") }
            let quarantine = self.root.appendingPathComponent(
                ".Deletion-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
            var moved: [(source: URL, quarantined: URL)] = []
            do {
                for directory in ["Invoices", "Staging", "Recovery"] {
                    let source = self.root.appendingPathComponent(directory, isDirectory: true)
                    guard FileManager.default.fileExists(atPath: source.path) else { continue }
                    let destination = quarantine.appendingPathComponent(directory, isDirectory: true)
                    try FileManager.default.moveItem(at: source, to: destination)
                    moved.append((source, destination))
                }
                try await database.deleteAllDomainData()
            } catch {
                for entry in moved.reversed() where FileManager.default.fileExists(atPath: entry.quarantined.path) {
                    try? FileManager.default.moveItem(at: entry.quarantined, to: entry.source)
                }
                try? FileManager.default.removeItem(at: quarantine)
                throw error
            }
            try? FileManager.default.removeItem(at: quarantine)
            try await self.refresh()
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do { try await work() } catch { errorMessage = String(describing: error) }
    }

    private func purgeCompletedDeletionQuarantines() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(".Deletion-") {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private func localDate(_ date: Date) throws -> LocalDate {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            throw InvoiceError.invalidDate
        }
        return try LocalDate(year: year, month: month, day: day)
    }

    private func loadJapaneseSample(database: AppDatabase) async throws {
        let profile = BusinessProfile(
            issuerName: "青空メンテナンス",
            postalAddress: "東京都千代田区1-2-3",
            registrationNumber: "T1234567890123",
            bankDetails: "青空銀行 本店 普通 1234567",
            invoicePrefix: "AOZORA"
        )
        let customer = Customer(
            name: "山田商事株式会社",
            billingAddress: "東京都新宿区4-5-6",
            closingDay: 31,
            paymentTermDays: 30
        )
        let site = Site(customerID: customer.id, name: "新宿本店", address: "東京都新宿区4-5-6")
        try await database.saveBusiness(profile)
        try await database.saveCustomer(customer)
        try await database.saveSite(site)

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month], from: now)
        let year = components.year ?? 2026
        let month = components.month ?? 9
        var sampleVisits: [Visit] = []
        for (index, day) in [5, 12, 19].enumerated() {
            let line = try VisitLine(
                position: 0,
                description: index == 1 ? "空調フィルター清掃" : "定期清掃",
                quantity: Quantity(decimalString: "1"),
                unit: "回",
                unitPrice: Money(yen: index == 1 ? 15_000 : 12_000),
                taxRate: .standard10,
                lineRounding: .halfUp
            )
            var visit = Visit(
                customerID: customer.id,
                siteID: site.id,
                workDate: try LocalDate(year: year, month: month, day: day),
                note: "サンプル作業",
                lines: [line]
            )
            try visit.complete()
            try await database.saveVisit(visit)
            sampleVisits.append(visit)
        }
        let endDay = calendar.range(of: .day, in: .month, for: now)?.count ?? 28
        let draft = InvoiceDraft(
            customerID: customer.id,
            selectedVisitIDs: sampleVisits.map(\.id),
            coveredStart: try LocalDate(year: year, month: month, day: 1),
            coveredEnd: try LocalDate(year: year, month: month, day: endDay),
            issueDate: try localDate(now),
            dueDate: try localDate(calendar.date(byAdding: .day, value: 30, to: now) ?? now)
        )
        try await database.saveDraft(draft)
    }
}
