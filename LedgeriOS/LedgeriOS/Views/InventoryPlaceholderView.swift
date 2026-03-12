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
            ToolbarItem(placement: .trailingNavBar) {
                Button {
                    showingCreateMenu = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .adaptivePresentation(isPresented: $showingCreateMenu, style: .quickMenu) {
            ActionMenuSheet(
                title: "Create New",
                items: createMenuItems
            )
        }
        .adaptivePresentation(isPresented: $showNewItem, style: .form) {
            NewItemView(context: .inventory)
        }
        .adaptivePresentation(isPresented: $showNewSpace, style: .form) {
            NewSpaceView(context: .inventory)
        }
    }
}

#Preview {
    NavigationStack {
        InventoryPlaceholderView()
    }
}
