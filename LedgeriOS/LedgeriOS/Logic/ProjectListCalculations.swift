import Foundation

enum ProjectArchiveFilter {
    case active, archived
}

/// Pure functions for filtering and sorting project lists.
/// Used by project list views and testable without SwiftUI.
enum ProjectListCalculations {

    /// Filters projects by archive state.
    /// When `showArchived` is true, returns only archived projects.
    /// When false, returns projects where `isArchived` is nil or false.
    static func filterByArchiveState(projects: [Project], showArchived: Bool) -> [Project] {
        if showArchived {
            return projects.filter { $0.isArchived == true }
        } else {
            return projects.filter { $0.isArchived != true }
        }
    }

    /// Filters projects by a search query against name and client name.
    /// Returns all projects when query is empty or whitespace-only.
    static func filterBySearch(projects: [Project], query: String) -> [Project] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return projects }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(trimmed)
                || project.clientName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Sorts projects alphabetically by name (case-insensitive).
    /// Projects with empty names sort last, with a final tiebreak on ID.
    static func sortByName(_ projects: [Project]) -> [Project] {
        projects.sorted { a, b in
            let nameA = a.name.lowercased()
            let nameB = b.name.lowercased()
            if !nameA.isEmpty && !nameB.isEmpty {
                return nameA.localizedCompare(nameB) == .orderedAscending
            }
            if !nameA.isEmpty { return true }
            if !nameB.isEmpty { return false }
            return (a.id ?? "") < (b.id ?? "")
        }
    }

    // MARK: - Combined Filter

    /// Filters projects by archive state and search query in one call.
    static func filterProjects(
        _ projects: [Project],
        filter: ProjectArchiveFilter,
        query: String
    ) -> [Project] {
        let archiveFiltered = filterByArchiveState(
            projects: projects,
            showArchived: filter == .archived
        )
        return filterBySearch(projects: archiveFiltered, query: query)
    }

    // MARK: - Empty State

    /// Returns the appropriate empty state message for a given filter.
    static func projectEmptyStateText(for filter: ProjectArchiveFilter) -> String {
        switch filter {
        case .active:
            return "No active projects yet."
        case .archived:
            return "No archived projects yet."
        }
    }

    // MARK: - Budget Bar Categories

    /// Returns ordered categories for the project card budget bar preview.
    /// Priority: (1) pinned categories in pinnedCategoryIds order,
    /// (2) remaining sorted by spend percentage descending,
    /// (3) if no category has any activity, returns empty (caller shows Overall Budget).
    static func budgetBarCategories(
        categories: [BudgetProgress.CategoryProgress],
        pinnedCategoryIds: [String]
    ) -> [BudgetProgress.CategoryProgress] {
        let enabled = categories.filter { $0.budgetCents > 0 || $0.spentCents != 0 }
        guard !enabled.isEmpty else { return [] }

        let enabledById = Dictionary(uniqueKeysWithValues: enabled.map { ($0.id, $0) })

        // Pinned categories in user-defined order
        var pinned: [BudgetProgress.CategoryProgress] = []
        var pinnedIds = Set<String>()
        for id in pinnedCategoryIds {
            if let cat = enabledById[id] {
                pinned.append(cat)
                pinnedIds.insert(id)
            }
        }

        // Remaining categories sorted by spend% descending
        let remaining = enabled
            .filter { !pinnedIds.contains($0.id) }
            .sorted { a, b in
                let pctA = a.budgetCents > 0 ? Double(a.spentCents) / Double(a.budgetCents) : 0
                let pctB = b.budgetCents > 0 ? Double(b.spentCents) / Double(b.budgetCents) : 0
                return pctA > pctB
            }

        return pinned + remaining
    }
}
