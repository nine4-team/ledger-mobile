# SUPERSEDED — Project–Inventory Net Ledger Research

**Status:** Historical research only. Do not implement the one-transaction-per-project proposal.

**Date:** 2026-08-29

**Audience:** Product owner and senior implementation reviewers

**Scope:** Ledger iOS, MCP, Cloud Functions, Firestore rules/indexes, migrations, budgets, billing, reporting, and specifications

> **Product-direction update, 2026-08-30:** This proposal is superseded. Ledger will not create one user-facing Inventory Activity Transaction per project. Project inventory charges/credits move into the invoicing workspace as occurrence-level Item Movements. Transaction meaning is relative to scope ownership: project Transactions record the client's real payments, while business-inventory Transactions record 1584's real inventory purchases. Direct client-to-vendor project purchases remain budget-bearing Transactions; client-to-1584 invoice settlements are settlement-only Transactions. The lineage and signed-movement research below remains useful, but every recommendation for a single aggregate project Transaction is historical. See [Invoice-Centered Project Accounting](../invoice-centered-project-accounting/impact-analysis.md).

<details>
<summary>Show the rejected historical proposal and its supporting research</summary>

## Historical executive conclusion — superseded

Everything in this section describing one visible or aggregate project Transaction is retained only to explain the rejected design. It is not an active plan.

The desired product model is viable:

- each project has one user-facing transaction representing the net financial effect of sales between that project and business inventory;
- inventory-to-project movements contribute positively;
- project-to-inventory movements contribute negatively;
- a project-to-project sale creates a correlated negative contribution in the source project and positive contribution in the destination project;
- the transaction always belongs to Furnishings;
- Additional Requests is an overlapping tagged subset of Furnishings, not a competing accounting category.

However, the one transaction document must not become the historical source of truth. It should be a managed, reconciled materialized view backed by signed, occurrence-level movement entries. A design that mutates only one long-lived transaction amount and `itemIds` array would reproduce the drift and lost-history problems that caused Ledger to replace its previous canonical-sale aggregator with per-batch transactions.

This is therefore a storage, write-authority, billing-lineage, reporting, and migration redesign—not a narrow transaction-total change.

The smoothest transition is additive and reversible:

1. Resolve the product decisions in this report.
2. Fix the existing settlement-budget and financial-visibility defects.
3. Establish a protected Furnishings system role.
4. Route every inventory movement entry point through one idempotent server-owned writer while retaining current per-batch output.
5. Shadow-write signed movement entries and a per-project aggregate.
6. Backfill only what can be proven; preserve ambiguous historical totals as legacy batch entries.
7. Reconcile every project exactly.
8. Flip an explicit per-project or per-account authority flag so only one model contributes to budgets and reports.
9. Keep legacy records hidden but intact through a rollback window.

Implementation should not begin with UI changes or with deletion of old movement transactions.

## Provisional design decision log — not finalized

The following points capture the direction of the product discussion so they are not lost. They are **working choices**, not approved implementation contracts. The remaining questions and the adjacent transaction-system redesign may change their exact shape.

1. **One visible aggregate, detailed accounting underneath.** Keep one project-scoped Inventory Activity transaction for the user-facing total, backed by signed item-movement occurrences that preserve the accounting history.
2. **Prefer evolving lineage over creating a duplicate movement-history system.** The existing `LineageEdge` graph already records item, movement intent, source/destination project and transaction, actor, and time. The leading option is to enrich designated financial intent edges with operation identity, amount, tax, price basis, Additional Requests classification, invoice linkage, and reversal linkage. Automatic `association` edges would remain nonfinancial. Whether the final storage model enriches `lineageEdges` directly or links them to a dedicated accounting-entry collection remains open pending the unified transaction-system design.
3. **Additional Requests spend is non-additive.** A tagged occurrence contributes to Furnishings and appears in the Additional Requests subtotal, but it does not contribute a second time to Overall Spend. The separate question of how an Additional Requests *budget allocation* affects Overall Budget remains unresolved.
4. **Negative movement and invoicing are related but not identical.** A project-to-inventory movement always reduces the project's Furnishings spend. The leading invoicing rule is that it changes client demand only when the exact positive item charge being reversed was already included on an invoice. The draft/sent/paid behavior remains to be finalized.
5. **Preserve current origin-aware valuation initially.** This redesign should not also change the price bases used for inventory-origin returns, project-origin acquisitions, or project-to-project movements unless a later product decision explicitly does so.
6. **Coordinate with the broader transaction-line redesign.** Non-item receipt lines, discounts/tax, transaction completeness, correction history, and inventory movement accounting may need shared line/event infrastructure. A cross-thread architecture review is in progress; do not finalize parallel schemas until that review is reconciled.
7. **Use one acquisition path for new design-business-paid item purchases.** When the design business pays a vendor transaction that contains physical Items, the leading rule is to create the vendor Purchase in business inventory and then sell/place those Items into the project through Inventory Activity. Do not also offer a direct project Purchase marked as reimbursable for the same scenario. Client-paid itemized purchases may still land directly in the project. Non-itemized project costs retain the Design Business versus Client payer choice and the corresponding reimbursement behavior. The exact persisted discriminator is unresolved below.

## Cross-redesign convergence findings

The adjacent [Non-Item Receipt Lines](../non-item-receipt-lines/design.md) design and production audit materially affect this proposal. These findings should be treated as part of the same transaction-system redesign program.

### Share accounting primitives, not necessarily one storage shape

The two designs need common concepts:

- stable line/occurrence IDs;
- positive magnitude plus explicit increase/decrease or sign semantics;
- source wording and immutable accounting snapshots;
- operation/idempotency identity;
- explicit invoice-source provenance;
- append-only corrections/reversals after accounting lock points;
- versioned reconstruction and reconciliation outputs;
- a strict distinction between physical Items and financial lines.

They have different lifecycles and should not be collapsed blindly:

- A vendor receipt is finite. Its `NonItemReceiptLine` values are naturally embedded in the receipt transaction beside references to physical Items.
- A project Inventory Activity ledger is lifetime-scoped and unbounded. Its financial movement occurrences must be separately queryable and paginated, whether stored as enriched lineage edges or linked accounting entries.

A shared value type or protocol may be appropriate, but a single embedded `transaction.lines` array is not appropriate for the lifetime ledger.

### Keep two different integrity equations

Ordinary itemized vendor receipt completeness asks:

```text
physical Item total + signed non-item receipt lines == final receipt amount
```

Inventory Activity integrity asks:

```text
sum(signed financial movement occurrences) == project Inventory Activity net
```

These can share a signed-cent arithmetic library and audit-result vocabulary, but they are not the same audit. The existing `isComplete`/transaction-audit model should become versioned or kind-aware rather than applying one formula to every transaction.

### Preserve the tax boundary during the first redesign

For a vendor receipt, printed tax can be a `NonItemReceiptLine`; vendor subtotal/rate inference should stop driving completeness. Generated inventory movements currently use Item tax rate and stored movement subtotal for tax-inclusive project charges, repricing, and legacy return snapshots. Do not remove that movement behavior as a side effect of the receipt-line migration. Any eventual unified tax allocation needs an explicit later design.

### Billability must be explicit for both line systems

Neither a non-item receipt line nor a negative inventory movement should alter client demand merely because it exists. Invoice sources must identify the exact receipt line or movement occurrence being billed or reversed. This creates a shared invoice-provenance model without assuming that every business cost is passed through to the client.

### Recommended separation of transaction concepts

Do not make one overloaded `TransactionType` answer three different questions. Preserve separate concepts:

1. **Money event:** Purchase, Return, client payment, and any future credit/refund event.
2. **Record/accounting kind:** itemized vendor receipt, general project cost/expense, project Inventory Activity aggregate, or invoice settlement.
3. **Budget attribution:** Furnishings, Install Services, and other budget categories.

The UI may call a non-itemized project Purchase an **Expense**, but reintroducing `Expense` as a money-direction type would conflict with the current Purchase/Return/payment taxonomy. If an explicit discriminator is needed, add a stable `accountingKind`/`recordKind` snapshot instead of overloading `type`.

## Provisional single acquisition-path rule

### Intended behavior

For new Purchase entry:

| Receipt composition | Paid by | Proposed path |
|---|---|---|
| Physical Items / itemized | Design Business | Create vendor Purchase in business inventory, create the Items there, then create positive project Inventory Activity occurrences when placing/selling them to the project. No direct reimbursable project Purchase option. |
| Physical Items / itemized | Client | Create the vendor Purchase and Items directly in the project; no business-inventory reimbursement leg unless the business actually acquires the Items. |
| Non-itemized project cost | Design Business | Keep a project cost transaction with Design Business payer and reimbursement/owed-to-company behavior as applicable. |
| Non-itemized project cost | Client | Keep a project cost transaction with Client payer and the existing owed-to-client/no-reimbursement behavior as applicable. |

This removes two competing representations of the same design-business-funded physical purchase. The vendor Purchase records what the business paid; Inventory Activity records what the project/client was charged. Invoicing should source the project movement occurrence rather than treating the original vendor receipt as a second reimbursable project cost.

### What should drive the branch

The leading design is a two-step contract:

1. The selected category's canonical `metadata.categoryType` drives the form branch at creation time: itemized categories expect physical Items; general categories expect non-itemized costs.
2. The resolved structural choice is persisted as an immutable or tightly controlled `accountingKind` snapshot so later category rename/reclassification cannot retroactively change the transaction's behavior.

This combines the user's category-driven mental model with an explicit data invariant. Relying only on mutable category metadata is unsafe for historical reads; relying only on a new `Expense` transaction type conflates transaction structure with money direction.

### Existing specs already chose most of this rule; implementation drifted

This proposal is not entirely new. `docs/specs/item-entry-flow.md` already says:

- eliminate direct-to-project entry for design-business-paid physical/itemized Items;
- use category type plus purchaser as the routing decision;
- route client-paid itemized Items directly to the project;
- route non-itemized costs directly to the project while retaining payer/reimbursement choices.

`docs/specs/transaction-creation.md` and `docs/specs/transaction-type.md` also say itemization belongs to budget-category metadata and that new writes must not use the legacy `Expense` transaction type.

The current app does something different: `PurchaseHandling` offers `inventory_resale` versus `project_reimbursement`, and `TransactionFormValidation.shouldRouteThroughInventory` routes only when the user explicitly selects `inventory_resale`. The New Transaction flow can present that choice before category behavior is known.

Therefore the redesign should be framed as both:

1. restoring the already documented category-plus-payer routing invariant; and
2. updating that older spec for the new one-per-project Inventory Activity ledger, Additional Requests tagging, non-item receipt lines, and server-owned atomic writes.

The older item-entry spec itself contains stale canonical-aggregator and Additional Requests-category language, so it cannot simply be reimplemented verbatim.

### UI and workflow consequences

- The form must know itemized versus non-itemized before presenting routing choices. Today payer and `purchaseHandling` can appear before category; the steps must be reordered or resolved together.
- For an itemized Purchase with Design Business selected, remove the Inventory Resale versus Project Reimbursement fork. Inventory routing is automatic.
- Preserve the Design Business versus Client choice for non-itemized costs.
- For client-paid itemized Purchases, make the direct-project result explicit so users understand why inventory is not involved.
- When the business-paid acquisition is intended immediately for a project, submit one server-owned request that creates the inventory receipt/Items and the project movement atomically or with a durable recoverable workflow. Do not leave a silent half-state.
- If project prices are not finalized, use the approved initial price-floor behavior and allow occurrence-scoped repricing to adjust Inventory Activity later.

### Data and migration consequences

- Retire `purchaseHandling = project_reimbursement` for new design-business-paid itemized transactions; preserve legacy rows as historical reads until a reviewed migration says otherwise.
- Keep `purchasedBy`/payer semantics for ordinary non-itemized project costs.
- Inventory acquisition transactions remain inventory-scoped and uncategorized under the existing item scope/category invariant; the project Inventory Activity aggregate supplies Furnishings attribution.
- Add validation so the same business-paid item cost cannot simultaneously enter the project as both a reimbursable direct Purchase and an Inventory Activity charge.
- Existing direct project reimbursable itemized Purchases require a production audit before reclassification. Do not mechanically reroute paid/invoiced history.

### Mixed-receipt issue still requiring design

A business-paid vendor receipt can contain physical Items plus shipping, tax, warranty, protection, installation labor, discounts, or credits. Moving the physical Items into a project must not automatically copy every `NonItemReceiptLine` into project Inventory Activity.

For each non-item line, the system needs an explicit policy or user choice:

- business acquisition cost only;
- allocated into one or more Item project prices;
- passed through to the project as a separate Furnishings movement charge/credit; or
- billed separately under another category or invoice-only line.

Automatic pass-through would be wrong for vendor discounts and some protection plans; automatic omission would lose legitimate client-facing shipping or installation charges. This billability/allocation decision is a shared blocker for the receipt-line and inventory-ledger releases.

## Product model being evaluated

### One visible transaction per project

The user-facing transaction is best described as **Inventory Activity** or **Inventory Purchases & Credits**. It is project-scoped and lifetime-scoped.

Its net is:

```text
net inventory activity
  = all inventory → project charges
  - all project → inventory credits
```

The aggregate may be positive, zero, or negative. It therefore cannot safely inherit the current rule that transaction amounts are non-negative and direction is inferred from `Purchase`, `Sale`, or `Return`.

The aggregate should expose at least:

- `grossChargesCents`
- `grossCreditsCents`
- `netAmountCents` (signed)
- `lastMovementAt`
- a stable managed kind such as `projectInventoryLedger`
- the protected Furnishings category ID
- a version and reconciliation status

The ordinary `amountCents` contract should not be silently changed for every transaction. Readers need an explicit managed-ledger branch. Whether the UI aliases `netAmountCents` as the transaction's displayed Amount is an implementation detail; the storage semantics must remain unambiguous.

### Signed movement occurrences are authoritative

Each project/item accounting occurrence needs a durable entry. A suggested shape is:

```text
InventoryMovementEntry
  id
  operationId                  // idempotency/correlation key
  projectId
  ledgerTransactionId
  itemId or legacyBatchId
  priorMovementEntryId
  counterpartEntryId           // project-to-project correlation
  movementKind                 // inventoryIn, inventoryOut, adjustment, reversal, legacyBatch
  sign                         // +1 or -1
  amountCents                  // unsigned magnitude
  subtotalCents
  taxCents / taxRate snapshot
  priceBasis                   // projectPrice, purchasePrice, recordedReturnAmount, legacyStoredTotal
  budgetCategoryId             // always resolved protected Furnishings ID for v2 entries
  additionalRequest            // project-occurrence classification
  sourceProjectId / destinationProjectId
  item description and price snapshots
  invoice/collection linkage
  reversesEntryId
  effectiveAt
  createdAt / createdBy
```

This is a logical accounting shape, not a finalized Firestore collection choice. The preferred reuse candidate is the existing lineage system: financial intent edges could carry or reference this payload, while automatic association edges remain navigation/audit-only. The final choice should be made together with the transaction-line and completion redesign so Ledger does not create overlapping line, event, and lineage abstractions.

Financial entries should be append-only. Repricing, voiding, and accounting correction should append deterministic delta/reversal entries rather than rewriting collected history. A separately controlled current classification may be needed if Additional Requests tags remain editable; every such change still needs an audit event.

The aggregate transaction should not contain an ever-growing movement-ID or item-ID array. That would create document-size, contention, and stale-membership risks. Detail screens should query paginated entries by project or ledger transaction.

### Existing valuation rules should be preserved initially

The redesign does not require changing the current origin-aware economics:

- inventory → project: positive, using normalized project price and tax;
- inventory-origin item → inventory: negative reversal of the recorded project charge;
- project-origin item → inventory: negative at purchase cost;
- project → project: negative source entry using the applicable source rule, plus positive destination entry at normalized project price.

Changing those bases simultaneously would turn an architecture migration into an accounting-policy migration. Preserve them unless product explicitly chooses otherwise.

### Additional Requests is a project-specific overlay

Additional Requests cannot remain a normal mutually exclusive category if the same item also contributes to Furnishings. It should be modeled as a project-specific classification of a movement occurrence or project placement.

It must not be a permanent global item flag. The same physical item can be an Additional Request in Project A and an ordinary furnishing in Project B. A negative movement should reduce the Additional Requests subtotal only when it reverses or credits an occurrence that was classified as Additional Requests for that project.

Recommended presentation:

```text
Furnishings spend                   $50,000
  of which Additional Requests      $8,000
```

The $8,000 is non-additive. It must not raise displayed overall spend to $58,000.

## Why the obvious single-document implementation is unsafe

The active inventory movement spec intentionally uses one transaction per movement batch. It says the prior long-lived canonical aggregator was replaced to avoid shared-state drift and stale membership ([sale-transactions.md](../../specs/sale-transactions.md), lines 7–20; [canonical-sales.md](../../specs/canonical-sales.md), lines 16–25 and 89–109).

Current transactions store one type, one category, one amount, and current `itemIds`; items store only their current transaction/category plus a last inventory-entry snapshot ([Transaction.swift](../../../LedgeriOS/LedgeriOS/Models/Transaction.swift), lines 33–71; [Item.swift](../../../LedgeriOS/LedgeriOS/Models/Item.swift), lines 45–71). Repeated project/inventory cycles cannot be represented faithfully by reusing one transaction ID.

If the aggregate document and `itemIds` were authoritative:

- deleting an item could erase the evidence needed to reproduce the total;
- a legitimate return and an erroneous deletion would be indistinguishable;
- repeated entries of the same item into the same project would collapse together;
- paid and unpaid occurrences could not be locked independently;
- a project-to-project movement could not preserve both accounting legs;
- report dates, notes, price bases, tags, and actors would be lost;
- concurrent MCP/iOS writes could overwrite or duplicate aggregate changes;
- the long-lived item array would eventually hit Firestore size and contention limits.

The new design can keep the cleaner one-transaction mental model while avoiding the old failure mode by separating presentation from evidence.

## Current-system impact map

| Surface | Current assumption | Required change | Main consequence/gotcha |
|---|---|---|---|
| Transaction model | One non-negative amount; one direction inferred from type | Add explicit managed kind and signed net fields | Every generic formatter, normalizer, filter, sort, export, and audit must branch explicitly |
| Item model | `transactionId` points to current batch; last inventory snapshot proves a return | Add active movement occurrence/placement identity | Transaction ID alone cannot identify repeated item/project episodes |
| Movement writes | iOS and MCP independently create per-batch docs | One idempotent server-owned domain writer | All bypasses must be removed before aggregate authority changes |
| Project-to-project | Two-hop batch creates 2–3 transactions | One operation creates correlated source/destination entries | Both ledgers and item relocation must commit atomically |
| Deletion/correction | Item deletion removes membership but not amount | Block direct deletion; append void/reversal through trusted operation | Collected occurrences require explicit accounting correction, not erasure |
| Repricing | Trigger adjusts eligible Purchase by delta | Append occurrence-scoped delta and update aggregate exactly once | Item/project matching is too coarse after repeat cycles |
| Categories | Transaction chooses one enabled itemized category | Resolve protected Furnishings automatically | Furnishings cannot be identified by name or a universal hardcoded ID |
| Additional Requests | Exclusive itemized category | Non-additive tagged subtotal | Existing overall-budget metadata cannot represent this safely |
| Budget rollups | Sum normalized transaction amount by category/type | Use v2 net aggregate or movement-derived summary; never legacy + v2 | Explicit authority flag is required to prevent double-counting |
| Invoices | Item/transaction IDs identify line sources | Reference movement occurrence IDs | Invoice collection remains whole-invoice UX; provenance is line-level internally |
| Paid locks | Item/project membership acts as lock | Lock the collected occurrence and invoice snapshot | The lifetime transaction must remain mutable for later activity |
| Reports | Current items and one transaction direction/category | Report movement history and overlapping AR subtotal | Aggregate-only export destroys dates, direction, and returned-item evidence |
| Transaction UI | Batches show active/departed item groups | One row with chronological signed entry detail | Lifetime date, naming, notes, and correction actions need new UX |
| Inventory UI | Inventory-scoped transaction list shows batch records | Decide on cross-project activity feed or no inventory-side transaction row | Project-owned aggregates do not naturally appear in inventory queries |
| Completeness audit | Compare batch amount with current/departed item values | Compare aggregate with non-voided signed entry sum | Old audit must exclude v2 managed ledgers |
| Offline/concurrency | Client batches and auto-IDs | Request-doc operation with stable ID and conflict detection | Retried/offline writes must be exact no-ops, not duplicate movements |
| Rules/Admin | Member creates broadly allowed; Admin bypasses rules | Server-only entry/aggregate mutation plus domain validation | Rules help clients but cannot protect MCP or migrations |
| Migration | Legacy rows are dual-read and preserved | Shadow, reconcile, authority flip, retention | Never relabel old accounting rows canceled merely to hide them |

## Detailed consequences and required redesigns

### 1. Movement write authority

The iOS `InventoryOperationsService` and MCP `inventory-operations.ts` each implement substantial independent domain logic. MCP composite creation and Quick Draft promotion also create movement transactions through additional paths.

The aggregate creates shared mutable state, so these writers cannot continue independently. All of these operations should submit the same request document or call the same server domain function:

- sell inventory items to a project;
- move project items to inventory;
- return eligible project-origin items from inventory;
- move items project-to-project;
- promote Quick Draft items into a project through inventory;
- create composite item/movement operations;
- reprice an active inventory-origin charge;
- void/delete an erroneous uncollected occurrence;
- apply a collected correction/reversal.

The repository already specifies request documents for multi-document, auditable, retry-safe, offline-capable work ([write-tiers.md](../../specs/write-tiers.md), lines 42–61 and 109–117). This redesign should implement that architecture rather than introduce another client-side batch path.

Every request needs:

- caller-generated `operationId`;
- deterministic movement-entry IDs;
- payload hash or exact conflict comparison;
- server transaction re-read of current item state;
- atomic item relocation, entry creation, lineage, and affected aggregate updates;
- completed/failed result persisted on the request;
- exact retry behavior: same ID/same payload is a no-op success; same ID/different payload is rejected.

For project-to-project sales, reference documents should be acquired in deterministic order to avoid contention, and the write count must be calculated before commit. The existing 100-item limit can exceed Firestore's 500-write ceiling once two movement legs, lineage, request state, item state, and aggregates are included.

### 2. Transaction identity, sign, and display

`Purchase`, `Sale`, and `Return` currently carry transaction-wide direction. A lifetime ledger mixes all three effects and can cross zero. It needs a dedicated managed identity rather than pretending to be a Purchase.

Recommended storage behavior:

- deterministic transaction ID per project;
- managed kind—not the deprecated legacy canonical-sale flags;
- `netAmountCents` signed and authoritative for v2 display/budget contribution;
- gross charges and credits stored for explanation and reconciliation;
- category fixed to the protected Furnishings ID;
- `createdAt` means ledger creation;
- `lastMovementAt` controls recent-activity sorting;
- no generic source/vendor, receipt, purchased-by, reimbursement, or payment fields;
- no generic attach/detach/delete actions.

The transaction detail should show entries grouped by operation/date, with item name, direction, price basis, tax, signed contribution, Additional Request classification, counterpart project where applicable, and correction/reversal links.

### 3. Items, current placement, and lineage

`item.transactionId` currently doubles as current membership and accounting provenance. That breaks when every placement in a project shares the same transaction ID.

Add a current occurrence reference such as `activeInventoryMovementEntryId` or a small project-placement record. Preserve existing lineage for association history, but make the new occurrence the accounting anchor for:

- repricing eligibility;
- return valuation;
- Additional Requests classification;
- invoice source identity;
- paid lock checks;
- correction/deletion eligibility.

When an item enters inventory, its project/category must still clear under the existing scope invariant. It should not remain attached to the prior project ledger as current membership. Its historical relationship survives in movement entries. A project-originated item in inventory may therefore have no current transaction; inventory provenance should use the entry reference, not fabricate an inventory transaction.

Items with accounting history should be tombstoned or snapshot-preserved rather than hard-deleted. The movement entry must retain enough name, price, tax, and scope evidence for reports after the live item is gone.

### 4. Corrections, deletion, and legitimate returns

Three distinct operations must stay distinct:

1. **Erroneous uncollected movement:** void/reverse the occurrence and update item placement and aggregate atomically. The audit remains.
2. **Legitimate later movement:** append a new negative or positive occurrence. Do not delete the earlier occurrence.
3. **Collected accounting correction:** preserve the collected occurrence and create an explicit reversal/credit path tied to the original invoice line.

The current direct deletion behavior is unsafe: item deletion removes the item and parent membership but does not adjust the financial total or enforce collection state. Rules also permit account members to delete items directly. Movement-linked deletion must be denied and routed through a trusted correction request.

The lifetime transaction itself must be non-deletable even when it has no current items. Its history can be non-empty while current membership is empty.

### 5. Repricing

The current repricing trigger already demonstrates a useful transactional delta and idempotency-marker pattern. Its eligibility is nevertheless based on current item/project/transaction identity and assumes the total cannot be negative.

Under v2:

- a price edit resolves the item's active positive occurrence;
- collection locks only that occurrence's client-facing amount, not the entire project ledger;
- an allowed edit appends a deterministic signed delta entry;
- the aggregate changes by that exact delta once;
- a negative aggregate is valid;
- periodic reconciliation verifies that aggregate net equals entry sum.

Do not recompute the ledger from current items. Returned/deleted items are part of historical accounting even when no longer active.

### 6. Furnishings identity and protection

Furnishings is currently an ordinary mutable category. New accounts seed `seed_furnishings`, older production data uses different IDs, some reads fall back to exact display-name matching, and project category settings can rename, retype, archive, disable, or delete categories.

Introduce a durable semantic role, for example:

```text
BudgetCategory.metadata.systemRole = "furnishings"
Account.inventoryMovementCategoryId = <verified category id>
```

Migration must verify exactly one active itemized category for the role or require an explicit account-level selection. Do not guess from duplicate names. Every project using inventory activity must have the category enabled automatically. Prevent retyping, archiving, deleting, or excluding the role in ways that invalidate accounting. Renaming may remain allowed if the semantic role is stable and the product wants customizable labels.

Remove category parameters and category pickers from new movement APIs and UI. Server resolution—not client input—sets the category.

### 7. Additional Requests budget semantics

The current budget system partitions spend by one transaction `budgetCategoryId`. `excludeFromOverallBudget` excludes both a category's spend and its budget allocation; it does not create an overlapping subtotal.

V2 needs an explicit overlay model in project budget summaries, for example:

```text
budgetSummary.categories[furnishingsId].spentCents
budgetSummary.overlays.additionalRequests.spentCents
budgetSummary.overlays.additionalRequests.budgetCents
```

The AR spend should normally use the same signed tax-inclusive contribution as Furnishings so the subset reconciles exactly. A tagged negative movement reduces the subset. A project-to-project destination may choose its own classification; it should not blindly inherit the source project's tag.

There is one unresolved budget-policy decision: whether the AR budget allocation is already inside the Furnishings/Overall budget or represents approved incremental budget. Existing projects may have treated Furnishings and Additional Requests as additive budgets. Removing the AR category from overall totals could silently shrink the project's total budget. The migration must preserve existing intended totals according to an explicit rule.

### 8. Budget aggregation and an existing settlement defect

There are multiple budget readers:

- iOS live calculations and budget progress;
- MCP budget tools and analytics/resources;
- Cloud Function denormalized project summaries.

They currently normalize sign from transaction type and group by transaction category. All need the same versioned authority rule:

```text
if project.inventoryLedgerAuthority == legacy:
    use legacy/per-batch movement transactions
if authority == v2:
    exclude superseded legacy movement transactions
    include the v2 signed net exactly once
```

The migration must never allow both models to contribute.

The audit also found a likely current defect that should be resolved independently before cutover: invoice collection creates categorized `paymentToBusiness` settlement transactions, while budget normalizers treat types other than Return/Sale as positive spend. That can count the item charge once and the collected payment again. Any transaction with an active `settlementInvoiceId` should be treated as payment evidence and excluded from project-spend aggregation. Fix and backfill all iOS, MCP, Functions, and cached-summary paths before using Furnishings as the universal movement category.

### 9. Invoices and collection

The user-facing invoice can still be collected as one whole invoice. Entry-level source identity is an internal accounting requirement; it does not imply partial collection UI.

One lifetime transaction ID is not specific enough for invoice provenance. An item can enter, leave, and re-enter the same project. Invoice lines should reference `movementEntryId` or an occurrence source type. Paid lines retain immutable amount/category/item snapshots.

The lifetime aggregate remains mutable after collection because later inventory activity is valid. Only the collected occurrence is frozen.

Recommended behavior, subject to product approval:

- **Created/draft invoice:** live source lines may be replaced/removed before the invoice is presented.
- **Sent but uncollected invoice:** preserve what the client saw and append a visible negative line when the item exits, rather than silently deleting the charge.
- **Paid invoice:** create a separate credit invoice/credit note referencing the collected occurrence.

Negative project budget activity is not automatically a client credit. Credit eligibility should depend on whether the associated positive occurrence was billed/collected and on ownership policy. Today inventory-origin returns have a paid-credit path but project-origin sales to inventory do not. The redesign must make this symmetric or explicitly document why those cases differ.

Legacy paid invoice lines and settlement categories should not be rewritten. New v2 item movement invoice lines can all snapshot Furnishings while paid history remains grandfathered.

### 10. Billing totals and financial visibility

The current Billing Summary's “Total Spent” uses active item purchase cost plus non-itemized transactions, while inventory movement budget spend uses project price plus tax. Those are different measures:

- business acquisition cost;
- project budget spend;
- client billable demand;
- cash collected.

The UI and specs need explicit names and inputs. The redesign must not silently swap one measure for another.

Separately, current app access logic appears to classify every `paymentToBusiness` transaction as a company fee, while the financial-access spec requires both the payment type and fee category. Furnishings settlements may therefore be hidden from restricted users. Resolve this alongside settlement exclusion.

### 11. Reports, exports, and transaction UI

Existing project closeout/client-summary reports group items into exclusive categories and commonly inspect current items. After the change:

- Furnishings is the additive item movement total;
- Additional Requests is an “of which” subset;
- negative movements must be visible and reduce the appropriate totals;
- returned/deleted items must remain reportable from entry snapshots;
- project-to-project counterpart information should be visible;
- aggregate-only exports are insufficient.

Provide two export levels:

1. one project Inventory Activity summary row for ordinary transaction export;
2. a movement-detail export with occurrence ID, date, item, operation, sign, gross/net contribution, price basis, tax, AR tag, counterpart, invoice state, and reversal linkage.

Transaction notes currently belong to batches. In v2, notes belong to the movement operation/entry, not the lifetime aggregate. The ledger can have a separate optional summary note if needed.

The inventory transaction screen needs a product decision: show a cross-project activity feed derived from entries, or omit project-owned aggregate transactions from inventory. Reusing the project transaction row on both sides would create ambiguous ownership and querying.

### 12. Completeness, triggers, and reconciliation

The current completeness audit derives a transaction amount from current/departed item documents and assumes Purchase/Return amounts are positive. V2 needs a separate invariant:

```text
ledger.netAmountCents
  == sum(entry.sign * entry.amountCents for every non-voided financial entry)
```

Also verify:

- `grossChargesCents` equals positive-entry magnitude sum;
- `grossCreditsCents` equals negative-entry magnitude sum;
- AR subtotal equals signed sum of AR-classified effective occurrences/deltas;
- every active project item from inventory has one active occurrence;
- every project-to-project operation has balanced correlated legs at the intended price bases;
- every idempotency marker matches exactly one payload/result;
- collected line sources still resolve to immutable evidence.

Current transaction triggers perform a full project transaction scan on changes. Movement-entry writes should not each cause that scan. The trusted operation should update the aggregate once; downstream summary work should consume that one update. A scheduled or on-demand reconciliation job should repair/flag drift from authoritative entries.

### 13. Security rules and indexes

Firestore rules currently allow broad account-member creation and direct item deletion, freeze some per-batch movement fields only after creation, and allow lineage creation despite comments describing it as server-produced. MCP and migrations use Admin SDK and bypass rules entirely.

V2 rules should:

- allow clients to create validated request documents only;
- deny direct client creation/update/deletion of movement entries;
- deny direct mutation/deletion of managed aggregate transactions;
- deny direct deletion of an item with movement or invoice history;
- make audit/lineage entries immutable;
- reject legacy movement creation after a project's v2 authority flips;
- test the actual production rule file, not a divergent simplified copy.

Server-side domain validation and reconciliation remain mandatory because Admin callers bypass these rules.

New queries will likely require indexes for:

- movement entries by project and effective date;
- movement entries by ledger transaction and effective date;
- item movement history by item and effective date;
- operation/idempotency lookups;
- collection/lock state where not denormalized.

Design query shapes before deploying indexes.

## Smooth-transition implementation plan

### Phase 0 — Product decisions and fresh production audit

Resolve the decisions listed later in this document. Then run a fresh read-only production audit, because repository snapshots are dated and the local environment did not expose current production credentials during this research pass.

The audit should report per account/project:

- per-batch and legacy canonical movement transactions;
- active/departed item membership discrepancies;
- exact stored signed movement total by project/category;
- items with ambiguous origin or missing price/tax snapshots;
- repeated project/item cycles;
- Additional Requests item rows versus non-item work;
- created/sent/paid invoice lines referencing movement items;
- settlement transactions and possible spend double-counting;
- categories named/slugged Furnishings, their IDs/types/archive state, and project enablement;
- records referenced by Quick Drafts, lineage, repricing markers, and deletion blockers.

Exit gate: approved data cohort report and explicit policy for every ambiguous class.

### Phase 1 — Correctness prerequisites

1. Exclude invoice settlement transactions from project-spend rollups in iOS, MCP, Functions, reports, and cached summaries.
2. Repair/backfill affected project budget summaries and verify parity.
3. Fix `paymentToBusiness` financial-access classification.
4. Add a stable Furnishings semantic role/account pointer and protect it.
5. Auto-enable the resolved Furnishings category for every project that can use inventory movements.
6. Add tolerant model decoding for v2 fields without changing authority.

Exit gate: current budgets reconcile before any inventory-ledger cutover.

### Phase 2 — Centralize existing movement writes

Implement the server request-doc domain writer while it still produces the current per-batch transactions. Route iOS, MCP inventory tools, composite flows, Quick Draft promotion, repricing, deletion/correction, and project-to-project movement through it.

Add operation IDs, deterministic results, payload conflict checks, atomic item re-reads, and request status UX.

Exit gate: no production-capable path can create or mutate an inventory movement outside the shared writer; retries and two-device races are tested.

### Phase 3 — Add v2 entries and aggregate in shadow mode

Deploy:

- movement-entry schema and indexes;
- managed aggregate transaction schema;
- occurrence-scoped item provenance;
- AR classification storage;
- v2 reconciliation jobs;
- rules denying direct client writes;
- dual-capable readers that still treat legacy as authoritative.

The centralized writer now writes both current per-batch records and v2 entries/aggregate in the same logical operation. V2 remains invisible/non-authoritative.

Exit gate: sustained exact parity between legacy signed totals and v2 aggregates for canary accounts, including retries, repricing, returns, deletions, and project-to-project operations.

### Phase 4 — Backfill historical evidence

Backfill with dry-run, allowlists, checkpoints, before snapshots, update-time preconditions, and resumable idempotency.

Rules:

- reconstruct per-item occurrences only when amount, tax, origin, and project episode are provable;
- preserve a stored multi-item transaction total as a signed `legacyBatch` entry when allocation is ambiguous;
- never infer historical discount/tax splits from current mutable item prices;
- preserve paid invoices and their original category snapshots;
- convert only item-like Additional Requests occurrences to the AR tag;
- retain non-item Additional Requests work under its correct accounting category/meaning;
- never delete or mark legacy movement transactions canceled to hide them.

Exit gate: every project is either exactly reconciled or explicitly blocked with a documented reason; no guessed allocations.

### Phase 5 — Make invoices, budgets, reports, and UI v2-ready

Before authority flips:

- add movement-entry invoice source identity and occurrence-level locks;
- decide and implement draft/sent/paid outbound behavior;
- implement AR overlay budgets and migrate budget allocations according to the approved policy;
- update project budget, project list summaries, MCP budget/analytics/resources, reports, closeout, exports, search, and transaction cards/details;
- add zero/negative ledger display;
- add paginated movement history and explicit correction actions;
- remove category selection from new movement UX;
- add old-client/version messaging.

Exit gate: all reads are version-aware and produce identical totals in legacy and shadow-v2 modes.

### Phase 6 — Canary authority flip

Set an explicit `inventoryLedgerAuthority` for allowlisted projects/accounts. Once set to v2:

- legacy movement rows are excluded from budgets/reports/list presentation;
- the v2 aggregate contributes exactly once;
- old client legacy writes are rejected or routed through compatibility ingestion;
- MCP/Admin operations enforce the same authority in code;
- hidden legacy records continue to be dual-written temporarily for rollback.

Monitor reconciliation, budget-summary parity, invoice totals, request failures, duplicate operation IDs, and old-client rejection rates.

Rollback is a flag flip only while dual-write remains healthy.

Exit gate: canary stability over an agreed accounting cycle with no unexplained drift.

### Phase 7 — General cutover and retirement

Expand authority gradually. After the rollback window:

- stop creating hidden legacy per-batch transactions;
- retain historical legacy documents read-only;
- remove old write code only after usage telemetry proves no callers remain;
- keep legacy readers for grandfathered data until a separate retirement decision;
- keep periodic v2 reconciliation permanently.

Destructive historical cleanup is not required for this product goal and should be a separate, explicitly approved project.

## Release gates and observability

No phase should advance without automated evidence.

Required metrics/alerts:

- aggregate/entry mismatch count and dollars;
- legacy/v2 shadow parity count and dollars;
- duplicate/replayed operation requests;
- operation ID payload conflicts;
- failed or partially processed request docs;
- active items missing occurrence references;
- orphan movement entries/aggregates;
- paid invoice lines missing immutable sources;
- settlement transactions included in spend (must be zero);
- projects missing/protecting the Furnishings role;
- AR subtotal outside Furnishings bounds where that is mathematically invalid;
- old-client legacy-write rejections after cutover;
- Firestore transaction abort/contention and write-count failures.

Every migration cohort should emit a signed/hashable manifest with before/after totals and blocked records.

## Required test matrix

### Domain and concurrency

- first movement creates one aggregate and one positive occurrence per item;
- later movement reuses the aggregate without rewriting earlier occurrences;
- project exit creates negative occurrence using the correct price basis;
- project-to-project creates correlated negative/positive legs atomically;
- one item can cycle through the same project multiple times;
- retry with same operation ID/payload is an exact no-op;
- same operation ID/different payload is rejected;
- concurrent first writes create one aggregate;
- simultaneous reprice/return/delete resolves without double application;
- positive, zero, and negative nets display and aggregate correctly;
- batch limits remain under Firestore write ceilings.

### Corrections and collection

- uncollected erroneous occurrence can be voided without erasing audit;
- legitimate return preserves earlier history;
- collected occurrence blocks destructive correction;
- paid correction produces explicit credit/reversal;
- future occurrences for the same item/project are not locked by old paid invoices;
- sent invoice exit behavior matches the approved policy;
- project-origin and inventory-origin negative movements use the approved client-credit rules.

### Budgets and Additional Requests

- aggregate net equals signed entry sum;
- Furnishings spends exactly once in legacy, shadow, and v2 modes;
- settlements never contribute to spend;
- AR spend equals signed tagged subset;
- AR does not double-count overall spend;
- AR budget allocation migration preserves the approved overall-budget policy;
- source and destination projects can classify the same item differently;
- negative tagged movement reduces only the appropriate project's overlay.

### Billing, reports, and visibility

- movement occurrence invoice sources remain stable across repeat cycles;
- paid line snapshots remain immutable while aggregate changes later;
- client summary shows Furnishings plus non-additive AR subset;
- reports include departed/deleted item snapshots and reversals;
- movement-detail export reconciles to summary row;
- restricted-user visibility treats Furnishings settlement correctly;
- Billing Summary labels distinguish cost, budget spend, demand, and collection.

### Security, migration, and rollback

- direct client aggregate/entry mutation and linked-item deletion are denied;
- Admin/domain writer rejects the same invalid states despite rule bypass;
- production rules and rule tests match;
- dry-run/backfill is idempotent and resumable;
- ambiguous historical batches preserve stored totals without invented allocation;
- authority flip never counts legacy and v2 together;
- rollback restores legacy authority with exact parity;
- old clients cannot silently write stale per-batch state after cutover.

## Decisions requiring product discussion before implementation

### A. Additional Requests budget allocation

Is an Additional Requests budget:

1. an informational cap already contained inside Furnishings/Overall; or
2. approved incremental budget that increases Overall while its spend remains an overlapping Furnishings subset?

This is the most important unresolved budget decision because existing projects may have treated the two category budgets as additive.

### B. Sent-but-uncollected invoice behavior

When an item exits after an invoice was sent but before collection, should Ledger:

- keep the original visible line and append a negative line (recommended for auditability); or
- silently remove/recalculate the line because sent invoices remain live?

Draft invoices can reasonably remain fully live; sent invoices need an explicit client-communication policy.

### C. Which negative movements are client credits

Every project-to-inventory sale reduces project budget spend. Does every such sale also reduce client demand, or only one tied to a previously billed/client-owned positive occurrence? The latter is safer and avoids creating cash credits from pure internal accounting movement.

### D. Additional Requests tag mutability

Can the classification change after an invoice is sent or paid? Recommended:

- editable with audit before collection;
- frozen on collected invoice snapshots;
- any later reporting reclassification requires an explicit correction event.

### E. Inventory-side experience

Should Business Inventory show:

- a cross-project movement activity feed; or
- only items and inventory acquisition records, leaving the one net transaction solely in each project?

### F. Lifetime transaction terminology and date

Recommended label: **Inventory Activity**. Recommended list sort: `lastMovementAt`; detail retains creation date and every operation date. Confirm whether the transaction should remain at one stable list position or rise on new activity.

### G. Historical presentation

Recommended: do not merge old documents destructively. Hide reconciled legacy movement rows behind the new summary with an expandable “legacy history” view or export. Confirm how much historical batch detail should remain visible in the ordinary UI.

## Specifications and code surfaces that must change

### Specifications

- `docs/specs/sale-transactions.md` — replace per-batch authority with v2 aggregate/entry contract; preserve a legacy section.
- `docs/specs/canonical-sales.md` — distinguish the failed mutable aggregator from the new entry-backed materialized view.
- `docs/specs/data-model.md` — add managed aggregate, movement entry, occurrence linkage, AR overlay, authority flag, and invoice provenance.
- `docs/specs/inventory-as-store.md` — update movement output, provenance, display, and migration.
- `docs/specs/lineage-tracking.md` — connect lineage to occurrence IDs and repeat cycles.
- `docs/specs/reassign-vs-sell.md` — keep correction versus financial movement distinction.
- `docs/specs/budget-management.md` — signed v2 net, settlement exclusion, AR non-additive overlay, authority switching.
- `docs/specs/billing-invoicing.md` — movement-entry source, occurrence locks, sent/paid credit behavior.
- `docs/specs/project-closeout-report.md` and `docs/specs/reports.md` — Furnishings plus “of which AR,” signed history.
- `docs/specs/transaction-completeness.md` — entry reconciliation rather than current membership.
- `docs/specs/write-tiers.md` — designate inventory movement as a request-doc domain operation.
- `docs/specs/financial-access-controls.md` — align payment classification.
- `docs/specs/item-entry-flow.md` — remove stale single-Furnishings-transaction and Additional Requests category contradictions.
- `docs/specs/_index.md` and `_changelog.md` — establish the new canonical spec status when approved.

### iOS

- models: `Transaction.swift`, `Item.swift`, `Invoice.swift`, `BudgetCategory.swift`, budget summary models, shared enums;
- writes: `InventoryOperationsService.swift`, item/transaction deletion and association services, repricing/request services;
- state: account/project subscriptions and a movement-entry repository/paginated detail loader;
- movement UI: Sell to Project, Move/Sell to Inventory, Return to Project, Add Existing, project-to-project flows;
- transaction UI: list grouping, card calculations, menu builder, detail, sorting, search, delete/correction actions;
- budget: `BudgetTabCalculations.swift`, `BudgetProgressService.swift`, project summary presentation;
- billing: invoice-line calculations, collection/credit service, Billing Summary, financial access;
- reports/exports: report aggregation, closeout/client summary, CSV field and row calculations;
- tests: execution/integration inventory operations, budget, invoice service, billing summary, reports, rules-facing behavior.

### MCP and backend

- types/schema/server guidance for managed ledgers, entries, AR overlay, invoice source, and removal of category input;
- inventory operations, composite tools, Quick Draft promotion, item deletion, transaction actions;
- one shared server domain writer with request/idempotency handling;
- repricing trigger/logic and occurrence-scoped collection checks;
- budget normalizer, budget tool, analytics, resources, and server summaries;
- invoice creation/collection/credit provenance;
- project budget-summary and completeness triggers;
- Firestore rules, test rules, indexes, and rule tests;
- dry-run/backfill/reconciliation/rollback scripts;
- MCP and Functions deployment sequence plus compatibility/version gating.

## Evidence base and confidence

This report is based on the current repository specifications, implementation, tests, prior migration artifacts, and three focused read-only code audits covering iOS movement behavior, budgets/billing/reports, and backend/MCP/migration surfaces.

Highest-confidence findings:

- a mutable single-document aggregator is unsafe;
- signed occurrence-level evidence is required;
- current amount/type semantics cannot represent a negative net cleanly;
- Furnishings lacks durable protected identity;
- Additional Requests cannot be implemented with the current exclusive category field;
- invoice provenance/locks must become occurrence-scoped;
- all movement writers must be centralized and idempotent;
- legacy and v2 authority must be mutually exclusive during cutover;
- ambiguous historical amounts must not be reverse-engineered from mutable current prices.

Evidence gap:

- no fresh production read-only cohort audit was run in this research pass because current production credentials were not available in the shell environment. Historical audit artifacts prove that ambiguous Additional Requests and category/membership anomalies exist, but they do not establish current counts. Phase 0 must close that gap.

Repository-state caveat:

- the working tree was already dirty and one commit behind `origin/dev` during research. Existing uncommitted files—including transaction-deletion work—were treated as design evidence only, not shipped behavior. This report is the only file added by this research task.

## Historical final recommendation — rejected

Approve the direction, but define it precisely as:

> One stable, project-scoped Inventory Activity transaction is the user-facing and budget-facing materialized view of immutable signed inventory movement occurrences. Furnishings is its protected accounting category. Additional Requests is a project-specific, non-additive tagged subtotal of those occurrences. Legacy movement transactions remain intact until a reconciled, reversible authority cutover is complete.

That gives the user the cleaner accounting surface they want without discarding the history, concurrency safety, invoice specificity, and rollback capacity the system needs.

</details>
