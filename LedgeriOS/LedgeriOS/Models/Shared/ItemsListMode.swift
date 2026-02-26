import Foundation

enum ItemsListMode {
    case standalone(scope: ListScope)
    case embedded(items: [Item], onItemPress: (String) -> Void)
    case picker(
        eligibilityCheck: ((Item) -> Bool)?,
        onAddSingle: ((Item) -> Void)?,
        addedIds: Set<String>,
        onAddSelected: (() -> Void)?
    )
}
