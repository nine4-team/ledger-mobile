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

    private var projectInvoices: [Invoice] {
        guard let projectId = projectContext.currentProjectId else { return [] }
        return accountContext.allInvoices
            .filter { $0.projectId == projectId }
            .sorted { ($0.dateIssued ?? .distantPast) > ($1.dateIssued ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                BillingSummaryCard()

                CandidateReceivablesSection(
                    onCreateInvoice: { showingCreateInvoice = true }
                )

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("Invoices").sectionLabelStyle()
                        Spacer()
                        Button {
                            showingCreateInvoice = true
                        } label: {
                            Label("Create Invoice", systemImage: "plus.circle.fill")
                                .font(Typography.body.weight(.semibold))
                                .foregroundStyle(BrandColors.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    if projectInvoices.isEmpty {
                        Card {
                            Text("No invoices yet. Tap Create Invoice to bill the client for approved items.")
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ForEach(projectInvoices, id: \.id) { invoice in
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Candidate Receivables").sectionLabelStyle()
                Spacer()
                Button(action: onCreateInvoice) {
                    Label("Create Invoice", systemImage: "plus.circle.fill")
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(BrandColors.primary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: Spacing.sm) {
                SearchField(text: $searchText, placeholder: "Search receivables...")
                Button { showingFilters = true } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(Typography.h3)
                        .foregroundStyle(filtersAreActive ? BrandColors.primary : BrandColors.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(BrandColors.surface, in: Circle())
                        .overlay(Circle().stroke(BrandColors.border, lineWidth: Dimensions.borderWidth))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter receivables")
            }

            Text(summaryLabel)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)

            if hasVisibleRows {
                feeGroupList
                sourceRows
            } else {
                Card {
                    Text("No candidate receivables match the current filters.")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
        }
        .adaptivePresentation(isPresented: $showingFilters, style: .selectionMenu) {
            ActionMenuSheet(title: "Receivable Filters", items: filterMenuItems, closeOnItemPress: false)
        }
        .sheet(item: $editingFeeCategory) { group in
            FeeInstallmentFormSheet(group: group)
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
    private var sourceRows: some View {
        if sourceFilter == .all || sourceFilter == .items {
            ForEach(visibleItemRows) { row in
                if let item = row.item {
                    NavigationLink(value: item) {
                        CandidateRow(row: row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if sourceFilter == .all || sourceFilter == .expenses {
            ForEach(visibleTransactionRows) { row in
                if let transaction = row.transaction {
                    NavigationLink(value: transaction) {
                        CandidateRow(row: row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var filtersAreActive: Bool {
        availabilityFilter != .available || sourceFilter != .all
    }

    private var summaryLabel: String {
        let count = visibleFeeGroups.reduce(0) { $0 + $1.rows.count } + visibleItemRows.count + visibleTransactionRows.count
        return "\(availabilityFilter.label) · \(sourceFilter.label) · \(count) row\(count == 1 ? "" : "s")"
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
        sourceFilter == .fees || display.toInvoiceCents > 0 || display.rows.contains { $0.state == .available }
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

private struct CandidateRow: View {
    let row: CandidateSourceRow

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.sm) {
                        Text(row.title)
                            .font(Typography.body.weight(.semibold))
                            .foregroundStyle(BrandColors.textPrimary)
                            .lineLimit(2)
                        Badge(text: row.kindLabel, color: BrandColors.textSecondary)
                    }
                    if !row.subtitle.isEmpty {
                        Text(row.subtitle)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: Spacing.xs) {
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
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .monospacedDigit()
            }
        }
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
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.sm) {
                            Text(display.group.name)
                                .font(Typography.body.weight(.semibold))
                                .foregroundStyle(BrandColors.textPrimary)
                                .lineLimit(2)
                            Spacer()
                            Badge(text: "\(display.rows.count)", color: BrandColors.primary)
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                        metricGrid
                        DualToneFeeProgressBar(
                            totalCents: display.totalCents,
                            invoicedCents: display.invoicedCents,
                            receivedCents: display.receivedCents
                        )
                    }
                    .padding(Spacing.cardPadding)
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
                                .padding(Spacing.cardPadding)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var metricGrid: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                metric("Total", display.totalCents)
                Spacer()
                metric("Invoiced", display.invoicedCents)
            }
            HStack {
                metric("Received", display.receivedCents)
                Spacer()
                metric("To Invoice", display.toInvoiceCents)
            }
        }
    }

    private func metric(_ label: String, _ cents: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
            Text(CurrencyFormatting.formatCents(cents))
                .font(Typography.small.weight(.semibold))
                .foregroundStyle(BrandColors.textPrimary)
                .monospacedDigit()
        }
        .frame(minWidth: 110, alignment: .leading)
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

// MARK: - Billing Pipeline Section

/// Three-segment view of the project's billable pipeline:
/// - Available: items and non-itemized transactions not on any non-canceled invoice.
/// - Invoiced: everything on sent-but-unpaid invoices.
/// - Paid: everything on paid invoices.
/// Membership is derived via `InvoiceLineCalculations.billableMembership`.
private struct BillingPipelineSection: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @State private var selectedSegment = "to-invoice"
    @State private var selectedRecordType = "all"
    @State private var showingPipelineInfo = false

    private var projectId: String? { projectContext.currentProjectId }

    private var membership: InvoiceLineCalculations.BillableMembership? {
        guard let pid = projectId else { return nil }
        return InvoiceLineCalculations.billableMembership(
            projectId: pid,
            items: projectContext.items,
            transactions: projectContext.transactions,
            invoices: accountContext.allInvoices,
            budgetCategories: categoryLookup
        )
    }

    private var categoryLookup: [String: BudgetCategory] {
        Dictionary(
            uniqueKeysWithValues: projectContext.budgetCategories.compactMap { category in
                guard let id = category.id else { return nil }
                return (id, category)
            }
        )
    }

    private func items(in ids: Set<String>) -> [Item] {
        projectContext.items
            .filter { $0.id.map { ids.contains($0) } ?? false }
    }

    private func transactions(in ids: Set<String>) -> [Transaction] {
        projectContext.transactions
            .filter { $0.id.map { ids.contains($0) } ?? false }
    }

    private var visibleItems: [Item] {
        guard let m = membership else { return [] }
        switch selectedSegment {
        case "invoiced": return items(in: m.invoicedItemIds)
        case "paid": return items(in: m.paidItemIds)
        default: return items(in: m.toInvoiceItemIds)
        }
    }

    private var visibleTransactions: [Transaction] {
        guard let m = membership else { return [] }
        switch selectedSegment {
        case "invoiced": return transactions(in: m.invoicedTransactionIds)
        case "paid": return transactions(in: m.paidTransactionIds)
        default: return transactions(in: m.toInvoiceTransactionIds)
        }
    }

    private var isEmpty: Bool {
        switch selectedRecordType {
        case "items":
            return visibleItems.isEmpty
        case "transactions":
            return visibleTransactions.isEmpty
        default:
            return visibleItems.isEmpty && visibleTransactions.isEmpty
        }
    }

    private var emptyMessage: String {
        if selectedRecordType == "items" {
            return "No \(selectedSegmentName.lowercased()) items."
        }
        if selectedRecordType == "transactions" {
            return "No \(selectedSegmentName.lowercased()) transactions."
        }
        switch selectedSegment {
        case "invoiced":
            return "Nothing is on a sent invoice yet."
        case "paid":
            return "Nothing is on a paid invoice yet."
        default:
            return "Everything in this project is already on an invoice."
        }
    }

    private var selectedSegmentName: String {
        switch selectedSegment {
        case "invoiced": return "Invoiced"
        case "paid": return "Paid"
        default: return "Available"
        }
    }

    private var recordCountsLabel: String {
        "\(visibleItems.count) item\(visibleItems.count == 1 ? "" : "s") · \(visibleTransactions.count) transaction\(visibleTransactions.count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("Pipeline").sectionLabelStyle()
                Button {
                    showingPipelineInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pipeline info")
                .accessibilityHint(pipelineInfoMessage)
            }

            SegmentedControl(selection: $selectedSegment, options: [
                SegmentOption(id: "to-invoice", label: "Available"),
                SegmentOption(id: "invoiced", label: "Invoiced"),
                SegmentOption(id: "paid", label: "Paid"),
            ])

            SegmentedControl(selection: $selectedRecordType, options: [
                SegmentOption(id: "all", label: "All"),
                SegmentOption(id: "items", label: "Items"),
                SegmentOption(id: "transactions", label: "Transactions"),
            ])

            Text(recordCountsLabel)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isEmpty {
                Card {
                    Text(emptyMessage)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if selectedRecordType != "transactions", !visibleItems.isEmpty {
                    if selectedRecordType == "all" {
                        Text("Items").sectionLabelStyle()
                    }
                    ForEach(visibleItems, id: \.id) { item in
                        NavigationLink(value: item) {
                            ItemCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if selectedRecordType != "items", !visibleTransactions.isEmpty {
                    if selectedRecordType == "all" {
                        Text("Transactions").sectionLabelStyle()
                    }
                    ForEach(visibleTransactions, id: \.id) { tx in
                        NavigationLink(value: tx) {
                            TransactionCard(transaction: tx)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .alert("Billing Pipeline", isPresented: $showingPipelineInfo) {
            Button("OK", role: .cancel) { showingPipelineInfo = false }
        } message: {
            Text(pipelineInfoMessage)
        }
    }

    private var pipelineInfoMessage: String {
        """
        The pipeline shows where existing project items and billable transactions are in the invoicing process.

        Available: eligible records that can be added to an invoice.

        Invoiced: records on invoices sent to the client but not collected yet.

        Paid: records on invoices marked collected.
        """
    }
}

// MARK: - Invoice Row

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
        Card {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.sm) {
                        Text(invoice.invoiceNumber ?? "Invoice")
                            .font(Typography.body.weight(.semibold))
                            .foregroundStyle(BrandColors.textPrimary)
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
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .monospacedDigit()
            }
        }
    }
}
