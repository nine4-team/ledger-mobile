# Inventory Sale / Reassign Cleanup Plan

Status: implemented; automated targeted tests passing; full pre-release/manual QA still required.

## Goal

Clean up the item movement/sale/correction model so the UI, service names, MCP names, specs, audit trail, and accounting behavior all describe the same domain rules.

## Current Problems

- The visible UI has `Sell to Project`, but no equally clear `Sell to Inventory` path.
- Project -> business inventory is currently accessed through `Return to Inventory`, even when selected items originated in a project and should be sold to inventory.
- `SellToBusinessModal.swift` contains a `MoveToInventoryModal` struct, and the service entry point is `moveToInventory`, even though the flow may create either a Return or a Sale-to-Inventory.
- `ReassignToProjectModal` was wired to `sellItemsFromProjectToProject`, which is a financial project-to-project sale path. Reassign/correct must not be a sale path.
- `sellItemsFromProjectToProject` is a misleading name for a financial project-to-project sale operation.
- MCP public names are already clear and should be treated as the naming model:
  - `sell_items_from_inventory_to_project`
  - `sell_items_from_project_to_inventory`
  - `sell_items_from_project_to_project`
  - `return_items`

## Canonical Rules

- `Sell` means a financial event.
- `Return to Inventory` only applies when the item originally came from inventory.
- `Sell to Inventory` applies when a project-originated item is acquired by the business into inventory.
- `Reassign` / `Correct` / `Move` means a non-financial correction flow.
- Inventory -> project uses project price.
- Project -> project uses two hops:
  - source project -> business inventory at purchase price
  - business inventory -> destination project at project price
- Project -> business inventory uses purchase price.
- Missing `projectPriceCents` should be prompted only when selling into a project:
  - inventory -> project
  - project -> project destination hop

## Implementation Plan

### 1. Rename the Financial Project-to-Project Path

Align iOS and MCP internals to the MCP public operation name.

- Rename `InventoryOperationsService.sellItemsFromProjectToProject` to `sellItemsFromProjectToProject`.
- Rename MCP internal helper `commitSellItemsFromProjectToProject` to `commitSellItemsFromProjectToProject`.
- Keep MCP public tool `sell_items_from_project_to_project`.
- Update call sites, tests, docs, and comments that refer to the financial path as a move.

### 2. Fix `ReassignToProjectModal`

`ReassignToProjectModal` must be correction-only.

Final behavior:

- Select destination project.
- Select destination transaction if needed.
- Call correction/reassignment service only.
- Do not prompt for project price.
- Do not create Sale, Return, or Purchase transactions.
- Write correction/audit lineage only.

### 3. Fix Sale Entry UI

Replace the split/confusing sale entry model with one clear sale action.

Proposed flow:

- Menu shows `Sell`.
- User picks destination:
  - `Project`
  - `Business Inventory`
- If destination is `Project`:
  - inventory items use `sellToProject`
  - project items use `sellItemsFromProjectToProject`
  - missing `projectPriceCents` prompts before commit
- If destination is `Business Inventory`:
  - project-originated items use `sellToInventory`
  - from-inventory items are not a sale; they use `Return to Inventory`

Decision needed: for mixed-origin batches under `Sell -> Business Inventory`, either block with a clear message or explicitly split the batch. Recommended default: block mixed batches in `Sell` and keep mixed handling only in an explicit inventory disposition flow if still needed.

### 4. Rename Project-to-Inventory UI/Service Concepts

Current naming is misleading:

- File: `SellToBusinessModal.swift`
- Struct: `MoveToInventoryModal`
- Service: `moveToInventory`

If one modal continues to handle both Return and Sale-to-Inventory, rename toward disposition language, for example:

- `InventoryDispositionModal`
- `resolveProjectItemsToInventory`

If UX is split into explicit sale vs return flows, use explicit names:

- `SellToInventoryModal`
- `ReturnToInventoryModal`

### 5. Keep Return Only for Actual Returns

The UI should not make `Return to Inventory` the only project -> inventory path.

Final rule:

- From-inventory selected items can show `Return to Inventory`.
- Project-originated selected items can show `Sell` -> `Business Inventory`.
- Mixed selected batches should either be explicitly split or blocked with a clear explanation.

### 6. Update Specs

Update specs so they encode the corrected model:

- `Sell` is destination-based.
- `Return to Inventory` is only for items originally from inventory.
- `Sell to Inventory` is for project-originated items acquired by the business.
- `Reassign` / `Correct` / `Move` is non-financial.
- `sell_items_from_project_to_project` is the canonical financial project-to-project operation name.

Likely files:

- `docs/specs/reassign-vs-sell.md`
- `docs/specs/sale-transactions.md`
- `docs/specs/inventory-as-store.md`
- `docs/specs/data-model.md`
- `docs/specs/add-existing-items.md`
- `docs/specs/lineage-tracking.md`
- `docs/specs/item-detail-view.md`
- `docs/specs/_app-map.md`
- `docs/specs/_index.md`
- `CLAUDE.md`

### 7. Add / Rename Tests

Cover:

- `ReassignToProjectModal` never calls sale path.
- `sellItemsFromProjectToProject` creates first-hop purchase-price exit and second-hop project-price purchase.
- Missing project price prompts only in sell-to-project destination flows.
- Project-originated item -> business inventory is Sale, not Return.
- From-inventory item -> business inventory is Return, not Sale.
- UI menu visibility/routes distinguish Sell vs Return correctly.

### 8. Production Repair Plan

Handle the specific production issue separately from the cleanup implementation.

For item `H11MvVi0hAmeTmTF8qaz` and its companion same-name/SKU item:

- Dry-run first.
- Do not move the items again.
- Snapshot current evidence: items, source project, destination project, existing destination Purchase transaction, lineage, and audit logs.
- Classify each item's true origin from historical lineage/source transaction, not overwritten current fields.
- Create the missing first-hop source-side Sale/Return trail as appropriate.
- Append lineage/audit edges.
- Verify accounting and budget impact.
- Require explicit approval before write mode.

## Approval Gates

1. Approve naming and UX direction for `Sell` destination picker vs separate buttons.
2. Approve code/spec/test implementation.
3. Approve production repair dry-run output before any write-mode repair.

## User-Readiness Testing Plan

Status: partially executed. MCP, iOS non-emulator unit/regression tests, emulator-backed integration tests, and Functions emulator/build verification pass. Manual simulator QA and production repair dry-run remain before release.

### A. Automated Regression Tests

Run these before any user-facing build is cut:

```bash
cd mcp-server
npm test -- --run sell-items.test.ts
```

```bash
xcodebuild test -quiet \
  -project LedgeriOS/LedgeriOS.xcodeproj \
  -scheme LedgeriOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:LedgeriOSTests/ItemMenuBuilderTests \
  -only-testing:LedgeriOSTests/SellItemsFromProjectToProjectExecutionTests \
  -only-testing:LedgeriOSTests/SellToProjectExecutionTests \
  -only-testing:LedgeriOSTests/ReturnToInventoryExecutionTests
```

Required assertions:

- Inventory -> project creates a destination Purchase at `projectPriceCents`.
- Project -> inventory is origin-aware: an inventory-originated Return reverses normalized `projectPriceCents`; a project-originated Sale-to-Inventory uses `purchasePriceCents`.
- Project -> project creates two hops:
  - source project -> business inventory using the same origin-aware Return/Sale basis
  - business inventory -> destination project at `projectPriceCents`
- Missing `projectPriceCents` is rejected or prompted only for project-destination sales.
- Reassign/correct flows do not prompt for price and do not create Sale, Return, or Purchase transactions.
- Menu tests distinguish `Sell`, `Return to Inventory`, and `Correct / Move`.

### B. Firestore Emulator Integration Tests

Run against the Firestore emulator with test rules before release. Each scenario should verify item fields, transaction documents, old transaction `itemIds`, lineage edges, and budget-facing amounts.

Scenarios:

- Inventory item -> Sell -> Project:
  - missing project price prompts in UI or rejects in non-interactive tooling
  - entered price is persisted as `projectPriceCents`
  - Purchase amount uses project price
  - item lands in destination project/category
- Project-originated item -> Sell -> Business Inventory:
  - creates Sale-to-Inventory
  - no `budgetCategoryId` on the Sale
  - amount uses purchase price
  - lineage edge is `soldToInventory`
  - item lands in inventory with no `projectId` / `budgetCategoryId`
- From-inventory project item -> Return to Inventory:
  - creates Return, not Sale
  - amount reverses normalized project price
  - lineage edge is `returned`
  - item lands in inventory with no `projectId` / `budgetCategoryId`
- Project -> Project, from-inventory item:
  - first hop is Return at normalized project price
  - second hop is Purchase at project price
  - lineage includes first-hop return and second-hop sold edge
- Project -> Project, project-originated item:
  - first hop is Sale-to-Inventory at purchase price
  - second hop is Purchase at project price
  - lineage includes first-hop sold-to-inventory and second-hop sold edge
- Project -> Project, mixed-origin batch:
  - creates Return plus Sale-to-Inventory plus destination Purchase atomically
  - every item lands in destination project/category
  - source transaction `itemIds` are updated except frozen source transactions

### C. Manual Simulator QA

Run these in the iOS simulator using realistic project/inventory data:

- Inventory item menu:
  - shows `Sell`
  - `Sell -> Project` completes
  - no `Return to Inventory` action appears
- Project-originated item menu:
  - shows `Sell`
  - `Sell -> Business Inventory` completes as Sale-to-Inventory
  - `Sell -> Project` completes as project-to-project sale
  - no `Return to Inventory` action appears
- From-inventory project item menu:
  - shows `Return to Inventory`
  - `Return to Inventory` completes as Return
  - `Sell -> Project` still works for a different destination project
  - `Sell -> Business Inventory` is not offered for that item
- Bulk project selections:
  - all project-originated: `Sell -> Business Inventory` is available
  - all from-inventory: `Return to Inventory` is available
  - mixed origin: UI does not imply one wrong operation; either blocks clearly or requires an explicit split flow
- Reassign/correct:
  - destination project/transaction correction does not ask for project price
  - no financial transaction is created
  - item association/audit trail updates as correction only

Record the result of each manual scenario with:

- source item ID(s)
- starting scope and origin classification
- action taken
- transaction IDs created
- lineage movement kinds created
- final item `projectId`, `budgetCategoryId`, `transactionId`, and `currentSource`

### D. Full Pre-Release Test Pass

After targeted tests and manual QA pass:

```bash
cd mcp-server
npm test
```

```bash
xcodebuild test -quiet \
  -project LedgeriOS/LedgeriOS.xcodeproj \
  -scheme LedgeriOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Also run or verify any Firebase Functions tests/build checks for touched files under `firebase/functions`.

Release is not ready until:

- MCP full test suite passes.
- iOS full test suite passes or any unrelated pre-existing failures are documented.
- Firebase Functions build/tests pass or touched function changes are otherwise verified.
- Manual simulator QA has no unresolved behavior mismatches.

### E. Production Repair Validation for `H11MvVi0hAmeTmTF8qaz`

Do this separately from the app release path.

Dry-run checklist:

- Snapshot both affected item documents.
- Identify the companion same-name/SKU item.
- Snapshot existing source and destination transactions.
- Snapshot lineage edges and audit records.
- Classify each item's origin from historical evidence, not current UI state alone.
- Compute the missing source-side first hop:
  - Return if the item originally came from inventory
  - Sale-to-Inventory if the item originated in the source project
- Compute accounting deltas using purchase price for source-project exit.
- Confirm the destination project Purchase already present, or identify the missing destination leg if not.
- Produce exact Firestore writes for review.

Write-mode requirements:

- No write mode until dry-run output is explicitly approved.
- Repair must not use correction/reassign/move semantics.
- Repair must create the proper financial transaction trail, lineage trail, and audit notes.
- After write mode, re-read all touched docs and verify budget/accounting projections.

### F. Test Execution Log

2026-06-23 results:

- MCP targeted regression passed: `firebase emulators:exec --only firestore --project demo-mcp-test "cd mcp-server && npm test -- --run sell-items.test.ts"` -> 11/11 passed.
- iOS targeted unit/regression pass succeeded:
  - `ItemMenuBuilderTests`
  - `SellItemsFromProjectToProjectExecutionTests`
  - `SellToProjectExecutionTests`
  - `ReturnToInventoryExecutionTests`
- Inventory emulator integration passed under Auth/Firestore/Storage test-rules stack:
  - `firebase emulators:exec --only auth,firestore,storage --import=./firebase-export --config firebase.test.json "cd LedgeriOS && xcodebuild test -scheme 'LedgeriOS (Emulator)' -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:LedgeriOSTests/InventoryOperationsIntegrationTests -derivedDataPath DerivedData -quiet"`
  - Latest `.xcresult`: 9/9 passed.
- Added direct emulator coverage for `sellItemsFromProjectToProject`:
  - the original 2026-06-23 assertion priced a from-inventory first-hop `Return` at `purchasePriceCents`; this was incorrect and is superseded by the origin-aware rule above: Return at normalized `projectPriceCents`
  - project-originated item creates first-hop `Sale` to inventory at `purchasePriceCents`, then destination `Purchase` at `projectPriceCents`
  - both verify item relocation, source transaction item removal, and lineage edge kinds.
- Firebase Functions TypeScript build passed: `cd firebase/functions && npm run build`.
- Full Functions emulator-backed inventory integration passed:
  - `firebase emulators:exec --import=./firebase-export --config firebase.test.json "cd LedgeriOS && xcodebuild test -scheme 'LedgeriOS (Emulator)' -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:LedgeriOSTests/InventoryOperationsIntegrationTests -derivedDataPath DerivedData -quiet"`
  - Latest `.xcresult`: 9/9 passed.
  - Triggered Functions initialized and drained cleanly.

2026-06-24 results:

- MCP full discovered suite passed under Firestore emulator:
  - `firebase emulators:exec --only firestore --project demo-mcp-test "cd mcp-server && npm test -- --run"`
  - Current discovered suite is `sell-items.test.ts`: 11/11 passed.
- iOS stale unit expectations fixed and targeted rerun passed:
  - `PinnedImageCalculationTests`
  - `ImageThumbnailGeneratorTests`
  - `TransactionNextStepsCalculationTests`
  - `InventoryTransactionGroupingTests`
  - `TransactionMenuBuilderTests`
- iOS non-emulator suite passed with Firebase integration classes skipped:
  - `xcodebuild test -quiet -project LedgeriOS/LedgeriOS.xcodeproj -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath LedgeriOS/DerivedData -skip-testing:LedgeriOSTests/SpaceCRUDIntegrationTests -skip-testing:LedgeriOSTests/ItemCRUDIntegrationTests -skip-testing:LedgeriOSTests/RelationshipIntegrationTests -skip-testing:LedgeriOSTests/InventoryOperationsIntegrationTests -skip-testing:LedgeriOSTests/TransactionCRUDIntegrationTests`
- Emulator-backed integration suite passed with Auth/Firestore/Storage/Functions:
  - `firebase emulators:exec --only auth,firestore,storage,functions --import=./firebase-export --config firebase.test.json "cd LedgeriOS && xcodebuild test -scheme 'LedgeriOS (Emulator)' -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath DerivedData -quiet -only-testing:LedgeriOSTests/SpaceCRUDIntegrationTests -only-testing:LedgeriOSTests/ItemCRUDIntegrationTests -only-testing:LedgeriOSTests/RelationshipIntegrationTests -only-testing:LedgeriOSTests/InventoryOperationsIntegrationTests -only-testing:LedgeriOSTests/TransactionCRUDIntegrationTests"`
  - Functions triggers initialized and drained cleanly during the run.
- Manual simulator QA was run against the `LedgeriOS (Emulator)` build with the orange `EMULATOR` badge visible. Auth user `team@nine4.co` was reset in the Auth emulator before sign-in.
- Manual inventory -> project sale with existing `projectPriceCents` passed:
  - UI path: Business Inventory item menu -> `Sell` -> `Project` -> project -> category -> `Confirm Sale`.
  - The sheet used `Sell` / `Sell to Project`, not a correction/reassign path.
  - Verification: created a `Purchase` transaction from `Business Inventory` for item `I-1770105821392-2c1t`.
- Manual inventory -> project sale with missing `projectPriceCents` passed:
  - UI showed `Project Price` prompt after project selection for item `I-1770075204351-9jhu`.
  - Entered `12.34`; sale continued to budget category selection and confirmation.
  - Verification: item persisted `projectPriceCents = 1234`; created `Purchase` transaction amount/subtotal `1234` from `Business Inventory`.
- Manual project-side inventory-originated item menu passed:
  - Project item menu showed `Return to Inventory`, `Sell`, and `Correct / Move` as separate actions.
  - `Sell` opened the destination picker and then `Sell to Project`, not the correction flow.
- Manual project -> project sale for an inventory-originated item passed:
  - Sold item `I-1770105821392-2c1t` from Bradshaws Desert Color Rental to Hyer's Martinique Rental.
  - Verification: first-hop source project record is `Return` from `Business Inventory` at purchase price `7999`; destination record is `Purchase` from `Business Inventory` at project price `7999`.
- Manual project-originated item menu check passed on grouped Ross item SKU `400294701841`:
  - Opened the individual item overflow for `36" tall gold metal candlestick`.
  - Menu showed `Sell` and `Correct / Move`, with no `Return to Inventory`.
  - `Sell` opened the destination picker with `Project` and `Business Inventory`; `Business Inventory` was described as creating a sale from the project into inventory.

Observed blockers / notes:

- The Functions emulator failure was caused by Firebase CLI 14.1.0 calling `localFunctionsModule.config()` while wrapping the SDK. `firebase-functions` v7 throws on that call, so the repo now pins `firebase-functions` to `6.6.0` for emulator compatibility with the installed CLI.
- `recalculateProjectBudgetSummary` now uses `set(..., { mergeFields: ['budgetSummary'] })` instead of `update(...)`, so emulator tests with synthetic project IDs do not produce NOT_FOUND trigger errors while still replacing the whole `budgetSummary` field.
- Firebase CLI still prints auth-token warnings because the local Firebase login needs reauth, but local emulator startup and tests complete successfully.
- Firebase CLI warns that `firebase-functions` 6.6.0 is outdated. Do not upgrade back to v7 without also upgrading the local Firebase CLI/runtime path and rerunning the full Functions emulator suite.
- One iOS simulator launch attempt failed before tests ran with Mach error `-308`; shutting down the simulator and retrying passed. Treat as simulator flake, not app test failure.
- Existing unrelated warnings remain in the test output, including `ExportFieldConfigTests` always-true `is String`, `SelectorCircle` main-actor warnings, and app Swift concurrency warnings.
