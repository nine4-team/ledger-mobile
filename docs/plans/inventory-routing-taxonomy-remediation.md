# Inventory Routing / Transaction Taxonomy Remediation

Status: proposed
Created: 2026-06-26

## Problem

The current transaction creation flow can show the post-create `ItemEntryFlowView`
and "Sell to Project?" path when a user is only creating a paid transaction. This
is especially wrong for non-itemized transactions such as install, fuel, delivery,
storage, or other service costs.

The regression is a taxonomy drift:

- The intended routing signal was **budget category itemization** plus purchaser.
- Later taxonomy work narrowed `TransactionType.purchase` to mean "items only".
- Current code then uses `.purchase + design-business` as the inventory-routing
  signal before the budget category is known.

That conflates "purchase" as a normal financial event with "itemized inventory
purchase" as a workflow. Services and other costs are also purchased; they should
not inherit inventory behavior merely because the business paid.

## Last Known-Good Behavior

Commit `322cf420` (`2026-04-05`, `feat: item entry flow -- inventory routing for
business-purchased itemized transactions`) had the correct gate:

```swift
private var isItemizedCategory: Bool {
    selectedCategory?.metadata?.categoryType == .itemized
}

let routeThroughInventory = isItemizedCategory && purchasedBy == "design-business"
```

The matching spec language in that commit said:

- Business-purchased itemized items route through inventory.
- Client-purchased itemized items go direct to the project.
- Non-itemized expense categories skip inventory entirely.
- Category type plus purchaser is the routing decision.

This remains the intended product behavior.

## Source of Truth

Use this rule:

```text
routeThroughInventory =
  selected budget category is itemized/items
  AND purchasedBy == design-business
```

Do not use this rule:

```text
routeThroughInventory =
  transactionType == purchase
  AND purchasedBy == design-business
```

`purchase` must remain understandable as a normal money-spent transaction. The
item/inventory behavior belongs to the selected budget category.

## Code Problems To Fix

### 1. `NewTransactionView` routes too early and on the wrong axis

File: `LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift`

Current problem:

```swift
private var autoInventoryRouting: Bool {
    transactionType == .purchase && purchasedBy == "design-business"
}
```

This is wrong because it knows nothing about the budget category. It also runs
before category selection and can skip the Destination step.

Fix:

- Remove `autoInventoryRouting` as a standalone route gate.
- Route through inventory only after `selectedCategory` is known.
- Use current category API:

```swift
private var routeThroughInventory: Bool {
    selectedCategory?.isItemsCategory == true &&
    purchasedBy == "design-business"
}
```

If `isItemsCategory` remains broad because mixed categories contain `.purchase`,
add a precise helper that preserves the old category semantics:

```swift
private var isItemizedCategory: Bool {
    selectedCategory?.metadata?.categoryType == .itemized ||
    selectedCategory?.resolvedSupportedTypes == [.purchase, .return]
}
```

Do not let mixed service/item categories auto-route every business-paid purchase
through inventory unless the user has explicitly chosen the itemized path.

### 2. Step ordering skips Destination before category is known

File: `LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift`

Current problem:

```swift
if !autoInventoryRouting { steps.append(.destination) }
if destinationProjectId != nil { steps.append(.budgetCategory) }
```

Because `autoInventoryRouting` is based on `.purchase + design-business`, the
form can skip Destination and create an inventory transaction before category
selection has proven that this is itemized.

Fix:

- Do not skip Destination based only on transaction type and purchaser.
- Make category selection happen for project-scoped purchases before inventory
  routing is finalized.
- At submit time, clear `projectId` only if the selected category is itemized
  and the business paid.

Target submit behavior:

```swift
transaction.projectId = routeThroughInventory ? nil : destinationProjectId
transaction.budgetCategoryId = routeThroughInventory ? nil : selectedCategoryId

if routeThroughInventory {
    createdTransactionId = txId
} else {
    onCreated?(transaction)
    dismiss()
}
```

### 3. `routeThroughInventorySource` is an extra, undocumented route

File: `LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift`

Current problem:

```swift
private var routeThroughInventorySource: Bool {
    transactionType == .purchase && destinationProjectId != nil && inventorySourceSelected
}
```

This is not the original routing rule and should not be able to route a plain
transaction into item entry. Selecting an inventory-looking source/vendor is not
the same as creating business-owned inventory items.

Fix:

- Remove this path, or restrict it behind the same category itemization gate.
- If kept, rename it away from "source" and make it explicit in the UI as an
  itemized inventory acquisition action.

### 4. `ItemEntryFlowView` can show "Sell to Project?" with no items

File: `LedgeriOS/LedgeriOS/Views/Creation/ItemEntryFlowView.swift`

Current problem:

- The flow advances from Add Items to Sell Prompt even if no items were created.
- That makes the user experience feel transaction-driven instead of item-driven.

Fix:

- If `transactionItems.isEmpty`, the primary action should dismiss or stay in
  Add Items, not show "Sell to Project?".
- Only show the sell options when at least one item exists.

### 5. Tax/subtotal and audit gates may be using transaction type as itemization

Files to audit:

- `LedgeriOS/LedgeriOS/Modals/EditTransactionDetailsModal.swift`
- `LedgeriOS/LedgeriOS/Logic/TransactionNextStepsCalculations.swift`
- `firebase/functions/src/index.ts` (`computeIsComplete`)
- `docs/specs/transaction-completeness.md`
- `docs/specs/transaction-audit.md`

Problem:

Some newer taxonomy work says category shape is irrelevant and audit should be
based on `transactionType == .purchase || .return`. That may be correct for a
future explicitly itemized transaction model, but it is not safe while
`purchase` remains normal money-spent language.

Fix:

- Reconfirm the desired audit source.
- If itemization is still a budget category property, audit/tax fields should be
  driven by the selected/linked itemized category, not by `.purchase` alone.
- Mixed categories need an explicit UX decision before they can safely replace
  category itemization as the audit gate.

## Documentation Problems To Fix

### 1. Bad taxonomy spec narrows `purchase`

File: `docs/specs/transaction-type.md`

Problem lines:

- `purchase` is defined as physical items only.
- The spec says the old meaning narrows.
- The wizard used to label `Purchase (items)` as the `.purchase` transaction
  type.
- It says category shape is irrelevant to audit.

Fix:

- Mark this spec as superseded or rewrite it.
- Restore `purchase` as money spent to buy goods or services.
- Keep itemization as budget-category behavior unless a separate approved
  itemization axis is introduced.
- Remove or revise the claim that `BudgetCategoryType` can be fully retired
  without replacing the itemization signal.

### 2. Migration plan encodes the bad taxonomy

File: `docs/plans/transaction-type-migration.md`

Problem lines:

- Phase 1 says to add a doc comment that `.purchase` means itemized purchase
  only.
- Phase 4 says to clear `metadata.categoryType`, delete `BudgetCategoryType`,
  and add a write-path guard for `.purchase`.
- Phase 2/4 audit-gate notes move itemization to transaction type.

Fix:

- Pause Phase 4.
- Add a correction section explaining that `purchase` must not be narrowed.
- Do not clear the category itemization metadata until an approved replacement
  exists.
- Update verification to include a business-paid non-itemized purchase that
  must not open item entry or sell-to-project.

### 3. `item-entry-flow.md` drifted from the original purchaser-sensitive rule

File: `docs/specs/item-entry-flow.md`

Current problem:

- It now says all itemized categories flow through inventory first.
- It lost the original distinction that client-purchased itemized items go
  direct to project.

Fix:

- Restore the original rule:
  - business-paid + itemized category -> inventory first
  - client-paid + itemized category -> direct to project
  - non-itemized category -> direct to project
- Clarify that "Sell to Project?" appears only after inventory items have been
  created.

### 4. `transaction-creation.md` is closer to correct but must survive taxonomy cleanup

File: `docs/specs/transaction-creation.md`

Good line:

```text
The "route through inventory" decision is computed as
isItemizedCategory && purchasedBy == "design-business".
```

Fix:

- Keep this rule.
- Update any step descriptions that imply transaction type alone controls
  itemization.
- Add a regression note: business-paid non-itemized purchases never route to
  `ItemEntryFlowView`.

### 5. User docs are conceptually right and should not be rewritten to match bad code

Files:

- `user-docs/reference/transaction-types.md`
- `user-docs/core-concepts/transactions.md`
- `user-docs/workflows/create-a-transaction.md`

Current state:

- These docs correctly use Purchase in the ordinary sense: money spent to buy
  items or pay costs.

Fix:

- Keep that meaning.
- Add one clarification: itemized budget categories may trigger item entry and
  inventory routing when the business paid.
- Do not tell users that services are "not purchases."

## Implementation Plan

### Phase 1: Stop the incorrect sell prompt

1. Restore category-based routing in `NewTransactionView`.
2. Remove or constrain `routeThroughInventorySource`.
3. Ensure `ItemEntryFlowView` only appears for category-itemized,
   business-paid transactions.
4. Prevent the sell prompt when zero items exist.

Acceptance tests:

- Business-paid purchase in a non-itemized category stays on the project and
  dismisses after creation.
- Business-paid purchase in an itemized category creates inventory transaction
  and opens item entry.
- Client-paid purchase in an itemized category stays on the project.
- Business-paid transaction with source/vendor equal to inventory does not route
  unless the category is itemized.

### Phase 2: Repair specs

1. Rewrite or supersede `transaction-type.md`.
2. Amend `transaction-type-migration.md` and pause Phase 4.
3. Restore purchaser-sensitive language in `item-entry-flow.md`.
4. Add regression examples to `transaction-creation.md`.

### Phase 3: Audit downstream category/type consumers

Review every call site that uses transaction type as a proxy for itemization.
For each one, decide whether it needs:

- financial type (`purchase`, `return`, `sale`, etc.), or
- category itemization (`itemized` / `items category`), or
- both.

Known high-risk areas:

- transaction completeness / audit
- tax/subtotal fields
- invoice line inclusion
- billing summaries
- transaction filters and labels
- MCP transaction creation/update guidance
- Cloud Functions budget and completeness logic

### Phase 4: Data cleanup only after semantics are fixed

Do not run scripts that clear category itemization metadata until the product
has an approved replacement for the itemized/non-itemized signal.

## Non-Goals

- Do not add a new itemization field unless category metadata is formally
  retired and replaced.
- Do not redefine services as "not purchases."
- Do not make inventory routing depend on source/vendor text.
- Do not route mixed categories automatically without an explicit user choice.

## Regression Checklist

- [ ] Non-itemized business-paid purchase creates one project transaction.
- [ ] Non-itemized business-paid purchase does not show Add Items.
- [ ] Non-itemized business-paid purchase does not show Sell to Project.
- [ ] Itemized business-paid purchase creates an inventory transaction.
- [ ] Itemized business-paid purchase opens Add Items.
- [ ] Sell to Project appears only after one or more items exist.
- [ ] Itemized client-paid purchase stays on the destination project.
- [ ] Inventory source/vendor text alone does not trigger item entry.
- [ ] Existing inventory item action "Sell to Project" still works.
- [ ] Existing inventory movement transactions still display correctly.
