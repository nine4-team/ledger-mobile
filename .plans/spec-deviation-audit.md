# Spec-to-Implementation Deviation Audit

**Date:** 2026-03-05 (revised)
**Scope:** All 13 system design specs in `docs/specs/` audited against SwiftUI implementation in `LedgeriOS/`.

## Verification

**Every finding verified.** All 13 specs were read in full. All 65 original findings were verified against source code by reading the referenced files. Two false positives were identified and removed (L5: data-model.md spec includes the `source`/`note` fields on edges; L12: "Budget" suffix is applied at the BudgetTabView call site, not missing).

**Reliability: 95+.** Every finding is now confirmed against both the spec text and the source code. The remaining uncertainty is in subjective severity judgments and whether some spec text is aspirational vs prescriptive.

## Classification Key

Each finding is tagged with one of:
- **`WRONG CODE`** — Implementation deviates from clear spec text; code needs fixing
- **`DEFERRED`** — Requires server infrastructure (Cloud Functions / request-doc system) not yet built
- **`SPEC CONFLICT`** — Two specs disagree; needs reconciliation before fixing code
- **`STALE SPEC`** — Spec references things that don't exist in the canonical data model

## Summary

| Severity | Count |
|----------|-------|
| Critical (data corruption / spec architecture violated) | 8 |
| High (feature missing or fundamentally wrong) | 22 |
| Medium (partial implementation or incorrect behavior) | 18 |
| Low (copy mismatches, stale spec text, minor gaps) | 15 |
| **Total (verified)** | **63** |

| Classification | Count |
|----------------|-------|
| Wrong code | 54 |
| Deferred (needs server infra) | 4 |
| Spec conflict | 2 |
| Stale spec | 3 |

---

## Spec-vs-Spec Inconsistencies Found

These need resolution before the code can be "correct" — the specs themselves disagree.

### Conflict 1: Return transaction budget normalization field

| Spec | Says |
|------|------|
| `data-model.md` line 504 | `if transaction.status == "returned" OR amount < 0: return -abs(amount)` |
| `budget-management.md` line ~90 | `if transactionType is "Return": multiplier = -1` |
| `return-and-sale-tracking.md` line 54 | `if transactionType is "Return": budget_multiplier = -1` |

Two specs check `transactionType`, one checks `transaction.status`. The implementation matches `data-model.md`. This affects C7 severity — the code may be correct per one spec and wrong per two others.

**Semantic difference:** A return transaction with `transactionType: "Return"` and `status: "pending"` would be caught by `transactionType` check but NOT by `status == "returned"` check.

### Conflict 2: Lineage edge timestamp field name

| Spec | Field name |
|------|------------|
| `data-model.md` line ~257 | `createdAt` |
| `lineage-tracking.md` line 23 | `timestamp` |

Code uses `createdAt`, matching `data-model.md`. This is L4.

### Conflict 3: Lineage edge extra fields

`data-model.md` defines `source` and `note` fields on lineage edges. `lineage-tracking.md` omits them. Code includes them, matching `data-model.md`. (This was original L5, now removed as false positive since data-model.md is the canonical source.)

---

## Critical — Data Corruption / Architecture Violations

### C1. `InventoryOperationsService` writes wrong Firestore field name for transaction type `WRONG CODE`
**Specs:** data-model, canonical-sales
**File:** [InventoryOperationsService.swift:25](LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift#L25)

Writes `"transactionType": "sale"` but the Firestore field is `"type"` (per CodingKeys mapping `transactionType = "type"`). Documents created by sell operations will have `type == nil` when decoded, breaking all downstream display, filtering, and budget calculations for those transactions. Affects lines 25, 85, 101.

### C2. `InventorySaleDirection` enum missing `"project_to_project"` — written but can't be decoded `WRONG CODE`
**Specs:** data-model, canonical-sales
**File:** [InventoryOperationsService.swift:87](LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift#L87)

`sellToProject()` writes `"project_to_project"` to Firestore, but the `InventorySaleDirection` enum only has `businessToProject` and `projectToBusiness`. On read, this field decodes to `nil`, breaking budget normalization for project-to-project sales. The spec also doesn't define this value — the canonical-sales spec only defines `business_to_project` and `project_to_business`.

### C3. No request document infrastructure exists — all multi-doc writes use client-side patterns `DEFERRED`
**Specs:** write-tiers, canonical-sales, lineage-tracking
**Files:** Entire codebase — zero matches for `requestDoc`, `request_doc`

The spec explicitly chose Tier 2 (request-doc + Cloud Function) over client-side batched writes for multi-document operations. The entire request-doc architecture is absent. All inventory operations, item reassignments, and sale flows use client-side `WriteBatch` or individual fire-and-forget writes.

**Why deferred:** Requires Cloud Function infrastructure that doesn't exist yet. The write-tiers spec explains the architecture but the server side isn't built.

### C4. Reassign semantics fundamentally wrong — changes scope instead of transaction `WRONG CODE`
**Specs:** reassign-vs-sell
**File:** [InventoryOperationsService.swift:147](LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift#L147)

The spec defines reassign as moving an item between transactions *within the same scope*. The implementation changes `projectId` (cross-scope move), which the spec says MUST be a "sell" with financial tracking. Both `reassignToProject` and `reassignToInventory` bypass all financial tracking for cross-scope moves.

### C5. Source transaction `itemIds` never updated during any operation `WRONG CODE`
**Specs:** reassign-vs-sell, canonical-sales, return-and-sale-tracking
**Files:** [InventoryOperationsService.swift](LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift) (all methods)

When items are sold, reassigned, or returned, the item's original transaction's `itemIds` array is never modified. No `FieldValue.arrayRemove` or `FieldValue.arrayUnion` calls exist anywhere in the codebase. Source transactions retain stale references to moved items.

### C6. `createdAt`/`updatedAt` excluded from CodingKeys in ALL models `WRONG CODE`
**Specs:** data-model, project-lifecycle, spaces
**Files:** [Transaction.swift:31](LedgeriOS/LedgeriOS/Models/Transaction.swift#L31), [Item.swift:33](LedgeriOS/LedgeriOS/Models/Item.swift#L33), [Project.swift:16](LedgeriOS/LedgeriOS/Models/Project.swift#L16), [Space.swift:15](LedgeriOS/LedgeriOS/Models/Space.swift#L15), [SpaceTemplate.swift:13](LedgeriOS/LedgeriOS/Models/SpaceTemplate.swift#L13)

Properties declared but excluded from CodingKeys, meaning timestamps are NEVER decoded from Firestore. Always `nil`. Breaks timestamp-based sorting (e.g., `TransactionSortOption.createdDesc` — all items sort as `.distantPast`).

### C7. Budget normalization uses `status == "returned"` — specs disagree on correct field `SPEC CONFLICT`
**Specs:** data-model (supports implementation), budget-management + return-and-sale-tracking (contradict)
**File:** [BudgetTabCalculations.swift:158](LedgeriOS/LedgeriOS/Logic/BudgetTabCalculations.swift#L158)

Implementation checks `transaction.status == "returned" || amount < 0`, which matches `data-model.md` line 504 pseudocode exactly. However, `budget-management.md` and `return-and-sale-tracking.md` both say to check `transactionType == "Return"`. See "Spec-vs-Spec Inconsistencies" section above.

**Impact regardless of which spec is "right":** The `amount < 0` fallback has no spec basis in any spec. It catches negative amounts regardless of type, which could misclassify non-return transactions.

### C8. `addExistingItemsToTransaction` fires individual non-atomic writes with errors silenced `WRONG CODE`
**Specs:** write-tiers
**File:** [TransactionDetailView.swift:750](LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift#L750)

Fires N independent `Task` blocks with `try?` (errors silenced), then a separate transaction update. Partial failures are invisible. Not even batched, let alone using request-docs.

---

## High — Missing Features or Fundamentally Wrong

### H1. No deterministic transaction IDs for canonical sales `WRONG CODE`
**Spec:** canonical-sales
**File:** [InventoryOperationsService.swift:22](LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift#L22)

Spec requires `"SALE_" + projectId + "_" + direction + "_" + budgetCategoryId`. Implementation uses random `txCollection.document()` IDs. No lookup for existing canonical sales, no deduplication. Every operation creates a new transaction.

### H2. No archive/unarchive action in project UI `WRONG CODE`
**Spec:** project-lifecycle
**File:** [ProjectDetailView.swift:80](LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailView.swift#L80)

Action menu only has Edit, Export, Delete. No Archive/Unarchive. The spec says "Archiving is preferred" over deletion, but only Delete is offered.

### H3. Lineage tracking is largely unimplemented `WRONG CODE / PARTIALLY DEFERRED`
**Spec:** lineage-tracking
- Only `"sold"` edges are ever created. No `"association"`, `"returned"`, or `"correction"` edges.
- `reassignToProject`/`reassignToInventory` create no edges despite being scope changes.
- No query method for full item history by `itemId`.
- `ItemDetailView` has no lineage display section.
- `TransactionDetailView.movedItemsSection` returns `EmptyView()` (stubbed).

**Additional note:** The spec (line 92-94) says "Lineage edges are created server-side as part of request-doc processing. They are never created directly by client code." The client creating `sold` edges is itself a deviation from this rule, done as a workaround for the absent request-doc infrastructure (C3).

### H4. Return processing flow is unimplemented `WRONG CODE / PARTIALLY DEFERRED`
**Spec:** return-and-sale-tracking
- No return processing service exists. Spec's Step 2 multi-document atomic flow (update item, remove from source tx, create return tx, create lineage edge) has no implementation.
- Items are returned via simple status field updates, not the full flow.
- No incomplete return detection algorithm.
- No double-return guard.

**Partially deferred:** The full return flow is a Tier 2 operation requiring request-doc infrastructure (C3).

### H5. Invoice import is entirely unimplemented `DEFERRED`
**Spec:** invoice-import
No PDF/image extraction, no Cloud Function calls, no review/edit screen, no draft transaction creation from parsed data. Adjacent infrastructure exists (CameraCapture, VendorDefaults) but nothing is wired for this flow.

**Why deferred:** Requires a Tier 3 callable Cloud Function for server-side PDF parsing.

### H6. No sync status indicators `WRONG CODE`
**Spec:** offline-first
**File:** [SyncTracking.swift](LedgeriOS/LedgeriOS/State/SyncTracking.swift)

No connectivity monitoring (`NWPathMonitor`), no sync state tracking. Only a `NoOpSyncTracker` exists. `StatusBanner` component is built but never instantiated. Users have zero visibility into online/offline/syncing state.

### H7. Attachment lifecycle skips pre-upload metadata write `WRONG CODE`
**Spec:** offline-first
**Files:** [ItemDetailView.swift:401](LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift#L401), [SpaceDetailView.swift:405](LedgeriOS/LedgeriOS/Views/Projects/SpaceDetailView.swift#L405)

Spec says: write `AttachmentRef` with placeholder URL first (works offline), then upload bytes, then update URL. Implementation uploads first, then writes. If upload fails or user is offline, the selected image is silently lost.

### H8. No upload queue or retry for failed uploads `WRONG CODE`
**Spec:** offline-first
**File:** [MediaService.swift](LedgeriOS/LedgeriOS/Services/MediaService.swift)

No queuing, no retry on connectivity return. `MediaService.uploadImage` is a single `try await` with no retry logic.

### H9. Account discovery blocks on network with no cache-first behavior `WRONG CODE`
**Spec:** offline-first
**File:** [AccountContext.swift:57](LedgeriOS/LedgeriOS/State/AccountContext.swift#L57)

`discoverAccounts()` uses `getDocuments()` which attempts network first, then falls back to cache. Not a hard block, but violates offline-first's "cache first" principle. Should use `addSnapshotListener` for immediate cache-first reads.

### H10. Canonical sale transactions are editable (spec says system-generated, NOT editable) `WRONG CODE`
**Spec:** canonical-sales
**File:** [TransactionDetailView.swift:579](LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift#L579)

No guard on `isCanonicalInventorySale`. Users can edit amount, type, status of system-generated sale transactions.

### H11. `amountCents` not set on canonical sale transactions `WRONG CODE`
**Spec:** canonical-sales
**File:** [InventoryOperationsService.swift:23](LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift#L23)

Spec requires `amountCents = sum of purchasePriceCents for all items`. Neither `sellToBusiness` nor `sellToProject` computes or sets this field.

### H12. Bulk sales don't group items by `budgetCategoryId` `WRONG CODE`
**Spec:** canonical-sales
**File:** [InventoryOperationsService.swift:13](LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift#L13)

Spec says items with different categories should create separate canonical sale transactions. Implementation puts all items into a single transaction regardless of category.

### H13. `budgetCategoryId` not set on `sellToBusiness` transaction (modal UI ignored) `WRONG CODE`
**Spec:** canonical-sales
**File:** [SellToBusinessModal.swift:62](LedgeriOS/LedgeriOS/Modals/SellToBusinessModal.swift#L62)

Modal collects `selectedCategoryId` via UI picker but never passes it to the service call. `sellToBusiness()` method signature doesn't accept a `budgetCategoryId` parameter.

### H14. No color thresholds for budget progress bars `WRONG CODE`
**Spec:** budget-management
**File:** [BudgetCategoryTracker.swift:24](LedgeriOS/LedgeriOS/Components/BudgetCategoryTracker.swift#L24)

Spec defines green/yellow/red thresholds (0-49%/50-74%/75%+) with inverted logic for fees. All bars use `BrandColors.primary` regardless of percentage.

### H15. Space delete is hard delete, not soft delete (archive) `WRONG CODE`
**Spec:** spaces
**File:** [SpacesService.swift:25](LedgeriOS/LedgeriOS/Services/SpacesService.swift#L25)

Spec says soft delete (archive via `isArchived` flag). Implementation does permanent Firestore delete. Items in the deleted space retain orphaned `spaceId` references.

### H16. Creating a space from a template is not wired up `WRONG CODE`
**Spec:** spaces
**File:** [NewSpaceView.swift:46](LedgeriOS/LedgeriOS/Views/Creation/NewSpaceView.swift#L46)

Hardcoded stub: "No templates available". `SpaceTemplatesService` is fully built but `NewSpaceView` doesn't integrate with it.

### H17. Audit section shown for non-itemized categories `WRONG CODE`
**Spec:** transaction-audit
**File:** [TransactionDetailView.swift:549](LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift#L549)

Spec says audit is only relevant when `categoryType == "itemized"`. Implementation shows it for any transaction with a non-zero subtotal, regardless of category type.

### H18. Invoice report groups by transaction, not by budget category `WRONG CODE`
**Spec:** reports
**File:** [ReportAggregationCalculations.swift:78](LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift#L78)

Spec says group items by budget category with subtotals. Implementation groups by transaction into Charges/Credits sections.

### H19. Client Summary missing budget progress (budgeted/remaining per category) `WRONG CODE`
**Spec:** reports
**File:** [ReportAggregationCalculations.swift:169](LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift#L169)

Only shows total spent/market value/saved. Missing: budgeted amount per category, remaining per category, overall budget total, fee category distinction.

### H20. Display names semantically inverted for sale directions `WRONG CODE`
**Spec:** canonical-sales
**File:** [TransactionDisplayCalculations.swift:32](LedgeriOS/LedgeriOS/Logic/TransactionDisplayCalculations.swift#L32)

`businessToProject` (items FROM inventory) displays as "To Inventory". `projectToBusiness` (items TO inventory) displays as "From Inventory". Labels are backwards.

### H21. Menu visibility rules not enforced for reassign/sell actions `WRONG CODE`
**Spec:** reassign-vs-sell
**File:** [ItemDetailCalculations.swift:44](LedgeriOS/LedgeriOS/Logic/ItemDetailCalculations.swift#L44)

All actions shown unconditionally. Spec defines specific visibility rules based on item scope, `projectId`, and existence of same-scope transactions.

### H22. Delete confirmation doesn't warn about orphaned items `WRONG CODE`
**Spec:** project-lifecycle
**File:** [ProjectDetailView.swift:99](LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailView.swift#L99)

Only says "This action cannot be undone." Spec requires warning about orphaned transactions/items/spaces and suggesting moving items to inventory first.

---

## Medium — Partial Implementation or Incorrect Behavior

### M1. `transactionType` comparisons not case-normalized in some files `WRONG CODE`
**Spec:** data-model
**Files:** [SharedTransactionsList.swift:109](LedgeriOS/LedgeriOS/Components/SharedTransactionsList.swift#L109), [ReturnTransactionPickerModal.swift:16](LedgeriOS/LedgeriOS/Modals/ReturnTransactionPickerModal.swift#L16)

Some files correctly use `.lowercased()` (`TransactionListCalculations`, `TransactionCardCalculations`, `TransactionDisplayCalculations`), others compare directly without normalization. Inconsistent.

### M2. `sellToBusiness` edge missing `fromTransactionId` `WRONG CODE`
**Spec:** lineage-tracking, canonical-sales
**File:** [InventoryOperationsService.swift:48](LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift#L48)

Edge has `toTransactionId` but not `fromTransactionId`. `sellToProject` includes both. Inconsistent, and breaks item provenance tracing.

### M3. `createdBy` field never populated on lineage edges `WRONG CODE`
**Spec:** lineage-tracking
**File:** [InventoryOperationsService.swift:48](LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift#L48)

Edge data omits `createdBy` in all write locations. Spec defines `createdBy` as "The user who initiated the action."

### M4. Transaction lineage queries not ordered by timestamp `WRONG CODE`
**Spec:** lineage-tracking
**File:** [LineageEdgesService.swift:27](LedgeriOS/LedgeriOS/Services/LineageEdgesService.swift#L27)

No `.order(by:)` clause. Results in arbitrary Firestore document order. Spec says `order by timestamp ascending`.

### M5. `saveAsTemplate()` in SpaceDetailView is a stub `WRONG CODE`
**Spec:** spaces
**File:** [SpaceDetailView.swift:452](LedgeriOS/LedgeriOS/Views/Projects/SpaceDetailView.swift#L452)

Shows fake success message "Template saved! (Template service coming soon)" but `SpaceTemplatesService` is fully built and operational.

### M6. `createFromSpace` doesn't reset `isChecked` to false `WRONG CODE`
**Spec:** spaces
**File:** [SpaceTemplatesService.swift:30](LedgeriOS/LedgeriOS/Services/SpaceTemplatesService.swift#L30)

Copies `space.checklists` directly without resetting check states. Spec says templates must have all `isChecked` values set to `false`.

### M7. `taxAmount` field missing from `TransactionCompleteness` `WRONG CODE`
**Spec:** transaction-audit
**File:** [TransactionCompletenessCalculations.swift:11](LedgeriOS/LedgeriOS/Logic/TransactionCompletenessCalculations.swift#L11)

When explicit subtotal exists, the tax difference (`amountCents - subtotalCents`) is never computed. Only `inferredTax` (from `taxRatePct`) is calculated.

### M8. `missingTaxData` incorrectly true when `taxRatePct` is 0 `WRONG CODE`
**Spec:** transaction-audit
**File:** [TransactionCompletenessCalculations.swift:45](LedgeriOS/LedgeriOS/Logic/TransactionCompletenessCalculations.swift#L45)

`taxRate > 0` check means a 0% rate falls through to fallback, setting `missingTaxData = true`. Spec says `missingTaxData = (subtotalCents is null) AND (taxRatePct is null)` — 0% is a known value, not missing.

### M9. Invoice price fallback to `purchasePriceCents` not implemented `WRONG CODE`
**Spec:** reports
**File:** [ReportAggregationCalculations.swift:123](LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift#L123)

Uses `item.projectPriceCents ?? 0`. Spec says display price priority: `projectPriceCents` if set, otherwise `purchasePriceCents`.

### M10. Invoice doesn't exclude fee categories `WRONG CODE`
**Spec:** reports
**File:** [ReportAggregationCalculations.swift:91](LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift#L91)

Fee-type transactions included in invoice. Spec says fee categories are "typically excluded from item invoices."

### M11. Report headers missing business name/logo `WRONG CODE`
**Spec:** reports
**Files:** [InvoiceReportView.swift:12](LedgeriOS/LedgeriOS/Views/Reports/InvoiceReportView.swift#L12), [ClientSummaryReportView.swift:3](LedgeriOS/LedgeriOS/Views/Reports/ClientSummaryReportView.swift#L3)

`BusinessProfile` exists with `name`/`logoUrl` but not passed to any report view. InvoiceReportView has client name but no business name/logo. ClientSummaryReportView PDF lacks both client name and business name/logo.

### M12. Fee category remaining label missing "to receive" suffix `WRONG CODE`
**Spec:** budget-management
**File:** [BudgetTabCalculations.swift:57](LedgeriOS/LedgeriOS/Logic/BudgetTabCalculations.swift#L57)

Under-budget fee categories show "$X remaining" instead of "$X remaining to receive". Over-budget path correctly differentiates ("over received" for fees).

### M13. First-time auto-pinning of Furnishings category not implemented `WRONG CODE`
**Spec:** budget-management
No code exists to auto-pin Furnishings when user first views a project.

### M14. Budget tab display order — Overall Budget after fees instead of between standard and fees `WRONG CODE`
**Spec:** budget-management
**File:** [BudgetTabView.swift:59](LedgeriOS/LedgeriOS/Views/Projects/BudgetTabView.swift#L59)

Overall Budget row rendered after ALL categories including fees. Spec order: pinned → non-pinned standard → Overall Budget → fee categories.

### M15. Project card budget preview shows 1 category max, spec says 1-2 `WRONG CODE`
**Spec:** budget-management
**File:** [ProjectsListView.swift:165](LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift#L165)

`Array(sorted.prefix(1))` when no pinned categories — should be `prefix(2)`.

### M16. Project card missing "Overall Budget" fallback `WRONG CODE`
**Spec:** budget-management
**File:** [ProjectsListView.swift:137](LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift#L137)

When no categories have activity, returns empty array and card shows nothing. Comment in `ProjectListCalculations.swift` says "caller shows Overall Budget" but the caller does NOT implement this fallback.

### M17. `sellToProject` hardcodes wrong direction for business-to-project sells `WRONG CODE`
**Spec:** canonical-sales
**File:** [InventoryOperationsService.swift:87](LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift#L87)

Always writes `"project_to_project"` regardless of item source. When items come from business inventory (no `projectId`), direction should be `"business_to_project"`. Related to C2 — `project_to_project` is not a valid direction in any spec.

### M18. No "Sale" badge for canonical sale transactions `WRONG CODE`
**Spec:** canonical-sales
**File:** [TransactionDisplayCalculations.swift:68](LedgeriOS/LedgeriOS/Logic/TransactionDisplayCalculations.swift#L68)

`badgeConfigs` only generates badges for "purchase" and "return". "sale" falls through to default with no badge.

---

## Low — Copy Mismatches, Stale Spec Text, Minor Gaps

### L1. Item status `"to-purchase"` uses hyphen; spec says `"to purchase"` with space `WRONG CODE`
**Spec:** data-model
**Files:** [StatusPickerModal.swift:12](LedgeriOS/LedgeriOS/Modals/StatusPickerModal.swift#L12), [NewItemView.swift:411](LedgeriOS/LedgeriOS/Views/Creation/NewItemView.swift#L411)

### L2. Inconsistent `"to return"` (space) vs `"to-return"` (hyphen) within codebase `WRONG CODE`
**Specs:** data-model, return-and-sale-tracking
StatusPickerModal uses `"to return"` (space), `ItemListEnums` uses `"to-return"` (hyphen), `NewItemView` uses `"to-return"` (hyphen), `ItemDetailView` and `ListFilterSortCalculations` use `"to return"` (space).

### L3. `transactionType` values written as lowercase; spec defines title-case `WRONG CODE`
**Spec:** data-model
**File:** [NewTransactionView.swift:92](LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift#L92)

Writes `"purchase"`, `"sale"`, `"return"`. Spec says `"Purchase"`, `"Sale"`, `"Return"`.

### L4. LineageEdge uses `createdAt` instead of lineage-tracking spec's `timestamp` field name `SPEC CONFLICT`
**Specs:** lineage-tracking (says `timestamp`), data-model (says `createdAt`)
**File:** [LineageEdgesService.swift:16](LedgeriOS/LedgeriOS/Services/LineageEdgesService.swift#L16)

Code matches `data-model.md`. The two specs need reconciliation on this field name.

### L5. *(Removed — false positive. data-model.md spec includes `source`/`note` fields on edges.)*

### L6. Project lifecycle spec stale — references fields not in data-model `STALE SPEC`
**Spec:** project-lifecycle
References `status` (string), `address`, `notes`, `images` (array), `createdBy`/`updatedBy`. These fields don't exist in the `data-model.md` spec or in the Project model. The lifecycle spec needs updating.

### L7. Property Management report uses "No Space" instead of "Unassigned" `WRONG CODE`
**Spec:** reports
**File:** [PropertyManagementReportView.swift:23](LedgeriOS/LedgeriOS/Views/Reports/PropertyManagementReportView.swift#L23)

### L8. Property Management shows market value instead of price per item `WRONG CODE`
**Spec:** reports
**File:** [PropertyManagementReportView.swift:102](LedgeriOS/LedgeriOS/Views/Reports/PropertyManagementReportView.swift#L102)

Uses `item.marketValueCents` and labels column "MARKET VALUE". Spec says show "price" (purchase or project price).

### L9. Property Management header missing property address `STALE SPEC`
**Spec:** reports
Reports spec says header should include "property address" but the Project model has no `address` field, and `data-model.md` doesn't define one. The reports spec is aspirational here.

### L10. No empty state "No data for this report" message `WRONG CODE`
**Spec:** reports
All three report views render blank sections when no data exists. Spec says show message.

### L11. Items without prices show "No Price" instead of "Price not set" `WRONG CODE`
**Spec:** reports
**File:** [InvoiceReportView.swift:148](LedgeriOS/LedgeriOS/Views/Reports/InvoiceReportView.swift#L148)

### L12. *(Removed — false positive. "Budget" suffix IS applied at BudgetTabView call site.)*

### L13. Category name character validation missing (allows special chars) `WRONG CODE`
**Spec:** budget-management
**File:** [CategoryFormModal.swift:97](LedgeriOS/LedgeriOS/Components/Modals/CategoryFormModal.swift#L97)

Only validates empty and 100-char max length. No character set restrictions.

### L14. Category name uniqueness not validated (per-account, case-insensitive) `WRONG CODE`
**Spec:** budget-management
**File:** [CategoryFormModal.swift](LedgeriOS/LedgeriOS/Components/Modals/CategoryFormModal.swift)

No duplicate name check against existing categories.

### L15. Transactions with invalid `budgetCategoryId` silently dropped instead of "Unknown Category" `WRONG CODE`
**Spec:** budget-management
**File:** [BudgetProgressService.swift:21](LedgeriOS/LedgeriOS/Services/BudgetProgressService.swift#L21)

Spending for transactions whose `budgetCategoryId` doesn't match any active category is silently dropped from budget display. Spec says show as "Unknown Category."

### L16. Budget category validation for sell destination not checked `WRONG CODE`
**Spec:** reassign-vs-sell
**File:** [SellToProjectModal.swift](LedgeriOS/LedgeriOS/Modals/SellToProjectModal.swift)

Spec says check if item's category is enabled in destination project. Modal shows all account-level categories without validating they exist in the destination project's budget.

### L17. Explicit tax amount never displayed in audit panel `WRONG CODE`
**Spec:** transaction-audit
**File:** [TransactionAuditPanel.swift:61](LedgeriOS/LedgeriOS/Views/Projects/TransactionAuditPanel.swift#L61)

Shows calculated/inferred tax only. When both `amountCents` and `subtotalCents` are set, the explicit tax (`amountCents - subtotalCents`) is not displayed.

---

## Cross-Cutting Themes

### Theme 1: InventoryOperationsService is the most deviation-dense file
Almost every spec violation in canonical-sales, lineage-tracking, reassign-vs-sell, and write-tiers traces back to this single file. It writes wrong field names (C1), uses invalid enum values (C2), never updates source transaction itemIds (C5), implements reassign with sell semantics (C4), doesn't compute amountCents (H11), doesn't group by category (H12), and creates lineage edges client-side when the spec says server-only (H3). **This file needs a ground-up rewrite.**

### Theme 2: Timestamps are universally broken
Every model struct declares `createdAt`/`updatedAt` but excludes them from CodingKeys (C6). This affects sorting, display, and audit trails across the entire app. **Quick fix: add the keys to CodingKeys in all 5 model files.**

### Theme 3: The lineage system is skeletal
The data model and service exist, but only `"sold"` edges are created (and those are created client-side when the spec says server-only). No UI displays them, queries are incomplete, and the vast majority of operations that should create edges don't. Full implementation depends on the request-doc infrastructure (C3).

### Theme 4: String value inconsistency
Status values, transaction types, and sale directions have inconsistent casing and hyphenation across the codebase: `"to-purchase"` vs `"to purchase"`, `"return"` vs `"Return"`, `"project_to_project"` with no enum case. **These should be consolidated into enums with CodingKeys mappings to prevent further drift.**

### Theme 5: Reports are structurally different from spec
All three reports have architectural differences (grouping logic, data fields, headers) beyond cosmetic issues. The invoice report groups by transaction instead of budget category (H18), the client summary lacks budget progress data (H19), and the property management report shows wrong price fields (L8).

### Theme 6: Offline-first principles partially implemented
Firestore's automatic caching provides a baseline, but the spec's higher-level requirements are missing: no sync status indicators (H6), wrong attachment lifecycle (H7), no upload queue (H8), server-first account discovery (H9). The app "works" offline thanks to the SDK but doesn't give users visibility into sync state.
