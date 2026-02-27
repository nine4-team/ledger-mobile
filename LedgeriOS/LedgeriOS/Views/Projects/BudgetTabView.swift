import SwiftUI

struct BudgetTabView: View {
    @Environment(ProjectContext.self) private var projectContext

    private var pinnedCategoryIds: [String] {
        projectContext.projectPreferences?.pinnedBudgetCategoryIds ?? []
    }

    private var categories: [BudgetProgress.CategoryProgress] {
        guard let progress = projectContext.budgetProgress else { return [] }
        let enabled = BudgetTabCalculations.enabledCategories(allCategories: progress.categories)
        let sorted = BudgetTabCalculations.sortCategories(enabled)
        return BudgetTabCalculations.applyPinning(sorted, pinnedCategoryIds: pinnedCategoryIds)
    }

    private var overallBudgetCents: Int {
        guard let progress = projectContext.budgetProgress else { return 0 }
        return progress.categories
            .filter { !$0.excludeFromOverallBudget }
            .reduce(0) { $0 + $1.budgetCents }
    }

    private var overallSpentCents: Int {
        guard let progress = projectContext.budgetProgress else { return 0 }
        return progress.categories
            .filter { !$0.excludeFromOverallBudget }
            .reduce(0) { $0 + $1.spentCents }
    }

    var body: some View {
        if categories.isEmpty {
            ContentUnavailableView(
                "No Budget Set",
                systemImage: "chart.bar",
                description: Text("Budget categories will appear here once configured.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(categories) { category in
                        BudgetCategoryRow(category: category)
                        if category.id != categories.last?.id {
                            Divider()
                                .foregroundStyle(BrandColors.borderSecondary)
                        }
                    }

                    // Overall Budget row
                    if overallBudgetCents > 0 {
                        Divider()
                            .padding(.vertical, Spacing.xs)

                        overallBudgetRow
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    private var overallBudgetRow: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Overall Budget")
                .font(Typography.h3)
                .foregroundStyle(BrandColors.textPrimary)

            HStack {
                Text(BudgetTabCalculations.spentLabel(
                    spentCents: overallSpentCents,
                    categoryType: .general
                ))
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)

                Spacer()

                let isOver = overallSpentCents > overallBudgetCents
                Text(BudgetTabCalculations.remainingLabel(
                    spentCents: overallSpentCents,
                    budgetCents: overallBudgetCents,
                    categoryType: .general
                ))
                .font(Typography.small)
                .fontWeight(isOver ? .bold : .regular)
                .foregroundStyle(isOver ? StatusColors.overflowBar : BrandColors.textSecondary)
            }

            BudgetProgressView(
                spentCents: overallSpentCents,
                budgetCents: overallBudgetCents,
                compact: true
            )
        }
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Budget Category Row

private struct BudgetCategoryRow: View {
    let category: BudgetProgress.CategoryProgress

    private var isFee: Bool { category.categoryType == .fee }
    private var isOverBudget: Bool {
        category.budgetCents > 0 && category.spentCents > category.budgetCents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("\(category.name) Budget")
                .font(Typography.h3)
                .foregroundStyle(BrandColors.textPrimary)

            HStack {
                Text(BudgetTabCalculations.spentLabel(
                    spentCents: category.spentCents,
                    categoryType: category.categoryType
                ))
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)

                Spacer()

                Text(BudgetTabCalculations.remainingLabel(
                    spentCents: category.spentCents,
                    budgetCents: category.budgetCents,
                    categoryType: category.categoryType
                ))
                .font(Typography.small)
                .fontWeight(isOverBudget ? .bold : .regular)
                .foregroundStyle(isOverBudget ? StatusColors.overflowBar : BrandColors.textSecondary)
            }

            if category.budgetCents > 0 {
                BudgetProgressView(
                    spentCents: category.spentCents,
                    budgetCents: category.budgetCents,
                    compact: true
                )
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}
