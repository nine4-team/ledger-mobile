# Implementation Plan: Phase 4 Screens Implementation

**Branch**: `main` | **Date**: 2026-02-26 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `kitty-specs/008-phase-4-screens-implementation/spec.md`

---

## Summary

Implement all user-facing screens for the SwiftUI iOS migration. Phases 1–3 built the foundation (Firebase, data models, navigation shell); Phase 5 delivered 45 reusable UI components. This phase wires those foundations into 30+ complete, functional screens spanning projects, transactions, items, spaces, inventory, creation flows, settings, universal search, and reports.

**Technical approach:** Pure logic first, screens second (14 WPs covering 7 sessions × 2 stages) plus WP00 (MediaService prerequisite) and 3 WPs splitting Session 7 into Settings/Search/Reports = **17 WPs total**. Every WP follows the test-first sequence: logic modules + tests → screens + navigation wiring.

---

## Technical Context

**Language/Version**: Swift 5.9 / SwiftUI, iOS 17+
**Primary Dependencies**: Firebase Swift SDK (Auth, Firestore, Storage), GoogleSignIn-iOS (SPM only)
**Storage**: Firestore (offline-first, native SDK cache) + Firebase Storage (images via `putData()`)
**Testing**: Swift Testing framework (`@Test`, `#expect`, `@Suite`) — **not XCTest**
**Target Platform**: iOS 17+, iPhone and iPad, light + dark mode
**Project Type**: Native SwiftUI iOS app (`LedgeriOS/LedgeriOS/`)
**Performance Goals**: Screen load from Firestore cache ≤1s; write reflection ≤200ms; search debounce 400ms, results ≤500ms for 1,000+ entities
**Constraints**: Offline-first (no blocking spinners); optimistic UI; bottom-sheet-first for all modals; no inline magic numbers (use `Theme/`); no XCTest; no CocoaPods; NavigationLink(value:) only
**Scale/Scope**: 30+ screens, 16+ modals, 13+ logic modules, 8 new services, >95% branch coverage on all pure logic

---

## Constitution Check

*No constitution.md found — section skipped.*

---

## Project Structure

### Documentation (this feature)

```
kitty-specs/008-phase-4-screens-implementation/
├── plan.md              ← This file
├── research.md          ← Phase 0 output (generated below)
├── data-model.md        ← Phase 1 output (generated below)
├── contracts/           ← Phase 1 output (Firestore field contracts)
└── tasks/               ← Phase 2 output (/spec-kitty.tasks — not created here)
```

### Source Code Layout

```
LedgeriOS/LedgeriOS/
├── Models/
│   ├── Item.swift                   ← Add `quantity: Int?` field (WP00)
│   ├── SpaceTemplate.swift          ← New model (WP13)
│   ├── VendorDefault.swift          ← New model (WP13)
│   ├── Invite.swift                 ← New model (WP13)
│   └── BusinessProfile.swift        ← New model (WP13)
├── Services/
│   ├── MediaService.swift           ← New (WP00)
│   ├── LineageEdgesService.swift    ← New (WP05/WP06)
│   ├── InventoryOperationsService.swift ← New (WP05/WP06)
│   ├── SpaceTemplatesService.swift  ← New (WP13)
│   ├── VendorDefaultsService.swift  ← New (WP13)
│   ├── InvitesService.swift         ← New (WP13)
│   ├── BusinessProfileService.swift ← New (WP13)
│   └── AccountPresetsService.swift  ← New (WP13)
├── Logic/
│   ├── TransactionDisplayCalculations.swift   ← New (WP03)
│   ├── TransactionNextStepsCalculations.swift  ← New (WP03)
│   ├── TransactionCompletenessCalculations.swift ← New (WP03, port from RN)
│   ├── TransactionListCalculations.swift       ← New (WP03)
│   ├── ItemListCalculations.swift              ← New (WP05)
│   ├── ItemDetailCalculations.swift            ← New (WP05)
│   ├── BulkSaleResolutionCalculations.swift    ← New (WP05)
│   ├── SpaceListCalculations.swift             ← New (WP07)
│   ├── SpaceDetailCalculations.swift           ← New (WP07)
│   ├── InventoryContext.swift                  ← New (WP09)
│   ├── ProjectFormValidation.swift             ← New (WP11)
│   ├── TransactionFormValidation.swift         ← New (WP11)
│   ├── ItemFormValidation.swift                ← New (WP11)
│   ├── SpaceFormValidation.swift               ← New (WP11)
│   ├── SearchCalculations.swift                ← New (WP15, port from RN)
│   ├── ReportAggregationCalculations.swift     ← New (WP16)
│   └── ReceiptListParser.swift                 ← New (WP03, port from RN)
├── Views/
│   ├── Projects/
│   │   ├── ProjectsListView.swift              ← Extend (WP02)
│   │   ├── ProjectDetailView.swift             ← Extend (WP02)
│   │   ├── BudgetTabView.swift                 ← Extend (WP02)
│   │   ├── TransactionsTabView.swift           ← New replaces placeholder (WP04)
│   │   ├── TransactionDetailView.swift         ← New (WP04)
│   │   ├── ItemsTabView.swift                  ← New replaces placeholder (WP06)
│   │   ├── ItemDetailView.swift                ← New (WP06)
│   │   ├── SpacesTabView.swift                 ← New replaces placeholder (WP08)
│   │   ├── SpaceDetailView.swift               ← New (WP08)
│   │   └── AccountingTabView.swift             ← New replaces placeholder (WP16)
│   ├── Inventory/
│   │   └── InventoryView.swift                 ← New replaces placeholder (WP10)
│   ├── Creation/
│   │   ├── NewProjectView.swift                ← New (WP12)
│   │   ├── NewTransactionView.swift            ← New (WP12)
│   │   ├── NewItemView.swift                   ← New (WP12)
│   │   └── NewSpaceView.swift                  ← New (WP12)
│   ├── Settings/
│   │   ├── SettingsView.swift                  ← New replaces placeholder (WP13)
│   │   ├── BudgetCategoryManagementView.swift  ← New (WP13)
│   │   ├── SpaceTemplateManagementView.swift   ← New (WP13)
│   │   ├── VendorDefaultsView.swift            ← New (WP13)
│   │   ├── UsersView.swift                     ← New (WP13)
│   │   └── AccountView.swift                   ← New (WP13)
│   ├── Search/
│   │   └── UniversalSearchView.swift           ← New replaces placeholder (WP15)
│   └── Reports/
│       ├── InvoiceReportView.swift             ← New (WP16)
│       ├── ClientSummaryReportView.swift       ← New (WP16)
│       └── PropertyManagementReportView.swift  ← New (WP16)
├── Modals/
│   ├── EditTransactionDetailsModal.swift       ← New (WP04)
│   ├── EditItemDetailsModal.swift              ← New (WP06)
│   ├── EditNotesModal.swift                    ← New shared (WP04)
│   ├── SetSpaceModal.swift                     ← New (WP06)
│   ├── ReassignToProjectModal.swift            ← New (WP06)
│   ├── SellToBusinessModal.swift               ← New (WP06)
│   ├── SellToProjectModal.swift                ← New (WP06)
│   ├── TransactionPickerModal.swift            ← New (WP06)
│   ├── ReturnTransactionPickerModal.swift      ← New (WP06)
│   ├── CategoryPickerList.swift                ← New (WP04)
│   ├── SpacePickerList.swift                   ← New (WP06)
│   ├── ProjectPickerList.swift                 ← New (WP06)
│   ├── MakeCopiesModal.swift                   ← New (WP06)
│   ├── StatusPickerModal.swift                 ← New (WP06)
│   ├── CreateItemsFromListModal.swift          ← New (WP04)
│   ├── EditSpaceDetailsModal.swift             ← New (WP08)
│   ├── EditChecklistModal.swift                ← New (WP08)
│   └── CategoryFormModal.swift                 ← New (WP13)
└── LedgeriOSTests/
    └── [Logic module tests — Swift Testing, per WP]
```

**Structure Decision**: Native SwiftUI iOS app, single-project structure. All new screens go in `Views/` subdirectories by domain. Logic modules stay in `Logic/`. New services go in `Services/`. Modals extracted to `Modals/` to match RN's established convention and CLAUDE.md "extract reusable sheet components" rule.

---

## Work Package Map

### WP00 — MediaService Prerequisite
**Scope:** Firebase Storage integration + PhotosPicker wiring + Item.quantity field addition
**Deliverables:**
- `MediaService.swift` — Firebase Storage `putData()` upload, download URL resolution, delete
- `MediaGallerySection` wiring: connect existing add/remove/set-primary actions to MediaService
- `Item.swift` — Add `quantity: Int?` field
- Tests for MediaService upload/download/delete happy paths and error cases

### WP01 — Session 1 Logic: Project List + Budget Tab Calculations
**Scope:** Pure logic modules for projects screen and budget tab
**Deliverables:**
- `ProjectListCalculations.swift` — extend existing: active/archived filter, alphabetical sort (case-insensitive), search across name+client, empty-state logic, budget bar priority (pinned → spend% → Overall Budget)
- `BudgetTabCalculations.swift` — extend existing: enabled categories filter, fee-last sort, spend normalization (canceled=$0, returns subtract, canonical sales sign, fee label "received"), overall budget exclusion
- Tests: happy path, edge cases (no categories, all archived, all fee), sort correctness

### WP02 — Session 1 Screens: Projects List + Project Detail Hub + Budget Tab
**Scope:** Wire WP01 logic into working screens
**Deliverables:**
- `ProjectsListView.swift` — real data, active/archived toggle, search bar, empty states with exact text, optimistic navigation
- `ProjectDetailView.swift` — 5-tab interface via `ScrollableTabBar`, kebab menu (Edit Project / Export Transactions CSV / Delete Project with confirmation), subscription lifecycle (`activate`/`deactivate`)
- `BudgetTabView.swift` — extend existing with pinned categories, correct sort, "received" for fees, overflow color
- Export Transactions CSV action via system share sheet (columns: id, date, source, amount, categoryName, budgetCategoryId, inventorySaleDirection, itemCategories)
- Navigation: `NavigationLink(value:)` from projects list → project detail

### WP03 — Session 2 Logic: Transaction Display + Next Steps + Completeness
**Scope:** Pure logic for transaction screens
**Deliverables:**
- `TransactionDisplayCalculations.swift` — display name (source → canonical inventory label → ID prefix → "Untitled Transaction"), badge config (type/reimbursement/receipt/needs-review/category colors), formatted date, formatted amount
- `TransactionNextStepsCalculations.swift` — 5/6 step checklist: categorize, enter amount, add receipt, add items, set purchased by, conditional tax rate; hide card when all complete
- `TransactionCompletenessCalculations.swift` — port from `src/utils/transactionCompleteness.ts`: ratio=itemsNetTotalCents/transactionSubtotalCents; thresholds (over>1.2, complete≤1%, near≤20%, incomplete otherwise); variance calculation; subtotal resolution (explicit → inferred from amount+taxRate → fallback amount)
- `TransactionListCalculations.swift` — sort (8 modes: date/created/source/amount asc+desc, default date-desc), filter (8 dimensions), search across source/notes/type/amount
- `ReceiptListParser.swift` — port from `src/utils/receiptListParser.ts`: parse free-form receipt text into `(name: String, price: Int?)` pairs; expose skipped lines
- Tests: completeness thresholds (all 4 states + null), subtotal resolution priority, next-steps (5-step and 6-step), filter dimensions, receiptListParser edge cases

### WP04 — Session 2 Screens: Transactions Tab + Transaction Detail
**Scope:** Wire WP03 logic into screens and modals
**Deliverables:**
- `TransactionsTabView.swift` — replaces `TransactionsTabPlaceholder.swift`; real data from `ProjectContext.transactions`; transaction cards sorted date-desc; toolbar (search, sort, filter, add); navigation to detail
- `TransactionDetailView.swift` — hero card, Next Steps card (hidden when complete), 8 collapsible sections (Receipts expanded, others collapsed), Moved Items non-collapsible, Transaction Audit section, action menu for delete
- Modals wired: `EditTransactionDetailsModal`, `EditNotesModal`, `CategoryPickerList`, `CreateItemsFromListModal`
- `CreateItemsFromListModal.swift` — two-step: paste text → preview parsed items + skipped-lines disclosure → create all items linked to transaction
- Navigation: tab content → `NavigationLink(value: transaction)` → `TransactionDetailView`

### WP05 — Session 3 Logic: Item List + Item Detail + Bulk Sale Calculations
**Scope:** Pure logic for items screens
**Deliverables:**
- `ItemListCalculations.swift` — 10 filter modes (project scope) + 7 filter modes (inventory scope), multi-select filtering; 4 sort modes (created-desc default); search (name/source/SKU/notes); duplicate grouping (name+SKU+source case-insensitive → expandable groups)
- `ItemDetailCalculations.swift` — contextual action menu generation based on item status; display logic (project price vs purchase price, space name resolution, category name resolution)
- `BulkSaleResolutionCalculations.swift` — category resolution for sell operations; filters out items with `transactionId` for bulk reassign
- Tests: all 10 filter modes individually and combined, duplicate grouping algorithm, action menu contextual logic, bulk sale category resolution

### WP06 — Session 3 Screens: Items Tab + Item Detail + 13 Modals
**Scope:** Wire WP05 logic into screens and all item modals
**Deliverables:**
- `ItemsTabView.swift` — replaces `ItemsTabPlaceholder.swift`; real data; `ItemsListControlBar` (sort + filter); multi-select with `BulkSelectionBar`; duplicate group rows; `SharedItemsList` embedded mode fix (add `.onChange(of:)` handler)
- `ItemDetailView.swift` — hero card (name, quantity, purchase/project/market price), collapsible sections (media, notes, details), contextual action menu
- **13 modals wired:** `EditItemDetailsModal`, `EditNotesModal`, `SetSpaceModal`, `ReassignToProjectModal`, `SellToBusinessModal`, `SellToProjectModal`, `TransactionPickerModal`, `ReturnTransactionPickerModal`, `CategoryPickerList`, `SpacePickerList`, `ProjectPickerList`, `MakeCopiesModal`, `StatusPickerModal`
- New services: `InventoryOperationsService` (sell/reassign multi-step Firestore writes), `LineageEdgesService` (lineage edge reads/writes for Moved Items)
- Navigation: items tab → `NavigationLink(value: item)` → `ItemDetailView`

### WP07 — Session 4 Logic: Space List + Space Detail Calculations
**Scope:** Pure logic for spaces screens
**Deliverables:**
- `SpaceListCalculations.swift` — sort, filter, search for space cards; checklist progress computation (X of Y complete)
- `SpaceDetailCalculations.swift` — checklist progress per space; item grouping for space scope; role check for "Save as Template" (owner/admin only)
- Tests: checklist progress (0/0, 0/N, N/N, partial), role check gate, space item grouping

### WP08 — Session 4 Screens: Spaces Tab + Space Detail + Modals
**Scope:** Wire WP07 logic into screens and space modals
**Deliverables:**
- `SpacesTabView.swift` — replaces `SpacesTabPlaceholder.swift`; space cards with name/item count/checklist progress; add button
- `SpaceDetailView.swift` — 4 collapsible sections: Media (expanded), Notes, Items (full `ItemsListControlBar` + 10 project-scope filter modes), Checklists; "Save as Template" action (role-gated)
- Modals: `EditSpaceDetailsModal`, `EditChecklistModal` (add/remove/reorder/check items), `EditNotesModal` (reused)
- Navigation: spaces tab → `NavigationLink(value: space)` → `SpaceDetailView`

### WP09 — Session 5 Logic: Inventory Context
**Scope:** Inventory-scoped state management
**Deliverables:**
- `InventoryContext.swift` — `@MainActor @Observable` class managing inventory-scoped subscriptions (items, transactions, spaces via `scope: .inventory`); persists last-selected tab to `UserDefaults`
- Extend `ProjectContext` if needed for inventory fallback paths
- Tests: scope filtering ensures no project-scoped data bleeds into inventory view

### WP10 — Session 5 Screens: Inventory Screen
**Scope:** Wire WP09 into the Inventory tab
**Deliverables:**
- `InventoryView.swift` — replaces `InventoryPlaceholderView.swift`; 3 sub-tabs (`ScrollableTabBar`): Items/Transactions/Spaces scoped to business inventory; reuses `SharedItemsList`, `SharedTransactionsList`, space card list; tab selection persisted
- Full filtering, sorting, bulk operations available (same as project-scoped)
- Navigation: Inventory tab root → reuses same detail screens (ItemDetailView, TransactionDetailView, SpaceDetailView)

### WP11 — Session 6 Logic: Creation Form Validation
**Scope:** Pure validation logic for all creation flows
**Deliverables:**
- `ProjectFormValidation.swift` — required: name, clientName; budget allocation sum
- `TransactionFormValidation.swift` — progressive disclosure validation: type → destination → detail fields; required field rules per type
- `ItemFormValidation.swift` — required: name; price field validation
- `SpaceFormValidation.swift` — required: name
- Tests: required field errors, boundary values, valid/invalid inputs for each form

### WP12 — Session 6 Screens: Creation Flows
**Scope:** Wire WP11 validation into creation form screens
**Deliverables:**
- `NewProjectView.swift` — name (required), clientName (required), description, main image upload (MediaService), per-category budget allocation; present as bottom sheet
- `NewTransactionView.swift` — progressive disclosure: type selection → destination/channel → detail fields (source, date, amount, status, purchasedBy, reimbursementType, notes, category, emailReceipt, conditional tax); vendor suggestions from VendorDefaults
- `NewItemView.swift` — name, source, SKU, status, purchase/project/market price, quantity, space selection (SpacePickerList), transaction association (TransactionPickerModal), image upload (MediaService)
- `NewSpaceView.swift` — name, notes, optional template selection
- All forms: optimistic UI (navigate back immediately, entity appears in list), required field validation blocks submission
- Accessibility from project detail tabs, inventory screen, and center Add button

### WP13 — Session 7a Screens: Settings
**Scope:** All Settings tab screens and their new services/models
**Deliverables:**
- New models: `SpaceTemplate`, `VendorDefault`, `Invite`, `BusinessProfile`
- New services: `SpaceTemplatesService`, `VendorDefaultsService`, `InvitesService`, `BusinessProfileService`, `AccountPresetsService`
- `SettingsView.swift` — replaces `SettingsPlaceholderView.swift`; 4-tab interface: General, Presets, Users, Account
- `BudgetCategoryManagementView.swift` — full CRUD, drag-reorder (`DraggableCardList`), archive/unarchive with warning; `CategoryFormModal` (name required max 100 chars, isItemized, isFee mutually exclusive, excludeFromOverallBudget); exact validation error messages from spec
- `SpaceTemplateManagementView.swift` — full CRUD, reorder; template fields: name, notes, checklists, isArchived, order
- `VendorDefaultsView.swift` — manage vendor list; pre-populate with common stores; add/remove/reorder
- `UsersView.swift` — team member list with roles, pending invitations, create invitation with role selection
- `AccountView.swift` — business profile (name, logo upload via MediaService), create new account, sign out (clears all local state → back to sign-in)
- General tab: theme selection (light/dark/system), account info display

### WP14 — Session 7b Logic: Search Calculations
**Scope:** Pure search logic (no RN equivalent — net new for Phase 4)
**Deliverables:**
- `SearchCalculations.swift` — three matching strategies:
  1. Case-insensitive substring for text fields (per-entity field mapping per FR-13.4–13.6)
  2. Amount prefix-range: parse typed amount string ("40" → [$4000–$4099]; "40.0" → [$4000–$4009]; strips `$` and `,`; converts to cents range)
  3. Normalized SKU: strip all non-alphanumeric chars, case-insensitive comparison
- Tests: amount prefix-range edge cases (integer-only, one decimal, two decimal, `$` prefix, comma separators, invalid input), SKU normalization (hyphen, slash, space, mixed case), text substring (case sensitivity, empty query)

### WP15 — Session 7b Screens: Universal Search
**Scope:** Wire WP14 logic into the Search tab
**Deliverables:**
- `UniversalSearchView.swift` — replaces `SearchPlaceholderView.swift`; search bar (auto-focus on mount); 3 result tabs (Items, Transactions, Spaces) with result counts; initial state (search icon + "Start typing to search"); per-tab empty states with exact text; debounce ~400ms; real-time filter from `AccountContext` / `ProjectContext` data
- Navigation: result tap → appropriate detail screen
- Tab selection persists across search sessions

### WP16 — Session 7c Logic + Screens: Reports + PDF Sharing
**Scope:** Report aggregation logic and all three report views
**Deliverables:**
- `ReportAggregationCalculations.swift`:
  - Invoice: split transactions into Charge Lines / Credit Lines (excludes canceled); per-line: display name, date, notes, amount, category, linked items with project prices; compute charges subtotal, credits subtotal, net due; flag items with missing project prices
  - Client Summary: total spent (sum project prices), total market value, total saved (marketValue−projectPrice where marketValue>0), per-category breakdown (category from item.budgetCategoryId or item's transaction.budgetCategoryId), per-item list with receipt link 3-states
  - Property Management: group items by space; each item: name, source, SKU, market value; "No Space" group for unassigned; total item count + total market value
- `InvoiceReportView.swift`, `ClientSummaryReportView.swift`, `PropertyManagementReportView.swift` — native SwiftUI scrollable views (no WebView); share via system share sheet as PDF via `ImageRenderer`
- `AccountingTabView.swift` — replaces `AccountingTabPlaceholder.swift`; two reimbursement summary cards (Owed to Design Business / Owed to Client); three report navigation buttons; skip canceled transactions in totals
- Tests: all aggregation functions (Invoice net due, Client Summary totals, Property Management grouping)

---

## Dependency Graph

```
WP00 (MediaService + Item.quantity)
  ↓
WP01 (Session 1 Logic) → WP02 (Session 1 Screens)
WP03 (Session 2 Logic) → WP04 (Session 2 Screens: depends on WP02 ProjectContext)
WP05 (Session 3 Logic) → WP06 (Session 3 Screens: depends on WP04)
WP07 (Session 4 Logic) → WP08 (Session 4 Screens: depends on WP06)
WP09 (Inventory Context) → WP10 (Inventory Screens: depends on WP06, WP08)
WP11 (Creation Validation) → WP12 (Creation Screens: depends on WP02, WP04, WP06, WP08)
WP13 (Settings: depends on WP00)
WP14 (Search Logic) → WP15 (Search Screens: depends on WP02–WP08 for data access)
WP16 (Reports: depends on WP04)
```

**Parallel opportunities:**
- WP01 and WP03 can be started in parallel (separate logic domains)
- WP07, WP09, WP11, WP14 can run in parallel after their respective screen WPs are done
- WP13 can run in parallel with WP09–WP12 (no shared dependencies beyond WP00)

---

## Key Model Gaps (Identified from Codebase Audit)

| Gap | Fix | WP |
|-----|-----|----|
| `Item.quantity` field missing | Add `quantity: Int?` to `Item.swift` | WP00 |
| `ChecklistItem.isCompleted` naming | `isChecked` in Swift model — use as-is (semantically equivalent), update spec terminology | WP07 |
| `ProjectBudgetCategoriesService` lacks create/delete | Add if needed for budget allocation in NewProjectView | WP11 |
| No search/filter utilities in RN | Net-new Swift implementation; derive from FR-13 requirements | WP14 |

## Risk Register

| Risk | Mitigation |
|------|-----------|
| Component integration gaps (45 pre-built components designed against spec, not real data) | Each session WP validates components against reference screenshots; fix during screen WP |
| Business logic divergence (JS→Swift: float, date, string differences) | Unit tests mirror RN test cases; port `transactionCompleteness.test.ts` and `receiptListParser.test.ts` verbatim |
| SharedItemsList embedded mode bug | Fix `.onChange(of:)` handler in WP06 |
| Session 7+ scope creep | WP13/14/15/16 are independent; each can be split further if needed |
| 8 missing services (none exist yet) | WP00 builds MediaService; others deferred to their first use session |

---

## Complexity Tracking

*No constitution violations — no entries required.*
