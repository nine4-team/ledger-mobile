import SwiftUI

struct BillingTabView: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @State private var showingCreateInvoice = false
    @State private var overviewExpanded = false
    @State private var receivablesExpanded = false
    @State private var invoicesExpanded = false

    private var projectInvoices: [Invoice] {
        guard let projectId = projectContext.currentProjectId else { return [] }
        return accountContext.allInvoices
            .filter { $0.projectId == projectId }
            .sorted { ($0.dateIssued ?? .distantPast) > ($1.dateIssued ?? .distantPast) }
    }

    var body: some View {
        BillingWorkspacePresentation {
                CollapsibleSection(
                    title: "Overview",
                    isExpanded: $overviewExpanded,
                    badge: "Metrics"
                ) {
                    BillingSummaryCard()
                        .padding(.top, Spacing.xs)
                }

                CandidateReceivablesSection(
                    isExpanded: $receivablesExpanded,
                    onCreateInvoice: { showingCreateInvoice = true }
                )

                InvoiceListSection(
                    invoices: projectInvoices,
                    isExpanded: $invoicesExpanded,
                    onCreateInvoice: { showingCreateInvoice = true }
                )
        }
        .adaptivePresentation(isPresented: $showingCreateInvoice, style: .form) {
            if let accountId = accountContext.currentAccountId,
               let projectId = projectContext.currentProjectId {
                CreateInvoiceModal(accountId: accountId, projectId: projectId)
            }
        }
    }
}

// MARK: - Candidate Receivables

private enum CandidateMembershipState: Equatable {
    case available
    case created(invoiceName: String?)
    case sent(invoiceName: String?)
    case paid(invoiceName: String?)

    var availability: CandidateAvailabilityFilter {
        switch self {
        case .available: .available
        case .created: .created
        case .sent: .sent
        case .paid: .paid
        }
    }

    var label: String {
        switch self {
        case .available: "Available"
        case .created: "Created"
        case .sent: "Sent"
        case .paid: "Paid"
        }
    }

    var invoiceName: String? {
        switch self {
        case .available: nil
        case .created(let name), .sent(let name), .paid(let name): name
        }
    }

    var color: Color {
        switch self {
        case .available: BrandColors.primary
        case .created: BrandColors.textSecondary
        case .sent: StatusColors.inProgressText
        case .paid: StatusColors.metText
        }
    }
}

private struct CandidateReceivablesSection: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AuthManager.self) private var authManager

    @Binding var isExpanded: Bool
    var onCreateInvoice: () -> Void

    @State private var searchText = ""
    @State private var availabilityFilter: CandidateAvailabilityFilter = .available
    @State private var sourceFilter: CandidateSourceFilter = .all
    @State private var showingFilters = false
    @State private var editingFeeCategory: FeeCategoryContext?
    @State private var expandedFeeGroups: Set<String> = []
    @State private var selectedItemId: String?
    @State private var showItemDetail = false
    @State private var selectedTransactionId: String?
    @State private var initialTransaction: Transaction?
    @State private var showTransactionDetail = false

    private var projectId: String? { projectContext.currentProjectId }

    private var projectInvoices: [Invoice] {
        guard let projectId else { return [] }
        return accountContext.allInvoices.filter { $0.projectId == projectId && $0.status != .canceled }
    }

    private var categoryLookup: [String: BudgetCategory] {
        Dictionary(uniqueKeysWithValues: projectContext.budgetCategories.compactMap { category in
            guard let id = category.id else { return nil }
            return (id, category)
        })
    }

    private var membership: InvoiceLineCalculations.BillableMembership? {
        guard let projectId else { return nil }
        return InvoiceLineCalculations.billableMembership(
            projectId: projectId,
            items: projectContext.items,
            transactions: projectContext.transactions,
            invoices: accountContext.allInvoices,
            budgetCategories: categoryLookup
        )
    }

    private var feeGroups: [FeeCategoryContext] {
        projectContext.budgetCategories
            .filter { $0.isFeeCategory && $0.id != nil }
            .compactMap { category in
                guard let id = category.id else { return nil }
                let projectBudget = projectContext.projectBudgetCategories.first { $0.id == id }
                return FeeCategoryContext(
                    id: id,
                    name: category.name,
                    totalCents: projectBudget?.budgetCents,
                    projectBudgetCategory: projectBudget
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var visibleItemRows: [CandidateSourceRow] {
        guard let membership else { return [] }
        var rows: [CandidateSourceRow] = []
        appendItemRows(ids: membership.toInvoiceItemIds, state: .available, into: &rows)
        appendItemRows(ids: membership.createdItemIds, state: .created(invoiceName: nil), into: &rows)
        appendItemRows(ids: membership.invoicedItemIds, state: .sent(invoiceName: nil), into: &rows)
        appendItemRows(ids: membership.paidItemIds, state: .paid(invoiceName: nil), into: &rows)
        return rows
            .map { row in row.withInvoiceName(invoiceName(forSourceType: .item, sourceId: row.id, fallback: row.state)) }
            .filter(matchesFilters)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var visibleTransactionRows: [CandidateSourceRow] {
        guard let membership else { return [] }
        var rows: [CandidateSourceRow] = []
        appendTransactionRows(ids: membership.toInvoiceTransactionIds, state: .available, into: &rows)
        appendTransactionRows(ids: membership.createdTransactionIds, state: .created(invoiceName: nil), into: &rows)
        appendTransactionRows(ids: membership.invoicedTransactionIds, state: .sent(invoiceName: nil), into: &rows)
        appendTransactionRows(ids: membership.paidTransactionIds, state: .paid(invoiceName: nil), into: &rows)
        return rows
            .map { row in row.withInvoiceName(invoiceName(forSourceType: .transaction, sourceId: row.id, fallback: row.state)) }
            .filter(matchesFilters)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var visibleFeeGroups: [FeeGroupDisplay] {
        guard sourceFilter == .all || sourceFilter == .fees else { return [] }
        return feeGroups.compactMap { group in
            let installments = projectContext.feeInstallments
                .filter { $0.budgetCategoryId == group.id }
                .sorted { lhs, rhs in
                    if (lhs.sortOrder ?? 0) != (rhs.sortOrder ?? 0) {
                        return (lhs.sortOrder ?? 0) < (rhs.sortOrder ?? 0)
                    }
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
            let rows = installments.map { installment -> FeeInstallmentDisplayRow in
                let state = membershipState(forSourceType: .feeInstallment, sourceId: installment.id)
                return FeeInstallmentDisplayRow(
                    installment: installment,
                    state: state,
                    invoiceName: state.invoiceName
                )
            }.filter { row in
                matchesAvailability(row.state)
                    && matchesSearch([row.installment.label, group.name, row.invoiceName])
            }
            let invoiced = installments.reduce(0) { partial, installment in
                membershipState(forSourceType: .feeInstallment, sourceId: installment.id).availability == .available
                    ? partial
                    : partial + installment.amountCents
            }
            let received = installments.reduce(0) { partial, installment in
                membershipState(forSourceType: .feeInstallment, sourceId: installment.id).availability == .paid
                    ? partial + installment.amountCents
                    : partial
            }
            let total = group.totalCents ?? max(invoiced, installments.reduce(0) { $0 + $1.amountCents })
            let display = FeeGroupDisplay(
                group: group,
                rows: rows,
                totalCents: total,
                invoicedCents: invoiced,
                receivedCents: received
            )
            let groupMatchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || matchesSearch([group.name])
            guard groupMatchesSearch || !rows.isEmpty else { return nil }
            guard availabilityFilter == .all || !rows.isEmpty || (availabilityFilter == .available && display.toInvoiceCents > 0) else { return nil }
            return display
        }
    }

    private var hasVisibleRows: Bool {
        !visibleFeeGroups.isEmpty || !visibleItemRows.isEmpty || !visibleTransactionRows.isEmpty
    }

    var body: some View {
        CollapsibleSection(
            title: "Receivables",
            isExpanded: $isExpanded,
            badge: summaryLabel,
            onAdd: onCreateInvoice
        ) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                BillingReceivablesToolbar(
                    searchText: $searchText,
                    filtersAreActive: filtersAreActive,
                    onFilter: { showingFilters = true }
                )
                SegmentedControl(
                    selection: $sourceFilter,
                    options: CandidateSourceFilter.allCases.map(\.segmentOption)
                )

                if hasVisibleRows {
                    receivableContent
                } else {
                    BillingEmptyRow("No candidate receivables match the current filters.")
                }
            }
            .padding(.top, Spacing.xs)
        }
        .adaptivePresentation(isPresented: $showingFilters, style: .selectionMenu) {
            ActionMenuSheet(title: "Receivable Filters", items: filterMenuItems, closeOnItemPress: false)
        }
        .sheet(item: $editingFeeCategory) { group in
            FeeInstallmentFormSheet(group: group)
        }
        .navigationDestination(isPresented: $showItemDetail) {
            if let selectedItemId,
               let item = projectContext.items.first(where: { $0.id == selectedItemId }) {
                ItemDetailView(
                    itemId: selectedItemId,
                    projectId: projectId,
                    initialItem: item
                )
            } else {
                ContentUnavailableView("Item Unavailable", systemImage: "cube.box")
            }
        }
        .navigationDestination(isPresented: $showTransactionDetail) {
            if let selectedTransactionId {
                TransactionDetailContainer(
                    transactionId: selectedTransactionId,
                    projectId: initialTransaction?.projectId ?? projectId,
                    initialTransaction: initialTransaction
                )
            } else {
                ContentUnavailableView("Transaction Unavailable", systemImage: "receipt")
            }
        }
    }

    @ViewBuilder
    private var receivableContent: some View {
        if !visibleFeeGroups.isEmpty {
            feeGroupList
        }
        if !visibleItemRows.isEmpty {
            itemRows
        }
        if !visibleTransactionRows.isEmpty {
            transactionRows
        }
    }

    private var feeGroupList: some View {
        VStack(spacing: Spacing.cardListGap) {
            ForEach(visibleFeeGroups) { display in
                FeeGroupCard(
                    display: display,
                    isExpanded: Binding(
                        get: { expandedFeeGroups.contains(display.id) || shouldDefaultExpand(display) },
                        set: { expanded in
                            if expanded { expandedFeeGroups.insert(display.id) }
                            else { expandedFeeGroups.remove(display.id) }
                        }
                    ),
                    onAddInstallment: { editingFeeCategory = display.group }
                )
            }
        }
    }

    @ViewBuilder
    private var itemRows: some View {
        ForEach(visibleItemRows) { row in
            if let item = row.item {
                Button {
                    selectedItemId = item.id
                    showItemDetail = item.id != nil
                } label: {
                    CandidateRow(row: row)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var transactionRows: some View {
        ForEach(visibleTransactionRows) { row in
            if let transaction = row.transaction {
                Button {
                    selectedTransactionId = transaction.id
                    initialTransaction = transaction
                    showTransactionDetail = transaction.id != nil
                } label: {
                    CandidateRow(row: row)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filtersAreActive: Bool {
        availabilityFilter != .available
    }

    private var summaryLabel: String {
        let count = visibleFeeGroups.reduce(0) { $0 + $1.rows.count } + visibleItemRows.count + visibleTransactionRows.count
        return "\(count)"
    }

    private var filterMenuItems: [ActionMenuItem] {
        let availability = CandidateAvailabilityFilter.allCases.map { option in
            ActionMenuItem(
                id: "availability-\(option.rawValue)",
                label: option.label,
                isSelected: availabilityFilter == option,
                onPress: { availabilityFilter = option }
            )
        }
        return availability
    }

    private func shouldDefaultExpand(_ display: FeeGroupDisplay) -> Bool {
        false
    }

    private func appendItemRows(ids: Set<String>, state: CandidateMembershipState, into rows: inout [CandidateSourceRow]) {
        for item in projectContext.items where item.id.map({ ids.contains($0) }) ?? false {
            guard let id = item.id else { continue }
            rows.append(CandidateSourceRow(
                id: id,
                title: item.displayName.isEmpty ? "Untitled item" : item.displayName,
                subtitle: [categoryLookup[item.budgetCategoryId ?? ""]?.name, item.currentSource ?? item.source]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " · "),
                amountCents: InvoiceLineCalculations.amountCents(
                    for: item,
                    projectId: projectId ?? "",
                    transactions: projectContext.transactions
                ) ?? InvoiceLineCalculations.amountCents(for: item),
                state: state,
                kindLabel: "Item",
                item: item,
                transaction: nil
            ))
        }
    }

    private func appendTransactionRows(ids: Set<String>, state: CandidateMembershipState, into rows: inout [CandidateSourceRow]) {
        for tx in projectContext.transactions where tx.id.map({ ids.contains($0) }) ?? false {
            guard let id = tx.id else { continue }
            rows.append(CandidateSourceRow(
                id: id,
                title: TransactionDisplayCalculations.displayName(for: tx),
                subtitle: categoryLookup[tx.budgetCategoryId ?? ""]?.name ?? "Expense",
                amountCents: tx.amountCents ?? 0,
                state: state,
                kindLabel: InvoiceLineCalculations.sign(for: tx) == .credit ? "Credit" : "Expense",
                item: nil,
                transaction: tx
            ))
        }
    }

    private func matchesFilters(_ row: CandidateSourceRow) -> Bool {
        matchesAvailability(row.state) && matchesSearch([row.title, row.subtitle, row.state.invoiceName])
    }

    private func matchesAvailability(_ state: CandidateMembershipState) -> Bool {
        availabilityFilter == .all || state.availability == availabilityFilter
    }

    private func matchesSearch(_ values: [String?]) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return values.contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }

    private func membershipState(forSourceType sourceType: InvoiceLineSourceType, sourceId: String?) -> CandidateMembershipState {
        guard let sourceId else { return .available }
        return invoiceName(forSourceType: sourceType, sourceId: sourceId, fallback: .available)
    }

    private func invoiceName(
        forSourceType sourceType: InvoiceLineSourceType,
        sourceId: String,
        fallback: CandidateMembershipState
    ) -> CandidateMembershipState {
        for invoice in projectInvoices {
            let status = invoice.status ?? .created
            let matches: Bool
            switch sourceType {
            case .item:
                matches = invoice.itemIds?.contains(sourceId) == true
            case .transaction:
                matches = invoice.transactionIds?.contains(sourceId) == true
            case .feeInstallment:
                matches = invoice.lines?.contains { $0.sourceType == .feeInstallment && $0.sourceId == sourceId } == true
            case .manual:
                matches = false
            }
            guard matches else { continue }
            let name = invoice.invoiceNumber
            switch status {
            case .created: return .created(invoiceName: name)
            case .sent: return .sent(invoiceName: name)
            case .paid: return .paid(invoiceName: name)
            case .canceled: continue
            }
        }
        return fallback
    }
}

private struct CandidateSourceRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let amountCents: Int
    let state: CandidateMembershipState
    let kindLabel: String
    let item: Item?
    let transaction: Transaction?

    var rowId: String { "\(kindLabel)-\(id)" }

    func withInvoiceName(_ state: CandidateMembershipState) -> CandidateSourceRow {
        CandidateSourceRow(
            id: id,
            title: title,
            subtitle: subtitle,
            amountCents: amountCents,
            state: state,
            kindLabel: kindLabel,
            item: item,
            transaction: transaction
        )
    }
}

private struct BillingSubsectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(Typography.caption.weight(.semibold))
            .foregroundStyle(BrandColors.textSecondary)
            .textCase(.uppercase)
            .padding(.top, Spacing.sm)
    }
}

private struct CandidateRow: View {
    let row: CandidateSourceRow

    var body: some View {
        BillingCandidateRowPresentation(title: row.title, metadata: metadataLabel,
            amountText: CurrencyFormatting.formatCents(row.amountCents), statusLabel: row.state.label,
            statusColor: row.state.color, invoiceName: row.state.invoiceName)
    }

    private var metadataLabel: String {
        [row.kindLabel, row.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct FeeCategoryContext: Identifiable, Hashable {
    let id: String
    let name: String
    let totalCents: Int?
    let projectBudgetCategory: ProjectBudgetCategory?
}

private struct FeeInstallmentDisplayRow: Identifiable {
    let installment: FeeInstallment
    let state: CandidateMembershipState
    let invoiceName: String?

    var id: String { installment.id ?? "\(installment.budgetCategoryId)-\(installment.label)" }
}

private struct FeeGroupDisplay: Identifiable {
    let group: FeeCategoryContext
    let rows: [FeeInstallmentDisplayRow]
    let totalCents: Int
    let invoicedCents: Int
    let receivedCents: Int

    var id: String { group.id }
    var toInvoiceCents: Int { max(totalCents - invoicedCents, 0) }
}

private struct FeeGroupCard: View {
    let display: FeeGroupDisplay
    @Binding var isExpanded: Bool
    var onAddInstallment: () -> Void

    var body: some View {
        FeeGroupCardPresentation(name: display.group.name, rowCount: display.rows.count,
            remainingText: CurrencyFormatting.formatCents(display.toInvoiceCents),
            totalText: CurrencyFormatting.formatCents(display.totalCents),
            invoicedText: CurrencyFormatting.formatCents(display.invoicedCents),
            receivedText: CurrencyFormatting.formatCents(display.receivedCents),
            invoicedRatio: invoicedRatio, receivedRatio: receivedRatio,
            isExpanded: $isExpanded, onAddInstallment: onAddInstallment) {
            ForEach(display.rows) { row in
                FeeInstallmentRow(row: row)
                if row.id != display.rows.last?.id { CardDivider(horizontalPadding: Spacing.cardPadding) }
            }
        }
    }
    private var invoicedRatio: Double {
        display.totalCents > 0 ? min(Double(display.invoicedCents) / Double(display.totalCents), 1) : 0
    }
    private var receivedRatio: Double {
        display.totalCents > 0 ? min(Double(display.receivedCents) / Double(display.totalCents), invoicedRatio) : 0
    }
}

private struct FeeInstallmentRow: View {
    let row: FeeInstallmentDisplayRow

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.installment.label)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(2)
                HStack(spacing: Spacing.xs) {
                    Badge(text: row.state.label, color: row.state.color)
                    if let invoiceName = row.invoiceName, !invoiceName.isEmpty {
                        Text(invoiceName)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
            }
            Spacer()
            Text(CurrencyFormatting.formatCents(row.installment.amountCents))
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(BrandColors.textPrimary)
                .monospacedDigit()
        }
        .padding(Spacing.cardPadding)
    }
}

private struct FeeInstallmentFormSheet: View {
    let group: FeeCategoryContext

    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var amount = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var parsedAmount: Int? {
        InvoiceMoneyParsing.parseCentsFromDollarString(amount)
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedAmount != nil
            && !isSaving
    }

    var body: some View {
        FeeInstallmentFormPresentation(categoryName: group.name,
            totalText: group.totalCents.map(CurrencyFormatting.formatCents),
            label: $label, amount: $amount, isSaving: isSaving, canSave: canSave,
            errorMessage: errorMessage, onSave: save)
    }

    private func save() {
        guard let accountId = accountContext.currentAccountId,
              let projectId = projectContext.currentProjectId,
              let cents = parsedAmount
        else { return }
        isSaving = true
        errorMessage = nil
        let service = FeeInstallmentsService()
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalCents = group.totalCents
        let existingInvoicedCents = FeeInstallmentCalculations.invoicedCents(
            budgetCategoryId: group.id,
            installments: projectContext.feeInstallments
        )
        let userId = authManager.currentUser?.uid
        Task { @MainActor in
            do {
                _ = try await service.createFeeInstallment(
                    accountId: accountId,
                    projectId: projectId,
                    budgetCategoryId: group.id,
                    label: trimmedLabel,
                    amountCents: cents,
                    sortOrder: nil,
                    totalCents: totalCents,
                    existingInvoicedCents: existingInvoicedCents,
                    userId: userId
                )
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Installment exceeds the fee total or could not be saved."
                }
            }
        }
    }
}

// MARK: - Invoice Row

private extension InvoicePipelineFilter {
    var status: InvoiceStatus? {
        switch self {
        case .all: nil
        case .created: .created
        case .sent: .sent
        case .paid: .paid
        case .canceled: .canceled
        }
    }

}

private struct InvoiceListSection: View {
    let invoices: [Invoice]
    @Binding var isExpanded: Bool
    var onCreateInvoice: () -> Void

    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AuthManager.self) private var authManager

    @State private var selectedStatus: InvoicePipelineFilter = .all
    @State private var workingInvoiceIds: Set<String> = []
    @State private var errorMessage: String?
    @State private var selectedInvoiceId: String?
    @State private var showInvoiceDetail = false

    private var visibleInvoices: [Invoice] {
        guard let status = selectedStatus.status else { return invoices }
        return invoices.filter { ($0.status ?? .created) == status }
    }

    private var emptyMessage: String {
        guard !invoices.isEmpty else {
            return "No invoices yet. Add receivables to create the first invoice."
        }
        return "No \(selectedStatus.label.lowercased()) invoices."
    }

    var body: some View {
        CollapsibleSection(
            title: "Invoices",
            isExpanded: $isExpanded,
            badge: "\(invoices.count)",
            onAdd: onCreateInvoice
        ) {
            VStack(alignment: .leading, spacing: Spacing.cardListGap) {
                SegmentedControl(
                    selection: $selectedStatus,
                    options: InvoicePipelineFilter.allCases.map(\.segmentOption)
                )

                if visibleInvoices.isEmpty {
                    BillingEmptyRow(emptyMessage)
                } else {
                    ForEach(visibleInvoices, id: \.id) { invoice in
                        InvoiceRow(
                            invoice: invoice,
                            items: projectContext.items,
                            transactions: projectContext.transactions,
                            feeInstallments: projectContext.feeInstallments,
                            isWorking: invoice.id.map { workingInvoiceIds.contains($0) } ?? false,
                            onOpen: {
                                selectedInvoiceId = invoice.id
                                showInvoiceDetail = invoice.id != nil
                            },
                            onSelectStatus: { changeStatus(of: invoice, to: $0) }
                        )
                    }
                }
            }
            .padding(.top, Spacing.xs)
        }
        .alert("Invoice update failed", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .navigationDestination(isPresented: $showInvoiceDetail) {
            if let selectedInvoiceId,
               let invoice = invoices.first(where: { $0.id == selectedInvoiceId }) {
                InvoiceDetailView(invoice: invoice)
            } else {
                ContentUnavailableView("Invoice Unavailable", systemImage: "doc.text")
            }
        }
    }

    private func changeStatus(of invoice: Invoice, to targetStatus: InvoiceStatus) {
        guard let invoiceId = invoice.id,
              let accountId = accountContext.currentAccountId
        else { return }

        let status = invoice.status ?? .created
        guard status != targetStatus else { return }
        guard status != .canceled else { return }

        workingInvoiceIds.insert(invoiceId)
        let userId = authManager.currentUser?.uid

        Task {
            do {
                switch targetStatus {
                case .sent where status == .paid:
                    let settlementIds = projectContext.transactions.compactMap { tx -> String? in
                        guard tx.settlementInvoiceId == invoiceId,
                              tx.status != .canceled,
                              let txId = tx.id
                        else { return nil }
                        return txId
                    }
                    try await InvoiceService().voidInvoicePayment(
                        invoice: invoice,
                        accountId: accountId,
                        settlementTransactionIds: settlementIds,
                        userId: userId
                    )

                case .sent:
                    let liveLines = materializedLiveLines(for: invoice)
                    try await InvoiceService().markSent(
                        invoiceId: invoiceId,
                        accountId: accountId,
                        lines: liveLines,
                        totalCents: InvoiceLineCalculations.netTotalCents(lines: liveLines),
                        userId: userId
                    )

                case .paid:
                    let liveLines = materializedLiveLines(for: invoice)
                    var invoiceForCollection = invoice
                    invoiceForCollection.lines = liveLines
                    invoiceForCollection.totalCents = InvoiceLineCalculations.netTotalCents(lines: liveLines)
                    _ = try await InvoiceService().markCollected(
                        invoice: invoiceForCollection,
                        accountId: accountId,
                        projectId: invoice.projectId ?? projectContext.currentProjectId ?? "",
                        amountCents: max(invoiceForCollection.totalCents ?? 0, 0),
                        source: invoice.invoiceNumber?.isEmpty == false ? "Collected \(invoice.invoiceNumber!)" : "Collected invoice",
                        settlementInvoiceLineIds: liveLines.map(\.id),
                        userId: userId
                    )

                case .canceled:
                    try await InvoiceService().cancelInvoice(
                        invoice: invoice,
                        accountId: accountId,
                        userId: userId
                    )

                case .created:
                    break
                }
                await MainActor.run {
                    workingInvoiceIds.remove(invoiceId)
                }
            } catch {
                await MainActor.run {
                    workingInvoiceIds.remove(invoiceId)
                    errorMessage = "Could not update invoice status."
                }
            }
        }
    }

    private func materializedLiveLines(for invoice: Invoice) -> [InvoiceLine] {
        let itemIdSet = Set(invoice.itemIds ?? [])
        let txIdSet = Set(invoice.transactionIds ?? [])
        var lines: [InvoiceLine] = []

        for item in projectContext.items where item.id.map({ itemIdSet.contains($0) }) ?? false {
            if let line = InvoiceLineCalculations.makeLine(
                item: item,
                projectId: invoice.projectId ?? "",
                transactions: projectContext.transactions
            ) {
                lines.append(line)
            }
        }

        for tx in projectContext.transactions where tx.id.map({ txIdSet.contains($0) }) ?? false {
            if let line = InvoiceLineCalculations.makeLine(transaction: tx) {
                lines.append(line)
            }
        }

        for line in invoice.lines ?? [] {
            if line.sourceType == .feeInstallment,
               let sourceId = line.sourceId,
               let installment = projectContext.feeInstallments.first(where: { $0.id == sourceId }) {
                lines.append(InvoiceLine(
                    id: line.id,
                    sourceType: .feeInstallment,
                    sourceId: sourceId,
                    amountCents: installment.amountCents,
                    sign: .charge,
                    budgetCategoryId: installment.budgetCategoryId,
                    snapshotName: installment.label
                ))
            } else if line.sourceType == .manual {
                lines.append(line)
            }
        }

        return lines
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice
    let items: [Item]
    let transactions: [Transaction]
    let feeInstallments: [FeeInstallment]
    let isWorking: Bool
    let onOpen: () -> Void
    let onSelectStatus: (InvoiceStatus) -> Void

    private var status: InvoiceStatus { invoice.status ?? .created }
    private var isPaid: Bool { status == .paid }
    private var isCanceled: Bool { status == .canceled }

    /// Created and sent invoices stay live. Paid invoices use the final
    /// `totalCents` snapshot written at collection.
    private var displayedTotalCents: Int {
        if status != .paid {
            let itemIdSet = Set(invoice.itemIds ?? [])
            let txIdSet = Set(invoice.transactionIds ?? [])
            var lines: [InvoiceLine] = []
            for item in items where item.id.map({ itemIdSet.contains($0) }) ?? false {
                if let line = InvoiceLineCalculations.makeLine(
                    item: item,
                    projectId: invoice.projectId ?? "",
                    transactions: transactions
                ) {
                    lines.append(line)
                }
            }
            for tx in transactions where tx.id.map({ txIdSet.contains($0) }) ?? false {
                if let line = InvoiceLineCalculations.makeLine(transaction: tx) { lines.append(line) }
            }
            for line in invoice.lines ?? [] where line.sourceType == .feeInstallment || line.sourceType == .manual {
                if line.sourceType == .feeInstallment,
                   let sourceId = line.sourceId,
                   let installment = feeInstallments.first(where: { $0.id == sourceId }) {
                    lines.append(InvoiceLine(
                        id: line.id,
                        sourceType: .feeInstallment,
                        sourceId: sourceId,
                        amountCents: installment.amountCents,
                        sign: .charge,
                        budgetCategoryId: installment.budgetCategoryId,
                        snapshotName: installment.label
                    ))
                } else {
                    lines.append(line)
                }
            }
            return InvoiceLineCalculations.netTotalCents(lines: lines)
        }
        return invoice.totalCents ?? 0
    }

    private var statusColor: Color {
        switch status {
        case .created: return BrandColors.textSecondary
        case .sent: return StatusColors.inProgressText
        case .paid: return StatusColors.metText
        case .canceled: return BrandColors.destructive
        }
    }

    private var statusTargets: [InvoiceStatus] {
        switch status {
        case .created: return [.sent, .paid, .canceled]
        case .sent: return [.paid, .canceled]
        case .paid: return [.sent]
        case .canceled: return []
        }
    }

    var body: some View {
        BillingRowSurface(isMuted: isPaid || isCanceled) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Button(action: onOpen) {
                    invoiceSummary
                }
                .buttonStyle(.plain)

                Spacer(minLength: Spacing.sm)

                Menu {
                    ForEach(statusTargets, id: \.self) { targetStatus in
                        Button(role: targetStatus == .canceled ? .destructive : nil) {
                            onSelectStatus(targetStatus)
                        } label: {
                            Label(statusActionLabel(for: targetStatus), systemImage: statusActionIcon(for: targetStatus))
                        }
                        .disabled(targetStatus == .paid && displayedTotalCents <= 0)
                    }
                } label: {
                    statusControl
                }
                .buttonStyle(.plain)
                .disabled(isWorking || statusTargets.isEmpty)
                .accessibilityLabel("Change invoice status")
            }
        }
    }

    private var invoiceSummary: some View {
        BillingInvoiceSummaryPresentation(title: invoice.invoiceNumber ?? "Invoice",
            amountText: CurrencyFormatting.formatCents(displayedTotalCents),
            date: invoice.datePaid ?? invoice.dateSent ?? invoice.dateIssued)
    }

    private var statusControl: some View {
        BillingInvoiceStatusPresentation(label: status.displayLabel, color: statusColor,
            isWorking: isWorking, hasActions: !statusTargets.isEmpty)
    }

    private func statusActionLabel(for targetStatus: InvoiceStatus) -> String {
        switch targetStatus {
        case .created: return "Mark Created"
        case .sent: return status == .paid ? "Correct to Sent" : "Mark Sent"
        case .paid: return "Mark Paid"
        case .canceled: return "Cancel Invoice"
        }
    }

    private func statusActionIcon(for targetStatus: InvoiceStatus) -> String {
        switch targetStatus {
        case .created: return "doc"
        case .sent: return status == .paid ? "arrow.uturn.backward" : "paperplane"
        case .paid: return "checkmark.circle"
        case .canceled: return "trash"
        }
    }
}
