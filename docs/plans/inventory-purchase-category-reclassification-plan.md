# Inventory Purchase Category Reclassification — Implementation Plan

Created: 2026-08-25
Updated: 2026-09-18
Status: implemented locally; production rollout pending

## Scope and decision

Allow a user to correct the entire project Purchase from Inventory from an incorrect category (for example Additional Requests) to another project-enabled itemized category. The reported transaction is `IATtFpB6v6SgjOqtIGAk`; its production shape has not yet been verified.

The September 18 scope revision supersedes this plan's previous invoice prerequisites. Invoice state does not block category correction. This work does not read, update, backfill, or migrate invoices, invoice lines, collection workflows, settlement transactions, or invoice provenance. Existing invoice snapshots may retain the previous category; that discrepancy is accepted for this feature.

Canonical behavior: [Purchase Category Reclassification](../specs/sale-transactions.md#purchase-category-reclassification).

## Required behavior

- Expose **Change Category** through the transaction details editor for eligible Purchases.
- Update the Purchase and every currently attached project item atomically.
- Offer active, non-system, itemized categories already enabled in the same project; no empty category or automatic category enablement.
- Preserve transaction and item IDs, membership, project, source, amounts, tax, prices, dates, status, spaces, existing lineage, departed items, downstream movements, and original vendor purchases.
- Keep generic movement category writes blocked. The iOS service and MCP tool are the supported correction paths; the Firestore rule permits only the fixed-shape Purchase category exception needed by those paths.
- Record the actor, original/target category, affected item IDs, request ID, and timestamp in a structured audit event.

The full stored Purchase amount moves between budget categories. Historical Returns/Sales retain their existing categories, so historical category offsets may no longer pair. This feature does not reconcile those records.

## Identity and eligibility

Resolve the transaction using its document ID within the authenticated account. Category choices use category IDs; names are display text.

A changed account/business name must never make a transaction ineligible. Do not compare the stored source to the account's current generated inventory label. Use the existing movement classification and persisted type/project/canonical state; inspect existing lineage where needed to distinguish ambiguous legacy records. Do not introduce an account-rename migration.

Support non-canonical, non-canceled, project-scoped Purchases from Inventory. Ordinary vendor transactions retain their current editor. Source-side Sales/Returns and inventory-only transactions remain outside this command.

Before implementation, characterize the reported record with a read-only lookup if access is available. This diagnoses the reported editor behavior; it is not an additional eligibility rule or a prerequisite for developing fixtures.

## Backend contract

One shared request contract, exposed through authenticated iOS and MCP entry points:

```typescript
interface ReclassifyInventoryPurchaseCategoryRequest {
  accountId: string;
  transactionId: string;
  targetBudgetCategoryId: string;
  expectedCurrentBudgetCategoryId: string;
  requestId: string;
  dryRun?: boolean;
}
```

Derive actor identity and account authorization from authenticated context. Validate the target account category and its project enablement on the server.

The MCP implementation uses a Firestore transaction:

1. Read the deterministic receipt keyed by account, transaction, and request ID before checking the current category. An exact replay returns the original receipt. Reuse with a different request payload fails.
2. Read the Purchase, check eligibility and expected category, then read its listed items and reverse-linked items. Require identical membership sets and matching project scopes.
3. Validate the target category. Calculate write limits before attempting any writes.
4. For preview, return the proposed category, full amount, active item count, unchanged fields, and blockers without writes.
5. For commit, update only category and audit timestamps on the Purchase and active items, and create the immutable receipt/audit event in the same transaction.

The iOS implementation uses the same eligibility shape and a single Firestore
batch through `TransactionsService`: it updates the Purchase and current item
documents together, consumes a request marker before persistence, and writes the
same structured audit event in that batch. The rules enforce the movement's
structural fields; the supported clients enforce the item cascade and target
category validation.

Return transaction ID, previous and target category IDs, active item count, amount, audit event ID, and whether the request was already applied. Same-category requests are no-ops. Specify their receipt behavior consistently across both clients.

All reads must precede writes. Concurrent moves/category edits must retry and revalidate; reject stale state without partial writes. Use field updates so unrelated concurrent amount changes are preserved. No project accounting coordination document or invoice collection migration is required.

## Client flow

1. Show the current category and **Change Category** in the details editor.
2. Present the valid project category choices.
3. Confirm the old/new category, entire Purchase amount, and current item count.
4. Submit the dedicated command using a request ID retained across retries after network errors or an uncertain response.
5. Show success from the committed receipt and refresh through listeners. Show actionable errors while retaining the selected target on failure.

The movement editor keeps source, totals, type, and other accounting fields
read-only. Category selection is sent through the service's correction branch,
which strips its internal request marker before writing. When offline, the
existing save path reports the write failure; it does not claim a correction
was committed locally.

MCP exposes the same preview and commit behavior and defaults to dry-run. Generic `update_transaction` remains unable to edit movement categories.

## Implementation sequence

1. Characterize existing movement identity, category selection, item membership, rules, and budget triggers; add fixtures for the reported category change. **Complete locally.**
2. Implement the authenticated iOS batch path, MCP planner/transaction, rules exception, request receipt, and audit event. **Complete locally.**
3. Add the iOS details action and register the MCP tool. **Complete locally.**
4. Verify service behavior, rules, category filtering, and buildability. **Complete locally; production fixture remains unverified.**
5. Deploy the required rules/client/MCP changes and verify with an authorized production fixture. Any real production correction remains a separately requested action.

Initial inventory-sale picker cleanup may reuse the category resolver, but redesigning sale creation is not a dependency of this fix.

## Verification and acceptance

- Additional Requests → Furnishings updates the Purchase and all active items together.
- Account renaming does not affect eligibility; category renaming does not affect identity.
- Invalid, disabled, archived, system, non-itemized, or cross-account targets fail without writes.
- Missing, asymmetric, or cross-project item membership fails without writes.
- Departed items, downstream transactions, invoice records, and settlement records are unchanged.
- Existing invoice status never blocks this operation.
- Response-loss retry returns the original receipt; conflicting request-ID reuse fails.
- Concurrent item movement/category edits cannot leave mismatched active membership or categories.
- Concurrent repricing cannot be overwritten by a category-only update.
- Injected write failure leaves no partial changes; oversized transactions fail before writes.
- Generic app/service and generic MCP movement category writes remain rejected; only the supported correction paths use the fixed-shape rules exception.
- Budget summaries move the full stored Purchase contribution from the old category to the new one.
- Focused iOS tests cover the movement correction cascade, audit event, and marker guard; rules tests cover the allowed Purchase category change and rejected structural edits. Full production-backed UI and retry UX remain rollout QA.

Use focused domain/rules/integration tests and the plain LedgeriOS scheme for manual production-backed QA. Focused emulator integration tests may verify transaction/rule behavior; normal manual launches use production Firebase.

## Rollout and rollback

Enable the action only after the backend and required rules are deployed. Log outcomes by transaction/request ID and failure reason. Disable the action if post-commit checks detect drift.

A user-requested reversal uses the same command with a new request ID and an eligible previous category. No automatic reversal or bulk reclassification. Invoice changes, source-side movement corrections, partial-item reclassification, and transaction splitting are outside this plan.
