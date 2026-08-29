# Inventory Movement Transactions

> **Status:** Active. Replaces the legacy "canonical sale" model documented in [canonical-sales.md](canonical-sales.md). The Purchase-from-Inventory category-reclassification behavior below was approved on 2026-08-25 and is implementation-pending.

## Overview

When items move between business inventory and a project, the system creates a per-batch **inventory movement transaction** to represent the financial impact on the project's budget. Inventory → project is a **Purchase** from inventory. Project → inventory acquisition is a **Sale** to inventory. This document is the source of truth for how these per-batch inventory movements work.

## The Per-Batch Model

An ordinary Sell from inventory into a project creates **one new purchase transaction**. Return to Project instead restores the original category per item, so a bulk return creates one Purchase per represented original category in the same atomic batch. Each transaction has an initial active item list. Configurable Sell amounts derive from sold items' project prices; Return-to-Project amounts come from immutable inventory-entry accounting snapshots. If an active ordinarily sold item's project price later changes before the existing paid-invoice freeze boundary, Ledger adjusts this project-side Purchase total by that item's price delta. Before collection, a user may also reclassify the entire Purchase to another project-enabled itemized category; Ledger updates the Purchase and all currently attached items atomically. If items later leave through return or sale, they are removed from `itemIds` and preserved through lineage.

This is different from the legacy canonical-sale model, where one long-lived transaction per `(project, direction, category)` triple aggregated every inventory movement over time. The legacy model is preserved for historical data — see "Legacy Canonical Sales" below.

### Why per-batch

- **Aggregator drift avoided.** Each movement is a per-batch document instead of a shared long-lived aggregator. Source `itemIds` still update for normal return/sale membership changes.
- **Accounting-correct.** Structural movement fields and departed/paid item amounts remain historical. An open project-side Purchase may follow deliberate repricing of an item that is still attached to that sale.
- **Matches user mental model.** "I bought these five things from inventory for Hawaii under Furnishings" = one transaction. Not "this category in this project has accumulated $X of inventory transfers."
- **Atomic failure.** A failed batch fails as a unit. There's no partial state where some items moved and others didn't.

## Movement Direction

Inventory movements go in **both directions** between business inventory and a project:

1. **Business inventory → project** is a `Purchase` from inventory. Items leave inventory and land in the project with a `budgetCategoryId`. The project's budget for that category increases.
2. **Project → business inventory** is a `Sale` to inventory only when items **originated in the project** and the business is acquiring them into inventory. The project's budget decreases. This is distinct from a Return — Returns are reserved for items that came from inventory and are going home.

Direction is not stored as a dedicated field. It is **implicit in the transaction shape**:

| Direction | `type` | `source` | `budgetCategoryId` | Project's budget |
|---|---|---|---|---|
| Inventory → Project | `Purchase` | inventory label | set (destination category) | **increases** |
| Project → Inventory | `Sale` | inventory label | set (source category) | **decreases** |

Item category and transaction category are different concepts. Inventory items have no category, so item `budgetCategoryId` is wiped when the item lands in inventory. The Sale transaction still carries `budgetCategoryId` as frozen source-project accounting attribution.

**Item origin governs which direction applies for project → inventory moves.** Resolve origin from durable accounting provenance, in order: (1) the item's current project-scoped Purchase, where an inventory-label source proves inventory origin and a vendor source proves project origin; (2) sold lineage entering the current project, which proves inventory origin; (3) `currentSource` versus `source` only as a legacy fallback. If none of those resolves the origin, non-interactive tooling must block instead of guessing. Inventory-originated items go back via Return; project-originated items go via Sale-to-Inventory. See [reassign-vs-sell.md](reassign-vs-sell.md) for UI routing and [inventory-as-store.md](inventory-as-store.md) for the semantic model.

**Project → inventory price basis is origin-aware.** An inventory-originated item goes home through a Return that reverses normalized `projectPriceCents`. A project-originated item enters inventory through a Sale-to-Inventory at `purchasePriceCents`. This distinction is defensive: the business must not overpay if a project-originated item has an incorrectly elevated project price.

## Inventory Purchase Transaction Shape

```typescript
interface InventoryPurchaseTransaction {
  type: "Purchase";
  projectId: string;                    // destination project
  budgetCategoryId: string;             // destination category
  amountCents: number;                  // project-price basis; server-maintained while open
  itemIds: string[];                    // active membership, length 0..100 after returns/sales
  source: "[Account] Inventory";        // inventory label, the non-project side
  notes?: string;                       // optional audit note
  createdAt: Timestamp;
  updatedAt: Timestamp;
  createdBy: string;                    // Firebase Auth uid
}
```

**Auto-generated ID.** No deterministic ID formula. The transaction document ID is a Firestore auto-ID.

**Removed fields.** New per-batch inventory purchases and sale-to-inventory transactions do NOT have `isCanonicalInventorySale` or `inventorySaleDirection`. Those fields exist only on legacy canonical sales.

## Invariants

The following invariants are enforced by Firestore security rules and by tests in both iOS and the MCP server:

1. **Controlled accounting mutation after creation.** `type`, `source`, and `projectId` cannot be updated on an inventory movement transaction after it is created. Clients cannot directly edit movement `amountCents`, `subtotalCents`, or `budgetCategoryId`. Trusted workflows have two narrow exceptions: the item-price trigger may adjust amount/subtotal for an attached item under its existing paid-invoice freeze rule; and the dedicated category-reclassification operation may change `budgetCategoryId` for an eligible uncollected project-side Purchase-from-Inventory while atomically updating its currently attached items. Mutable client fields include `itemIds`, `notes`, `status`, and `updatedAt`. `itemIds` is current active membership; lineage carries returned/sold historical membership.
2. **Batch size cap.** Initial `itemIds.length >= 1 && itemIds.length <= 100`. Later returns/sales can reduce `itemIds` to zero on the source transaction. Both clients enforce the initial cap locally; the cap exists because Firestore batch writes have a 500-doc limit and a 100-item movement touches ~305 docs.
3. **Non-negative amount.** `amountCents >= 0`.
4. **Direction is type/source-derived.** `type == "Purchase"` with an inventory source is inventory → project. `type == "Sale"` with an inventory source is project → inventory acquisition. No dedicated direction field is written for new per-batch movements.
5. **Category must be project-enabled and itemized for configurable Sell.** The selected account `BudgetCategory` must be active, non-system, and have canonical `metadata.categoryType == "itemized"`. A matching `ProjectBudgetCategory` must already exist in the destination project. Sale and reclassification pickers show only categories satisfying all of these conditions; these workflows do not auto-enable a category. Return to Project is the narrow exception: it restores and re-enables the recorded original category rather than asking the user to choose a new one.
6. **One accounting category per transaction.** Inventory → project purchases use one destination `budgetCategoryId`. Source project egress transactions use one source `budgetCategoryId`; mixed source categories are split into separate first-hop transactions.

## The Sell Flow

When a user purchases items from business inventory into a project:

### 1. Collect inputs from the user

- **Items.** A list of business-inventory items (each must have `projectId == null`).
- **Destination project.**
- **Budget category.** One active, non-system, itemized category, applied to every item in the batch (per invariant 5). It must already be enabled in the destination project.
- **Optional notes.**

### 2. Pre-flight validation

- Every item must have `projectId == null` (in business inventory). If any item is in a project, fail with a clear error.
- Item count must be 1..100.
- Destination project must exist.
- Budget category must be an active, non-system account category with `metadata.categoryType == "itemized"` and must already exist as a `ProjectBudgetCategory` in the destination project. Otherwise reject and require the user to choose from the project-enabled itemized categories.
- Every item must resolve to a positive project price. Ledger first applies the canonical item price floor, raising `projectPriceCents` to `purchasePriceCents` whenever it is missing, zero, or lower. An already higher project price is preserved. If neither price is positive, the UI asks the user what to sell it for and non-interactive callers reject the operation.

### 3. Compute the initial amount

```
resolvedProjectPrice(item) = max(projectPriceCents ?? 0, purchasePriceCents ?? 0)
amountCents = sum(resolvedProjectPrice(item)) for item in items
```

Inventory → project movements use the project-price basis because this is the amount charged to the destination project/client. A project price below purchase cost is raised to purchase cost; otherwise the higher project price is preserved. If neither price is positive, the UI asks the user what they want to sell it for. The resolved value is written to `projectPriceCents` before or atomically with the movement.

### 4. Build the Firestore batch

One batch, all-or-nothing:

1. **Create the Purchase transaction** at `accounts/{accountId}/transactions/{auto-id}` with the shape above.
2. **For each item:** update at `accounts/{accountId}/items/{itemId}`:
   - `projectId` = destination project ID
   - `budgetCategoryId` = the chosen category
   - `transactionId` = the new purchase transaction ID
   - `status` = `"purchased"`
   - `spaceId` = validated per-item destination assignment when supplied; otherwise null
   - `updatedAt` = serverTimestamp()
3. **Create one `sold` lineage edge per item** at `accounts/{accountId}/lineageEdges/{auto-id}`:
   - `itemId`
   - `fromProjectId`: null (item was in business inventory)
   - `toProjectId`: destination project
   - `fromTransactionId`: the item's prior `transactionId` if any
   - `toTransactionId`: the new purchase transaction
   - `movementKind`: `"sold"`
   - `createdBy`, `createdAt`

4. **Commit.** Single `batch.commit()`. If any write fails, the whole batch rolls back.

### 5. Side effects (server-side, automatic)

- The `onItemTransactionIdChanged` Cloud Function fires for each item, creating an `association` lineage edge as the audit trail. (Already exists, no change needed.)
- The `onTransactionWritten` Cloud Function fires for the new Purchase transaction and recalculates the destination project's budget summary.

## The Return-to-Project Flow

Return to Project is a reversal of Sale-to-Inventory, not a configurable sale. It is available only while every selected project-originated item is in inventory and its current active Sale-to-Inventory transaction proves the same source project. The confirmation UI does not offer project, category, or price controls. An inventory-originated item that came home through Return is ordinary sellable inventory and is ineligible.

When an item moves from a project into inventory, the item stores an immutable snapshot of that movement's transaction ID, source project, source budget category, accounting price, and tax-inclusive amount. Return to Project uses those values only for a current Sale-to-Inventory acquisition, even if mutable item prices change later. A Return entry may preserve its project-price-plus-tax snapshot for audit, but it does not qualify the item for Return to Project. A Sale-to-Inventory entry snapshots purchase cost. A pre-snapshot Sale-to-Inventory item is accepted only when a single-item source movement stores an exact subtotal and amount. Ambiguous legacy allocations are blocked until verified snapshots are backfilled; Ledger never recalculates a historical return amount from mutable item fields.

The atomic writer groups selected items by their recorded original category and creates one Purchase-from-Inventory per category. Each Purchase restores the recorded subtotal and amount, each item returns to the recorded project/category, source transaction membership is removed, and lineage is written in the same batch. The original category is restored even if it is not currently enabled; the same batch re-enables its project category record. If provenance changes between presentation and confirmation, the operation fails rather than guessing.

## Purchase Category Reclassification

Category reclassification is an accounting correction for the **entire** per-batch Purchase. It is not a per-item edit and does not split a transaction.

### Eligibility

The operation is available only when all of the following are true:

- The transaction is a non-legacy, project-scoped `Purchase` whose source exactly matches the account's derived inventory label; a suffix-only match is not sufficient authorization.
- The transaction is not canceled.
- The target category is already enabled in the same project and its account category is active, non-system, and canonically itemized.
- No affected invoice source has been collected. A paid invoice or an active settlement/payment transaction for an affected line is a collection lock. Canceled invoices and canceled settlement transactions do not lock the correction.

### Atomic write contract

One trusted operation must atomically:

1. Re-read and validate the transaction and expected current category.
2. Set the Purchase `budgetCategoryId` to the target category.
3. Resolve current membership from both `Purchase.itemIds` and the reverse item `transactionId` association, require the ID sets and project scopes to match exactly, and set the same category on every resulting item.
4. Keep any created or sent, uncollected invoice line category snapshots for affected sources aligned with the new category.
5. Write a structured audit event containing actor, request ID, transaction ID, project ID, previous category, target category, affected active item IDs, and timestamp.

The operation must fail without writes if membership is stale, the target is ineligible, or collection has locked any affected source. Direct client writes to movement `budgetCategoryId` remain prohibited; iOS and MCP use this dedicated operation.

### What changes and what does not

- The Purchase's **entire stored amount** moves from the old budget category to the new one. This includes the Purchase contribution of items that later left through return or sale.
- Currently attached items receive the new category so item and transaction attribution cannot drift.
- Departed items keep their current category/scope, and downstream movement transactions are not rewritten.
- `amountCents`, `subtotalCents`, prices, `projectId`, `source`, `type`, dates, status, membership, lineage, and the original vendor Purchase do not change.
- The existing project budget-summary trigger moves the Purchase amount between the old and new category rollups after commit.

Changing the category for only a subset of a multi-item Purchase requires an explicit transaction-splitting correction and is out of scope for this operation.

## Project → Project Moves

Moving items from one project to another is a **two-hop** operation in a single atomic batch. The first hop is origin-aware:

1. **First hop (per-item, per origin):**
   - Items resolved as inventory-originated → a **Return** transaction against the source project.
   - Items resolved as project-originated → a **Sale-to-Inventory** transaction (`type: "Sale"`, source `budgetCategoryId`) against the source project.
   - Mixed batches produce **both** first-hop transactions in the same Firestore batch.
2. **Second hop:** one **Purchase-from-Inventory** transaction (`type: "Purchase"`, with `budgetCategoryId`) against the destination project. Covers every item in the batch.

The iOS UI presents this as a single "move to project" action. The service layer issues all hops in one atomic Firestore batch. Lineage edges link each hop.

The destination category is collected from the user — items don't carry a category through the inventory hop. Before commit, every item's project price is normalized to at least its purchase price. The UI asks what to sell it for, and MCP/tooling callers reject, only when neither price is positive.

## Lineage Edges

Every inventory → project purchase creates one `sold` lineage edge per item. See [lineage-tracking.md](lineage-tracking.md) for the edge schema.

For project→project moves, **two** edges are created per item:
- A `returned` edge from the source project to the return transaction.
- A `sold` edge from inventory to the destination purchase transaction.

Together they record the full path: source project → inventory → destination project.

## Amount Calculation

The inventory movement transaction's initial `amountCents` is computed at creation time:

| Movement | Price basis |
|---|---|
| Inventory → project Purchase | Project price (`projectPriceCents`) |
| Return to Project Purchase | Immutable inventory-entry price and amount, restoring the original project/category movement |
| Project → inventory Sale-to-Inventory | Purchase cost (`purchasePriceCents`) |
| Return to inventory | Effective project-sale price (`max(projectPriceCents, purchasePriceCents)`), reversing the inventory→project Purchase |
| Project → project source exit | Origin-aware: Return at project price; Sale-to-Inventory at purchase cost |
| Project → project destination Purchase | Project price (`projectPriceCents`) |

```
projectPriceSubtotalCents = sum(max(item.projectPriceCents ?? 0, item.purchasePriceCents ?? 0))
projectPriceAmountCents = sum(round(effectiveProjectPriceCents * (1 + taxRatePct / 100)))
saleToInventoryAmountCents = sum(item.purchasePriceCents ?? 0)
```

The transaction type records both origin and financial meaning:

- An inventory-originated `Return` must reverse the amount the project was charged, including markup, rather than merely crediting supplier cost.
- A project-originated `Sale` represents the business acquiring the item from the project. It uses purchase cost even if `projectPriceCents` is unexpectedly higher; the project-price floor is not relied upon as a safety mechanism.
- A project → project batch may therefore have Return and Sale source legs with different price bases, followed by one destination Purchase at normalized project price.

For project-price movements, `subtotalCents` excludes tax and `amountCents` includes per-item tax when recorded. Sale-to-Inventory acquisition amount and subtotal both equal purchase cost.

After creation, most movement totals remain frozen. The exception is the destination project's Purchase-from-Inventory: when an item remains attached to that transaction and is not on a paid invoice, changing its effective project price adjusts `subtotalCents` by the item's project-price delta and `amountCents` by the corresponding tax-inclusive delta. The original vendor Purchase, Return/Sale-to-Inventory records, transactions the item has left, and paid invoice history never change.

The adjustment is delta-based rather than a fresh sum of `transaction.itemIds`. `itemIds` represents current active membership and may omit items that left later; recomputing the entire transaction from it would incorrectly erase historical contributions. Server event IDs are deduplicated atomically so retries cannot apply a delta twice.

Before a project-price movement, Ledger persists `projectPriceCents = max(projectPriceCents ?? 0, purchasePriceCents ?? 0)`. If neither price is positive, the UI must collect a price and non-interactive tools reject the call.

## Sign Convention

| Transaction | Multiplier on project budget | Effect |
|---|---|---|
| Purchase, inventory → project (`type: "Purchase"`, `budgetCategoryId` set, inventory source) | +1 | Adds to project spend (destination category) |
| Sale, project → inventory (`type: "Sale"`, source `budgetCategoryId`) | –1 | Items leave the project; item-level category is wiped on the item |
| Return (`type: "Return"`) | –1 | Subtracts from project spend; items leave |
| Legacy canonical sale (`isCanonicalInventorySale: true`) | direction-based | See "Legacy Canonical Sales" below |

The sign convention is centralized in [mcp-server/src/util/budget.ts](../../mcp-server/src/util/budget.ts) `normalizeSpendAmount`. Any new reader must consult this function rather than reimplement the convention.

## Display — Naming Convention

Inventory movement direction is rendered in the transaction's **display name**, from the project's point of view. There is no direction badge — direction lives in the name.

| Direction | Display name | Example |
|---|---|---|
| Inventory → Project (Purchase with `budgetCategoryId`) | `Purchase from [source]` | `Purchase from 1584 Design Inventory` |
| Project → Inventory (Sale with source `budgetCategoryId`) | `Sale to [source]` | `Sale to 1584 Design Inventory` |
| Return to inventory (`type: "Return"`) | `Return to [source]` | `Return to 1584 Design Inventory` |
| Return to vendor (`type: "Return"`) | `Return to [source]` | `Return to Wayfair` |

Resolution is implemented in `TransactionDisplayCalculations.displayName(for:)` and mirrored in `SearchCalculations.transactionDisplayName(for:)` for search cards.

**Other display:**
- **Type badge:** "Purchase", "Sale", or "Return" (type only — never direction).
- **Source field:** the inventory label for inventory-involved transactions, the vendor name for vendor transactions.
- **Amount:** the stored `amountCents`; for an open Purchase-from-Inventory it follows eligible sold-item project-price changes.
- **Items:** current active items rendered from `itemIds`; items that left via return/sale render from lineage sections.

Inventory movement transactions are NOT directly user-editable for accounting shape or totals. Users edit the sold item's project price; the trusted server trigger maintains the eligible project Purchase amount. Users can edit `notes` and add/cancel via `status`; inventory flows may update `itemIds` as items leave via return/sale.

### Transaction List Grouping

Transaction lists visually group inventory-movement records so the list reads as movement activity per project/category rather than a stream of per-batch documents. This grouping is **presentation-only**:

- The underlying Sale, Return, and Purchase documents remain separate auditable records. Their identity fields are frozen; only an eligible project Purchase-from-Inventory total has the controlled repricing exception described above.
- Transaction detail always opens the real child transaction.
- Bulk selection, export, and totals operate on the child transaction IDs.
- No grouped row is written back to Firestore and no grouped row becomes a canonical aggregate.

Groupable records:

| Record | Group row | Notes |
|---|---|---|
| Inventory purchase/acquisition (`type: "Purchase"`, `projectId: null`) | `Added to Business Inventory` | Groups inventory-scope acquisition purchases by vendor/type. |
| Inventory → project Purchase (`type: "Purchase"`, `budgetCategoryId` set) | `From [inventory label]` | Groups by inventory label, project, category, and transaction type. |
| Project -> inventory Sale (`type: "Sale"`, source `budgetCategoryId`) | `Sold to [inventory label]` | Groups by inventory label, project, category, and transaction type. |
| Return to inventory (`type: "Return"`, inventory-label source) | `Returned to [inventory label]` | Vendor returns are excluded; only inventory-label returns are grouped. |

The grouping key includes movement direction, source/inventory label, project ID, budget category ID, and transaction type. **Date is not part of the key** — all matching batches collapse into a single row regardless of when they happened, so a project that pulls from inventory across many days shows one card per (direction, source, category). Charges and credits must not be collapsed into a misleading net row; that's why direction and type are part of the key.

The group's displayed date is the most recent `effectiveSortDate` among its child transactions.

## Legacy Canonical Sales

Existing sale transactions written under the canonical-sale model remain in the data as read-only historical records. They are identified by the field `isCanonicalInventorySale: true` and have an `inventorySaleDirection` field of either `"business_to_project"` or `"project_to_business"`.

**Reading legacy canonical sales:**
- Their amounts are frozen (the `onItemPriceChanged` recalc has been removed).
- They display normally in transaction lists.
- Their sign convention follows the original direction-based rule (see [budget-management.md](budget-management.md) Sign Conventions).
- They remain mutable for narrow operations (`cancel_transaction` updates `status`); the new immutability rules carve them out via `isCanonicalInventorySale: true`.

**No migration.** Legacy canonical sales are not converted to per-batch shape. The dual-read path in `util/budget.ts` is the maintenance cost of preserving them. If the volume becomes problematic, a one-time migration script can be considered as a follow-up.

**Why preserve them:** rewriting historical financial records is risky. Freezing them is the safe move. The new shape applies only to inventory movement records created after this taxonomy correction ships.

## Edge Cases

1. **Inventory → project item with a missing or below-cost project price.** Ledger raises it to the positive purchase price automatically. The movement requires user input only when neither price is positive. The normalized value is persisted on `item.projectPriceCents` and used for the Purchase amount.
2. **Inventory-originated Return with no explicit project price.** The project-price floor uses a positive purchase price. If neither price is positive, the item contributes $0 but remains in `itemIds` and still receives a lineage edge.
3. **Project-originated Sale with a higher project price.** The Sale still uses `purchasePriceCents`; malformed markup must not increase what the business pays.
4. **Movement with 0 total amount.** Allowed when the selected origin-aware price basis has no positive value.
5. **Category not enabled in destination.** Pre-flight validation rejects with a clear error. UI prompts user to enable or pick a different category.
6. **Item already in destination project.** Pre-flight validation rejects — the purchase-from-inventory flow only accepts inventory items.
7. **Concurrent moves of the same item.** Firestore batch atomicity handles this: whichever batch commits second will fail because the item's `projectId` no longer matches inventory state. The user sees a "stale data" error and refreshes.
8. **Cancellation.** Setting `status: "canceled"` on an inventory movement transaction excludes it from budget calculations. The transaction remains in the data; items are not automatically reverted. Manual cleanup via `update_item` if needed.
9. **Project price edited after collection.** Paid invoice lines and their associated project Purchase amount remain historical. The item editor disables ordinary project-price editing for paid items; privileged or legacy writes do not rewrite the collected movement.
