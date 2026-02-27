import Foundation

/// Pure functions for space detail view logic — role gates,
/// item grouping, section defaults. No SwiftUI, no Firestore.
enum SpaceDetailCalculations {

    // MARK: - Role Gate

    /// Returns `true` if the user's role permits saving a space as a template.
    /// Only "owner" and "admin" roles are allowed.
    static func canSaveAsTemplate(userRole: String) -> Bool {
        userRole == "owner" || userRole == "admin"
    }

    // MARK: - Item Grouping

    /// Returns all items belonging to the given space.
    static func itemsInSpace(spaceId: String, allItems: [Item]) -> [Item] {
        allItems.filter { $0.spaceId == spaceId }
    }

    // MARK: - Checklist Progress

    /// Computes checklist progress for a space.
    /// Delegates to `SpaceListCalculations.computeChecklistProgress` to stay DRY.
    static func checklistProgress(for space: Space) -> ChecklistProgress {
        SpaceListCalculations.computeChecklistProgress(for: space)
    }

    // MARK: - Section Defaults

    /// Default expanded/collapsed states for space detail sections (per FR-9.3).
    /// `true` = expanded, `false` = collapsed.
    static func defaultSectionStates() -> [String: Bool] {
        [
            "media": true,
            "notes": false,
            "items": false,
            "checklists": false,
        ]
    }
}
