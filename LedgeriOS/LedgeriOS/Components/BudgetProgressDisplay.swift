import SwiftUI

struct BudgetProgressDisplay: View {
    let categories: [BudgetProgress.CategoryProgress]
    var onManageBudget: (() -> Void)?

    var body: some View {
        if categories.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    BudgetCategoryTracker(
                        name: category.name,
                        spentCents: category.spentCents,
                        budgetCents: category.budgetCents,
                        categoryType: category.categoryType
                    )

                    if index < categories.count - 1 {
                        Divider()
                            .foregroundStyle(BrandColors.borderSecondary)
                    }
                }

                if let onManageBudget {
                    AppButton(
                        title: "Manage Budget",
                        variant: .secondary,
                        action: onManageBudget
                    )
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("2 Categories") {
    BudgetProgressDisplay(
        categories: [
            BudgetProgress.CategoryProgress(
                id: "furnishings",
                name: "Furnishings Budget",
                budgetCents: 100_000,
                spentCents: 87_305,
                categoryType: .general,
                excludeFromOverallBudget: false
            ),
            BudgetProgress.CategoryProgress(
                id: "kitchen",
                name: "Kitchen Budget",
                budgetCents: 50_000,
                spentCents: 50_000,
                categoryType: .general,
                excludeFromOverallBudget: false
            ),
        ]
    )
    .padding(Spacing.screenPadding)
}

#Preview("Over Budget Category") {
    BudgetProgressDisplay(
        categories: [
            BudgetProgress.CategoryProgress(
                id: "additional",
                name: "Additional Requests Budget",
                budgetCents: 50_000,
                spentCents: 83_560,
                categoryType: .general,
                excludeFromOverallBudget: false
            ),
        ]
    )
    .padding(Spacing.screenPadding)
}

#Preview("With Manage Button") {
    BudgetProgressDisplay(
        categories: [
            BudgetProgress.CategoryProgress(
                id: "fuel",
                name: "Fuel Budget",
                budgetCents: 100_000,
                spentCents: 34_100,
                categoryType: .general,
                excludeFromOverallBudget: false
            ),
        ],
        onManageBudget: {}
    )
    .padding(Spacing.screenPadding)
}

#Preview("Empty") {
    BudgetProgressDisplay(categories: [])
        .padding(Spacing.screenPadding)
}
