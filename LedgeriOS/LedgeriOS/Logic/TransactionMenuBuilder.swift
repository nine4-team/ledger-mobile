import Foundation

// MARK: - Types

/// Callbacks for single-transaction menu actions. All optional so callers only wire what they need.
struct SingleTransactionMenuCallbacks {
    // Reassign (detail context only)
    var onReassignToInventory: (() -> Void)?
    var onReassignToProject: (() -> Void)?
    // Delete
    var onDelete: (() -> Void)?
}

/// Callbacks for bulk transaction menu actions.
struct BulkTransactionMenuCallbacks {
    var onDelete: (() -> Void)?
}

// MARK: - Builder

enum TransactionMenuBuilder {

    // MARK: Card Menu

    /// Menu for a transaction card in a list view.
    /// Legacy canonical inventory sales: no actions.
    /// New per-batch Sales: delete only (shape fields are immutable).
    static func buildCardMenu(
        transaction: Transaction,
        callbacks: SingleTransactionMenuCallbacks
    ) -> [ActionMenuItem] {
        guard transaction.isCanonicalInventorySale != true else { return [] }

        var items: [ActionMenuItem] = []
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
    /// New per-batch Sales: suppress Reassign (shape is immutable), allow Delete.
    static func buildDetailMenu(
        transaction: Transaction,
        callbacks: SingleTransactionMenuCallbacks
    ) -> [ActionMenuItem] {
        let isCanonical = transaction.isCanonicalInventorySale == true
        let isPerBatchSale = transaction.transactionType == .sale && !isCanonical
        var items: [ActionMenuItem] = []

        if !isCanonical && !isPerBatchSale {
            var reassignSubactions: [ActionMenuSubitem] = []
            if let onReassignToInventory = callbacks.onReassignToInventory {
                reassignSubactions.append(ActionMenuSubitem(
                    id: "reassign-to-inventory",
                    label: "Reassign to Inventory",
                    icon: "shippingbox",
                    onPress: onReassignToInventory
                ))
            }
            if let onReassignToProject = callbacks.onReassignToProject {
                reassignSubactions.append(ActionMenuSubitem(
                    id: "reassign-to-project",
                    label: "Reassign to Project",
                    icon: "arrow.triangle.2.circlepath",
                    onPress: onReassignToProject
                ))
            }
            if !reassignSubactions.isEmpty {
                items.append(ActionMenuItem(
                    id: "reassign",
                    label: "Reassign",
                    icon: "arrow.triangle.2.circlepath",
                    subactions: reassignSubactions,
                    isActionOnly: true
                ))
            }
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
