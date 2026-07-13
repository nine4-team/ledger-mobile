import SwiftUI

/// Project billing summary — Total Spent / Invoiced / Collected / Outstanding.
/// Reads project items + transactions from `ProjectContext`.
struct BillingSummaryCard: View {
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @State private var selectedDefinition: BillingSummaryDefinition?

    private var summary: BillingSummaryCalculations.Summary {
        BillingSummaryCalculations.summarize(
            projectId: projectContext.currentProjectId,
            items: projectContext.items,
            transactions: projectContext.transactions,
            invoices: accountContext.allInvoices,
            feeInstallments: projectContext.feeInstallments,
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

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Billing")
                    .sectionLabelStyle()

                row(.totalSpent, cents: summary.totalSpentCents, color: BrandColors.textPrimary)
                row(.invoiced, cents: summary.invoicedCents, color: BrandColors.primary)
                row(.collected, cents: summary.collectedCents, color: StatusColors.metText)
                Divider()
                row(.outstanding, cents: summary.outstandingCents, color: BrandColors.textPrimary, emphasized: true)
            }
        }
        .alert(
            selectedDefinition?.title ?? "",
            isPresented: Binding(
                get: { selectedDefinition != nil },
                set: { if !$0 { selectedDefinition = nil } }
            )
        ) {
            Button("OK", role: .cancel) { selectedDefinition = nil }
        } message: {
            Text(selectedDefinition?.message ?? "")
        }
    }

    private func row(_ definition: BillingSummaryDefinition, cents: Int, color: Color, emphasized: Bool = false) -> some View {
        HStack {
            HStack(spacing: Spacing.xs) {
                Text(definition.title)
                    .font(emphasized ? Typography.body.weight(.semibold) : Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                Button {
                    selectedDefinition = definition
                } label: {
                    Image(systemName: "info.circle")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(definition.title) info")
                .accessibilityHint(definition.message)
            }
            Spacer()
            Text(CurrencyFormatting.formatCents(cents))
                .font(emphasized ? Typography.body.weight(.semibold) : Typography.body)
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

private enum BillingSummaryDefinition: Identifiable {
    case totalSpent
    case invoiced
    case collected
    case outstanding

    var id: String { title }

    var title: String {
        switch self {
        case .totalSpent: "Total Spent"
        case .invoiced: "Invoiced"
        case .collected: "Collected"
        case .outstanding: "Outstanding"
        }
    }

    var message: String {
        switch self {
        case .totalSpent:
            "Project activity and cost basis: item purchase prices plus non-itemized project transactions. This is not the amount currently owed."
        case .invoiced:
            "Invoices that have been sent to the client or already collected. Created invoices do not count here."
        case .collected:
            "Money received from the client, tracked by transactions linked to invoices as settlement."
        case .outstanding:
            "Invoices sent to the client that have not been collected yet. This is sent invoice totals minus linked payment transactions."
        }
    }
}
