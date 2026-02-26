# Data Model: SwiftUI Component Library

This feature creates UI components — not data entities. The "data model" here describes the **component interfaces** (Swift structs/enums that components accept as configuration).

## New Types

### ActionMenuItem

Used by: `ActionMenuSheet`, `FilterMenu`, `SortMenu`, `ItemCard`, `TransactionCard`, `MediaGallerySection`, `SharedItemsList`, `SharedTransactionsList`

```swift
struct ActionMenuItem: Identifiable {
    let id: String                          // unique key
    let label: String                       // display text
    var icon: String?                       // SF Symbol name (optional)
    var subactions: [ActionMenuSubitem]?    // child items (optional)
    var selectedSubactionKey: String?       // currently selected child key
    var isDestructive: Bool = false         // red styling
    var isActionOnly: Bool = false          // execute immediately, no subactions
    var onPress: (() -> Void)?             // action handler
}

struct ActionMenuSubitem: Identifiable {
    let id: String                          // unique key
    let label: String
    var icon: String?                       // SF Symbol name
    var onPress: () -> Void
}
```

### ControlAction

Used by: `ListControlBar`, `ItemsListControlBar`

```swift
struct ControlAction: Identifiable {
    let id: String
    let title: String
    var variant: AppButtonVariant = .secondary
    var icon: String?                       // SF Symbol name
    var isDisabled: Bool = false
    var isActive: Bool = false
    var appearance: ControlActionAppearance = .standard
    var accessibilityLabel: String?
    var action: () -> Void
}

enum ControlActionAppearance {
    case standard       // text + optional icon button
    case iconOnly       // fixed-size icon button
    case tile           // dashed-border icon square
}
```

### FormSheetAction

Used by: `FormSheet`, `MultiStepFormSheet`

```swift
struct FormSheetAction {
    let title: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var action: () -> Void
}
```

### ItemsListMode

Used by: `SharedItemsList`

```swift
enum ItemsListMode {
    case standalone(scopeConfig: ScopeConfig)
    case embedded(items: [ScopedItem], onItemPress: (String) -> Void)
    case picker(
        eligibilityCheck: ((ScopedItem) -> Bool)?,
        onAddSingle: ((ScopedItem) -> Void)?,
        addedIds: Set<String>,
        onAddSelected: (() -> Void)?
    )
}
```

### StatusBannerVariant

Used by: `StatusBanner`

```swift
enum StatusBannerVariant {
    case error
    case warning
    case info
}
```

### ItemFilterOption / ItemSortOption

Used by: `SharedItemsList`, `FilterMenu`, `SortMenu`

```swift
enum ItemFilterOption: String, CaseIterable {
    case all
    case bookmarked
    case fromInventory = "from-inventory"
    case toReturn = "to-return"
    case returned
    case noSku = "no-sku"
    case noName = "no-name"
    case noProjectPrice = "no-project-price"
    case noImage = "no-image"
    case noTransaction = "no-transaction"
}

enum ItemSortOption: String, CaseIterable {
    case createdDesc = "created-desc"
    case createdAsc = "created-asc"
    case alphabeticalAsc = "alphabetical-asc"
    case alphabeticalDesc = "alphabetical-desc"
}
```

## Existing Types Referenced (no changes)

These types are already defined in the data layer and used as-is by components:

| Type | File | Used by Components |
|------|------|-------------------|
| `Project` | `Models/Project.swift` | SharedItemsList (standalone mode) |
| `Transaction` | `Models/Transaction.swift` | TransactionCard, SharedTransactionsList |
| `Item` / `ScopedItem` | `Models/Item.swift` | ItemCard, GroupedItemCard, SharedItemsList |
| `Space` | `Models/Space.swift` | SpaceCard |
| `BudgetCategory` | `Models/BudgetCategory.swift` | BudgetCategoryTracker, CategoryRow |
| `AttachmentRef` | `Models/AttachmentRef.swift` | MediaGallerySection, ThumbnailGrid, ImageGallery |

## Potential New StatusColors

Transaction badge types may require new color entries in `StatusColors.swift`:

```swift
// Verify these don't already exist before adding
static let transactionPurchase: Color    // green
static let transactionSale: Color        // blue
static let transactionReturn: Color      // red
static let transactionToInventory: Color // brand primary
static let reimbursement: Color          // amber
static let needsReview: Color            // orange
static let emailReceipt: Color           // amber
```

Check existing `StatusColors.swift` during WP3 implementation. If badge colors already exist (e.g., via the existing `Badge` component), reuse them.
