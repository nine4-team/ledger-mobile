# Phase 4 Screens Implementation

## Feature Overview

### Problem Statement

The Ledger Mobile app is migrating from React Native (Expo) to native SwiftUI. Phases 1–3 delivered the foundation: Xcode project with Firebase, data models and services, navigation shell with auth gate and tabs. Phase 5 delivered 45 reusable UI components. But the app has no functional screens — all four tabs show placeholder content. Users cannot browse projects, view transactions, manage items, or access settings. The app is unusable.

### Proposed Solution

Implement all user-facing screens that replace the React Native app's functionality. This spans 7 implementation sessions covering: project browsing and detail views, transaction management, item management with bulk operations, space/location tracking, business inventory, entity creation forms, and utility screens (settings, search, reports). Each session produces a working, testable increment that wires existing data services and components into complete screen flows.

### Target Users

- **Interior designers** who manage procurement projects (the primary user base)
- **Design firm owners** who need budget tracking and reporting across multiple projects
- **Team members** who browse and update shared project data on mobile

### User Value

- **Browse and manage projects** with real-time Firestore data, budget progress tracking, and archived project access
- **Track transactions** with completeness scoring, next-steps guidance, receipt management, and categorized badge displays
- **Manage item inventory** with bulk operations (set space, reassign project, sell to business/project), multi-select, and detailed item views
- **Organize physical spaces** with checklist tracking and notes
- **Create new entities** (projects, transactions, items, spaces) through guided forms
- **Search across all data** with fuzzy matching, amount-range search, and cross-entity results
- **Configure account settings** including budget category management, team members, vendor defaults, and business profile

---

## User Scenarios & Testing

### Scenario 1: Project Browsing and Budget Review

**Actor:** Interior designer
**Trigger:** Opens the app to check project status

1. User sees the Projects tab with a list of active project cards showing names, client names, hero images, and budget progress previews
2. User switches to the Archived tab to see completed projects
3. User taps a project card to enter the Project Detail hub
4. User sees 5 tabs: Budget, Items, Transactions, Spaces, Accounting
5. User views the Budget tab showing each budget category with spent/remaining amounts, progress bars, and color-coded over-budget indicators
6. User sees an "Overall Budget" summary row at the bottom

**Acceptance:** Project list loads from Firestore cache immediately (no spinner), sorted by most recently updated. Budget tab shows correct aggregated amounts matching the Firestore data. Active/Archived toggle filters correctly. Empty states display when no projects exist.

### Scenario 2: Transaction Management

**Actor:** Designer reviewing a recent purchase
**Trigger:** Navigates to a project's Transactions tab

1. User sees transaction cards sorted by date (newest first) with vendor name, amount, date, item count, badges (type, category, receipt status), and truncated notes
2. User taps a transaction to see the full detail screen
3. Hero card shows transaction name, amount, and date
4. "Next Steps" card shows a progress ring and checklist (categorize, enter amount, add receipt, add items, set purchased by, optionally set tax rate)
5. Collapsible sections show receipts (expanded by default), other images, notes, details (11 fields), linked items, and optionally returned/sold items and transaction audit
6. Transaction audit section shows completeness status (complete/near/incomplete/over) with variance calculations when the budget category is itemized

**Acceptance:** Badge colors match the RN app's color scheme. Next Steps hides when all steps are complete. Tax rate step only appears for itemized budget categories. Completeness calculations match the existing `transactionCompleteness.ts` logic. Detail fields appear in the exact order from the RN app.

### Scenario 3: Item Management with Bulk Operations

**Actor:** Designer organizing newly purchased items
**Trigger:** Navigates to a project's Items tab

1. User sees item cards with name, source, price, status badge, and optional thumbnail
2. User uses the toolbar to search, sort by name/price/status/date, and filter by status/space/category
3. User taps an item to see the full detail screen with hero card (name, quantity, prices), media gallery, notes, and detail fields
4. User long-presses or uses the select button to enter multi-select mode
5. User selects multiple items and uses the bulk action bar to: set space, reassign to another project, sell to business inventory, or sell to another project
6. Sell-to-project flow prompts for destination project and resolves budget categories as needed

**Acceptance:** List filtering and sorting match the RN app's 6 filter types and 8 sort modes. Bulk operations present appropriate picker modals. Item detail shows all fields in the correct order. Action menu options are contextual to item status (active items can be sold/reassigned, returned items cannot).

### Scenario 4: Space and Checklist Management

**Actor:** Designer tracking room preparation
**Trigger:** Navigates to a project's Spaces tab

1. User sees space cards with names, item counts, and checklist progress
2. User taps a space to see the full detail screen with media, notes, and checklists
3. User edits a checklist via bottom sheet — adds items, checks/unchecks them, reorders
4. User creates a new space from the Spaces tab using the "Add" button
5. Space form accepts name, notes, and optional checklist template

**Acceptance:** Checklist progress displays correctly (X of Y complete). Editing a checklist updates Firestore optimistically. New spaces appear in the list immediately after creation (optimistic UI). Space detail shows items assigned to that space.

### Scenario 5: Inventory Screen

**Actor:** Firm owner checking business inventory
**Trigger:** Taps the Inventory tab

1. User sees 3 sub-tabs: Items, Transactions, Spaces — scoped to business inventory (no project filter)
2. Items tab reuses the same list component as the project Items tab, but scoped to all business-owned items
3. Transactions tab reuses the same list component scoped to business transactions
4. Spaces tab shows business inventory storage locations with add/edit capability
5. User can create new business spaces from this screen

**Acceptance:** Inventory scope shows only business-owned items/transactions (no project-scoped data). Same filtering, sorting, and bulk operations available as project-scoped lists. Tab selection persists across app sessions.

### Scenario 6: Entity Creation

**Actor:** Designer adding a new purchase
**Trigger:** Uses the "Add" button or navigates to a creation form

1. **New Project:** Form with name (required), client name (required), description, main image upload, and budget category allocation (per-category dollar amounts)
2. **New Transaction:** Progressive disclosure form — type selection (purchase/sale/return/to-inventory), then destination/channel, then detail fields (source, date, amount, status, purchased by, reimbursement type, notes, category, receipt, tax fields)
3. **New Item:** Form with name, source, SKU, status, purchase price, project price, quantity, space selection, image upload
4. **New Space:** Form with name, notes, optional checklist from template
5. After submission, user is navigated back to the list with the new entity visible (optimistic UI)

**Acceptance:** Required field validation prevents submission with empty required fields. Budget allocation in new project sums correctly. Transaction form shows/hides fields based on type selection. All forms dismiss cleanly and return to the originating screen. Created entities appear in lists immediately.

### Scenario 7: Settings and Account Management

**Actor:** Firm owner configuring the account
**Trigger:** Taps the Settings tab

1. **General tab:** Theme selection (light/dark/system), account info display
2. **Presets tab (sub-tabs):**
   - Budget Categories: CRUD, reorder, archive. Each category has name, type (general/itemized/fee), and optional metadata
   - Space Templates: CRUD, reorder. Templates have name and default checklist items
   - Vendors: Default vendor list for autofill in transaction forms
3. **Users tab:** Team member list with roles, pending invitations, ability to create new invitations with role selection
4. **Account tab:** Business profile (name, logo upload), create new account, sign out

**Acceptance:** Budget category changes reflect immediately in project budget views. Archived categories are hidden from pickers but preserved in historical data. Team member roles display correctly. Sign out clears all local state and returns to sign-in screen.

### Scenario 8: Universal Search

**Actor:** Designer looking for a specific item
**Trigger:** Taps the Search tab

1. User types in the search bar — results appear in real-time with debounced input
2. Three tabs: Items, Transactions, Spaces — each showing matching results
3. Item search matches on name, source, SKU, and notes (fuzzy)
4. Transaction search matches on source, notes, type, and supports amount-range prefix matching (typing "40" matches $40.00–$40.99)
5. Space search matches on name
6. User taps a result to navigate to the full detail screen

**Acceptance:** Search debounces at ~400ms to avoid excessive filtering. Amount prefix matching works correctly (e.g., "40.0" matches $40.00–$40.09). Results update as the user types. Each result navigates to the correct detail screen.

### Scenario 9: Reports

**Actor:** Designer generating a client deliverable
**Trigger:** Navigates to reports from the project detail

1. **Invoice Report:** Generates a formatted invoice view with line items, amounts, and totals from project transactions
2. **Client Summary Report:** Overview of project progress, budget utilization, and key metrics for client presentation
3. **Property Management Report:** Property-specific summary for management purposes
4. All reports render as scrollable native views (no WebView HTML)

**Acceptance:** Report data aggregates correctly from project transactions and budget data. Reports are read-only views (no editing). Reports can be shared via the system share sheet.

---

## Functional Requirements

### FR-1: Projects List Screen

- FR-1.1: Display all projects for the active account, sorted by most recently updated
- FR-1.2: Support Active/Archived tab filtering using an underline-style tab bar
- FR-1.3: Each project card shows: hero image (or placeholder), project name, client name, and budget category progress bars for top categories
- FR-1.4: Support text search filtering across project name and client name (case-insensitive)
- FR-1.5: Show appropriate empty state when no projects exist or no results match the search
- FR-1.6: Navigate to Project Detail on card tap
- FR-1.7: Manage its own Firestore subscription for the project list (independent of ProjectContext which requires a selected project)

### FR-2: Project Detail Hub

- FR-2.1: Display project name and client name in the navigation bar
- FR-2.2: Provide a 5-tab interface (Budget, Items, Transactions, Spaces, Accounting) using a scrollable underline tab bar
- FR-2.3: Activate real-time Firestore subscriptions (transactions, items, spaces, budget categories, budget progress) when the project is entered
- FR-2.4: Clean up all subscriptions when leaving the project detail
- FR-2.5: Provide a kebab menu with contextual project actions (edit, delete with confirmation)

### FR-3: Budget Tab

- FR-3.1: Display each enabled budget category with: category name, spent amount label, remaining/over amount label (color-coded), and a progress bar
- FR-3.2: Filter to only enabled categories (non-zero budget or non-zero spend)
- FR-3.3: Sort categories with fee categories last, then alphabetically
- FR-3.4: Display an "Overall Budget" summary row with aggregate totals
- FR-3.5: Show "received" instead of "spent" for fee-type categories
- FR-3.6: Color over-budget amounts in the overflow status color

### FR-4: Transactions Tab

- FR-4.1: Display transaction cards sorted by date descending (newest first), with nil dates sorted last
- FR-4.2: Each transaction card shows: badge row (type, reimbursement, receipt, needs-review, category), source/display name, formatted amount, date with item count, and truncated notes (italic, 2-line limit)
- FR-4.3: Badge colors follow the established mapping: Purchase (green), Sale (blue), Return (red), To Inventory (brand primary), Owed to Client/Business (amber), Receipt (primary), Needs Review (rust), Category (primary)
- FR-4.4: Support text search across source, notes, transaction type, and formatted amount
- FR-4.5: Provide toolbar with search, sort, filter, and add action pills (sort/filter/add are stubs initially)
- FR-4.6: Display name follows priority: source → canonical inventory sale label → ID prefix (6 chars) → "Untitled Transaction"
- FR-4.7: Navigate to Transaction Detail on card tap

### FR-5: Transaction Detail Screen

- FR-5.1: Display hero card with transaction display name, formatted amount, and formatted date
- FR-5.2: Display "Next Steps" card with progress ring showing completion fraction, incomplete steps first with chevrons, completed steps with strikethrough and gold checkmark
- FR-5.3: Next Steps computes 5 or 6 steps: categorize, enter amount, add receipt, add items, set purchased by, and conditionally set tax rate (only for itemized budget categories)
- FR-5.4: Next Steps card is hidden entirely when all steps are complete
- FR-5.5: Display collapsible sections in order: Receipts (expanded by default), Other Images, Notes, Details, Items, Returned Items (conditional), Sold Items (conditional), Transaction Audit (conditional)
- FR-5.6: Details section shows fields in exact order: Source, Date, Amount, Status, Purchased by, Reimbursement type, Budget category, Email receipt — then conditionally: Subtotal, Tax rate, Tax amount (only for itemized categories)
- FR-5.7: Transaction Audit section computes completeness (complete/near/incomplete/over) based on item prices vs. transaction subtotal, with variance percentage and status thresholds
- FR-5.8: Returned Items and Sold Items sections only appear when items with those statuses exist
- FR-5.9: Provide edit functionality for notes, details, and media via bottom sheet modals
- FR-5.10: Subtotal resolution follows priority: explicit subtotal → inferred from amount and tax rate → fallback to amount (with missing-tax-data flag)

### FR-6: Items Tab

- FR-6.1: Display item cards with name, source, price, status badge, and optional thumbnail image
- FR-6.2: Support 6 filter types: status (active/returned/sold/missing), location (project/business), price status (has/missing prices), space, budget category, market value
- FR-6.3: Support 8 sort modes: name, price, status, date-added (each ascending and descending)
- FR-6.4: Support text search across name, source, SKU, and notes
- FR-6.5: Support multi-select mode with bulk action bar offering: set space, reassign to project, sell to business, sell to project
- FR-6.6: Navigate to Item Detail on card tap

### FR-7: Item Detail Screen

- FR-7.1: Display hero card with item name, quantity, purchase price, and project price
- FR-7.2: Display collapsible sections: Media gallery, Notes, Details (status, space, source, SKU, prices, dates)
- FR-7.3: Provide contextual action menu based on item status — active items can be sold/reassigned/moved; returned/sold items have limited actions
- FR-7.4: Support editing notes, details, and media via bottom sheet modals
- FR-7.5: Support delete with confirmation dialog

### FR-8: Item Modals (10 modals wired during Items session)

- FR-8.1: EditItemDetailsModal — edit item fields (name, source, SKU, status, prices, quantity) via bottom sheet form
- FR-8.2: EditNotesModal — edit free-text notes field via bottom sheet
- FR-8.3: SetSpaceModal — assign item to a space using space picker (project-scoped)
- FR-8.4: ReassignToProjectModal — move item to a different project using project picker
- FR-8.5: SellToBusinessModal — confirm sell-to-business with optional source category picker
- FR-8.6: SellToProjectModal — confirm sell-to-project with destination project picker and dual category pickers
- FR-8.7: TransactionPickerModal — select transaction to link item(s) to
- FR-8.8: ReturnTransactionPickerModal — select return transaction with filtering for incomplete returns
- FR-8.9: CategoryPickerList — single-select budget category picker
- FR-8.10: SpacePickerList — single-select space picker with optional create-new

### FR-9: Spaces Tab and Space Detail

- FR-9.1: Display space cards with names, item counts, and checklist completion progress
- FR-9.2: Navigate to Space Detail on card tap
- FR-9.3: Space Detail shows media, notes, and checklists with collapsible sections
- FR-9.4: Checklist editing via EditChecklistModal — add/remove/reorder/check items
- FR-9.5: Space details editing via EditSpaceDetailsModal
- FR-9.6: Support creating new spaces from the tab
- FR-9.7: Show items assigned to each space

### FR-10: Inventory Screen

- FR-10.1: Display 3 sub-tabs (Items, Transactions, Spaces) scoped to business inventory
- FR-10.2: Items and Transactions tabs reuse the same list components as project-scoped versions, but filtered to business-owned entities only
- FR-10.3: Spaces tab shows business inventory storage locations with add/edit capability
- FR-10.4: Persist the last-selected tab across app sessions
- FR-10.5: Support all filtering, sorting, and bulk operations available in project-scoped lists

### FR-11: Creation Flows

- FR-11.1: New Project form with: name (required), client name (required), description, main image upload, and per-category budget allocation
- FR-11.2: New Transaction form with progressive disclosure: type → destination/channel → detail fields. Fields include: source, date, amount, status, purchased by, reimbursement type, notes, category, email receipt flag, and conditional tax fields
- FR-11.3: New Item form with: name, source, SKU, status, purchase price, project price, quantity, space selection, image upload
- FR-11.4: New Space form with: name, notes, optional checklist template selection
- FR-11.5: All forms validate required fields before submission
- FR-11.6: All forms navigate back to the originating list after successful creation with optimistic UI (new entity visible immediately)
- FR-11.7: Creation flows are accessible from both project-scoped and inventory-scoped contexts where applicable

### FR-12: Settings Screen

- FR-12.1: General tab with theme selection (light/dark/system) and account info display
- FR-12.2: Presets tab with sub-tabs for Budget Categories, Space Templates, and Vendors
- FR-12.3: Budget Categories: full CRUD, reorder, archive/unarchive. Each category has name, type (general/itemized/fee), and optional metadata
- FR-12.4: Space Templates: full CRUD, reorder. Templates define name and default checklist items
- FR-12.5: Vendors: manage default vendor list for transaction form autofill
- FR-12.6: Users tab: display team members with roles, show pending invitations, create new invitations with role selection
- FR-12.7: Account tab: business profile editing (name, logo), create new account, sign out (clears all local state)

### FR-13: Universal Search Screen

- FR-13.1: Display search bar with real-time debounced input (~400ms)
- FR-13.2: Three result tabs: Items, Transactions, Spaces
- FR-13.3: Item search matches across name, source, SKU, and notes with fuzzy matching
- FR-13.4: Transaction search matches across source, notes, type, and supports amount-range prefix matching (typing "40" matches $40.00–$40.99)
- FR-13.5: Space search matches on name
- FR-13.6: Navigate to the appropriate detail screen on result tap
- FR-13.7: Show result counts per tab

### FR-14: Reports

- FR-14.1: Invoice Report: formatted view with transaction line items, amounts, and totals
- FR-14.2: Client Summary Report: project progress overview with budget utilization
- FR-14.3: Property Management Report: property-specific summary
- FR-14.4: All reports render as native scrollable views
- FR-14.5: Reports support sharing via the system share sheet

### FR-15: Cross-Cutting Requirements

- FR-15.1: All screens work in both light and dark mode using the existing adaptive color system
- FR-15.2: All data loads from Firestore cache first (no blocking spinners) per the offline-first principles
- FR-15.3: All write operations are optimistic — UI updates immediately without waiting for server confirmation
- FR-15.4: All modals present as bottom sheets with `.presentationDetents()` and `.presentationDragIndicator(.visible)`
- FR-15.5: All business logic is extracted into pure function modules with comprehensive test coverage
- FR-15.6: Destructive actions (delete) require confirmation via `.confirmationDialog()`
- FR-15.7: Navigation uses `NavigationLink(value:)` with `.navigationDestination(for:)` — never deprecated label-based NavigationLink

---

## Key Entities

### Project
The primary organizing entity. Contains name, client name, description, main image, budget allocations, and serves as the parent for transactions, items, and spaces.

### Transaction
A financial event (purchase, sale, return, or inventory transfer). Contains source/vendor, amount, date, type, budget category, tax fields, receipt references, and linked items.

### Item
A physical inventory item tracked through the procurement lifecycle. Contains name, source, SKU, status (active/returned/sold), purchase price, project price, quantity, space assignment, and media.

### Space
A physical location (room, storage area, staging zone). Contains name, notes, checklists, and serves as a container for items. Exists in both project scope and business inventory scope.

### BudgetCategory
An account-level budget classification (e.g., "Furnishings", "Lighting", "Design Fees"). Has type (general/itemized/fee) and is allocated per-project with dollar amounts.

### AccountMember
A team member within an account. Has a role (owner/admin/member) and email. Managed through the Users settings tab.

---

## Success Criteria

1. Users can browse, filter, and search all project data (projects, transactions, items, spaces) within 1 second of screen load from cached data
2. All 30+ screens visually match the React Native app's dark mode reference screenshots in layout, spacing, and information hierarchy
3. All business logic calculations (budget progress, transaction completeness, next steps, display names, badge configs) produce identical results to the React Native implementations
4. Users can complete the full entity creation flow (project, transaction, item, space) without encountering validation errors on valid input
5. Bulk item operations (set space, reassign, sell) complete successfully for 1–50 selected items
6. All write operations reflect in the UI within 200ms of user action (optimistic updates)
7. Light and dark mode are correct on all screens with no hard-coded colors or missing adaptive values
8. Pure logic modules achieve >95% branch coverage through unit tests
9. Settings changes (budget categories, vendors, templates) propagate immediately to dependent screens
10. Universal search returns relevant results within 500ms of the debounce threshold for datasets of 1,000+ entities

---

## Dependencies

- **Phase 2 (Data Layer):** All Firestore models, services, and state managers must be complete. Deferred services (LineageEdgesService, InvitesService, BusinessProfileService, etc.) are added when their sessions need them.
- **Phase 3 (Navigation Shell):** Tab bar, auth gate, and account selection flow must be functional.
- **Phase 5 (Component Library):** All 45 reusable UI components must be merged to main. Known limitation: SharedItemsList embedded mode needs `.onChange(of:)` handler added during Phase 4 integration.
- **Reference Screenshots:** Dark mode screenshots in `reference/screenshots/dark/` serve as visual parity targets.
- **React Native Source:** `src/` directory serves as read-only reference for business logic, field orders, conditional rendering rules, and section structures.

---

## Assumptions

1. Firestore data structure is stable and matches the existing Swift model definitions (no schema changes needed during Phase 4)
2. The 45 existing UI components (Phase 5) are functionally complete and only need wiring, not redesign
3. Media upload/download via Firebase Storage is out of scope for initial screen implementation — placeholder handling is acceptable for images, with upload functionality added incrementally
4. Import flows (Amazon/Wayfair invoice parsing) are deferred to a later phase
5. Paywall/StoreKit 2 subscription management is deferred to a later phase
6. Mac Catalyst / macOS adaptation is deferred to Phase 6
7. Reports will initially render as native SwiftUI views; PDF generation (if needed) is a future enhancement
8. The "Accounting" tab in Project Detail is a summary view — full accounting features are deferred
9. Offline-first behavior is provided by the native Firestore SDK automatically — no custom offline queue is needed for reads/writes
10. All sessions build on the same branch pattern: pure logic + tests first, then components, then screens + navigation wiring

---

## Constraints

- **Bottom sheet convention:** All modals, pickers, and forms must present as bottom sheets (`.sheet()` with `.presentationDetents()`), matching the React Native app's established UX pattern
- **No inline magic numbers:** All spacing, typography, colors, and dimensions must use the established design token system in `Theme/`
- **Pure logic modules:** All business logic must be extracted into testable pure functions — no computation in view bodies
- **Swift Testing framework:** All tests must use Swift Testing (`@Test`, `#expect`, `@Suite`), not XCTest
- **NavigationStack per tab:** Each tab maintains its own NavigationStack; no shared navigation state across tabs
- **Optimistic UI:** Never block UI on Firestore server acknowledgment for reads or writes

---

## Session Breakdown

### Session 1: Projects List + Project Detail Hub + Budget Tab
**Screens:** ProjectsListView, ProjectDetailView, BudgetTabView, 4 tab placeholders (Items, Transactions, Spaces, Accounting)
**Logic modules:** ProjectListCalculations (filter/search/sort), BudgetTabCalculations (enabled categories, sort, labels)
**Components used:** ScrollableTabBar, ProjectCard, Card, BudgetProgressView, DetailRow, ContentUnavailableView
**Navigation:** Projects tab root → NavigationLink to ProjectDetail → tab switching within detail

### Session 2: Transactions Tab + Transaction Detail
**Screens:** TransactionsTabView (replaces placeholder), TransactionDetailView
**Logic modules:** TransactionDisplayCalculations (display name, formatting, badges), TransactionNextStepsCalculations (5-6 step checklist), TransactionCompletenessCalculations (audit), TransactionListCalculations (filter/sort)
**Modals wired:** EditTransactionDetailsModal, EditNotesModal, CategoryPickerList
**Components used:** TransactionCard, ProgressRing, ListToolbar, CollapsibleSection, Badge, DetailRow, ProgressBar
**Navigation:** Transactions tab content → NavigationLink to TransactionDetail

### Session 3: Items Tab + Item Detail + Modals
**Screens:** ItemsTabView (replaces placeholder), ItemDetailView
**Logic modules:** ItemListCalculations (6 filter types, 8 sort modes, search), ItemDetailCalculations (display logic, action menu generation), BulkSaleResolutionCalculations (category resolution for sell operations)
**Modals wired (10):** EditItemDetailsModal, EditNotesModal, SetSpaceModal, ReassignToProjectModal, SellToBusinessModal, SellToProjectModal, TransactionPickerModal, ReturnTransactionPickerModal, CategoryPickerList, SpacePickerList
**Components used:** ItemCard, SharedItemsList, BulkSelectionBar, ListControlBar, ActionMenuSheet, CollapsibleSection, MediaGallerySection
**Services added:** LineageEdgesService (if needed for return flow), InventoryOperationsService (for sell/reassign)
**Navigation:** Items tab content → NavigationLink to ItemDetail; bulk operations via modals

### Session 4: Spaces Tab + Space Detail + Modals
**Screens:** SpacesTabView (replaces placeholder), SpaceDetailView
**Logic modules:** SpaceListCalculations (sort/filter), SpaceDetailCalculations (checklist progress, item grouping)
**Modals wired (3):** EditSpaceDetailsModal, EditChecklistModal, EditNotesModal
**Components used:** SpaceCard, CollapsibleSection, MediaGallerySection, SharedItemsList (embedded mode)
**Navigation:** Spaces tab content → NavigationLink to SpaceDetail; editing via modals

### Session 5: Inventory Screen
**Screens:** InventoryView (replaces InventoryPlaceholderView) with 3 sub-tabs
**Logic modules:** Reuses ItemListCalculations, TransactionListCalculations, SpaceListCalculations with inventory scope
**Components used:** Reuses SharedItemsList, SharedTransactionsList, SpaceCard list, ScrollableTabBar
**State:** Persists last-selected tab to UserDefaults
**Navigation:** Inventory tab root → reuses same detail screen navigation as project-scoped lists

### Session 6: Creation Flows
**Screens:** NewProjectView, NewTransactionView, NewItemView, NewSpaceView
**Logic modules:** ProjectFormValidation, TransactionFormValidation, ItemFormValidation, SpaceFormValidation
**Modals/pickers wired (4):** ProjectSelector, SpaceSelector, VendorPicker, MultiSelectPicker (for budget category allocation)
**Components used:** FormSheet, MultiStepFormSheet, FormField, AppButton, MediaGallerySection, CategoryBudgetInput (new or adapted)
**Services used:** ProjectService.create, TransactionsService.create, ItemsService.create, SpacesService.create, ProjectBudgetCategoriesService.set
**Navigation:** Accessible from project detail tabs, inventory screen, and potentially the center "Add" button

### Session 7+: Settings, Universal Search, Reports
**Screens:**
- Settings: SettingsView with 5 tabs (General, Presets, Users, Account) — each as a separate sub-view
- Presets sub-views: BudgetCategoryManagementView, SpaceTemplateManagementView, VendorDefaultsView
- UsersView: member list, invitation management
- AccountView: business profile, sign out
- UniversalSearchView with 3 result tabs
- Reports: InvoiceReportView, ClientSummaryReportView, PropertyManagementReportView
**Logic modules:** SearchCalculations (fuzzy matching, amount-range prefix matching), ReportAggregationCalculations
**Services added (as needed):** BusinessProfileService, SpaceTemplatesService, VendorDefaultsService, InvitesService, AccountPresetsService
**Components used:** ScrollableTabBar, FormField, AppButton, DraggableCardList (for reordering), various existing components

---

## Scope Boundaries

### In Scope
- All screens listed in the session breakdown above
- All 14 modals from the RN modals directory
- All business logic porting (display names, completeness, next steps, filtering/sorting, badges, formatting)
- Light and dark mode on all screens
- Optimistic UI for all write operations
- Unit tests for all pure logic modules

### Out of Scope
- Media upload/download implementation (Firebase Storage integration) — placeholder handling for now
- Amazon/Wayfair invoice import flows
- Paywall/StoreKit 2 subscription management
- Mac Catalyst / macOS layout adaptation (Phase 6)
- PDF generation for reports
- Push notifications
- Deep linking
- Offline queue management (native Firestore SDK handles this)
- Performance optimization beyond standard SwiftUI best practices

---

## Risks

1. **Component integration gaps:** The 45 pre-built components were designed against specs, not real screen flows. Some may need modifications when wired into actual screens. Mitigation: each session validates components against reference screenshots and fixes discrepancies.
2. **Business logic divergence:** Porting RN JavaScript logic to Swift introduces risk of subtle behavior differences (floating point, date parsing, string handling). Mitigation: comprehensive unit tests that mirror the RN test cases.
3. **SharedItemsList known limitation:** The embedded mode copies items into `@State` once during `.task` — parent array updates won't reflect. Mitigation: add `.onChange(of:)` handler during Session 3 integration.
4. **Session 7+ scope creep:** Settings, Search, and Reports span many small screens. Mitigation: these can be split into multiple sessions if needed; the session boundary is flexible.
