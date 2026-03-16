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

    private var addedIds: Set<String> {
        switch context {
        case .transaction(let tx):
            let liveTx = projectContext.transactions.first(where: { $0.id == tx.id }) ?? tx
            return Set(liveTx.itemIds ?? [])
        case .space(let space):
            return Set(projectContext.items.filter { $0.spaceId == space.id }.compactMap(\.id))
        }
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
        NavigationStack {
            VStack(spacing: 0) {
                if tabs.count > 1 {
                    Picker("", selection: $activeTab) {
                        ForEach(tabs, id: \.self) { tab in
                            Text(tabLabel(tab)).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.vertical, Spacing.sm)
                }

                SharedItemsList(
                    mode: .picker(
                        scope: nil,
                        eligibilityCheck: nil,
                        onAddSingle: nil,
                        addedIds: addedIds,
                        onAddSelected: { handleAddSelected() }
                    ),
                    emptyMessage: emptyMessageForTab,
                    selectedIds: $selectedIds,
                    emptyIcon: "shippingbox",
                    filterScope: (activeTab == .outside || activeTab == .projects) ? nil : (activeTab == .inventory ? .inventory : .project),
                    pickerItems: pickerItems
                )
            }
            .navigationTitle(navigationTitle)
            .navBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
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
        }
        .adaptivePresentation(isPresented: $showConflictSheet, style: .quickMenu) {
            ItemConflictSheet(
                message: conflictMessage,
                itemNames: conflictItemNames,
                onConfirm: { executeAdd(items: pendingItems) },
                onCancel: { pendingItems.removeAll() }
            )
        }
        .adaptivePresentation(isPresented: $showCategoryPicker, style: .form) {
            CategoryPickerList(
                categories: accountContext.allBudgetCategories,
                selectedId: nil,
                onSelect: { category in
                    guard let categoryId = category?.id else { return }
                    // Apply chosen category to items that were missing one, then proceed
                    let updatedItems = pendingItems.map { item -> Item in
                        if item.budgetCategoryId == nil {
                            var updated = item
                            updated.budgetCategoryId = categoryId
                            return updated
                        }
                        return item
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
            destinationCategoryId = nil
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
        let destinationProjectId = liveTx.projectId

        // Route by scope
        let routing = AddExistingItemsCalculations.routeByScope(
            items: items,
            destinationProjectId: destinationProjectId
        )

        // Same-scope: use InventoryOperationsService.reassignToProject
        if !routing.sameScope.isEmpty, let destProjectId = destinationProjectId {
            let ops = InventoryOperationsService()
            Task {
                do {
                    try await ops.reassignToProject(
                        items: routing.sameScope,
                        destinationTransactionId: transactionId,
                        destinationProjectId: destProjectId,
                        accountId: accountId
                    )
                } catch {
                    print("🔴 reassignToProject failed: \(error)")
                }
            }
        } else if !routing.sameScope.isEmpty {
            // Inventory-to-inventory: simple batch reassign (no projectId)
            sameProjectBatchReassign(
                items: routing.sameScope,
                transactionId: transactionId,
                accountId: accountId,
                budgetCategoryId: liveTx.budgetCategoryId
            )
        }

        // Cross-scope: use sellToProject (two-hop for project→project, single hop for inventory→project)
        if !routing.crossScope.isEmpty, let destProjectId = destinationProjectId {
            let ops = InventoryOperationsService()
            Task {
                do {
                    try await ops.sellToProject(
                        items: routing.crossScope,
                        destinationProjectId: destProjectId,
                        accountId: accountId,
                        destinationCategoryId: liveTx.budgetCategoryId
                    )
                } catch {
                    print("🔴 sellToProject failed: \(error)")
                }
            }
        }

        selectedIds.removeAll()
        onDismiss()
    }

    /// Fallback batch write for inventory-scope transactions (no projectId).
    private func sameProjectBatchReassign(
        items: [Item],
        transactionId: String,
        accountId: String,
        budgetCategoryId: String?
    ) {
        let batch = FirestoreBatchWriter()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"

        for item in items {
            guard let itemId = item.id else { continue }

            var fields: [String: Any] = [
                "transactionId": transactionId,
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let budgetCategoryId, item.budgetCategoryId == nil {
                fields["budgetCategoryId"] = budgetCategoryId
            }
            if item.projectPriceCents == nil, let purchasePrice = item.purchasePriceCents {
                fields["projectPriceCents"] = purchasePrice
            }
            batch.updateData(fields, forDocumentAt: "\(itemsPath)/\(itemId)")

            // Source transaction cleanup
            if let fromTxId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId])],
                    forDocumentAt: "\(txPath)/\(fromTxId)"
                )
            }
        }

        // Add to destination
        let newIds = items.compactMap(\.id)
        batch.updateData(
            ["itemIds": FieldValue.arrayUnion(newIds), "updatedAt": FieldValue.serverTimestamp()],
            forDocumentAt: "\(txPath)/\(transactionId)"
        )

        Task {
            do { try await batch.commit() }
            catch { print("🔴 sameProjectBatchReassign failed: \(error)") }
        }
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
            Task {
                do {
                    try await ops.sellToProject(
                        items: routing.crossScope,
                        destinationProjectId: destProjectId,
                        accountId: accountId
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
                } catch {
                    print("🔴 cross-scope space add failed: \(error)")
                }
            }
        }

        selectedIds.removeAll()
        onDismiss()
    }
}
