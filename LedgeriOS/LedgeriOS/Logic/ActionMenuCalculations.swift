import Foundation

enum MenuActionResult: Equatable {
    case expand(String)
    case collapse
    case executeAction
}

enum ActionMenuCalculations {

    static func toggleExpansion(currentKey: String?, tappedKey: String) -> String? {
        currentKey == tappedKey ? nil : tappedKey
    }

    static func isSubactionSelected(item: ActionMenuItem, subactionKey: String) -> Bool {
        item.selectedSubactionKey == subactionKey
    }

    static func hasSubactions(_ item: ActionMenuItem) -> Bool {
        !(item.subactions ?? []).isEmpty
    }

    static func isDestructiveItem(_ item: ActionMenuItem) -> Bool {
        item.isDestructive
    }

    static func resolveMenuAction(item: ActionMenuItem, expandedKey: String?) -> MenuActionResult {
        if hasSubactions(item) {
            if expandedKey == item.id {
                return .collapse
            }
            return .expand(item.id)
        }
        return .executeAction
    }
}
