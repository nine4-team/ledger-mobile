import Foundation
import LedgerTargetCore
import LedgerTargetMigrationCore
#if os(macOS)
import Darwin

private struct ExpenseReceiptCopyPlan: Decodable {
    struct Object: Decodable {
        let id: String, sha256: String, byteCount: String, mediaType: String, storagePath: String
    }
    struct Receipt: Decodable { let sourceID: String; let images: [Object] }
    let sourceSHA256: String, accountID: String
    let receipts: [Receipt]
}

/// Private, partial real-data QA copy. Not the production cutover runner. The
/// preserved snapshot remains authority for fields/history not loaded yet.
func loadRealProjectCopy(path: String, apply: Bool, mediaDirectory: String? = nil) throws {
    let root = "/Users/benjaminmackenzie/Dev/ledger_mobile_supabase"
    let privateRoot = root + "/tmp/real-project-copy"
    try require(FileManager.default.currentDirectoryPath == root, "Use Supabase worktree")
    let url = URL(fileURLWithPath: path).standardizedFileURL
    try require(url.deletingLastPathComponent().path == privateRoot && (try regularFile(url.path)), "Invalid private snapshot")
    let bytes = try Data(contentsOf: url)
    try require(bytes.count <= 10_000_000, "Snapshot too large")
    let sourceAccount = "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94"
    let selectedProject = "5abd46c9-9886-4b3e-b2b1-19f6cf995a44"
    let documents = try FirebaseRESTSnapshotReader.read(bytes, accountPath:
        "projects/ledger-nine4/databases/(default)/documents/accounts/" + sourceAccount)
    let lineage = FirebaseLineageSourceReview.review(documents: documents, accountScopeID: sourceAccount)
    try require(lineage.issues.isEmpty, "Source documents require review")
    let prefix = "realcopy-" + String(try MigrationSHA256.make(bytes: Data(selectedProject.utf8)).rawValue.prefix(12))
        + (apply ? "" : "-check-" + String(try MigrationSHA256.make(bytes: bytes).rawValue.prefix(12)))
    func id(_ entity: String, _ source: String) throws -> String {
        let value = prefix + "-" + entity + "-" + String(try MigrationSHA256.make(bytes: Data(source.utf8)).rawValue.prefix(24))
        return try ItemID(validating: value).rawValue
    }
    func records(_ kind: String) -> [FirebaseSourceDocument] {
        documents.filter { $0.documentPathSegments.count == 4 && $0.documentPathSegments[2] == kind }
    }
    func field(_ document: FirebaseSourceDocument, _ key: String) -> FirebaseSourceValue? {
        guard case .map(let values) = document.fields else { return nil }
        return values.first { $0.key == key }?.value
    }
    func text(_ document: FirebaseSourceDocument, _ key: String) throws -> String? {
        switch field(document, key) {
        case nil, .null: return nil
        case .string(let value): try require(!value.contains("\0"), "Text requires explicit NUL disposition"); return value
        default: throw ImportFailure("Unexpected source text type")
        }
    }
    func q(_ value: String?) -> String { value.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" } ?? "null" }
    func boolean(_ document: FirebaseSourceDocument, _ key: String) throws -> Bool? {
        switch field(document, key) {
        case nil, .null: return nil
        case .bool(let value): return value
        default: throw ImportFailure("Unexpected source boolean type")
        }
    }
    func integerSQL(_ document: FirebaseSourceDocument, _ key: String) throws -> String {
        switch field(document, key) {
        case nil, .null: return "null"
        case .integer(let value): return value
        default: throw ImportFailure("Expected exact source integer")
        }
    }
    func timestampMillisecondsSQL(_ document: FirebaseSourceDocument, _ key: String) throws -> String {
        switch field(document, key) {
        case nil, .null: return "null"
        case .timestamp(let seconds, let nanos):
            guard let seconds = Int64(seconds) else { throw ImportFailure("Invalid source timestamp") }
            let product = seconds.multipliedReportingOverflow(by: 1000)
            let sum = product.partialValue.addingReportingOverflow(Int64(nanos / 1_000_000))
            try require(!product.overflow && !sum.overflow, "Source timestamp overflow")
            return String(sum.partialValue)
        default: throw ImportFailure("Expected original timestamp evidence")
        }
    }
    func legacyTaxSQL(_ document: FirebaseSourceDocument) throws -> String {
        switch field(document,"taxRatePct") {
        case nil, .null: return "null"
        case .integer(let value): return value
        case .double(let bits):
            guard let raw = UInt64(bits, radix: 16) else { throw ImportFailure("Invalid source tax bits") }
            let value = Double(bitPattern: raw)
            try require(value.isFinite, "Nonfinite source tax")
            // Display metadata only; original binary bits stay in source bytes.
            return String(value)
        default: throw ImportFailure("Unexpected source tax representation")
        }
    }
    let account = prefix + "-account"
    let sourceHash = try MigrationSHA256.make(bytes: bytes).rawValue
    func receiptCommand(_ mode: String, sourceIDs: [String]) throws -> ExpenseReceiptCopyPlan {
        guard let mediaDirectory else { throw ImportFailure("Receipt copy directory missing") }
        let request: [String:Any] = ["snapshotPath":url.path,"mediaDirectory":mediaDirectory,
            "targetAccountID":account,"sourceIDs":sourceIDs.sorted()]
        let result = try command(["node","scripts/real-copy-transaction-media.cjs",mode],
            input: String(decoding: JSONSerialization.data(withJSONObject: request),as: UTF8.self))
        let plan = try JSONDecoder().decode(ExpenseReceiptCopyPlan.self,from: Data(result.utf8))
        try require(plan.sourceSHA256 == sourceHash && plan.accountID == account, "Receipt source identity changed")
        try require(Set(plan.receipts.map(\.sourceID)).count == plan.receipts.count, "Duplicate receipt mapping")
        return plan
    }
    // Planning reads only copied bytes. Upload/remote verification is deferred
    // until complete financial validation has selected the accepted sources.
    let receiptPlan = try mediaDirectory.map { _ in
        try receiptCommand("--plan-expense-receipts", sourceIDs: records("transactions")
            .filter { field($0,"projectId") == .string(selectedProject) }.map { $0.documentPathSegments[3] })
    }
    var acceptedReceiptSources = Set<String>()
    var acceptedReceiptObjects: [String:DownloadedMediaObjectReference] = [:]
    let owner = "upload-http-owner-4b1e9766-5791-48a9-a7b1-15a541807e64"
    let ownerEmail = "upload-owner-4b1e9766-5791-48a9-a7b1-15a541807e64@ledger-tests.invalid"
    let destinationPreflight = "do $$ begin if not exists(select 1 from public.spike_principals p join auth.users u on u.id=p.auth_user_id where p.id=\(q(owner)) and u.email=\(q(ownerEmail))) then raise exception 'Expected isolated QA principal missing'; end if; if exists(select 1 from public.spike_accounts where id=\(q(account))) then raise exception 'Test copy already exists; reconcile before replay'; end if; end $$;\n"
    var sql = "begin; set local standard_conforming_strings=on; set local statement_timeout='30s';\n"
    sql += "select pg_advisory_xact_lock(hashtextextended(\(q(account)),0));\n"
    sql += destinationPreflight
    sql += "insert into public.spike_accounts(id,display_name) values(\(q(account)),'PRIVATE REAL-DATA COPY — partial import');\n"
    sql += "insert into public.spike_account_memberships(account_id,principal_id,role,state,can_manage_clients) values(\(q(account)),\(q(owner)),'owner','active',true);\n"
    let projects = records("projects"), items = records("items"), spaces = records("spaces")
    try require(projects.contains { $0.documentPathSegments[3] == selectedProject }, "Selected Project missing")
    for project in projects {
        let sourceID = project.documentPathSegments[3]
        let name = try text(project, "name")
        try require(!(name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Missing Project name")
        // Each copied Project gets an explicit isolated Client identity. No
        // production Clients are merged by matching display names.
        let client = try id("client", sourceID), projectID = try id("project", sourceID)
        let clientName = try text(project, "clientName")
        try require(!(clientName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Missing Client display evidence")
        sql += "insert into public.spike_clients(id,account_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id) values(\(q(client)),\(q(account)),\(q(clientName)),now(),now(),floor(extract(epoch from now())*1000)::bigint,floor(extract(epoch from now())*1000)::bigint,\(q(owner)));\n"
        let lifecycle = try boolean(project,"isArchived") == true ? "archived" : "active"
        sql += "insert into public.spike_projects(id,account_id,client_id,display_name,description,legacy_notes,lifecycle,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id) values(\(q(projectID)),\(q(account)),\(q(client)),\(q(name)),nullif(\(q(try text(project,"description"))),''),\(q(try text(project,"notes"))),\(q(lifecycle)),now(),now(),floor(extract(epoch from now())*1000)::bigint,floor(extract(epoch from now())*1000)::bigint,\(q(owner)));\n"
    }
    for space in spaces {
        guard case .string(let project) = field(space, "projectId") else { throw ImportFailure("Unresolved Space scope") }
        let name = try text(space, "name")
        try require(name == name?.trimmingCharacters(in: .whitespacesAndNewlines), "Space name needs explicit normalization")
        let lifecycle = try boolean(space,"isArchived") == true ? "archived" : "active"
        sql += "insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle) values(\(q(try id("space",space.documentPathSegments[3]))),\(q(account)),'project',\(q(try id("project",project))),\(q(name)),\(q(lifecycle)));\n"
    }
    for item in items {
        let placement = FirebaseCurrentItemPlacement.read(item, accountID: sourceAccount, documents: documents)
        try require(placement.isResolved, "Unresolved current Item placement")
        let itemID = try id("item", item.documentPathSegments[3])
        let bookmark = try boolean(item,"bookmark").map { $0 ? "true" : "false" } ?? "null"
        sql += "insert into public.spike_items(id,account_id,description,name,sku,source,current_source,notes,workflow_status,bookmark,created_by_principal_id) values(\(q(itemID)),\(q(account)),coalesce(\(q(try text(item,"name"))),''),\(q(try text(item,"name"))),\(q(try text(item,"sku"))),\(q(try text(item,"source"))),\(q(try text(item,"currentSource"))),\(q(try text(item,"notes"))),\(q(try text(item,"status"))),\(bookmark),\(q(owner)));\n"
        sql += "insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at,started_by_principal_id,start_evidence) values(\(q(try id("placement",item.documentPathSegments[3]))),\(q(account)),\(q(itemID)),\(q(placement.projectID == nil ? "business_inventory" : "project")),\(q(try placement.projectID.map { try id("project",$0) })),\(q(try placement.spaceID.map { try id("space",$0) })),now(),\(q(owner)),'import_observation');\n"
    }
    // Financial plans are prepared separately below; never relabel legacy
    // vendor purchases as imported client payments to make a test load succeed.
    let scope = TransactionScope.project(accountId: try .init(validating: account),
        projectId: try .init(validating: id("project",selectedProject)), clientId: try .init(validating: id("client",selectedProject)))
    var eligible = 0, unresolved = 0
    var unresolvedReasons: [String:Int] = [:]
    var excludedTransactions: [String:String] = [:]
    var categories = Set<String>()
    for transaction in records("transactions") where field(transaction,"projectId") == .string(selectedProject) {
        let result = FirebaseAcquisitionConversion.convert(transaction, sourceAccountID: sourceAccount,
            sourceProjectID: selectedProject,targetProjectScope: scope,documents: documents,lineage: lineage.lineage)
        guard case .planned(let plan) = result else {
            unresolved += 1
            if case .unresolved(let reason) = result {
                unresolvedReasons[reason.rawValue, default: 0] += 1
                excludedTransactions[transaction.documentPathSegments[3]] = reason.rawValue
            }
            continue
        }
        guard plan.historicalItemIDs.isSubset(of: plan.sourceItemIDs) else {
            unresolved += 1; unresolvedReasons["historicalMembershipNeedsMapping", default: 0] += 1
            excludedTransactions[transaction.documentPathSegments[3]] = "historicalMembershipNeedsMapping"
            continue
        }
        let categoryID = try id("category",plan.sourceCategory.documentPathSegments.last!)
        if categories.insert(categoryID).inserted {
            let categoryName = try text(plan.sourceCategory,"name")
            try require(!(categoryName ?? "").isEmpty, "Missing category name")
            sql += "insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,presentation_order,lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms) values(\(q(categoryID)),\(q(account)),\(q(categoryName)),\(q(plan.categoryKind.rawValue)),'company_financial',\(categories.count),'active',false,false,1,1);\n"
        }
        let sourceID = transaction.documentPathSegments[3]
        let mappings = try plan.sourceItemIDs.sorted().map { sourceItemID -> FirebaseVendorPurchaseItemMapping in
            guard let sourceItem = items.first(where: { $0.documentPathSegments[3] == sourceItemID }) else { throw ImportFailure("Missing receipt Item") }
            let price = FirebaseReceiptItemPriceEvidence.read(sourceItem, sourceAccountID: sourceAccount, sourceTransactionID: sourceID)
            // Recorded purchase price only. No guessed header-tax allocation,
            // quantity multiplication or historical/current-price substitution.
            return .init(sourceItemID: sourceItemID, relationshipID: try id("receipt-item",sourceID + ":" + sourceItemID),
                targetItemID: try .init(validating: id("item",sourceItemID)),
                amountMinorUnits: price.issues.isEmpty ? price.purchasePriceCents : nil, membership: .linked)
        }
        let p = try FirebaseVendorPurchaseImportParameters.make(plan: plan,
            targetID: .init(validating: id("transaction",sourceID)), targetCategoryID: .init(validating: categoryID),
            currency: .init(validating: "USD"),items: mappings,lines: [])
        let linesJSON = String(decoding: try canonical(p.p_lines),as: UTF8.self)
        let itemsJSON = String(decoding: try canonical(p.p_items),as: UTF8.self)
        sql += "select ledger_private.import_vendor_purchase(\(q(p.p_id)),\(q(p.p_account_id)),\(q(p.p_scope_kind)),\(q(p.p_project_id)),\(q(p.p_client_id)),\(q(p.p_category_id)),\(p.p_amount),\(q(p.p_currency)),\(q(linesJSON))::jsonb,\(q(itemsJSON))::jsonb,\(q(p.p_source_account)),\(q(p.p_source_document)),\(q(p.p_source_bytes))::bytea);\n"
        let date = try text(transaction,"transactionDate")
        if let date {
            try require(date.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",options: .regularExpression) != nil,
                "Transaction date requires explicit interpretation")
        }
        let email = try boolean(transaction,"hasEmailReceipt").map { $0 ? "true" : "false" } ?? "null"
        sql += "update public.spike_transactions set source=\(q(try text(transaction,"source"))),notes=\(q(try text(transaction,"notes"))),payment_method=\(q(try text(transaction,"paymentMethod"))),transaction_date=\(q(date))::date,created_at_ms=\(try timestampMillisecondsSQL(transaction,"createdAt")),has_email_receipt=\(email),legacy_subtotal_minor_units=\(try integerSQL(transaction,"subtotalCents")),legacy_tax_rate_pct=\(try legacyTaxSQL(transaction)) where id=\(q(p.p_id));\n"
        eligible += 1
    }
    var expenseInvoices = 0, importedExpenses = 0
    var excludedInvoices: [String:String] = [:]
    for invoice in records("invoices") where field(invoice,"projectId") == .string(selectedProject) {
        let sourceInvoiceID = invoice.documentPathSegments[3]
        let payments = records("transactions").filter { field($0,"settlementInvoiceId") == .string(sourceInvoiceID) }
        let review = FirebaseInvoiceSettlementReview.review(invoice: invoice, payments: payments,
            sourceAccountID: sourceAccount, targetScope: scope).resolveSources(in: documents)
        guard review.settlement.hasSinglePaymentLineCoverage, payments.count == 1 else {
            excludedInvoices[sourceInvoiceID] = "settlementRequiresMapping"; continue
        }
        var mapped: [FirebaseExpenseConversion.Result] = []
        var historicalCategories: [String:BudgetCategoryID] = [:]
        var requiredCategories: [String:FirebaseSourceDocument] = [:]
        var invoiceReceiptObjects: [String:DownloadedMediaObjectReference] = [:]
        var issue: String?
        func categorySource(_ sourceID: String) -> FirebaseSourceDocument? {
            let matches = documents.filter {
                $0.documentPathSegments == ["accounts",sourceAccount,"presets","default","budgetCategories",sourceID]
            }
            return matches.count == 1 ? matches[0] : nil
        }
        for reviewed in review.lines {
            guard case .map(let fields) = reviewed.line, let source = reviewed.source,
                  case .string(let lineID) = fields.first(where: { $0.key == "id" })?.value,
                  case .string(let historicalID) = fields.first(where: { $0.key == "budgetCategoryId" })?.value,
                  case .string(let currentID) = field(source,"budgetCategoryId"),
                  let historical = categorySource(historicalID), let current = categorySource(currentID) else {
                issue = "sourceOrHistoricalCategoryRequiresMapping"; break
            }
            var receiptMappings: [FirebaseExpenseConversion.ReceiptMapping] = []
            if let copied = receiptPlan?.receipts.first(where: { $0.sourceID == source.documentPathSegments.last! }) {
                let originals: [FirebaseSourceValue]
                switch field(source,"receiptImages") {
                case nil, .null: originals = []
                case .array(let values): originals = values
                default: originals = []; issue = "attachmentMappingRequired"
                }
                if issue != nil { break }
                try require(originals.count == copied.images.count, "Receipt order/count changed")
                receiptMappings = try zip(originals,copied.images).map { original, image in
                    let object = try DownloadedMediaObjectReference(accountId: scope.accountId, attachmentId: image.id,
                        sha256: image.sha256, byteCount: image.byteCount, mediaType: image.mediaType,
                        storagePath: image.storagePath, kind: image.mediaType == "application/pdf" ? .pdf : .image)
                    invoiceReceiptObjects[image.id] = object
                    return .init(sourceReference: original,object: object)
                }
            }
            let result = try FirebaseExpenseConversion.convertInvoiceSource(review, lineID: lineID,
                targetScope: scope, expenseID: .init(validating: id("expense",source.documentPathSegments.last!)),
                categoryID: .init(validating: id("category",currentID)), currency: .init(validating: "USD"), lineage: lineage.lineage,
                receiptMappings: receiptMappings)
            guard case .invoiceSourceMapped = result else {
                if case .unresolved(let reason) = result { issue = reason.rawValue }
                else { issue = "invoiceSourceRequiresMapping" }
                break
            }
            mapped.append(result)
            historicalCategories[historicalID] = try .init(validating: id("category",historicalID))
            requiredCategories[currentID] = current
            requiredCategories[historicalID] = historical
        }
        if let issue { excludedInvoices[sourceInvoiceID] = issue; continue }
        let paymentBatch = try FirebaseClientPaymentBatch.convert(transactions: payments, projects: projects,
            sourceAccountID: sourceAccount, targetAccountID: scope.accountId,
            projectMappings: [.init(sourceProject: projects.first { $0.documentPathSegments[3] == selectedProject }!, targetScope: scope)],
            identityMappings: [.init(sourcePath: payments[0].documentPathSegments,
                targetID: .init(validating: id("transaction",payments[0].documentPathSegments[3])))])
        guard paymentBatch.isFullyReconciled else { excludedInvoices[sourceInvoiceID] = "paymentRequiresMapping"; continue }
        let payment = try FirebaseClientPaymentImportParameters.make(batch: paymentBatch, currency: .init(validating: "USD"))[0]
        let parameters: FirebaseExpenseInvoiceImportParameters
        do {
            parameters = try .make(review: review, mappedSources: mapped, targetScope: scope,
                invoiceID: .init(validating: id("invoice",sourceInvoiceID)), payment: payment,
                invoiceRevision: 1, sourceRevision: 1, historicalCategories: historicalCategories, currency: .init(validating: "USD"))
        } catch {
            excludedInvoices[sourceInvoiceID] = "completeInvoiceParametersRequireMapping"; continue
        }
        // Historical definitions can differ from a source's current category.
        // Retain both IDs; use source category kind rather than renaming all as General.
        var categorySQL = ""
        var categoryIDs: [String] = []
        for sourceID in requiredCategories.keys.sorted() {
            let definition = requiredCategories[sourceID]!
            let categoryID = try id("category",sourceID)
            if categories.contains(categoryID) { continue }
            guard let name = try text(definition,"name"), !name.isEmpty,
                  case .map(let metadata) = field(definition,"metadata"),
                  case .string(let kind) = metadata.first(where: { $0.key == "categoryType" })?.value,
                  ["general","itemized","fee"].contains(kind) else { issue = "categoryDefinitionRequiresMapping"; break }
            categoryIDs.append(categoryID)
            categorySQL += "insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,presentation_order,lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms) values(\(q(categoryID)),\(q(account)),\(q(name)),\(q(kind)),'company_financial',\(categories.count + categoryIDs.count),'active',false,false,1,1);\n"
        }
        if let issue { excludedInvoices[sourceInvoiceID] = issue; continue }
        categories.formUnion(categoryIDs)
        sql += categorySQL
        for object in invoiceReceiptObjects.values.sorted(by: { $0.attachmentId.rawValue < $1.attachmentId.rawValue }) {
            let objectID = object.attachmentId.rawValue
            if let previous = acceptedReceiptObjects[objectID] {
                try require(previous == object, "Receipt object changed across Invoices")
                continue
            }
            acceptedReceiptObjects[objectID] = object
            // Catalog references and financial rows share this transaction.
            // The existing transport verifies actual bytes before SQL executes.
            sql += "insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path) values(\(q(objectID)),\(q(account)),\(q(object.contentSHA256.rawValue)),\(object.byteCount),\(q(object.mediaType)),\(q(object.storagePath)));\n"
        }
        if !invoiceReceiptObjects.isEmpty {
            acceptedReceiptSources.formUnion(review.lines.compactMap(\.source).map { $0.documentPathSegments.last! })
        }
        sql += "select ledger_private.import_client_payment(" + [payment.p_id,payment.p_account_id,payment.p_project_id,
            payment.p_client_id,payment.p_amount,payment.p_currency,payment.p_source_account,payment.p_source_document,payment.p_source_bytes]
            .map { q($0) }.joined(separator: ",") + ");\n"
        sql += "select ledger_private.import_expense_invoice(\(q(String(decoding: try canonical(parameters.p_invoice),as: UTF8.self)))::jsonb,\(q(String(decoding: try canonical(parameters.p_expenses),as: UTF8.self)))::jsonb,\(q(String(decoding: try canonical(payment),as: UTF8.self)))::jsonb,\(q(parameters.p_source_account)),\(q(parameters.p_source_invoice)),\(q(parameters.p_invoice_bytes))::bytea);\n"
        let expenseJSON = String(decoding: try canonical(parameters.p_expenses),as: UTF8.self)
        let invoiceJSON = String(decoding: try canonical(parameters.p_invoice),as: UTF8.self)
        sql += "do $$ begin if ledger_private.read_collected_invoice(\(q(account)),\(q(try id("invoice",sourceInvoiceID))))->'display_metadata' is distinct from (\(q(invoiceJSON))::jsonb)->'display_metadata' then raise exception 'Invoice display metadata reconciliation mismatch'; end if; end $$;\n"
        sql += "do $$ begin if exists(select 1 from jsonb_array_elements(\(q(expenseJSON))::jsonb) expected left join ledger_private.expenses e on e.id=expected->'record'->>'id' where to_jsonb(e) is distinct from to_jsonb(jsonb_populate_record(null::ledger_private.expenses,expected->'record'))) then raise exception 'Imported Expense field reconciliation mismatch'; end if; end $$;\n"
        sql += "do $$ begin if exists(select 1 from jsonb_array_elements(\(q(expenseJSON))::jsonb) expected where coalesce((select jsonb_agg(r.attachment_id order by r.position) from ledger_private.expense_receipt_attachments r where r.expense_id=expected->'record'->>'id'),'[]'::jsonb) is distinct from expected->'receipt_attachment_ids') then raise exception 'Expense receipt reconciliation mismatch'; end if; end $$;\n"
        expenseInvoices += 1; importedExpenses += mapped.count
        excludedTransactions.removeValue(forKey: payments[0].documentPathSegments[3])
        for source in review.lines.compactMap(\.source) { excludedTransactions.removeValue(forKey: source.documentPathSegments.last!) }
    }
    // This partial copier already targets one explicitly reviewed source Account.
    // Preserve its reviewed Furnishings identity, never infer it from a display name
    // or from the presence of another itemized category (for example Additional Requests).
    let furnishingsSourceID = "da556858-1df8-40be-b10c-b15710d7cc9a"
    try require(FirebaseReviewedFurnishingsSource.matches(documents, accountID: sourceAccount,
        categoryID: furnishingsSourceID), "Reviewed Furnishings source missing, ambiguous or changed; mapping review required")
    let furnishingsID = try id("category", furnishingsSourceID)
    try require(categories.contains(furnishingsID), "Reviewed Furnishings category was not imported")
    sql += "update public.spike_accounts set furnishings_category_id=\(q(furnishingsID)) where id=\(q(account)) and furnishings_category_id is null;\n"
    sql += "do $$ begin if (select furnishings_category_id from public.spike_accounts where id=\(q(account))) is distinct from \(q(furnishingsID)) then raise exception 'Furnishings identity reconciliation mismatch'; end if; end $$;\n"
    unresolved = excludedTransactions.count
    unresolvedReasons = Dictionary(grouping: excludedTransactions.values, by: { $0 }).mapValues(\.count)
    // A labeled QA dataset is not a migrated Account. Retain the exact source
    // and exclusions before committing; never imply accounting completeness.
    sql += "do $$ begin if (select count(*) from public.spike_items where account_id=\(q(account)))<>\(items.count) or (select count(*) from public.spike_item_placements where account_id=\(q(account)) and start_evidence='import_observation')<>\(items.count) or (select count(*) from public.spike_transactions where account_id=\(q(account)) and origin='vendor_payment')<>\(eligible) or (select count(*) from public.spike_transactions where account_id=\(q(account)) and origin='firebase_client_payment')<>\(expenseInvoices) or (select count(*) from ledger_private.collected_invoices where account_id=\(q(account)))<>\(expenseInvoices) or (select count(*) from ledger_private.expenses where account_id=\(q(account)))<>\(importedExpenses) then raise exception 'Real copy reconciliation mismatch'; end if; end $$;\n"
    sql += apply ? "commit;\n" : "rollback;\n"
    let env = ProcessInfo.processInfo.environment
    try require((env["DOCKER_HOST"] ?? "").isEmpty && (env["DOCKER_CONTEXT"] ?? "").isEmpty, "No remote Docker overrides")
    let context = try command(["docker","context","show"])
    try require(try command(["docker","context","inspect",context,"--format","{{.Endpoints.docker.Host}}"]).hasPrefix("unix:///"), "Local Docker required")
    let container = "supabase_db_ledger_target_supabase_local"
    let inspected = try command(["docker","inspect",container,"--format","{{json .}}"])
    let info = try JSONSerialization.jsonObject(with: Data(inspected.utf8)) as? [String:Any]
    let labels = (info?["Config"] as? [String:Any])?["Labels"] as? [String:String]
    try require(labels?["com.supabase.cli.project"] == "ledger_target_supabase_local"
        && labels?["com.supabase.cli.workdir"] == root, "Wrong local database")
    let ports = (info?["NetworkSettings"] as? [String:Any])?["Ports"] as? [String:Any] ?? [:]
    let bindings = ports.values.compactMap { $0 as? [[String:String]] }.flatMap { $0 }
    try require(!bindings.isEmpty && bindings.allSatisfy { ["127.0.0.1","::1"].contains($0["HostIp"] ?? "") }, "Database must be loopback-only")
    // Fail before transport side effects, then repeat under the transaction's
    // lock so a concurrent loader cannot invalidate this early check.
    _ = try command(["docker","exec","-i",container,"psql","-X","-q","-U","postgres","-d","postgres","-v","ON_ERROR_STOP=1"], input: destinationPreflight)
    if !acceptedReceiptObjects.isEmpty {
        let privateBucket = try command(["docker","exec",container,"psql","-X","-At","-U","postgres","-d","postgres","-c",
            "select not public from storage.buckets where id='ledger-attachments';"])
        try require(privateBucket == "t", "Private receipt bucket required")
        let verified = try receiptCommand(apply ? "--upload-expense-receipts" : "--verify-expense-receipts",
            sourceIDs: Array(acceptedReceiptSources))
        let verifiedIDs = Set(verified.receipts.flatMap(\.images).map(\.id))
        try require(verifiedIDs == Set(acceptedReceiptObjects.keys), "Verified receipt coverage changed")
        for image in verified.receipts.flatMap(\.images) {
            let object = try DownloadedMediaObjectReference(accountId: scope.accountId, attachmentId: image.id,
                sha256: image.sha256, byteCount: image.byteCount, mediaType: image.mediaType,
                storagePath: image.storagePath, kind: image.mediaType == "application/pdf" ? .pdf : .image)
            try require(acceptedReceiptObjects[image.id] == object, "Verified receipt bytes changed")
        }
    }
    if apply {
        let directory = privateRoot + "/qa-copy-" + String(sourceHash.prefix(16))
        if !FileManager.default.fileExists(atPath: directory) {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        var info = stat()
        try require(lstat(directory,&info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
            && info.st_uid == getuid() && (info.st_mode & 0o077) == 0, "Private copy directory required")
        try retain(bytes, at: directory + "/source.json", directory: directory)
        try retain(Data(sql.utf8), at: directory + "/load.sql", directory: directory)
        let manifest: [String:Any] = ["kind":"partial-real-data-qa-copy", "sourceSHA256":sourceHash,
            "accountID":account, "qaPrincipalID":owner, "selectedSourceProject":selectedProject,
            "projects":projects.count,"spaces":spaces.count,"items":items.count,"vendorPurchases":eligible,
            "excludedTransactions":excludedTransactions,"excludedInvoices":excludedInvoices,
            "expenseInvoices":expenseInvoices,"expenses":importedExpenses,
            "verifiedExpenseReceiptObjects":acceptedReceiptObjects.count,
            "limitations":["Not accounting/migration acceptance evidence",
                "Related Projects use separate QA Client identities, not approved production Client mappings",
                "Category visibility is restricted to company financial access for this QA copy",
                "Only explicitly verified Expense receipts are loaded here; other media, full historical relationships, mixed-source/unresolved billing histories and remaining metadata are not loaded",
                "Physical record timestamps currently describe target creation; original timestamps remain in source.json",
                "No balance adjustment or tax allocation invented; nonphysical receipt lines await source mapping"]]
        try retain(JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]),
            at: directory + "/manifest.json",directory: directory)
    }
    _ = try command(["docker","exec","-i",container,"psql","-X","-q","-U","postgres","-d","postgres","-v","ON_ERROR_STOP=1","-v","VERBOSITY=terse"], input: sql)
    print("Private copy \(apply ? "committed (partial QA only)" : "rollback check passed"): \(projects.count) Projects, \(spaces.count) Spaces, \(items.count) Items. Vendor plans \(eligible), Expense Invoices \(expenseInvoices), Expenses \(importedExpenses), unresolved Transactions \(unresolved), unresolved Invoices \(excludedInvoices.count).")
    print(String(decoding: try canonical(unresolvedReasons), as: UTF8.self))
    print("Verified Expense receipt objects: \(acceptedReceiptObjects.count)")
}
#endif
