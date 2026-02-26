import SwiftUI

/// Category-level budget row showing name, spent/remaining amounts, and progress bar with overflow.
/// Used in BudgetProgressDisplay and Budget tab.
struct BudgetCategoryTracker: View {
    let name: String
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

    private var fillColor: Color {
        if overBudget { return StatusColors.overflowBar }
        if percentage >= 100 { return StatusColors.inProgressBar }
        return BrandColors.primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(name)
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()

                Text(BudgetTrackerCalculations.spentLabel(spentCents: spentCents, categoryType: categoryType))
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            ProgressBar(
                percentage: percentage,
                fillColor: fillColor,
                overflowPercentage: overflow > 0 ? overflow : nil,
                overflowColor: overflow > 0 ? StatusColors.overflowBar : nil
            )

            Text(BudgetTrackerCalculations.remainingLabel(
                spentCents: spentCents, budgetCents: budgetCents, categoryType: categoryType
            ))
            .font(Typography.caption)
            .foregroundStyle(BrandColors.textSecondary)
        }
    }
}

#Preview("Under Budget (50%)") {
    BudgetCategoryTracker(name: "Materials", spentCents: 25000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
}

#Preview("At Budget (100%)") {
    BudgetCategoryTracker(name: "Lumber", spentCents: 50000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
}

#Preview("Over Budget (150%)") {
    BudgetCategoryTracker(name: "Appliances", spentCents: 75000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
}

#Preview("Fee Category") {
    BudgetCategoryTracker(name: "Architect Fee", spentCents: 30000, budgetCents: 50000, categoryType: .fee)
        .padding(Spacing.screenPadding)
}

#Preview("Zero Budget") {
    BudgetCategoryTracker(name: "Miscellaneous", spentCents: 0, budgetCents: 0)
        .padding(Spacing.screenPadding)
}
