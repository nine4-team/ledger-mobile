import SwiftUI

struct InventoryPlaceholderView: View {
    @State private var showingCreateMenu = false
    @State private var createMenuPendingAction: (() -> Void)?

    private var createMenuItems: [ActionMenuItem] {
        [
            ActionMenuItem(id: "item", label: "Create Item", icon: "plus.circle"),
            ActionMenuItem(id: "transaction", label: "Create Transaction", icon: "plus.circle"),
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
        .sheet(isPresented: $showingCreateMenu, onDismiss: {
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
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    NavigationStack {
        InventoryPlaceholderView()
    }
}
