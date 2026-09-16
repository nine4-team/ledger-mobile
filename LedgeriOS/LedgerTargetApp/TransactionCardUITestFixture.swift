#if DEBUG
import SwiftUI
import LedgerTargetCore
import CryptoKit
import PDFKit
import LedgerTargetPowerSync

/// Callback-failure presentation proof only; not runtime or durability proof.
struct MediaCaptureBatchUITestFixture: View {
    @State private var menu = false
    @State private var saving = false
    @State private var failure: String?
    @State private var attempts = 0
    @State private var accepted = 0
    private enum Refusal: LocalizedError {
        case firstFile
        var errorDescription: String? { "First attachment refused by test callback" }
    }
    var body: some View {
        VStack {
            Text("SHARED PICKER TEST • INJECTED CALLBACK REFUSAL")
            Button("Add Attachment") { menu = true }.disabled(saving)
            Text("Attempts: \(attempts); accepted: \(accepted)").accessibilityIdentifier("capture-batch-result")
            if let failure { Text(failure).accessibilityIdentifier("capture-batch-error") }
        }
        .modifier(MediaCapturePresentation(showAddSourceMenu: $menu, isUploading: $saving,
            uploadError: $failure, remainingSlots: 5,
            onUploadAttachmentFile: { _ in
                attempts += 1
                if attempts == 1 { throw Refusal.firstFile }
                accepted += 1
            }))
    }
}

/// Real encrypted local runtime; only downloaded server records are synthetic.
/// The system picker and Transaction section below are their normal components.
struct TransactionCaptureUITestFixture: View {
    let environment: ValidatedLedgerEnvironment
    let fixtureID: UUID
    @State private var runtime: LedgerOfflineClientRuntime?
    @State private var failure: String?
    @State private var verifiedOriginals = false

    var body: some View {
        ScrollView {
            VStack {
                Text("LOCAL CAPTURE TEST • NO NETWORK")
                if let runtime {
                    if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-expense-capture") {
                        ExpenseCaptureUITestContent(runtime: runtime,
                            accountId: try! AccountID(validating: "capture-ui-\(fixtureID.uuidString)"))
                    } else {
                    TransactionAttachmentsSection(
                        scope: .businessInventory(accountId: try! AccountID(validating: "capture-ui-\(fixtureID.uuidString)")),
                        transactionId: try! TransactionID(validating: "capture-ui-parent"),
                        section: .receipts, reader: runtime)
                    Button("Simulate rejected upload") {
                        Task {
                            do { try await runtime.rejectTransactionAttachmentUIFixture() }
                            catch { failure = String(describing: error) }
                        }
                    }
                    Button("Verify local originals") {
                        Task {
                            do {
                                let catalog = try await runtime.readDownloadedTransactionAttachments(
                                    scope: .businessInventory(accountId: AccountID(validating: "capture-ui-\(fixtureID.uuidString)")),
                                    transactionId: TransactionID(validating: "capture-ui-parent"), section: .receipts)
                                guard catalog.attachments.count == 2 else { return }
                                let first = catalog.attachments[0], second = catalog.attachments[1]
                                let original = try await runtime.loadDownloadedTransactionAttachment(catalog: catalog,
                                    attachment: first, allowDownload: false)
                                let pasted = try await runtime.loadDownloadedTransactionAttachment(catalog: catalog,
                                    attachment: second, allowDownload: false)
                                verifiedOriginals = original != nil && original == pasted && first.id != second.id
                                    && first.isPrimary && !second.isPrimary
                            } catch { failure = String(describing: error) }
                        }
                    }
                    if verifiedOriginals { Text("Original bytes match; distinct attachments").accessibilityIdentifier("capture-originals-verified") }
                    }
                } else if let failure {
                    Text(failure).accessibilityIdentifier("capture-ui-error")
                } else { ProgressView("Opening local fixture…") }
            }.padding()
        }
        .task {
            guard runtime == nil else { return }
            do {
                runtime = try await LedgerPowerSyncLocalBootstrap.openTransactionAttachmentUIFixture(
                    validatedEnvironment: environment, fixtureID: fixtureID)
            } catch { failure = String(describing: error) }
        }
        // The fixture runtime lives until this test app process terminates;
        // presenting a full-screen picker must not close its database.
    }
}

/// Reuses the real Expense form and encrypted runtime; no fake draft persistence.
private struct ExpenseCaptureUITestContent: View {
    let runtime: LedgerOfflineClientRuntime
    let accountId: AccountID
    private let projectId = try! ProjectID(validating: "capture-ui-project")
    @State private var creating = false
    @State private var recovery: ExpenseEntryRecovery?
    @State private var entries: [ExpenseEntryRecovery] = []
    @State private var editing: ProjectExpenses.Expense?
    @State private var pendingEdit = false
    @State private var failure: String?

    private var isEditing: Bool {
        ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-expense-edit-capture")
    }

    var body: some View {
        VStack {
            Button(isEditing ? "Edit Expense" : "New Expense") { creating = true }
                .disabled(isEditing && editing == nil)
            if pendingEdit { Text("Expense edit saved offline").accessibilityIdentifier("capture-expense-edit-pending") }
            ForEach(entries) { entry in
                Button(entry.vendor.isEmpty ? "Unfinished Expense" : entry.vendor) { recovery = entry }
                    .accessibilityIdentifier("capture-unfinished-expense")
            }
            if let failure { Text(failure).accessibilityIdentifier("capture-ui-error") }
        }
        .sheet(isPresented: $creating) { form(nil) }
        .sheet(item: $recovery) { form($0) }
        .task {
            do {
                for try await value in runtime.watchExpenses(accountId: accountId, projectId: projectId) {
                    entries = isEditing ? value?.unfinishedEdits ?? [] : value?.unfinishedEntries ?? []
                    editing = isEditing ? value?.expenses.first : nil
                    pendingEdit = !(value?.pendingEdits.isEmpty ?? true)
                }
            } catch { failure = String(describing: error) }
        }
    }

    private func form(_ entry: ExpenseEntryRecovery?) -> some View {
        ExpenseCreationView(accountId: accountId, projectId: projectId,
            currency: try! CurrencyCode(validating: "USD"), service: runtime, recovery: entry, editing: editing,
            onSaved: { _ in })
    }
}

/// Rendering/interaction proof only, not a Transaction browser implementation.
struct TransactionCardUITestFixture: View {
    @State private var find = FindStateManager()
    @State private var selected = false
    @State private var bookmarked = false
    @State private var opened = 0
    @State private var copied = false

    var body: some View {
        VStack {
            TransactionCardPresentation(id: "transaction-fixture", title: "Fixture vendor",
                source: "Fixture vendor", amountText: "$100.00", dateText: "Sep 13, 2026",
                itemCount: 2, budgetCategoryName: "Furnishings", assignmentLabel: "Office",
                projectName: "Business Inventory", matchingTransactionID: "transaction-fixture",
                notesPreview: "Existing card notes", badges: [CardBadge(text: "Purchase", color: BrandColors.primary)],
                isSelected: $selected, bookmarked: bookmarked, onBookmarkPress: { bookmarked.toggle() },
                menuItems: [ActionMenuItem(id: "copy", label: "Copy ID", icon: "doc.on.doc", onPress: { copied = true })],
                onPress: { opened += 1 })
            Text("Selected: \(selected ? "yes" : "no"); opened: \(opened); copied: \(copied ? "yes" : "no")")
                .accessibilityIdentifier("transaction-card-actions")
        }
        .padding()
        .environment(find)
    }
}

/// Uses the actual target browser/detail, replacing only the watched data source.
struct TransactionBrowserUITestFixture: View {
    var projectPayment = false
    @State private var reader = TransactionBrowserFixtureReader()
    var body: some View {
        NavigationStack {
            ScrollView {
                TargetTransactionBrowserView(scope: projectPayment
                    ? .project(accountId: try! AccountID(validating: "fixture-account"),
                        projectId: try! ProjectID(validating: "fixture-project"), clientId: try! ClientID(validating: "fixture-client"))
                    : .businessInventory(accountId: try! AccountID(validating: "fixture-account")),
                    scopeName: projectPayment ? "Fixture Project" : "Business Inventory", reader: reader)
                    .padding()
            }
            .toolbar { Button("Withdraw access") { reader.withdraw() } }
        }
    }
}

final class TransactionBrowserFixtureReader: TransactionBrowsing, TransactionExportReading, DownloadedItemPlacementHistoryReading, DownloadedTransactionAttachmentReading, Sendable {
    private let updates = NSLockingTransactionFixtureUpdates()
    static let imageBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jH1sAAAAASUVORK5CYII=")!
    @MainActor static let pdfBytes: Data = {
        let document = PDFDocument()
        #if os(iOS)
        let image = UIImage(data: imageBytes)!
        #else
        let image = NSImage(data: imageBytes)!
        #endif
        document.insert(PDFPage(image: image)!, at: 0)
        return document.dataRepresentation()!
    }()
    func readDownloadedTransactionAttachments(scope: TransactionScope, transactionId: TransactionID,
        section: TransactionAttachmentSection) async throws -> DownloadedTransactionAttachments {
        guard updates.hasAccess else { throw DownloadedTransactionAttachments.Failure.unavailable }
        var attachments: [DownloadedTransactionAttachment] = []
        if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-transaction-attachments") {
            let kinds = section == .receipts ? ["pdf", "image", "image"] : ["image"]
            for (index, kind) in kinds.enumerated() {
                let bytes = kind == "pdf" ? await Self.pdfBytes : Self.imageBytes
                let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                let id = "fixture-\(section.rawValue)-\(index)"
                let object = try DownloadedMediaObjectReference(accountId: scope.accountId, attachmentId: id,
                    sha256: hash, byteCount: String(bytes.count), mediaType: kind == "pdf" ? "application/pdf" : "image/png",
                    storagePath: "accounts/\(scope.accountId.rawValue)/attachments/\(id)/\(hash)", kind: kind == "pdf" ? .pdf : .image)
                attachments.append(try .init(id: .init(validating: id), object: object, position: index,
                    isPrimary: index == 0, fileName: kind == "pdf" ? "Vendor receipt.pdf" : "Photo \(index).png"))
            }
        }
        return try .init(scope: scope, transactionId: transactionId, section: section,
            revision: 1, isComplete: true, attachments: attachments)
    }
    func watchDownloadedTransactionAttachments(scope: TransactionScope, transactionId: TransactionID,
        section: TransactionAttachmentSection) -> AsyncThrowingStream<DownloadedTransactionAttachments?, Error> {
        let stream = AsyncThrowingStream<DownloadedTransactionAttachments?, Error>.makeStream()
        let id = UUID()
        updates.addAttachment(stream.continuation, id: id)
        let task = Task {
            do { stream.continuation.yield(try await readDownloadedTransactionAttachments(scope: scope,
                transactionId: transactionId, section: section)) }
            catch { stream.continuation.yield(nil) }
        }
        stream.continuation.onTermination = { [updates] _ in task.cancel(); updates.removeAttachment(id) }
        return stream.stream
    }
    func loadDownloadedTransactionAttachment(catalog: DownloadedTransactionAttachments,
        attachment: DownloadedTransactionAttachment, allowDownload: Bool) async throws -> Data? {
        let current = try await readDownloadedTransactionAttachments(scope: catalog.scope,
            transactionId: catalog.transactionId, section: catalog.section)
        guard current == catalog, current.attachments.contains(attachment) else {
            throw DownloadedTransactionAttachments.Failure.unavailable
        }
        return attachment.object.mediaType == "application/pdf" ? await Self.pdfBytes : Self.imageBytes
    }
    func watchTransactions(scope: TransactionScope) -> AsyncThrowingStream<TransactionBrowserUpdate, Error> {
        let stream = AsyncThrowingStream<TransactionBrowserUpdate, Error>.makeStream()
        let id = UUID()
        updates.add(stream.continuation, id: id)
        stream.continuation.onTermination = { [updates] _ in updates.remove(id) }
        guard updates.hasAccess else {
            stream.continuation.yield(.unavailable)
            return stream.stream
        }
        do {
            let wire = """
            {"accountId":"fixture-account","principalId":"fixture-member","transactionId":"transaction-browser-fixture",
            "scopeKind":"business_inventory","projectId":null,"clientId":null,"type":"purchase","role":"standalone",
            "origin":"vendor_payment","amountMinorUnits":"10000","currency":"USD",
            "category":{"id":"fixture-category","name":"Furnishings","kind":"itemized","revision":"1"},
            "source":"Fixture vendor","transactionDate":"2024-02-29","createdAtMilliseconds":"1709251200123",
            "notes":"Existing Transaction notes","paymentMethod":"Company card","hasEmailReceipt":null}
            """
            var payload = try JSONSerialization.jsonObject(with: Data(wire.utf8)) as! [String: Any]
            payload["accountId"] = scope.accountId.rawValue
            if scope.ownerKind == .project {
                payload["scopeKind"] = "project"
                payload["projectId"] = scope.projectId?.rawValue
                payload["clientId"] = scope.clientId?.rawValue
                payload["origin"] = "firebase_client_payment"
                payload["category"] = NSNull()
                payload["source"] = "Client payment"
                payload["currentItemCategories"] = [["itemId": "linked", "placementId": "linked-project",
                    "categoryId": "fixture-category"]]
                var contents: [String: Any] = ["accountId": scope.accountId.rawValue, "principalId": "fixture-member",
                    "transactionId": "transaction-browser-fixture", "projectId": scope.projectId!.rawValue,
                    "clientId": scope.clientId!.rawValue,
                    "connections": [["id":"current-link","itemId":"linked","placementId":"linked-project"]],
                    "items": [["itemId":"linked","name":"Current lamp","imageCount":"0"]]]
                if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-payment-history") {
                    contents["connections"] = [["id":"current-link","itemId":"linked","placementId":"linked-project"],
                        ["id":"closed-link","itemId":"sold","placementId":"old-project-placement","endedAt":"2024-02-01"]]
                    contents["items"] = [["itemId":"linked","name":"Current lamp","imageCount":"0"],
                        ["itemId":"sold","name":"Historical chair","currentSpaceName":"Other Project","imageCount":"0"]]
                    contents["invoice"] = ["invoice_id":"invoice-fixture","invoice_revision":"1","account_id":scope.accountId.rawValue,
                        "project_id":scope.projectId!.rawValue,"client_id":scope.clientId!.rawValue,"purchase_id":"transaction-browser-fixture",
                        "currency":"USD","total_minor_units":"4500","lines":[
                            ["id":"frozen-item-line","line_position":0,"source_kind":"item","source_id":"occurrence","item_id":"sold",
                             "source_revision":"1","category_id":"fixture-category","signed_amount_minor_units":"4000",
                             "description":"Frozen chair at collection","source_snapshot_json":"{\"item\":{\"itemId\":\"sold\",\"occurrenceId\":\"occurrence\",\"price\":{\"basis\":{\"projectPrice\":{}},\"amount\":{\"minorUnits\":4000,\"currency\":\"USD\"}}}}"],
                            ["id":"frozen-expense-line","line_position":1,"source_kind":"expense","source_id":"expense","item_id":NSNull(),
                             "source_revision":"1","category_id":"fixture-category","signed_amount_minor_units":"500",
                             "description":"Delivery at collection","source_snapshot_json":"{\"expense\":{\"expenseId\":\"expense\"}}"]]]
                }
                payload["paymentContents"] = contents
            } else {
                payload["legacySubtotalMinorUnits"] = "9250"
                payload["legacyTaxRatePct"] = "8.125"
                var receipt = payload
                receipt["items"] = [
                    ["itemId": "linked", "amountMinorUnits": "6000", "membershipKind": "linked", "name": "Current lamp"],
                    ["itemId": "sold", "amountMinorUnits": "4000", "membershipKind": "sold", "name": "Historical chair"]]
                receipt["nonItemReceiptLines"] = [] as [String]
                if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-transaction-groups") {
                    receipt["items"] = [
                        ["itemId": "linked", "amountMinorUnits": "3000", "membershipKind": "linked", "name": "Current lamp", "sku": "LAMP", "source": "Original vendor", "currentSource": "Display vendor", "currentSpaceName": "Kitchen", "imageCount": "0"],
                        ["itemId": "linked-copy", "amountMinorUnits": "3000", "membershipKind": "linked", "name": "Current lamp", "sku": "LAMP", "source": "Original vendor", "currentSource": "Copy display vendor", "currentSpaceName": "Office", "imageCount": "1"],
                        ["itemId": "sold", "amountMinorUnits": "4000", "membershipKind": "sold", "name": "Historical chair"]]
                }
                payload["receipt"] = receipt
            }
            stream.continuation.yield(.partial([try JSONDecoder().decode(TransactionDetailSnapshot.self,
                from: JSONSerialization.data(withJSONObject: payload))]))
        } catch { stream.continuation.finish(throwing: error) }
        return stream.stream
    }
    func withdraw() { updates.withdraw() }
    func readTransactionExport(scope: TransactionScope, orderedTransactionIDs: [TransactionID]?,
                               asOf: ProtectedArtifactEpochMilliseconds) async throws -> TransactionExportSnapshot {
        // Synthetic source completeness only; actual provider evidence is separate.
        for try await update in watchTransactions(scope: scope) {
            guard case .partial(let rows) = update, updates.hasAccess else {
                throw TransactionExportSnapshot.Failure.incomplete
            }
            let snapshot = try TransactionExportSnapshot(scope: scope, principalId: PrincipalID(validating: "fixture-member"), update: .ready(rows),
                orderedTransactionIDs: orderedTransactionIDs, asOf: asOf, sourceVersion: .init(validating: "fixture-v1"),
                visibilityScopeID: .make(bytes: Data(scope.accountId.rawValue.utf8)),
                authorityVersion: .init(validating: "transaction-export-v1"))
            if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-export-watch-finish") {
                updates.finishTransactions()
            }
            return snapshot
        }
        throw TransactionExportSnapshot.Failure.incomplete
    }
    func readDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) async throws -> DownloadedItemPlacementHistory {
        guard accountId.rawValue == "fixture-account", ["linked", "linked-copy", "sold"].contains(itemId.rawValue) else {
            throw TransactionReceiptSnapshot.Failure.scopeMismatch
        }
        let sold = itemId.rawValue == "sold"
        let name = sold ? "Historical chair" : "Current lamp"
        var history: [PhysicalItemPlacementHistoryInterval] = [
            .init(placementId: try EntityID(validating: "\(itemId.rawValue)-inventory"), scope: .businessInventory,
                spaceId: nil, startedAt: "2024-01-01", endedAt: sold ? "2024-02-01" : nil)]
        if sold { history.insert(.init(placementId: try EntityID(validating: "sold-project"),
            scope: .project(try ProjectID(validating: "other-project")), spaceId: nil, projectDisplayName: "Other Project",
            startedAt: "2024-02-01", endedAt: nil), at: 0) }
        var invoices: [DownloadedItemInvoiceLine] = []
        if sold && ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-payment-history") {
            let amount = try Money(minorUnits: 4000, currency: .init(validating: "USD"))
            let line = try FrozenInvoiceLine(id: .init(validating: "frozen-item-line"),
                scope: .project(accountId: accountId, projectId: .init(validating: "fixture-project"), clientId: .init(validating: "fixture-client")),
                source: .item(itemId: itemId, occurrenceId: .init(validating: "occurrence"),
                    price: .init(basis: .importedInvoiceAmount, amount: amount)),
                sourceRevision: 1, categoryId: .init(validating: "fixture-category"), signedAmount: amount,
                description: "Frozen chair at collection")
            invoices = [try .init(invoiceId: .init(validating: "invoice-fixture"),
                purchaseId: .init(validating: "transaction-browser-fixture"), line: line, invoiceNumber: "INV-001")]
        }
        return try .init(accountId: accountId, itemId: itemId, description: name, intervals: history,
            details: .init(name: name, description: name, notes: "Same physical Item"), invoiceLines: invoices)
    }
    func watchDownloadedItemPlacementHistory(accountId: AccountID, itemId: ItemID) -> AsyncThrowingStream<DownloadedItemPlacementHistory, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do { continuation.yield(try await readDownloadedItemPlacementHistory(accountId: accountId, itemId: itemId)) }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Test-only broadcast storage; each navigation entry needs a fresh stream.
final class NSLockingTransactionFixtureUpdates: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: AsyncThrowingStream<TransactionBrowserUpdate, Error>.Continuation] = [:]
    private var attachments: [UUID: AsyncThrowingStream<DownloadedTransactionAttachments?, Error>.Continuation] = [:]
    private var withdrawn = false
    private var invoiceReportReadCount = 0
    private var expenseEdit: ProjectExpenses.PendingEdit?
    private var invoiceCreation: PendingInvoiceCreation?
    private var invoiceRevision: PendingInvoiceRevision?
    var pendingInvoiceRevision: PendingInvoiceRevision? { lock.withLock { invoiceRevision } }
    func saveInvoiceRevision(_ value: PendingInvoiceRevision) { lock.withLock { invoiceRevision = value } }
    private var feeCreation: PendingFeeCreation?
    var pendingFeeCreation: PendingFeeCreation? { lock.withLock { feeCreation } }
    func saveFeeCreation(_ value: PendingFeeCreation) { lock.withLock { feeCreation = value } }
    private var firstFeeAttempt: (UUID, Date, FeeInstallmentDraft)?
    func isExactFeeRetry(_ id: UUID, date: Date, draft: FeeInstallmentDraft) -> Bool {
        lock.withLock {
            guard let firstFeeAttempt else { firstFeeAttempt = (id, date, draft); return false }
            return firstFeeAttempt.0 == id && firstFeeAttempt.1 == date && firstFeeAttempt.2 == draft
        }
    }
    private var changedInvoiceSource = false
    var invoiceSourceHasChanged: Bool { lock.withLock { changedInvoiceSource } }
    func changeInvoiceSource() { lock.withLock { changedInvoiceSource = true } }
    private var firstInvoiceAttempt: (UUID, Date, CreateInvoiceCommand.Payload)?
    private var firstReturnAttempt: (UUID, Date, ReturnUninvoicedItemsPayload)?
    func isExactReturnRetry(_ id: UUID, date: Date, payload: ReturnUninvoicedItemsPayload) -> Bool {
        lock.withLock {
            guard let firstReturnAttempt else { firstReturnAttempt = (id, date, payload); return false }
            return firstReturnAttempt.0 == id && firstReturnAttempt.1 == date && firstReturnAttempt.2 == payload
        }
    }
    func isExactInvoiceRetry(_ id: UUID, date: Date, payload: CreateInvoiceCommand.Payload) -> Bool {
        lock.withLock {
            guard let firstInvoiceAttempt else { firstInvoiceAttempt = (id, date, payload); return false }
            return firstInvoiceAttempt.0 == id && firstInvoiceAttempt.1 == date && firstInvoiceAttempt.2 == payload
        }
    }
    var pendingInvoiceCreation: PendingInvoiceCreation? { lock.withLock { invoiceCreation } }
    func saveInvoiceCreation(_ value: PendingInvoiceCreation) { lock.withLock { invoiceCreation = value } }
    private var expenseObservers: [UUID: AsyncThrowingStream<ProjectExpenses?, Error>.Continuation] = [:]
    var pendingExpenseEdit: ProjectExpenses.PendingEdit? { lock.withLock { expenseEdit } }
    func saveExpenseEdit(_ edit: ProjectExpenses.PendingEdit) { lock.withLock { expenseEdit = edit } }
    func observeExpenses(_ value: AsyncThrowingStream<ProjectExpenses?, Error>.Continuation, id: UUID) {
        lock.withLock { expenseObservers[id] = value }
    }
    func removeExpenseObserver(_ id: UUID) { lock.withLock { expenseObservers[id] = nil } }
    func publishExpenses(_ snapshot: ProjectExpenses) {
        let observers = lock.withLock { Array(expenseObservers.values) }
        for observer in observers { observer.yield(snapshot) }
    }
    func rejectFirstInvoiceExport() -> Bool {
        lock.withLock {
            invoiceReportReadCount += 1
            // Preview, protected handoff, then the user's Save confirmation.
            // Reject the Save check, not the earlier pre-dialog handoff check.
            return invoiceReportReadCount == 3
        }
    }
    var hasAccess: Bool { lock.withLock { !withdrawn } }
    func add(_ value: AsyncThrowingStream<TransactionBrowserUpdate, Error>.Continuation, id: UUID) {
        lock.withLock { values[id] = value }
    }
    func remove(_ id: UUID) { lock.withLock { values[id] = nil } }
    func finishTransactions() {
        let current = lock.withLock { Array(values.values) }
        for value in current { value.finish() }
    }
    func addAttachment(_ value: AsyncThrowingStream<DownloadedTransactionAttachments?, Error>.Continuation, id: UUID) {
        lock.withLock { attachments[id] = value }
    }
    func removeAttachment(_ id: UUID) { lock.withLock { attachments[id] = nil } }
    func withdraw() {
        let current = lock.withLock { withdrawn = true; return Array(values.values) }
        for value in current { value.yield(.unavailable) }
        let media = lock.withLock { Array(attachments.values) }
        for value in media { value.yield(nil) }
    }
}
#endif
