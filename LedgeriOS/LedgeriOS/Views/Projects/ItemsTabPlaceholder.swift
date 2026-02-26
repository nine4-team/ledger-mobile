import SwiftUI

struct ItemsTabPlaceholder: View {
    @Environment(ProjectContext.self) private var projectContext

    var body: some View {
        ContentUnavailableView(
            "\(projectContext.items.count) Items",
            systemImage: "cube.box",
            description: Text("Coming soon")
        )
    }
}
