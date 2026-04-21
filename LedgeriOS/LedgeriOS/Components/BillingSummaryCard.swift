import SwiftUI

/// Project billing summary — Total Spent / Invoiced / Collected / Outstanding.
/// Reads project items + transactions from `ProjectContext`.
struct BillingSummaryCard: View {
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext

    private var summary: BillingSummaryCalculations.Summary {
        BillingSummaryCalculations.summarize(
            projectId: projectContext.currentProjectId,
            items: projectContext.items,
            transactions: projectContext.transactions,
            invoices: accountContext.allInvoices
        )
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Billing")
                    .sectionLabelStyle()

                row("Total Spent", cents: summary.totalSpentCents, color: BrandColors.textPrimary)
                row("Invoiced", cents: summary.invoicedCents, color: StatusColors.inProgressText)
                row("Collected", cents: summary.collectedCents, color: StatusColors.metText)
                Divider()
                row("Outstanding", cents: summary.outstandingCents, color: BrandColors.textPrimary, emphasized: true)
            }
        }
    }

    private func row(_ label: String, cents: Int, color: Color, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? Typography.body.weight(.semibold) : Typography.body)
                .foregroundStyle(BrandColors.textSecondary)
            Spacer()
            Text(CurrencyFormatting.formatCents(cents))
                .font(emphasized ? Typography.body.weight(.semibold) : Typography.body)
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}
