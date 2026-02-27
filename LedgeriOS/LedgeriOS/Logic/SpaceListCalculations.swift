import Foundation

/// View-model data for a space card in the spaces list.
struct SpaceCardData {
    let space: Space
    let itemCount: Int
    let checklistProgress: ChecklistProgress
}

/// Progress through checklist items (completed / total).
struct ChecklistProgress: Equatable {
    let completed: Int
    let total: Int
    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    var displayText: String { "\(completed) of \(total)" }
}

/// Pure functions for filtering, sorting, search, and progress
/// computation on the spaces list. No SwiftUI, no Firestore.
enum SpaceListCalculations {

    // MARK: - Checklist Progress

    /// Computes checklist progress across ALL checklists in a space.
    /// Returns 0/0 when the space has no checklist items.
    static func computeChecklistProgress(for space: Space) -> ChecklistProgress {
        let allItems = space.checklists?.flatMap(\.items) ?? []
        let total = allItems.count
        let completed = allItems.filter(\.isChecked).count
        return ChecklistProgress(completed: completed, total: total)
    }

    // MARK: - Build Cards

    /// Builds card data for each space, computing item counts and checklist progress.
    static func buildSpaceCards(spaces: [Space], items: [Item]) -> [SpaceCardData] {
        spaces.map { space in
            let itemCount = items.filter { $0.spaceId == space.id }.count
            let progress = computeChecklistProgress(for: space)
            return SpaceCardData(space: space, itemCount: itemCount, checklistProgress: progress)
        }
    }

    // MARK: - Search

    /// Filters space cards by a case-insensitive substring match on the space name.
    /// Returns all cards when the query is empty or whitespace-only.
    static func applySearch(spaces: [SpaceCardData], query: String) -> [SpaceCardData] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return spaces }
        return spaces.filter { $0.space.name.localizedCaseInsensitiveContains(trimmed) }
    }

    // MARK: - Sort

    /// Sorts space cards alphabetically by name (case-insensitive).
    /// Spaces with empty names sort last, with a tiebreak on ID.
    static func sortSpaces(_ spaces: [SpaceCardData]) -> [SpaceCardData] {
        spaces.sorted { a, b in
            let nameA = a.space.name.lowercased()
            let nameB = b.space.name.lowercased()
            if !nameA.isEmpty && !nameB.isEmpty {
                return nameA.localizedCompare(nameB) == .orderedAscending
            }
            if !nameA.isEmpty { return true }
            if !nameB.isEmpty { return false }
            return (a.space.id ?? "") < (b.space.id ?? "")
        }
    }
}
