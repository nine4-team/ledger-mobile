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
                                InvoiceRow(invoice: invoice)
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
/// - To Invoice: items and non-itemized transactions not on any non-voided invoice.
/// - Invoiced: everything on sent-but-unpaid invoices.
/// - Paid: everything on paid invoices.
/// Membership is derived via `InvoiceLineCalculations.billableMembership`.
private struct BillingPipelineSection: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @State private var selectedSegment = "to-invoice"

    private var projectId: String? { projectContext.currentProjectId }

    private var membership: InvoiceLineCalculations.BillableMembership? {
        guard let pid = projectId else { return nil }
        return InvoiceLineCalculations.billableMembership(
            projectId: pid,
            items: projectContext.items,
            transactions: projectContext.transactions,
            invoices: accountContext.allInvoices
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
        visibleItems.isEmpty && visibleTransactions.isEmpty
    }

    private var emptyMessage: String {
        switch selectedSegment {
        case "invoiced":
            return "Nothing is on a sent invoice yet."
        case "paid":
            return "Nothing is on a paid invoice yet."
        default:
            return "Everything in this project is already on an invoice."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Pipeline").sectionLabelStyle()

            SegmentedControl(selection: $selectedSegment, options: [
                SegmentOption(id: "to-invoice", label: "To Invoice"),
                SegmentOption(id: "invoiced", label: "Invoiced"),
                SegmentOption(id: "paid", label: "Paid"),
            ])

            if isEmpty {
                Card {
                    Text(emptyMessage)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if !visibleItems.isEmpty {
                    Text("Items").sectionLabelStyle()
                    ForEach(visibleItems, id: \.id) { item in
                        NavigationLink(value: item) {
                            ItemCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !visibleTransactions.isEmpty {
                    Text("Transactions").sectionLabelStyle()
                    ForEach(visibleTransactions, id: \.id) { tx in
                        NavigationLink(value: tx) {
                            TransactionCard(transaction: tx)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Invoice Row

private struct InvoiceRow: View {
    let invoice: Invoice

    private var status: InvoiceStatus { invoice.status ?? .draft }

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
                Text(CurrencyFormatting.formatCents(invoice.totalCents ?? 0))
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(BrandColors.textPrimary)
                    .monospacedDigit()
            }
        }
    }
}
