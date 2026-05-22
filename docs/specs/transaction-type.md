# Transaction Taxonomy — Single-Enum Model

> Status: **proposed.** Implementation plan: [../plans/transaction-type-migration.md](../plans/transaction-type-migration.md).

## Purpose

Collapse the two overlapping type axes on Transaction — `transactionType` (`purchase | sale | return`) and the referenced budget category's `metadata.categoryType` (`fee | expense | itemized | general`) — into a **single enum used by both**. Categories reference `TransactionType` values directly through a `supportedTypes` field. `BudgetCategoryType` is retired.

This spec defines the single enum, the new Category field, the user-facing labels, and data-model invariants. Phased rollout is in the companion plan.

## The Single Enum

`TransactionType` expands from 3 values to 5. The three existing raw values are retained unchanged — their meaning narrows. Two new values are added.

| Value | Raw | Meaning | Notes |
|---|---|---|---|
| `fee` | `"fee"` | Money the business charges the client for services. Counterparty is implicitly the business. | New. |
| `expense` | `"expense"` | Non-itemized project cost paid to a third party (delivery, storage, fuel). | New. |
| `purchase` | `"purchase"` | Purchase of physical items that flow through the inventory/item model, including inventory → project purchases. | Retained. **Meaning narrows** — was previously any payment-out transaction; now itemized only. |
| `sale` | `"sale"` | Items sold out of a project into inventory when the business acquires project-originated items. Not user-pickable from the wizard. | Retained. |
| `return` | `"return"` | Items returned to a vendor (wizard) or to inventory (item action). | Retained. |

Keeping `purchase`, `sale`, `return` as raw values means Firestore field values don't rename; only legacy `purchase` transactions whose category is semantically a fee or expense get rewritten.

## Budget Category

`BudgetCategoryType` is **removed**. Categories gain a new field:

```swift
struct BudgetCategory {
    // existing fields unchanged: id, accountId, projectId, name, slug,
    // isArchived, order, createdAt, updatedAt, metadata (minus categoryType)

    var supportedTypes: [TransactionType]
}
```

`supportedTypes` is the list of transaction kinds this category accepts.

**Fees are exclusive.** A fee category holds fees only — fee totals are income (client-owed-to-business), inverted vs. spend totals, and mixing would make the budget math meaningless.

**Everything else can combine.** Real-world budget lines like "Install" or "Additional Requests" naturally hold both item purchases (cabinets, TVs) and service expenses (installer labor, delivery). Forcing such a category into one shape misrepresents the data.

Valid shapes:

| Category kind | `supportedTypes` |
|---|---|
| Fees | `[.fee]` |
| Expense-only | `[.expense]` |
| Items-only | `[.purchase, .return]` |
| Mixed | `[.purchase, .return, .expense]` |

The UI's category-creation picker surfaces these four as named options. Arbitrary subsets of `{purchase, return, expense}` are schema-valid but the UI doesn't emit them; they exist only as a safety-net for legacy derivation edge cases.

Sales (`.sale`) are not included in any `supportedTypes` list — sale-to-inventory transactions have no category because items leave the project's category system. Inventory → project movements are Purchases and link to the destination category.

### Invariants

- Every category has a non-empty `supportedTypes`.
- Every non-Sale transaction with a `budgetCategoryId` links to a category where `supportedTypes.contains(transactionType)`.
- Fee categories are exclusive: `supportedTypes == [.fee]`, never mixed with other values.
- Enforced at the write layer (iOS + MCP), not in Firestore rules.

## UI Model

### Creating a transaction (the wizard)

First step becomes a single 4-option picker:

```
Fee                   → writes .fee
Expense               → writes .expense
Purchase (items)      → writes .purchase
Return (items)        → writes .return
```

The fifth enum value, `.sale`, is not user-pickable from the wizard. Sales are written exclusively by inventory operations when project-originated items are sold into inventory.

The downstream flow follows the picked kind. The separate "Fee / Expense / Itemized" filter step (introduced in v2) is retired — it was the symptom of the two-enum split.

Flow by kind:

| Kind | Who paid? | Destination | Budget category | Vendor | Reimbursement toggle |
|---|---|---|---|---|---|
| `.fee` | skip (business) | Project (pre-filled) | filter: `supportedTypes.contains(.fee)` | skip | no |
| `.expense` | shown | Project (pre-filled) | filter: `supportedTypes.contains(.expense)` | shown | shown |
| `.purchase` | shown | Project OR auto-Inventory (if business-paid) | filter: `supportedTypes.contains(.purchase)` | shown | no |
| `.return` | skip (business) | Project (pre-filled) OR inventory | filter: `supportedTypes.contains(.return)` | shown (vendor items went back to) | no |
| *(`.sale` — not user-pickable)* | n/a | written via `sellToProject()` with items | | | |

Reimbursement toggle semantics are unchanged — see [transaction-creation.md](transaction-creation.md) §Payable Semantics.

### Creating a category (settings)

The "Category type" picker is a **4-option, pluralized picker**:

```
Fees                                → supportedTypes = [.fee]
Expenses                            → supportedTypes = [.expense]
Purchases/Returns (items)           → supportedTypes = [.purchase, .return]
Mixed (items + expenses)            → supportedTypes = [.purchase, .return, .expense]
```

The options are plural because a category collects many transactions over time. The wizard's top picker stays singular because it's about one action.

**Why "Mixed" exists.** Some budget lines (Install, Additional Requests) track both items and service expenses together — e.g. a Lowe's supplies run alongside an installer's labor fee. Forcing those categories into one shape either hides transactions from the wizard's filter or mis-labels them. Mixed accepts both.

### Return-to-vendor vs return-to-inventory

Two distinct return operations both write `.return` transactions:

- **Return to vendor** — user-initiated from the wizard. Items physically go back to a store. User picks the vendor on the Vendor step. This is the only path for this operation.
- **Return to inventory** — item-action-initiated from item detail / action menus, handled by `InventoryOperationsService.returnToInventory()`. Items move from a project back to the business's own inventory. Not created through the wizard.

### Transaction audit gate

Whether a transaction needs tax/subtotal data (and therefore whether it shows as "Needs Review") is a property of the **transaction's own type**, not the category's shape. A category like "Install" holding both a Lowe's supply purchase and an installer's labor-fee expense has:

- The purchase → needs tax + subtotal → may be incomplete until entered.
- The expense → needs neither → auto-complete.

Audit gate (applies everywhere — Cloud Functions `computeIsComplete`, `EditTransactionDetailsModal`, `TransactionDetailView`, `TransactionNextStepsCalculations`, the wizard):

```
needsAudit = transactionType == .purchase || transactionType == .return
```

Category-shape is irrelevant to this check. The legacy rule `metadata.categoryType == 'itemized'` is retired.

## Reading Legacy Data

Two types of legacy documents exist pre-migration:

**Transactions** — historical docs with `type ∈ {"purchase", "sale", "return"}`, some of which are really fees or expenses:

| Stored type | Linked category's supportedTypes | Resolves to |
|---|---|---|
| `sale` | any | `sale` |
| `return` | any | `return` |
| `purchase` | `[.fee]` | `fee` |
| `purchase` | `[.expense]` | `expense` |
| `purchase` | `[.purchase, .return]` | `purchase` |
| `purchase` | empty / nil / unknown | `purchase` (default — inventory purchases and edge cases) |

**Categories** — historical docs with `metadata.categoryType ∈ {"fee", "expense", "itemized", "general"}`, or the field entirely missing:

| Stored `categoryType` | Derived `supportedTypes` |
|---|---|
| `fee` | `[.fee]` |
| `expense` | `[.expense]` |
| `general` | `[.expense]` |
| `itemized` | `[.purchase, .return]` |
| `(missing)` | `[.purchase, .return, .expense]` (Mixed — widest safe default so the category matches the wizard filter regardless of tx type) |

The derivation is fallback-only; real migration uses per-category human-reviewed overrides (see the migration plan, Script 2).

These derivations are the single source of truth. They live in one named place in code (proposed: `TransactionTaxonomy.resolve(…)`), not scattered across call sites.

## Downstream Consumers

Every consumer that reads `categoryType` or uses `transactionType` in a legacy-three-value way is audited and swapped. See the migration plan for the consumer checklist.

Notable ones:

- `ReportAggregationCalculations.computeInvoiceReport` — today excludes categories with `categoryType == .fee`. Becomes: exclude categories where `supportedTypes == [.fee]` (or better, exclude transactions where `transactionType == .fee` directly).
- Budget Tab grouping / display — today groups categories by `categoryType`. Becomes: group by the single element of `supportedTypes`, or derive a "primary type" (first element).
- Firestore rules — no change needed. Raw values of `transactionType` don't shift.
- MCP server — `transactionType` zod enum expands to accept all 5 values. Category tools that read/write `categoryType` swap to `supportedTypes`.

## Open Questions

- **`.general` legacy.** Treated as `.expense` throughout. Not separately migrated — a legacy `.general` category's `supportedTypes` is derived as `[.expense]`. New categories can no longer be `.general` (UI constraint added at Phase 1).
- **Edit flow.** Editing a category may change its `supportedTypes`. What happens to existing transactions whose type is no longer in the new list? Options: block the change, warn and reassign, allow (drift). Leaning toward "block the change if it would orphan existing transactions" — call out during implementation.
- **MCP backwards compat.** External MCP callers may still pass old `categoryType` values when creating categories. Accept both field names during a deprecation window.
