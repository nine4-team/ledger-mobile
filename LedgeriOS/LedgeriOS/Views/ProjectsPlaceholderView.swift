import SwiftUI

struct ProjectsPlaceholderView: View {
    @State private var showingCreateMenu = false
    @State private var createMenuPendingAction: (() -> Void)?

    private var createMenuItems: [ActionMenuItem] {
        [
            ActionMenuItem(id: "item", label: "Create Item", icon: "plus.circle"),
            ActionMenuItem(id: "transaction", label: "Create Transaction", icon: "plus.circle"),
            ActionMenuItem(id: "project", label: "Create Project", icon: "folder.badge.plus"),
        ]
    }

    var body: some View {
        ContentUnavailableView(
            "No Projects Yet",
            systemImage: "house",
            description: Text("Projects will appear here.")
        )
        .navigationTitle("Projects")
        .navigationDestination(for: ProjectRoute.self) { route in
            ProjectDetailContainer(projectId: route.id)
        }
        .toolbar {
            ToolbarItem(placement: .trailingNavBar) {
                Button {
                    showingCreateMenu = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .adaptivePresentation(isPresented: $showingCreateMenu, style: .quickMenu, onDismiss: {
            createMenuPendingAction?()
            createMenuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: "Create New",
                items: createMenuItems,
                onSelectAction: { action in
                    createMenuPendingAction = action
                }
            )
        }
    }
}

#Preview {
    NavigationStack {
        ProjectsPlaceholderView()
    }
}
