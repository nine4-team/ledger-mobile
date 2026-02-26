import SwiftUI

struct ProjectsPlaceholderView: View {
    @State private var showingAddDialog = false

    var body: some View {
        ContentUnavailableView(
            "No Projects Yet",
            systemImage: "house",
            description: Text("Projects will appear here.")
        )
        .navigationTitle("Projects")
        .navigationDestination(for: Project.self) { project in
            Text("Project: \(project.name)")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddDialog = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .confirmationDialog("Create New", isPresented: $showingAddDialog) {
            Button("Create Item") {
                // Phase 4: navigate to item creation
            }
            Button("Create Transaction") {
                // Phase 4: navigate to transaction creation
            }
            Button("Create Project") {
                // Phase 4: navigate to project creation
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProjectsPlaceholderView()
    }
}
