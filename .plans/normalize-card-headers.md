# Normalize Card Headers + SwiftUI-Native Card Architecture

## Context

Card components have two problems:
1. **Visual drift** — kebab menus, bookmarks, and selectors look different across TransactionCard, ItemCard, SpaceCard
2. **React-like architecture** — TransactionCard takes 16 params, ItemCard takes 17, each unpacked from models that every callsite already has. Header layout and menu sheet state are duplicated.

SpaceCard is already the most SwiftUI-native card — it takes `Space` model directly. TransactionCard and ItemCard should follow that pattern.

## Changes

### 1. Shared button components — `Components/CardActionButtons.swift` (new)

Three small views matching TransactionCard's styling:

- **`CardKebabButton(action:)`** — vertical ellipsis (rotated 90°), 18pt, `BrandColors.textSecondary`, `.padding(6)`, `.contentShape(Rectangle())`, a11y label
- **`CardBookmarkButton(isBookmarked:, action:)`** — 18pt bookmark, `StatusColors.badgeError` when filled, `.padding(6)`, a11y label
- **`CardSelectorButton(isSelected:, label:, action:)`** — wraps `SelectorCircle(indicator: .dot)` with Button, `.contentShape(Rectangle())`, a11y label

### 2. Shared header — `Components/CardHeader.swift` (new)

Owns the full header row layout + menu sheet state. Follows TransactionCard's pattern:

```
[Selector?] [Badges (centered)] [Warning?] [Bookmark?] [Kebab?]
```

API:
```swift
struct CardHeader: View {
    // Selection
    var isSelected: Binding<Bool>?
    var selectionLabel: String = ""

    // Badges
    var badges: [CardBadge] = []

    // Actions
    var bookmarked: Bool = false
    var onBookmarkPress: (() -> Void)?
    var warningMessage: String?
    var menuTitle: String = ""
    var menuItems: [ActionMenuItem] = []
}
```

Owns internally: `@State showMenu`, `@State menuPendingAction`, `.sheet()` + `ActionMenuSheet`.

Padding: `.horizontal(Spacing.sm)`, `.vertical(Spacing.sm)`. `CardDivider()` at bottom.

### 3. Badge data type — `CardBadge` struct

```swift
struct CardBadge {
    let text: String
    let color: Color
    var backgroundOpacity: Double = 0.10
    var borderOpacity: Double = 0.20
}
```

Replace `TransactionCardCalculations.BadgeItem` and `ItemCardCalculations.BadgeItem` with this shared type. Both calculation functions return `[CardBadge]`.

### 4. TransactionCard — take model, use CardHeader

**Before (16 params, unpacked at every callsite):**
```swift
TransactionCard(
    id: txId,
    source: transaction.source ?? "",
    amountCents: transaction.amountCents,
    transactionDate: transaction.transactionDate,
    notes: transaction.notes,
    budgetCategoryName: catName,
    transactionType: transaction.transactionType,
    needsReview: transaction.needsReview ?? false,
    reimbursementType: transaction.reimbursementType,
    hasEmailReceipt: transaction.hasEmailReceipt ?? false,
    status: transaction.status,
    itemCount: transaction.itemIds?.count,
    isSelected: binding,
    menuItems: items
)
```

**After (model + derived data only):**
```swift
TransactionCard(
    transaction: transaction,
    budgetCategoryName: catName,    // external lookup
    isSelected: binding,
    menuItems: items
)
```

The card reads `source`, `amountCents`, `transactionDate`, `notes`, `transactionType`, `needsReview`, `reimbursementType`, `hasEmailReceipt`, `status`, `itemIds` directly from the model. `budgetCategoryName` stays a param because it requires a cross-collection lookup the card can't do.

Internally uses `CardHeader` instead of custom `headerRow`/`headerActions` computed properties. Removes `@State showMenu`/`menuPendingAction` and `.sheet()` — CardHeader owns those.

### 5. ItemCard — take model, use CardHeader

**Before (17 params):**
```swift
ItemCard(
    name: item.displayName,
    sku: item.sku,
    sourceLabel: item.source,
    priceLabel: displayPrice(for: item),
    statusLabel: item.status,
    budgetCategoryName: categoryName(for: item.budgetCategoryId),
    thumbnailUri: item.images?.first?.url,
    isSelected: binding,
    bookmarked: item.bookmark == true,
    menuItems: items
)
```

**After (model + derived data):**
```swift
ItemCard(
    item: item,
    priceLabel: displayPrice(for: item),      // external formatting
    budgetCategoryName: categoryName(for: item),  // external lookup
    isSelected: binding,
    menuItems: items
)
```

The card reads `displayName`, `sku`, `source`, `status`, `images`, `bookmark` from the model. `priceLabel` stays a param because the format varies by context (purchase vs project price). `budgetCategoryName` stays a param for the same cross-collection reason.

For detail views that override status:
```swift
ItemCard(item: item, statusOverride: "Returned")
```

### 6. Drop internal selection fallback

Currently both cards have `isSelected: Binding<Bool>?` + `@State private var internalSelected` + `defaultSelected: Bool`. The internal fallback means the card can show selection UI that the parent can't observe — this is never useful.

**Change:** `isSelected` remains `Binding<Bool>?`. When nil, no selector shows. When provided, parent owns the state. Remove `@State internalSelected` and `defaultSelected` entirely.

All existing callsites already provide proper bindings or don't use selection at all — no callsite relies on the internal fallback.

### 7. SpaceCard — kebab button only

SpaceCard already takes its model. Just replace the inline kebab with `CardKebabButton`. No CardHeader needed — SpaceCard's layout is fundamentally different (content inside `ImageCard`, no separate header row).

### 8. GroupedItemCard — selector normalization

Replace `.onTapGesture` on bare `SelectorCircle` with `CardSelectorButton` for VoiceOver support.

### 9. Update CLAUDE.md — shared components table

Add `CardHeader`, `CardKebabButton`, `CardBookmarkButton`, `CardSelectorButton`, `CardBadge`.

## Files Modified

| File | Change |
|------|--------|
| `Components/CardActionButtons.swift` | **New** — 3 button components |
| `Components/CardHeader.swift` | **New** — shared header + menu sheet |
| `Components/CardBadge.swift` | **New** — shared badge data type |
| `Components/TransactionCard.swift` | Take `Transaction` model, use `CardHeader` |
| `Components/ItemCard.swift` | Take `Item` model, use `CardHeader` |
| `Components/SpaceCard.swift` | Use `CardKebabButton` |
| `Components/GroupedItemCard.swift` | Use `CardSelectorButton` |
| `Calculations/TransactionCardCalculations.swift` | Return `[CardBadge]` |
| `Calculations/ItemCardCalculations.swift` | Return `[CardBadge]` |
| `Views/Inventory/InventoryTransactionsSubTab.swift` | Simplify TransactionCard callsite |
| `Views/Inventory/InventoryItemsSubTab.swift` | Simplify ItemCard callsites |
| `Views/Projects/TransactionsTabView.swift` | Simplify TransactionCard callsite |
| `Views/Projects/ItemsTabView.swift` | Simplify ItemCard callsites |
| `Views/Search/UniversalSearchView.swift` | Simplify both card callsites |
| `Views/TransactionDetailView.swift` | Simplify ItemCard callsites |
| `Views/SpaceDetailView.swift` | Simplify ItemCard callsite |
| `CLAUDE.md` | Add shared components |

## What this eliminates

- Duplicated header layout and menu sheet state across cards
- 10+ redundant params per card (read from model instead)
- Internal selection fallback state (parent always owns it)
- Visual drift in buttons (shared components)
- Missing accessibility labels
- `ItemCardData` intermediary in GroupedItemCard (future — can take `[Item]` directly)

## Verification

1. **Build:** `cd LedgeriOS && xcodebuild build -scheme "LedgeriOS (Emulator)" -destination 'platform=iOS Simulator,name=iPhone 16e' -derivedDataPath DerivedData -quiet 2>&1 | tail -5`
2. **Visual:** All card headers should look identical — vertical kebab, centered badges, same padding/colors
3. **Functional:** Menu sheets present/dismiss correctly, selection toggles work, bookmarks toggle, navigation still works
4. **Callsites:** Verify simplified API at each of the 14 callsites across views
