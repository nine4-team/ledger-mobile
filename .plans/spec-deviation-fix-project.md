# Spec Deviation Fix Project

## Context

The spec-to-implementation audit (`.plans/spec-deviation-audit.md`) found **63 verified deviations**. We are mid-migration from React Native to SwiftUI, and a three-way comparison (RN types vs specs vs Swift models) revealed that:

1. Some deviations are clear bugs (code writes wrong field names, missing CodingKeys)
2. Some are migration regressions (Item fields dropped during migration)
3. Some are aspirational spec features not yet in Firestore (Project notes, images)
4. Some are deferred (need Cloud Function infrastructure)

The RN `src/` types represent the production Firestore schema. The specs represent desired state. Neither the data-model spec nor the project-lifecycle spec is individually canonical — they need reconciliation.

## Decisions Made

1. **Project model:** Add `notes`, `images`, `createdBy`, `updatedBy` fields. Defer `address`. Keep `isArchived` boolean (don't migrate to status string).
2. **Item model:** Restore all 4 dropped lineage fields (`originTransactionId`, `latestTransactionId`, `previousProjectId`, `previousProjectTransactionId`). Remove `quantity` (migration invention not in Firestore).
3. **Spec conflicts:** Where data-model.md and lineage-tracking.md disagree, data-model.md + RN types win (they match production Firestore).
4. **Server infra (C3, H3, H4, H5):** Deferred entirely.

## Phase 0: Spec + Model Reconciliation

Before fixing behavior, align the data layer.

**Spec updates:**
| File | Change |
|------|--------|
| `lineage-tracking.md` | Fix `timestamp` → `createdAt`. Add `source`, `note` fields. (Matches data-model.md + RN) |
| `project-lifecycle.md` | Mark `address` as future. Keep `notes`, `images`, `createdBy`/`updatedBy` as current. Remove `status` string (use `isArchived`). |
| `data-model.md` | Add missing Item fields: `originTransactionId`, `latestTransactionId`, `previousProjectId`, `previousProjectTransactionId`. Remove `quantity`. |
| `budget-management.md` | Reconcile normalization: match data-model.md pseudocode (`status == "returned" OR amount < 0`) |
| `return-and-sale-tracking.md` | Same reconciliation as above |

**Model updates (Swift):**
| File | Change |
|------|--------|
| `Project.swift` | Add `notes: String?`, `images: [AttachmentRef]?`, `createdBy: String?`, `updatedBy: String?`. Add all to CodingKeys including `createdAt`/`updatedAt`. |
| `Transaction.swift` | Add `createdAt`/`updatedAt` to CodingKeys |
| `Item.swift` | Add `originTransactionId`, `latestTransactionId`, `previousProjectId`, `previousProjectTransactionId`. Remove `quantity`. Add `createdAt`/`updatedAt` to CodingKeys. |
| `Space.swift` | Add `createdAt`/`updatedAt` to CodingKeys |
| `SpaceTemplate.swift` | Add `createdAt`/`updatedAt` to CodingKeys |

**Tests:** Extend `ModelCodableTests` with round-trip tests for new/changed fields.

## Phase 1: Clear Bug Fixes (no decisions needed)

All sources agree these are wrong. Low risk, high confidence.

| ID | Fix | File(s) |
|----|-----|---------|
| C1 | Raw dict writes: `"type"` not `"transactionType"` | `InventoryOperationsService.swift` |
| C2 | Remove `"project_to_project"` — only `business_to_project`/`project_to_business` exist | `InventoryOperationsService.swift`, `Enums.swift` |
| C5 | `FieldValue.arrayRemove`/`arrayUnion` on source/dest transaction `itemIds` | `InventoryOperationsService.swift` |
| H20 | Swap inverted direction display labels | `TransactionDisplayCalculations.swift` |
| M8 | `taxRatePct != nil` not `> 0` for missingTaxData | `TransactionCompletenessCalculations.swift` |
| M18 | Add "sale" badge | `TransactionDisplayCalculations.swift` |
| L1/L2 | Normalize status strings (`"to purchase"` not `"to-purchase"`) | `StatusPickerModal.swift`, `ItemListEnums.swift`, `NewItemView.swift` |
| M1 | Case-normalize transactionType comparisons | `SharedTransactionsList.swift`, `ReturnTransactionPickerModal.swift` |

## Phase 2: Budget + Spaces (parallel, isolated)

**Budget display:**
| ID | Fix | File(s) |
|----|-----|---------|
| H14 | Green/yellow/red thresholds (inverted for fees) | `BudgetCategoryTracker.swift` |
| M12 | Fee: "$X remaining to receive" | `BudgetTabCalculations.swift` |
| M14 | Overall Budget between standard and fee categories | `BudgetTabView.swift` |
| M15 | `prefix(2)` not `prefix(1)` | `ProjectsListView.swift` / `ProjectListCalculations.swift` |
| M16 | Overall Budget fallback when no activity | `ProjectListCalculations.swift` |
| L15 | "Unknown Category" for orphaned budgetCategoryIds | `BudgetProgressService.swift` |

**Spaces:**
| ID | Fix | File(s) |
|----|-----|---------|
| H15 | Soft delete (set `isArchived = true`) | `SpacesService.swift` |
| H16 | Wire NewSpaceView to SpaceTemplatesService | `NewSpaceView.swift` |
| M5 | Wire saveAsTemplate to actual service | `SpaceDetailView.swift` |
| M6 | Reset `isChecked` in `createFromSpace` | `SpaceTemplatesService.swift` |

## Phase 3: Reports

| ID | Fix | File(s) |
|----|-----|---------|
| H18 | Invoice: group by budget category | `ReportAggregationCalculations.swift`, `InvoiceReportView.swift` |
| H19 | Client Summary: budget progress per category | `ReportAggregationCalculations.swift`, `ClientSummaryReportView.swift` |
| M9 | Price fallback: `projectPriceCents ?? purchasePriceCents` | `ReportAggregationCalculations.swift` |
| M10 | Exclude fee categories from invoice | `ReportAggregationCalculations.swift` |
| M11 | Business name/logo in report headers | `InvoiceReportView.swift`, `ClientSummaryReportView.swift` |
| L7 | "No Space" → "Unassigned" | `PropertyManagementReportView.swift` |
| L8 | Show price not market value | `PropertyManagementReportView.swift` |
| L10 | Empty state message | All report views |
| L11 | "No Price" → "Price not set" | `InvoiceReportView.swift` |

## Phase 4: InventoryOperationsService Rewrite

The most deviation-dense file. Write tests first, then rewrite.

| ID | Fix |
|----|-----|
| C4 | Reassign = within-scope only. Cross-scope = sell. |
| H1 | Deterministic IDs: `SALE_{projectId}_{direction}_{budgetCategoryId}` |
| H11 | Compute `amountCents = sum of purchasePriceCents` |
| H12 | Group items by `budgetCategoryId` → separate transactions |
| H13 | Accept + set `budgetCategoryId` in `sellToBusiness` |
| M2 | Include `fromTransactionId` in sellToBusiness edge |
| M3 | Include `createdBy` in all edges |
| M17 | Direction based on item's current `projectId` |

**Also update:** `SellToBusinessModal.swift`, `SellToProjectModal.swift` (pass required params)
**New file:** `InventoryOperationsServiceTests.swift`

## Phase 5: Transaction & Item Detail Fixes

| ID | Fix | File(s) |
|----|-----|---------|
| C8 | WriteBatch for addExistingItems | `TransactionDetailView.swift` |
| H2 | Archive/Unarchive in project menu | `ProjectDetailView.swift` |
| H10 | Guard canonical sales from editing | `TransactionDetailView.swift` |
| H17 | Gate audit on `categoryType == "itemized"` | `TransactionDetailView.swift` |
| H21 | Menu visibility rules for reassign/sell | `ItemDetailCalculations.swift` |
| H22 | Orphaned items warning on project delete | `ProjectDetailView.swift` |
| M7 | Add explicit `taxAmount` to completeness | `TransactionCompletenessCalculations.swift` |
| M13 | Auto-pin Furnishings on first view | `BudgetTabView.swift` or `ProjectContext` |
| L13 | Character validation for category names | `CategoryFormModal.swift` |
| L14 | Uniqueness check for category names | `CategoryFormModal.swift` |
| L16 | Validate sell destination category | `SellToProjectModal.swift` |
| L17 | Display explicit tax in audit panel | `TransactionAuditPanel.swift` |

## Phase 6: Offline-First

| ID | Fix | File(s) |
|----|-----|---------|
| H6 | NWPathMonitor + StatusBanner | `SyncTracking.swift`, root view |
| H7 | Pre-upload placeholder AttachmentRef | `ItemDetailView.swift`, `SpaceDetailView.swift`, `MediaService.swift` |
| H8 | Upload queue with retry | `MediaService.swift` |
| H9 | Cache-first `addSnapshotListener` | `AccountContext.swift` |

## Deferred (blocked on server infrastructure)

| ID | Reason |
|----|--------|
| C3 | Request-doc system needs Cloud Functions |
| H3 | Full lineage tracking needs server-side edge creation (spec says client must NOT create edges) |
| H4 | Return processing Step 2 needs Tier 2 request docs |
| H5 | Invoice import needs Tier 3 callable Cloud Function |

## Verification

After each phase:
1. `cd LedgeriOS && xcodebuild test -scheme "LedgeriOS (Emulator)" -destination 'platform=iOS Simulator,name=iPhone 16e' -derivedDataPath DerivedData -quiet`
2. `cd LedgeriOS && xcodebuild build -scheme "LedgeriOS (Emulator)" -destination 'platform=iOS Simulator,name=iPhone 16e' -derivedDataPath DerivedData -quiet 2>&1 | tail -5`
3. Manual smoke test for UI changes (budget colors, report layouts, action menus)
4. After Phase 4: full walkthrough of sell/reassign flows in simulator

## Related Docs
- Audit: `.plans/spec-deviation-audit.md` (63 deviations, severity, classification)
- Migration: `.plans/swiftui-migration.md`
- Specs: `docs/specs/` (13 files)
- RN types: `src/data/*Service.ts`
- Legacy web: `/Users/benjaminmackenzie/Dev/ledger/src/types/index.ts`
