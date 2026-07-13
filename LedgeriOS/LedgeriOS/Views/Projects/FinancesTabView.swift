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
                                    transactions: projectContext.transactions
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                BillingPipelineSection()
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

// MARK: - Billing Pipeline Section

/// Three-segment view of the project's billable pipeline:
/// - Available: items and non-itemized transactions not on any non-voided invoice.
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

    private var status: InvoiceStatus { invoice.status ?? .draft }

    /// Drafts are live previews — compute the displayed total from the current
    /// item / transaction state. Sent / paid / voided invoices use the frozen
    /// `totalCents` snapshot written at `markSent`.
    private var displayedTotalCents: Int {
        if status == .draft {
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
            for line in invoice.lines ?? [] where line.sourceType == .manual {
                lines.append(line)
            }
            return InvoiceLineCalculations.netTotalCents(lines: lines)
        }
        return invoice.totalCents ?? 0
    }

    private var statusColor: Color {
        switch status {
        case .draft: return BrandColors.textSecondary
        case .sent: return StatusColors.inProgressText
        case .paid: return StatusColors.metText
        case .voided: return BrandColors.destructive
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
