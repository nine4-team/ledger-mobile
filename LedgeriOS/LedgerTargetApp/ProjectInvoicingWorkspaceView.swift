import LedgerTargetCore
import SwiftUI
import PDFKit

/// Canonical data orchestration; layout, disclosures and rows are original Billing components.
struct ProjectInvoicingWorkspaceView: View {
    let runtime: any ProjectInvoicingReading
    let accountId: AccountID
    let projectId: ProjectID
    let currency: CurrencyCode
    var projectName: String = "Project name unavailable"
    var clientName: String = ""
    @State private var items: ProjectInvoicingItems?
    @State private var expenses: ProjectExpenses?
    @State private var invoices: [FrozenInvoiceContents]?
    @State private var liveInvoices: [LiveInvoiceContents]?
    @State private var liveInvoiceError: String?
    @State private var invoiceError: String?
    @State private var invoiceFilter: InvoicePipelineFilter = .all
    @State private var itemError: String?
    @State private var expenseError: String?
    @State private var search = ""
    @State private var sourceFilter: CandidateSourceFilter = .all
    @State private var availabilityFilter: CandidateAvailabilityFilter = .all
    @State private var showingFilters = false
    @State private var itemsExpanded = true
    @State private var expensesExpanded = true
    @State private var feesExpanded = false
    @State private var invoicesExpanded = false
    @State private var creatingExpense = false
    @State private var recoveringExpense: ExpenseEntryRecovery?
    @State private var saveNotice: String?

    var body: some View {
        BillingWorkspacePresentation {
            if let saveNotice { BillingEmptyRow(saveNotice) }
            BillingReceivablesToolbar(searchText: $search, filtersAreActive: availabilityFilter != .all,
                onFilter: { showingFilters = true })
            SegmentedControl(selection: $sourceFilter, options: CandidateSourceFilter.allCases.map(\.segmentOption))
            if sourceFilter == .all || sourceFilter == .items {
            CollapsibleSection(title: "Items", isExpanded: $itemsExpanded) {
                if let itemError { BillingEmptyRow(itemError) }
                else if let items {
                    let rows = items.rows.filter { $0.matches(search: search,
                        availability: InvoicingAvailability(rawValue: availabilityFilter.rawValue)) }
                    if rows.isEmpty { BillingEmptyRow("No matching Item charges in downloaded data.") }
                    ForEach(rows) { row in
                        BillingCandidateRowPresentation(title: row.title, metadata: row.categoryName ?? "Item",
                            amountText: amount(row.amount), statusLabel: row.availability.rawValue.capitalized,
                            statusColor: row.availability == .paid ? StatusColors.metText : BrandColors.textSecondary,
                            invoiceName: row.invoiceName)
                    }
                    BillingEmptyRow("Credit and live-Invoice status coverage is not complete in this build.")
                } else { ProgressView("Downloading Item charges") }
            }
            }
            if sourceFilter == .all || sourceFilter == .expenses {
            CollapsibleSection(title: "Expenses", isExpanded: $expensesExpanded,
                onAdd: runtime is any ExpenseCreating && expenses != nil ? { recoveringExpense = nil; creatingExpense = true } : nil) {
                if let expenseError { BillingEmptyRow(expenseError) }
                else if availabilityFilter != .all && availabilityFilter != .paid {
                    BillingEmptyRow("Expense Invoice status has not been downloaded; this status filter cannot be applied yet.")
                } else if let expenses {
                    if availabilityFilter == .paid && expenses.expenses.contains(where: { $0.collectedInvoice == nil }) {
                        BillingEmptyRow("Some Expense Invoice statuses are unavailable; only confirmed paid Expenses are shown.")
                    }
                    ForEach(availabilityFilter == .all ? expenses.unfinishedEntries : []) { entry in
                        Button {
                            recoveringExpense = entry
                        } label: {
                            BillingCandidateRowPresentation(title: entry.vendor.isEmpty ? "Unfinished Expense" : entry.vendor,
                                metadata: "Saved form on this device", amountText: entry.amountText,
                                statusLabel: "Finish entry", statusColor: BrandColors.textSecondary, invoiceName: nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("target-unfinished-expense-\(entry.id.rawValue)")
                    }
                    let rows = expenses.expenses.filter { row in
                        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
                        return (availabilityFilter == .all || row.collectedInvoice != nil)
                            && (query.isEmpty || [row.entry.vendor, row.entry.notes, row.entry.date].contains { $0.localizedStandardContains(query) })
                    }
                    let pending = expenses.pendingCreations.filter { row in
                        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
                        return availabilityFilter == .all && (query.isEmpty || [row.entry.vendor, row.entry.notes, row.entry.date].contains { $0.localizedStandardContains(query) })
                    }
                    if rows.isEmpty && pending.isEmpty && expenses.unfinishedEntries.isEmpty { BillingEmptyRow("No matching Expenses in downloaded data.") }
                    ForEach(pending) { row in
                        NavigationLink(value: row.entry.expenseId) {
                        BillingCandidateRowPresentation(title: row.entry.vendor, metadata: row.entry.date,
                            amountText: amount(row.entry.finalAmount),
                            statusLabel: row.state == .rejected ? "Not saved to server — needs review"
                                : row.state == .applied ? "Saved — waiting for download" : "Saved on device — pending sync",
                            statusColor: BrandColors.textSecondary, invoiceName: nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("target-pending-expense-\(row.entry.expenseId.rawValue)")
                    }
                    ForEach(rows) { row in
                        NavigationLink(value: row.id) {
                        BillingCandidateRowPresentation(title: row.entry.vendor, metadata: row.entry.date,
                            amountText: amount(row.entry.finalAmount), statusLabel: row.collectedInvoice == nil ? "Invoice status unavailable" : "Paid",
                            statusColor: BrandColors.textSecondary, invoiceName: nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("target-invoicing-expense-\(row.id.rawValue)")
                    }
                } else { ProgressView("Downloading Expenses") }
            }
            }
            if sourceFilter == .all || sourceFilter == .fees {
            CollapsibleSection(title: "Fees", isExpanded: $feesExpanded) {
                BillingEmptyRow("Canonical Fee browsing is not connected yet.")
            }
            }
            CollapsibleSection(title: "Invoices", isExpanded: $invoicesExpanded) {
                VStack(alignment: .leading, spacing: Spacing.cardListGap) {
                    SegmentedControl(selection: $invoiceFilter,
                        options: InvoicePipelineFilter.allCases.map(\.segmentOption))
                    if let invoiceError { BillingEmptyRow(invoiceError) }
                    else if let invoices {
                        if invoiceFilter == .all || invoiceFilter == .paid {
                            if invoices.isEmpty { BillingEmptyRow("No paid Invoices in downloaded data.") }
                            ForEach(invoices, id: \.invoiceId) { invoice in
                                NavigationLink(value: invoice.invoiceId) {
                                BillingRowSurface(isMuted: true) {
                                    HStack(alignment: .center, spacing: Spacing.md) {
                                        BillingInvoiceSummaryPresentation(title: invoice.displayMetadata?.invoiceNumber ?? "Invoice",
                                            amountText: amount(invoice.total), date: invoice.displayMetadata?.displayDate)
                                        Spacer(minLength: Spacing.sm)
                                        BillingInvoiceStatusPresentation(label: "Paid", color: StatusColors.metText)
                                    }
                                }
                                }.buttonStyle(.plain)
                                .accessibilityIdentifier("target-invoicing-invoice-\(invoice.invoiceId.rawValue)")
                            }
                        }
                        if invoiceFilter == .all || invoiceFilter == .created || invoiceFilter == .sent {
                            if let liveInvoiceError { BillingEmptyRow(liveInvoiceError) }
                            else if let liveInvoices {
                                let visible = liveInvoices.filter { invoiceFilter == .all || $0.status.rawValue == invoiceFilter.rawValue }
                                if visible.isEmpty { BillingEmptyRow("No matching live Invoices in downloaded data.") }
                                ForEach(visible, id: \.invoiceId) { invoice in
                                    NavigationLink(value: invoice.invoiceId) {
                                        BillingRowSurface(isMuted: false) {
                                            HStack(spacing: Spacing.md) {
                                                BillingInvoiceSummaryPresentation(title: invoice.name.isEmpty ? "Invoice" : invoice.name,
                                                    amountText: amount(invoice.total), date: nil)
                                                Spacer(minLength: Spacing.sm)
                                                BillingInvoiceStatusPresentation(label: invoice.status.rawValue.capitalized, color: BrandColors.textSecondary)
                                            }
                                        }
                                    }.buttonStyle(.plain)
                                    .accessibilityIdentifier("target-invoicing-invoice-\(invoice.invoiceId.rawValue)")
                                }
                            } else { ProgressView("Downloading live Invoices") }
                        }
                        if invoiceFilter == .all || invoiceFilter == .canceled {
                            BillingEmptyRow("Canceled Invoice coverage is not connected yet.")
                        }
                        BillingEmptyRow("Invoice lifecycle actions are still being connected.")
                    } else { ProgressView("Downloading Invoices") }
                }.padding(.top, Spacing.xs)
            }
        }
        .navigationTitle("Invoicing")
        .onChange(of: expenses == nil) { _, unavailable in
            if unavailable, creatingExpense || recoveringExpense != nil {
                creatingExpense = false
                recoveringExpense = nil
                saveNotice = "Expense access is unavailable. Previously saved work remains on this device."
            }
        }
        .adaptivePresentation(isPresented: $creatingExpense, style: .form) {
            expenseForm(recovery: nil)
        }
        .adaptivePresentation(item: $recoveringExpense, style: .form) { entry in
            expenseForm(recovery: entry)
        }
        .navigationDestination(for: ExpenseID.self) { id in
            InvoicingExpenseDetail(runtime: runtime, accountId: accountId, projectId: projectId, expenseId: id)
        }
        .navigationDestination(for: InvoiceID.self) { id in
            InvoicingInvoicePreview(runtime: runtime, accountId: accountId, projectId: projectId,
                invoiceId: id, projectName: projectName, clientName: clientName)
        }
        .adaptivePresentation(isPresented: $showingFilters, style: .selectionMenu) {
            ActionMenuSheet(title: "Receivable Filters", items: CandidateAvailabilityFilter.allCases.map { option in
                ActionMenuItem(id: "availability-\(option.rawValue)", label: option.label,
                    isSelected: availabilityFilter == option,
                    isFilterActive: availabilityFilter == option && option != .all,
                    onPress: { availabilityFilter = option })
            }, closeOnItemPress: false, onClear: { availabilityFilter = .all })
        }
        .task(id: projectId) {
            items = nil; itemError = nil
            do {
                for try await value in runtime.watchInvoicingCharges(accountId: accountId, projectId: projectId) {
                    if Task.isCancelled { return }; items = value
                }
            } catch { if !Task.isCancelled { items = nil; itemError = "Item charges are unavailable." } }
        }
        .task(id: projectId) {
            expenses = nil; expenseError = nil
            do {
                for try await value in runtime.watchExpenses(accountId: accountId, projectId: projectId) {
                    if Task.isCancelled { return }; expenses = value
                }
            } catch { if !Task.isCancelled { expenses = nil; expenseError = "Expenses are unavailable." } }
        }
        .task(id: projectId) {
            invoices = nil; invoiceError = nil
            do {
                for try await value in runtime.watchCollectedInvoices(accountId: accountId, projectId: projectId) {
                    if Task.isCancelled { return }; invoices = value
                }
            } catch { if !Task.isCancelled { invoices = nil; invoiceError = "Invoices are unavailable." } }
        }
        .task(id: projectId) {
            liveInvoices = nil; liveInvoiceError = nil
            guard let reader = runtime as? any ProjectLiveInvoiceReading else {
                liveInvoiceError = "Live Invoices are not connected in this build."; return
            }
            do {
                for try await value in reader.watchLiveInvoices(accountId: accountId, projectId: projectId) {
                    guard !Task.isCancelled else { return }; liveInvoices = value
                }
                if !Task.isCancelled { liveInvoices = nil; liveInvoiceError = "Live Invoices are unavailable." }
            } catch { if !Task.isCancelled { liveInvoices = nil; liveInvoiceError = "Live Invoices are unavailable." } }
        }
    }

    @ViewBuilder private func expenseForm(recovery: ExpenseEntryRecovery?) -> some View {
        if expenses != nil, let creator = runtime as? any ExpenseCreating {
            ExpenseCreationView(accountId: accountId, projectId: projectId, currency: currency,
                service: creator, recovery: recovery) { receipt in
                saveNotice = "Expense saved on this device (\(receipt.localState.rawValue)). It appears here after sync."
            }
        }
    }

    private func amount(_ value: Money) -> String {
        (Decimal(value.minorUnits) / 100).formatted(.currency(code: value.currency.rawValue))
    }
}

/// Own the watch while pushed; never retain financial details from a stale list snapshot.
private struct InvoicingExpenseDetail: View {
    let runtime: any ProjectInvoicingReading
    let accountId: AccountID
    let projectId: ProjectID
    let expenseId: ExpenseID
    @State private var row: ProjectExpenses.Expense?
    @State private var pending: ProjectExpenses.PendingCreation?
    @State private var pendingEdits: [ProjectExpenses.PendingEdit] = []
    private struct EditSelection: Identifiable {
        let source: ProjectExpenses.Expense
        let recovery: ExpenseEntryRecovery?
        var id: ExpenseID { source.id }
    }
    @State private var editSource: EditSelection?
    @State private var unfinishedEdit: ExpenseEntryRecovery?
    @State private var loading = true
    @State private var find = FindStateManager()
    @State private var selectedReceipt: ExpenseReceiptSelection?

    var body: some View {
        BillingWorkspacePresentation {
            if let entry = row?.entry ?? pending?.entry {
                if let pending {
                    BillingEmptyRow(pending.state == .rejected
                        ? "This Expense was rejected. Your original details are retained below. Closing this view does not discard or resolve it."
                        : pending.state == .applied ? "Saved to the server; waiting for the Expense to download."
                        : "Saved on this device; waiting to sync.")
                }
                BillingRowSurface {
                    VStack(spacing: 0) {
                        DetailRow(label: "Vendor", value: entry.vendor)
                        DetailRow(label: "Date", value: entry.date)
                        DetailRow(label: "Amount", value: amount(entry.finalAmount))
                        DetailRow(label: "Current category", value: row?.currentCategoryName ?? "Not downloaded")
                        DetailRow(label: "Notes", value: entry.notes, showDivider: false)
                    }
                }
                ForEach(entry.receiptLines, id: \.id) { line in
                    DetailRow(label: line.description.rawValue,
                        value: "\(line.effect == .decrease ? "−" : "+")\(amount(line.magnitude))")
                    if let quantity = line.quantity { DetailRow(label: "Quantity", value: String(quantity)) }
                }
                if entry.receiptAttachmentIds.isEmpty { BillingEmptyRow("No receipts attached.") }
                else if let row {
                    ThumbnailGridPresentation(count: row.entry.receiptAttachmentIds.count, showAddTile: false,
                        isPrimary: { _ in false }, thumbnail: { index in
                            let id = row.entry.receiptAttachmentIds[index]
                            if let object = row.receiptObjects.first(where: { $0.attachmentId == id }) {
                                if object.mediaType == "application/pdf" { PDFThumbnailTile(fileName: "Receipt \(index + 1)") }
                                else {
                                    DownloadedMediaPhotoView(identity: object.storagePath,
                                        load: { try await runtime.loadExpenseReceipt(projectId: projectId, expenseId: expenseId,
                                            attachmentId: id, allowDownload: true) }, thumbnail: true, scale: .constant(1))
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel("Receipt image \(index + 1)")
                                }
                            } else { Text("Receipt not downloaded") }
                        }, upload: { _ in EmptyView() }, onThumbnailTap: { index in
                            let id = row.entry.receiptAttachmentIds[index]
                            if let object = row.receiptObjects.first(where: { $0.attachmentId == id }) {
                                selectedReceipt = .init(object: object, objects: row.receiptObjects)
                            }
                        }, onAddTap: {})
                } else {
                    ForEach(Array(entry.receiptAttachmentIds.enumerated()), id: \.element) { index, id in
                        Button("Receipt \(index + 1)") { selectedReceipt = .init(localID: id) }
                    }
                }
                ForEach(pendingEdits) { edit in
                    BillingRowSurface {
                        VStack(alignment: .leading) {
                            Text(edit.state == .rejected ? "Edit rejected — saved details retained" : edit.state == .applied
                                ? "Edit accepted — waiting for updated data" : "Edit saved on this device — waiting to sync")
                            DetailRow(label: "Proposed vendor", value: edit.entry.vendor)
                            DetailRow(label: "Proposed amount", value: amount(edit.entry.finalAmount))
                            DetailRow(label: "Proposed notes", value: edit.entry.notes)
                        }
                    }
                }
                if let row, row.collectedInvoice == nil, pendingEdits.isEmpty,
                   runtime is any ExpenseCreating, runtime is any ExpenseEditing {
                    Button(unfinishedEdit == nil ? "Edit Expense" : "Resume saved edit") {
                        editSource = .init(source: row, recovery: unfinishedEdit)
                    }
                        .disabled(unfinishedEdit.map { $0.editContext?.expectedRevision != row.revision } ?? false)
                        .accessibilityIdentifier("target-expense-edit")
                }
                if let unfinishedEdit {
                    if row?.collectedInvoice != nil {
                        BillingEmptyRow("This Expense was collected after your edit was saved. Your saved details and receipt files are retained; they have not changed the collected Invoice.")
                    } else if unfinishedEdit.editContext?.expectedRevision != row?.revision {
                        BillingEmptyRow("This Expense changed after your edit was saved. Your saved details and receipt files are retained; they have not overwritten the newer Expense.")
                    }
                }
                BillingEmptyRow("Collection is not available in this build.")
            } else if loading { ProgressView("Loading Expense") }
            else { BillingEmptyRow("Expense details are unavailable.") }
        }
        .environment(find)
        .navigationTitle("Expense")
        .sheet(item: $editSource) { source in
            if let creator = runtime as? any ExpenseCreating {
                ExpenseCreationView(accountId: accountId, projectId: projectId, currency: source.source.entry.finalAmount.currency,
                    service: creator, recovery: source.recovery, editing: source.source) { _ in editSource = nil }
            }
        }
        #if os(iOS)
        .fullScreenCover(item: $selectedReceipt) { selection in receiptViewer(selection) }
        #else
        .adaptivePresentation(item: $selectedReceipt, style: .viewer) { selection in receiptViewer(selection) }
        #endif
        .task(id: expenseId) {
            row = nil; pending = nil; pendingEdits = []; unfinishedEdit = nil; loading = true
            do {
                for try await value in runtime.watchExpenses(accountId: accountId, projectId: projectId) {
                    try Task.checkCancellation()
                    row = value?.expenses.first(where: { $0.id == expenseId })
                    pending = value?.pendingCreations.first(where: { $0.entry.expenseId == expenseId })
                    pendingEdits = value?.pendingEdits.filter { $0.entry.expenseId == expenseId } ?? []
                    unfinishedEdit = value?.unfinishedEdits.first { $0.expenseId == expenseId }
                    if row == nil || row?.collectedInvoice != nil { editSource = nil }
                    loading = false
                }
            } catch { if !Task.isCancelled { row = nil; pending = nil; pendingEdits = []; unfinishedEdit = nil; editSource = nil; loading = false } }
            if !Task.isCancelled { row = nil; pending = nil; pendingEdits = []; unfinishedEdit = nil; editSource = nil; loading = false }
        }
        .onDisappear { row = nil; pending = nil; pendingEdits = []; unfinishedEdit = nil }
    }

    private func receiptViewer(_ selection: ExpenseReceiptSelection) -> some View {
        ExpenseReceiptViewer(runtime: runtime, accountId: accountId, projectId: projectId, expenseId: expenseId,
            selection: selection, isPresented: Binding(get: { selectedReceipt != nil }, set: { if !$0 { selectedReceipt = nil } }))
    }

    private func amount(_ value: Money) -> String {
        (Decimal(value.minorUnits) / 100).formatted(.currency(code: value.currency.rawValue))
    }
}

private struct ExpenseReceiptSelection: Identifiable {
    let id: AttachmentID
    let object: DownloadedMediaObjectReference?
    let objects: [DownloadedMediaObjectReference]
    let localID: AttachmentID?
    init(object: DownloadedMediaObjectReference, objects: [DownloadedMediaObjectReference]) {
        id = object.attachmentId; self.object = object; self.objects = objects; localID = nil
    }
    init(localID: AttachmentID) { id = localID; self.localID = localID; object = nil; objects = [] }
}

private struct ExpenseReceiptViewer: View {
    let runtime: any ProjectInvoicingReading
    let accountId: AccountID
    let projectId: ProjectID
    let expenseId: ExpenseID
    let selection: ExpenseReceiptSelection
    @Binding var isPresented: Bool
    @State private var authorized = false
    @State private var localIsPDF: Bool?

    var body: some View {
        Group {
            if authorized {
                if selection.localID != nil {
                    if let localIsPDF {
                        if localIsPDF {
                            AuthorizedPDFViewer(fileName: nil, load: loadLocal, isPresented: $isPresented)
                                .accessibilityIdentifier("target-expense-pdf-viewer")
                        } else {
                            ImageGalleryPresentation(imageIDs: [AnyHashable(selection.id)], initialIndex: 0,
                                isPresented: $isPresented, accessibilityPrefix: "target-expense-gallery") { context in
                                DownloadedMediaPhotoView(identity: selection.id.rawValue, load: loadLocal,
                                    onTap: context.onTap, scale: context.zoom)
                            }
                        }
                    } else { ProgressView("Opening saved receipt") }
                } else if let object = selection.object, object.mediaType == "application/pdf" {
                    AuthorizedPDFViewer(fileName: nil, load: { try await load(object) }, isPresented: $isPresented)
                        .accessibilityIdentifier("target-expense-pdf-viewer")
                } else {
                    let images = selection.objects.filter { $0.mediaType != "application/pdf" }
                    ImageGalleryPresentation(imageIDs: images.map { AnyHashable($0.attachmentId) },
                        initialIndex: images.firstIndex(where: { $0.attachmentId == selection.id }) ?? 0,
                        isPresented: $isPresented, accessibilityPrefix: "target-expense-gallery") { context in
                            let object = images[context.index]
                            DownloadedMediaPhotoView(identity: object.storagePath, load: { try await load(object) },
                                onTap: context.onTap, scale: context.zoom)
                        }
                }
            } else { ProgressView("Loading receipt") }
        }
        .task(id: selection.id) {
            authorized = false
            do {
                for try await value in runtime.watchExpenses(accountId: accountId, projectId: projectId) {
                    try Task.checkCancellation()
                    if selection.localID != nil {
                        guard value?.pendingCreations.contains(where: {
                            $0.entry.expenseId == expenseId && $0.entry.receiptAttachmentIds.contains(selection.id)
                        }) == true else { break }
                        if localIsPDF == nil {
                            guard let bytes = try await loadLocal() else { break }
                            localIsPDF = PDFDocument(data: bytes) != nil
                        }
                    } else {
                        guard value?.expenses.first(where: { $0.id == expenseId })?.receiptObjects == selection.objects else { break }
                    }
                    authorized = true
                }
            } catch { }
            if !Task.isCancelled { authorized = false; isPresented = false }
        }
        .onDisappear { authorized = false; localIsPDF = nil }
    }

    private func loadLocal() async throws -> Data? {
        try await runtime.loadExpenseReceipt(projectId: projectId, expenseId: expenseId,
            attachmentId: selection.id, allowDownload: false)
    }

    private func load(_ object: DownloadedMediaObjectReference) async throws -> Data? {
        try await runtime.loadExpenseReceipt(projectId: projectId, expenseId: expenseId,
            attachmentId: object.attachmentId, allowDownload: true)
    }
}
