import Foundation

// MARK: - Navigation Routes
//
// Small immutable identifiers used as view input or at the root navigation
// level. Nested entity screens use parent-owned selected IDs with
// `.navigationDestination(isPresented:)`; they do not enter SwiftUI's typed
// navigation path.

/// Stable route to a project detail surface. Identity is the project ID only.
struct ProjectRoute: Hashable {
    let id: String
}

/// Immutable space lookup context used by search detail presentation.
struct SpaceRoute: Hashable, Identifiable {
    let id: String
    let projectId: String?

    init(id: String, projectId: String? = nil) {
        self.id = id
        self.projectId = projectId
    }
}
