import SwiftUI

// MARK: - Universal Add Modifier

/// Adds a branded "+" toolbar button that presents a native Menu dropdown
/// with options to create a project, item, or transaction.
/// Uses native Menu for instant response — no intermediate sheet animation.
struct UniversalAddModifier: ViewModifier {
    @State private var showNewProject = false
    @State private var showNewItem = false
    @State private var showNewTransaction = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .trailingNavBar) {
                    Menu {
                        Button {
                            showNewProject = true
                        } label: {
                            Label("New Project", systemImage: "folder.badge.plus")
                        }
                        Button {
                            showNewItem = true
                        } label: {
                            Label("New Item", systemImage: "shippingbox")
                        }
                        Button {
                            showNewTransaction = true
                        } label: {
                            Label("New Transaction", systemImage: "creditcard")
                        }
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
            .adaptivePresentation(isPresented: $showNewProject, style: .form) {
                NewProjectView()
            }
            .adaptivePresentation(isPresented: $showNewItem, style: .form) {
                NewItemView()
            }
            .adaptivePresentation(isPresented: $showNewTransaction, style: .form) {
                NewTransactionView(context: .inventory)
            }
    }
}

// MARK: - Sheet-Based Universal Add Modifier (preserved for fallback)

/// Alternative version using ActionMenuSheet for richer styling.
/// Trade-off: has a dismiss animation delay before the creation form appears.
struct UniversalAddSheetModifier: ViewModifier {
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
            .adaptivePresentation(isPresented: $showAddMenu, style: .quickMenu, onDismiss: {
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
            }
            .adaptivePresentation(isPresented: $showNewProject, style: .form) {
                NewProjectView()
            }
            .adaptivePresentation(isPresented: $showNewItem, style: .form) {
                NewItemView()
            }
            .adaptivePresentation(isPresented: $showNewTransaction, style: .form) {
                NewTransactionView(context: .inventory)
            }
    }
}

extension View {
    /// Universal add button using native Menu (fast, no intermediate animation).
    func universalAddButton() -> some View {
        modifier(UniversalAddModifier())
    }

    /// Universal add button using ActionMenuSheet (richer styling, slower transition).
    func universalAddButtonSheet() -> some View {
        modifier(UniversalAddSheetModifier())
    }
}
