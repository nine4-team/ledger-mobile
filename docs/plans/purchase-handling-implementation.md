# Purchase Handling and Quick-Draft Routing Implementation

## Status

Complete. Started 2026-08-17; runtime verification closed 2026-08-19.

This tracker implements
[Purchase Handling and Inventory Intent](../specs/purchase-handling-and-inventory-intent.md)
and the transaction-association portions of
[Proto Item Capture](../specs/proto-item-capture.md).

## Progress Tracker

- [x] Record the agreed product and data-model specification.
- [x] Audit the iOS transaction creation, item creation, quick-draft, inventory
  movement, and MCP transaction/promotion paths.
- [x] Add canonical `purchaseHandling` values to the iOS transaction model.
- [x] Add `intendedProjectId` and `intendedBudgetCategoryId` to the iOS
  transaction model.
- [x] Add the business-paid handling decision and explanatory copy to New
  Transaction.
- [x] Route only explicit `inventory_resale` purchases into inventory.
- [x] Persist project/category intent while preserving inventory transaction
  invariants.
- [x] Make `project_reimbursement` direct-project purchases payable to the
  business.
- [x] Persist purchase price as project price when an item on a covered project
  purchase has no explicit project price.
- [x] Expose From Inventory during initial project quick-draft capture.
- [x] Stop MCP quick-draft promotion from treating legacy
  `candidateTransactionId` as confirmed.
- [x] Add intended-project purchase status derivation and the Business Inventory
  follow-up UI.
- [x] Validate intended project/category availability before immediate or delayed
  sale.
- [x] Route project quick drafts whose authoritative `transactionId` references
  inventory through one atomic create-and-sell operation.
- [x] Implement that atomic inventory-linked promotion route in the Ledger MCP,
  including scope/category/price validation and acquisition lineage.
- [x] Add an optional authoritative transaction picker to project quick-draft
  review/conversion.
- [x] Add MCP transaction intent fields, filters, enriched queue reads, updates,
  resolution, correction, and dry-run operations.
- [x] Add MCP legacy candidate audit reporting without allowing candidate writes.
- [x] Add focused iOS tests for routing, follow-up states, model persistence,
  intent resolution, and batch-failure propagation.
- [x] Verify MCP schemas and write paths with a clean TypeScript build.
- [x] Run the complete non-emulator iOS unit profile and update this tracker.
- [x] Run a disposable real-Firestore MCP smoke test for the new mutating tools.
- [x] Perform installed-app QA of both business-paid branches and both
  quick-draft conversion entry points through the production Sparkle build.

## Implementation Order

1. Land the model and New Transaction routing foundation.
2. Complete quick-draft authoritative transaction selection and conversion.
3. Add the inventory follow-up read model and UI.
4. Bring the Ledger MCP to full feature parity, including corrections.
5. Verify cross-client invariants and close documentation gaps.

## Verification Log

- 2026-08-17: Generic iOS Simulator Debug build succeeded after the first iOS
  routing and model slice. Existing unrelated compiler warnings remain.
- 2026-08-17: Ledger MCP TypeScript build succeeded after authoritative
  quick-draft association and atomic inventory-linked promotion changes.
- 2026-08-17: Generic iOS Simulator Debug build succeeded again after the
  initial-capture affordance and covered-project price fallback changes.
- 2026-08-17: Added app-side atomic quick-draft inventory conversion, inventory
  transaction selection, and the Planned for Projects follow-up area. Generic
  iOS Simulator Debug build succeeded.
- 2026-08-17: Added MCP intent listing, enrichment, grouping diagnostics,
  metadata updates/resolution, direct-project correction with dry-run, and
  legacy candidate audit. TypeScript build succeeded.
- 2026-08-17: The focused Transaction Creation Step Resolver suite passed all
  13 tests on the iOS Simulator.
- 2026-08-17: Extracted inventory-intent state derivation and added waiting,
  missing-price, and ready-state coverage. The focused resolver suite passed all
  16 tests.
- 2026-08-17: Added recording-batch coverage proving acquisition-intent
  resolution is queued in the same sale batch and commit failures propagate,
  plus Codable coverage for all new transaction fields. The focused inventory
  execution and model suites passed.
- 2026-08-17: Closed an alternate-entry gap in the project Items screen so
  quick-draft conversions preserve the draft ID and From Inventory marker.
  From Inventory drafts now require a valid Purchase acquisition and cannot use
  an acquisition intended for another project. The iOS build and MCP TypeScript
  build both succeeded afterward.
- 2026-08-17: Updated test Firestore rules to match production's mutable
  `itemIds` contract for inventory movement transactions while retaining frozen
  accounting-shape fields.
- 2026-08-17: The full documented non-emulator iOS unit profile passed with all
  five Firebase integration suites explicitly skipped. Existing unrelated
  compiler and asset-catalog warnings remain. `git diff --check` also passed.
- 2026-08-17: Published signed and notarized macOS Sparkle build 38 to Firebase
  Hosting, verified the live appcast/archive and Gatekeeper assessment, then
  updated `/Applications/Ledger.app` from build 37 through the real Sparkle UI.
  The installed build reports version 1.0 (38).
- 2026-08-17: Installed-app walkthrough passed without creating production test
  records: both business-paid choices and explanations render; project resale
  skips unknown-project selection; unscoped resale offers “I don't know yet”;
  unscoped covered purchase requires a project; initial quick-draft capture
  exposes From Inventory; and both detail-screen and Items-screen conversion
  routes require an inventory acquisition and omit the unlinked inventory
  bypass.
- 2026-08-17: Completed a labeled real-Firestore write-path test in the Assiist
  Biz account. The test exposed and fixed two installed-app defects: project
  categories were not reliably available in quick-draft conversion, and the
  completed acquisition intent was not marked resolved. Sparkle build 40 was
  signed, notarized, deployed, installed, and retested. The final run inherited
  Brianhead Cabin / Furnishings, created a $1.25 project Purchase and item from
  the selected $1.00 business inventory acquisition, converted the quick draft,
  recorded sale lineage atomically, and removed the completed acquisition from
  Planned for Projects. The equivalent MCP promotion now also resolves the
  acquisition intent; its TypeScript build passed.
- 2026-08-19: Completed the remaining disposable real-Firestore smoke through
  the local Ledger MCP. Verified purchase-intent dry-run isolation and committed
  updates, enriched waiting-state reads, authoritative quick-draft transaction
  linkage, From Inventory promotion, acquisition-intent resolution, purchase and
  project pricing, destination Purchase creation, and sold lineage. The harness
  removed every transaction, draft, item, and lineage document it created.

## Runtime QA Complete

The MCP package intentionally has no default local unit-test command. Its required
disposable real-Firestore smoke and the installed-app walkthrough are complete.
Future mutating MCP changes must repeat the disposable smoke and must not use
existing production records as fixtures.
