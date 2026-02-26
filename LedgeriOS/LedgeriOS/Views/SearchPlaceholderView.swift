import SwiftUI

struct SearchPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Search",
            systemImage: "magnifyingglass",
            description: Text("Search across projects, items, and transactions.")
        )
        .navigationTitle("Search")
    }
}

#Preview {
    NavigationStack {
        SearchPlaceholderView()
    }
}
