# Phase 4: Transactions Tab + Transaction Detail

## Context

Phase 4 Session 2 of the SwiftUI migration. The data layer, navigation shell, and Phase 5a shared components are complete. Phase 4 Session 1 (Projects List + Project Detail Hub + Budget Tab) established patterns: pure logic modules, reusable components, screen views reading from `ProjectContext`, and `CollapsibleSection` for detail screens.

This plan covers: the Transactions tab content within the Project Detail Hub, the Transaction Detail screen, and all supporting logic and components.

**RN source reference:** All business logic is ported from the React Native implementation — field orders, conditional rendering rules, badge colors, completeness calculations, and section structure are taken directly from the existing codebase in `src/`.

## Scope

**Build:** TransactionsTabView (list within project hub), TransactionDetailView (full detail screen), TransactionCard component, supporting logic + tests
**Defer:** Transaction creation/editing flows, bulk selection actions, filter/sort sheets (toolbar pills render but tap actions are stubs), image upload/delete, edit modals, item linking

## Reference

- **Screenshots:** `reference/screenshots/dark/05_project_detail_transactions.png`, `07_transaction_detail.png`, `08_transaction_detail_scrolled.png`
- **RN transaction detail:** `src/app/transactions/[id]/index.tsx` + `src/app/transactions/[id]/sections/*.tsx`
- **RN transaction list:** `src/components/SharedTransactionsList.tsx`
- **RN transaction card:** `src/components/TransactionCard.tsx`
- **RN completeness:** `src/utils/transactionCompleteness.ts`
- **RN display name:** `src/utils/transactionDisplayName.ts`
- **RN edit details:** `src/components/modals/EditTransactionDetailsModal.tsx`

## Implementation Order

```
1. Pure logic + tests (no UI dependencies)
2. New components: TransactionCard, ProgressRing, ListToolbar
3. Screens: TransactionsTabView, TransactionDetailView
4. Navigation wiring: ProjectDetailView.swift
5. Build + test verification
```

---

## Step 1: Pure Logic + Tests

### New file: `LedgeriOS/LedgeriOS/Logic/TransactionDisplayCalculations.swift`

`enum TransactionDisplayCalculations` with static functions:

#### `displayName(source:id:isCanonicalInventorySale:inventorySaleDirection:)` → `String`

Ported from `src/utils/transactionDisplayName.ts`:
1. If `source?.trimmingCharacters(in: .whitespaces)` is non-empty → return trimmed source
2. If `isCanonicalInventorySale == true`:
   - `.projectToBusiness` → `"Sale to Inventory"`
   - `.businessToProject` → `"Purchase from Inventory"`
   - else → `"Inventory Transfer"`
3. If `id` is non-nil and non-empty → `"Transaction \(String(id.prefix(6)))"`
4. Fallback → `"Untitled Transaction"`

#### `formattedAmount(amountCents:)` → `String`

Ported from RN `formatMoney()`:
- `nil` → `"$0.00"`
- Otherwise → `"$\(Double(cents) / 100.0)" with 2 decimal places` (use `String(format: "$%.2f", Double(cents) / 100.0)`)

#### `formattedDate(transactionDate:)` → `String`

Ported from RN `formatDate()` with short month, numeric day, numeric year:
- Parse ISO `"2026-02-03"` → `DateFormatter` with `"MMM d, yyyy"` → `"Feb 3, 2026"`
- `nil` or empty or unparseable → `"No date"`

#### `itemCountLabel(count:)` → `String`

Ported from RN TransactionCard item count display:
- `0` → `"0 items"`, `1` → `"1 item"`, `n` → `"\(n) items"`

#### `struct BadgeConfig: Identifiable { let id: String; let text: String; let color: Color }`

#### `badgeConfigs(transactionType:reimbursementType:hasEmailReceipt:needsReview:budgetCategoryName:)` → `[BadgeConfig]`

Ported from `src/components/TransactionCard.tsx` badge rendering. Exact order:
1. **Transaction type** (if non-nil):
   - `"purchase"` → `BadgeConfig(text: "Purchase", color: StatusColors.badgeSuccess)`
   - `"sale"` → `BadgeConfig(text: "Sale", color: StatusColors.badgeInfo)`
   - `"return"` → `BadgeConfig(text: "Return", color: StatusColors.badgeError)`
   - `"to-inventory"` → `BadgeConfig(text: "To Inventory", color: BrandColors.primary)`
2. **Reimbursement type** (if non-nil):
   - `"owed-to-client"` → `BadgeConfig(text: "Owed to Client", color: StatusColors.badgeWarning)`
   - `"owed-to-company"` → `BadgeConfig(text: "Owed to Business", color: StatusColors.badgeWarning)`
3. **Email receipt** (if `hasEmailReceipt == true`):
   - `BadgeConfig(text: "Receipt", color: BrandColors.primary)`
4. **Needs review** (if `needsReview == true`):
   - `BadgeConfig(text: "Needs Review", color: StatusColors.badgeNeedsReview)`
5. **Budget category** (if `budgetCategoryName` is non-nil and non-empty):
   - `BadgeConfig(text: budgetCategoryName, color: BrandColors.primary)`

#### `formattedPercent(taxRatePct:)` → `String`

- `nil` → `"—"`
- Otherwise → `String(format: "%.2f%%", value)` e.g. `"8.25%"`

#### `formattedTaxAmount(amountCents:subtotalCents:)` → `String`

Ported from RN DetailsSection tax amount computation:
- If both non-nil → `formattedAmount(amountCents: amountCents - subtotalCents)`
- Otherwise → `"—"`

### New file: `LedgeriOS/LedgeriOS/Logic/TransactionNextStepsCalculations.swift`

`enum TransactionNextStepsCalculations` with static functions.

Ported from `src/app/transactions/[id]/sections/NextStepsSection.tsx` `computeNextSteps()`:

#### `struct NextStep: Identifiable { let id: String; let label: String; let isComplete: Bool; let systemImage: String }`

#### `computeSteps(transaction:itemCount:budgetCategoryExists:isItemizedCategory:)` → `[NextStep]`

Returns 5 or 6 steps in this **exact order** (from RN):
1. `"Categorize this transaction"` — complete if `transaction.budgetCategoryId` is non-nil, non-empty, AND `budgetCategoryExists == true` (icon: `"tag"`)
2. `"Enter the amount"` — complete if `transaction.amountCents` is non-nil AND `> 0` (icon: `"dollarsign.circle"`)
3. `"Add a receipt"` — complete if `(transaction.receiptImages?.count ?? 0) > 0` (icon: `"doc.text"`)
4. `"Add items"` — complete if `itemCount > 0` (icon: `"doc.on.clipboard"`)
5. `"Set purchased by"` — complete if `transaction.purchasedBy?.trimmingCharacters(in: .whitespaces)` is non-empty (icon: `"person"`)
6. **CONDITIONAL** `"Set tax rate"` — only included if `isItemizedCategory == true`. Complete if `transaction.taxRatePct` is non-nil AND `> 0` (icon: `"percent"`)

**Key detail from RN:** Step 6 (tax rate) is only added to the steps array when the transaction's budget category has `metadata.categoryType == "itemized"`. This means the total step count is 5 or 6 depending on the category.

#### `completedCount(steps:)` → `Int`

`steps.filter(\.isComplete).count`

#### `completionFraction(steps:)` → `Double`

`steps.isEmpty ? 1.0 : Double(completedCount(steps: steps)) / Double(steps.count)`

#### `allComplete(steps:)` → `Bool`

`completedCount(steps: steps) == steps.count`

**RN behavior:** The Next Steps section is **hidden entirely** when `allComplete` returns true.

### New file: `LedgeriOS/LedgeriOS/Logic/TransactionCompletenessCalculations.swift`

`enum TransactionCompletenessCalculations` — Ported from `src/utils/transactionCompleteness.ts`.

This powers the Transaction Audit section (only shown when itemization is enabled).

#### `struct CompletenessResult`

```swift
struct CompletenessResult {
    let itemsNetTotalCents: Int
    let itemsCount: Int
    let itemsMissingPriceCount: Int
    let transactionSubtotalCents: Int
    let completenessRatio: Double        // itemsNet / subtotal
    let status: CompletenessStatus
    let varianceCents: Int               // itemsNet - subtotal
    let variancePercent: Double
    let missingTaxData: Bool
}

enum CompletenessStatus: String {
    case complete      // |variance%| <= 1
    case near          // |variance%| <= 20
    case incomplete    // |variance%| > 20
    case over          // ratio > 1.2
}
```

#### `resolveSubtotal(amountCents:subtotalCents:taxRatePct:)` → `(subtotalCents: Int, missingTaxData: Bool)?`

Priority order (from RN):
1. If `subtotalCents` is non-nil and `> 0` → return `(subtotalCents, false)`
2. If `amountCents` is non-nil, `> 0`, AND `taxRatePct` is non-nil, `> 0` → infer: `(Int(Double(amountCents) / (1.0 + taxRatePct / 100.0)), false)`
3. If `amountCents` is non-nil and `> 0` → fallback: `(amountCents, true)`
4. Otherwise → `nil` (completeness cannot be computed)

#### `compute(items:returnedItems:soldItems:amountCents:subtotalCents:taxRatePct:)` → `CompletenessResult?`

From RN `computeTransactionCompleteness()`:
- Resolve subtotal. If nil, return nil.
- `itemsNetTotalCents` = sum of `purchasePriceCents ?? 0` from all items + returnedItems + soldItems
- `itemsMissingPriceCount` = count where `purchasePriceCents` is nil or 0
- `completenessRatio` = `Double(itemsNetTotalCents) / Double(subtotalCents)`
- `varianceCents` = `itemsNetTotalCents - subtotalCents`
- `variancePercent` = `(Double(varianceCents) / Double(subtotalCents)) * 100`
- Status thresholds:
  - `ratio > 1.2` → `.over`
  - `abs(variancePercent) <= 1` → `.complete`
  - `abs(variancePercent) <= 20` → `.near`
  - else → `.incomplete`

### New file: `LedgeriOS/LedgeriOS/Logic/TransactionListCalculations.swift`

`enum TransactionListCalculations` with static functions.

Ported from `src/components/SharedTransactionsList.tsx`:

#### `filterBySearch(transactions:query:)` → `[Transaction]`

From RN search logic — case-insensitive substring match across:
- `source` (display name)
- `notes`
- `transactionType`
- formatted `amountCents` (dollar string)

Empty query → return all.

#### `sortByDateDescending(_:)` → `[Transaction]`

Default sort from RN (`date-desc`):
- Sort by `transactionDate` descending (string comparison works for ISO dates — `"2026-02-03" > "2026-01-15"`)
- Nil dates sort last
- Tiebreaker: `createdAt` descending

### New file: `LedgeriOS/LedgeriOSTests/TransactionDisplayCalculationTests.swift`

~16 tests using Swift Testing (`@Suite`, `@Test`, `#expect`):
- `displayName`: source priority, trimmed whitespace, inventory sale labels (each direction), ID fallback (6 chars), empty fallback
- `formattedAmount`: nil → "$0.00", 10012 → "$100.12", 0 → "$0.00"
- `formattedDate`: valid ISO → "Feb 3, 2026", nil → "No date", empty → "No date", invalid → "No date"
- `itemCountLabel`: 0 → "0 items", 1 → "1 item", 5 → "5 items"
- `badgeConfigs`: purchase type (green), return type (red), sale type (blue), to-inventory (primary), reimbursement owed-to-client (amber label "Owed to Client"), receipt badge, needs review badge, category badge, multiple badges in order, no badges returns empty array
- `formattedPercent`: nil → "—", 8.25 → "8.25%"
- `formattedTaxAmount`: both present → difference, nil amount → "—"

### New file: `LedgeriOS/LedgeriOSTests/TransactionNextStepsCalculationTests.swift`

~12 tests using Swift Testing:
- Empty transaction, non-itemized → 5 steps, all incomplete
- Empty transaction, itemized → 6 steps, all incomplete
- Each step individually complete (with correct inputs)
- `budgetCategoryId` set but `budgetCategoryExists = false` → step 1 incomplete
- `taxRatePct = 0` and `> 0` → both incomplete per RN (requires `> 0`)
- `taxRatePct = nil` → step not present when `isItemizedCategory = false`
- `completedCount` matches expected
- `completionFraction` 5/6 → ~0.833
- `allComplete` true when all done, hides section

### New file: `LedgeriOS/LedgeriOSTests/TransactionCompletenessCalculationTests.swift`

~10 tests using Swift Testing. Ported from `src/utils/__tests__/transactionCompleteness.test.ts`:
- `resolveSubtotal`: explicit subtotal priority, inferred from tax, fallback to amount, nil when no data
- `compute`: complete (within 1%), near (within 20%), incomplete (> 20%), over (> 120%)
- Missing price count accuracy
- Nil result when no subtotal resolvable
- `missingTaxData` flag set correctly on fallback

### New file: `LedgeriOS/LedgeriOSTests/TransactionListCalculationTests.swift`

~8 tests using Swift Testing:
- Search by source substring, notes, type, formatted amount, case insensitive
- Empty query returns all
- Sort by date descending, nil dates last, tiebreaker by createdAt

**Pattern to follow:** `BudgetDisplayCalculations.swift` + `BudgetDisplayCalculationTests.swift`

---

## Step 2: New Components

### New file: `LedgeriOS/LedgeriOS/Components/ProgressRing.swift`

Circular progress indicator matching screenshot 07. RN uses a circular border approach; SwiftUI uses `Circle().trim()`.

```swift
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 48
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle()
                .stroke(BrandColors.progressTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(BrandColors.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(fraction * 100))%")
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(BrandColors.textPrimary)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(Int(fraction * 100)) percent complete")
    }
}
```

### New file: `LedgeriOS/LedgeriOS/Components/TransactionCard.swift`

Transaction card matching screenshot 05 and RN `TransactionCard.tsx`.

**Props:**
```swift
struct TransactionCard: View {
    let transaction: Transaction
    let budgetCategoryName: String?
    let itemCount: Int
    var selected: Bool = false
    var onSelectedChange: ((Bool) -> Void)? = nil
    var onMenuTap: (() -> Void)? = nil
}
```

**Layout (ported from RN TransactionCard):**

```
Card(padding: 0) {
  VStack(alignment: .leading, spacing: Spacing.sm) {
    // Row 1: badges
    HStack {
      if let onSelectedChange {
        SelectorCircle(selected: selected) { onSelectedChange(!selected) }
      }
      // FlowLayout or wrapping HStack of Badge views
      ForEach(badgeConfigs) { badge in
        Badge(text: badge.text, color: badge.color)
      }
      Spacer()
      if let onMenuTap {
        Button { onMenuTap() } label: {
          Image(systemName: "ellipsis")
            .foregroundStyle(BrandColors.textSecondary)
        }
      }
    }

    // Row 2: source + amount
    HStack(alignment: .firstTextBaseline) {
      Text(displayName)
        .font(Typography.h3)
        .foregroundStyle(BrandColors.textPrimary)
        .lineLimit(2)
      Spacer()
      Text(formattedAmount)
        .font(Typography.h3)
        .foregroundStyle(BrandColors.textPrimary)
        .lineLimit(1)
    }

    // Row 3: date + item count
    Text("\(formattedDate) - \(itemCountLabel)")
      .font(Typography.small)
      .foregroundStyle(BrandColors.textSecondary)

    // Row 4: notes (conditional — RN shows italic, 2-line limit)
    if let notes = transaction.notes?.trimmingCharacters(in: .whitespaces), !notes.isEmpty {
      Text(notes)
        .font(Typography.caption)
        .italic()
        .foregroundStyle(BrandColors.textTertiary)
        .lineLimit(2)
    }
  }
  .padding(Spacing.cardPadding)
}
```

All display values computed via `TransactionDisplayCalculations` static methods.

### New file: `LedgeriOS/LedgeriOS/Components/ListToolbar.swift`

Horizontally scrollable toolbar row matching screenshot 05 and RN `SharedTransactionsList` header.

```swift
struct ListToolbar: View {
    var onSelectAll: (() -> Void)? = nil
    var onSearch: (() -> Void)? = nil
    var onSort: (() -> Void)? = nil
    var onFilter: (() -> Void)? = nil
    var onAdd: (() -> Void)? = nil
}
```

Layout:
- `ScrollView(.horizontal, showsIndicators: false)` → `HStack(spacing: Spacing.sm)`
- Select-all: `SelectorCircle` (only if `onSelectAll` non-nil)
- Search: pill with `magnifyingglass` icon
- Sort: pill with `arrow.up.arrow.down` icon + "Sort" label
- Filter: pill with `line.3.horizontal.decrease.circle` icon + "Filter" label
- Add: `+ Add` in `BrandColors.primary` filled capsule (only if `onAdd` non-nil)

Pill style: `BrandColors.surface` background, `BrandColors.border` stroke, capsule shape, `Typography.buttonSmall` text. Reusable for Items list (Session 3).

---

## Step 3: Screens

### New file: `Views/Projects/TransactionsTabView.swift`

Replaces `TransactionsTabPlaceholder`. Layout ported from RN `SharedTransactionsList` in project scope mode.

**Data source:** `@Environment(ProjectContext.self)` — reads `transactions`, `budgetCategories`, `items`

**Layout:**
- `ListToolbar` at top
- `ScrollView` → `LazyVStack(spacing: Spacing.cardListGap)` of `NavigationLink(value: transaction)` → `TransactionCard`
- Empty state: `ContentUnavailableView("No Transactions", systemImage: "doc.text", description: "Add a transaction to get started.")`

**Computed properties:**
```swift
private var sortedTransactions: [Transaction] {
    let filtered = searchQuery.isEmpty
        ? projectContext.transactions
        : TransactionListCalculations.filterBySearch(
            transactions: projectContext.transactions, query: searchQuery)
    return TransactionListCalculations.sortByDateDescending(filtered)
}

private func categoryName(for transaction: Transaction) -> String? {
    projectContext.budgetCategories
        .first { $0.id == transaction.budgetCategoryId }?.name
}

private func itemCount(for transaction: Transaction) -> Int {
    projectContext.items
        .filter { $0.transactionId == transaction.id }.count
}
```

**Toolbar actions (stubs):**
- Search: toggles `@State private var isSearching = false` → shows search `TextField` below toolbar
- Sort/Filter: no-op (future: present sheet with RN's 8 sort modes and 8 filter types)
- Add: no-op (future: creation flow)
- Select All: no-op (future: bulk selection)

### New file: `Views/Projects/TransactionDetailView.swift`

Full transaction detail screen. Section structure ported from RN `src/app/transactions/[id]/index.tsx`.

**Init:** `let transaction: Transaction`

**Data source:** `@Environment(ProjectContext.self)` for `budgetCategories`, `items`

**Navigation bar (from RN):**
- `.navigationBarTitleDisplayMode(.inline)`
- `ToolbarItem(placement: .principal)`: `HStack` of `Badge` views for the transaction's badges
- `ToolbarItem(placement: .topBarTrailing)`: kebab `Menu` → confirmation dialog (stubs: Edit, Delete)

**Section state (default expand/collapse from RN):**
```swift
@State private var receiptsExpanded = true      // RN default: EXPANDED
@State private var otherImagesExpanded = false   // RN default: COLLAPSED
@State private var notesExpanded = false         // RN default: COLLAPSED
@State private var detailsExpanded = false       // RN default: COLLAPSED
@State private var itemsExpanded = false         // RN default: COLLAPSED
@State private var returnedItemsExpanded = false // RN default: COLLAPSED
@State private var soldItemsExpanded = false     // RN default: COLLAPSED
@State private var auditExpanded = false         // RN default: COLLAPSED
```

**ScrollView content — exact section order from RN SectionList:**

#### 1. Hero Card

```swift
Card {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        Text(TransactionDisplayCalculations.displayName(...))
            .font(Typography.h2)
            .foregroundStyle(BrandColors.textPrimary)
        DetailRow(label: "Amount",
                  value: TransactionDisplayCalculations.formattedAmount(amountCents: transaction.amountCents))
        DetailRow(label: "Date",
                  value: TransactionDisplayCalculations.formattedDate(transactionDate: transaction.transactionDate))
    }
}
```

#### 2. Next Steps Card (hidden when all complete — from RN)

```swift
let steps = TransactionNextStepsCalculations.computeSteps(
    transaction: transaction,
    itemCount: transactionItems.count,
    budgetCategoryExists: categoryName != nil,
    isItemizedCategory: isItemizedCategory
)
if !TransactionNextStepsCalculations.allComplete(steps: steps) {
    Card { ... }
}
```

Content:
- Header row: "Next Steps" (h3) + `"\(completedCount)/\(steps.count) complete"` (small, secondary) + `ProgressRing(fraction: completionFraction)`
- Incomplete steps first (from RN): icon (secondary) + label (primary) + `chevron.right`
- Divider
- Completed steps (from RN): gold checkmark circle + strikethrough label (secondary)

#### 3. Receipts — `CollapsibleSection(title: "RECEIPTS", isExpanded: $receiptsExpanded, onAdd: { })`

Content: Horizontal scroll of `AsyncImage` thumbnails from `transaction.receiptImages`. Empty state: `Text("No receipts yet.")` in secondary.

#### 4. Other Images — `CollapsibleSection(title: "OTHER IMAGES", isExpanded: $otherImagesExpanded, onAdd: { })`

Content: Same gallery pattern from `transaction.otherImages`. Empty state: `Text("No other images yet.")`

#### 5. Notes — `CollapsibleSection(title: "NOTES", isExpanded: $notesExpanded, onEdit: { })`

From RN NotesSection:
- If `notes?.trimmingCharacters(in: .whitespaces)` is empty → `Text("No notes.")` secondary
- Otherwise → `Text(notes)` body style

#### 6. Details — `CollapsibleSection(title: "DETAILS", isExpanded: $detailsExpanded, onEdit: { })`

From RN DetailsSection — **exact field order:**
1. `DetailRow(label: "Source", value: transaction.source?.trimmingCharacters(in: .whitespaces) ?? "—")`
2. `DetailRow(label: "Date", value: formattedDate)`
3. `DetailRow(label: "Amount", value: formattedAmount)`
4. `DetailRow(label: "Status", value: transaction.status?.trimmingCharacters(in: .whitespaces) ?? "—")`
5. `DetailRow(label: "Purchased by", value: transaction.purchasedBy?.trimmingCharacters(in: .whitespaces) ?? "—")`
6. `DetailRow(label: "Reimbursement type", value: transaction.reimbursementType?.trimmingCharacters(in: .whitespaces) ?? "—")`
7. `DetailRow(label: "Budget category", value: categoryName ?? transaction.budgetCategoryId ?? "None")`
8. `DetailRow(label: "Email receipt", value: transaction.hasEmailReceipt == true ? "Yes" : "No")`

**Conditional (only if `isItemizedCategory`):**
9. `DetailRow(label: "Subtotal", value: formattedAmount(subtotalCents))`
10. `DetailRow(label: "Tax rate", value: formattedPercent(taxRatePct))`
11. `DetailRow(label: "Tax amount", value: formattedTaxAmount(amountCents, subtotalCents))`

#### 7. Items — `CollapsibleSection(title: "ITEMS", isExpanded: $itemsExpanded, onAdd: { }, badge: "\(transactionItems.count)")`

Content: Simple list of item names (full `SharedItemsList` deferred to Session 3).
```swift
ForEach(transactionItems) { item in
    Text(item.name.isEmpty ? "Unnamed item" : item.name)
        .font(Typography.body)
        .foregroundStyle(BrandColors.textPrimary)
}
```
Empty state: `Text("No items yet.")` secondary.

#### 8. Returned Items (conditional — from RN `MovedItemsSection`)

Only shown if `returnedItems.count > 0`:
```swift
CollapsibleSection(title: "RETURNED ITEMS", isExpanded: $returnedItemsExpanded, badge: "\(returnedItems.count)")
```
Content: List of returned item names with 0.5 opacity (faded, from RN).

#### 9. Sold Items (conditional — from RN `MovedItemsSection`)

Only shown if `soldItems.count > 0`:
```swift
CollapsibleSection(title: "SOLD ITEMS", isExpanded: $soldItemsExpanded, badge: "\(soldItems.count)")
```
Content: List of sold item names with 0.5 opacity.

#### 10. Transaction Audit (conditional — from RN, only if `isItemizedCategory`)

`CollapsibleSection(title: "TRANSACTION AUDIT", isExpanded: $auditExpanded)`

From RN `AuditSection.tsx` — calls `TransactionCompletenessCalculations.compute()`:

- **If result is nil** (no valid subtotal): `Text("Unable to calculate completeness — transaction has no subtotal.")`
- **If result exists:**
  - Status row: SF Symbol + status label (left) + `"$items / $subtotal"` (right)
    - `.complete`/`.near` → `checkmark.circle.fill` green + "Complete"/"Nearly Complete"
    - `.incomplete` → `exclamationmark.circle` amber + "Incomplete"
    - `.over` → `xmark.circle.fill` red + "Over"
  - `ProgressBar(percentage: min(ratio * 100, 100))` with overflow indication
  - Below bar: `"\(itemsCount) items"` (left) + `"$X remaining"` or `"Over by $X"` (right)
  - If `returnedItemsCount > 0 || soldItemsCount > 0`: `"Includes X returned and Y sold item(s)"`
  - If `itemsMissingPriceCount > 0`: warning text `"N item(s) missing purchase price"` in amber

**Computed properties for TransactionDetailView:**
```swift
private var transactionItems: [Item] {
    projectContext.items.filter { $0.transactionId == transaction.id }
}

private var returnedItems: [Item] {
    // Items with status "returned" linked to this transaction
    projectContext.items.filter { $0.transactionId == transaction.id && $0.status == "returned" }
}

private var soldItems: [Item] {
    projectContext.items.filter { $0.transactionId == transaction.id && $0.status == "sold" }
}

private var activeItems: [Item] {
    transactionItems.filter { $0.status != "returned" && $0.status != "sold" }
}

private var categoryName: String? {
    projectContext.budgetCategories
        .first { $0.id == transaction.budgetCategoryId }?.name
}

private var isItemizedCategory: Bool {
    guard let catId = transaction.budgetCategoryId else { return false }
    return projectContext.budgetCategories
        .first { $0.id == catId }?
        .metadata?.categoryType == .itemized
}
```

---

## Step 4: Navigation Wiring

### Modify: `Views/Projects/ProjectDetailView.swift`

1. Replace `TransactionsTabPlaceholder()` with `TransactionsTabView()` in the tab content switch
2. Add `.navigationDestination(for: Transaction.self)`:

```swift
.navigationDestination(for: Transaction.self) { transaction in
    TransactionDetailView(transaction: transaction)
}
```

### Delete: `Views/Projects/TransactionsTabPlaceholder.swift`

---

## Step 5: Verification

1. **Unit tests:** Run all tests — new logic tests pass (~46 new tests), existing tests don't regress
2. **Build:** `xcodebuild build` succeeds with no new warnings
3. **Manual (iPhone 16e simulator):**
   - Navigate to project → Transactions tab shows transaction cards sorted by date (newest first)
   - Cards display: vendor name, amount, date, item count, notes (italic), badges in correct order/colors
   - Tap transaction → detail screen
   - Detail: hero card with name/amount/date
   - Next Steps shows progress ring, incomplete steps with chevrons, completed steps with strikethrough + gold check
   - Next Steps hidden when all steps are complete
   - Tax rate step only appears for itemized budget categories
   - Collapsible sections: Receipts (expanded), Others/Notes/Details/Items/Audit (collapsed)
   - Details section shows correct field order (Source, Date, Amount, Status, Purchased by, Reimbursement, Category, Email receipt, then conditional Subtotal/Tax rate/Tax amount)
   - Returned Items / Sold Items sections only appear when items exist with those statuses
   - Transaction Audit only appears for itemized categories, shows completeness status/bar/variance
   - Back button returns to list
   - Empty project shows empty state
   - Light + dark mode correct

---

## File Summary

| Action | File | Purpose |
|--------|------|---------|
| Create | `Logic/TransactionDisplayCalculations.swift` | Pure formatting: display name, amount, date, badges, percent |
| Create | `Logic/TransactionNextStepsCalculations.swift` | Pure step computation: 5-6 steps, conditional tax step |
| Create | `Logic/TransactionCompletenessCalculations.swift` | Pure completeness: subtotal resolution, ratio, status |
| Create | `Logic/TransactionListCalculations.swift` | Pure filtering/sorting for list |
| Create | `Tests/TransactionDisplayCalculationTests.swift` | ~16 tests |
| Create | `Tests/TransactionNextStepsCalculationTests.swift` | ~12 tests |
| Create | `Tests/TransactionCompletenessCalculationTests.swift` | ~10 tests |
| Create | `Tests/TransactionListCalculationTests.swift` | ~8 tests |
| Create | `Components/ProgressRing.swift` | Circular progress indicator |
| Create | `Components/TransactionCard.swift` | Transaction card for lists |
| Create | `Components/ListToolbar.swift` | Reusable search/sort/filter/add toolbar |
| Create | `Views/Projects/TransactionsTabView.swift` | Transaction list within project hub |
| Create | `Views/Projects/TransactionDetailView.swift` | Full transaction detail screen |
| Modify | `Views/Projects/ProjectDetailView.swift` | Wire transaction tab + navigation destination |
| Delete | `Views/Projects/TransactionsTabPlaceholder.swift` | Replaced |

## Execution Strategy

**Step 1 (parallel):** Logic + tests — create 8 files, run tests
**Step 2 (parallel):** Components — create ProgressRing + TransactionCard + ListToolbar
**Step 3 (sequential after 1+2):** Screens + navigation — create 2 views, modify ProjectDetailView, build + verify

## Key Files to Reuse

- `Components/Badge.swift` — badge pills in card and detail nav bar
- `Components/Card.swift` — card wrapper
- `Components/DetailRow.swift` — label + value in hero card and details section
- `Components/CollapsibleSection.swift` — all detail sections
- `Components/SelectorCircle.swift` — multi-select in list
- `Components/ProgressBar.swift` — reused in Transaction Audit section
- `State/ProjectContext.swift` — data source (transactions, items, budgetCategories)
- `Logic/BudgetDisplayCalculations.swift` — pattern reference
- `Theme/*` — spacing, typography, colors, dimensions

## Architecture Notes

### Data flow

`ProjectContext.activate()` already subscribes to the project's transactions, items, and budget categories. The Transactions tab reads directly from these — no additional subscriptions needed.

### Category name + itemization lookup

Transaction stores `budgetCategoryId` but not name or type. Lookup from `projectContext.budgetCategories`:
```swift
let cat = projectContext.budgetCategories.first { $0.id == transaction.budgetCategoryId }
let categoryName = cat?.name
let isItemized = cat?.metadata?.categoryType == .itemized
```

### Item classification (from RN)

Items have a `status` field. In the transaction detail:
- **Active items**: `transactionId == tx.id && status != "returned" && status != "sold"`
- **Returned items**: `transactionId == tx.id && status == "returned"`
- **Sold items**: `transactionId == tx.id && status == "sold"`

### Navigation pattern

```
ProjectDetailView
  └── ScrollableTabBar tab: "Transactions"
      └── TransactionsTabView
          └── NavigationLink(value: Transaction) → TransactionCard
  └── .navigationDestination(for: Transaction.self)
      └── TransactionDetailView(transaction:)
          ├── Hero Card (name, amount, date)
          ├── Next Steps Card (conditional — hidden when all complete)
          │   └── ProgressRing + checklist steps
          ├── CollapsibleSection: Receipts (expanded by default)
          ├── CollapsibleSection: Other Images
          ├── CollapsibleSection: Notes
          ├── CollapsibleSection: Details (11 fields, 3 conditional)
          ├── CollapsibleSection: Items (with count badge)
          ├── CollapsibleSection: Returned Items (conditional)
          ├── CollapsibleSection: Sold Items (conditional)
          └── CollapsibleSection: Transaction Audit (conditional, itemized only)
```

### ListToolbar reusability

The toolbar pattern (select-all + search + sort + filter + add) appears in both Transactions and Items tabs (screenshot 04a). Building it now avoids duplication in Session 3.

### Badge color mapping (from RN TransactionCard.tsx)

| Badge | Label | Color |
|-------|-------|-------|
| Transaction type: purchase | "Purchase" | `StatusColors.badgeSuccess` (green #059669) |
| Transaction type: sale | "Sale" | `StatusColors.badgeInfo` (blue #2563eb) |
| Transaction type: return | "Return" | `StatusColors.badgeError` (red #dc2626) |
| Transaction type: to-inventory | "To Inventory" | `BrandColors.primary` (taupe #987e55) |
| Reimbursement: owed-to-client | "Owed to Client" | `StatusColors.badgeWarning` (amber #d97706) |
| Reimbursement: owed-to-company | "Owed to Business" | `StatusColors.badgeWarning` (amber #d97706) |
| Email receipt | "Receipt" | `BrandColors.primary` |
| Needs review | "Needs Review" | `StatusColors.badgeNeedsReview` (rust #b94520) |
| Budget category | category name | `BrandColors.primary` |
