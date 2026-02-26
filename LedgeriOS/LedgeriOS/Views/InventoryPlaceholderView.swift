import SwiftUI

struct InventoryPlaceholderView: View {
    @State private var showingAddDialog = false

    var body: some View {
        ContentUnavailableView(
            "No Items Yet",
            systemImage: "shippingbox",
            description: Text("Inventory items will appear here.")
        )
        .navigationTitle("Inventory")
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
        }
    }
}

#Preview {
    NavigationStack {
        InventoryPlaceholderView()
    }
}
