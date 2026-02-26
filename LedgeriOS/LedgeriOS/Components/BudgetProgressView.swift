import SwiftUI

struct BudgetProgressView: View {
    let spentCents: Int
    let budgetCents: Int
    var compact: Bool = false

    var body: some View {
        let overBudget = BudgetDisplayCalculations.isOverBudget(spent: spentCents, budget: budgetCents)
        let ratio = BudgetDisplayCalculations.budgetRatio(spent: spentCents, budget: budgetCents)
        let overflow = ProgressBarCalculations.overflowPercentage(spent: spentCents, budget: budgetCents)

        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(BudgetDisplayCalculations.budgetProgressLabel(spent: spentCents, budget: budgetCents, compact: compact))
                    .font(Typography.small)
                    .foregroundColor(BrandColors.textSecondary)

                Spacer()

                Text(BudgetDisplayCalculations.budgetPercentageLabel(spent: spentCents, budget: budgetCents))
                    .font(Typography.caption)
                    .foregroundColor(overBudget ? StatusColors.overflowBar : BrandColors.textSecondary)
            }

            ProgressBar(
                percentage: ratio * 100,
                fillColor: overBudget ? StatusColors.overflowBar : BrandColors.primary,
                overflowPercentage: overflow > 0 ? overflow : nil,
                overflowColor: overflow > 0 ? StatusColors.overflowBar : nil
            )
        }
    }
}

#Preview("Under Budget") {
    BudgetProgressView(spentCents: 4500, budgetCents: 10000)
        .padding()
}

#Preview("At Budget") {
    BudgetProgressView(spentCents: 10000, budgetCents: 10000)
        .padding()
}

#Preview("Over Budget") {
    BudgetProgressView(spentCents: 13500, budgetCents: 10000)
        .padding()
}

#Preview("Compact") {
    BudgetProgressView(spentCents: 6000, budgetCents: 10000, compact: true)
        .padding()
}

#Preview("Zero Budget") {
    BudgetProgressView(spentCents: 0, budgetCents: 0)
        .padding()
}
