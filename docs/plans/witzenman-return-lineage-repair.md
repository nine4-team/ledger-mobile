# Witzenman Return lineage repair — implementation handoff

Status: proposed implementation plan; no repair or deployment authorized by this document alone.
Prepared 2026-09-18. The current request is to prepare this plan, not execute production changes.

## 1. Objective and non-negotiable rules

The Witzenman inventory Return must describe the items returned and the credit issued. A subsequent inventory sale is a separate event. Returns must not be source or destination transaction endpoints of `sold` or `soldToInventory` intent edges, and must not display a Sold Items subsection or sold-item audit totals.

Preserve actual inventory sales, destination Purchases, return credits, item locations, invoice history, and historical evidence. Do not relabel genuine `sold` edges as `returned`. Do not redirect them to the consolidated Witzenman Sale: that Sale represents the business acquiring project-origin items, not later inventory resales.

Distinguish intent edges from association history. An `association` edge may record that an item was linked to Return R before Purchase P. That is a historical link change, not a sale attributed to R. Full item history remains available by item ID. This plan deliberately allows that association history; the forbidden endpoints apply to sale intent edges.

## 2. Evidence, including corrections to earlier explanations

- Account: `1dd4fd75-8eea-4f7a-98e7-bf45b987ae94`.
- Project: `5abd46c9-9886-4b3e-b2b1-19f6cf995a44` (Witzenman’s 2nd Home). Do not use the incorrect project ID ending `bf45b987ae94` from earlier conversation summaries.
- Return: `CONSOLIDATED_5abd46c9-9886-4b3e-b2b1-19f6cf995a44_outbound_return`.
- Original backup: `docs/plans/witzenman-inventory-consolidation-backup-2026-09-18.json`, committed and pushed in `8513d5cf`.
- Exact pre-write backup: `tmp/witzenman-inventory-consolidation-commit-backup-2026-09-18.json`.
- The Git backup contains 28 transaction documents, 341 current item documents, and 1,014 lineage documents. It is not a complete backup of all historical items, invoices, attachments, or account data.
- The operation created Purchase/Return/Sale replacements and deleted the originals. Return amount/subtotal: 152831/152380 cents. The then-current project spend was 15585055 cents. That old spend is historical evidence, not the expected total for a later repair.
- The reported Sold Items section contains **22 unique items**. The previous claim of three was wrong: the diagnostic incorrectly let `association` edges participate in latest-movement selection. The app filters association edges out first.
- Of those 22 sale edges, 21 predate consolidation: 16 from `BC3D4934-3EFB-4A0E-9511-ECA18352D2BE`, three from `iTGI4u24SoiOApf1UD7B`, and two from `3h7cyd9AxKp2nDmcLHXx`.
- One additional app-created sale edge is `b2zeto3LmlA7A1IBXuMm`, item `cW5PaCT7DF7NrY8aEXvf`, destination Purchase `BB168242-54DC-4414-9425-B5D884C2422B`, created `2026-09-18T20:08:00.677Z`. It occurred after consolidation and must survive the repair.
- At the last investigation the Return had 33 active item IDs, 109 outgoing edges, and an audit reporting 22 sold items / 51253 cents, variance 28175 cents, and `isComplete: false`. Refresh all of this before implementing a production manifest.
- Firestore Timestamp handling in `computeIsComplete` is defective (`instanceof Date` on Firestore timestamps). It does **not** explain the 22 visible sold items. Do not claim fixing it resolves this incident.

## 3. Root cause and responsibility

The pre-existing model overloaded `fromTransactionId`: it represented both a previous item link and the source of a financial movement. Inventory sale writers copied `item.transactionId`, including when it was a Return. Transaction-detail and audit readers then treated any outgoing sale edge as evidence that the source transaction had sold an item.

Consolidation carried these pre-existing sale edges onto the aggregate Return and removed stale current memberships. It preserved transaction totals and referential connectivity, but did not validate transaction-type semantics, historical Return membership, or audit reconciliation. Item relinks also generated 341 association edges and 34 synthetic returned edges through the server trigger. Those 34 can become Return-to-itself intent edges after remapping. Inventory movement did not actually happen during consolidation.

The repair must address writers, readers, historical Return membership, and migration-generated intent. Merely hiding the section is insufficient. Restoring the entire old backup would erase later valid actions and restore the original semantic problem.

## 4. Read these files before editing

- `LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift`: inventory sale, project-to-project transfer, return-to-inventory, Sale-to-Inventory, Return-to-Project, and `inventoryEntrySnapshotFields`.
- `mcp-server/src/tools/inventory-operations.ts`: matching movement writers. Swift and MCP currently differ on project-to-project second-hop endpoints.
- `LedgeriOS/LedgeriOS/Services/LineageEdgesService.swift`: model and queries.
- `LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift`: `loadLineageItems`, `soldItemsSection`, `itemsSection`, and audit presentation.
- `LedgeriOS/LedgeriOS/Views/Projects/TransactionAuditPanel.swift`.
- `LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift`: full history labels for a null source transaction.
- `firebase/functions/src/index.ts`: `onItemTransactionIdChanged`, `onLineageEdgeCreated`, `onTransactionWritten`, item-price triggers, and `computeIsComplete`.
- `firebase/functions/src/transactionAuditPricing.ts`.
- `LedgeriOS/LedgeriOS/Logic/InvoiceLineCalculations.swift` and inventory origin/provenance resolvers: sale destination queries must continue working with a null source transaction.
- `scripts/consolidate-witzenman-inventory-transactions.mjs`: retain as evidence; do not reuse its commit path for this repair.
- `docs/specs/lineage-tracking.md`, `return-and-sale-tracking.md`, `inventory-as-store.md`, `sale-transactions.md`.

There are unrelated working-tree edits, including inventory specifications and UI files. Read `git diff` first and preserve them. Some current specs already describe immutable inventory-entry amounts. Reuse that contract where applicable; do not replace concurrent work with an older description.

## 5. Explicit model decisions

### 5.1 Sale intent endpoints

For inventory → project `sold` events:

| Situation | fromTransactionId | fromProjectId | toTransactionId |
| --- | --- | --- | --- |
| Inventory item whose previous transaction is a Return | null | null | actual destination Purchase |
| Second hop of project → inventory → project | null | null | destination Purchase |
| Ordinary inventory purchase provenance, source is an existing non-Return purchase | retain valid purchase source | null | destination Purchase |

Do not invent a placeholder inventory transaction. Null already represents inventory without a source financial transaction. For a project transfer, the first-hop `returned` or `soldToInventory` edge retains the source-project exit; the second hop represents inventory as its source. Use the two events and item history to describe the full transfer.

`soldToInventory` is project-origin item acquisition by the business. Its source must be a valid project transaction and its destination the actual Sale-to-Inventory transaction; neither endpoint may be a Return. Block malformed new operations rather than reclassifying them automatically.

Do not globally clear sale sources: normal Purchase histories still need legitimate outgoing sold edges. Do not add a previous-Return endpoint under a new name on sale intent rows; preserve link history in association edges and repair evidence.

### 5.2 Return membership is historical, itemIds is current

Add an additive transaction field `returnedItemIds: [String]`, representing every item included in that Return event. It is a historical set and survives later resale. Keep `itemIds` as existing active membership, so origin checks, Return-to-Project eligibility, and current inventory selection remain compatible.

Populate `returnedItemIds` in every new Return writer (inventory and vendor; discover all with repository search). It must be written atomically with the Return. Subsequent sales can remove `itemIds` but must never remove `returnedItemIds`. A correction that changes the actual Return requires an explicit correction path and preserved evidence.

Return detail should display historical members as the Return's items, including items subsequently moved elsewhere. Historical-only rows must be read-only for bulk movement actions; do not make items in another project eligible for movement by merely displaying them. Label later location/history separately without a Sold Items subsection. Do not set their current item status to returned.

For legacy Returns without `returnedItemIds`, derive a read-only fallback from active IDs plus valid incoming `returned` intent edges. Never use arbitrary association edges or outgoing sales alone as proof of a return. If evidence is incomplete, show that limitation; do not silently report an empty/complete Return.

### 5.3 Financial snapshots and audit

Return membership and Return value must survive changes in the item's current price. Prefer an explicit versioned Return snapshot:

`returnSnapshot: { version: 1, subtotalCents: integer, amountCents: integer, source: 'movement' | 'verifiedLegacy', lines: [{ itemId, subtotalCents, amountCents }] }`.

For new Returns, calculate lines from the actual operation's existing pricing/tax rules and store them in the same atomic write. Check line sums against transaction totals. Do not substitute today's prices for a historic Return.

For the consolidated legacy Return, per-item amounts may not be provable. Do not allocate a total evenly, use current item prices, or claim the old audit is reliable. Use an additional legacy snapshot form with `components: [{ sourceTransactionId, subtotalCents, amountCents, returnedItemIds, evidencePaths }]`, no invented line prices, and explicit `lineAmountsVerified: false`. Sum the backed-up original Return components to the unchanged consolidated totals. Preserve original raw audits in the backup/evidence, not as proof of per-item prices.

The audit must distinguish verified aggregate transaction totals from unverified line amounts. A component-sum check cannot mark item-level reconciliation complete. Design an explicit pending/manual-reconciliation state if existing audit fields cannot express this; keep `isComplete` false while line reconciliation is unresolved. Never manufacture a zero variance by assigning stored subtotal to a calculated item sum.

For Returns with proven snapshots, compute using those snapshots and historical membership. For legacy incomplete snapshots, expose unresolved reconciliation. Return audits must not include `soldItemsCount`/`soldItemsSumCents` as sale categories. Hiding them must not silently remove their historical Return membership or value.

## 6. Implementation sequence

1. Add model decoding, snapshot validation, and shared pure classification helpers in Swift and TypeScript. Optional fields keep old documents decodable. Tests must cover both old and new records.
2. Update Return creation writers and inventory sale/transfer writers. Resolve source transaction type from actual transaction data before emitting an edge. If a non-null source cannot be resolved, block the write with a clear error; do not guess from item status. All affected writes remain atomic.
3. Update both Swift and MCP project-transfer second hops to the same inventory-source semantics. Preserve the first-hop exit and existing transaction amounts. Audit other sale writers, including creation/import/quick-draft paths, with `rg`; apply the invariant wherever a Return can be selected as source.
4. Update the transaction detail loader and renderer: Return type excludes sold classification, Sold Items section, sold-item badges, and stale stored sold audit values. Use historical membership for Return content. Pass transaction type into audit presentation if necessary. Extract classification into a testable helper rather than duplicating filters.
5. Update backend Return audit calculation and all relevant recomputation paths. Ensure item-price changes cannot rewrite historical snapshot values. Fix timestamp comparison with `toMillis()` (Date fallback only for genuine Date inputs), using deterministic ID tie-breaking. This is a separate defect; retain separate tests.
6. Address automatic trigger intent: `onItemTransactionIdChanged` must not infer a physical return solely from a link change into a Return. Inspect all direct-link workflows before removing this behavior. Preferred contract: explicit return operations atomically emit return intent; the generic trigger emits association only. If direct-link-to-Return is a supported user return operation, route it through that explicit operation before removing trigger inference. Do not silently remove an existing flow's only intent writer.
7. Add backend validation/diagnostics for invalid sale endpoints. Firestore client rules can reject Return sale endpoints where compatible with batched new documents using `getAfter`; evaluate access-call limits with bulk operations. Admin/MCP writes bypass client rules and require their own validation. Do not ship an untested rules restriction that breaks movement batches.
8. Update specs to document the new sale-source contract, historical Return membership, snapshots, and the distinction between intent and association history. Existing append-only lineage policy needs an explicit narrowly scoped migration exception for this repair, not a general license to rewrite history.
9. Build a separate dry-run-first repair tool and evidence report as below. Do not deploy or repair merely because this plan exists.

## 7. Repair inventory and exact selection rules

Create `scripts/repair-witzenman-return-lineage.mjs` and a companion fixture test. Default execution is read-only. Implement `--plan`, `--backup-only`, `--apply --manifest <path> --backup <path>`, and `--verify`. Applying requires an exact reviewed manifest and backup; it must not rediscover and expand targets.

Inputs: original Git backup, exact commit backup when available, and fresh live reads. Verify originals have the expected account/project; compare the two backups and report any differences. Fetch current documents for every historic item needed, because the old backup only contains then-active items.

Generate the original 21 sale-edge candidates from the backup with this exact predicate:

```
originalReturnIds = IDs of backup.transactions with normalized type == 'return'
originalSaleEdges = backup.lineageEdges where
  edge.data.fromTransactionId in originalReturnIds AND
  edge.data.movementKind in ['sold', 'soldToInventory']
```

Expected baseline: 21 edges / 21 unique items. Group by original source: 16/3/2 as listed above. Derive IDs from the backup; do not select all edges with an inventory label.

Match each live edge by its exact original edge ID. Verify item ID, kind, destination ID, event timestamp, and consolidation metadata against evidence. The current source should be the consolidated Return. Any mismatch goes to an unresolved report and blocks applying the entire manifest.

Query current outgoing sale edges from the consolidated Return to identify post-consolidation events. The known 22nd edge is `b2zeto3LmlA7A1IBXuMm`. Verify its current destination, item, and timestamp independently. Preserve this actual sale and its destination Purchase. New events discovered since planning require a new reviewed manifest, not an automatic extension at apply time.

For each proven inventory-resale edge: preserve ID, item, movement kind, destination transaction/project, creation time, actor and note; set `fromTransactionId: null` and `fromProjectId: null`. Store the exact before/after record and reason in an immutable repair journal/backup, with `repairVersion` and journal reference on the repaired edge if needed. This is an explicit audited exception to append-only history. Do not replace its actor/time with the repair actor/time.

Verify the item's full association history still explains link continuity. If missing, produce a proposed deterministic correction-history record based on proven before/after evidence, not a fake new sale/return event. Include every such create in the reviewed manifest.

Build historical Return membership per original Return from the union of backed-up `itemIds` and valid incoming `returned` edges. Cross-check outgoing resale items against that membership; outgoing resale alone is not proof. Deduplicate duplicate app/server representations of the same return event. Keep component event identity: one item could have been returned more than once, so a unique item set cannot substitute for financial line counts.

Union component memberships into consolidated `returnedItemIds`, preserve component evidence and amounts, and keep live `itemIds` unchanged. Do not restore the pillow to the old Return's active membership. It belongs to the post-consolidation Purchase.

Separately inventory synthetic `returned` edges created by consolidation relinks. Candidate evidence must include server source, original source in the backed-up Return set, destination the consolidated Return, item in the 34 relinked return items, and creation in the consolidation window. A self-loop alone is not sufficient evidence. Confirm expected 34 against live evidence. Proposed correction: change proven migration-only `returned` intent to `association`, preserve original payload in the journal and explain the non-movement relink. Do not touch genuine incoming returns. Deduplicate display/audit reads by item/event rather than deleting association history.

Inspect `inventoryEntryTransactionId` and other item/reference fields for deleted original IDs. Report all findings. Only remap fields with proven meaning and full before/after evidence; a remap must preserve the original amount/category snapshot. Invoices, paid charges, attachments, or unrelated project data require a separately reviewed scope if they need mutation.

## 8. Concrete manifest, backup, and execution requirements

Each manifest operation contains full document path, exact `updateTime` (seconds and nanoseconds), typed before image, field-level after patch, reason code, evidence IDs, and expected resulting invariants. Include the original-to-consolidated mapping and operation counts. Canonicalize and hash the manifest.

The report must show all 22 known items individually, original Return, sale destination, present project/transaction, current price versus proven historical price if available, and the exact proposed change. Unknowns are explicit. Include aggregate Return membership and component sums, synthetic-intent candidates, all destination transaction totals, and current budget/invoice baselines.

Back up ALL documents to be changed plus referenced evidence before mutation. Use a lossless Firestore codec for Timestamp, reference, bytes, GeoPoint and nested values; test restoration. Persist, fsync, read back, verify hashes, and record the manifest hash. Backups must be exclusive-create and must never overwrite the original backup.

Before production application, commit and push the new repair backup and manifest to the same user-authorized repository, then verify the remote commit contains those exact hashes. Do not put service-account keys in Git. The original backup is essential historical evidence but does not substitute for backing up current state, which includes later user activity.

Prefer one atomic Firestore transaction/batch for this bounded repair if actual write count and size fit. Apply exact update-time preconditions to every edited document and read/check any dependencies on which the repair relies. If a dependency changed, stop before writes and generate a new plan. Never ignore changed audit fields merely to make a stale plan apply. If batching is necessary, document a resumable state machine before execution; do not improvise partial writes.

Verify no unlisted document changed because of the tool. Account for server-trigger writes separately. Deployment order: compatible readers and backend audits, corrected writers/trigger behavior, then production repair once old writers are handled. Old app versions can recreate invalid edges: explicitly test and document prevention through rules/server mediation, or establish a maintenance/version gate. A one-time quiet query does not prove prevention.

Prepare a rollback manifest using exact before images and post-write preconditions. Restore only repair-owned fields; never restore the entire account or overwrite later user operations. Reconciliation with newer writes is manual if rollback preconditions fail.

## 9. Required tests and acceptance criteria

1. Regression fixture matching the actual client filter: 22 unique sold items plus newer association edges still yields 22 before the fix. This catches the earlier incorrect three-item diagnostic.
2. Return with a genuine later resale: no Sold Items UI/audit category; the returned item remains in Return history; destination Purchase and item current location remain correct.
3. Ordinary inventory Purchase with later sales still displays its valid sold history.
4. Vendor Return and inventory Return both maintain historical membership; item-price/tax changes do not alter snapshot totals.
5. Swift and MCP inventory sale from a Return emit null sale source, null source project, actual destination Purchase, and accurate association history.
6. Both project-transfer branches: inventory-origin uses first-hop Return; project-origin uses Sale-to-Inventory. Second-hop sold edge starts from inventory in both writers. Verify both budgets, categories, item location, and immutable amounts.
7. Existing Return-to-Project/Sale-to-Inventory eligibility and `inventoryEntry*` snapshot behavior continue working. Do not treat inventory-origin Returns as Return-to-Project candidates.
8. Repair fixture: 21 original edges + later pillow sale; 34 synthetic intent candidates; duplicate app/server history; repeat return of one item; missing evidence; concurrent edits; rerun idempotency; lossless backup and rollback.
9. Timestamp helper accepts Firestore Timestamp and Date, handles missing timestamps and ties deterministically. Do not attribute the 22-item incident to this defect.
10. Generic association relink cannot create a physical return; genuine return operations still produce their explicit return event. Include delayed/retried trigger cases.
11. Legacy component snapshots preserve exact totals but never claim verified item-level amounts without evidence.
12. Missing/deleted historical items produce visible unresolved evidence rather than silent omission or falsely complete audits.

Run focused Swift unit/execution tests in the existing test setup, functions `npm test`, and MCP `npm run build` plus appropriate pure tests. The MCP default `npm test` intentionally fails; read its package scripts rather than treating that as a product defect. Use isolated mocked/unit fixtures for repair tests. Do not use production records as a mutation smoke test. Follow repository rules for explicit emulator integration tests and production-backed normal launches.

Post-repair read-only verification must prove:

- No `sold`/`soldToInventory` intent endpoints name this Return.
- All actual destination sales/Purchases and current item locations are preserved.
- Return detail presents historical members, zero Sold Items, and accurate snapshot/reconciliation status.
- Genuine returned edges and the item history remain available; synthetic migration intents no longer masquerade as returns.
- Return stored amount/subtotal remain 152831/152380 unless a separately authorized accounting correction changes them.
- Project spend and invoices match the freshly recorded pre-repair baseline; do not insist on the historical 15585055 value after later user activity.
- Repeating verification after triggered work finishes yields the same result, and tested old/new writer behavior cannot immediately recreate the problem.

## 10. Handoff and stop conditions

Deliver code, meaningful tests, updated specs, a complete dry-run manifest, a before/after report, and rollback instructions. Resolve any ambiguous item or valuation evidence before proposing production application. A correct partial model fix may be reviewable while historical line pricing remains unresolved; state that explicitly rather than inventing reconciliation.

This plan does not authorize restoring the old consolidation, deleting further financial records, changing invoice totals, deploying a release, or applying the new repair. Prepare the concrete result first. Obtain approval for the new production repair/deployment after the user can review its exact scope. Preserve the user's standing requirement that backups be pushed before production mutation.
