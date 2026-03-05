import SwiftUI

/// Shows the user's pinned budget categories as compact progress bars.
/// Renders between the nav bar and ScrollableTabBar in ProjectDetailView.
/// If no categories are pinned (or budget data hasn't loaded), renders nothing.
struct PinnedBudgetsSection: View {
    @Environment(ProjectContext.self) private var projectContext

    private var pinnedCategories: [BudgetProgress.CategoryProgress] {
        BudgetTabCalculations.pinnedCategories(
            allCategories: projectContext.budgetProgress?.categories ?? [],
            pinnedCategoryIds: projectContext.projectPreferences?.pinnedBudgetCategoryIds ?? []
        )
    }

    var body: some View {
        if !pinnedCategories.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(pinnedCategories) { category in
                    BudgetProgressPreview(
                        categoryName: category.name,
                        spentCents: category.spentCents,
                        budgetCents: category.budgetCents,
                        categoryType: category.categoryType
                    )
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.md)
        }
    }
}
