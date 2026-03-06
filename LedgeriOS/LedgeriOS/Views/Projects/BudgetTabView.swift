import SwiftUI

struct BudgetTabView: View {
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager

    private let preferencesService = ProjectPreferencesService()
    /// Tracks whether auto-pin has been attempted this session to avoid re-pinning on every view update.
    @State private var didAutoPin = false

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
        let _ = print("[BudgetTab] categories=\(categories.count), budgetProgress=\(projectContext.budgetProgress != nil ? "\(projectContext.budgetProgress!.categories.count) cats" : "nil"), budgetCats=\(projectContext.budgetCategories.count), projBudgetCats=\(projectContext.projectBudgetCategories.count), txns=\(projectContext.transactions.count)")
        Group {
            if categories.isEmpty {
                ContentUnavailableView(
                    "No Budget Set",
                    systemImage: "chart.bar",
                    description: Text("Budget categories will appear here once configured.")
                )
            } else {
                ScrollView {
                    AdaptiveContentWidth {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(categories) { category in
                                BudgetCategoryRow(
                                    category: category,
                                    isPinned: pinnedCategoryIds.contains(category.id),
                                    onTogglePin: { togglePin(category.id) }
                                )
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
        }
        // M13: Reset auto-pin flag when project changes, then auto-pin Furnishings on first view
        .task(id: projectContext.currentProjectId) {
            didAutoPin = false
        }
        .onChange(of: categories.count) { _, newCount in
            guard newCount > 0, !didAutoPin, pinnedCategoryIds.isEmpty else { return }
            didAutoPin = true
            autoPickFurnishingsIfNeeded()
        }
    }

    private var overallBudgetRow: some View {
        let isOver = overallSpentCents > overallBudgetCents
        let pct = BudgetTrackerCalculations.progressPercentage(spentCents: overallSpentCents, budgetCents: overallBudgetCents)
        let overflow = BudgetTrackerCalculations.overflowPercentage(spentCents: overallSpentCents, budgetCents: overallBudgetCents)

        return HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Overall Budget")
                    .font(Typography.h3)
                    .foregroundStyle(BrandColors.textPrimary)

                HStack {
                    Text(BudgetTabCalculations.spentLabel(spentCents: overallSpentCents, categoryType: .general))
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                    Spacer()
                    Text(BudgetTabCalculations.remainingLabel(
                        spentCents: overallSpentCents,
                        budgetCents: overallBudgetCents,
                        categoryType: .general
                    ))
                    .font(Typography.small)
                    .fontWeight(isOver ? .bold : .regular)
                    .foregroundStyle(isOver ? StatusColors.overflowBar : BrandColors.textSecondary)
                }

                ProgressBar(
                    percentage: pct,
                    fillColor: BrandColors.primary,
                    overflowPercentage: overflow > 0 ? overflow : nil,
                    overflowColor: overflow > 0 ? StatusColors.overflowBar : nil
                )
            }

            // Spacer keeps alignment with pinnable rows
            Color.clear.frame(width: 20)
        }
        .padding(.vertical, Spacing.sm)
    }

    private func autoPickFurnishingsIfNeeded() {
        guard let furnishings = categories.first(where: { $0.name.lowercased().contains("furnishing") }),
              let accountId = accountContext.currentAccountId,
              let userId = authManager.currentUser?.uid,
              let projectId = projectContext.currentProjectId else { return }
        Task {
            try? await preferencesService.updatePinnedCategories(
                accountId: accountId,
                userId: userId,
                projectId: projectId,
                pinnedIds: [furnishings.id]
            )
        }
    }

    private func togglePin(_ categoryId: String) {
        guard let accountId = accountContext.currentAccountId,
              let userId = authManager.currentUser?.uid,
              let projectId = projectContext.currentProjectId else { return }

        let current = pinnedCategoryIds
        let next = current.contains(categoryId)
            ? current.filter { $0 != categoryId }
            : current + [categoryId]

        Task {
            try? await preferencesService.updatePinnedCategories(
                accountId: accountId,
                userId: userId,
                projectId: projectId,
                pinnedIds: next
            )
        }
    }
}

// MARK: - Budget Category Row

private struct BudgetCategoryRow: View {
    let category: BudgetProgress.CategoryProgress
    let isPinned: Bool
    let onTogglePin: () -> Void

    private var isOverBudget: Bool {
        category.budgetCents > 0 && category.spentCents > category.budgetCents
    }

    private var percentage: Double {
        BudgetTrackerCalculations.progressPercentage(spentCents: category.spentCents, budgetCents: category.budgetCents)
    }

    private var overflow: Double {
        BudgetTrackerCalculations.overflowPercentage(spentCents: category.spentCents, budgetCents: category.budgetCents)
    }

    private var displayName: String {
        category.categoryType == .fee ? category.name : "\(category.name) Budget"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(displayName)
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
                    ProgressBar(
                        percentage: percentage,
                        fillColor: BrandColors.primary,
                        overflowPercentage: overflow > 0 ? overflow : nil,
                        overflowColor: overflow > 0 ? StatusColors.overflowBar : nil
                    )
                }
            }

            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundStyle(isPinned ? BrandColors.primary : BrandColors.textSecondary)
                    .opacity(isPinned ? 1 : 0.4)
                    .frame(width: 20, height: 20)
            }
            .padding(.bottom, 1)
        }
        .padding(.vertical, Spacing.sm)
    }
}
