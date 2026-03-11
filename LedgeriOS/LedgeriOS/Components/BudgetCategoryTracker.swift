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
        BudgetTrackerCalculations.progressColor(percentage: percentage, categoryType: categoryType)
    }

    private var remainingColor: Color {
        BudgetTrackerCalculations.remainingTextColor(percentage: percentage, categoryType: categoryType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(name)
                .font(Typography.h3)
                .foregroundStyle(BrandColors.textPrimary)

            HStack {
                Text(BudgetTrackerCalculations.spentLabel(spentCents: spentCents, categoryType: categoryType))
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)

                Spacer()

                Text(BudgetTrackerCalculations.remainingLabel(
                    spentCents: spentCents, budgetCents: budgetCents, categoryType: categoryType
                ))
                .font(Typography.small)
                .fontWeight(.regular)
                .foregroundStyle(remainingColor)
            }

            ProgressBar(
                percentage: percentage,
                fillColor: fillColor,
                overflowPercentage: overflow > 0 ? overflow : nil,
                overflowColor: overflow > 0 ? StatusColors.overflowBar : nil
            )
        }
    }
}

#Preview("Green (< 50%)") {
    BudgetCategoryTracker(name: "Materials", spentCents: 20000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
}

#Preview("Yellow (50–74%)") {
    BudgetCategoryTracker(name: "Lumber", spentCents: 30000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
}

#Preview("Red (≥ 75%)") {
    BudgetCategoryTracker(name: "Appliances", spentCents: 40000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
}

#Preview("Over Budget (150%)") {
    BudgetCategoryTracker(name: "Appliances", spentCents: 75000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
}

#Preview("Fee — Green (≥ 75%)") {
    BudgetCategoryTracker(name: "Architect Fee", spentCents: 40000, budgetCents: 50000, categoryType: .fee)
        .padding(Spacing.screenPadding)
}

#Preview("Fee — Yellow (50–74%)") {
    BudgetCategoryTracker(name: "Architect Fee", spentCents: 30000, budgetCents: 50000, categoryType: .fee)
        .padding(Spacing.screenPadding)
}

#Preview("Fee — Red (< 50%)") {
    BudgetCategoryTracker(name: "Architect Fee", spentCents: 20000, budgetCents: 50000, categoryType: .fee)
        .padding(Spacing.screenPadding)
}

#Preview("Zero Budget") {
    BudgetCategoryTracker(name: "Miscellaneous", spentCents: 0, budgetCents: 0)
        .padding(Spacing.screenPadding)
}
