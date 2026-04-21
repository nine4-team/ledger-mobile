import SwiftUI

/// Compact budget preview for ProjectCard — shows category name, spent/remaining labels, and thin progress bar.
/// Matches the React Native BudgetProgressPreview layout.
struct BudgetProgressPreview: View {
    let categoryName: String
    let spentCents: Int
    let budgetCents: Int
    var isFeeCategory: Bool = false

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
        BudgetTrackerCalculations.remainingLabel(spentCents: spentCents, budgetCents: budgetCents, isFeeCategory: isFeeCategory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(categoryName)
                .font(Typography.h3)
                .foregroundStyle(BrandColors.textPrimary)

            HStack {
                Text(BudgetTrackerCalculations.spentLabel(spentCents: spentCents, isFeeCategory: isFeeCategory))
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
                Spacer()
                Text(remainingLabel)
                    .font(Typography.small)
                    .fontWeight(.regular)
                    .foregroundStyle(BudgetTrackerCalculations.remainingTextColor(percentage: percentage, isFeeCategory: isFeeCategory))
            }

            ProgressBar(
                percentage: percentage,
                fillColor: BudgetTrackerCalculations.progressColor(percentage: percentage, isFeeCategory: isFeeCategory),
                overflowPercentage: overflow > 0 ? overflow : nil,
                overflowColor: overflow > 0 ? StatusColors.overflowBar : nil
            )
        }
    }
}

#Preview("Green (< 50%)") {
    BudgetProgressPreview(categoryName: "Furnishings", spentCents: 20000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}

#Preview("Yellow (50–74%)") {
    BudgetProgressPreview(categoryName: "Furnishings", spentCents: 30000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}

#Preview("Red (≥ 75%)") {
    BudgetProgressPreview(categoryName: "Furnishings", spentCents: 40000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}

#Preview("Over Budget") {
    BudgetProgressPreview(categoryName: "Appliances", spentCents: 75000, budgetCents: 50000)
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}

#Preview("Fee — Green (≥ 75%)") {
    BudgetProgressPreview(categoryName: "Architect Fee", spentCents: 40000, budgetCents: 50000, isFeeCategory: true)
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}

#Preview("Fee — Red (< 50%)") {
    BudgetProgressPreview(categoryName: "Architect Fee", spentCents: 20000, budgetCents: 50000, isFeeCategory: true)
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}
