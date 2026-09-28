import Foundation
import GRDB
import InvoiceDomain

public actor AppDatabase {
    public static let schemaVersion = 3

    private let writer: DatabasePool

    public init(path: String) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = FULL")
        }
        writer = try DatabasePool(path: path, configuration: configuration)
        try Self.migrator.migrate(writer)
    }

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "business_profile") { t in
                t.column("id", .text).primaryKey()
                t.column("payload", .blob).notNull()
                t.column("updated_at", .double).notNull()
            }
            try db.create(table: "customer") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("is_active", .boolean).notNull().indexed()
                t.column("payload", .blob).notNull()
                t.column("updated_at", .double).notNull()
            }
            try db.create(table: "site") { t in
                t.column("id", .text).primaryKey()
                t.column("customer_id", .text).notNull().indexed()
                    .references("customer", onDelete: .restrict)
                t.column("is_active", .boolean).notNull()
                t.column("payload", .blob).notNull()
                t.column("updated_at", .double).notNull()
            }
            try db.create(table: "visit") { t in
                t.column("id", .text).primaryKey()
                t.column("customer_id", .text).notNull().indexed()
                    .references("customer", onDelete: .restrict)
                t.column("site_id", .text).notNull().indexed()
                    .references("site", onDelete: .restrict)
                t.column("work_date", .text).notNull().indexed()
                t.column("state", .text).notNull().indexed()
                t.column("billed_invoice_id", .text).indexed()
                t.column("payload", .blob).notNull()
                t.column("updated_at", .double).notNull()
            }
            try db.create(table: "invoice_draft") { t in
                t.column("id", .text).primaryKey()
                t.column("customer_id", .text).notNull().indexed()
                t.column("payload", .blob).notNull()
                t.column("updated_at", .double).notNull()
            }
            try db.create(table: "issued_invoice") { t in
                t.column("id", .text).primaryKey()
                t.column("number", .text).notNull().unique()
                t.column("customer_id", .text).notNull().indexed()
                t.column("status", .text).notNull().indexed()
                t.column("issue_date", .text).notNull().indexed()
                t.column("pdf_relative_path", .text)
                t.column("pdf_sha256", .text)
                t.column("payload", .blob).notNull()
                t.column("issued_at", .double).notNull()
            }
            try db.create(table: "invoice_visit_link") { t in
                t.column("invoice_id", .text).notNull()
                    .references("issued_invoice", onDelete: .restrict)
                t.column("visit_id", .text).notNull().indexed()
                    .references("visit", onDelete: .restrict)
                t.primaryKey(["invoice_id", "visit_id"])
            }
            try db.create(table: "file_operation_journal") { t in
                t.column("id", .text).primaryKey()
                t.column("invoice_id", .text).notNull().indexed()
                    .references("issued_invoice", onDelete: .restrict)
                t.column("staged_path", .text).notNull()
                t.column("final_path", .text).notNull()
                t.column("sha256", .text).notNull()
                t.column("state", .text).notNull().indexed()
                t.column("created_at", .double).notNull()
            }
            try db.create(table: "invoice_sequence") { t in
                t.column("year", .integer).primaryKey()
                t.column("next_value", .integer).notNull()
            }
            try db.create(table: "entitlement_usage") { t in
                t.column("singleton", .integer).primaryKey()
                t.column("first_clean_invoice_id", .text)
            }
            try db.create(table: "app_setting") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
            try db.create(table: "migration_log") { t in
                t.column("identifier", .text).primaryKey()
                t.column("applied_at", .double).notNull()
                t.column("app_build", .text).notNull()
            }
            try db.execute(
                sql: "INSERT INTO entitlement_usage(singleton, first_clean_invoice_id) VALUES (1, NULL)"
            )
            try db.execute(
                sql: "INSERT INTO migration_log(identifier, applied_at, app_build) VALUES (?, ?, ?)",
                arguments: ["v1", Date().timeIntervalSince1970, "schema-v1"]
            )
        }
        migrator.registerMigration("v2-active-invoice-link-guard") { db in
            try db.execute(sql: """
                CREATE TRIGGER prevent_duplicate_active_invoice_link
                BEFORE INSERT ON invoice_visit_link
                WHEN EXISTS (
                    SELECT 1
                    FROM invoice_visit_link AS link
                    JOIN issued_invoice AS invoice ON invoice.id = link.invoice_id
                    WHERE link.visit_id = NEW.visit_id
                      AND invoice.status IN ('issued', 'paid', 'needsRecovery')
                )
                BEGIN
                    SELECT RAISE(ABORT, 'visit_already_linked_to_active_invoice');
                END
                """)
            try db.execute(
                sql: "INSERT INTO migration_log(identifier, applied_at, app_build) VALUES (?, ?, ?)",
                arguments: ["v2-active-invoice-link-guard", Date().timeIntervalSince1970, "schema-v2"]
            )
        }
        migrator.registerMigration("v3-active-invoice-status-guard") { db in
            try db.execute(sql: """
                CREATE TRIGGER prevent_duplicate_active_invoice_reactivation
                BEFORE UPDATE OF status ON issued_invoice
                WHEN NEW.status IN ('issued', 'paid', 'needsRecovery')
                 AND OLD.status NOT IN ('issued', 'paid', 'needsRecovery')
                 AND EXISTS (
                    SELECT 1
                    FROM invoice_visit_link AS candidate
                    JOIN invoice_visit_link AS other ON other.visit_id = candidate.visit_id
                    JOIN issued_invoice AS other_invoice ON other_invoice.id = other.invoice_id
                    WHERE candidate.invoice_id = NEW.id
                      AND other.invoice_id <> NEW.id
                      AND other_invoice.status IN ('issued', 'paid', 'needsRecovery')
                 )
                BEGIN
                    SELECT RAISE(ABORT, 'invoice_reactivation_would_duplicate_active_link');
                END
                """)
            try db.execute(
                sql: "INSERT INTO migration_log(identifier, applied_at, app_build) VALUES (?, ?, ?)",
                arguments: ["v3-active-invoice-status-guard", Date().timeIntervalSince1970, "schema-v3"]
            )
        }
        return migrator
    }

    public func saveBusiness(_ profile: BusinessProfile) throws {
        let payload = try Self.encode(profile)
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO business_profile(id, payload, updated_at) VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at
                """, arguments: [profile.id.uuidString.lowercased(), payload, Date().timeIntervalSince1970])
        }
    }

    public func business() throws -> BusinessProfile? {
        try writer.read { db in
            guard let data: Data = try Data.fetchOne(db, sql: "SELECT payload FROM business_profile LIMIT 1") else { return nil }
            return try Self.decode(BusinessProfile.self, from: data)
        }
    }

    public func saveCustomer(_ customer: Customer, hasPro: Bool = false) throws {
        try customer.validate()
        let name = customer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = try Self.encode(customer)
        try writer.write { db in
            if customer.isActive, !hasPro {
                let activeOthers = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM customer WHERE is_active = 1 AND id <> ?",
                    arguments: [customer.id.uuidString.lowercased()]
                ) ?? 0
                guard activeOthers < 2 else { throw InvoiceError.entitlementRequired }
            }
            try db.execute(sql: """
                INSERT INTO customer(id, name, is_active, payload, updated_at) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, is_active = excluded.is_active,
                    payload = excluded.payload, updated_at = excluded.updated_at
                """, arguments: [customer.id.uuidString.lowercased(), name, customer.isActive, payload, Date().timeIntervalSince1970])
        }
    }

    public func customers(activeOnly: Bool = false) throws -> [Customer] {
        try writer.read { db in
            let sql = activeOnly
                ? "SELECT payload FROM customer WHERE is_active = 1 ORDER BY name, id"
                : "SELECT payload FROM customer ORDER BY is_active DESC, name, id"
            return try Data.fetchAll(db, sql: sql).map { try Self.decode(Customer.self, from: $0) }
        }
    }

    public func activeCustomerCount() throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM customer WHERE is_active = 1") ?? 0
        }
    }

    public func saveSite(_ site: Site) throws {
        try site.validate()
        let payload = try Self.encode(site)
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO site(id, customer_id, is_active, payload, updated_at) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET customer_id = excluded.customer_id,
                    is_active = excluded.is_active, payload = excluded.payload,
                    updated_at = excluded.updated_at
                """, arguments: [site.id.uuidString.lowercased(), site.customerID.uuidString.lowercased(), site.isActive, payload, Date().timeIntervalSince1970])
        }
    }

    public func sites(customerID: UUID) throws -> [Site] {
        try writer.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM site WHERE customer_id = ? ORDER BY is_active DESC, id", arguments: [customerID.uuidString.lowercased()])
                .map { try Self.decode(Site.self, from: $0) }
        }
    }

    public func saveVisit(_ visit: Visit) throws {
        let payload = try Self.encode(visit)
        let columns = Self.visitStateColumns(visit.state)
        try writer.write { db in
            if let stored = try Self.fetchVisit(db: db, id: visit.id) {
                switch stored.state {
                case .draft:
                    guard visit.state == .draft || visit.state == .unbilled else {
                        throw InvoiceError.invalidTransition
                    }
                case .unbilled:
                    guard visit.state == .unbilled else {
                        throw InvoiceError.invalidTransition
                    }
                case .billed:
                    guard visit.state == stored.state else {
                        throw InvoiceError.invalidTransition
                    }
                }
            } else if case .billed = visit.state {
                throw InvoiceError.invalidTransition
            }
            try db.execute(sql: """
                INSERT INTO visit(id, customer_id, site_id, work_date, state, billed_invoice_id, payload, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET customer_id = excluded.customer_id,
                    site_id = excluded.site_id, work_date = excluded.work_date,
                    state = excluded.state, billed_invoice_id = excluded.billed_invoice_id,
                    payload = excluded.payload, updated_at = excluded.updated_at
                """, arguments: [visit.id.uuidString.lowercased(), visit.customerID.uuidString.lowercased(), visit.siteID.uuidString.lowercased(), visit.workDate.description, columns.state, columns.invoiceID, payload, visit.updatedAt.timeIntervalSince1970])
        }
    }

    public func visits(customerID: UUID? = nil, unbilledOnly: Bool = false) throws -> [Visit] {
        try writer.read { db in
            let payloads: [Data]
            switch (customerID, unbilledOnly) {
            case (.some(let id), true):
                payloads = try Data.fetchAll(
                    db,
                    sql: "SELECT payload FROM visit WHERE customer_id = ? AND state = 'unbilled' ORDER BY work_date, id",
                    arguments: [id.uuidString.lowercased()]
                )
            case (.some(let id), false):
                payloads = try Data.fetchAll(
                    db,
                    sql: "SELECT payload FROM visit WHERE customer_id = ? ORDER BY work_date, id",
                    arguments: [id.uuidString.lowercased()]
                )
            case (.none, true):
                payloads = try Data.fetchAll(db, sql: "SELECT payload FROM visit WHERE state = 'unbilled' ORDER BY work_date, id")
            case (.none, false):
                payloads = try Data.fetchAll(db, sql: "SELECT payload FROM visit ORDER BY work_date, id")
            }
            return try payloads.map { try Self.decode(Visit.self, from: $0) }
        }
    }

    public func saveDraft(_ draft: InvoiceDraft) throws {
        let payload = try Self.encode(draft)
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO invoice_draft(id, customer_id, payload, updated_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET customer_id = excluded.customer_id,
                    payload = excluded.payload, updated_at = excluded.updated_at
                """, arguments: [draft.id.uuidString.lowercased(), draft.customerID.uuidString.lowercased(), payload, draft.updatedAt.timeIntervalSince1970])
        }
    }

    public func drafts() throws -> [InvoiceDraft] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, customer_id, payload, updated_at FROM invoice_draft ORDER BY updated_at DESC, id"
            ).map(Self.validatedDraft)
        }
    }

    public func draft(id: UUID) throws -> InvoiceDraft? {
        try writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT id, customer_id, payload, updated_at FROM invoice_draft WHERE id = ?",
                arguments: [id.uuidString.lowercased()]
            ) else { return nil }
            return try Self.validatedDraft(row)
        }
    }

    public func invoices() throws -> [IssuedInvoice] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, number, customer_id, status, issue_date,
                           pdf_relative_path, pdf_sha256, payload, issued_at
                    FROM issued_invoice ORDER BY issue_date DESC, number DESC
                    """
            ).map(Self.validatedIssuedInvoice)
        }
    }

    public func invoice(id: UUID) throws -> IssuedInvoice? {
        try writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, number, customer_id, status, issue_date,
                           pdf_relative_path, pdf_sha256, payload, issued_at
                    FROM issued_invoice WHERE id = ?
                    """,
                arguments: [id.uuidString.lowercased()]
            ) else { return nil }
            return try Self.validatedIssuedInvoice(row)
        }
    }

    public func canonicalPDFReference(invoiceID: UUID) throws -> CanonicalPDFReference {
        try writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, number, customer_id, status, issue_date,
                           pdf_relative_path, pdf_sha256, payload, issued_at
                    FROM issued_invoice WHERE id = ?
                    """,
                arguments: [invoiceID.uuidString.lowercased()]
            ) else { throw InvoiceError.corruptData("missing_invoice") }
            let invoice = try Self.validatedIssuedInvoice(row)
            guard let relativePath = invoice.pdfRelativePath,
                  let sha256 = invoice.pdfSHA256 else {
                throw InvoiceError.corruptData("missing_canonical_pdf_reference")
            }
            return CanonicalPDFReference(
                invoiceID: invoice.id.uuidString.lowercased(),
                relativePath: relativePath,
                sha256: sha256.lowercased()
            )
        }
    }

    public func deleteDraft(id: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM invoice_draft WHERE id = ?", arguments: [id.uuidString.lowercased()])
        }
    }

    public func deleteAllDomainData(committedDeletionID: UUID? = nil) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM file_operation_journal")
            try db.execute(sql: "DELETE FROM invoice_visit_link")
            try db.execute(sql: "DELETE FROM issued_invoice")
            try db.execute(sql: "DELETE FROM invoice_draft")
            try db.execute(sql: "DELETE FROM visit")
            try db.execute(sql: "DELETE FROM site")
            try db.execute(sql: "DELETE FROM customer")
            try db.execute(sql: "DELETE FROM business_profile")
            try db.execute(sql: "DELETE FROM invoice_sequence")
            try db.execute(sql: "DELETE FROM app_setting")
            try db.execute(sql: "UPDATE entitlement_usage SET first_clean_invoice_id = NULL WHERE singleton = 1")
            if let committedDeletionID {
                try db.execute(
                    sql: "INSERT INTO app_setting(key, value) VALUES ('committed_deletion_id', ?)",
                    arguments: [committedDeletionID.uuidString.lowercased()]
                )
            }
        }
    }

    public func committedDeletionID() throws -> UUID? {
        try writer.read { db in
            guard let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM app_setting WHERE key = 'committed_deletion_id'"
            ) else { return nil }
            guard let id = UUID(uuidString: value) else {
                throw InvoiceError.corruptData("invalid_committed_deletion_id")
            }
            return id
        }
    }

    public func domainIsEmpty() throws -> Bool {
        try writer.read { db in
            for table in [
                "business_profile", "customer", "site", "visit", "invoice_draft", "issued_invoice"
            ] {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
                if count != 0 { return false }
            }
            return true
        }
    }

    public func entitlementUsage(hasPro: Bool) throws -> EntitlementState {
        try writer.read { db in
            let value: String? = try String.fetchOne(db, sql: "SELECT first_clean_invoice_id FROM entitlement_usage WHERE singleton = 1")
            return EntitlementState(hasPro: hasPro, firstCleanInvoiceID: value.flatMap(UUID.init(uuidString:)))
        }
    }

    public func proposedNumber(issueDate: LocalDate, prefix: String) throws -> String {
        try writer.read { db in
            let next = try Int.fetchOne(db, sql: "SELECT next_value FROM invoice_sequence WHERE year = ?", arguments: [issueDate.year]) ?? 1
            return try InvoiceNumberAllocator().number(issueDate: issueDate, prefix: prefix, sequence: next)
        }
    }

    public func commitIssue(
        invoice: IssuedInvoice,
        sourceVisitIDs: [UUID],
        stagedPath: String,
        finalPath: String,
        pdfHash: String,
        consumeFreeAllowance: Bool
    ) throws -> UUID {
        guard !sourceVisitIDs.isEmpty,
              Set(sourceVisitIDs).count == sourceVisitIDs.count,
              Set(sourceVisitIDs) == Set(invoice.lines.map(\.sourceVisitID)) else {
            throw InvoiceError.invalidTransition
        }
        let operationID = UUID()
        try writer.write { db in
            let expected = try Int.fetchOne(db, sql: "SELECT next_value FROM invoice_sequence WHERE year = ?", arguments: [invoice.issueDate.year]) ?? 1
            let expectedNumber = try InvoiceNumberAllocator().number(issueDate: invoice.issueDate, prefix: invoice.issuer.invoicePrefix, sequence: expected)
            guard expectedNumber == invoice.number else { throw InvoiceError.invalidTransition }

            var stored = invoice
            stored.pdfRelativePath = finalPath
            stored.pdfSHA256 = pdfHash
            let payload = try Self.encode(stored)
            try db.execute(sql: """
                INSERT INTO issued_invoice(id, number, customer_id, status, issue_date,
                    pdf_relative_path, pdf_sha256, payload, issued_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [stored.id.uuidString.lowercased(), stored.number, stored.customerID.uuidString.lowercased(), stored.status.rawValue, stored.issueDate.description, finalPath, pdfHash, payload, stored.issuedAt.timeIntervalSince1970])

            for visitID in sourceVisitIDs {
                guard var visit = try Self.fetchVisit(db: db, id: visitID), visit.state == .unbilled else {
                    throw InvoiceError.visitNotUnbilled
                }
                visit.state = .billed(invoiceID: stored.id)
                visit.updatedAt = Date()
                let visitPayload = try Self.encode(visit)
                try db.execute(sql: "UPDATE visit SET state = 'billed', billed_invoice_id = ?, payload = ?, updated_at = ? WHERE id = ? AND state = 'unbilled'", arguments: [stored.id.uuidString.lowercased(), visitPayload, visit.updatedAt.timeIntervalSince1970, visitID.uuidString.lowercased()])
                guard db.changesCount == 1 else { throw InvoiceError.visitNotUnbilled }
                try db.execute(sql: "INSERT INTO invoice_visit_link(invoice_id, visit_id) VALUES (?, ?)", arguments: [stored.id.uuidString.lowercased(), visitID.uuidString.lowercased()])
            }

            try db.execute(sql: """
                INSERT INTO invoice_sequence(year, next_value) VALUES (?, 2)
                ON CONFLICT(year) DO UPDATE SET next_value = next_value + 1
                """, arguments: [stored.issueDate.year])
            if consumeFreeAllowance {
                let current: String? = try String.fetchOne(db, sql: "SELECT first_clean_invoice_id FROM entitlement_usage WHERE singleton = 1")
                guard current == nil else { throw InvoiceError.entitlementRequired }
                try db.execute(sql: "UPDATE entitlement_usage SET first_clean_invoice_id = ? WHERE singleton = 1", arguments: [stored.id.uuidString.lowercased()])
            }
            try db.execute(sql: """
                INSERT INTO file_operation_journal(id, invoice_id, staged_path, final_path, sha256, state, created_at)
                VALUES (?, ?, ?, ?, ?, 'pending', ?)
                """, arguments: [operationID.uuidString.lowercased(), stored.id.uuidString.lowercased(), stagedPath, finalPath, pdfHash, Date().timeIntervalSince1970])
        }
        return operationID
    }

    public func completeFileOperation(_ id: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE file_operation_journal SET state = 'complete' WHERE id = ?", arguments: [id.uuidString.lowercased()])
        }
    }

    public func markInvoicePaid(id: UUID, paidDate: LocalDate) throws {
        try writer.write { db in
            guard let data: Data = try Data.fetchOne(
                db,
                sql: "SELECT payload FROM issued_invoice WHERE id = ?",
                arguments: [id.uuidString.lowercased()]
            ) else { throw InvoiceError.corruptData("missing_invoice") }
            var invoice = try Self.decode(IssuedInvoice.self, from: data)
            guard invoice.status == .issued, paidDate >= invoice.issueDate else {
                throw InvoiceError.invalidTransition
            }
            invoice.status = .paid
            invoice.paidDate = paidDate
            try db.execute(
                sql: "UPDATE issued_invoice SET status = ?, payload = ? WHERE id = ?",
                arguments: [InvoiceStatus.paid.rawValue, try Self.encode(invoice), id.uuidString.lowercased()]
            )
        }
    }

    public func markInvoiceUnpaid(id: UUID) throws {
        try writer.write { db in
            guard let data: Data = try Data.fetchOne(
                db,
                sql: "SELECT payload FROM issued_invoice WHERE id = ?",
                arguments: [id.uuidString.lowercased()]
            ) else { throw InvoiceError.corruptData("missing_invoice") }
            var invoice = try Self.decode(IssuedInvoice.self, from: data)
            guard invoice.status == .paid else { throw InvoiceError.invalidTransition }
            invoice.status = .issued
            invoice.paidDate = nil
            try db.execute(
                sql: "UPDATE issued_invoice SET status = ?, payload = ? WHERE id = ?",
                arguments: [InvoiceStatus.issued.rawValue, try Self.encode(invoice), id.uuidString.lowercased()]
            )
        }
    }

    public func voidInvoice(id: UUID, returnVisitsToUnbilled: Bool) throws {
        try writer.write { db in
            guard let data: Data = try Data.fetchOne(
                db,
                sql: "SELECT payload FROM issued_invoice WHERE id = ?",
                arguments: [id.uuidString.lowercased()]
            ) else { throw InvoiceError.corruptData("missing_invoice") }
            var invoice = try Self.decode(IssuedInvoice.self, from: data)
            guard invoice.status == .issued || invoice.status == .paid else {
                throw InvoiceError.invalidTransition
            }
            invoice.status = .voided
            invoice.paidDate = nil
            try db.execute(
                sql: "UPDATE issued_invoice SET status = ?, payload = ? WHERE id = ?",
                arguments: [InvoiceStatus.voided.rawValue, try Self.encode(invoice), id.uuidString.lowercased()]
            )

            guard returnVisitsToUnbilled else { return }
            let visitIDs = try String.fetchAll(
                db,
                sql: "SELECT visit_id FROM invoice_visit_link WHERE invoice_id = ? ORDER BY visit_id",
                arguments: [id.uuidString.lowercased()]
            )
            for visitIDString in visitIDs {
                guard let visitID = UUID(uuidString: visitIDString),
                      var visit = try Self.fetchVisit(db: db, id: visitID),
                      visit.state == .billed(invoiceID: id) else { continue }
                visit.state = .unbilled
                visit.updatedAt = Date()
                try db.execute(
                    sql: "UPDATE visit SET state = 'unbilled', billed_invoice_id = NULL, payload = ?, updated_at = ? WHERE id = ? AND billed_invoice_id = ?",
                    arguments: [try Self.encode(visit), visit.updatedAt.timeIntervalSince1970, visitIDString, id.uuidString.lowercased()]
                )
            }
        }
    }

    public func pendingFileOperations() throws -> [FileOperation] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM file_operation_journal WHERE state = 'pending' ORDER BY created_at")
            return try rows.map { row in
                guard let id = UUID(uuidString: row["id"]), let invoiceID = UUID(uuidString: row["invoice_id"]) else {
                    throw InvoiceError.corruptData("file_operation_id")
                }
                let timestamp: Double = row["created_at"]
                return FileOperation(id: id, invoiceID: invoiceID, stagedPath: row["staged_path"], finalPath: row["final_path"], sha256: row["sha256"], createdAt: Date(timeIntervalSince1970: timestamp))
            }
        }
    }

    public func markNeedsRecovery(invoiceID: UUID, operationID: UUID) throws {
        try writer.write { db in
            guard let data: Data = try Data.fetchOne(db, sql: "SELECT payload FROM issued_invoice WHERE id = ?", arguments: [invoiceID.uuidString.lowercased()]) else { return }
            var invoice = try Self.decode(IssuedInvoice.self, from: data)
            guard invoice.status == .issued || invoice.status == .paid || invoice.status == .needsRecovery else {
                try db.execute(
                    sql: "UPDATE file_operation_journal SET state = 'needsRecovery' WHERE id = ?",
                    arguments: [operationID.uuidString.lowercased()]
                )
                return
            }
            invoice.status = .needsRecovery
            let payload = try Self.encode(invoice)
            try db.execute(sql: "UPDATE issued_invoice SET status = ?, payload = ? WHERE id = ?", arguments: [InvoiceStatus.needsRecovery.rawValue, payload, invoiceID.uuidString.lowercased()])
        }
    }

    public func integrityCheck() throws {
        try writer.read { db in
            let result = try String.fetchOne(db, sql: "PRAGMA integrity_check")
            guard result == "ok" else { throw InvoiceError.corruptData(result ?? "no_integrity_result") }
            let foreignKeys = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            guard foreignKeys.isEmpty else { throw InvoiceError.corruptData("foreign_key_check") }
            try Self.validateDomainInvariants(in: db)
        }
    }

    public func exportDatabase(to path: String) throws {
        let destination = try DatabaseQueue(path: path)
        try writer.backup(to: destination)
        try destination.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
        }
        try destination.close()

        let fileManager = FileManager.default
        for suffix in ["-wal", "-shm"] {
            let sidecar = path + suffix
            if fileManager.fileExists(atPath: sidecar) {
                try fileManager.removeItem(atPath: sidecar)
            }
        }
    }

    public static func validateDatabaseFile(at path: String) throws {
        let database = try DatabaseQueue(path: path)
        try database.read { db in
            let integrity = try String.fetchOne(db, sql: "PRAGMA integrity_check")
            guard integrity == "ok" else {
                throw InvoiceError.corruptData(integrity ?? "no_integrity_result")
            }
            guard try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else {
                throw InvoiceError.corruptData("foreign_key_check")
            }
            let requiredTables = [
                "business_profile", "customer", "site", "visit", "invoice_draft",
                "issued_invoice", "invoice_visit_link", "invoice_sequence",
                "entitlement_usage", "app_setting"
            ]
            for table in requiredTables {
                let exists = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                    arguments: [table]
                ) ?? 0
                guard exists == 1 else { throw InvoiceError.corruptData("missing_table_\(table)") }
            }
            try validateDomainInvariants(in: db)
        }
    }

    public static func canonicalPDFReferences(at path: String) throws -> [CanonicalPDFReference] {
        let database = try DatabaseQueue(path: path)
        return try database.read { db in
            let incomplete = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM issued_invoice
                WHERE pdf_relative_path IS NULL OR pdf_sha256 IS NULL
                   OR pdf_relative_path = '' OR pdf_sha256 = ''
                """) ?? 0
            guard incomplete == 0 else {
                throw InvoiceError.corruptData("issued_invoice_missing_pdf_reference")
            }

            return try Row.fetchAll(db, sql: """
                SELECT id, number, customer_id, status, issue_date,
                       pdf_relative_path, pdf_sha256, payload, issued_at
                FROM issued_invoice
                ORDER BY id
                """).map { row in
                let invoice = try Self.validatedIssuedInvoice(row)
                let invoiceID = invoice.id.uuidString.lowercased()
                guard let relativePath = invoice.pdfRelativePath,
                      let sha256 = invoice.pdfSHA256 else {
                    throw InvoiceError.corruptData("issued_invoice_missing_pdf_reference")
                }
                let pathComponents = relativePath.split(separator: "/", omittingEmptySubsequences: false)
                guard UUID(uuidString: invoiceID) != nil,
                      pathComponents.count == 2,
                      pathComponents.first == "Invoices",
                      pathComponents.last == Substring(invoiceID + ".pdf"),
                      !relativePath.contains(".."),
                      relativePath.lowercased().hasSuffix(".pdf"),
                      sha256.count == 64,
                      sha256.allSatisfy({ $0.isHexDigit }) else {
                    throw InvoiceError.corruptData("invalid_issued_pdf_reference")
                }
                return CanonicalPDFReference(
                    invoiceID: invoiceID,
                    relativePath: relativePath,
                    sha256: sha256.lowercased()
                )
            }
        }
    }

    public func replaceContents(from sourcePath: String) throws {
        try Self.validateDatabaseFile(at: sourcePath)
        let liveSequences: [(year: Int, nextValue: Int)] = try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT year, next_value FROM invoice_sequence").map { row in
                (year: row["year"], nextValue: row["next_value"])
            }
        }
        let liveConsumedIssueID: String? = try writer.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT first_clean_invoice_id FROM entitlement_usage WHERE singleton = 1"
            )
        }
        let source = try DatabaseQueue(path: sourcePath)
        try source.backup(to: writer)
        try Self.migrator.migrate(writer)
        try writer.write { db in
            for sequence in liveSequences {
                try db.execute(sql: """
                    INSERT INTO invoice_sequence(year, next_value) VALUES (?, ?)
                    ON CONFLICT(year) DO UPDATE SET next_value = MAX(next_value, excluded.next_value)
                    """, arguments: [sequence.year, sequence.nextValue])
            }
            if let liveConsumedIssueID {
                try db.execute(
                    sql: "UPDATE entitlement_usage SET first_clean_invoice_id = ? WHERE singleton = 1",
                    arguments: [liveConsumedIssueID]
                )
            }
        }
        try integrityCheck()
    }

    public func replaceContentsExactly(from sourcePath: String) throws {
        try Self.validateDatabaseFile(at: sourcePath)
        let source = try DatabaseQueue(path: sourcePath)
        try source.backup(to: writer)
        try Self.migrator.migrate(writer)
        try integrityCheck()
    }

    public func mergeContents(from sourcePath: String, dryRun: Bool = false) throws -> DatabaseMergeReport {
        try Self.validateDatabaseFile(at: sourcePath)
        return try writer.write { db in
            try db.execute(sql: "ATTACH DATABASE ? AS incoming", arguments: [sourcePath])
            defer { try? db.execute(sql: "DETACH DATABASE incoming") }

            let keyedTables = [
                "business_profile", "customer", "site", "visit", "invoice_draft", "issued_invoice"
            ]
            var conflicts: [String] = []
            for table in keyedTables {
                let ids = try String.fetchAll(db, sql: """
                    SELECT incoming.\(table).id
                    FROM incoming.\(table)
                    JOIN main.\(table) ON main.\(table).id = incoming.\(table).id
                    WHERE main.\(table).payload <> incoming.\(table).payload
                    ORDER BY incoming.\(table).id
                    """)
                conflicts.append(contentsOf: ids.map { "\(table):\($0)" })
            }
            let numberConflicts = try String.fetchAll(db, sql: """
                SELECT incoming.issued_invoice.number
                FROM incoming.issued_invoice
                JOIN main.issued_invoice ON main.issued_invoice.number = incoming.issued_invoice.number
                WHERE main.issued_invoice.id <> incoming.issued_invoice.id
                ORDER BY incoming.issued_invoice.number
                """)
            conflicts.append(contentsOf: numberConflicts.map { "invoice_number:\($0)" })

            let counts = DatabaseMergeReport.Counts(
                customers: try Self.newRowCount(db: db, table: "customer"),
                sites: try Self.newRowCount(db: db, table: "site"),
                visits: try Self.newRowCount(db: db, table: "visit"),
                drafts: try Self.newRowCount(db: db, table: "invoice_draft"),
                invoices: try Self.newRowCount(db: db, table: "issued_invoice")
            )
            let report = DatabaseMergeReport(counts: counts, conflicts: conflicts)
            guard conflicts.isEmpty else { return report }
            guard !dryRun else { return report }

            try db.execute(sql: "INSERT OR IGNORE INTO business_profile SELECT * FROM incoming.business_profile")
            try db.execute(sql: "INSERT OR IGNORE INTO customer SELECT * FROM incoming.customer")
            try db.execute(sql: "INSERT OR IGNORE INTO site SELECT * FROM incoming.site")
            try db.execute(sql: "INSERT OR IGNORE INTO visit SELECT * FROM incoming.visit")
            try db.execute(sql: "INSERT OR IGNORE INTO invoice_draft SELECT * FROM incoming.invoice_draft")
            try db.execute(sql: "INSERT OR IGNORE INTO issued_invoice SELECT * FROM incoming.issued_invoice")
            try db.execute(sql: "INSERT OR IGNORE INTO invoice_visit_link SELECT * FROM incoming.invoice_visit_link")
            try db.execute(sql: """
                INSERT INTO invoice_sequence(year, next_value)
                SELECT year, next_value FROM incoming.invoice_sequence
                ON CONFLICT(year) DO UPDATE SET next_value = MAX(next_value, excluded.next_value)
                """)
            try db.execute(sql: """
                UPDATE entitlement_usage
                SET first_clean_invoice_id = COALESCE(
                    first_clean_invoice_id,
                    (SELECT first_clean_invoice_id FROM incoming.entitlement_usage WHERE singleton = 1)
                )
                WHERE singleton = 1
                """)
            try db.execute(sql: "INSERT OR IGNORE INTO app_setting SELECT * FROM incoming.app_setting")
            return report
        }
    }

    private static func visitStateColumns(_ state: VisitState) -> (state: String, invoiceID: String?) {
        switch state {
        case .draft: ("draft", nil)
        case .unbilled: ("unbilled", nil)
        case .billed(let invoiceID): ("billed", invoiceID.uuidString.lowercased())
        }
    }

    private static func validateDomainInvariants(in db: Database) throws {
        _ = try Row.fetchAll(
            db,
            sql: "SELECT id, customer_id, payload, updated_at FROM invoice_draft ORDER BY id"
        ).map(validatedDraft)
        _ = try Row.fetchAll(
            db,
            sql: """
                SELECT id, number, customer_id, status, issue_date,
                       pdf_relative_path, pdf_sha256, payload, issued_at
                FROM issued_invoice ORDER BY id
                """
        ).map(validatedIssuedInvoice)

        let activeStatuses = "'issued', 'paid', 'needsRecovery'"
        let duplicateActiveLinks = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM (
                SELECT link.visit_id
                FROM invoice_visit_link AS link
                JOIN issued_invoice AS invoice ON invoice.id = link.invoice_id
                WHERE invoice.status IN (\(activeStatuses))
                GROUP BY link.visit_id
                HAVING COUNT(*) > 1
            )
            """) ?? 0
        guard duplicateActiveLinks == 0 else {
            throw InvoiceError.corruptData("duplicate_active_invoice_link")
        }

        let mismatchedActiveLinks = try Int.fetchOne(db, sql: """
            SELECT COUNT(*)
            FROM invoice_visit_link AS link
            JOIN issued_invoice AS invoice ON invoice.id = link.invoice_id
            JOIN visit ON visit.id = link.visit_id
            WHERE invoice.status IN (\(activeStatuses))
              AND (visit.state <> 'billed' OR visit.billed_invoice_id <> invoice.id)
            """) ?? 0
        guard mismatchedActiveLinks == 0 else {
            throw InvoiceError.corruptData("active_invoice_visit_state_mismatch")
        }

        let invalidVisitStates = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM visit
            WHERE (state = 'billed' AND (
                    billed_invoice_id IS NULL OR NOT EXISTS (
                        SELECT 1
                        FROM invoice_visit_link AS link
                        JOIN issued_invoice AS invoice ON invoice.id = link.invoice_id
                        WHERE link.visit_id = visit.id
                          AND invoice.id = visit.billed_invoice_id
                          AND invoice.status IN (\(activeStatuses))
                    )
                  ))
               OR (state <> 'billed' AND billed_invoice_id IS NOT NULL)
            """) ?? 0
        guard invalidVisitStates == 0 else {
            throw InvoiceError.corruptData("invalid_visit_billing_state")
        }

        let migrations = [
            ("v2-active-invoice-link-guard", "prevent_duplicate_active_invoice_link"),
            ("v3-active-invoice-status-guard", "prevent_duplicate_active_invoice_reactivation")
        ]
        for (migration, trigger) in migrations {
            let applied = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM grdb_migrations WHERE identifier = ?",
                arguments: [migration]
            ) ?? 0
            if applied > 0 {
                let exists = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name = ?",
                    arguments: [trigger]
                ) ?? 0
                guard exists == 1 else {
                    throw InvoiceError.corruptData("missing_invariant_trigger_\(trigger)")
                }
            }
        }

        let journalRows = try Row.fetchAll(db, sql: """
            SELECT journal.id, journal.invoice_id, journal.staged_path, journal.final_path,
                   journal.sha256, journal.state, invoice.pdf_relative_path, invoice.pdf_sha256
            FROM file_operation_journal AS journal
            JOIN issued_invoice AS invoice ON invoice.id = journal.invoice_id
            """)
        for row in journalRows {
            let operationID: String = row["id"]
            let invoiceID: String = row["invoice_id"]
            let stagedPath: String = row["staged_path"]
            let finalPath: String = row["final_path"]
            let hash: String = row["sha256"]
            let state: String = row["state"]
            let invoicePDFPath: String? = row["pdf_relative_path"]
            let invoicePDFHash: String? = row["pdf_sha256"]
            let stagedComponents = stagedPath.split(separator: "/", omittingEmptySubsequences: false)
            let finalComponents = finalPath.split(separator: "/", omittingEmptySubsequences: false)
            let expectedFilename = invoiceID.lowercased() + ".pdf"
            guard UUID(uuidString: operationID) != nil,
                  UUID(uuidString: invoiceID) != nil,
                  ["pending", "complete", "needsRecovery"].contains(state),
                  stagedComponents.count == 2,
                  stagedComponents.first == "Staging",
                  stagedComponents.last == Substring(expectedFilename),
                  finalComponents.count == 2,
                  finalComponents.first == "Invoices",
                  finalComponents.last == Substring(expectedFilename),
                  finalPath == invoicePDFPath,
                  hash.lowercased() == invoicePDFHash?.lowercased() else {
                throw InvoiceError.corruptData("invalid_file_operation_journal")
            }
        }
    }

    private static func fetchVisit(db: Database, id: UUID) throws -> Visit? {
        guard let data: Data = try Data.fetchOne(db, sql: "SELECT payload FROM visit WHERE id = ?", arguments: [id.uuidString.lowercased()]) else { return nil }
        return try Self.decode(Visit.self, from: data)
    }

    private static func validatedDraft(_ row: Row) throws -> InvoiceDraft {
        let rowID: String = row["id"]
        let rowCustomerID: String = row["customer_id"]
        let rowUpdatedAt: Double = row["updated_at"]
        let payload: Data = row["payload"]
        let draft = try decode(InvoiceDraft.self, from: payload)
        guard rowID == draft.id.uuidString.lowercased(),
              rowCustomerID == draft.customerID.uuidString.lowercased(),
              abs(rowUpdatedAt - draft.updatedAt.timeIntervalSince1970) < 0.0011 else {
            throw InvoiceError.corruptData("invoice_draft_payload_column_mismatch")
        }
        return draft
    }

    private static func validatedIssuedInvoice(_ row: Row) throws -> IssuedInvoice {
        let rowID: String = row["id"]
        let rowNumber: String = row["number"]
        let rowCustomerID: String = row["customer_id"]
        let rowStatus: String = row["status"]
        let rowIssueDate: String = row["issue_date"]
        let rowPDFPath: String? = row["pdf_relative_path"]
        let rowPDFHash: String? = row["pdf_sha256"]
        let rowIssuedAt: Double = row["issued_at"]
        let payload: Data = row["payload"]
        let invoice = try decode(IssuedInvoice.self, from: payload)
        guard rowID == invoice.id.uuidString.lowercased(),
              rowNumber == invoice.number,
              rowCustomerID == invoice.customerID.uuidString.lowercased(),
              rowStatus == invoice.status.rawValue,
              rowIssueDate == invoice.issueDate.description,
              rowPDFPath == invoice.pdfRelativePath,
              rowPDFHash?.lowercased() == invoice.pdfSHA256?.lowercased(),
              abs(rowIssuedAt - invoice.issuedAt.timeIntervalSince1970) < 0.0011 else {
            throw InvoiceError.corruptData("issued_invoice_payload_column_mismatch")
        }
        if let rowPDFPath, let rowPDFHash {
            let expectedPath = "Invoices/\(rowID).pdf"
            guard rowPDFPath == expectedPath,
                  rowPDFHash.count == 64,
                  rowPDFHash.allSatisfy({ $0.isHexDigit }) else {
                throw InvoiceError.corruptData("invalid_issued_pdf_reference")
            }
        } else if rowPDFPath != nil || rowPDFHash != nil {
            throw InvoiceError.corruptData("incomplete_issued_pdf_reference")
        }
        return invoice
    }

    private static func newRowCount(db: Database, table: String) throws -> Int {
        try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM incoming.\(table)
            LEFT JOIN main.\(table) ON main.\(table).id = incoming.\(table).id
            WHERE main.\(table).id IS NULL
            """) ?? 0
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}

public struct DatabaseMergeReport: Hashable, Sendable {
    public struct Counts: Hashable, Sendable {
        public let customers: Int
        public let sites: Int
        public let visits: Int
        public let drafts: Int
        public let invoices: Int

        public init(customers: Int, sites: Int, visits: Int, drafts: Int, invoices: Int) {
            self.customers = customers
            self.sites = sites
            self.visits = visits
            self.drafts = drafts
            self.invoices = invoices
        }
    }

    public let counts: Counts
    public let conflicts: [String]

    public init(counts: Counts, conflicts: [String]) {
        self.counts = counts
        self.conflicts = conflicts
    }

    public var canCommit: Bool { conflicts.isEmpty }
}

public struct FileOperation: Hashable, Sendable {
    public let id: UUID
    public let invoiceID: UUID
    public let stagedPath: String
    public let finalPath: String
    public let sha256: String
    public let createdAt: Date
}

public struct CanonicalPDFReference: Hashable, Sendable {
    public let invoiceID: String
    public let relativePath: String
    public let sha256: String

    public init(invoiceID: String, relativePath: String, sha256: String) {
        self.invoiceID = invoiceID
        self.relativePath = relativePath
        self.sha256 = sha256
    }
}
