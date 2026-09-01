import Foundation

// MARK: - Types

/// Callbacks for single-transaction menu actions. All optional so callers only wire what they need.
struct SingleTransactionMenuCallbacks {
    // Correct / Move — within-scope correction (no transactions, no budget impact).
    // Note: these reassign the whole transaction's scope, which is distinct from
    // item-level Correct / Move. See docs/specs/reassign-vs-sell.md.
    var onReassignToInventory: (() -> Void)?
    var onReassignToProject: (() -> Void)?
    // Copy ID
    var onCopyID: (() -> Void)?
    // Delete
    var onDelete: (() -> Void)?
}

/// Callbacks for bulk transaction menu actions.
struct BulkTransactionMenuCallbacks {
    var onCopyIDs: (() -> Void)?
    var onDelete: (() -> Void)?
}

/// Creation actions exposed from the Items section of a transaction detail.
/// Keeping this menu scope-agnostic ensures project and inventory transactions
/// offer the same creation paths.
struct TransactionItemCreationMenuCallbacks {
    var onCreateQuickDraft: (() -> Void)?
    var onCreateItem: (() -> Void)?
    var onAddExisting: (() -> Void)?
    var onCreateFromImages: (() -> Void)?
}

// MARK: - Builder

enum TransactionMenuBuilder {

    // MARK: Item Creation Menu

    static func buildItemCreationMenu(
        callbacks: TransactionItemCreationMenuCallbacks
    ) -> [ActionMenuItem] {
        var items: [ActionMenuItem] = []

        if let onCreateQuickDraft = callbacks.onCreateQuickDraft {
            items.append(ActionMenuItem(
                id: "item-draft",
                label: "Quick Add",
                icon: "camera.badge.ellipsis",
                onPress: onCreateQuickDraft
            ))
        }
        if let onCreateItem = callbacks.onCreateItem {
            items.append(ActionMenuItem(
                id: "create-new",
                label: "Create New Item",
                icon: "plus.square.fill",
                onPress: onCreateItem
            ))
        }
        if let onAddExisting = callbacks.onAddExisting {
            items.append(ActionMenuItem(
                id: "add-existing",
                label: "Add Existing Items",
                icon: "plus.square.on.square",
                onPress: onAddExisting
            ))
        }
        if let onCreateFromImages = callbacks.onCreateFromImages {
            items.append(ActionMenuItem(
                id: "create-from-images",
                label: "Create from Images",
                icon: "photo.on.rectangle.angled",
                onPress: onCreateFromImages
            ))
        }

        return items
    }

    // MARK: Card Menu

    /// Menu for a transaction card in a list view.
    /// Legacy canonical inventory sales: no actions.
    /// New per-batch inventory movements: delete only (shape fields are immutable).
    static func buildCardMenu(
        transaction: Transaction,
        callbacks: SingleTransactionMenuCallbacks
    ) -> [ActionMenuItem] {
        guard transaction.isCanonicalInventorySale != true else { return [] }

        var items: [ActionMenuItem] = []
        if let onCopyID = callbacks.onCopyID {
            items.append(ActionMenuItem(
                id: "copy-id",
                label: "Copy ID",
                icon: "doc.on.clipboard",
                onPress: onCopyID
            ))
        }
        if let onDelete = callbacks.onDelete {
            items.append(ActionMenuItem(
                id: "delete",
                label: "Delete Transaction",
                icon: "trash",
                isDestructive: true,
                onPress: onDelete
            ))
        }
        return items
    }

    // MARK: Detail Menu

    /// Menu for the transaction detail toolbar.
    /// Legacy canonical sales: suppress Reassign, allow Delete.
    /// New per-batch inventory movements: suppress Reassign (shape is immutable), allow Delete.
    static func buildDetailMenu(
        transaction: Transaction,
        callbacks: SingleTransactionMenuCallbacks
    ) -> [ActionMenuItem] {
        let isCanonical = transaction.isCanonicalInventorySale == true
        let isFrozenInventoryMovement = transaction.isInventoryMovement && !isCanonical
        var items: [ActionMenuItem] = []

        if !isCanonical && !isFrozenInventoryMovement {
            var correctSubactions: [ActionMenuSubitem] = []
            if transaction.projectId != nil,
               let onReassignToInventory = callbacks.onReassignToInventory {
                correctSubactions.append(ActionMenuSubitem(
                    id: "reassign-to-inventory",
                    label: "Move to Inventory",
                    icon: "shippingbox",
                    onPress: onReassignToInventory
                ))
            }
            if let onReassignToProject = callbacks.onReassignToProject {
                correctSubactions.append(ActionMenuSubitem(
                    id: "reassign-to-project",
                    label: "Move to Project",
                    icon: "arrow.triangle.2.circlepath",
                    onPress: onReassignToProject
                ))
            }
            if !correctSubactions.isEmpty {
                items.append(ActionMenuItem(
                    id: "correct-move",
                    label: "Correct / Move",
                    icon: "arrow.triangle.2.circlepath",
                    subactions: correctSubactions,
                    isActionOnly: true
                ))
            }
        }

        if let onCopyID = callbacks.onCopyID {
            items.append(ActionMenuItem(
                id: "copy-id",
                label: "Copy ID",
                icon: "doc.on.clipboard",
                onPress: onCopyID
            ))
        }
        if let onDelete = callbacks.onDelete {
            items.append(ActionMenuItem(
                id: "delete",
                label: "Delete Transaction",
                icon: "trash",
                isDestructive: true,
                onPress: onDelete
            ))
        }
        return items
    }

    // MARK: Bulk Menu

    /// Menu for bulk-selected transactions.
    static func buildBulkMenu(
        callbacks: BulkTransactionMenuCallbacks
    ) -> [ActionMenuItem] {
        var items: [ActionMenuItem] = []
        if let onCopyIDs = callbacks.onCopyIDs {
            items.append(ActionMenuItem(
                id: "copy-ids",
                label: "Copy IDs",
                icon: "doc.on.clipboard",
                onPress: onCopyIDs
            ))
        }
        if let onDelete = callbacks.onDelete {
            items.append(ActionMenuItem(
                id: "delete",
                label: "Delete Transactions",
                icon: "trash",
                isDestructive: true,
                onPress: onDelete
            ))
        }
        return items
    }
}
