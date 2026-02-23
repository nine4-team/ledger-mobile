# Return and Sale Tracking System — Spec

## Purpose

Single source of truth for how the app tracks **returns**, **sales**, and **item movements** within and across transactions — and how these movements interact with the **transaction audit** (completeness) system and the **lineage edge** system.

This spec covers:
- Creating and linking items to return transactions
- How returned and sold items appear in transaction detail views
- How the audit system accounts for items that have left a transaction
- How lineage edges record the intent and history of each movement
- Budget spending impact of returns and sales

## Scope

**In scope:**
- Return transaction creation and item linking
- Item disposition lifecycle (`to purchase` → `purchased` → `to return` → `returned`)
- Returned/sold item sections in transaction detail views
- Transaction audit completeness calculation including returned and sold items
- Lineage edge creation for returns vs sales vs corrections
- Budget spending sign conventions for returns and sales

**Out of scope:**
- Canonical sale flow mechanics (covered in [canonical_sale_system.md](canonical_sale_system.md))
- Reassign operations (covered in [reassign_spec.md](reassign_spec.md))
- Exact UI styling, animations, color values
- Permission/role rules

## Definitions

| Term | Meaning |
|------|---------|
| **Return transaction** | A user-created transaction with `transactionType: 'return'`. Represents a refund/return event at a vendor. |
| **Active items** | Items currently linked to a transaction (`item.transactionId === transaction.id`). |
| **Returned items** | Items that were once in a transaction but left via a return. Identified by lineage edges from this transaction with `movementKind: 'returned'`. |
| **Sold items** | Items that were once in a transaction but left via a sale. Identified by lineage edges from this transaction with `movementKind: 'sold'`. |
| **Association edge** | An audit-trail lineage edge (`movementKind: 'association'`) appended whenever `item.transactionId` changes. Records *what happened*. |
| **Intent edge** | A semantic lineage edge (`movementKind: 'sold' | 'returned' | 'correction'`) that records *why* the movement happened. |
| **Disposition** | An item-level status field tracking its lifecycle stage. Values: `'to purchase'`, `'purchased'`, `'to return'`, `'returned'`, `'inventory'`. |

## Data Model

### Item Fields (relevant subset)

```typescript
type Item = {
  id: string;
  transactionId?: string | null;          // Currently linked transaction
  projectId?: string | null;              // Project scope (null = business inventory)
  status?: string | null;                 // General status
  purchasePriceCents?: number | null;     // Used in audit completeness
  budgetCategoryId?: string | null;
  // Lineage pointers (denormalized)
  latestTransactionId?: string | null;    // Most recent transaction (set by triggers)
  originTransactionId?: string | null;    // First transaction (set once, immutable)
};
```

**Item disposition values** (from `src/constants/itemStatuses.ts`):

| Value | Meaning |
|-------|---------|
| `to purchase` | Marked for purchase, not yet bought |
| `purchased` | Purchase completed |
| `to return` | Marked for return, not yet returned |
| `returned` | Return completed (item linked to a return transaction) |

### Transaction Fields (relevant subset)

```typescript
type Transaction = {
  id: string;
  projectId?: string | null;
  transactionType?: string | null;                  // 'purchase' | 'return' | null
  amountCents?: number | null;                      // Total including tax
  subtotalCents?: number | null;                    // Pre-tax subtotal
  taxRatePct?: number | null;
  budgetCategoryId?: string | null;
  isCanceled?: boolean | null;
  isCanonicalInventorySale?: boolean | null;
  inventorySaleDirection?: 'business_to_project' | 'project_to_business' | null;
  itemIds?: string[] | null;
};
```

### Lineage Edge

```typescript
type ItemLineageMovementKind = 'sold' | 'returned' | 'correction' | 'association';

type ItemLineageEdge = {
  id: string;
  accountId: string;
  itemId: string;
  fromTransactionId: string | null;      // null = from inventory
  toTransactionId: string | null;        // null = to inventory
  movementKind: ItemLineageMovementKind;
  source: 'app' | 'server' | 'migration';
  createdAt: string;                     // ISO timestamp
  createdBy?: string | null;
  note?: string | null;
  fromProjectId?: string | null;
  toProjectId?: string | null;
};
```

## Return Flow

### How Returns Work

A return is modeled as **moving items from their original purchase transaction to a return transaction**. The return transaction represents the vendor refund event.

```
Purchase Transaction (transactionType: 'purchase')
  ├── Item A (active — still in this transaction)
  ├── Item B (active)
  └── Item C ──moved to──▶ Return Transaction (transactionType: 'return')
```

### Step-by-Step Flow

1. **User creates a return transaction** (or one already exists)
   - `transactionType` is set to `'return'`
   - The return transaction has its own `amountCents` (the refund amount)

2. **User moves item(s) to the return transaction**
   - Via item action menu: "Move to Return Transaction"
   - Or via bulk action: select items → move to transaction picker → select the return transaction

3. **On item assignment to a return transaction, the system:**

   a. **Updates `item.transactionId`** to the return transaction's ID

   b. **Auto-sets `item.disposition` to `'returned'`** (unless the caller explicitly provides a different disposition)

   c. **Creates a `returned` intent edge:**
      ```
      {
        itemId: item.id,
        fromTransactionId: originalPurchaseTransaction.id,
        toTransactionId: returnTransaction.id,
        movementKind: 'returned',
        source: 'app',        // or 'server' if triggered by cloud function
        note: 'Returned to project'
      }
      ```

   d. **Creates an `association` edge** (via the `onItemTransactionIdChanged` cloud function trigger):
      ```
      {
        itemId: item.id,
        fromTransactionId: originalPurchaseTransaction.id,
        toTransactionId: returnTransaction.id,
        movementKind: 'association',
        source: 'server'
      }
      ```

4. **The cloud function also detects return transactions independently:**
   - When `item.transactionId` changes, the `onItemTransactionIdChanged` trigger fires
   - It reads the destination transaction's `transactionType`
   - If `transactionType.trim().toLowerCase() === 'return'`, it creates a `returned` intent edge (server-side safety net)

### Return Detection Logic (Cloud Function)

The cloud function normalizes the transaction type field to handle legacy data variations:

```typescript
const rawType = (toTx?.transactionType ?? toTx?.type ?? toTx?.transaction_type ?? null);
const isReturn = typeof rawType === 'string' && rawType.trim().toLowerCase() === 'return';
```

This ensures return detection works regardless of which field name the transaction type is stored in.

## Sale Flow (Movement Tracking)

Sales are tracked differently from returns. When an item is sold (moved between project scopes via the canonical sale system), the system creates `sold` intent edges.

### Sale Edge Creation

Canonical sale request handlers in cloud functions create `sold` edges:

| Operation | Edge `from` | Edge `to` | `movementKind` |
|-----------|-------------|-----------|-----------------|
| Project → Business | Source allocation tx | Canonical sale tx | `sold` |
| Business → Project | Canonical sale tx (or null) | Target allocation tx | `sold` |
| Project → Project | Two edges (hop 1 + hop 2), each `sold` | | `sold` |

### Correction Edges

When items are moved between transactions for non-sale, non-return reasons (e.g., fixing a mis-linked item):

```
{
  movementKind: 'correction',
  note: 'Changed transaction'
}
```

Correction edges are **excluded** from sold/returned item sections and from audit completeness calculations.

## Transaction Detail View — Item Sections

### Section Structure

The transaction detail view displays items in three sections:

```
┌─────────────────────────────────────┐
│ ITEMS (active)                      │
│ ┌─────────────────────────────────┐ │
│ │ Item A         $25.00           │ │
│ │ Item B         $30.00           │ │
│ └─────────────────────────────────┘ │
│                                     │
│ RETURNED ITEMS                      │
│ ┌─────────────────────────────────┐ │
│ │ Item C         $15.00    (dim)  │ │
│ └─────────────────────────────────┘ │
│                                     │
│ SOLD ITEMS                          │
│ ┌─────────────────────────────────┐ │
│ │ Item D         $20.00    (dim)  │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### Section Definitions

| Section | Source | Interaction | Visual Treatment |
|---------|--------|-------------|------------------|
| **Items** (active) | `item.transactionId === transaction.id` | Full edit, bulk select, actions | Normal rendering |
| **Returned Items** | Lineage edges from this transaction with `movementKind: 'returned'` | Read-only, no actions | Dimmed (reduced opacity) |
| **Sold Items** | Lineage edges from this transaction with `movementKind: 'sold'` | Read-only, no actions | Dimmed (reduced opacity) |

### How Moved-Out Items are Identified

Items that left a transaction are found by querying lineage edges where `fromTransactionId === transaction.id`:

```typescript
// Query: all edges FROM this transaction
const edgesFromTransaction = getEdgesFromTransaction(transactionId, accountId);

// Filter by movement kind
const returnedItems = edgesFromTransaction
  .filter(edge => edge.movementKind === 'returned')
  .map(edge => fetchItem(edge.itemId));

const soldItems = edgesFromTransaction
  .filter(edge => edge.movementKind === 'sold')
  .map(edge => fetchItem(edge.itemId));
```

**Correction edges are excluded** — items moved via `correction` do not appear in either section.

### Visibility Rules

- **Returned Items section**: Only shown when `returnedItems.length > 0`
- **Sold Items section**: Only shown when `soldItems.length > 0`
- Both sections are collapsed by default (collapsible headers)

### Read-Only Enforcement

Returned and sold items must be:
- Non-selectable (excluded from bulk selection)
- Non-editable (no inline price editing)
- No context menu actions (no sell, reassign, unlink, etc.)
- Visually distinct (reduced opacity or other treatment to indicate they're historical)

## Incomplete Return Detection

### The Problem

A user can set an item's disposition to `'returned'` via the status dropdown without actually moving it to a return transaction. In this case:

- The item has `disposition: 'returned'` but is still linked to the original purchase transaction
- No `returned` lineage edge exists
- There is no financial record of the return (no return transaction, no budget impact)
- **The item stays in the active items section** — section placement is driven by lineage edges, not disposition

This is an **incomplete return**: the disposition signals intent, but the return hasn't been recorded in the system.

### Detection Rule

An item has an incomplete return when ALL of the following are true:
- `item.disposition === 'returned'`
- `item.transactionId` points to a non-return transaction (i.e., the item is still in a purchase transaction)
- No lineage edge exists from this transaction with `movementKind: 'returned'` for this item

### Three-Layer Response

The system addresses incomplete returns at three levels — prevention, per-item visibility, and transaction-level summary.

#### Layer 1: Prompt at Disposition Change (prevention)

When the user sets an item's disposition to `'returned'`, immediately present a bottom sheet prompting them to link the item to a return transaction:

- **Options**: Select an existing return transaction in this project, or create a new one
- **Non-blocking**: The user can dismiss the prompt. The disposition is still set to `'returned'` — the prompt is a nudge, not a gate. This allows rapid batch categorization with the option to come back and link later.
- If the user selects an existing return transaction, the item is moved immediately (triggering the full return flow: lineage edge, audit update, etc.)
- **"Create new" flow**: If the user chooses to create a new return transaction, they enter the standard transaction creation flow (screen-by-screen). When the new transaction is created, the originating item **must be automatically linked** to it with disposition `'returned'` — the system must carry the item context through the creation flow so the link isn't dropped. This is critical: the user initiated creation *because* of this item, so the item should be attached to the resulting transaction without any extra manual step.
- **Note**: The transaction creation flow is being revised to a screen-by-screen process (not a single form). The return-transaction prompt must integrate with whatever that flow looks like — the key contract is that item context is preserved and auto-linked on completion.

#### Layer 2: Warning Badge on Item (per-item visibility)

Items with an incomplete return show a small warning indicator on their card in the active items list. The indicator should be visually consistent with warning indicators used in the transaction audit section (same icon style and color).

- Tapping the badge reveals an explanation: "This item is marked as returned but hasn't been linked to a return transaction."
- The badge is only shown on items that match the detection rule above
- The badge disappears once the item is moved to a return transaction

#### Layer 3: Audit Section Flag (transaction-level summary)

The transaction audit section includes a warning when any active items have incomplete returns:

```
⚠ 2 items marked as returned but not linked to a return transaction
```

- Shown alongside existing audit warnings (missing prices, tax data, etc.)
- Gives the user a transaction-level view of the problem without needing to inspect each item
- The count updates in real time as items are moved to return transactions

### Requirements

- **MUST** prompt the user to select or create a return transaction when disposition is changed to `'returned'`
- **MUST** allow dismissing the prompt without blocking the disposition change
- **MUST** show a warning badge on items with incomplete returns
- **MUST** show an aggregate incomplete-return count in the audit section
- **MUST** clear all warnings when the item is moved to a return transaction

## Transaction Audit Completeness

### Core Principle

**The audit counts ALL items that were ever part of the transaction** — active items plus any returned or sold items. This is because the transaction's `amountCents`/`subtotalCents` reflects the original purchase total, which included items that have since been returned or sold.

### Completeness Calculation

```typescript
function computeTransactionCompleteness(
  transaction: Transaction,
  activeItems: Item[],
  returnedAndSoldItems: Item[]  // returned + sold, NOT correction
): TransactionCompleteness {
  const allItems = [...activeItems, ...returnedAndSoldItems];

  const itemsNetTotalCents = allItems.reduce(
    (sum, item) => sum + (item.purchasePriceCents ?? 0), 0
  );

  const itemsCount = allItems.length;

  const itemsMissingPriceCount = allItems.filter(
    item => !item.purchasePriceCents || item.purchasePriceCents === 0
  ).length;

  const transactionSubtotalCents = resolveSubtotal(transaction);

  const completenessRatio = transactionSubtotalCents > 0
    ? itemsNetTotalCents / transactionSubtotalCents
    : 0;

  // ... status classification, variance calculation ...
}
```

### Subtotal Resolution Priority

1. Explicit `transaction.subtotalCents` (if > 0)
2. Inferred: `transaction.amountCents / (1 + transaction.taxRatePct / 100)` (if both available)
3. Fallback: `transaction.amountCents` (sets `missingTaxData: true`)
4. `null` return: when no valid subtotal can be computed

### Status Classification

| Status | Condition | Meaning |
|--------|-----------|---------|
| `complete` | Variance within ±1% | Items account for the transaction total |
| `near` | Variance within ±20% | Close to complete |
| `incomplete` | Variance > 20% under | Significant items missing or unpriced |
| `over` | Completeness ratio > 1.2 | Items exceed the transaction total |

### Moved-Out Item Handling in Audit

- **Returned items**: Included in audit total. The original purchase transaction's amount included these items, so the audit must count them to reach completeness.
- **Sold items**: Included in audit total. Same reasoning — the item was part of the original purchase.
- **Correction items**: **Excluded** from audit. Corrections represent data fixes, not real movements — including them would double-count.

### Audit Display with Moved Items

```
AUDIT
  Progress: [████████░░] 85%
  Status: ⚠ Almost complete
  Items: $850.00 / $1,000.00
  Remaining: $150.00
  Note: Includes 1 returned item ($50.00) and 1 sold item ($100.00)
```

The audit section should indicate when returned or sold items contribute to the total, so users understand why the count includes items no longer visible in the active list.

## Lineage Edge System — Complete Reference

### Edge Types and When They Are Created

| Movement Kind | Created By | When | Purpose |
|---------------|-----------|------|---------|
| `association` | Cloud function (`onItemTransactionIdChanged`) | Every time `item.transactionId` changes | Complete audit trail of all transaction linkage changes |
| `sold` | Cloud function (canonical sale request handlers) | Item moves via a canonical sale operation | Records that the movement was a business sale |
| `returned` | App code + cloud function | Item is linked to a return transaction | Records that the movement was a return |
| `correction` | App code | Item is moved between transactions as a data fix | Records that the movement was a correction, not a business event |

### Edge Creation — Dual Path for Returns

Returns create edges from **two sources** for reliability:

1. **App-side** (immediate): When the app assigns an item to a return transaction, it creates a `returned` edge synchronously
2. **Server-side** (trigger): The `onItemTransactionIdChanged` cloud function detects the destination is a return transaction and creates a `returned` edge

**Idempotency**: The lineage system deduplicates edges within a 5-second window, so the dual creation doesn't produce duplicates.

### Edge Queries

| Query | Use Case |
|-------|----------|
| `getEdgesFromTransaction(txId)` | Find all items that LEFT a transaction (for returned/sold sections) |
| `getEdgesToTransaction(txId)` | Find all items that ENTERED a transaction |
| `getItemLineageHistory(itemId)` | Full movement history for a single item |

### Lineage Display (Breadcrumb)

Items show their full lineage path:

```
Inventory → Purchase TX-001 → Return TX-005
```

Or for sold items:
```
Inventory → Purchase TX-001 → Sale TX-003 → Purchase TX-007
```

## Budget Spending Impact

### Sign Conventions

Returns and sales affect budget spending calculations with specific sign rules:

```typescript
function normalizeSpendAmount(tx: Transaction): number {
  if (tx.isCanceled === true) return 0;
  if (typeof tx.amountCents !== 'number') return 0;

  const amount = tx.amountCents;
  const txType = tx.transactionType?.trim().toLowerCase();

  // Returns: NEGATIVE (reduces budget spending — money back)
  if (txType === 'return') {
    return -Math.abs(amount);
  }

  // Canonical sales:
  if (tx.isCanonicalInventorySale && tx.inventorySaleDirection) {
    // project_to_business: NEGATIVE (money back to budget)
    // business_to_project: POSITIVE (money spent from budget)
    return tx.inventorySaleDirection === 'project_to_business'
      ? -Math.abs(amount)
      : Math.abs(amount);
  }

  // Purchases: POSITIVE (money spent)
  return amount;
}
```

### Budget Impact Summary

| Transaction Type | Direction | Budget Impact | Sign |
|-----------------|-----------|---------------|------|
| Purchase | — | Increases spending | `+amount` |
| Return | — | Decreases spending (refund) | `-amount` |
| Canonical sale | `project_to_business` | Decreases spending (item left project) | `-amount` |
| Canonical sale | `business_to_project` | Increases spending (item entered project) | `+amount` |
| Canceled | — | No impact | `0` |

## Transaction Card Display

Transaction cards in list views show type badges:

| `transactionType` | Badge Label | Badge Color |
|-------------------|-------------|-------------|
| `purchase` | Purchase | Green (`#10b981`) |
| `return` | Return | Red (`#ef4444`) |
| (canonical sale) | Sale | Blue (`#3b82f6`) |
| (canonical to-inventory) | To Inventory | Brand primary |

## Feature Requirements (Testable)

### Return Creation

- **MUST** allow creating transactions with `transactionType: 'return'`
- **MUST** allow moving items from purchase transactions to return transactions
- **MUST** auto-set `item.disposition` to `'returned'` when item is linked to a return transaction (unless caller overrides)
- **MUST** create a lineage edge with `movementKind: 'returned'` when item is moved to a return transaction

### Transaction Detail Sections

- **MUST** show active items in the primary items section
- **MUST** show returned items in a separate "Returned Items" section (read-only, dimmed)
- **MUST** show sold items in a separate "Sold Items" section (read-only, dimmed)
- **MUST** hide returned/sold sections when they have zero items
- **MUST NOT** include correction-moved items in returned or sold sections

### Audit Completeness

- **MUST** include active, returned, and sold items in completeness calculation
- **MUST NOT** include correction-moved items in completeness calculation
- **MUST** resolve subtotal using the priority chain: explicit subtotal → inferred from tax → fallback to amount
- **SHOULD** indicate to users when returned or sold items are contributing to the audit total

### Lineage

- **MUST** create `association` edges on every `item.transactionId` change (via cloud function)
- **MUST** create `returned` intent edges when items move to return transactions
- **MUST** create `sold` intent edges when items move via canonical sale operations
- **MUST** deduplicate edges within a 5-second window

### Budget Spending

- **MUST** treat return transaction amounts as negative (reducing budget spending)
- **MUST** treat canceled transaction amounts as zero
- **MUST** apply correct sign for canonical sale directions

## Current State (Mobile App)

### Implemented

| Feature | Status | Location |
|---------|--------|----------|
| Transaction type field (`transactionType`) | Exists on model | `src/data/transactionsService.ts` |
| Item disposition values | Defined | `src/constants/itemStatuses.ts` |
| Transaction card type badges | Implemented | `src/components/TransactionCard.tsx` |
| Canonical sale flows (A, B, C) | Implemented | `src/data/inventoryOperations.ts` |
| `sold` lineage edges | Implemented (cloud functions) | `firebase/functions/src/index.ts` |
| `returned` lineage edge detection | Implemented (cloud function trigger) | `firebase/functions/src/index.ts` |
| `association` edge trigger | Implemented (cloud function) | `firebase/functions/src/index.ts` |
| Budget spending sign normalization | Implemented | `src/data/budgetProgressService.ts` |
| Audit completeness calculation | Implemented (active items only) | `src/utils/transactionCompleteness.ts` |
| Audit section in transaction detail | Implemented (basic) | `app/transactions/[id]/sections/AuditSection.tsx` |
| Transaction list type filtering | Implemented | `src/components/SharedTransactionsList.tsx` |

### Not Yet Implemented

| Feature | Priority | Notes |
|---------|----------|-------|
| "Move to Return Transaction" item action | High | Needs item action menu entry + transaction picker |
| Returned Items section in transaction detail | High | Needs lineage edge query + separate UI section |
| Sold Items section in transaction detail | High | Same as above, filtering on `movementKind: 'sold'` |
| Audit includes returned and sold items | High | `computeTransactionCompleteness` must query lineage edges and include returned/sold items |
| Incomplete return detection (3-layer) | High | Disposition prompt, item warning badge, audit section flag |
| Auto-set disposition to `'returned'` on return link | Medium | App-side logic when linking item to return transaction |
| App-side `returned` edge creation | Medium | Supplement to server-side trigger for immediate feedback |
| Lineage breadcrumb display on items | Low | Shows full movement path: Inventory → TX-001 → TX-005 |
| Bulk move to return transaction | Low | Select multiple items → move to return transaction |

## Implementation Guidance

### Phase 1: Return Item Flow + Disposition

1. Add "Move to Return Transaction" action to item context menus (transaction detail view)
2. When item is linked to a return transaction:
   - Update `item.transactionId` to return transaction ID
   - Set `item.disposition` to `'returned'` (auto, unless overridden)
   - Create `returned` lineage edge (app-side, for immediate feedback)
3. The existing cloud function trigger handles server-side edge creation as a safety net

### Phase 2: Returned/Sold Item Sections

1. Query lineage edges from the current transaction: `getEdgesFromTransaction(txId)`
2. Partition edges by `movementKind`:
   - `returned` → fetch items → render in "Returned Items" section
   - `sold` → fetch items → render in "Sold Items" section
   - `correction` → exclude
3. Render sections below active items, read-only, dimmed

### Phase 3: Audit Completeness with Moved-Out Items

1. Extend `computeTransactionCompleteness` to accept returned and sold items
2. Query lineage edges from the transaction
3. Fetch returned/sold item records (may no longer be in `transaction.itemIds`)
4. Include in completeness calculation (sum prices, count items)
5. Update UI to indicate when returned or sold items contribute to the total

### Phase 4: Lineage Breadcrumb

1. Query full lineage history for an item
2. Build ordered path from edges
3. Display in item detail view as clickable breadcrumb trail

## References

- **Canonical sale system**: [canonical_sale_system.md](canonical_sale_system.md)
- **Transaction audit**: [transaction_audit_spec.md](transaction_audit_spec.md)
- **Reassign operations**: [reassign_spec.md](reassign_spec.md)
- **Lineage edges spec**: `.cursor/plans/firebase-mobile-migration/40_features/inventory-operations-and-lineage/flows/lineage_edges_and_pointers.md`
- **Legacy web app reference**: `/Users/benjaminmackenzie/Dev/ledger` (TransactionDetail.tsx, inventoryService.ts, lineageService.ts)

## Open Questions

1. **Should the audit section show separate subtotals for active vs. returned/sold items?** The legacy app uses a single combined total. A breakdown could help users understand why completeness is higher than expected when many items have been returned.

2. **How should bulk returns work?** Select multiple items → move all to a return transaction. Should this be a dedicated bulk action or reuse the existing "move to transaction" flow?

3. **Should returned items reduce the audit's target subtotal?** Currently, the audit compares items total to the original transaction subtotal. If items are returned, the vendor refund (return transaction amount) could offset the target. This is a design decision about whether audit tracks "original completeness" vs "net completeness."

4. **Item lineage breadcrumb — where to display?** Options: item detail hero card, a dedicated lineage section, or both.
