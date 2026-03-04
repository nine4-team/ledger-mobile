import SwiftUI

/// Compact budget preview for ProjectCard — shows category name, spent/remaining labels, and thin progress bar.
/// Matches the React Native BudgetProgressPreview layout.
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

    private var remainingLabel: String {
        BudgetTrackerCalculations.remainingLabel(spentCents: spentCents, budgetCents: budgetCents, categoryType: categoryType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(categoryName)
                .font(Typography.small)
                .fontWeight(.medium)
                .foregroundStyle(BrandColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack {
                Text(BudgetTrackerCalculations.spentLabel(spentCents: spentCents, categoryType: categoryType))
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                Spacer()
                Text(remainingLabel)
                    .font(Typography.caption)
                    .fontWeight(overBudget ? .bold : .regular)
                    .foregroundStyle(overBudget ? StatusColors.overflowBar : BrandColors.textSecondary)
            }

            ProgressBar(
                percentage: percentage,
                fillColor: BrandColors.primary,
                height: 4,
                overflowPercentage: overflow > 0 ? overflow : nil,
                overflowColor: overflow > 0 ? StatusColors.overflowBar : nil
            )
        }
    }
}

#Preview("Normal (50%)") {
    BudgetProgressPreview(categoryName: "Furnishings", spentCents: 10_093_600, budgetCents: 10_320_000)
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}

#Preview("Over Budget") {
    BudgetProgressPreview(categoryName: "Appliances", spentCents: 75000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}

#Preview("Fee Category") {
    BudgetProgressPreview(categoryName: "Architect Fee", spentCents: 30000, budgetCents: 50000, categoryType: .fee)
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}
