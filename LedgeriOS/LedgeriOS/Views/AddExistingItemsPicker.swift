import SwiftUI
import FirebaseFirestore

/// Context describing where items are being added.
enum AddItemsPickerContext {
    case transaction(Transaction)
    case space(Space)
}

/// Full-featured picker for adding existing items to a transaction or space.
/// Supports scope tabs (Suggested/Project/Outside), conflict detection,
/// and automatic same-scope vs cross-scope routing.
struct AddExistingItemsPicker: View {
    let context: AddItemsPickerContext
    let projectId: String?
    let onDismiss: () -> Void

    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIds: Set<String> = []
    @State private var activeTab: PickerTab = .project
    @State private var showConflictSheet = false
    @State private var conflictMessage = ""
    @State private var conflictItemNames: [String] = []
    @State private var pendingItems: [Item] = []
    @State private var showCategoryPicker = false
    @State private var itemsAwaitingCategory: [Item] = []
    @State private var resolvedSpaceCategoryId: String?
    @State private var showSpaceMoveConfirm = false
    @State private var spaceMoveConfirmCount = 0

    // MARK: - Computed

    private var tabs: [PickerTab] {
        switch context {
        case .transaction(let tx):
            return AddExistingItemsCalculations.availableTabs(
                transaction: tx,
                projectItems: projectContext.items,
                allItems: accountContext.allItems
            )
        case .space:
            return AddExistingItemsCalculations.spaceAvailableTabs()
        }
    }

    private func tabLabel(_ tab: PickerTab) -> String {
        switch tab {
        case .suggested: "Suggested"
        case .project: "Project"
        case .outside: "Outside"
        case .inventory: "Inventory"
        case .projects: "Projects"
        }
    }

    private var currentTransaction: Transaction? {
        if case .transaction(let tx) = context {
            return projectContext.transactions.first(where: { $0.id == tx.id }) ?? tx
        }
        return nil
    }

    private var destinationIsReturn: Bool {
        currentTransaction?.isReturnTransaction ?? false
    }

    private var addedIds: Set<String> {
        switch context {
        case .transaction(let tx):
            let liveTx = projectContext.transactions.first(where: { $0.id == tx.id }) ?? tx
            return Set(liveTx.itemIds ?? [])
        case .space(let space):
            return Set(projectContext.items.filter { $0.spaceId == space.id }.compactMap(\.id))
        }
    }

    /// For space context: returns the name of the OTHER space an item lives in,
    /// nil if unassigned or already in the current space.
    private func otherSpaceName(for item: Item) -> String? {
        guard case .space(let currentSpace) = context,
              let itemSpaceId = item.spaceId,
              itemSpaceId != currentSpace.id
        else { return nil }
        return accountContext.allSpaces.first(where: { $0.id == itemSpaceId })?.name
    }

    private var pickerItems: [Item] {
        switch context {
        case .transaction(let tx):
            let liveTx = projectContext.transactions.first(where: { $0.id == tx.id }) ?? tx
            return AddExistingItemsCalculations.itemsForTab(
                activeTab,
                transaction: liveTx,
                projectItems: projectContext.items,
                allItems: accountContext.allItems
            )
        case .space(let space):
            return AddExistingItemsCalculations.itemsForSpaceTab(
                activeTab,
                space: space,
                projectId: projectId,
                projectItems: projectContext.items,
                allItems: accountContext.allItems
            )
        }
    }

    private var navigationTitle: String {
        switch context {
        case .transaction: "Add Existing Items"
        case .space: "Add Items to Space"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(navigationTitle)
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BrandColors.textTertiary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.screenPadding)
            .padding(.bottom, Spacing.md)

            if tabs.count > 1 {
                SegmentedControl(selection: $activeTab, options: tabs.map {
                    SegmentOption(id: $0, label: tabLabel($0))
                })
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.sm)
            }

            SharedItemsList(
                mode: .picker(
                    scope: nil,
                    eligibilityCheck: nil,
                    onAddSingle: nil,
                    addedIds: addedIds,
                    onAddSelected: { handleAddSelected() },
                    otherSpaceNameForItem: { item in otherSpaceName(for: item) }
                ),
                emptyMessage: emptyMessageForTab,
                selectedIds: $selectedIds,
                emptyIcon: "shippingbox",
                filterScope: (activeTab == .outside || activeTab == .projects) ? nil : (activeTab == .inventory ? .inventory : .project),
                pickerItems: pickerItems
            )
        }
        .onChange(of: activeTab) {
            selectedIds.removeAll()
        }
        .onAppear {
            // Default to first available tab
            if let first = tabs.first {
                activeTab = first
            }
        }
        .adaptivePresentation(isPresented: $showConflictSheet, style: .quickMenu) {
            ItemConflictSheet(
                message: conflictMessage,
                itemNames: conflictItemNames,
                onConfirm: { executeAdd(items: pendingItems) },
                onReturn: destinationIsReturn ? { executeReturn(items: pendingItems) } : nil,
                onCancel: { pendingItems.removeAll() }
            )
        }
        .alert(
            "Move \(spaceMoveConfirmCount) item\(spaceMoveConfirmCount == 1 ? "" : "s") from other spaces?",
            isPresented: $showSpaceMoveConfirm
        ) {
            Button("Move") {
                let items = pendingItems
                pendingItems.removeAll()
                executeAdd(items: items)
            }
            Button("Cancel", role: .cancel) {
                pendingItems.removeAll()
            }
        } message: {
            Text("\(spaceMoveConfirmCount) selected item\(spaceMoveConfirmCount == 1 ? "" : "s") will be moved out of \(spaceMoveConfirmCount == 1 ? "its current space" : "their current spaces").")
        }
        .adaptivePresentation(isPresented: $showCategoryPicker, style: .form) {
            CategoryPickerList(
                categories: accountContext.allBudgetCategories,
                selectedId: nil,
                onSelect: { category in
                    guard let categoryId = category?.id else { return }
                    resolvedSpaceCategoryId = categoryId
                    let updatedItems = pendingItems.map { item -> Item in
                        var updated = item
                        updated.budgetCategoryId = categoryId
                        return updated
                    }
                    executeAdd(items: updatedItems)
                }
            )
        }
    }

    private var emptyMessageForTab: String {
        switch activeTab {
        case .suggested: "No vendor-matched items"
        case .project: "No items available"
        case .outside: "No items outside this project"
        case .inventory: "No inventory items available"
        case .projects: "No project items available"
        }
    }

    // MARK: - Add Flow

    private func handleAddSelected() {
        let allItems: [Item]
        switch context {
        case .transaction:
            allItems = pickerItems + projectContext.items + accountContext.allItems
        case .space:
            allItems = pickerItems + projectContext.items + accountContext.allItems
        }

        // Resolve selected items from all available sources
        let idSet = selectedIds
        var seen = Set<String>()
        let selectedItems = allItems.filter { item in
            guard let id = item.id, idSet.contains(id), !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }

        guard !selectedItems.isEmpty else { return }

        // Space move confirmation: if any selected items live in another space,
        // confirm once before proceeding.
        if case .space(let currentSpace) = context {
            let movers = selectedItems.filter { item in
                guard let sid = item.spaceId else { return false }
                return sid != currentSpace.id
            }
            if !movers.isEmpty {
                pendingItems = selectedItems
                spaceMoveConfirmCount = movers.count
                showSpaceMoveConfirm = true
                return
            }
        }

        // Conflict detection (transaction context only)
        if case .transaction(let tx) = context {
            let liveTx = projectContext.transactions.first(where: { $0.id == tx.id }) ?? tx
            let conflicts = AddExistingItemsCalculations.detectConflicts(
                selectedItems: selectedItems,
                destinationTransactionId: liveTx.id ?? ""
            )

            if !conflicts.isEmpty {
                let summary = AddExistingItemsCalculations.conflictSummary(
                    conflicts: conflicts,
                    allTransactions: projectContext.transactions + accountContext.allTransactions
                )
                if let summary {
                    conflictMessage = summary.message
                    conflictItemNames = summary.itemNames
                    pendingItems = selectedItems
                    showConflictSheet = true
                    return
                }
            }
        }

        executeAdd(items: selectedItems)
    }

    private func executeAdd(items: [Item]) {
        // Check if cross-scope items need a budget category before proceeding
        let destinationProjectId: String?
        let destinationCategoryId: String?

        switch context {
        case .transaction(let tx):
            let liveTx = projectContext.transactions.first(where: { $0.id == tx.id }) ?? tx
            destinationProjectId = liveTx.projectId
            destinationCategoryId = liveTx.budgetCategoryId
        case .space:
            destinationProjectId = projectId
            destinationCategoryId = resolvedSpaceCategoryId
        }

        let routing = AddExistingItemsCalculations.routeByScope(
            items: items,
            destinationProjectId: destinationProjectId
        )

        let needCategory = AddExistingItemsCalculations.itemsNeedingCategory(
            crossScopeItems: routing.crossScope,
            destinationCategoryId: destinationCategoryId
        )

        if !needCategory.isEmpty {
            pendingItems = items
            showCategoryPicker = true
            return
        }

        switch context {
        case .transaction(let tx):
            addItemsToTransaction(items: items, transaction: tx)
        case .space(let space):
            addItemsToSpace(items: items, space: space)
        }
    }

    // MARK: - Transaction Add

    private func addItemsToTransaction(items: [Item], transaction: Transaction) {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = transaction.id else { return }

        let liveTx = projectContext.transactions.first(where: { $0.id == transaction.id }) ?? transaction
        let routing = AddExistingItemsCalculations.routeByScope(items: items, destinationProjectId: liveTx.projectId)
        Task {
            do {
                if !routing.sameScope.isEmpty {
                    try await ItemsService().setTransaction(
                        accountId: accountId,
                        items: routing.sameScope,
                        transactionId: transactionId
                    )
                }
                if !routing.crossScope.isEmpty,
                   let destinationProjectId = liveTx.projectId,
                   let destinationCategoryId = liveTx.budgetCategoryId {
                    try await InventoryOperationsService().reassignToProject(
                        items: routing.crossScope,
                        destinationTransactionId: transactionId,
                        destinationProjectId: destinationProjectId,
                        destinationBudgetCategoryId: destinationCategoryId,
                        accountId: accountId
                    )
                }
            } catch { print("🔴 addItemsToTransaction failed: \(error)") }
        }

        selectedIds.removeAll()
        onDismiss()
    }

    // MARK: - Return Add

    private func executeReturn(items: [Item]) {
        guard let accountId = accountContext.currentAccountId,
              let transactionId = currentTransaction?.id,
              let categoryId = currentTransaction?.budgetCategoryId else { return }

        let service = InventoryOperationsService()
        Task {
            do {
                try await service.returnToTransaction(
                    items: items,
                    destinationTransactionId: transactionId,
                    destinationBudgetCategoryId: categoryId,
                    accountId: accountId
                )
            } catch {
                print("🔴 executeReturn failed: \(error)")
            }
        }

        selectedIds.removeAll()
        onDismiss()
    }

    // MARK: - Space Add

    private func addItemsToSpace(items: [Item], space: Space) {
        guard let accountId = accountContext.currentAccountId,
              let spaceId = space.id else { return }

        // Route by scope
        let routing = AddExistingItemsCalculations.routeByScope(
            items: items,
            destinationProjectId: projectId
        )

        // Same-scope: batch update spaceId
        if !routing.sameScope.isEmpty {
            let batch = FirestoreBatchWriter()
            let itemsPath = "accounts/\(accountId)/items"
            for item in routing.sameScope {
                guard let itemId = item.id else { continue }
                batch.updateData(
                    ["spaceId": spaceId, "updatedAt": FieldValue.serverTimestamp()],
                    forDocumentAt: "\(itemsPath)/\(itemId)"
                )
            }
            Task {
                do { try await batch.commit() }
                catch { print("🔴 space batch spaceId update failed: \(error)") }
            }
        }

        // Cross-scope: sell first, then set spaceId
        if !routing.crossScope.isEmpty, let destProjectId = projectId {
            let ops = InventoryOperationsService()
            let inventoryLabel = InventoryOperationsService.inventoryLabel(for: accountContext.account?.name)
            Task {
                do {
                    guard let categoryId = resolvedSpaceCategoryId else { return }
                    try await ops.sellToProject(
                        items: routing.crossScope,
                        destinationProjectId: destProjectId,
                        budgetCategoryId: categoryId,
                        accountId: accountId,
                        inventoryLabel: inventoryLabel
                    )
                    // After sell completes, set spaceId
                    let batch = FirestoreBatchWriter()
                    let itemsPath = "accounts/\(accountId)/items"
                    for item in routing.crossScope {
                        guard let itemId = item.id else { continue }
                        batch.updateData(
                            ["spaceId": spaceId, "updatedAt": FieldValue.serverTimestamp()],
                            forDocumentAt: "\(itemsPath)/\(itemId)"
                        )
                    }
                    try await batch.commit()
                    await MainActor.run { resolvedSpaceCategoryId = nil }
                } catch {
                    print("🔴 cross-scope space add failed: \(error)")
                }
            }
        }

        selectedIds.removeAll()
        onDismiss()
    }
}
