# Fix Transaction Card Badges, Selector, Kebab Menu, and Card Styling

## Context

Transaction cards in the SwiftUI app don't match the React Native reference. Badges show types that shouldn't be visible (sale, to-inventory, reimbursement), badge order is wrong, opacity values don't match RN, cards are missing the selector circle and kebab menu, and the base Card component uses the wrong border color and lacks shadows compared to the RN app.

## Badge Requirements (Revised)

**Keep these badges only:**
- **Transaction type** (purchase/return) — styled with subtle opacity like category, NOT bright green/red
- **Needs review** — always leftmost
- **Category** (e.g. "Furnishings") — subtle brand primary

**Remove these badges:**
- Sale
- To-inventory
- Reimbursement (owed-to-client, owed-to-company)

**Badge order:** Needs Review → Transaction Type → Category

**Badge sizing:** Decrease to fit selector + kebab in header row.

## Changes

### 1. Update `Badge` component — add opacity params + reduce size

**File:** `LedgeriOS/LedgeriOS/Components/Badge.swift`

- Add `backgroundOpacity` (default 0.10) and `borderOpacity` (default 0.20) parameters
- Reduce padding from `(.horizontal, 10) / (.vertical, 4)` to `(.horizontal, 8) / (.vertical, 3)`
- Use a smaller font (~11pt) instead of `Typography.caption` (12pt)

### 2. Update badge logic — remove badges, fix order, fix opacity

**File:** `LedgeriOS/LedgeriOS/Logic/TransactionCardCalculations.swift`

- Add `backgroundOpacity` and `borderOpacity` to `BadgeItem` struct
- **Remove** sale, to-inventory, reimbursement cases
- **Keep** purchase and return but style with subtle opacity (0.10 bg / 0.20 border)
- **Reorder** to: needs review first, then type, then category

| Badge | Color | Bg Opacity | Border Opacity |
|-------|-------|-----------|----------------|
| Needs Review | `StatusColors.badgeNeedsReview` (#b94520) | 0.08 | 0.20 |
| Purchase | `StatusColors.badgeSuccess` (#059669) | 0.10 | 0.20 |
| Return | `StatusColors.badgeError` (#dc2626) | 0.10 | 0.20 |
| Category | `BrandColors.primary` (#987e55) | 0.10 | 0.20 |

### 3. Pass opacity through in `TransactionCard`

**File:** `LedgeriOS/LedgeriOS/Components/TransactionCard.swift`

Update `badgeRow` to pass `badge.backgroundOpacity` and `badge.borderOpacity` to `Badge()`.

### 4. Wire selector and kebab in `TransactionsTabView`

**File:** `LedgeriOS/LedgeriOS/Views/Projects/TransactionsTabView.swift`

Follow the `ItemsTabView` pattern (lines 252-291):
- Pass `isSelected` binding to every card using the existing `selectedIds` set
- Pass `menuItems` only when `selectedIds.isEmpty` (hide kebab during bulk select)
- When bulk selecting (`!selectedIds.isEmpty`), use `.onTapGesture` instead of `NavigationLink`
- Add `toggleSelection()` helper and `singleTransactionMenuItems()` builder
- Menu items: `[ActionMenuItem(id: "select", label: "Select", icon: "checkmark.circle")]`

### 5. Wire selector and kebab in `InventoryTransactionsSubTab`

**File:** `LedgeriOS/LedgeriOS/Views/Inventory/InventoryTransactionsSubTab.swift`

Same pattern as step 4. Already has `NavigationLink` vs `onTapGesture` switching (lines 153-161) and `toggleSelection()` (line 192). Just wire `isSelected` binding and `menuItems` into `transactionCardContent()`.

### 6. Fix Card component — border color + shadow

**File:** `LedgeriOS/LedgeriOS/Components/Card.swift`

Current issues vs RN reference:
- Border uses `BrandColors.border` (#C7CBD4 light) — RN uses secondary border (#E5E7EB, lighter)
- No shadow — RN uses `shadowOpacity: 0.05, shadowRadius: 6`

Changes to both `Card` and `CardStyle`:
- Change `.stroke(BrandColors.border, ...)` → `.stroke(BrandColors.borderSecondary, ...)`
- Add `.shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)`

### 7. Fix TransactionCard header divider

**File:** `LedgeriOS/LedgeriOS/Components/TransactionCard.swift` (line 173)

Change `Divider().foregroundStyle(BrandColors.border)` to a manual rectangle with the lighter secondary border:
```swift
Rectangle()
    .fill(BrandColors.borderSecondary)
    .frame(height: 1)
```

### 8. Update `TransactionDisplayCalculations` for detail view

**File:** `LedgeriOS/LedgeriOS/Logic/TransactionDisplayCalculations.swift`

- Add `backgroundOpacity`/`borderOpacity` to `BadgeConfig`
- Remove sale, to-inventory, reimbursement badge cases
- Keep purchase/return with subtle opacity
- Reorder to match: needs review → type → category

**File:** `LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift` (line 216)

Pass opacity from `BadgeConfig` through to `Badge()`.

### 9. Update tests

**File:** `LedgeriOS/LedgeriOSTests/TransactionCardCalculationTests.swift`

- **Remove** tests for sale, to-inventory, reimbursement badges
- **Rewrite** purchase/return tests to assert subtle opacity (0.10/0.20)
- **Update** multi-badge tests for new set (needs review + type + category only)
- **Update** order tests: needs review is first, then type, then category
- **Add** opacity value assertions

## Files Changed

| File | What |
|------|------|
| `Components/Badge.swift` | Add opacity params, reduce padding/font size |
| `Logic/TransactionCardCalculations.swift` | Remove badges, reorder, add opacity to BadgeItem |
| `Components/TransactionCard.swift` | Pass opacity to Badge, fix header divider color |
| `Components/Card.swift` | Use borderSecondary, add shadow |
| `Views/Projects/TransactionsTabView.swift` | Wire isSelected + menuItems |
| `Views/Inventory/InventoryTransactionsSubTab.swift` | Wire isSelected + menuItems |
| `Logic/TransactionDisplayCalculations.swift` | Mirror badge changes for detail view |
| `Views/Projects/TransactionDetailView.swift` | Pass opacity to Badge |
| `LedgeriOSTests/TransactionCardCalculationTests.swift` | Update/rewrite badge tests |

## Verification

1. **Build:** `cd LedgeriOS && xcodebuild build -scheme "LedgeriOS (Emulator)" -destination 'platform=iOS Simulator,name=iPhone 16e' -derivedDataPath DerivedData -quiet 2>&1 | tail -5`
2. **Tests:** `cd LedgeriOS && xcodebuild test -scheme "LedgeriOS (Emulator)" -destination 'platform=iOS Simulator,name=iPhone 16e' -derivedDataPath DerivedData -quiet 2>&1 | tail -20`
3. **Visual:** Launch with `npm run dev:native`, navigate to project Transactions tab:
   - No sale, to-inventory, or reimbursement badges
   - Purchase/return badges use subtle opacity (not bright)
   - Needs review badge is always leftmost
   - Category badge is subtle brand primary
   - Badges are smaller, fitting alongside selector + kebab
   - Selector circle visible on every card
   - Kebab menu visible when not in bulk select
   - Card borders are subtle (lighter secondary color)
   - Cards have slight shadow for depth
   - Header divider is subtle secondary border color
