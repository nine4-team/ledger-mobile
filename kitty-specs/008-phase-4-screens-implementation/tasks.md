# Work Packages: Phase 4 Screens Implementation

**Inputs**: Design documents from `/kitty-specs/008-phase-4-screens-implementation/`
**Prerequisites**: plan.md (required), spec.md (user stories), data-model.md (complete)

**Tests**: Required — all pure logic modules need >95% branch coverage using Swift Testing (`@Test`, `#expect`, `@Suite`).

**Organization**: Fine-grained subtasks (`Txxx`) roll up into 17 work packages (`WP00`–`WP16`). Each work package is independently deliverable. Logic WPs always precede their corresponding Screen WPs.

**Prompt Files**: Each work package references a matching prompt file in `/tasks/` with deep implementation detail.

## Subtask Format: `[Txxx] [P?] Description`
- **[P]** indicates the subtask can proceed in parallel (different files/concerns).
- File paths are relative to `LedgeriOS/LedgeriOS/`.

---

## Work Package WP00: MediaService Prerequisite (Priority: P0) 🎯 MVP

**Goal**: Build shared Firebase Storage service + wire it into MediaGallerySection; add missing `Item.quantity` field. Every subsequent WP that involves images depends on this.
**Independent Test**: MediaService can upload a UIImage as JPEG data to Firebase Storage and return a download URL; deletes work; `Item.quantity` round-trips through Firestore Codable.
**Prompt**: `tasks/WP00-media-service-prerequisite.md`

### Included Subtasks
- [x] T001 Add `quantity: Int?` to `Item.swift` with correct `CodingKeys` mapping
- [x] T002 Create `Services/MediaService.swift` — upload via `putData()`, download URL resolution, delete
- [x] T003 Wire `MediaService` into existing `MediaGallerySection` add/remove/set-primary actions
- [x] T004 Write Swift Testing tests for MediaService happy paths and error cases

### Implementation Notes
- `MediaService` is a `@MainActor @Observable` class injected via `.environment()`.
- Upload uses `putData(_ data: Data, metadata: StorageMetadata?)` — not `putFile()`.
- Image picking uses `PhotosPicker` (iOS 16+, SwiftUI native).
- `MediaGallerySection` already has add/remove/set-primary callbacks — just wire them to call `MediaService`.

### Parallel Opportunities
- T001 (model change) and T002 (new service) are independent; both can start simultaneously.

### Dependencies
- None (this IS the prerequisite).

### Estimated Prompt Size
~280 lines

### Risks & Mitigations
- Firebase Storage rules must allow authenticated writes — verify before testing upload.

---

## Work Package WP01: Session 1 Logic — Project List + Budget Tab (Priority: P0)

**Goal**: Implement pure logic modules for project list filtering/sorting and budget tab calculations. Tests gate the screen WP.
**Independent Test**: All Swift Testing tests pass: correct sort order, active/archived filter, budget spend normalization, fee label, pinned categories.
**Prompt**: `tasks/WP01-session-1-logic.md`

### Included Subtasks
- [x] T005 Create `Logic/ProjectListCalculations.swift` — active/archived filter, alphabetical sort (case-insensitive), search across name+client, empty-state logic, budget bar priority
- [x] T006 Create (or extend) `Logic/BudgetTabCalculations.swift` — enabled-categories filter, fee-last sort, spend normalization (canceled=$0, returns subtract, canonical sales sign-based, fee label "received"), overall budget exclusion for `excludeFromOverallBudget` categories
- [x] T007 Write Swift Testing suite for ProjectListCalculations (happy path, all-archived, no-name sort, search)
- [x] T008 Write Swift Testing suite for BudgetTabCalculations (normalization rules, fee label, pinned order, overall budget exclusion)

### Implementation Notes
- Budget bar priority: (1) pinned categories (from ProjectPreferences.pinnedBudgetCategoryIds), (2) top by spend%, (3) "Overall Budget" row if no activity.
- Spend normalization: `isCanceled=true` → $0; `status==returned` or negative amount → subtract; `isCanonicalInventorySale` with `inventorySaleDirection==project_to_business` → subtract; all others → add.

### Parallel Opportunities
- T005 and T006 are independent (separate files); T007 and T008 depend on their respective implementations.

### Dependencies
- Depends on WP00 (Item.quantity field needed by some budget-related item calculations).

### Estimated Prompt Size
~380 lines

### Risks & Mitigations
- Spend normalization rules are complex — test every combination; port from `src/utils/` RN logic.

---

## Work Package WP02: Session 1 Screens — Projects List + Project Detail + Budget Tab (Priority: P0) 🎯 MVP

**Goal**: Replace placeholder project screens with real data-driven views. Users can browse projects, enter project detail, view the budget tab, and export transactions CSV.
**Independent Test**: Launch app → Projects tab shows real data sorted alphabetically → tap project → budget tab shows correct category rows.
**Prompt**: `tasks/WP02-session-1-screens.md`

### Included Subtasks
- [ ] T009 Extend `Views/Projects/ProjectsListView.swift` — real Firestore subscription, active/archived toggle, search bar, `ProjectCard` wiring, empty states ("No active projects yet." / "No archived projects yet.")
- [ ] T010 Extend `Views/Projects/ProjectDetailView.swift` — 5-tab `ScrollableTabBar` (Budget/Items/Transactions/Spaces/Accounting), kebab menu (Edit Project / Export Transactions CSV / Delete Project with `.confirmationDialog()`), subscription lifecycle `activate`/`deactivate`
- [ ] T011 Implement "Export Transactions CSV" action — generate CSV string (columns: id, date, source, amount, categoryName, budgetCategoryId, inventorySaleDirection, itemCategories), share via `UIActivityViewController`
- [ ] T012 Extend `Views/Projects/BudgetTabView.swift` — wire WP01 logic, pinned categories, correct sort, "received" label for fee categories, overflow color
- [ ] T013 Implement `NavigationLink(value: project)` → `ProjectDetailView` navigation from projects list

### Implementation Notes
- Use `NavigationLink(value:)` + `.navigationDestination(for: Project.self)`.
- Kebab menu triggers delete with `.confirmationDialog()` — hard delete from Firestore.
- The 4 non-Budget tabs (Items, Transactions, Spaces, Accounting) remain as placeholder views until their respective session WPs.
- CSV export uses `String` building (no CSV library needed at this scale).

### Parallel Opportunities
- T011 (CSV export) is independent of T012 (budget tab); both can be implemented simultaneously after T010.

### Dependencies
- Depends on WP01.

### Estimated Prompt Size
~420 lines

### Risks & Mitigations
- `ProjectsListView` may currently have a placeholder subscription — fully replace it, don't layer on top.

---

## Work Package WP03: Session 2 Logic — Transaction Display + Next Steps + Completeness + Receipt Parser (Priority: P1)

**Goal**: Implement all pure logic for transaction screens. Five logic modules, all tested.
**Independent Test**: All Swift Testing suites pass; completeness thresholds match the pinned business rules exactly.
**Prompt**: `tasks/WP03-session-2-logic.md`

### Included Subtasks
- [x] T014 Create `Logic/TransactionDisplayCalculations.swift` — display name priority (source → canonical label → ID prefix → "Untitled Transaction"), badge config (type/reimbursement/receipt/needs-review/category colors), formatted date, formatted amount
- [x] T015 Create `Logic/TransactionNextStepsCalculations.swift` — 5-step base checklist (categorize, enter amount, add receipt, add items, set purchased by) + conditional 6th step (set tax rate — only for itemized budget categories); hide card when all complete
- [x] T016 Create `Logic/TransactionCompletenessCalculations.swift` — port from `src/utils/transactionCompleteness.ts`: ratio=itemsNetTotalCents/subtotal; exact thresholds: over>1.2, complete≤1%, near≤20%, incomplete otherwise; subtotal resolution priority (explicit → inferred from amount+taxRate → fallback amount)
- [x] T017 Create `Logic/TransactionListCalculations.swift` — 8 sort modes (date/created/source/amount asc+desc), 8 filter dimensions (status, reimbursement, receipt, type, completeness, budget category, purchased by, source), text search (source/notes/type/amount)
- [x] T018 Create `Logic/ReceiptListParser.swift` — port from `src/utils/receiptListParser.ts`: parse free-form text into `[(name: String, priceCents: Int?)]` pairs; expose skipped lines
- [x] T019 Write Swift Testing suites for all 5 modules (completeness thresholds all 4 states + null, subtotal resolution priority, next-steps 5-step and 6-step, all 8 filter dimensions, receiptListParser edge cases)

### Implementation Notes
- All monetary values as `Int` cents — never `Double`.
- Canonical inventory sale label: `isCanonicalInventorySale=true` → use direction-based label ("Sold to Inventory" / "Purchased from Inventory").
- Port `receiptListParser.test.ts` test cases verbatim to Swift Testing.

### Parallel Opportunities
- T014–T018 are all independent files — all 5 can be implemented simultaneously. Tests (T019) depend on their respective implementations.

### Dependencies
- Depends on WP00 (Item model complete).

### Estimated Prompt Size
~460 lines

### Risks & Mitigations
- JS→Swift float/rounding differences — test completeness with exact cent integer arithmetic.
- `ReceiptListParser` edge cases (blank lines, price-only lines, "$" prefix, commas) — port test suite verbatim.

---

## Work Package WP04: Session 2 Screens — Transactions Tab + Transaction Detail + Modals (Priority: P1)

**Goal**: Replace `TransactionsTabPlaceholder.swift` with real transaction list; build `TransactionDetailView` with all sections; wire `EditTransactionDetailsModal`, `EditNotesModal`, `CategoryPickerList`, `CreateItemsFromListModal`.
**Independent Test**: Transactions tab shows real data; tapping a transaction opens detail with correct badge colors, Next Steps card, and collapsible sections in correct default states.
**Prompt**: `tasks/WP04-session-2-screens.md`

### Included Subtasks
- [ ] T020 Create `Views/Projects/TransactionsTabView.swift` — replaces placeholder; real data from `ProjectContext.transactions`; toolbar (search, sort, filter, add pills); transaction cards sorted date-desc; navigation to detail
- [ ] T021 Create `Views/Projects/TransactionDetailView.swift` — hero card, Next Steps card (hidden when complete), 8 collapsible sections (Receipts expanded; Others/Notes/Details/Items/ReturnedItems/SoldItems/TransactionAudit collapsed), Moved Items non-collapsible (FR-5.13), Transaction Audit section, action menu for delete
- [ ] T022 Create/wire `Modals/EditTransactionDetailsModal.swift` — field order: Vendor/Source (with vendor suggestions from presets), Amount, Date, Status, Purchased By, Transaction Type, Reimbursement Type, Budget Category, Email Receipt, conditional Subtotal+TaxRate; present as bottom sheet
- [ ] T023 Create/wire `Modals/EditNotesModal.swift` — shared notes editing bottom sheet
- [ ] T024 Create/wire `Modals/CategoryPickerList.swift` — single-select budget category picker; used from transaction detail
- [ ] T025 Create `Modals/CreateItemsFromListModal.swift` — two-step: (1) paste text → (2) preview parsed items + skipped-lines disclosure → create all items linked to transaction; uses `ReceiptListParser`

### Implementation Notes
- Transaction detail Items section (FR-5.15): 6 sort modes + 6 filter modes for the items subsection.
- Moved Items section: always visible (not collapsible) when lineage edges exist; renders `ItemCard` at 50% opacity.
- `EditTransactionDetailsModal`: vendor suggestions autocomplete from `VendorDefaultsService` (show as picker or text suggestions).
- Tax Amount is computed display field: Amount − Subtotal (read-only, derived).

### Parallel Opportunities
- T022–T025 (modals) can be built in parallel once T021 skeleton exists.

### Dependencies
- Depends on WP02 (ProjectContext subscription active), WP03 (all logic modules).

### Estimated Prompt Size
~480 lines

### Risks & Mitigations
- Moved Items requires `LineageEdgesService` — stub the service if not yet built; show empty section.
- `CreateItemsFromListModal` two-step flow — ensure step 2 renders parsed items + skipped lines with disclosure.

---

## Work Package WP05: Session 3 Logic — Item List + Item Detail + Bulk Sale Calculations (Priority: P1)

**Goal**: Implement all pure logic for item screens — filtering (10 project-scope modes, 7 inventory-scope modes), sorting, search, duplicate grouping, action menu generation, and bulk sale category resolution.
**Independent Test**: All Swift Testing suites pass; 10 filter modes individually and combined; duplicate grouping algorithm correct; action menu contextual to item status.
**Prompt**: `tasks/WP05-session-3-logic.md`

### Included Subtasks
- [ ] T026 Create `Logic/ItemListCalculations.swift` — 10 filter modes (project scope): all/bookmarked/from-inventory/to-return/returned/no-sku/no-name/no-project-price/no-image/no-transaction; 7 filter modes (inventory scope): all/bookmarked/no-sku/no-name/no-project-price/no-image/no-transaction; multi-select filter support; 4 sort modes (created-desc default, created-asc, alpha-asc, alpha-desc); text search (name/source/SKU/notes); duplicate grouping algorithm (name+SKU+source case-insensitive → expandable group rows)
- [ ] T027 Create `Logic/ItemDetailCalculations.swift` — contextual action menu generation based on item status (active items: full 11 operations; returned/sold items: limited); display logic (project price vs purchase price priority; space name resolution; category name resolution)
- [ ] T028 Create `Logic/BulkSaleResolutionCalculations.swift` — category resolution map for sell operations; filters out items with `transactionId` (must unlink first for bulk reassign)
- [ ] T029 Write Swift Testing suite for all three modules (all 10 filter modes individually + combined; duplicate grouping with case variations; action menu for each item status; bulk sale eligibility filter)

### Implementation Notes
- Duplicate grouping: group key = `(name ?? "").lowercased() + "|" + (sku ?? "").lowercased() + "|" + (source ?? "").lowercased()`. Groups with count>1 become expandable group rows in the list.
- Multi-select filtering: multiple filter modes active simultaneously (union or intersection — match RN behavior, likely intersection).
- Action menu for `returned` status items: only bookmark/unbookmark + delete available.

### Parallel Opportunities
- T026, T027, T028 are independent files; all 3 can be implemented in parallel. T029 depends on all 3.

### Dependencies
- Depends on WP00 (Item.quantity present).

### Estimated Prompt Size
~400 lines

### Risks & Mitigations
- Multi-select filter intersection vs. union — check RN source; default to intersection if unclear.

---

## Work Package WP06: Session 3 Screens — Items Tab + Item Detail + 13 Modals (Priority: P1)

**Goal**: Replace `ItemsTabPlaceholder.swift` with real items list; build `ItemDetailView`; wire all 13 item modals; add `InventoryOperationsService` and `LineageEdgesService`.
**Independent Test**: Items tab shows real data with filter/sort toolbar; multi-select works; tapping item opens detail with hero card and all collapsible sections; action menu presents correct options per item status.
**Prompt**: `tasks/WP06-session-3-screens.md`

### Included Subtasks
- [ ] T030 Create `Views/Projects/ItemsTabView.swift` — replaces placeholder; real data from `ProjectContext.items`; `ItemsListControlBar` (sort + filter chips); multi-select with `BulkSelectionBar`; duplicate group rows (expandable); fix `SharedItemsList` embedded mode `.onChange(of:)` handler; navigation to detail
- [ ] T031 Create `Views/Projects/ItemDetailView.swift` — hero card (name, quantity, purchase price, project price, market value), 3 collapsible sections (Media expanded, Notes collapsed, Details collapsed), contextual action menu sheet
- [ ] T032 Create `Services/InventoryOperationsService.swift` — sell-to-business (creates sale + purchase Firestore records), sell-to-project (destination project + category resolution), reassign operations; multi-item Firestore batch writes
- [ ] T033 Create `Services/LineageEdgesService.swift` — read/write lineage edges for Moved Items display in TransactionDetailView
- [ ] T034 [P] Wire item modals (7): `EditItemDetailsModal` (field order: Name/Source/SKU/PurchasePrice/ProjectPrice/MarketValue), `SetSpaceModal`, `ReassignToProjectModal`, `SellToBusinessModal` (description text per spec), `SellToProjectModal` (description text per spec), `MakeCopiesModal`, `StatusPickerModal`
- [ ] T035 [P] Wire picker modals (6): `TransactionPickerModal`, `ReturnTransactionPickerModal`, `CategoryPickerList`, `SpacePickerList`, `ProjectPickerList`, `EditNotesModal` (reuse from WP04)

### Implementation Notes
- `SellToBusinessModal`: show description "This will move items from the project into business inventory. A sale record will be created for financial tracking. If you're just fixing a misallocation, use Reassign instead."
- `SellToProjectModal`: show description "Sale and purchase records will be created for financial tracking. If you're just fixing a misallocation, use Reassign instead."
- `ReturnTransactionPickerModal`: filter to incomplete return transactions only.
- Fix `SharedItemsList` embedded mode: add `.onChange(of: items) { newItems in localItems = newItems }`.

### Parallel Opportunities
- T034 and T035 (modal groups) are fully parallel to each other once T031 skeleton exists.

### Dependencies
- Depends on WP04 (TransactionPickerModal context, ProjectContext established), WP05 (logic modules).

### Estimated Prompt Size
~520 lines

### Risks & Mitigations
- 13 modals is a large surface — stub them first with correct sheet presentation, then fill in logic.
- `InventoryOperationsService` multi-step Firestore writes must be atomic (use batch writes).

---

## Work Package WP07: Session 4 Logic — Space List + Space Detail Calculations (Priority: P2)

**Goal**: Implement pure logic for space screens — sorting, filtering, checklist progress, and role-gated template save.
**Independent Test**: All Swift Testing suites pass: checklist progress (0/0, 0/N, N/N, partial), role check gate, space item grouping.
**Prompt**: `tasks/WP07-session-4-logic.md`

### Included Subtasks
- [ ] T036 Create `Logic/SpaceListCalculations.swift` — sort (alphabetical), filter (name search), checklist progress computation (X of Y complete across all checklists)
- [ ] T037 Create `Logic/SpaceDetailCalculations.swift` — checklist progress per space; item grouping for space-scoped display (filter items by `spaceId`); role check for "Save as Template" (owner/admin only)
- [ ] T038 Write Swift Testing suite for both modules (progress edge cases: empty checklists, all complete, partial; role gate: owner/admin pass, member fails; item grouping by spaceId)

### Implementation Notes
- Checklist progress: sum of all `isChecked=true` across all checklists / total checklist items across all checklists.
- Role values: "owner", "admin", "member" — "Save as Template" allowed for owner and admin only.
- Space item list in SpaceDetail uses full 10 project-scope filter modes (FR-9.10).

### Parallel Opportunities
- T036 and T037 are independent; both can be implemented simultaneously. T038 depends on both.

### Dependencies
- Depends on WP06 (items data fully wired; role handling pattern established).

### Estimated Prompt Size
~300 lines

### Risks & Mitigations
- `ChecklistItem.isChecked` vs `isCompleted` naming — use `isChecked` (confirmed existing Swift field name).

---

## Work Package WP08: Session 4 Screens — Spaces Tab + Space Detail + Modals (Priority: P2)

**Goal**: Replace `SpacesTabPlaceholder.swift` with real spaces list; build `SpaceDetailView` with 4 collapsible sections; wire `EditSpaceDetailsModal`, `EditChecklistModal`, `EditNotesModal`.
**Independent Test**: Spaces tab shows real data with item counts and checklist progress; tapping space opens detail with Media expanded by default; checklist editing works.
**Prompt**: `tasks/WP08-session-4-screens.md`

### Included Subtasks
- [ ] T039 Create `Views/Projects/SpacesTabView.swift` — replaces placeholder; space cards (name, item count, checklist progress); add button; navigation to detail
- [ ] T040 Create `Views/Projects/SpaceDetailView.swift` — 4 collapsible sections: Media (expanded), Notes (collapsed), Items (collapsed, with full `ItemsListControlBar` + 10 filter modes), Checklists (collapsed); "Save as Template" action (role-gated)
- [ ] T041 Create/wire `Modals/EditSpaceDetailsModal.swift` — edit name and notes fields; bottom sheet
- [ ] T042 Create/wire `Modals/EditChecklistModal.swift` — add/remove/reorder/check checklist items; Firestore optimistic update

### Implementation Notes
- "Save as Template" creates a `SpaceTemplate` in Firestore via `SpaceTemplatesService` (stubbed here, fully built in WP13).
- Space Detail Items section is a full `SharedItemsList` in embedded mode using the fixed `.onChange(of:)` handler from WP06.
- `EditChecklistModal`: supports adding new items (with a text field), removing items (swipe-to-delete), reordering (drag handles), and checking/unchecking items.

### Parallel Opportunities
- T041 and T042 can be built in parallel once T040 skeleton exists.

### Dependencies
- Depends on WP06 (SharedItemsList embedded fix applied), WP07 (logic modules).

### Estimated Prompt Size
~360 lines

### Risks & Mitigations
- Checklist reorder: use SwiftUI's `.onMove` modifier with a `@State var editMode`. Persist to Firestore optimistically.

---

## Work Package WP09: Session 5 Logic — Inventory Context (Priority: P2)

**Goal**: Build `InventoryContext` — the `@MainActor @Observable` state manager for inventory-scoped data, with tab persistence.
**Independent Test**: `InventoryContext.activate()` subscribes to inventory-scoped items/transactions/spaces; switching scope doesn't bleed project data; `UserDefaults` tab key persists.
**Prompt**: `tasks/WP09-inventory-context.md`

### Included Subtasks
- [ ] T043 Create `State/InventoryContext.swift` — `@MainActor @Observable` class; manages 3 Firestore subscriptions (items/transactions/spaces with `scope: .inventory`); `activate(accountId:)` / `deactivate()` lifecycle; persists `lastSelectedTab` to `UserDefaults("inventorySelectedTab")`
- [ ] T044 Inject `InventoryContext` into the app environment (`.environment(inventoryContext)`) alongside existing `ProjectContext` and `AccountContext`
- [ ] T045 Write Swift Testing suite: scope filtering (inventory scope returns no project-scoped data), UserDefaults persistence round-trip

### Implementation Notes
- Pattern mirrors `ProjectContext` — use same `activate`/`deactivate` lifecycle with `@Observable`.
- `scope: .inventory` means items/transactions with `projectId == nil` (or equivalent inventory scope predicate — check existing `ItemsService` for scope enum).

### Parallel Opportunities
- T043 and T044 are sequential (inject after creation). T045 can start alongside T044.

### Dependencies
- Depends on WP08 (establish pattern that inventory sub-views reuse project detail screens).

### Estimated Prompt Size
~280 lines

### Risks & Mitigations
- Check how `ItemsService` handles `scope: .inventory` — confirm the filter predicate before implementing.

---

## Work Package WP10: Session 5 Screens — Inventory Screen (Priority: P2)

**Goal**: Replace `InventoryPlaceholderView.swift` with a working 3-tab inventory screen reusing project-scoped list components.
**Independent Test**: Inventory tab shows Items/Transactions/Spaces sub-tabs; Items tab shows only inventory-scoped items; filtering/sorting/bulk operations work; tab selection persists across restarts.
**Prompt**: `tasks/WP10-inventory-screens.md`

### Included Subtasks
- [ ] T046 Create `Views/Inventory/InventoryView.swift` — replaces placeholder; 3 sub-tabs via `ScrollableTabBar` (Items/Transactions/Spaces); reads from `InventoryContext`; restores last tab from UserDefaults
- [ ] T047 Wire inventory Items sub-tab: reuse `SharedItemsList` with inventory-scoped data; full filter/sort/bulk ops; navigation → `ItemDetailView` (same screen as project-scoped)
- [ ] T048 Wire inventory Transactions sub-tab: reuse `SharedTransactionsList` with inventory-scoped data; full filter/sort; navigation → `TransactionDetailView`
- [ ] T049 Wire inventory Spaces sub-tab: reuse space card list with inventory-scoped spaces; add button; navigation → `SpaceDetailView`

### Implementation Notes
- All detail screens (`ItemDetailView`, `TransactionDetailView`, `SpaceDetailView`) are reused — no new detail views needed.
- Inventory-scoped creation: "Add" button in Spaces sub-tab opens `NewSpaceView` with inventory context.
- Navigation: each sub-tab maintains its own navigation path within the `NavigationStack` for the Inventory tab.

### Parallel Opportunities
- T047, T048, T049 are parallel once T046 skeleton exists.

### Dependencies
- Depends on WP09 (InventoryContext built and injected), WP06 (ItemDetailView), WP04 (TransactionDetailView), WP08 (SpaceDetailView).

### Estimated Prompt Size
~320 lines

### Risks & Mitigations
- `SharedItemsList` and `SharedTransactionsList` may have project-scoped assumptions — verify they accept inventory-scoped data cleanly.

---

## Work Package WP11: Session 6 Logic — Creation Form Validation (Priority: P2)

**Goal**: Implement pure validation logic for all 4 creation forms.
**Independent Test**: All Swift Testing suites pass: required field errors, boundary values, transaction progressive disclosure rules, valid/invalid inputs.
**Prompt**: `tasks/WP11-creation-form-validation.md`

### Included Subtasks
- [ ] T050 Create `Logic/ProjectFormValidation.swift` — required: name ("Name is required"), clientName ("Client name is required"); budget allocation sum validation
- [ ] T051 Create `Logic/TransactionFormValidation.swift` — progressive disclosure: type required → destination required → detail field rules per type; required fields per type
- [ ] T052 Create `Logic/ItemFormValidation.swift` — required: name ("Name is required"); price field validation (non-negative integers)
- [ ] T053 Create `Logic/SpaceFormValidation.swift` — required: name ("Name is required")
- [ ] T054 Write Swift Testing suites for all 4 validators (required field errors with exact messages, boundary values, valid inputs, transaction type-specific field requirements)

### Implementation Notes
- Use exact error messages from the spec (data-model.md: Validation Error Messages table).
- `TransactionFormValidation`: progressive disclosure means type selection unlocks destination field, destination unlocks detail fields — validate only visible fields.
- All validation returns `[ValidationError]` (struct with field + message) — consistent across all 4 forms.

### Parallel Opportunities
- T050–T053 are all independent; all 4 can be implemented simultaneously. T054 depends on all 4.

### Dependencies
- Depends on WP08 (pattern for form presentation established).

### Estimated Prompt Size
~330 lines

### Risks & Mitigations
- Transaction form has the most complex validation — test all 4 transaction types with their specific required fields.

---

## Work Package WP12: Session 6 Screens — Creation Flows (Priority: P2)

**Goal**: Build all 4 creation form bottom sheets. After submission, entities appear immediately in lists (optimistic UI) and the form dismisses.
**Independent Test**: Each form opens as a bottom sheet, validates required fields, creates entity in Firestore, dismisses, and new entity appears in the list.
**Prompt**: `tasks/WP12-creation-screens.md`

### Included Subtasks
- [ ] T055 Create `Views/Creation/NewProjectView.swift` — name (required), clientName (required), description, main image upload (via MediaService + PhotosPicker), per-category budget allocation; presents as `.sheet()` `.presentationDetents([.large])`
- [ ] T056 Create `Views/Creation/NewTransactionView.swift` — progressive disclosure: type selection → destination/channel → detail fields (source, date, amount, status, purchasedBy, reimbursementType, notes, category, emailReceipt, conditional tax); vendor suggestions from VendorDefaults
- [ ] T057 Create `Views/Creation/NewItemView.swift` — name, source, SKU, status, purchase/project/market price, quantity, space selection (`SpacePickerList`), transaction association (`TransactionPickerModal`), image upload (MediaService)
- [ ] T058 Create `Views/Creation/NewSpaceView.swift` — name, notes, optional template selection (from `SpaceTemplatesService` — stub if WP13 not yet done)
- [ ] T059 Wire accessibility entry points: "Add" button in project detail tabs + Inventory sub-tabs + potential center FAB button

### Implementation Notes
- All forms: optimistic UI — call `dismiss()` immediately after initiating Firestore write (don't `await`).
- `NewProjectView` budget allocation: per-category dollar input fields (one row per enabled budget category).
- `NewTransactionView`: progressive disclosure — hide destination/detail fields until type selected.
- Required field validation: disable Submit button OR show inline error on tap attempt.

### Parallel Opportunities
- T055–T058 are independent (separate files); all 4 can be built in parallel. T059 depends on all 4.

### Dependencies
- Depends on WP11 (validation logic), WP02 (project context for budget categories), WP04 (transaction context), WP06 (item creation wiring), WP08 (space context).

### Estimated Prompt Size
~440 lines

### Risks & Mitigations
- `NewProjectView` budget allocation UI — needs a scrollable form with one text field per category; handle keyboard avoidance.
- Vendor suggestions in `NewTransactionView` — stub `VendorDefaultsService` reads if WP13 not yet merged.

---

## Work Package WP13: Session 7a Screens — Settings (Priority: P3)

**Goal**: Replace `SettingsPlaceholderView.swift` with a full 4-tab Settings screen, including all new models, services, CRUD management views, and `CategoryFormModal`.
**Independent Test**: Settings tab opens with 4 tabs; Budget Categories CRUD works; drag-reorder persists; CategoryFormModal validation shows exact error messages; sign out clears state.
**Prompt**: `tasks/WP13-settings-screens.md`

### Included Subtasks
- [ ] T060 Create new models: `Models/SpaceTemplate.swift`, `Models/VendorDefault.swift`, `Models/Invite.swift`, `Models/BusinessProfile.swift` (Swift structs, Codable, per data-model.md)
- [ ] T061 Create new services: `Services/SpaceTemplatesService.swift`, `Services/VendorDefaultsService.swift`, `Services/InvitesService.swift`, `Services/BusinessProfileService.swift`, `Services/AccountPresetsService.swift` (Firestore CRUD with offline-first reads)
- [ ] T062 Create `Views/Settings/SettingsView.swift` — replaces placeholder; 4-tab interface (General/Presets/Users/Account) via `ScrollableTabBar`
- [ ] T063 Create `Views/Settings/BudgetCategoryManagementView.swift` + `Modals/CategoryFormModal.swift` — full CRUD, drag-reorder (`DraggableCardList`), archive/unarchive with warning; exact validation error messages from spec
- [ ] T064 [P] Create `Views/Settings/SpaceTemplateManagementView.swift` — full CRUD, reorder; template fields per data-model.md
- [ ] T065 [P] Create `Views/Settings/VendorDefaultsView.swift` + `Views/Settings/UsersView.swift` + `Views/Settings/AccountView.swift` — manage vendor list, team members, business profile (logo upload via MediaService), sign-out action

### Implementation Notes
- `CategoryFormModal` exact validation: name max 100 chars → "Category name must be 100 characters or less"; isItemized AND isFee → "A category cannot be both Itemized and Fee".
- `AccountPresetsService`: pre-populate vendor list with: Home Depot, Wayfair, West Elm, Pottery Barn (check RN `src/data/accountPresetsService.ts` for full list).
- Sign out: clear `ProjectContext`, `InventoryContext`, `AccountContext` state → navigate to sign-in screen.
- General tab: theme selection stored in `UserDefaults("colorSchemePreference")` with values: "light", "dark", "system" (default).

### Parallel Opportunities
- T064 and T065 are independent (different views/files); both can proceed simultaneously after T062.

### Dependencies
- Depends on WP00 (MediaService for logo upload), WP01 (budget categories context).

### Estimated Prompt Size
~500 lines

### Risks & Mitigations
- `DraggableCardList` for budget category reorder — verify this component exists in Phase 5 component library; if not, use SwiftUI's built-in `.onMove`.
- `SpaceTemplatesService` also used by WP08 ("Save as Template") and WP12 (`NewSpaceView`) — stub those consumers as needed until WP13 lands.

---

## Work Package WP14: Session 7b Logic — Search Calculations (Priority: P3)

**Goal**: Implement `SearchCalculations.swift` — three matching strategies (text substring, amount prefix-range, normalized SKU) with per-entity field mapping. Fully tested.
**Independent Test**: All Swift Testing suites pass: amount prefix-range edge cases, SKU normalization, text substring (case, empty query), per-entity field mapping.
**Prompt**: `tasks/WP14-search-logic.md`

### Included Subtasks
- [ ] T066 Create `Logic/SearchCalculations.swift` — three matching strategies: (1) case-insensitive text substring for text fields; (2) amount prefix-range (parse typed string → cents range; handle $, commas, integer/decimal variants per data-model.md algorithm); (3) normalized SKU (strip non-alphanumeric, case-insensitive); per-entity field mapping (FR-13.4–13.6)
- [ ] T067 Write Swift Testing suite — amount prefix-range edge cases (integer-only, one decimal, two decimal, $ prefix, comma separators, invalid input); SKU normalization (hyphen, slash, space, mixed case); text substring (case sensitivity, empty query, nil fields); per-entity field mapping verification

### Implementation Notes
- Amount prefix-range algorithm (from data-model.md):
  1. Strip leading `$` and commas
  2. Split on "." → integer + decimal parts
  3. Integer only → range `[cents, cents+99]`
  4. One decimal → range `[cents*10, cents*10+9]`
  5. Two decimals → exact cents match
  6. Invalid → no amount matching (skip, don't crash)
- `SearchCalculations` function signature: `func search(query: String, items: [Item], transactions: [Transaction], spaces: [Space], categories: [BudgetCategory]) -> SearchResults`

### Parallel Opportunities
- T066 and T067 are sequential (tests depend on implementation); but T066 is a single file — fast to implement.

### Dependencies
- Depends on WP06 (Item/Transaction/Space data models fully understood).

### Estimated Prompt Size
~300 lines

### Risks & Mitigations
- Amount prefix-range for "40.0" vs "40.00" — these produce different ranges; test all 3 decimal cases.
- Empty query: should return all results (not empty results).

---

## Work Package WP15: Session 7b Screens — Universal Search (Priority: P3)

**Goal**: Replace `SearchPlaceholderView.swift` with a real universal search screen using WP14 logic. Debounced 400ms, 3 result tabs, auto-focus on mount.
**Independent Test**: Type a query → results appear in ≤500ms; "40" matches transactions/items with amounts $40.00–$40.99; tapping result navigates to detail screen.
**Prompt**: `tasks/WP15-search-screens.md`

### Included Subtasks
- [ ] T068 Create `Views/Search/UniversalSearchView.swift` — replaces placeholder; search bar (auto-focus on mount via `.focused()`); initial state: centered search icon + "Start typing to search"; 3 result tabs (Items/Transactions/Spaces) with result counts; debounce ~400ms; per-tab empty states ("No items found", "No transactions found", "No spaces found")
- [ ] T069 Wire search results — read from `AccountContext` / `ProjectContext` data (all items, transactions, spaces the user has access to); apply `SearchCalculations.search()` on debounced query; display using existing `ItemCard`, `TransactionCard`, space card components
- [ ] T070 Wire result navigation — `ItemCard` tap → `ItemDetailView`; `TransactionCard` tap → `TransactionDetailView`; space row tap → `SpaceDetailView`

### Implementation Notes
- Debounce using Combine `PassthroughSubject` + `.debounce(for: .milliseconds(400), scheduler: RunLoop.main)` or Swift Concurrency `Task.sleep(for: .milliseconds(400))`.
- Tab selection: persist last-selected tab in `@State` (within session only — no UserDefaults needed).
- Search scope: all data the user has access to (all projects' items/transactions/spaces + inventory).

### Parallel Opportunities
- T069 and T070 are sequential within the view build.

### Dependencies
- Depends on WP14 (SearchCalculations), WP02–WP08 (detail screens exist for navigation).

### Estimated Prompt Size
~320 lines

### Risks & Mitigations
- Auto-focus on mount: use `@FocusState` with `.onAppear { isFocused = true }` — verify it works on iOS 17.
- Data scope: `AccountContext` may need to expose all items/transactions across projects for cross-project search — verify or add a cross-project data feed.

---

## Work Package WP16: Session 7c Logic + Screens — Reports + Accounting Tab (Priority: P3)

**Goal**: Implement `ReportAggregationCalculations.swift` and all 3 report views + `AccountingTabView`. Reports are native SwiftUI, shareable as PDF via `ImageRenderer`.
**Independent Test**: Invoice net due = charges subtotal − credits subtotal; Client Summary totals correct; Property Management groups by space with "No Space" fallback; PDF share sheet opens.
**Prompt**: `tasks/WP16-reports-accounting.md`

### Included Subtasks
- [ ] T071 Create `Logic/ReportAggregationCalculations.swift` — three aggregation functions: Invoice (split by reimbursementType, exclude canceled, per-line display name/date/notes/amount/category/items, compute charges+credits+netDue, flag missing project prices); Client Summary (total spent=sum projectPrices, total market value, total saved=sum(marketValue−projectPrice where marketValue>0), per-category breakdown, per-item list with receipt link 3 states); Property Management (group items by spaceId → space name, "No Space" for nil, per item: name/source/SKU/marketValue, total count+total market value)
- [ ] T072 Write Swift Testing suite for all 3 aggregations (Invoice net due, Client Summary totals, Property Management grouping including "No Space" group)
- [ ] T073 Create `Views/Projects/AccountingTabView.swift` — replaces `AccountingTabPlaceholder.swift`; two reimbursement summary cards (Owed to Design Business / Owed to Client; skip canceled transactions); three report navigation buttons (Property Management / Client Summary / Invoice)
- [ ] T074 Create `Views/Reports/InvoiceReportView.swift` — native SwiftUI scrollable; Charge Lines section + Credit Lines section + net due summary; share button → `ImageRenderer` PDF → `UIActivityViewController`
- [ ] T075 [P] Create `Views/Reports/ClientSummaryReportView.swift` — category breakdown + per-item list + totals; share button → PDF
- [ ] T076 [P] Create `Views/Reports/PropertyManagementReportView.swift` — grouped by space; "No Space" section; totals; share button → PDF

### Implementation Notes
- Receipt link 3 states for Client Summary (FR-15.2): `{type:'invoice'}` (canonical sale or invoiceable reimbursement), `{type:'receipt-url', url:String}` (has receipt image), `null` (none).
- `ImageRenderer` for PDF: wrap the SwiftUI view in `ImageRenderer`, call `.render(rects:)` and convert to `PDFDocument` or use `CGContext` PDF rendering.
- Report navigation: from `AccountingTabView` tap → push `InvoiceReportView` etc. onto the navigation stack.
- Reimbursement totals in AccountingTabView: skip `isCanceled=true` transactions.

### Parallel Opportunities
- T075 and T076 can be built in parallel once T074 pattern is established.

### Dependencies
- Depends on WP04 (TransactionDetailView navigation pattern), WP02 (ProjectContext for transactions/items/spaces/categories data).

### Estimated Prompt Size
~460 lines

### Risks & Mitigations
- `ImageRenderer` PDF quality — test with dense report data; may need multi-page PDF for large invoices.
- Category name resolution in Client Summary: resolve from `item.budgetCategoryId` first, then from `item's transaction.budgetCategoryId` — requires joining two data sources.

---

## Dependency & Execution Summary

```
WP00 (MediaService + Item.quantity)
  ↓
WP01 (Session 1 Logic) → WP02 (Session 1 Screens)
                          ↓
WP03 (Session 2 Logic) → WP04 (Session 2 Screens)
                          ↓
WP05 (Session 3 Logic) → WP06 (Session 3 Screens)
                          ↓
WP07 (Session 4 Logic) → WP08 (Session 4 Screens)
                          ↓
              WP09 (Inventory Context) → WP10 (Inventory Screens)
              WP11 (Creation Logic)    → WP12 (Creation Screens)
              WP13 (Settings: depends on WP00)
              WP14 (Search Logic)      → WP15 (Search Screens)
              WP16 (Reports: depends on WP04)
```

**Parallel opportunities:**
- WP01 and WP03 logic modules can run in parallel (separate domains)
- WP07, WP09, WP11, WP14 can all start in parallel after WP06
- WP13 can run in parallel with WP09–WP12 (only shares WP00 dependency)
- Within each logic WP: all module files are independent (parallel)
- Within each screen WP: modals can be built in parallel once the main view skeleton exists

**MVP Scope**: WP00 → WP01 → WP02 (users can browse projects and budget).

---

## Subtask Index (Reference)

| Subtask | Summary | Work Package | Priority | Parallel? |
|---------|---------|--------------|----------|-----------|
| T001 | Add `Item.quantity: Int?` | WP00 | P0 | Yes |
| T002 | Create MediaService | WP00 | P0 | Yes |
| T003 | Wire MediaService → MediaGallerySection | WP00 | P0 | No |
| T004 | MediaService tests | WP00 | P0 | No |
| T005 | ProjectListCalculations | WP01 | P0 | Yes |
| T006 | BudgetTabCalculations | WP01 | P0 | Yes |
| T007 | Tests: ProjectListCalculations | WP01 | P0 | No |
| T008 | Tests: BudgetTabCalculations | WP01 | P0 | No |
| T009 | ProjectsListView (real data) | WP02 | P0 | No |
| T010 | ProjectDetailView (5-tab + kebab) | WP02 | P0 | No |
| T011 | Export Transactions CSV | WP02 | P0 | Yes |
| T012 | BudgetTabView (wired) | WP02 | P0 | Yes |
| T013 | NavigationLink projects → detail | WP02 | P0 | No |
| T014 | TransactionDisplayCalculations | WP03 | P1 | Yes |
| T015 | TransactionNextStepsCalculations | WP03 | P1 | Yes |
| T016 | TransactionCompletenessCalculations | WP03 | P1 | Yes |
| T017 | TransactionListCalculations | WP03 | P1 | Yes |
| T018 | ReceiptListParser | WP03 | P1 | Yes |
| T019 | Tests: all 5 transaction logic modules | WP03 | P1 | No |
| T020 | TransactionsTabView | WP04 | P1 | No |
| T021 | TransactionDetailView | WP04 | P1 | No |
| T022 | EditTransactionDetailsModal | WP04 | P1 | Yes |
| T023 | EditNotesModal | WP04 | P1 | Yes |
| T024 | CategoryPickerList | WP04 | P1 | Yes |
| T025 | CreateItemsFromListModal | WP04 | P1 | Yes |
| T026 | ItemListCalculations (10+7 filter modes) | WP05 | P1 | Yes |
| T027 | ItemDetailCalculations (action menu) | WP05 | P1 | Yes |
| T028 | BulkSaleResolutionCalculations | WP05 | P1 | Yes |
| T029 | Tests: all 3 item logic modules | WP05 | P1 | No |
| T030 | ItemsTabView (with duplicate groups) | WP06 | P1 | No |
| T031 | ItemDetailView | WP06 | P1 | No |
| T032 | InventoryOperationsService | WP06 | P1 | No |
| T033 | LineageEdgesService | WP06 | P1 | No |
| T034 | Wire item modals (7) | WP06 | P1 | Yes |
| T035 | Wire picker modals (6) | WP06 | P1 | Yes |
| T036 | SpaceListCalculations | WP07 | P2 | Yes |
| T037 | SpaceDetailCalculations | WP07 | P2 | Yes |
| T038 | Tests: space logic modules | WP07 | P2 | No |
| T039 | SpacesTabView | WP08 | P2 | No |
| T040 | SpaceDetailView (4 sections) | WP08 | P2 | No |
| T041 | EditSpaceDetailsModal | WP08 | P2 | Yes |
| T042 | EditChecklistModal | WP08 | P2 | Yes |
| T043 | InventoryContext (@Observable) | WP09 | P2 | No |
| T044 | Inject InventoryContext into environment | WP09 | P2 | No |
| T045 | Tests: InventoryContext scope filter | WP09 | P2 | Yes |
| T046 | InventoryView (3 sub-tabs) | WP10 | P2 | No |
| T047 | Inventory Items sub-tab | WP10 | P2 | Yes |
| T048 | Inventory Transactions sub-tab | WP10 | P2 | Yes |
| T049 | Inventory Spaces sub-tab | WP10 | P2 | Yes |
| T050 | ProjectFormValidation | WP11 | P2 | Yes |
| T051 | TransactionFormValidation | WP11 | P2 | Yes |
| T052 | ItemFormValidation | WP11 | P2 | Yes |
| T053 | SpaceFormValidation | WP11 | P2 | Yes |
| T054 | Tests: all 4 form validators | WP11 | P2 | No |
| T055 | NewProjectView | WP12 | P2 | Yes |
| T056 | NewTransactionView | WP12 | P2 | Yes |
| T057 | NewItemView | WP12 | P2 | Yes |
| T058 | NewSpaceView | WP12 | P2 | Yes |
| T059 | Wire entry points (Add buttons) | WP12 | P2 | No |
| T060 | New models (SpaceTemplate/VendorDefault/Invite/BusinessProfile) | WP13 | P3 | Yes |
| T061 | New services (5 settings services) | WP13 | P3 | No |
| T062 | SettingsView (4-tab) | WP13 | P3 | No |
| T063 | BudgetCategoryManagementView + CategoryFormModal | WP13 | P3 | No |
| T064 | SpaceTemplateManagementView | WP13 | P3 | Yes |
| T065 | VendorDefaultsView + UsersView + AccountView | WP13 | P3 | Yes |
| T066 | SearchCalculations (3 strategies) | WP14 | P3 | No |
| T067 | Tests: SearchCalculations | WP14 | P3 | No |
| T068 | UniversalSearchView | WP15 | P3 | No |
| T069 | Wire search results | WP15 | P3 | No |
| T070 | Wire result navigation | WP15 | P3 | No |
| T071 | ReportAggregationCalculations (3 reports) | WP16 | P3 | No |
| T072 | Tests: report aggregations | WP16 | P3 | No |
| T073 | AccountingTabView | WP16 | P3 | No |
| T074 | InvoiceReportView + PDF share | WP16 | P3 | No |
| T075 | ClientSummaryReportView + PDF share | WP16 | P3 | Yes |
| T076 | PropertyManagementReportView + PDF share | WP16 | P3 | Yes |

---

> This tasks.md serves as the high-level checklist. All deep implementation detail lives in the individual WP prompt files in `tasks/`.
