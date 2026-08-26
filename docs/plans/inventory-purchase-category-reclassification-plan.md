# Inventory Purchase Category Reclassification — Implementation Plan

Created: 2026-08-25
Status: approved product behavior; implementation pending
Review posture: senior-review-ready; runtime changes require code review and the rollout gates below

## Decision

For a non-legacy project Purchase from Business Inventory:

- Allow the user to change the category of the entire Purchase.
- Offer only active, non-system, canonically itemized categories already enabled in that project.
- Atomically update the Purchase and every currently attached item.
- Never treat the operation as a selected-item or partial-transaction edit.
- Leave amount, subtotal, prices, project, source, type, dates, status, membership, lineage, departed item placement, downstream movements, and the original vendor Purchase unchanged.
- Allow the correction only while affected invoice sources are uncollected.
- Block it after an affected source is collected unless a separate collected-accounting correction is explicitly designed and approved.

Canonical behavior: [sale-transactions.md](../specs/sale-transactions.md#purchase-category-reclassification).

## Why a Dedicated Operation Is Required

Unlocking `transaction.budgetCategoryId` in the generic editor or Firestore rules is unsafe. A transaction-only write can leave its currently attached items in the prior category, causing transaction/item category drift and inconsistent invoice attribution.

The operation must be one trusted accounting command with one validation and write boundary. Direct app and MCP writes to movement `budgetCategoryId` remain prohibited.

## Current-State Findings

The implementation must address these existing gaps rather than building on them:

1. Firestore rules and MCP validation freeze movement `budgetCategoryId` entirely.
2. The iOS transaction editor disables the category for every inventory movement.
3. The ordinary iOS/MCP transaction update paths already cascade category changes to current `itemIds`, but those generic paths are not safe enough for movement/invoice semantics.
4. The iOS sell picker currently loads account categories and filters only archived/system categories; it does not require `categoryType == itemized` or project enablement.
5. The MCP sell path verifies project enablement but does not verify the account category's canonical type.
6. Invoice lines persist `budgetCategoryId`, and collection creates `paymentToBusiness` transactions grouped by that category.
7. iOS exposes whole-invoice collection, while service/MCP code also supports selected-line collection. This plan does not change collection granularity, but it must safely recognize existing line-level settlements.
8. Item-backed invoice lines currently identify the item but not the transaction association that supplied the line's category. Reused/departed items can therefore be ambiguous.

## Non-Negotiable Invariants

1. **Eligibility is shape-based and narrow.** Only a non-canonical, non-canceled, project-scoped `Purchase` whose source exactly matches the account's derived inventory label qualifies. A suffix-only match is insufficient. Vendor Purchases and project-egress Sale/Return transactions never qualify.
2. **Target category is server-validated.** It must have an account `BudgetCategory` document with `metadata.categoryType == "itemized"`, `isArchived != true`, and `isSystem != true`, plus an existing `ProjectBudgetCategory` document in the same project.
3. **No implicit enablement.** Neither creation nor reclassification silently creates a `ProjectBudgetCategory`.
4. **Whole transaction only.** The full stored Purchase amount changes rollup category. Selected-item category edits require transaction splitting and are out of scope.
5. **Active membership stays aligned.** `transaction.itemIds` must exactly equal the reverse-linked item set, and every item must match the Purchase project. Missing, extra, or cross-project membership fails the operation without writes.
6. **Departed placement is historical/current-state safe.** Lineage-derived departed items are used for invoice-lock detection and user disclosure but are not rewritten.
7. **Collected accounting is immutable here.** A paid invoice or active settlement transaction for an affected source blocks the normal correction.
8. **No accounting amount mutation.** The command never writes `amountCents`, `subtotalCents`, item prices, discounts, tax, or quantities.
9. **Atomicity and idempotency.** All category, invoice-snapshot, audit, and coordination writes commit together, and a repeated `requestId` cannot apply twice.
10. **Direct writes stay closed.** Firestore clients and generic MCP transaction tools cannot bypass the command.

## Proposed Architecture

### 1. One server-authoritative command

Add a backend command named `reclassifyInventoryPurchaseCategory`. Expose it through the authenticated Functions boundary used by iOS and a service-authenticated route used by MCP. Both routes call the same domain function.

Request:

```typescript
interface ReclassifyInventoryPurchaseCategoryRequest {
  accountId: string;
  transactionId: string;
  targetBudgetCategoryId: string;
  expectedCurrentBudgetCategoryId: string;
  requestId: string; // caller-generated UUID, used for idempotency
}
```

The authenticated actor is derived from auth/service identity, never trusted from request data.

Response:

```typescript
interface ReclassifyInventoryPurchaseCategoryResult {
  transactionId: string;
  previousBudgetCategoryId: string;
  budgetCategoryId: string;
  amountCents: number;
  activeItemCount: number;
  departedItemCount: number;
  updatedInvoiceCount: number;
  auditEventId: string;
  alreadyApplied: boolean;
}
```

### 2. Serialize category correction with invoice collection

The approved behavior allows correction until collection. A preflight query followed by unrelated writes is not sufficient: collection and category correction could race and categorize the payment differently from the Purchase.

Introduce a server-owned per-project coordination document:

```text
accounts/{accountId}/accountingMutationStates/{projectId}
```

Both collection and Purchase-category correction must run as backend Firestore transactions that read and increment this document. This serializes the two accounting mutations. The transaction must re-read source/item/invoice state after acquiring the shared revision and before writing.

Required prerequisite:

- Route iOS and MCP invoice collection through the trusted backend command path.
- Preserve existing collection semantics during this project; do not silently add or remove selected-line collection.
- Prevent direct clients from setting an invoice to paid or creating settlement linkage once supported client versions use the backend path.
- Do not enable category reclassification while an older supported client can still perform an uncoordinated collection write.

### 3. Make invoice source association unambiguous

Add optional `InvoiceLine.sourceTransactionId` for item-backed lines. Populate it whenever created/sent lines are materialized from an item. Preserve it in paid snapshots and returned-item credit derivation.

Resolution rules for existing lines:

- A transaction-backed line with `sourceId == purchaseTransactionId` is unambiguous.
- An item-backed line with `sourceTransactionId == purchaseTransactionId` is unambiguous.
- A legacy item line with no `sourceTransactionId` is safe only when the item is still currently attached to the Purchase in the same project.
- If a legacy/departed item line could refer to more than one transaction association, block automatic correction and return an actionable ambiguity error. Never guess.

Backfill `sourceTransactionId` only where current membership or immutable lineage proves the association. Leave ambiguous lines null.

### 4. Resolve transaction membership and history

Inside the backend command:

1. Read the Purchase and compare `expectedCurrentBudgetCategoryId`.
2. Read every current `transaction.itemIds` document and query items whose `transactionId` equals the Purchase ID.
3. Require those two ID sets to match exactly, and require every resulting item to have the same `projectId` as the Purchase. Category mismatch may be repaired to the target, but missing, extra, or cross-project membership is a stale-state failure.
4. Query lineage edges whose `fromTransactionId` is the Purchase and collect departed item IDs for invoice-lock detection and confirmation counts.
5. Do not add or remove transaction membership and do not write departed items.

The current per-batch limit is 100 items, leaving sufficient Firestore write capacity for the transaction, active items, affected invoice snapshots, audit event, and coordination document. The implementation must still calculate the final write count before commit and reject over-limit/corrupt legacy records safely.

### 5. Resolve collection locks

For active and lineage-derived original item IDs, plus the Purchase transaction ID:

1. Find non-canceled project invoices whose item/transaction membership or source lines reference an affected source.
2. Treat `invoice.status == "paid"` as locked.
3. Treat an affected line's nonempty `settlementTransactionIds` as locked unless every referenced settlement is canceled.
4. Query settlement transactions by `settlementInvoiceId` and treat any active transaction settling an affected line as authoritative, even if the invoice reverse lookup is stale.
5. Ignore canceled invoices and canceled settlement transactions.
6. Fail the entire category correction if any affected source is locked or association is ambiguous.

For created/sent uncollected invoices, update only the affected source lines' `budgetCategoryId` and preserve line IDs, amounts, signs, descriptions, and all unrelated lines.

### 6. Atomic write set

Within the coordinated Firestore transaction, write only:

- Purchase: `budgetCategoryId`, `updatedAt`, `updatedBy`, and optional `lastCategoryReclassification` summary.
- Current attached items: `budgetCategoryId`, `updatedAt`, `updatedBy`.
- Created/sent uncollected invoices: affected source-line `budgetCategoryId`, `updatedAt`, `updatedBy`.
- Coordination document: incremented revision and server timestamp.
- Immutable audit event:

```text
accounts/{accountId}/transactionCategoryEvents/{eventId}
```

```typescript
interface TransactionCategoryEvent {
  requestId: string;
  transactionId: string;
  projectId: string;
  previousBudgetCategoryId: string;
  budgetCategoryId: string;
  activeItemIds: string[];
  departedItemIds: string[];
  updatedInvoiceIds: string[];
  actorUid: string;
  source: "ios" | "mcp" | "admin";
  createdAt: Timestamp;
}
```

Use a deterministic event ID derived from `(transactionId, requestId)`. If that event already exists and matches the requested target, return `alreadyApplied: true`. A conflicting reuse of `requestId` is an error.

### 7. Authorization and rules

- Require account membership and the same financial-write authorization used for editing project transactions.
- Validate category visibility/type on the server regardless of caller.
- Keep direct movement `budgetCategoryId` edits rejected in Firestore rules.
- Keep `transactionCategoryEvents` and `accountingMutationStates` server-write-only; account members may read audit events if consistent with existing audit visibility.
- Restrict paid/settlement invoice mutations to trusted collection commands after compatible clients are deployed.

## Client Work

### iOS

1. Keep the generic movement accounting fields locked.
2. Add a dedicated **Change Category** action only for eligible Purchase-from-Inventory transactions.
3. Build the picker from the intersection of:
   - project `ProjectBudgetCategory` IDs;
   - active, non-system account categories;
   - `resolvedCategoryType == .itemized`.
4. Do not show "No Category" and do not offer an enable-category path from this sheet.
5. Show a confirmation summarizing:
   - old and new category;
   - entire Purchase amount being reclassified;
   - current attached item count;
   - departed historical item count, with an explanation that their current placement will not change.
6. Call the backend with the displayed current category and a UUID request ID.
7. Surface specific errors for stale membership, disabled/non-itemized target, collected lock, ambiguous legacy invoice line, and retryable concurrency.
8. On success, dismiss after listeners observe the updated transaction/items; do not optimistically patch only one model.

Also fix the initial sell flow to show only project-enabled itemized categories and remove silent auto-enablement.

### MCP

1. Add `reclassify_inventory_purchase_category` with `transactionId`, `targetBudgetCategoryId`, `requestId`, and `dryRun`/preview support.
2. Route commits through the same backend command; do not use `update_transaction` or Admin SDK field updates directly.
3. Keep generic movement immutability validation intact.
4. Validate and describe project-enabled itemized targets in dry-run output.
5. Fix all inventory-to-project sale tools to reject general, fee, archived, system, or project-disabled targets.

## Backend and Model Work Breakdown

### Phase 0 — Characterization and test fixtures

- Add pure eligibility/category/membership/collection-lock fixtures before runtime changes.
- Capture current whole-invoice iOS and selected-line MCP behavior without changing that product decision.
- Add representative legacy invoices without `sourceTransactionId`.
- Add a production read-only audit script for non-itemized inventory Purchases, transaction/item category drift, and ambiguous invoice associations.

### Phase 1 — Additive invoice provenance

- Add `sourceTransactionId` to Swift, MCP, Functions, specs, serializers, projections, and tests.
- Populate it whenever item-backed invoice lines are created or rematerialized.
- Backfill only provable associations; report ambiguous rows.
- Verify old clients/readers ignore the additive field.

### Phase 2 — Coordinated server collection boundary

- Extract collection calculation into a tested backend domain module.
- Add the per-project accounting mutation state/revision.
- Implement server-authoritative collection transactions for iOS and MCP.
- Preserve current visible iOS whole-invoice collection and current MCP semantics until a separate product decision changes them.
- Update rules only after supported clients have migrated.

### Phase 3 — Category reclassification command

- Implement shape/category/membership/lineage/invoice validation.
- Implement idempotency and structured audit events.
- Perform the atomic write set without touching amounts or structural fields.
- Confirm `onTransactionWritten` moves budget spend between category summaries and does not create trigger loops.

### Phase 4 — iOS and MCP surfaces

- Add dedicated iOS action, picker, confirmation, and error states.
- Add MCP preview/commit tool.
- Fix initial sale category filtering and server validation in both clients.
- Remove any documentation that still says the Purchase category is unconditionally frozen or that sell flows auto-enable targets.

### Phase 5 — Rollout and production validation

- Run the read-only production audit and archive its output.
- Deploy additive model/backend changes with category UI feature-disabled.
- Migrate collection writers and verify server metrics.
- Tighten rules against direct collection and settlement writes.
- Enable category reclassification for internal users, then general users.
- Perform one controlled production reclassification on an uncollected test/real transaction selected by the user; verify transaction, active items, invoice snapshots, audit event, and old/new budget summaries.

## Test Matrix

### Pure/domain tests

- Accept exact project Purchase-from-Inventory shape.
- Reject vendor Purchase (including one that merely ends in `" Inventory"`), Sale, Return, canonical sale, inventory-scoped transaction, and canceled Purchase.
- Accept active, non-system, project-enabled itemized target.
- Reject project-disabled, general, fee, archived, system, missing, and same-ID-with-conflicting-request targets.
- Resolve active versus departed membership without rewriting departed items.
- Resolve invoice lines by `sourceTransactionId`; reject ambiguous legacy/departed lines.
- Detect paid status, line settlement IDs, and active settlement transactions; ignore canceled invoice/settlement records.

### Firestore integration tests

- Single- and 100-item success paths update Purchase and active items atomically.
- Any stale/missing active item or reverse-linked item omitted from `transaction.itemIds` causes zero writes.
- Departed items and downstream transactions remain byte-for-byte unchanged.
- Amount, subtotal, prices, project, source, type, itemIds, status, and lineage remain unchanged.
- Created/sent uncollected invoice line categories update without changing line IDs/amounts.
- Paid or actively settled affected lines block with zero writes.
- Concurrent item move causes transaction retry then stale-state rejection.
- Concurrent price repricing preserves both the amount delta and category correction.
- Concurrent collection and reclassification serialize; exactly one observes the other's committed state and no category mismatch results.
- Duplicate request ID is idempotent; conflicting reuse is rejected.
- Budget summary subtracts the full Purchase amount from the old category and adds it to the new category exactly once.
- Firestore rules reject direct client transaction-category, audit-event, coordination-state, paid-status, and settlement-link writes.

### iOS tests

- Picker contains only enabled itemized categories and excludes "No Category".
- General, fee, archived, system, and account-only categories never appear.
- Action appears only for eligible project Purchase-from-Inventory transactions.
- Confirmation clearly states whole-Purchase scope and departed-item behavior.
- Collected/ambiguous/stale errors are actionable.
- Initial inventory sale picker enforces the same category filter.

### MCP tests

- Preview shows exact unchanged and changed fields.
- Commit routes through backend and produces the same audit result as iOS.
- Generic `update_transaction` remains blocked for movement category.
- Inventory sale tools reject every non-itemized or non-enabled category target.

## Verification Profiles

Use both profiles from [verification.md](../verification.md):

1. `taxonomy-model` for additive model fields, category filtering, Functions/MCP builds, and Swift model tests.
2. `firestore-integration` for the exact reclassification, collection-race, rule, trigger, and budget-summary tests with Auth + Firestore + Functions emulators and the repository seed/export.

Do not run the full iOS suite unless failures or touched shared infrastructure justify it. Add a manual production-backed simulator QA pass only after backend rollout and before enabling the feature flag.

## Observability

Emit structured logs and metrics for:

- attempts, successes, idempotent successes, and failures by reason;
- stale membership;
- ineligible target category;
- collected/settled lock;
- ambiguous invoice association;
- transaction retry/conflict count;
- old/new category IDs and transaction ID, without invoice notes or other user prose.

Add an admin/read-only audit query that confirms after each success:

- transaction and every active item share the target category;
- no affected active settlement remains in the prior category;
- old/new budget summaries reflect one full-amount transfer;
- exactly one audit event exists for the request ID.

## Rollout Gates

The feature flag must remain off until all are true:

- additive invoice provenance is deployed and read-compatible;
- iOS and MCP collection writers use the coordinated backend command;
- supported old clients can no longer perform an uncoordinated collection write, either through adoption or rules;
- direct category writes remain blocked;
- emulator concurrency tests pass;
- production audit identifies no unexplained category drift or ambiguous records that would be silently mutated.

## Rollback

- Disable the category-reclassification feature flag immediately; collection continues through the coordinated backend.
- Do not roll back additive invoice provenance or audit events.
- A successful uncollected category correction is reversible by running the same audited operation back to the prior eligible category.
- Never auto-reverse after collection. Use a separately approved collected-accounting correction.
- Because writes are atomic, failed requests require no partial-data cleanup. Any unexpected post-commit invariant failure must disable the feature and use the audit event to construct a reviewed repair plan.

## No Automatic Migration

Do not bulk-reclassify existing transactions. Existing non-itemized or drifted inventory Purchases are reported, not silently repaired. A user or approved repair plan chooses each target category. Unambiguous `sourceTransactionId` backfill is additive provenance only and must not change amounts, categories, invoice status, or settlement transactions.

## Out of Scope

- Reclassifying only selected items from a multi-item Purchase.
- Splitting or merging movement transactions.
- Changing categories on project-egress Sales/Returns or vendor Purchases.
- Changing a Purchase category after collection.
- Changing invoice collection granularity. The current iOS/MCP inconsistency requires a separate product decision and cleanup plan.
- Repricing items or transactions as part of category correction.
- Production deployment or data repair in the documentation turn that created this plan.

## Acceptance Criteria

The work is complete only when:

1. Initial sale and reclassification pickers can select only project-enabled itemized categories.
2. iOS and MCP invoke one server-authoritative category command.
3. Transaction, active items, uncollected invoice snapshots, audit event, and coordination revision commit atomically.
4. Collected/paid affected accounting blocks without writes.
5. All prohibited fields and all departed/downstream/original-vendor records remain unchanged.
6. Concurrent collection, item movement, and price repricing cannot create category or amount drift.
7. Direct client/MCP generic writes remain rejected by rules/validation.
8. Old/new budget summaries move the full Purchase amount exactly once.
9. Required unit, model, rule, integration, concurrency, and manual QA gates pass.
10. Production rollout is feature-gated, observable, reversible before collection, and accompanied by an immutable audit trail.
