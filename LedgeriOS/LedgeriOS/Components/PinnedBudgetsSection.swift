import SwiftUI

/// Shows the user's pinned budget categories as compact progress bars.
/// Renders between the nav bar and ScrollableTabBar in ProjectDetailView.
/// If no categories are pinned (or budget data hasn't loaded), renders nothing.
struct PinnedBudgetsSection: View {
    @Environment(ProjectContext.self) private var projectContext

    private static let overallBudgetPinId = "overall"

    private var pinnedIds: [String] {
        projectContext.projectPreferences?.pinnedBudgetCategoryIds ?? []
    }

    private var pinnedCategories: [BudgetProgress.CategoryProgress] {
        BudgetTabCalculations.pinnedCategories(
            allCategories: projectContext.budgetProgress?.categories ?? [],
            pinnedCategoryIds: pinnedIds
        )
    }

    private var isOverallPinned: Bool {
        pinnedIds.contains(Self.overallBudgetPinId)
    }

    private var overallProgress: BudgetProgress.CategoryProgress? {
        guard isOverallPinned,
              let progress = projectContext.budgetProgress else { return nil }
        let included = progress.categories.filter { !$0.excludeFromOverallBudget }
        let totalBudget = included.reduce(0) { $0 + $1.budgetCents }
        let totalSpent = included.reduce(0) { $0 + $1.spentCents }
        guard totalBudget > 0 else { return nil }
        return BudgetProgress.CategoryProgress(
            id: Self.overallBudgetPinId,
            name: "Overall Budget",
            budgetCents: totalBudget,
            spentCents: totalSpent,
            categoryType: .general,
            excludeFromOverallBudget: false
        )
    }

    var body: some View {
        let cats = pinnedCategories
        let overall = overallProgress
        if !cats.isEmpty || overall != nil {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(cats) { category in
                    BudgetProgressPreview(
                        categoryName: category.name,
                        spentCents: category.spentCents,
                        budgetCents: category.budgetCents,
                        categoryType: category.categoryType
                    )
                }
                if let overall {
                    BudgetProgressPreview(
                        categoryName: overall.name,
                        spentCents: overall.spentCents,
                        budgetCents: overall.budgetCents,
                        categoryType: overall.categoryType
                    )
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.md)
        }
    }
}
