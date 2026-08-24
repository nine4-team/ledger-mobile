# Vendor Credits

**Status:** Proposed — no implementation or migration is authorized by this document.

## Purpose

Ledger currently uses `Return` for any negative vendor event. That is wrong for
an order line a vendor cancels before the project receives it: no physical item
was sent back. This spec adds a general-purpose **Credit** transaction for a
vendor-issued reduction of a prior purchase, beginning with cancellation
credits.

The design deliberately distinguishes two questions:

1. Did money come back from the vendor? A credit records that financial event.
2. Did a physical item leave the project? A return records that physical
   disposition.

Those answers may both be yes in a physical return, but they are not the same
event and must not be inferred from each other.

## Decision

Add canonical transaction type `Credit`.

`Credit` is a negative vendor transaction, stored with a positive
`amountCents` and a negative budget effect, like `Return`. It is not a
synonym for a client invoice credit or a payment reversal.

The first required reason is `cancellation`. The UI calls this **Vendor
Cancellation Credit**. The model is intentionally broader so later credits
(price adjustment, courtesy credit, etc.) do not require another transaction
type.

Do not relabel or migrate existing `Return` rows merely because their notes
describe a cancellation. Historical rows remain intact unless a separately
approved migration has complete source evidence.

## When to use Credit versus Return

| Situation | Transaction | Item disposition |
|---|---|---|
| Vendor canceled one or more lines; the project never received them | `Credit` with `creditReason: cancellation` | `canceled` |
| Vendor refunded a price difference or issued a courtesy amount; no item changed hands | `Credit` with its applicable reason | Items remain `purchased` |
| Project sent merchandise back to vendor or business inventory | `Return` | `returned` |
| Entire order was canceled and no valid purchase remains | Unsupported in v1. Do not create a Credit and do not cancel the Purchase through this feature. Use a future dependency-aware whole-order cancellation workflow. | No change |

The v1 write rejects a selection equal to all remaining active lines on the
Purchase. If the Purchase contains other fulfilled or still-valid lines, it
must remain active and the canceled portion is a linked Credit. A partial
credit is never evidence that the whole order was canceled.

## Data model

### Transaction

Extend the canonical `type` enum with `Credit`. New server-owned writes persist
the exact string `Credit`. Readers remain case-insensitive because existing
data and the iOS enum use lowercase raw values while MCP-created canonical
events currently use title case. Do not normalize or rewrite legacy rows.

A Credit has the ordinary project/vendor/category/amount fields plus:

| Field | Type | Rule |
|---|---|---|
| `creditReason` | enum | Required for `Credit`; persisted lower-camel value: `cancellation`, `priceAdjustment`, `courtesy`, or `other` |
| `creditedTransactionId` | string | Required for `creditReason: cancellation`; references the original active Purchase |
| `itemIds` | string[] | Required for cancellation credits; each item must be a line from `creditedTransactionId` |
| `amountCents` | positive integer | Actual amount credited by the vendor, including tax and any fee/discount effects |
| `subtotalCents` | non-negative integer | Gross merchandise amount being credited before discount, adjustment, and tax |
| `discount.amountCents` | non-negative integer | Existing representation; a positive discount reduces credited merchandise |
| `adjustmentCents` | signed integer | New field; positive increases the credit and negative represents a deduction. Require `adjustmentExplanation` when non-zero |
| `adjustmentExplanation` | string | Required when `adjustmentCents != 0`; source-supported explanation such as promotional adjustment or shipping deduction |
| `taxCents` | non-negative integer | New field; actual tax credited. Prefer this exact amount over inferring tax from a rate |
| `taxRatePct` | number | Optional informational source value; it is not used to override `taxCents` |

For Credit writes, enforce
`amountCents == subtotalCents - discount.amountCents + adjustmentCents + taxCents`.
Omitted discount, adjustment, and tax are zero. The result must be positive.
This signed adjustment model is required for v1; notes alone and the existing
positive-only `discount` field cannot faithfully represent both additions and
deductions. Never change `purchasePriceCents` to make this equation pass.

`Credit` has the same itemized-category requirement as `Return`. It cannot
settle an invoice and cannot be used for a client-facing credit.

### Item and lineage

Add item status `canceled` for a purchase line canceled before possession.

For a cancellation credit, write atomically:

1. remove each canceled item from the original Purchase's active `itemIds`;
2. add it to the Credit's `itemIds`;
3. set its status to `canceled` and its current transaction to the Credit;
4. create a lineage edge with `movementKind: credited`, from the Purchase to
   the Credit.

Persist `credited` exactly in lowercase. Add `creditReversed` for the reversal
edge described below. Both are additive enum values; existing `association`,
`returned`, `sold`, `soldToInventory`, `correction`, and `transferred` readers
remain valid. The automatic item-transaction trigger will also produce its
ordinary `association` edge; it must recognize Credit without incorrectly
adding a `returned` edge.

`credited` is a financial-resolution edge, not a physical scope move. It must
not change an item's project, budget category, original source, or inventory
location. A canceled line is excluded from active-item counts and cannot later
be returned, sold, or moved without an explicit reversal workflow.

The original Purchase audit must include `credited` items in its resolved
merchandise subtotal, just as it includes returned and sold items. Extend the
persisted audit object with `creditedItemsSumCents` and
`creditedItemsCount`; retain the existing meanings of `itemsSumCents`,
`linkedItemsSumCents`, returned fields, and sold fields. MCP transaction detail
adds a separate `creditedItems` array. This keeps partial cancellation from
making a valid mixed order appear incomplete without relabeling it as a return.

### Accounting and reports

Budget normalization gives active Credits a `-1` multiplier. Canceled Credits,
like all canceled transactions, contribute zero. All report, search, project
summary, and MCP readers must recognize `Credit`; none may silently treat it as
a Purchase.

The purchase remains the gross order event and the Credit is the documented
offset. Reports should show both, with an optional net amount, rather than
hiding the original purchase.

## Validation and invariants

- A cancellation Credit must point to one active Purchase in the same project,
  vendor, and itemized category.
- Every credited item must be an active line on that Purchase and must not have
  a terminal `returned`, `sold`, or `credited` lineage edge.
- A linked Purchase may contain unrelated fulfilled items. Those items are not
  changed.
- A Credit may not use `status: canceled` to mean a vendor cancellation. That
  status means the *credit record itself* was voided. `creditReason` describes
  why the vendor issued it.
- The original purchase may be canceled only when evidence supports cancellation
  of every line and no dependent movement, invoice, or payment remains. That
  operation is explicitly outside v1; the vendor-credit writer always rejects
  a credit that would leave the source Purchase with no active items.
- Writes must preserve source prices. A mismatch between item subtotal and
  credit amount is surfaced with its source-supported tax, discount, fee, or
  adjustment explanation; it is never resolved by editing item prices.

## User experience

### Creation flow

From an eligible Purchase, expose **Record vendor credit** as a separate action
from **Return items**. Pre-fill vendor, project, category, and the original
Purchase link. The user selects the affected order lines and the reason.

For `Cancellation / unavailable`, the form requires the original Purchase and
at least one selected line. It shows the remaining valid lines on that order so
the user can verify that the action is partial, not a full-order cancellation.

The financial section shows:

- merchandise subtotal from selected lines;
- transaction-level discount or adjustment, if source-supported;
- tax; and
- actual vendor credit amount.

If the amount does not reconcile, show the variance and require a short
explanation/source attachment before save. The source attachment is required
for a non-zero adjustment and recommended for every cancellation. Do not
change line prices. A non-zero unexplained variance disables Save; it is not a
warning that can be bypassed.

### Display

- Transactions list/detail: show **Vendor cancellation credit** (or the
  appropriate credit reason), never the Return label.
- Original Purchase detail: show a linked **Credited items** section distinct
  from **Returned items** and **Sold items**.
- Item detail: show `Canceled by vendor` and the linked credit; do not show a
  return disposition.
- Search, filters, exports, and reports: include a Credit type/filter and
  reason label. Budget summaries display it as a negative vendor amount.

## Implementation plan

### Compatibility and exact persisted shape

- Add iOS `.credit` with raw value `credit`; decoding remains case-insensitive.
  Add `.canceled` to `ItemStatus` with persisted value `canceled`.
- Add MCP read/write enum value `Credit`, item status `canceled`, movement
  kinds `credited` and `creditReversed`, and reason values listed above.
- New writes use Firestore field `type` (not `transactionType`) and exact value
  `Credit`, matching the current document schema and MCP convention. Existing
  aliases and legacy values remain read-only compatible.
- `itemIds` continues to mean current active membership. The canceled items
  leave the Purchase and enter the Credit; historical Purchase membership is
  recovered through lineage. `Item.transactionId` remains a cache
  back-reference and is updated to the Credit, never used as the authority for
  selecting source lines.
- Credit shape fields `type`, `creditReason`, `creditedTransactionId`,
  `projectId`, `budgetCategoryId`, `source`, `amountCents`, `subtotalCents`,
  `discount`, `adjustmentCents`, `adjustmentExplanation`, `taxCents`, and
  `itemIds` are not generally editable. Only the dedicated record/reverse
  operations may change active membership.

### Write path and atomicity

Do not compose this operation from `createTransaction`, `create_transaction`,
`return_items`, generic item updates, or a client `WriteBatch`. Those paths do
not atomically read and validate current membership and can double-credit under
concurrency.

Implement one server-owned `recordVendorCredit` callable operation for iOS and
one MCP `record_vendor_credit` tool with the same request/result contract. Each
uses a Firestore **read/write transaction**, not a blind batch:

1. authenticate account membership and pre-allocate the Credit and deterministic
   lineage document IDs;
2. transactionally read the source Purchase, selected items, itemized category,
   and relevant terminal lineage/dependency records;
3. validate active Purchase status, exact same project/vendor/category, source
   `itemIds` membership, item cache links, allowed statuses, positive/reconciled
   amounts, no terminal edge, and at least one unselected active source line;
4. create the immutable Credit, remove selected IDs from the Purchase, update
   each item to `status: canceled` and `transactionId: creditId`, and create one
   `credited` edge per item in the same transaction;
5. return the new Credit ID and affected item IDs. Cloud Functions recompute
   source/Credit completeness and budget summaries after commit; they are
   derived results, not part of the correctness boundary.

Use a client-generated `operationId` as the Credit document ID/idempotency key.
A retry with the same ID and identical payload returns the prior result; a
different payload conflicts. Cap v1 at 100 items so transaction reads/writes
stay below Firestore limits used by existing inventory operations.

Tighten Firestore rules so clients cannot directly create a `Credit`, change
its frozen fields, forge `credited`/`creditReversed` edges, or directly move an
item into/out of `canceled`. Admin/server operations bypass rules after doing
the cross-document validation. Existing non-Credit permissions are unchanged
in this feature.

### Phase 0 — design decisions and test fixtures

1. Add the exact compatibility values and persisted fields above without
   changing legacy reads.
2. Add the signed adjustment and exact tax representation above, using both
   Wayfair examples as read-only fixtures.
3. Implement and test reversal before enabling creation in production.

### Phase 1 — data and server behavior

1. Extend transaction, item-status, and lineage enums.
2. Add Firestore validation/security rules for the invariants above.
3. Update Cloud Function status/lineage triggers, completeness audit, and budget
   normalization.
4. Add the transactional/idempotent credit and reversal operations; do not
   compose them from general item edits.
5. Update MCP schemas, descriptions, reads, and dedicated safe write tools.

### Phase 2 — client UI

1. Add the Record vendor credit flow from Purchase detail.
2. Add labels, badges, linked-credit sections, filters, and accessible empty/
   error states.
3. Update project totals, transaction detail, item detail, search, and exports.

### Phase 3 — verification

Add server, MCP, and iOS tests for:

- mixed purchase: credit selected canceled lines while fulfilled lines remain;
- full-order selection and selection of all remaining lines are rejected with
  no writes;
- reserved non-cancellation reasons remain unavailable through v1 writes;
- duplicate/invalid credit attempts;
- credit reversal;
- audit correctness for gross purchase, Credit, tax, discounts, and source
  prices;
- reports, filters, and legacy return rows.

The detailed test matrix is:

| Layer | Required cases |
|---|---|
| Pure model/calculation | case-insensitive `Credit` decoding; reason labels; amount equation with no discount, positive/negative adjustment, exact tax, rounding-independent `taxCents`; Credit budget sign; canceled Credit zero sign |
| Server transaction | happy-path mixed Purchase; stale source `itemIds`; item cache mismatch; wrong project/vendor/category; non-itemized category; source/credit canceled; duplicate item ID; already returned/sold/credited; concurrent credits for the same line (exactly one commits); idempotent retry; conflicting operation ID; zero/negative/unreconciled amount; missing adjustment explanation; 100/101-item boundary; all-active-lines rejection; rollback leaves every document untouched |
| Audit/triggers | Purchase total includes linked + returned + sold + credited exactly once; automatic association plus credited edge does not create returned intent; source recomputes after credit and reversal; item price remains unchanged; Credit and canceled Credit budget summaries; trigger retries are idempotent |
| Reversal | successful reversal; second reversal idempotent; reject if Credit is already canceled for another reason, source Purchase unavailable/canceled, item no longer belongs to Credit, or a downstream edge/dependency exists; atomically restore source membership/status/cache link and append `creditReversed` |
| MCP | enum/schema discovery; dry-run preview; safe write/reversal; get/list/search return `creditedItems` and fields; filters/exports distinguish Credit from Return; errors contain no partial writes |
| iOS UI | action eligibility; partial-line selector; remaining-lines warning; reconciliation and attachment gates; loading/retry/offline/error states; list/detail/item badges; filters/search/export; VoiceOver labels and Dynamic Type |
| Regression | Purchase/Return/Sale/payment reads and writes; inventory operations; invoice settlement exclusion; legacy casing; the two named Wayfair Return documents remain byte-for-byte unchanged |

### Phase 4 — migration (separate approval)

Do not migrate legacy Returns by heuristic. First produce an evidence-backed
candidate list, including original order, canceled lines, refund proof, and
whether any item was physically returned. Review and approve each candidate or
a narrowly defined batch before writing.

### Reversal design

Reversal is a compensating operation, never deletion or mutation of source
prices. `reverseVendorCredit` / MCP `reverse_vendor_credit` runs a Firestore
transaction and is allowed only when the active Credit still owns every item,
the original Purchase is active, and no item has any later disposition or
dependency. It atomically:

1. sets the Credit transaction `status: canceled` and records
   `reversedAt`, `reversedBy`, and required `reversalReason`;
2. removes the item IDs from the Credit and adds them back to the original
   Purchase;
3. restores each item to `status: purchased` and
   `transactionId: creditedTransactionId` without changing price, source,
   project, category, or location fields; and
4. appends one immutable `creditReversed` edge per item from the Credit back to
   the Purchase.

The original `credited` and automatic `association` edges remain as history.
Canceled Credit contributes zero to budgets. A reversal retry uses its own
idempotency key and returns the existing result.

### Explicit unresolved decisions

These decisions do not block the v1 cancellation-credit implementation unless
marked otherwise:

1. **Whole-order cancellation (blocked/out of scope):** define dependency
   discovery and accounting semantics before allowing a Purchase to be
   canceled. Until then, reject all-active-line selections.
2. **Non-cancellation Credit behavior:** the enum reserves `priceAdjustment`,
   `courtesy`, and `other`, but v1 creation UI and write operation accept only
   `cancellation`. Itemless credit validation and audit semantics require a
   later spec amendment.
3. **Attachments:** confirm whether an existing `receiptImages` or
   `otherImages` reference satisfies the required source evidence for a
   non-zero adjustment; do not invent a third attachment collection.
4. **Vendor identity:** current transactions use free-form `source`. V1 uses
   trimmed, case-insensitive equality while persisting the source Purchase's
   exact string. A future vendor-ID model may replace this check.
5. **Deployment gate:** choose Remote Config, minimum app version, or another
   release flag so rules/server support deploy before any client exposes the
   action. Creation must remain hidden until reversal is deployed and tested.

## Concrete fixtures from Kapcsos Martinique

These existing records are documentation fixtures only; leave them unchanged
for now.

| Legacy Return | Evidence | Intended future representation |
|---|---|---|
| `7JZ0cEleTkJmuYdPRIzV` — $2,065.95 | Four dining chairs were canceled as backordered; their original Wayfair purchase also had other lines and replacements were selected. | Credit / cancellation linked to the mixed original Purchase |
| `bWRLUgK307RmXi3cd47M` — $39.54 | A pack of six stems was canceled as unavailable; the credit includes price, adjustment, and tax. | Credit / cancellation with source-supported adjustment and tax |

## Non-goals

- No changes to existing cleanup records in this workstream.
- No automatic classification based on a matching amount, note wording, or a
  single order ID.
- No conversion of client invoice credits or payment reversals into vendor
  Credits.
