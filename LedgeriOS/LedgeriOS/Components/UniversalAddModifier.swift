import SwiftUI

// MARK: - Universal Add Modifier

/// Adds a branded "+" toolbar button that presents a native Menu dropdown
/// with options to create a project, item, or transaction.
/// Uses native Menu for instant response — no intermediate sheet animation.
struct UniversalAddModifier: ViewModifier {
    @State private var showNewProject = false
    @State private var showNewItem = false
    @State private var showNewTransaction = false
    @State private var showQuickNote = false
    @State private var createdTransaction: Transaction?

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
                            print("🔵 [UniversalAdd] 'New Transaction' menu item tapped")
                            showNewTransaction = true
                        } label: {
                            Label("New Transaction", systemImage: "creditcard")
                        }
                        Button {
                            showQuickNote = true
                        } label: {
                            Label("Quick Note", systemImage: "note.text")
                        }
                    } label: {
                        UniversalAddIcon()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Create new")
                }
            }
            .adaptivePresentation(isPresented: $showNewProject, style: .form) {
                NewProjectView()
            }
            .adaptivePresentation(isPresented: $showNewItem, style: .form) {
                NewItemView()
            }
            .onChange(of: showNewTransaction) { _, newValue in
                print("🔵 [UniversalAdd] showNewTransaction changed to \(newValue)")
            }
            .adaptivePresentation(isPresented: $showNewTransaction, style: .form) {
                let _ = print("🔵 [UniversalAdd] NewTransactionView sheet body evaluated")
                NewTransactionView(
                    context: .inventory,
                    onCreated: { createdTransaction = $0 }
                )
            }
            .adaptivePresentation(isPresented: $showQuickNote, style: .form) {
                QuickNoteModal()
            }
            .navigationDestination(item: $createdTransaction) { tx in
                TransactionDetailView(transaction: tx)
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
    @State private var showQuickNote = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .trailingNavBar) {
                    Button {
                        showAddMenu = true
                    } label: {
                        UniversalAddIcon()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
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
                        ActionMenuItem(
                            id: "note",
                            label: "Quick Note",
                            icon: "note.text",
                            onPress: { showQuickNote = true }
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
            .adaptivePresentation(isPresented: $showQuickNote, style: .form) {
                QuickNoteModal()
            }
    }
}

// MARK: - Universal Add Icon

/// Branded "+" icon: white plus on a brand-primary disc. The surrounding
/// circular chrome is supplied by the toolbar button via `.buttonStyle(.bordered)`
/// + `.buttonBorderShape(.circle)`.
struct UniversalAddIcon: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(BrandColors.primary, in: Circle())
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
