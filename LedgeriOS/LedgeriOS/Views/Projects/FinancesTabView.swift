import SwiftUI

struct FinancesTabView: View {
    @State private var selectedSubtab = "budget"

    var body: some View {
        VStack(spacing: 0) {
            SegmentedControl(selection: $selectedSubtab, options: [
                SegmentOption(id: "budget", label: "Budget"),
                SegmentOption(id: "billing", label: "Billing"),
                SegmentOption(id: "reports", label: "Reports"),
            ])
            .frame(maxWidth: Dimensions.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)

            switch selectedSubtab {
            case "reports":
                AccountingTabView()
            case "billing":
                BillingSubTab()
            default:
                BudgetTabView()
            }
        }
    }
}

// MARK: - Billing Sub-Tab

private struct BillingSubTab: View {
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
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
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
            .padding(Spacing.screenPadding)
            .frame(maxWidth: Dimensions.contentMaxWidth)
            .frame(maxWidth: .infinity)
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

private enum CandidateAvailabilityFilter: String, CaseIterable {
    case available, created, sent, paid, all

    var label: String {
        switch self {
        case .available: "Available"
        case .created: "On Created Invoice"
        case .sent: "Sent"
        case .paid: "Paid"
        case .all: "All"
        }
    }
}

private enum CandidateSourceFilter: String, CaseIterable {
    case all, fees, expenses, items

    var label: String {
        switch self {
        case .all: "All Sources"
        case .fees: "Fees"
        case .expenses: "Expenses"
        case .items: "Items"
        }
    }
}

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
    }

    @ViewBuilder
    private var receivableContent: some View {
        if !visibleFeeGroups.isEmpty {
            BillingSubsectionLabel("Fees")
            feeGroupList
        }
        if !visibleItemRows.isEmpty {
            BillingSubsectionLabel("Items")
            itemRows
        }
        if !visibleTransactionRows.isEmpty {
            BillingSubsectionLabel("Expenses")
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
                NavigationLink(value: item) {
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
                NavigationLink(value: transaction) {
                    CandidateRow(row: row)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filtersAreActive: Bool {
        availabilityFilter != .available || sourceFilter != .all
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
        let sources = CandidateSourceFilter.allCases.map { option in
            ActionMenuItem(
                id: "source-\(option.rawValue)",
                label: option.label,
                isSelected: sourceFilter == option,
                onPress: { sourceFilter = option }
            )
        }
        return availability + sources
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

private struct BillingReceivablesToolbar: View {
    @Binding var searchText: String
    let filtersAreActive: Bool
    var onFilter: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            SearchField(text: $searchText, placeholder: "Search receivables...")

            Button(action: onFilter) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(filtersAreActive ? BrandColors.primary : BrandColors.textSecondary)
            }
            .buttonStyle(CircleBarButtonStyle())
            .background(BrandColors.surface, in: Circle())
            .overlay(Circle().stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth))
            .accessibilityLabel("Filter receivables")
        }
    }
}

private struct BillingEmptyRow: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(Typography.small)
            .foregroundStyle(BrandColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.md)
    }
}

private struct BillingRowSurface<Content: View>: View {
    var padding: CGFloat = Spacing.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(BrandColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
            )
            .shadow(color: .black.opacity(0.035), radius: 4, x: 0, y: 1)
    }
}

private struct CandidateRow: View {
    let row: CandidateSourceRow

    var body: some View {
        BillingRowSurface {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.title)
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: Spacing.xs) {
                        Text(metadataLabel)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .lineLimit(1)
                        Badge(text: row.state.label, color: row.state.color)
                        if let invoiceName = row.state.invoiceName, !invoiceName.isEmpty {
                            Text(invoiceName)
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: Spacing.md)
                Text(CurrencyFormatting.formatCents(row.amountCents))
                    .font(Typography.small.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .monospacedDigit()
            }
        }
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
        BillingRowSurface(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.sm) {
                            Text(display.group.name)
                                .font(Typography.body.weight(.semibold))
                                .foregroundStyle(BrandColors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(CurrencyFormatting.formatCents(display.toInvoiceCents))
                                .font(Typography.small.weight(.semibold))
                                .foregroundStyle(BrandColors.textPrimary)
                                .monospacedDigit()
                            if !display.rows.isEmpty {
                                Badge(text: "\(display.rows.count)", color: BrandColors.primary)
                            }
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                        feeSummaryLine
                        DualToneFeeProgressBar(
                            totalCents: display.totalCents,
                            invoicedCents: display.invoicedCents,
                            receivedCents: display.receivedCents
                        )
                    }
                    .padding(Spacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    CardDivider()
                    VStack(spacing: 0) {
                        ForEach(display.rows) { row in
                            FeeInstallmentRow(row: row)
                            if row.id != display.rows.last?.id { CardDivider(horizontalPadding: Spacing.cardPadding) }
                        }
                        Button(action: onAddInstallment) {
                            Label("Add Installment", systemImage: "plus.circle.fill")
                                .font(Typography.body.weight(.semibold))
                                .foregroundStyle(BrandColors.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Spacing.md)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var feeSummaryLine: some View {
        HStack(spacing: Spacing.sm) {
            Text("Total \(CurrencyFormatting.formatCents(display.totalCents))")
            Text("Invoiced \(CurrencyFormatting.formatCents(display.invoicedCents))")
            Text("Received \(CurrencyFormatting.formatCents(display.receivedCents))")
        }
        .font(Typography.caption)
        .foregroundStyle(BrandColors.textSecondary)
        .lineLimit(1)
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

private struct DualToneFeeProgressBar: View {
    let totalCents: Int
    let invoicedCents: Int
    let receivedCents: Int

    private var invoicedRatio: Double {
        guard totalCents > 0 else { return 0 }
        return min(Double(invoicedCents) / Double(totalCents), 1)
    }

    private var receivedRatio: Double {
        guard totalCents > 0 else { return 0 }
        return min(Double(receivedCents) / Double(totalCents), invoicedRatio)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(BrandColors.progressTrack)
                Capsule()
                    .fill(BrandColors.primary.opacity(0.35))
                    .frame(width: geometry.size.width * invoicedRatio)
                Capsule()
                    .fill(BrandColors.primary)
                    .frame(width: geometry.size.width * receivedRatio)
            }
        }
        .frame(height: 7)
        .clipShape(Capsule())
        .accessibilityLabel("Fee invoicing progress")
        .accessibilityValue("\(CurrencyFormatting.formatCents(invoicedCents)) invoiced, \(CurrencyFormatting.formatCents(receivedCents)) received")
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
        FormSheet(
            title: "Add \(group.name) Installment",
            description: "Create one billable portion of this fee.",
            primaryAction: FormSheetAction(
                title: "Add Installment",
                isLoading: isSaving,
                isDisabled: !canSave,
                action: { save() }
            ),
            secondaryAction: FormSheetAction(title: "Cancel") { dismiss() },
            error: errorMessage
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                FormField(label: "Label", text: $label, placeholder: "Design fee 1 of 3")
                FormField(label: "Amount", text: $amount, placeholder: "$2,500")
                if let total = group.totalCents {
                    Text("Total fee: \(CurrencyFormatting.formatCents(total))")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
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

private struct InvoiceListSection: View {
    let invoices: [Invoice]
    @Binding var isExpanded: Bool
    var onCreateInvoice: () -> Void

    @Environment(ProjectContext.self) private var projectContext

    var body: some View {
        CollapsibleSection(
            title: "Invoices",
            isExpanded: $isExpanded,
            badge: "\(invoices.count)",
            onAdd: onCreateInvoice
        ) {
            VStack(alignment: .leading, spacing: Spacing.cardListGap) {
                if invoices.isEmpty {
                    BillingEmptyRow("No invoices yet. Add receivables to create the first invoice.")
                } else {
                    ForEach(invoices, id: \.id) { invoice in
                        NavigationLink(value: invoice) {
                            InvoiceRow(
                                invoice: invoice,
                                items: projectContext.items,
                                transactions: projectContext.transactions,
                                feeInstallments: projectContext.feeInstallments
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, Spacing.xs)
        }
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice
    let items: [Item]
    let transactions: [Transaction]
    let feeInstallments: [FeeInstallment]

    private var status: InvoiceStatus { invoice.status ?? .created }

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

    var body: some View {
        BillingRowSurface {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: Spacing.sm) {
                        Text(invoice.invoiceNumber ?? "Invoice")
                            .font(Typography.body.weight(.semibold))
                            .foregroundStyle(BrandColors.textPrimary)
                            .lineLimit(1)
                        Text(status.displayLabel)
                            .font(Typography.caption.weight(.semibold))
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(statusColor.opacity(0.30), lineWidth: 1))
                            .foregroundStyle(statusColor)
                    }
                    if let date = invoice.dateIssued {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
                Spacer()
                Text(CurrencyFormatting.formatCents(displayedTotalCents))
                    .font(Typography.small.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .monospacedDigit()
            }
        }
    }
}
