import SwiftUI

/// Compact budget preview for ProjectCard — shows category name, spent label, and thin progress bar.
struct BudgetProgressPreview: View {
    let categoryName: String
    let spentCents: Int
    let budgetCents: Int
    var categoryType: BudgetCategoryType = .general

    private var overBudget: Bool {
        BudgetTrackerCalculations.isOverBudget(spentCents: spentCents, budgetCents: budgetCents)
    }

    private var percentage: Double {
        BudgetTrackerCalculations.progressPercentage(spentCents: spentCents, budgetCents: budgetCents)
    }

    private var overflow: Double {
        BudgetTrackerCalculations.overflowPercentage(spentCents: spentCents, budgetCents: budgetCents)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(categoryName)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(BudgetTrackerCalculations.spentLabel(spentCents: spentCents, categoryType: categoryType))
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            ProgressBar(
                percentage: percentage,
                fillColor: overBudget ? StatusColors.overflowBar : BrandColors.primary,
                height: 4,
                overflowPercentage: overflow > 0 ? overflow : nil,
                overflowColor: overflow > 0 ? StatusColors.overflowBar : nil
            )
        }
    }
}

#Preview("Normal (50%)") {
    BudgetProgressPreview(categoryName: "Materials", spentCents: 25000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
}

#Preview("Over Budget") {
    BudgetProgressPreview(categoryName: "Appliances", spentCents: 75000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
}

#Preview("Fee Category") {
    BudgetProgressPreview(categoryName: "Architect Fee", spentCents: 30000, budgetCents: 50000, categoryType: .fee)
        .padding(Spacing.screenPadding)
}
