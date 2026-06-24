import Foundation

// MARK: - Types

/// Where the menu is being shown.
enum ItemMenuContext {
    case list        // Item card in a list view
    case detail      // Item detail toolbar menu
    case space       // Item within a SpaceDetailView
    case transaction // Item within TransactionDetailView
}

/// What scope the view is operating in.
enum ItemScope {
    case project
    case inventory
    case search // Cross-scope — shows all options
}

/// Callbacks for single-item menu actions. All optional so callers only wire what they need.
struct SingleItemMenuCallbacks {
    // Navigation
    var onOpen: (() -> Void)?
    var onSelect: (() -> Void)?
    // Status
    var onStatusChange: ((String) -> Void)?
    var onClearStatus: (() -> Void)?
    // Transaction
    var onSetTransaction: (() -> Void)?
    var onClearTransaction: (() -> Void)?
    var onMoveToReturnTransaction: (() -> Void)?
    // Space
    var onSetSpace: (() -> Void)?
    var onClearSpace: (() -> Void)?
    // Sell / Return — real business events (transactions created, budgets shift)
    var onReturnToInventory: (() -> Void)?
    var onSellToProject: (() -> Void)?
    // Correct / Move — within-scope correction (no transactions, no budget impact)
    var onReassignToProject: (() -> Void)?
    // Copies
    var onMakeCopies: (() -> Void)?
    // Copy ID
    var onCopyID: (() -> Void)?
    // Delete
    var onDelete: (() -> Void)?
}

/// Callbacks for bulk item menu actions.
struct BulkItemMenuCallbacks {
    var onStatusChange: ((String) -> Void)?
    var onSetTransaction: (() -> Void)?
    var onClearTransaction: (() -> Void)?
    var onMoveToReturnTransaction: (() -> Void)?
    var onSetSpace: (() -> Void)?
    var onClearSpace: (() -> Void)?
    var onReturnToInventory: (() -> Void)?
    var onSellToProject: (() -> Void)?
    var onReassignToProject: (() -> Void)?
    var onCopyIDs: (() -> Void)?
    var onDelete: (() -> Void)?
}

// MARK: - Item Statuses

/// User-settable item statuses (excludes `.sold` — system-set only).
private let itemStatuses: [ItemStatus] = [
    .toPurchase, .purchased, .toReturn, .returned,
]

// MARK: - Builder

enum ItemMenuBuilder {

    // MARK: Single-Item Menu

    static func buildSingleItemMenu(
        context: ItemMenuContext,
        scope: ItemScope,
        callbacks: SingleItemMenuCallbacks,
        currentStatus: String? = nil
    ) -> [ActionMenuItem] {
        var items: [ActionMenuItem] = []

        // --- First items: Open/Select ---
        switch context {
        case .list:
            if let onOpen = callbacks.onOpen {
                items.append(ActionMenuItem(id: "open", label: "Open", icon: "arrow.up.right.square", onPress: onOpen))
            }
            if let onSelect = callbacks.onSelect {
                items.append(ActionMenuItem(id: "select", label: "Select", icon: "checkmark.circle", onPress: onSelect))
            }
        case .space:
            if let onOpen = callbacks.onOpen {
                items.append(ActionMenuItem(id: "open", label: "Open", icon: "arrow.up.right.square", onPress: onOpen))
            }
        case .transaction:
            if let onOpen = callbacks.onOpen {
                items.append(ActionMenuItem(id: "open", label: "Open Item", icon: "arrow.up.right.square", onPress: onOpen))
            }
            if let onMakeCopies = callbacks.onMakeCopies {
                items.append(ActionMenuItem(id: "make-copies", label: "Make Copies", icon: "doc.on.doc", onPress: onMakeCopies))
            }
        case .detail:
            if let onMakeCopies = callbacks.onMakeCopies {
                items.append(ActionMenuItem(id: "make-copies", label: "Make Copies", icon: "doc.on.doc", onPress: onMakeCopies))
            }
        }

        // --- Status submenu ---
        // Detail context has a dedicated toolbar status capsule, so the
        // submenu is suppressed there to avoid duplicating the affordance.
        if context != .detail {
            var statusSubactions: [ActionMenuSubitem] = itemStatuses.map { status in
                ActionMenuSubitem(id: status.rawValue, label: status.displayLabel, onPress: {
                    callbacks.onStatusChange?(status.rawValue)
                })
            }
            if context == .transaction {
                if let onClearStatus = callbacks.onClearStatus {
                    statusSubactions.append(ActionMenuSubitem(id: "clear-status", label: "Clear Status", onPress: onClearStatus))
                }
            }
            items.append(ActionMenuItem(
                id: "status", label: "Status", icon: "flag",
                subactions: statusSubactions,
                selectedSubactionKey: currentStatus,
                isActionOnly: true
            ))
        }

        // --- Transaction submenu ---
        if context == .transaction {
            // In transaction context, item is already linked — only offer clear/move
            var txnSubactions: [ActionMenuSubitem] = []
            if let onClear = callbacks.onClearTransaction {
                txnSubactions.append(ActionMenuSubitem(id: "clear-transaction", label: "Clear Transaction", icon: "link.badge.plus", onPress: onClear))
            }
            if let onMove = callbacks.onMoveToReturnTransaction {
                txnSubactions.append(ActionMenuSubitem(id: "move-return-tx", label: "Move to Return Transaction", icon: "arrow.uturn.left", onPress: onMove))
            }
            if !txnSubactions.isEmpty {
                items.append(ActionMenuItem(
                    id: "transaction", label: "Transaction", icon: "arrow.left.arrow.right",
                    subactions: txnSubactions,
                    isActionOnly: true
                ))
            }
        } else {
            var txnSubactions: [ActionMenuSubitem] = []
            if let onSet = callbacks.onSetTransaction {
                txnSubactions.append(ActionMenuSubitem(id: "set-transaction", label: "Set Transaction", icon: "link", onPress: onSet))
            }
            if let onClear = callbacks.onClearTransaction {
                txnSubactions.append(ActionMenuSubitem(id: "clear-transaction", label: "Clear Transaction", icon: "link.badge.plus", onPress: onClear))
            }
            if let onMove = callbacks.onMoveToReturnTransaction {
                txnSubactions.append(ActionMenuSubitem(id: "move-return-tx", label: "Move to Return Transaction", icon: "arrow.uturn.left", onPress: onMove))
            }
            if !txnSubactions.isEmpty {
                items.append(ActionMenuItem(
                    id: "transaction", label: "Transaction", icon: "arrow.left.arrow.right",
                    subactions: txnSubactions,
                    isActionOnly: true
                ))
            }
        }

        // --- Space picker ---
        // The picker includes "No Space", so the menu can jump straight there.
        if let onSet = callbacks.onSetSpace {
            items.append(ActionMenuItem(
                id: "space",
                label: "Space",
                icon: "mappin.and.ellipse",
                onPress: onSet
            ))
        }

        // --- Sell / Return — top-level, no parent grouping ---
        // These are real business events. They are intentionally NOT grouped
        // under a "Move / Sell" parent because doing so conflates them with
        // Correct / Move (a within-scope correction with no financial impact).
        // See docs/specs/reassign-vs-sell.md §Design Decision.
        if scope == .project || scope == .search {
            if let onReturnToInventory = callbacks.onReturnToInventory {
                items.append(ActionMenuItem(
                    id: "return-to-inventory",
                    label: "Return to Inventory",
                    icon: "shippingbox",
                    onPress: onReturnToInventory
                ))
            }
        }
        if let onSellToProject = callbacks.onSellToProject {
            items.append(ActionMenuItem(
                id: "sell",
                label: "Sell",
                icon: "arrow.right.square",
                onPress: onSellToProject
            ))
        }

        // --- Correct / Move — within-scope correction, no money moves ---
        // The label combines intent ("Correct") with mechanic ("Move") so users
        // don't confuse this with Sell. Reassigns an item between transactions
        // within the same scope. See docs/specs/reassign-vs-sell.md.
        if let onReassignToProject = callbacks.onReassignToProject {
            items.append(ActionMenuItem(
                id: "correct-move",
                label: "Correct / Move",
                icon: "arrow.triangle.2.circlepath",
                onPress: onReassignToProject
            ))
        }

        // --- Copy ID ---
        if let onCopyID = callbacks.onCopyID {
            items.append(ActionMenuItem(id: "copy-id", label: "Copy ID", icon: "doc.on.clipboard", onPress: onCopyID))
        }

        // --- Delete (always last) ---
        if let onDelete = callbacks.onDelete {
            items.append(ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true, onPress: onDelete))
        }

        return items
    }

    // MARK: Bulk Menu

    static func buildBulkMenu(
        context: ItemMenuContext = .list,
        scope: ItemScope,
        callbacks: BulkItemMenuCallbacks
    ) -> [ActionMenuItem] {
        var items: [ActionMenuItem] = []

        // Status submenu
        if let onStatusChange = callbacks.onStatusChange {
            items.append(ActionMenuItem(
                id: "status", label: "Change Status", icon: "flag",
                subactions: itemStatuses.map { status in
                    ActionMenuSubitem(id: status.rawValue, label: status.displayLabel, onPress: {
                        onStatusChange(status.rawValue)
                    })
                },
                isActionOnly: true
            ))
        }

        // Transaction submenu
        var txnSubactions: [ActionMenuSubitem] = []
        if let onSet = callbacks.onSetTransaction {
            txnSubactions.append(ActionMenuSubitem(id: "set-transaction", label: "Set Transaction", icon: "link", onPress: onSet))
        }
        if let onClear = callbacks.onClearTransaction {
            txnSubactions.append(ActionMenuSubitem(id: "clear-transaction", label: "Clear Transaction", icon: "link.badge.plus", onPress: onClear))
        }
        if let onMove = callbacks.onMoveToReturnTransaction {
            txnSubactions.append(ActionMenuSubitem(id: "move-return-tx", label: "Move to Return Transaction", icon: "arrow.uturn.left", onPress: onMove))
        }
        if !txnSubactions.isEmpty {
            items.append(ActionMenuItem(
                id: "transaction", label: "Transaction", icon: "arrow.left.arrow.right",
                subactions: txnSubactions,
                isActionOnly: true
            ))
        }

        // Space picker
        if let onSet = callbacks.onSetSpace {
            items.append(ActionMenuItem(
                id: "space",
                label: "Space",
                icon: "mappin.and.ellipse",
                onPress: onSet
            ))
        }

        // Sell / Return — top-level, scope-dependent. See single-item builder
        // for rationale (no "Move / Sell" parent grouping).
        if scope == .project || scope == .search {
            if let onReturnToInventory = callbacks.onReturnToInventory {
                items.append(ActionMenuItem(
                    id: "return-to-inventory",
                    label: "Return to Inventory",
                    icon: "shippingbox",
                    onPress: onReturnToInventory
                ))
            }
        }
        if let onSellToProject = callbacks.onSellToProject {
            items.append(ActionMenuItem(
                id: "sell",
                label: "Sell",
                icon: "arrow.right.square",
                onPress: onSellToProject
            ))
        }

        // Correct / Move — within-scope correction.
        if let onReassignToProject = callbacks.onReassignToProject {
            items.append(ActionMenuItem(
                id: "correct-move",
                label: "Correct / Move",
                icon: "arrow.triangle.2.circlepath",
                onPress: onReassignToProject
            ))
        }

        // Copy IDs
        if let onCopyIDs = callbacks.onCopyIDs {
            items.append(ActionMenuItem(id: "copy-ids", label: "Copy IDs", icon: "doc.on.clipboard", onPress: onCopyIDs))
        }

        // Delete (always last)
        if let onDelete = callbacks.onDelete {
            items.append(ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true, onPress: onDelete))
        }

        return items
    }
}
