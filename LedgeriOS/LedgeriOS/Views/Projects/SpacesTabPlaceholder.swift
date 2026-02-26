import SwiftUI

struct SpacesTabPlaceholder: View {
    @Environment(ProjectContext.self) private var projectContext

    var body: some View {
        ContentUnavailableView(
            "\(projectContext.spaces.count) Spaces",
            systemImage: "square.grid.2x2",
            description: Text("Coming soon")
        )
    }
}
