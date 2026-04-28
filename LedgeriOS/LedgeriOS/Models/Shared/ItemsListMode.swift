import Foundation

enum ItemsListMode {
    case standalone(scope: ListScope)
    case embedded(items: [Item], onItemPress: (String) -> Void)
    case picker(
        scope: ListScope?,
        eligibilityCheck: ((Item) -> Bool)?,
        onAddSingle: ((Item) -> Void)?,
        addedIds: Set<String>,
        onAddSelected: (() -> Void)?,
        // Returns the name of the OTHER space an item lives in, if any.
        // nil means: not in any space, or in the picker's current space.
        // When non-nil, the row renders as a tap-to-stage-move candidate.
        otherSpaceNameForItem: ((Item) -> String?)?
    )
}
