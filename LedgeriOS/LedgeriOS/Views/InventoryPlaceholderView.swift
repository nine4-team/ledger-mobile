import SwiftUI

struct InventoryPlaceholderView: View {
    @State private var showingCreateMenu = false
    @State private var showNewItem = false
    @State private var showNewSpace = false

    private var createMenuItems: [ActionMenuItem] {
        [
            ActionMenuItem(id: "item", label: "Create Item", icon: "plus.circle", onPress: {
                showNewItem = true
            }),
            ActionMenuItem(id: "space", label: "Create Space", icon: "square.grid.2x2", onPress: {
                showNewSpace = true
            }),
        ]
    }

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
                    showingCreateMenu = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateMenu) {
            ActionMenuSheet(
                title: "Create New",
                items: createMenuItems
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewItem) {
            NewItemView(context: .inventory)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewSpace) {
            NewSpaceView(context: .inventory)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    NavigationStack {
        InventoryPlaceholderView()
    }
}
