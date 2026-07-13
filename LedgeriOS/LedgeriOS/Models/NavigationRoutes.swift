import Foundation

// MARK: - Navigation Routes
//
// Stable navigation values for SwiftUI `.navigationDestination(for:)`.
//
// Route values identify *where to go* using stable IDs — never the mutable
// Firestore model. A `Project` or `Item` struct changes on every listener
// reconciliation, optimistic write, or thumbnail update; using it as a
// `NavigationLink(value:)` payload couples navigation identity to ordinary data
// changes and causes the destination to churn. These route structs stay stable
// across edits, and the destination resolves live display data from context or
// a focused listener.
//
// See the "Navigation" section of the project CLAUDE.md and
// docs/plans/stable-id-navigation-first-milestone-plan.md.

/// Stable route to a project detail surface. Identity is the project ID only.
struct ProjectRoute: Hashable {
    let id: String
}

/// Stable route to an item detail surface. Identity is the item ID plus the
/// minimal immutable context needed to resolve the item from the best source.
/// `projectId` is set for items opened from a project; nil for inventory /
/// account-scope items.
struct ItemRoute: Hashable {
    let id: String
    let projectId: String?

    init(id: String, projectId: String? = nil) {
        self.id = id
        self.projectId = projectId
    }
}

/// Stable route to a space detail surface. `projectId` is set for project
/// spaces; nil is reserved for inventory/account-scope spaces.
struct SpaceRoute: Hashable, Identifiable {
    let id: String
    let projectId: String?

    init(id: String, projectId: String? = nil) {
        self.id = id
        self.projectId = projectId
    }
}
