# SwiftUI Migration - Master Plan

## Goal

Replace the React Native (Expo) mobile app with a native SwiftUI codebase that targets both iOS and macOS from a single Xcode project. Start with iOS, then add Mac Catalyst / macOS target.

## Strategy

**Build iOS first, then add macOS.** iOS is the primary platform and the direct replacement for the RN app. Once iOS reaches feature parity, macOS (Mac Catalyst or native SwiftUI for Mac) is an additive layer — sidebars, keyboard navigation, and window management layered on top of the working iOS codebase. Both targets share ~80-90% of code.

**Run both apps in parallel.** Keep the RN app working until the SwiftUI iOS version reaches feature parity. No big-bang cutover.

## UI Fidelity

Dark mode screenshots are the single source of truth for visual parity. Light mode is inferred from the theme system — layout, spacing, and structure are identical; only colors change. Screenshots stored in `reference/screenshots/dark/`.

---

## Phase 0: Reference Capture

Dark mode screenshots are the source of truth. Light mode is inferred from the theme system (colors, surfaces, borders flip; layout and spacing stay the same).

Screenshots captured in `reference/screenshots/dark/`:

- [x] Projects list (active + archived)
- [x] Project detail (budget, transactions, items, spaces tabs)
- [x] Transaction detail (+ scrolled)
- [x] Item detail (+ scrolled)
- [x] Space detail (2 views)
- [x] Settings presets (budget categories, vendors)
- [x] Bottom sheet menu
- [ ] New Project form
- [ ] New Transaction wizard
- [ ] New Item form
- [ ] New Space form
- [ ] Inventory screen (3-tab view)
- [ ] Universal Search
- [ ] Settings screens (general, users, account)

Still needed (not screenshot-dependent):

- [x] Document the color system (brand color `#987e55`, dark mode palette, status colors) — `Theme/BrandColors.swift`, `Theme/StatusColors.swift`, asset catalog colorsets
- [x] Document the typography scale (h1, h2/title, body, caption sizes and weights) — `Theme/Typography.swift`
- [x] Document spacing constants (card padding, section gaps, screen padding) — `Theme/Spacing.swift`, `Theme/Dimensions.swift`

---

## Phase 1: Xcode Project + Firebase Foundation

**Objective:** Xcode project builds, connects to Firestore, authenticates a user.

- [x] Create `LedgeriOS/` directory with Xcode project (iOS target first; macOS target added in Phase 6)
- [x] Add Firebase Swift SDK via SPM (Auth, Firestore, Storage) — firebase-ios-sdk 11.15.0
- [x] Register iOS app in Firebase Console, download `GoogleService-Info.plist` — copied from existing RN project
- [x] Implement Firebase initialization — `FirebaseApp.configure()` in `LedgerApp.init()`, `GIDSignIn` configured same place
- [x] Implement sign-in / sign-up screens — email/password + Google Sign-In (`GoogleSignIn-iOS` via SPM, `AuthManager` @Observable/@MainActor)
- [x] User successfully authenticated and navigated the tab bar (verified manually)
- [x] Verify Firestore reads work — `FirestoreTestView` confirms account read from production Firestore (verified manually)
- [x] Verify offline persistence works out of the box — cache-source read confirmed after server fetch (verified manually)
- [x] Seed production Firestore — account doc + owner membership doc created via firebase-admin; `health/ping` created

**Deliverable:** ✅ Complete — app launches, user signs in, reads account from Firestore, cache read confirmed offline.

---

## Phase 2: Swift Data Models + Service Layer

**Objective:** All Firestore entities are modeled in Swift with full CRUD + real-time subscriptions.

### Models (Swift structs, Codable)

Core models (implemented):

- [x] `Account`
- [x] `Project` + `ProjectBudgetSummary` + `BudgetSummaryCategory`
- [x] `Transaction` (~24 fields)
- [x] `Item` (greenfield — uses `name`, no legacy `description`)
- [x] `Space` + `Checklist` + `ChecklistItem`
- [x] `BudgetCategory` + `BudgetCategoryType` enum
- [x] `ProjectBudgetCategory`
- [x] `AccountMember`
- [x] `AttachmentRef` + `AttachmentKind` enum
- [x] `BudgetProgress` (pure computation struct)
- [x] Shared enums: `MemberRole`, `InventorySaleDirection`

Deferred (added when their screens need them):

- [ ] `ItemLineageEdge` — service exists (`LineageEdgesService.swift`), model file not confirmed
- [x] `Invite`
- [x] `BusinessProfile`
- [x] `SpaceTemplate`
- [x] `VendorDefaults`
- [x] `ProjectPreferences`
- [ ] `AccountPresets` — service exists, model file not confirmed
- [ ] `RequestDoc<T>` (generic) — likely not needed

### Service Layer

Core services (implemented):

- [x] Generic `FirestoreRepository<T>` with subscribe/list/get/create/update/delete
- [x] `RepositoryProtocol` (for mock testing)
- [x] `AccountsService`
- [x] `ProjectService`
- [x] `TransactionsService`
- [x] `ItemsService`
- [x] `SpacesService`
- [x] `BudgetCategoriesService`
- [x] `ProjectBudgetCategoriesService`
- [x] `BudgetProgressService` (pure aggregation logic)
- [x] `AccountMembersService`

Deferred (added when their screens need them):

- [x] `LineageEdgesService`
- [x] `InvitesService`
- [x] `BusinessProfileService`
- [x] `SpaceTemplatesService`
- [x] `VendorDefaultsService`
- [x] `ProjectPreferencesService`
- [x] `AccountPresetsService`
- [ ] `RequestDocsService` — likely not needed
- [x] `InventoryOperationsService`
- [ ] `ReturnFlowService` — return flow handled via modals (ReturnTransactionPickerModal, SellToBusinessModal)

### State Management

Replace Zustand stores with `@Observable` classes:

- [x] `AuthStore` → `AuthManager` (@Observable) — Phase 1
- [x] `AccountContextStore` → `AccountContext` (@Observable)
- [x] `ProjectContextStore` → `ProjectContext` (@Observable)
- [x] `SyncTracking` protocol + `NoOpSyncTracker` stub
- [x] `InventoryContext` (@Observable) — added, not in original plan
- [ ] `SyncStatusStore` → `SyncStatus` (@Observable)
- [ ] `BillingStore` → `BillingManager` (@Observable) — RevenueCat Swift SDK (`revenuecat/purchases-ios` via SPM), native SwiftUI paywalls via `RevenueCatUI`, server-side receipt validation, analytics
- [ ] `ListStateStore` → `ListStateManager` (@Observable)
- [ ] `MediaStore` → `MediaManager` (@Observable)

**Deliverable:** All entities can be fetched, subscribed to, created, updated, deleted from Swift. Full test coverage on the service layer.

---

## Phase 3: Navigation Shell

**Objective:** App has the correct navigation structure with empty placeholder screens.

### iOS Layout (primary)
- [x] Tab bar (same 4 tabs as current app: Projects, Inventory, Search, Settings)
- [x] Navigation stack per tab
- [x] "Add" button (floating or tab-center)

### macOS Layout (add in Phase 6)
- Sidebar navigation, window toolbar, keyboard shortcuts

### Shared
- [x] Account selection flow
- [x] Auth gate (show sign-in if not authenticated)
- [x] Router/coordinator pattern for navigation

**Deliverable:** ✅ Complete — tabs, auth gate, account selection, nav shell all in place.

---

## Phase 4: Screens

### Priority 1 — Core Loop
- [x] **Projects List** — active/archived tabs, project cards with budget summaries
- [x] **Project Detail (Hub)** — 4-tab interface (budget, transactions, items, spaces)
- [x] **Transaction List** — embedded in project hub
- [x] **Transaction Detail** — hero card, details, receipts, images, items, audit trail
- [x] **Item List** — embedded in project hub, search/sort/filter/bulk select
- [x] **Item Detail** — hero card, media, notes, details

### Priority 2 — Creation Flows
- [x] **New Project** — form with budget category allocation, main image
- [x] **New Transaction** — progressive disclosure wizard (type → destination → channel → details)
- [x] **New Item** — form with SKU, source, price, status, media

### Priority 3 — Spaces & Inventory
- [x] **Spaces List** — project spaces and business inventory spaces
- [x] **Space Detail** — checklists, media, notes
- [x] **New Space** — form with template selection
- [x] **Inventory Screen** — 3-tab view (transactions, items, spaces)

### Priority 4 — Budget & Reports
- [x] **Project Budget** — category-based budget management, progress visualization
- [x] **Invoice Report**
- [x] **Client Summary Report**
- [x] **Property Management Report**
- [x] **Accounting Tab** — added (`AccountingTabView.swift`), not in original plan

### Priority 5 — Settings & Admin
- [x] **Settings: General** — appearance, defaults
- [x] **Settings: Budget Categories** — CRUD, reorder
- [x] **Settings: Space Templates** — CRUD, reorder
- [x] **Settings: Vendors** — default vendor list
- [x] **Settings: Users** — invite management, member roles
- [x] **Settings: Account** — business profile

### Priority 6 — Search & Polish
- [x] **Universal Search** — cross-entity search with tabs
- [ ] **Import flows** (Amazon, Wayfair)
- [ ] **Paywall / subscription** — RevenueCat Swift SDK (`PaywallView`/`PaywallFooterView` from `RevenueCatUI`), server-side validation, entitlement checks throughout app

**Deliverable per screen:** Visually matches reference screenshots, all data operations work, light + dark mode correct.

---

## Phase 5: Shared Components Library

Full component parity audit: `.plans/component-parity-audit.md`
Component library spec: `kitty-specs/007-swiftui-component-library/spec.md`

### Phase 5a — Simple (complete)
Pure UI components, no data dependencies. All built.

- [x] `Card`, `TitledCard`, `Badge`, `DetailRow`, `ProgressBar`
- [x] `SelectorCircle`, `AppButton`, `FormField`, `SegmentedControl`
- [x] `CollapsibleSection`, `BudgetProgressView`
- [x] `ScrollableTabBar`, `ProjectCard`

### Phase 5b — Component Library (Tiers 1–4, ~45 components) ✅
Tracked in `kitty-specs/007-swiftui-component-library/`. Merged to main.

- [x] **Tier 1** (16): ImageCard, SpaceCard, BudgetCategoryTracker, BudgetProgressPreview, FormSheet, MultiStepFormSheet, CategoryRow, BulkSelectionBar, ListStateControls, ThumbnailGrid, ImageGallery, StatusBanner, ErrorRetryView, LoadingScreen, DraggableCard, InfoCard
- [x] **Tier 2** (4): ActionMenuSheet, BudgetProgressDisplay, ListControlBar, ItemCard
- [x] **Tier 3** (8): TransactionCard, GroupedItemCard, MediaGallerySection, ItemsListControlBar, FilterMenu, SortMenu, ListSelectAllRow, ListSelectionInfo
- [x] **Tier 4** (3): SharedItemsList, SharedTransactionsList, DraggableCardList
  - **Known limitation:** SharedItemsList embedded mode copies items into `@State` once during `.task`. If the parent updates its items array, the list won't reflect changes. Add `.onChange(of:)` handler when wiring embedded mode to parent views during Phase 4 integration.

### Phase 5c — Feature Modals (Tier 5, built with screens)
These are tightly coupled to specific screens. Built during their respective Phase 4 session, not as standalone components.

- [x] EditItemDetailsModal (Session 3: Items)
- [x] EditTransactionDetailsModal (Session 2: Transactions)
- [x] EditSpaceDetailsModal (Session 4: Spaces)
- [x] EditNotesModal (Sessions 2–4)
- [x] EditChecklistModal (Session 4: Spaces)
- [x] SetSpaceModal (Session 3: Items)
- [x] ReassignToProjectModal (Session 3: Items)
- [x] SellToProjectModal (Session 3: Items)
- [x] SellToBusinessModal (Session 3: Items)
- [x] TransactionPickerModal (Session 3: Items)
- [x] ReturnTransactionPickerModal (Session 3: Items)
- [x] ProjectPickerList (Sessions 3/5: Items/Inventory)
- [x] CategoryPickerList (Session 2: Transactions)
- [x] SpacePickerList (Session 3: Items)
- [x] ProjectSelector — built as `ProjectPickerList`; used in `ReassignToProjectModal` and `SellToProjectModal` for reassignment flows (not creation flows, which have project context via `ProjectContext`)
- [x] SpaceSelector — built as `SpacePickerList` + `SetSpaceModal`; covers item → space assignment (`NewItemView`, `ItemDetailView`). Other flows may need it when built.
- [x] VendorPicker — built as `VendorPickerField` (inline component). Shows scrollable preset list with radio-button selection + "Other" free-text fallback. Subscribes to `VendorDefaults` via real-time listener. Integrated into `NewItemView`, `EditItemDetailsModal`, and `NewTransactionView` (Steps 2 & 3).
- [x] MultiSelectPicker — not needed; RN component only used in single-select mode; all single-select picker use cases covered by dedicated components (`CategoryPickerList`, etc.)
- [x] StatusPickerModal — added, not in original plan
- [x] CreateItemsFromListModal — added, not in original plan
- [x] MakeCopiesModal — added, not in original plan

---

## Phase 6: macOS Target + Layout Adaptation

- [ ] Add macOS target to existing Xcode project (Mac Catalyst or native SwiftUI for Mac)
- [ ] Register Mac app in Firebase Console, add `GoogleService-Info.plist` for Mac target
- [ ] `NavigationSplitView` sidebar for Mac (collapses to stack on iPhone, already working)
- [ ] Window toolbar with account selector
- [ ] Keyboard shortcuts (Cmd+N for new, Cmd+F for search, etc.)
- [ ] Adapt card layouts for wider screens
- [ ] Test on Mac (various window sizes), iPad (sidebar collapse), iPhone SE + 15 Pro Max
- [ ] Ensure all screens work at all sizes

---

## Phase 7: Migration & Retirement

- [ ] Feature parity checklist (every RN screen has a SwiftUI equivalent)
- [ ] Data migration verification (same Firestore, no data migration needed)
- [ ] Beta test SwiftUI iOS alongside RN app
- [ ] Submit SwiftUI app to App Store
- [ ] Archive React Native codebase

---

## Billing & Subscriptions

Use the **RevenueCat Swift SDK** — not StoreKit 2 directly, not the RN/JS SDK.

- Native SwiftUI paywalls via `RevenueCatUI` (`PaywallView`, `PaywallFooterView`)
- Server-side receipt validation (RevenueCat handles this — no client-side validation code)
- Purchase analytics and entitlement management via RevenueCat dashboard
- `BillingManager` (@Observable, @MainActor) wraps `Purchases` shared instance
- Add `revenuecat/purchases-ios` via SPM when billing screen is built (Phase 4 Session 7+)

Reference RN implementation: `src/stores/billingStore.ts`, `src/components/paywall/`

---

## What We DON'T Need to Port

- React Native Firebase workarounds (cache-first prelude, trackPendingWrite)
- Hermes/JS bridge considerations
- Expo SDK dependency management
- AsyncStorage hydration pattern (use SwiftData or UserDefaults)
- RevenueCat JS/RN SDK (replaced by RevenueCat Swift SDK — see Billing & Subscriptions above)

## What Gets Simpler

- Offline-first: Native Firestore SDK handles cache-first reads automatically
- Real-time subscriptions: `onSnapshot` works correctly (cache → server, not server-only)
- Media handling: Native PhotosUI and FileManager instead of Expo modules
- Navigation: SwiftUI NavigationStack/NavigationSplitView instead of Expo Router
- Keyboard shortcuts: Native macOS menu bar integration
- Window management: Free with AppKit/SwiftUI

---

## How Phases Overlap

Phases are **not** strictly sequential. Here's what can run at the same time:

```
Phase 0  ████░░░░░░░░░░░░░░░░░░░░░░░░░░  (done — screenshots are reference)
Phase 1  ░░████░░░░░░░░░░░░░░░░░░░░░░░░  (done — Xcode + Firebase foundation)
Phase 2  ░░░░░░████████░░░░░░░░░░░░░░░░  (models + services)
Phase 3  ░░░░░░████░░░░░░░░░░░░░░░░░░░░  (nav shell — runs alongside Phase 2)
Phase 5a ░░░░░░████░░░░░░░░░░░░░░░░░░░░  (simple components — runs alongside 2+3)
Phase 4  ░░░░░░░░░░░░████████████████░░  (screens — starts after 2+3 are done)
Phase 5b ░░░░░░░░░░░░░░████████████░░░░  (complex components — extracted from screens)
Phase 6  ░░░░░░░░░░░░░░░░░░░░░░░░████░░  (macOS — needs working iOS screens)
Phase 7  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░██  (migration — needs everything else)
```

### Rules

1. **Phases 2, 3, and simple Phase 5 components all run at the same time.** Simple components (`Card`, `Badge`, `AppButton`, `DetailRow`, `FormField`, `SegmentedControl`, `CollapsibleSection`, `SelectorCircle`) have no data dependencies — they take strings and colors as inputs. They can be built now.
2. **Phase 4 starts after both 2 and 3 are done.** Screens need real data (Phase 2) wired into real navigation (Phase 3). Don't start screens until both are finished.
3. **Within Phase 4, screens can run in parallel.** Each screen is its own feature branch. Multiple screens can be built at the same time as long as each one builds and runs independently.
4. **Complex Phase 5 components are extracted from screens, not built upfront.** `ItemCard`, `TransactionCard`, `SearchableFilterableList`, `BulkSelectionBar`, `MediaGallery` all need a real screen to design against. Build them as Phase 4 needs them.
5. **Phase 6 waits for Phase 4.** macOS adaptation needs working iOS screens to adapt.
6. **Phase 7 is last.** Ship only after everything works.

### Current Status (updated 2026-02-28)

- Phase 0: ✅ Done (remaining screenshot gaps are non-blocking)
- Phase 1: ✅ Done
- Phase 2: ✅ Done (all deferred models/services built during Phase 4; minor unknowns: ItemLineageEdge model file, AccountPresets model file — services exist)
- Phase 3: ✅ Done (auth gate, account selection, tab structure, nav shell)
- Phase 4: ✅ Done — all screens implemented (198 Swift files total); only remaining items are Import flows and Paywall/subscription
- Phase 5a: ✅ Done
- Phase 5b: ✅ Done
- Phase 5c: ✅ Done — all modals complete including VendorPickerField.

### Phase 4 Session Breakdown

Detailed plans:
- Session 1: `.plans/phase4-projects-list-detail-budget.md`
- Session 2: `.plans/phase4-transactions-list-detail.md`

| Session | Screens | Status |
|---------|---------|--------|
| Session 1 | Projects List + Project Detail Hub + Budget Tab | ✅ Done |
| Session 2 | Transactions Tab + Transaction Detail | ✅ Done |
| Session 3 | Item List + Item Detail | ✅ Done |
| Session 4 | Spaces Tab + Space Detail | ✅ Done |
| Session 5 | Inventory Screen (3-tab reuse of list components) | ✅ Done |
| Session 6 | Creation flows (New Project, New Transaction, New Item, New Space) | ✅ Done |
| Session 7+ | Settings, Search, Accounting, Reports | ✅ Done |

**Next:** Phase 6 (macOS Target) — or remaining polish items: Import flows (Amazon, Wayfair), Paywall/subscription (RevenueCat).

### Phase 4 Review Notes (carry forward)

Issues identified during WP reviews that affect future WPs:

1. **TransactionListCalculations completeness filter uses AND logic** — Selecting both "needs-review" and "complete" simultaneously returns zero results. When building the filter UI (likely Session 2 screen work), either use OR logic for multi-select or ensure the UI prevents selecting conflicting completeness values.
2. **CompletenessResult omits returned/sold item breakdowns** — The RN `transactionCompleteness.ts` returns `returnedItemsCount`, `returnedItemsTotalCents`, `soldItemsCount`, `soldItemsTotalCents`. The Swift port in `TransactionCompletenessCalculations.swift` omits these 4 fields. If the Transaction Detail view needs a returned/sold breakdown, add these fields to `CompletenessResult` and update `computeCompleteness`.
3. **Missing test coverage for completeness filter dimension** — `TransactionListCalculationTests.swift` tests 7 of 8 filter dimensions but not `completenessValues`. Add coverage when touching that file.

---

## Estimated Scope

| Phase | Effort | Notes |
|-------|--------|-------|
| Phase 0: Screenshots | 1 session | Done |
| Phase 1: Xcode + Firebase | 1-2 sessions | Done |
| Phase 2: Models + Services | 3-5 sessions | Parallel with Phase 3 |
| Phase 3: Navigation Shell | 1-2 sessions | Parallel with Phase 2 |
| Phase 4: Screens | 10-15 sessions | Multiple screens in parallel |
| Phase 5: Components | Built incrementally | Part of Phase 4 work |
| Phase 6: macOS Target | 2-3 sessions | After Phase 4 |
| Phase 7: Migration | 1-2 sessions | After everything |

Each "session" = a focused worktree feature branch.
