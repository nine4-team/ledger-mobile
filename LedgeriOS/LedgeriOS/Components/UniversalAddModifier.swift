import SwiftUI

// MARK: - Universal Add Modifier

/// Adds a branded "+" toolbar button that presents a "Create New" menu
/// with options to create a project, item, or transaction.
/// Uses deferred-action pattern to sequence menu → creation form sheets.
struct UniversalAddModifier: ViewModifier {
    @State private var showAddMenu = false
    @State private var pendingCreationAction: (() -> Void)?
    @State private var showNewProject = false
    @State private var showNewItem = false
    @State private var showNewTransaction = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .trailingNavBar) {
                    Button {
                        showAddMenu = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(BrandColors.primary)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Create new")
                }
            }
            .sheet(isPresented: $showAddMenu, onDismiss: {
                pendingCreationAction?()
                pendingCreationAction = nil
            }) {
                ActionMenuSheet(
                    title: "Create New",
                    items: [
                        ActionMenuItem(
                            id: "project",
                            label: "New Project",
                            icon: "folder.badge.plus",
                            onPress: { showNewProject = true }
                        ),
                        ActionMenuItem(
                            id: "item",
                            label: "New Item",
                            icon: "shippingbox",
                            onPress: { showNewItem = true }
                        ),
                        ActionMenuItem(
                            id: "transaction",
                            label: "New Transaction",
                            icon: "creditcard",
                            onPress: { showNewTransaction = true }
                        ),
                    ],
                    onSelectAction: { action in
                        pendingCreationAction = action
                    }
                )
                .sheetStyle(.quickMenu)
            }
            .sheet(isPresented: $showNewProject) {
                NewProjectView()
                    .sheetStyle(.form)
            }
            .sheet(isPresented: $showNewItem) {
                NewItemView(context: .inventory)
                    .sheetStyle(.form)
            }
            .sheet(isPresented: $showNewTransaction) {
                NewTransactionView(context: .inventory)
                    .sheetStyle(.form)
            }
    }
}

extension View {
    func universalAddButton() -> some View {
        modifier(UniversalAddModifier())
    }
}
