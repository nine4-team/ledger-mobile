import Foundation

/// Pure lookup helpers that resolve a stable route ID to its current model.
///
/// These are display-source helpers, not the live document source. A detail
/// screen uses them for immediate first paint (and while a focused listener
/// refreshes), then prefers its own focused listener once it returns.
///
/// No SwiftUI, no Firestore, no listener or context mutation — pure functions
/// so they are unit-testable without a live backend.
enum NavigationRouteResolution {
    /// Resolve a project by ID from the account-level project list.
    static func project(id: String, in projects: [Project]) -> Project? {
        projects.first { $0.id == id }
    }

    /// Resolve an item by ID, preferring the project-scoped items over the
    /// account-wide list. Returns nil when the item is in neither.
    static func item(id: String, projectItems: [Item], accountItems: [Item]) -> Item? {
        projectItems.first { $0.id == id } ?? accountItems.first { $0.id == id }
    }
}
