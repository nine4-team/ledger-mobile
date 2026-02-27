# Phase 4 Screens Implementation

## Clarifications

### Session 2026-02-26

- Q: Should Universal Search port all three RN matching strategies (text substring, amount prefix-range, normalized SKU) with per-entity field mapping? → A: Yes — port all three strategies exactly, with per-entity field mapping. Improvements welcome but no functionality loss allowed.
- Q: Should the Accounting tab match RN behavior (two reimbursement summary cards + three report navigation buttons)? → A: Yes — the Accounting tab's primary value is the reports. Match RN exactly. Assumption #8 was wrong to defer it.
- Q: How should reports render and share — pure SwiftUI, SwiftUI+PDF, or HTML/WebView like RN? → A: SwiftUI views for on-screen display + PDF generation via ImageRenderer for sharing. Recipients expect PDFs. Simpler than RN's HTML/WebView approach.
- Q: Should image upload (Firebase Storage + PhotosPicker) be in scope for Phase 4 or deferred? → A: In scope. Images are core to nearly every detail screen and creation form. Build shared MediaService early, wire per-session.
- Q: Should all RN item operations be ported (status change, link/unlink transaction, clear space, make copies, bookmark, reassign to inventory, move to return transaction) — not just the bulk operations in the spec? → A: Yes — port all RN item operations exactly. No functionality loss allowed.
- Q: Should reports match the exact RN data structures (invoice charges/credits with net due, client summary with savings/category breakdown, property management grouped by space) or allow redesign? → A: Match the RN report data structures exactly (same computed fields, aggregations, line items). Design improvements to the visual presentation are welcome.
- Q: Should the transaction edit modal include vendor suggestions from the vendor defaults/presets list and a transaction type dropdown (both present in RN but missing from spec)? → A: Yes — include vendor suggestions from presets and transaction type dropdown in the edit modal, matching RN exactly. Source and vendor are the same field (source is the data field, vendor is the UI label).
- Q: Should the spec pin exact transaction completeness thresholds (over >1.2 ratio, complete <=1% variance, near <=20% variance, incomplete otherwise) or leave as implementation detail? → A: Pin exact thresholds in the spec — they're business rules that affect how designers interpret transaction health.

### Session 2026-02-26 (Round 3 — RN Source Audit)

- Audit finding: Projects list sort order is alphabetical by name (case-insensitive), not most-recently-updated as previously stated. Corrected in FR-1.1.
- Audit finding: Project card budget preview — pinned first, then top by spend%, then "Overall Budget" if no category activity. No hard cap on bar count. Corrected in FR-1.3.
- Audit finding: Project kebab menu has 3 items: Edit Project, Export Transactions (CSV via share sheet), Delete Project. Export Transactions was missing from spec. Added to FR-2.5.
- Audit finding: Transaction detail field order in EditTransactionDetailsModal is: Vendor/Source → Amount → Date → Status → Purchased By → Transaction Type → Reimbursement Type → Budget Category → Email Receipt → (conditional) Subtotal → Tax Rate. Spec FR-5.6 had them in wrong order. Corrected.
- Audit finding: Transaction detail section default collapsed states — Receipts=expanded, all others (Other Images, Notes, Details, Items, Returned Items, Sold Items, Audit) collapsed. Added to FR-5.5.
- Audit finding: Transaction detail has a "Moved Items" section (uses lineage edges) showing items moved via inventory operations, rendered dimmed at 50% opacity. Not a collapsible section — always visible when data exists. Missing from spec entirely. Added as FR-5.13.
- Audit finding: Transaction detail has a "Create Items from List" modal (CreateItemsFromListModal) for bulk item creation via receipt text parsing. Two-step: paste text → preview parsed items → create. Missing from spec. Added as FR-5.14 and FR-8.14.
- Audit finding: Transaction detail items section has its own 6-mode sort (alphabetical-asc/desc, price-asc/desc, created-asc/desc) and 6-mode filter (all, bookmarked, no-sku, no-name, no-price, no-image). Added to FR-5.15.
- Audit finding: Item card displays Location label (space name) and budget category name as a pill badge, in addition to previously specified fields. Corrected in FR-6.1.
- Audit finding: Space Detail items section — full 10 project-scope filter modes for parity (overriding RN's 4-mode subset). Added as FR-9.10.
- Audit finding: Space Detail items section includes a full ItemsListControlBar (sort + filter) — not just a plain list. Added to FR-9.3.
- Audit finding: Space Detail section default collapsed states — Media=expanded, Notes=collapsed, Items=collapsed, Checklists=collapsed. Added to FR-9.3.
- Audit finding: Checklist item boolean field — using `isCompleted` as the canonical Swift field name. Key Entities updated.
- Audit finding: SpaceTemplate Firestore model also has `notes`, `isArchived`, and `order` fields beyond name + checklists. `order` is a numeric field used for drag-reorder persistence. Added to FR-12.4.
- Audit finding: "Save as Template" in Space Detail is restricted to owner/admin roles only. Added to FR-9.8.
- Audit finding: Sell-to-project modal shows description text: "Sale and purchase records will be created for financial tracking. If you're just fixing a misallocation, use Reassign instead." Added to FR-8.6.
- Audit finding: Sell-to-business modal shows description text: "This will move items from the project into business inventory. A sale record will be created for financial tracking. If you're just fixing a misallocation, use Reassign instead." Added to FR-8.5.
- Audit finding: Property Management report — grouped by space (design decision, overriding RN flat list). Each item shows: name, source, SKU, market value. "No Space" group for unassigned items. Updated in FR-15.3.
- Audit finding: Client Summary receipt link — 3 states: `invoice`, `receipt-url`, `null`. The RN `pending-upload` offline state is not being ported (RN-only legacy). Updated in FR-15.2.
- Audit finding: Transaction type canonical values and labels: `purchase`→"Purchase", `sale`→"Sale", `return`→"Return", `to-inventory`→"To Inventory". Reimbursement type values: `none`→"None", `owed-to-client`→"Owed to Client", `owed-to-company`→"Owed to Business". Added to FR-5.6 and FR-12.3 area.
- Audit finding: Budget category form validation error messages: name max 100 chars error = "Category name must be 100 characters or less"; mutual exclusivity error = "A category cannot be both Itemized and Fee". Added to FR-12.8.
- Audit finding: Search screen initial state shows centered search icon + "Start typing to search" text; auto-focuses search input on mount. No-results text per tab: "No items found", "No transactions found", "No spaces found". Added to FR-13.
- Audit finding: Empty state text for projects list: "No active projects yet." (active tab), "No archived projects yet." (archived tab). Added to FR-1.5.

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

**Acceptance:** Project list loads from Firestore cache immediately (no spinner), sorted alphabetically by project name. Budget tab shows correct aggregated amounts matching the Firestore data. Active/Archived toggle filters correctly. Empty states display exact text: "No active projects yet." / "No archived projects yet."

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
3. User taps an item to see the full detail screen with hero card (name, quantity, purchase price, project price, market value), media gallery, notes, and detail fields
4. User uses the action menu for single-item operations: change status, set/clear space, set/clear transaction, sell to business, sell to project, reassign to project, reassign to inventory, move to return transaction, make copies, bookmark/unbookmark, delete
5. User long-presses or uses the select button to enter multi-select mode
6. User selects multiple items and uses the bulk action bar to: set space, reassign to another project, sell to business inventory, or sell to another project
7. Sell-to-project flow prompts for destination project and resolves budget categories as needed

**Acceptance:** List filtering and sorting match the RN app's 10 filter modes (project scope) / 7 filter modes (inventory scope) and 4 sort modes. Bulk and single-item operations present appropriate picker modals. Item detail shows all fields in the correct order including market value. Action menu options are contextual to item status (active items have full operations, returned/sold items have limited actions).

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
3. Item search matches on name, source, SKU (with normalized alphanumeric matching), notes, and budget category name; also matches on purchase price, project price, and market value via amount prefix-range
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

- FR-1.1: Display all projects for the active account, sorted alphabetically by project name (case-insensitive; projects with no name sort by ID)
- FR-1.2: Support Active/Archived tab filtering using an underline-style tab bar
- FR-1.3: Each project card shows: hero image (or placeholder), project name, client name, and budget category progress bars. Priority: (1) pinned categories in user-defined order, (2) top categories by spend%, (3) "Overall Budget" row if no category has any activity. No hard cap on the number of bars shown
- FR-1.4: Support text search filtering across project name and client name (case-insensitive)
- FR-1.5: Show appropriate empty state when no projects exist or no results match the search. Exact text: "No active projects yet." (active tab), "No archived projects yet." (archived tab)
- FR-1.6: Navigate to Project Detail on card tap
- FR-1.7: Manage its own Firestore subscription for the project list (independent of ProjectContext which requires a selected project)

### FR-2: Project Detail Hub

- FR-2.1: Display project name and client name in the navigation bar
- FR-2.2: Provide a 5-tab interface (Budget, Items, Transactions, Spaces, Accounting) using a scrollable underline tab bar
- FR-2.3: Activate real-time Firestore subscriptions (transactions, items, spaces, budget categories, budget progress) when the project is entered
- FR-2.4: Clean up all subscriptions when leaving the project detail
- FR-2.5: Provide a kebab menu with 3 project actions: "Edit Project" (navigates to edit form), "Export Transactions" (generates CSV of all project transactions and shares via system share sheet), "Delete Project" (destructive confirmation)

### FR-3: Budget Tab

- FR-3.1: Display each enabled budget category with: category name, spent amount label, remaining/over amount label (color-coded), and a progress bar
- FR-3.2: Filter to only enabled categories (non-zero budget or non-zero spend)
- FR-3.3: Sort categories with fee categories last, then alphabetically
- FR-3.4: Display an "Overall Budget" summary row with aggregate totals — categories with `excludeFromOverallBudget` flag are excluded from the overall row but still displayed individually
- FR-3.5: Show "received" instead of "spent" for fee-type categories
- FR-3.6: Color over-budget amounts in the overflow status color
- FR-3.7: Support pinned budget categories (from ProjectPreferences) — pinned categories appear at the top of the list
- FR-3.8: Budget spend normalization rules: canceled transactions contribute $0; returns subtract from spent (negative amount); canonical inventory sales use direction-based sign (project_to_business subtracts, business_to_project adds); all other transactions add to spent. Per-category spending always includes all transactions; overall spending excludes categories with `excludeFromOverallBudget` flag

### FR-4: Transactions Tab

- FR-4.1: Display transaction cards sorted by date descending (newest first), with nil dates sorted last
- FR-4.2: Each transaction card shows: badge row (type, reimbursement, receipt, needs-review, category), source/display name, formatted amount, date with item count, and truncated notes (italic, 2-line limit)
- FR-4.3: Badge colors follow the established mapping: Purchase (green), Sale (blue), Return (red), To Inventory (brand primary), Owed to Client/Business (amber), Receipt (primary), Needs Review (rust), Category (primary)
- FR-4.4: Support text search across source, notes, transaction type, and formatted amount
- FR-4.5: Provide toolbar with search, sort, filter, and add action pills
- FR-4.5a: 8 filter dimensions: status (pending/completed/canceled/inventory-only), reimbursement (we-owe/client-owes), receipt (yes/no), type (purchase/return), completeness (needs-review/complete), budget category (dynamic from project categories), purchased by (client-card/design-business/missing), source (dynamic from unique transaction sources)
- FR-4.5b: 8 sort modes: date (asc/desc), created (asc/desc), source (asc/desc), amount (asc/desc). Default: date-desc
- FR-4.6: Display name follows priority: source → canonical inventory sale label → ID prefix (6 chars) → "Untitled Transaction"
- FR-4.7: Navigate to Transaction Detail on card tap

### FR-5: Transaction Detail Screen

- FR-5.1: Display hero card with transaction display name, formatted amount, and formatted date
- FR-5.2: Display "Next Steps" card with progress ring showing completion fraction, incomplete steps first with chevrons, completed steps with strikethrough and gold checkmark
- FR-5.3: Next Steps computes 5 or 6 steps: categorize, enter amount, add receipt, add items, set purchased by, and conditionally set tax rate (only for itemized budget categories)
- FR-5.4: Next Steps card is hidden entirely when all steps are complete
- FR-5.5: Display collapsible sections in order: Receipts (expanded by default), Other Images (collapsed), Notes (collapsed), Details (collapsed), Items (collapsed), Returned Items (conditional, collapsed), Sold Items (conditional, collapsed), Moved Items (conditional, not collapsible — see FR-5.13), Transaction Audit (conditional, collapsed)
- FR-5.6: Details section shows fields in exact order: Vendor/Source (with suggestions from vendor defaults presets), Amount, Date, Status, Purchased By, Transaction Type, Reimbursement Type, Budget Category, Email Receipt — then conditionally: Subtotal, Tax Rate (%) (only for itemized categories). Tax Amount is computed on display (Amount − Subtotal) and shown as a derived read-only field. Transaction Type values: `purchase`→"Purchase", `sale`→"Sale", `return`→"Return", `to-inventory`→"To Inventory". Reimbursement Type values: `none`→"None", `owed-to-client`→"Owed to Client", `owed-to-company`→"Owed to Business". Email Receipt values: `true`→"Yes", `false`→"No". Missing values display as "—"
- FR-5.7: Transaction Audit section computes completeness based on item prices vs. transaction subtotal. Ratio = itemsNetTotalCents / transactionSubtotalCents. Exact thresholds (check in order): `over` if ratio > 1.2; `complete` if |variance%| <= 1%; `near` if |variance%| <= 20%; `incomplete` otherwise. Variance = (itemsNetTotal − subtotal) / subtotal × 100. Returns null if no valid subtotal exists. Tracks returned items and sold items separately but includes them in total
- FR-5.8: Returned Items and Sold Items sections only appear when items with those statuses exist
- FR-5.9: Provide edit functionality for notes, details, and media via separate bottom sheet modals (one modal per section)
- FR-5.10: Subtotal resolution follows priority: explicit subtotal → inferred from amount and tax rate → fallback to amount (with missing-tax-data flag)
- FR-5.11: Handle `isCanceled` flag on transactions — canceled transactions are excluded from budget calculations and reimbursement totals but still visible in transaction lists (filterable by "Canceled" status). This flag is set by server-side processes, not a user-facing action
- FR-5.12: Support delete transaction with confirmation dialog (hard delete, removes from Firestore)
- FR-5.13: Moved Items section — when a transaction has lineage edges (items moved in/out via inventory operations), display those items as a non-collapsible ItemCard list at 50% opacity below the Sold Items section. This section has no title/header and appears only when lineage edges exist
- FR-5.14: Transaction detail provides a "Create Items from List" action (accessible from the items section add menu) that opens CreateItemsFromListModal. Two-step flow: (1) paste free-form receipt text, (2) preview parsed items (name + price per line) with skipped-lines disclosure, then create all parsed items linked to the transaction. Uses `receiptListParser` utility
- FR-5.15: Items section within Transaction Detail has its own sort and filter controls. 6 sort modes: alphabetical-asc, alphabetical-desc, price-asc, price-desc, created-asc, created-desc. 6 filter modes: all, bookmarked, no-sku, no-name, no-price, no-image

### FR-6: Items Tab

- FR-6.1: Display item cards with: thumbnail image (108×108 or camera-icon placeholder), name (3 lines max), source label, SKU label, Location label (space name if assigned), price (project price if set, otherwise purchase price), budget category name pill badge, status pill badge (with dropdown arrow when tappable). All pill badges use brand primary color. Bookmark toggle and context menu button also visible per card
- FR-6.2: Support item filter modes — Project scope (10 modes): all, bookmarked, from-inventory, to-return, returned, no-sku, no-name, no-project-price, no-image, no-transaction. Inventory scope (7 modes): all, bookmarked, no-sku, no-name, no-project-price, no-image, no-transaction. Supports multi-select filtering (multiple modes active simultaneously)
- FR-6.3: Support 4 sort modes: created-desc (default), created-asc, alphabetical-asc, alphabetical-desc
- FR-6.3a: Duplicate grouping — items with matching name+SKU+source (case-insensitive) are automatically grouped into expandable group rows showing the group label and item count. This is default list behavior, not a filter toggle
- FR-6.4: Support text search across name, source, SKU, and notes
- FR-6.5: Support multi-select mode with bulk action bar. Bulk menu mirrors single-item operations: change status (submenu with 4 statuses), transaction (set/clear/move-to-return), space (set/clear), sell (to business/to project — scope-dependent), reassign (to inventory/to project — scope-dependent), delete. Bulk reassign filters out items with `transactionId` (must unlink first)
- FR-6.6: Navigate to Item Detail on card tap
- FR-6.7: Single-item operations available from item detail action menu: change status, set/clear space, set/clear transaction, sell to business, sell to project, reassign to project, reassign to inventory (no financial record), move to return transaction, make copies, bookmark/unbookmark, delete

### FR-7: Item Detail Screen

- FR-7.1: Display hero card with item name, quantity, purchase price, project price, and market value
- FR-7.2: Display collapsible sections: Media gallery, Notes, Details (status, space, source, SKU, purchase price, project price, market value, dates)
- FR-7.3: Provide contextual action menu based on item status with all operations: change status, set/clear space, set/clear transaction, sell to business, sell to project, reassign to project, reassign to inventory (no financial record), move to return transaction, make copies, bookmark/unbookmark, delete. Active items have full operations; returned/sold items have limited actions
- FR-7.4: Support editing notes, details, and media via separate bottom sheet modals (one modal per section)
- FR-7.5: Support delete with confirmation dialog
- FR-7.6: Support bookmark/unbookmark toggle for quick item flagging

### FR-8: Item Modals (13 modals wired during Items session)

- FR-8.1: EditItemDetailsModal — edit item fields (name, source, SKU, purchase price, project price, market value) via bottom sheet form. Field order: Name, Source, SKU, Purchase Price, Project Price, Market Value
- FR-8.2: EditNotesModal — edit free-text notes field via bottom sheet
- FR-8.3: SetSpaceModal — assign item to a space using space picker (project-scoped)
- FR-8.4: ReassignToProjectModal — move item to a different project using project picker
- FR-8.5: SellToBusinessModal — confirm sell-to-business with optional source category picker (shown when item has no budget category). Shows description text: "This will move items from the project into business inventory. A sale record will be created for financial tracking. If you're just fixing a misallocation, use Reassign instead."
- FR-8.6: SellToProjectModal — confirm sell-to-project with: (1) destination project picker, (2) optional destination budget category picker, (3) optional source budget category picker (for uncategorized items). Shows description text: "Sale and purchase records will be created for financial tracking. If you're just fixing a misallocation, use Reassign instead."
- FR-8.7: TransactionPickerModal — select transaction to link item(s) to
- FR-8.8: ReturnTransactionPickerModal — select return transaction with filtering for incomplete returns
- FR-8.9: CategoryPickerList — single-select budget category picker
- FR-8.10: SpacePickerList — single-select space picker with optional create-new
- FR-8.11: ProjectPickerList — single-select project picker (used by ReassignToProjectModal and SellToProjectModal)
- FR-8.12: MakeCopiesModal — specify number of copies to create of an item
- FR-8.13: StatusPickerModal — select new item status from the 4 canonical statuses (to purchase, purchased, to return, returned)
- FR-8.14: CreateItemsFromListModal — two-step bulk item creation from receipt text: (1) paste text input, (2) preview parsed items (name + optional price extracted per line) with disclosure of skipped lines, then create all items linked to the current transaction. Used from within Transaction Detail items section

### FR-9: Spaces Tab and Space Detail

- FR-9.1: Display space cards with names, item counts, and checklist completion progress
- FR-9.2: Navigate to Space Detail on card tap
- FR-9.3: Space Detail shows 4 collapsible sections in order: Media/Images (expanded by default), Notes (collapsed), Items (collapsed, includes full ItemsListControlBar with sort and full 10 project-scope filter modes matching FR-6.2), Checklists (collapsed)
- FR-9.4: Checklist editing via EditChecklistModal — add/remove/reorder/check items
- FR-9.5: Space details editing via EditSpaceDetailsModal
- FR-9.6: Support creating new spaces from the tab
- FR-9.7: Show items assigned to each space
- FR-9.8: Support "Save as Template" action from Space Detail — restricted to owner/admin roles only. Creates a reusable SpaceTemplate from the current space's name, notes, and checklists
- FR-9.10: Items section within Space Detail uses the full 10 project-scope filter modes (matching FR-6.2), providing full filter parity with the project Items tab
- FR-9.9: Support delete space with confirmation dialog

### FR-10: Inventory Screen

- FR-10.1: Display 3 sub-tabs (Items, Transactions, Spaces) scoped to business inventory
- FR-10.2: Items and Transactions tabs reuse the same list components as project-scoped versions, but filtered to business-owned entities only
- FR-10.3: Spaces tab shows business inventory storage locations with add/edit capability
- FR-10.4: Persist the last-selected tab across app sessions
- FR-10.5: Support all filtering, sorting, and bulk operations available in project-scoped lists

### FR-11: Creation Flows

- FR-11.1: New Project form with: name (required), client name (required), description, main image upload, and per-category budget allocation
- FR-11.2: New Transaction form with progressive disclosure: type → destination/channel → detail fields. Fields include: source, date, amount, status, purchased by, reimbursement type, notes, category, email receipt flag, and conditional tax fields
- FR-11.3: New Item form with: name, source, SKU, status, purchase price, project price, market value, quantity, space selection, transaction association (optional — via TransactionPickerModal), image upload. Budget category is inherited from the associated transaction, not set directly
- FR-11.4: New Space form with: name, notes, optional checklist template selection
- FR-11.5: All forms validate required fields before submission
- FR-11.6: All forms navigate back to the originating list after successful creation with optimistic UI (new entity visible immediately)
- FR-11.7: Creation flows are accessible from both project-scoped and inventory-scoped contexts where applicable

### FR-12: Settings Screen

- FR-12.1: General tab with theme selection (light/dark/system) and account info display
- FR-12.2: Presets tab with sub-tabs for Budget Categories, Space Templates, and Vendors
- FR-12.3: Budget Categories: full CRUD, drag-reorder, archive/unarchive (with warning if transactions exist using category), default category picker. Each category has name, type (general/itemized/fee — mutually exclusive), and `excludeFromOverallBudget` toggle. CategoryFormModal handles create and edit
- FR-12.4: Space Templates: full CRUD, reorder. Template Firestore fields: `name`, `notes` (optional), `checklists` (array of Checklist objects), `isArchived`, `order` (numeric, used for drag-reorder persistence). Templates with `isArchived=true` are hidden from pickers but preserved
- FR-12.5: Vendors: manage variable-length vendor list for transaction form autofill. Pre-populated with common stores (e.g., Home Depot, Wayfair, West Elm, Pottery Barn, etc.). Users can add/remove/reorder vendors
- FR-12.6: Users tab: display team members with roles, show pending invitations, create new invitations with role selection
- FR-12.7: Account tab: business profile editing (name, logo), create new account, sign out (clears all local state)
- FR-12.8: CategoryFormModal — create/edit budget category form with: name (required, max 100 chars), isItemized toggle, isFee toggle (mutually exclusive with isItemized), excludeFromOverallBudget toggle. Button label: "Create" (new) or "Save" (edit). Exact validation error messages: "Category name must be 100 characters or less"; "A category cannot be both Itemized and Fee". Used from BudgetCategoryManagement view

### FR-13: Universal Search Screen

- FR-13.1: Display search bar with real-time debounced input (~400ms). Auto-focus search input on screen mount. Initial state (before typing): show centered search icon + text "Start typing to search". No-results state per tab: "No items found", "No transactions found", "No spaces found"
- FR-13.2: Three result tabs: Items, Transactions, Spaces
- FR-13.3: Three matching strategies applied per entity: (1) case-insensitive text substring matching, (2) amount prefix-range matching (typing "40" matches $40.00–$40.99, "40.0" matches $40.00–$40.09, handles $ symbols and commas), (3) normalized SKU matching (strip all non-alphanumeric chars so "ABC-123" matches "abc123")
- FR-13.4: Item search fields — text: name, source, SKU (exact + normalized), notes, budget category name; amount: purchasePrice, projectPrice, marketValue
- FR-13.5: Transaction search fields — text: display name (with canonical inventory sale handling), transactionType, notes, purchasedBy, budget category name; amount: amountCents
- FR-13.6: Space search fields — text: name, notes; no amount matching
- FR-13.7: Navigate to the appropriate detail screen on result tap
- FR-13.8: Show result counts per tab

### FR-14: Accounting Tab

- FR-14.1: Display two reimbursement summary cards computed from all non-canceled transactions: "Owed to Design Business" (sum of OWED_TO_COMPANY reimbursements) and "Owed to Client" (sum of OWED_TO_CLIENT reimbursements)
- FR-14.2: Display three report navigation buttons: Property Management Summary, Client Summary, and Invoice
- FR-14.3: Tapping a report button navigates to the corresponding report view
- FR-14.4: Skip canceled transactions when computing reimbursement totals

### FR-15: Reports

- FR-15.1: **Invoice Report** — Separates transactions into Charge Lines (reimbursementType=owed-to-company) and Credit Lines (reimbursementType=owed-to-client). Excludes canceled transactions. Each line shows: transaction display name, date, notes, amount, budget category, and linked items with project prices. Computes charges subtotal, credits subtotal, and net amount due (charges − credits). Flags items with missing project prices
- FR-15.2: **Client Summary Report** — Shows: total spent (sum of item project prices), total market value (sum of item market values), total saved (sum of `marketValue − projectPrice` per item where marketValue > 0), per-category spending breakdown sorted alphabetically by category name (category resolved from item.budgetCategoryId or item's transaction.budgetCategoryId), and per-item list with: name, source, space name, project price, receipt link. Receipt link has 3 states: `{type:'invoice'}` (canonical inventory sale or invoiceable reimbursement transaction), `{type:'receipt-url';url:string}` (transaction has a receipt image URL), `null` (no receipt)
- FR-15.3: **Property Management Report** — Groups items by space. Each space section shows the space name and its items. Each item row shows: name, source, SKU, market value. Items without a space assignment are grouped under a "No Space" section. Summary shows total item count and total market value
- FR-15.4: All reports render as native SwiftUI scrollable views (no WebView/HTML)
- FR-15.5: Reports support sharing via the system share sheet as PDF, generated from the SwiftUI view using `ImageRenderer`

### FR-16: Cross-Cutting Requirements

- FR-16.1: All screens work in both light and dark mode using the existing adaptive color system
- FR-16.2: All data loads from Firestore cache first (no blocking spinners) per the offline-first principles
- FR-16.3: All write operations are optimistic — UI updates immediately without waiting for server confirmation
- FR-16.4: All modals present as bottom sheets with `.presentationDetents()` and `.presentationDragIndicator(.visible)`
- FR-16.5: All business logic is extracted into pure function modules with comprehensive test coverage
- FR-16.6: Destructive actions (delete) require confirmation via `.confirmationDialog()`
- FR-16.7: Navigation uses `NavigationLink(value:)` with `.navigationDestination(for:)` — never deprecated label-based NavigationLink
- FR-16.8: Shared MediaService provides Firebase Storage upload (via `putData()`), download URL resolution, and delete operations. Image picking uses SwiftUI `PhotosPicker` (iOS 16+). Wired into `MediaGallerySection`'s existing add/remove/set-primary actions
- FR-16.9: Image upload supports transactions (receiptImages, otherImages), items (images), spaces (images, max 50), and project hero images

---

## Key Entities

### Project
The primary organizing entity. Contains name, client name, description, main image, budget allocations, and serves as the parent for transactions, items, and spaces.

### Transaction
A financial event (purchase, sale, return, or inventory transfer). Contains source/vendor, amount, date, type, budget category, tax fields, receipt references, linked items, `needsReview` flag (displayed as a "Needs Review" badge), and `isCanceled` flag (logical delete — preserves transaction for report history but excludes from budget calculations). Canonical inventory sale transactions are identified by `isCanonicalInventorySale` flag, `inventorySaleDirection` field, or `SALE_` ID prefix.

### Item
A physical inventory item tracked through the procurement lifecycle. Contains name, source, SKU, status (to purchase/purchased/to return/returned), purchase price, project price, market value, quantity, space assignment, bookmark flag, and media. `budgetCategoryId` is inherited from the associated transaction, not set directly on items.

### Space
A physical location (room, storage area, staging zone). Contains name, notes, checklists, and serves as a container for items. Exists in both project scope and business inventory scope. Each `Checklist` has: `id`, `title`, `items[]`. Each checklist item has: `id`, `text`, `isCompleted` (boolean).

### BudgetCategory
An account-level budget classification (e.g., "Furnishings", "Lighting", "Design Fees"). Has type (general/itemized/fee), an `excludeFromOverallBudget` flag (categories with this flag are tracked individually but excluded from the overall budget aggregation), and is allocated per-project with dollar amounts. Types are mutually exclusive: a category is either general, itemized, or fee.

### ProjectPreferences
Per-user, per-project preferences. Contains `pinnedBudgetCategoryIds` — categories the user has pinned to the top of the budget tab. Auto-pins "Furnishings" category if it exists and is enabled.

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
3. Media upload/download via Firebase Storage is in scope. A shared MediaService (Firebase Storage upload + SwiftUI PhotosPicker) is built early and wired into each screen's session as detail/creation screens are implemented
4. Import flows (Amazon/Wayfair invoice parsing) are deferred to a later phase
5. Paywall/StoreKit 2 subscription management is deferred to a later phase
6. Mac Catalyst / macOS adaptation is deferred to Phase 6
7. Reports render as native SwiftUI views on-screen and generate PDF via `ImageRenderer` for sharing — no WebView or HTML generation needed
8. The "Accounting" tab in Project Detail displays two reimbursement summary cards and three report navigation buttons (Property Management, Client Summary, Invoice), matching the RN implementation exactly
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
**Export Transactions CSV:** Session 1 also implements the kebab menu "Export Transactions" action. CSV columns: id, date, source, amount, categoryName, budgetCategoryId, inventorySaleDirection, itemCategories (pipe-separated category IDs of linked items). Shared via system share sheet

### Session 2: Transactions Tab + Transaction Detail
**Screens:** TransactionsTabView (replaces placeholder), TransactionDetailView
**Logic modules:** TransactionDisplayCalculations (display name, formatting, badges), TransactionNextStepsCalculations (5-6 step checklist), TransactionCompletenessCalculations (audit), TransactionListCalculations (filter/sort)
**Modals wired:** EditTransactionDetailsModal, EditNotesModal, CategoryPickerList
**Components used:** TransactionCard, ProgressRing, ListToolbar, CollapsibleSection, Badge, DetailRow, ProgressBar
**Navigation:** Transactions tab content → NavigationLink to TransactionDetail

### Session 3: Items Tab + Item Detail + Modals
**Screens:** ItemsTabView (replaces placeholder), ItemDetailView
**Logic modules:** ItemListCalculations (10 filter modes, 4 sort modes, search, duplicate grouping), ItemDetailCalculations (display logic, action menu generation), BulkSaleResolutionCalculations (category resolution for sell operations)
**Modals wired (13):** EditItemDetailsModal, EditNotesModal, SetSpaceModal, ReassignToProjectModal, SellToBusinessModal, SellToProjectModal, TransactionPickerModal, ReturnTransactionPickerModal, CategoryPickerList, SpacePickerList, ProjectPickerList, MakeCopiesModal, StatusPickerModal
**Transaction Detail modals also wired (Session 2):** CreateItemsFromListModal (FR-8.14) — add to Session 2 scope
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
- All 16+ modals from the RN modals directory (13 item-related + CreateItemsFromListModal + CategoryFormModal + space/transaction edit modals)
- All business logic porting (display names, completeness, next steps, filtering/sorting, badges, formatting)
- Light and dark mode on all screens
- Optimistic UI for all write operations
- Unit tests for all pure logic modules
- Media upload/download via Firebase Storage — shared MediaService built early, wired into detail screens and creation forms per session
- Image display from remote URLs via existing AsyncImage components

### Out of Scope
- Amazon/Wayfair invoice import flows
- Paywall/StoreKit 2 subscription management
- Mac Catalyst / macOS layout adaptation (Phase 6)
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
