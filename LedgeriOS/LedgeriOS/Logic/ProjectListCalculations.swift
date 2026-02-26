import Foundation

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
}
