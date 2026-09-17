import LedgerTargetCore
import LedgerTargetPowerSync
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
    @State private var selectedItem: ProjectInvoicingItem?
    @State private var expenses: ProjectExpenses?
    @State private var invoices: [FrozenInvoiceContents]?
    @State private var liveInvoices: [LiveInvoiceContents]?
    @State private var pendingInvoices: [PendingInvoiceCreation] = []
    @State private var feeReview: FeeBrowsingReview?
    @State private var pendingFees: [PendingFeeCreation] = []
    @State private var feeError: String?
    private struct FeeCategoryChoice: Identifiable {
        let id = UUID()
        let categories: [FeeCreationCategory]
    }
    @State private var feeCategoryChoice: FeeCategoryChoice?
    @State private var selectedFeeCategory: FeeCreationCategory?
    @State private var feeFormState = FeeInstallmentEntryState()
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
    @State private var expandedFeeCategories: Set<BudgetCategoryID> = []
    @State private var invoicesExpanded = false
    @State private var creatingExpense = false
    @State private var creatingInvoice = false
    @State private var invoiceFormState = InvoiceCreationFormState()
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
                        Button { selectedItem = row } label: {
                        BillingCandidateRowPresentation(title: row.title, metadata: row.categoryName ?? "Item",
                            amountText: amount(row.amount), statusLabel: row.availability.rawValue.capitalized,
                            statusColor: row.availability == .paid ? StatusColors.metText : BrandColors.textSecondary,
                            invoiceName: row.invoiceName)
                        }
                        .buttonStyle(.plain)
                        .disabled(!(runtime is any DownloadedItemPlacementHistoryReading))
                        .accessibilityIdentifier("target-invoicing-item-\(row.id)")
                    }
                    BillingEmptyRow("Credit and live-Invoice status coverage is not complete in this build.")
                } else { ProgressView("Downloading Item charges") }
            }
            }
            if sourceFilter == .all || sourceFilter == .expenses {
            CollapsibleSection(title: "Expenses", isExpanded: $expensesExpanded,
                onAdd: runtime is any ExpenseCreating && expenses != nil ? { recoveringExpense = nil; creatingExpense = true } : nil) {
                if let expenseError { BillingEmptyRow(expenseError) }
                else if let expenses {
                    if availabilityFilter != .all && expenses.expenses.contains(where: { $0.availability == nil }) {
                        BillingEmptyRow("Some Expense Invoice statuses are unavailable; only confirmed matching Expenses are shown.")
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
                        return (availabilityFilter == .all || row.availability?.rawValue == availabilityFilter.rawValue)
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
                            amountText: amount(row.entry.finalAmount), statusLabel: row.availability?.rawValue.capitalized ?? "Invoice status unavailable",
                            statusColor: row.availability == .paid ? StatusColors.metText : BrandColors.textSecondary,
                            invoiceName: row.liveInvoice?.name ?? row.collectedInvoice?.displayMetadata?.invoiceNumber)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("target-invoicing-expense-\(row.id.rawValue)")
                    }
                } else { ProgressView("Downloading Expenses") }
            }
            }
            if sourceFilter == .all || sourceFilter == .fees {
            CollapsibleSection(title: "Fees", isExpanded: $feesExpanded,
                onAdd: feeReview?.canCreate == true ? { beginFeeCreation() } : nil) {
                if let liveInvoiceError { BillingEmptyRow(liveInvoiceError) }
                else if let feeError { BillingEmptyRow(feeError) }
                else {
                    ForEach(pendingFees.filter { search.isEmpty || $0.draft.label.localizedStandardContains(search) }) { pending in
                        BillingCandidateRowPresentation(title: pending.draft.label, metadata: "Fee",
                            amountText: amount(pending.draft.amount),
                            statusLabel: pending.state == .rejected ? "Not saved to server — needs review"
                                : pending.state == .applied ? "Saved — waiting for download" : "Saved on device — pending sync",
                            statusColor: BrandColors.textSecondary, invoiceName: nil)
                    }
                    if let feeReview, let liveInvoices, let invoices {
                        if let groups = try? feeGroups(review: feeReview, live: liveInvoices, paid: invoices) {
                            if groups.isEmpty && pendingFees.isEmpty { BillingEmptyRow("No matching Fees in downloaded data.") }
                            ForEach(groups) { group in
                                feeGroupCard(group, review: feeReview)
                            }
                        } else { BillingEmptyRow("Fee history is unavailable. Please retry after sync.") }
                    } else if let invoiceError { BillingEmptyRow(invoiceError) }
                    else { ProgressView("Downloading Fees") }
                }
            }
            }
            CollapsibleSection(title: "Invoices", isExpanded: $invoicesExpanded,
                onAdd: runtime is any ProjectInvoiceCreating && liveInvoices != nil ? {
                    invoiceFormState.prepareCreation(); creatingInvoice = true
                } : nil) {
                VStack(alignment: .leading, spacing: Spacing.cardListGap) {
                    SegmentedControl(selection: $invoiceFilter,
                        options: InvoicePipelineFilter.allCases.map(\.segmentOption))
                    if let liveInvoiceError { BillingEmptyRow(liveInvoiceError) }
                    if invoiceFilter == .all {
                        ForEach(pendingInvoices) { pending in
                            BillingRowSurface(isMuted: false) {
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    BillingInvoiceSummaryPresentation(title: pending.payload.name.isEmpty ? "Invoice" : pending.payload.name,
                                        amountText: amount(pending.payload.selection.reviewedTotal), date: nil)
                                    BillingInvoiceStatusPresentation(label: pending.state == .rejected ? "Not saved to server — needs review"
                                        : pending.state == .applied ? "Saved — waiting for download" : "Saved on device — pending sync",
                                        color: BrandColors.textSecondary)
                                }
                            }
                            .accessibilityIdentifier("target-pending-invoice-\(pending.payload.invoiceId.rawValue)")
                        }
                    }
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
                            if let liveInvoices {
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
                            } else if liveInvoiceError == nil { ProgressView("Downloading live Invoices") }
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
        .sheet(item: $selectedItem) { selection in
            if let reader = runtime as? any DownloadedItemPlacementHistoryReading {
                DownloadedItemDetailView(accountId: accountId, itemId: selection.occurrence.itemId, reader: reader)
            }
        }
        .onChange(of: items) { _, value in
            if let selectedItem, value?.rows.contains(where: { $0.id == selectedItem.id }) != true {
                self.selectedItem = nil
            }
        }
        .adaptivePresentation(isPresented: $creatingInvoice, style: .form) {
            if let creator = runtime as? any ProjectInvoiceCreating {
                CreateInvoiceModal(accountId: accountId, projectId: projectId, service: creator, state: invoiceFormState) { receipt in
                    saveNotice = "Invoice saved on this device (\(receipt.localState.rawValue))."
                    invoicesExpanded = true
                }
            }
        }
        .onChange(of: liveInvoiceError) { _, error in
            if error != nil {
                creatingInvoice = false; invoiceFormState = InvoiceCreationFormState()
                feeCategoryChoice = nil; selectedFeeCategory = nil
                feeFormState = FeeInstallmentEntryState()
                feeReview = nil; pendingFees = []
            }
        }
        .adaptivePresentation(item: $feeCategoryChoice, style: .selectionMenu) { choice in
            ActionMenuSheet(title: "Choose Budget Category", items: choice.categories.map { category in
                ActionMenuItem(id: category.id.rawValue, label: category.name, onPress: {
                    feeCategoryChoice = nil; feeFormState = FeeInstallmentEntryState(); selectedFeeCategory = category
                })
            })
        }
        .adaptivePresentation(item: $selectedFeeCategory, style: .form) { category in
            if let service = runtime as? any ProjectFeeInstallmentCreating {
                FeeInstallmentEntry(service: service, accountId: accountId, projectId: projectId,
                    category: category, currency: currency, state: feeFormState) { receipt in
                    saveNotice = "Fee saved on this device (\(receipt.localState.rawValue))."
                    feesExpanded = true
                }
            }
        }
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
                if !Task.isCancelled { items = nil; itemError = "Item charges are unavailable." }
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
            liveInvoices = nil; pendingInvoices = []; feeReview = nil; pendingFees = []; feeError = nil; liveInvoiceError = nil
            guard let reader = runtime as? any ProjectLiveInvoiceReading else {
                liveInvoiceError = "Live Invoices are not connected in this build."; return
            }
            do {
                // Saved local intent is readable before network streams finish downloading.
                pendingInvoices = try await (reader as? any ProjectInvoiceCreating)?
                    .readPendingInvoiceCreations(accountId: accountId, projectId: projectId) ?? []
                pendingFees = try await (runtime as? any ProjectFeeInstallmentCreating)?
                    .readPendingFeeCreations(accountId: accountId, projectId: projectId) ?? []
                for try await value in reader.watchLiveInvoices(accountId: accountId, projectId: projectId) {
                    let pending = try await (reader as? any ProjectInvoiceCreating)?
                        .readPendingInvoiceCreations(accountId: accountId, projectId: projectId) ?? []
                    let feePending = try await (runtime as? any ProjectFeeInstallmentCreating)?
                        .readPendingFeeCreations(accountId: accountId, projectId: projectId) ?? []
                    var review: FeeBrowsingReview?
                    do {
                        review = value == nil ? nil : try await (runtime as? any ProjectFeeInstallmentCreating)?
                            .readFeeBrowsingReview(accountId: accountId, projectId: projectId)
                        feeError = nil
                    } catch { feeError = "Fee sources are unavailable." }
                    guard !Task.isCancelled else { return }
                    liveInvoices = value; pendingInvoices = pending; feeReview = review; pendingFees = feePending
                }
                if !Task.isCancelled { liveInvoices = nil; pendingInvoices = []; liveInvoiceError = "Live Invoices are unavailable." }
            } catch { if !Task.isCancelled { liveInvoices = nil; pendingInvoices = []; liveInvoiceError = "Live Invoices are unavailable." } }
        }
    }

    private func beginFeeCreation() {
        guard let service = runtime as? any ProjectFeeInstallmentCreating else { return }
        Task { @MainActor in
            do {
                let categories = try await service.readFeeCreationCategories(accountId: accountId, projectId: projectId)
                guard !Task.isCancelled, liveInvoiceError == nil else { return }
                if let category = categories.first, categories.count == 1 {
                    feeFormState = FeeInstallmentEntryState(); selectedFeeCategory = category
                } else if categories.isEmpty {
                    saveNotice = "No active Fee budget categories are available."
                } else { feeCategoryChoice = FeeCategoryChoice(categories: categories) }
            } catch { saveNotice = "Fee categories are unavailable. Wait for download or check access." }
        }
    }

    private func feeGroups(review: FeeBrowsingReview, live: [LiveInvoiceContents], paid: [FrozenInvoiceContents]) throws -> [ProjectFeeGroup] {
        let rows = try ProjectFeeRow.compose(review: review.sources, live: live, paid: paid)
        let categoryIDs = Set(review.categories.map { $0.category.id })
        guard rows.allSatisfy({ categoryIDs.contains($0.categoryId) }) else { throw ProjectFeeRow.Failure.scopeMismatch }
        return try review.categories.map { entry in
            try ProjectFeeGroup(category: entry.category, rows: rows.filter { $0.categoryId == entry.category.id },
                currency: currency, sortOrders: review.sortOrders)
        }.filter { group in
            let matching = group.rows.filter { $0.matches(search: search, availability: InvoicingAvailability(rawValue: availabilityFilter.rawValue)) }
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            return (query.isEmpty || group.name.localizedStandardContains(query) || !matching.isEmpty)
                && (availabilityFilter == .all || !matching.isEmpty || (availabilityFilter == .available && group.remainingToInvoice.minorUnits > 0))
        }
    }

    private func feeGroupCard(_ group: ProjectFeeGroup, review: FeeBrowsingReview) -> some View {
        let matching = group.rows.filter { $0.matches(search: search, availability: InvoicingAvailability(rawValue: availabilityFilter.rawValue)) }
        let entry = review.categories.first { $0.category.id == group.id }
        let invoicedRatio = group.total.minorUnits > 0 ? min(Double(group.invoiced.minorUnits) / Double(group.total.minorUnits), 1) : 0
        let receivedRatio = group.total.minorUnits > 0 ? min(Double(group.received.minorUnits) / Double(group.total.minorUnits), invoicedRatio) : 0
        return FeeGroupCardPresentation(name: group.name, rowCount: matching.count,
            remainingText: amount(group.remainingToInvoice), totalText: amount(group.total),
            invoicedText: amount(group.invoiced), receivedText: amount(group.received),
            invoicedRatio: invoicedRatio, receivedRatio: receivedRatio,
            isExpanded: Binding(get: { expandedFeeCategories.contains(group.id) }, set: { expanded in
                if expanded { expandedFeeCategories.insert(group.id) } else { expandedFeeCategories.remove(group.id) }
            }), onAddInstallment: entry?.canCreate == true ? {
                guard let entry else { return }
                feeFormState = FeeInstallmentEntryState(); selectedFeeCategory = entry.category
            } : nil) {
                ForEach(matching) { row in
                    BillingCandidateRowPresentation(title: row.title, metadata: row.categoryName ?? "Fee",
                        amountText: amount(row.amount), statusLabel: row.availability.rawValue.capitalized,
                        statusColor: row.availability == .paid ? StatusColors.metText : BrandColors.textSecondary,
                        invoiceName: row.invoiceName)
                    if row.id != matching.last?.id { CardDivider(horizontalPadding: Spacing.cardPadding) }
                }
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
    @State private var exportTask: Task<Void, Never>?
    @State private var exportError: String?

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
                if row != nil {
                    Button("Export Expense", systemImage: "square.and.arrow.up", action: exportExpense)
                        .disabled(exportTask != nil)
                        .accessibilityIdentifier("target-expense-export")
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
        .onChange(of: row == nil) { _, unavailable in
            if unavailable { exportTask?.cancel() }
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
        .onDisappear { exportTask?.cancel(); row = nil; pending = nil; pendingEdits = []; unfinishedEdit = nil }
    }

    private func exportExpense() {
        guard row != nil, exportTask == nil else { return }
        exportTask = Task { @MainActor in
            defer { exportTask = nil }
            do {
                let snapshot = try await ExpenseExportDelivery.read(accountId: accountId, projectId: projectId,
                    expenseId: expenseId, reader: runtime)
                let csv = TransactionExportCalculations.exportExpenseCSV(snapshot: snapshot)
                try await ExpenseExportDelivery.deliver(data: Data(csv.utf8), snapshot: snapshot, reader: runtime) { url in
                    try await PropertyManagementReportSystemDelivery.handoff(url, action: .share)
                }
            } catch is CancellationError { }
            catch { exportError = "The Expense could not be exported. Its data or your access may have changed. Please try again." }
        }
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
