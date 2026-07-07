# Stable ID Navigation Remediation Plan

## Goal

Replace mutable Firestore model values in SwiftUI navigation with stable route values that carry IDs and minimal immutable context.

This is a loading-lifecycle and correctness fix. Editing an item, project, transaction, or space should update screen content without changing the identity of the current route, list row, sheet presenter, or destination view.

## Why This Matters

Ledger data is live, mutable, listener-driven, and offline-first. A Firestore model value can change because of:

- local optimistic writes
- snapshot listener reconciliation
- server-side trigger updates
- account/project context refreshes
- derived summary updates
- media thumbnail updates

Using the entire mutable model as a `NavigationLink(value:)` payload means SwiftUI navigation identity can be coupled to normal data changes. That is the wrong layer of identity for this app.

The route should be stable. The displayed content should be live.

## Target Design

Navigation keeps the existing project standard of one `NavigationStack` per tab and value-based `.navigationDestination(for:)`.

The changed standard:

- Use route structs/enums containing stable IDs.
- Do not use Firestore model structs as navigation values.
- Resolve the current model inside the destination from `AccountContext`, `ProjectContext`, `InventoryContext`, or a focused document listener.
- Preserve existing content while live data refreshes.
- Use whole model values only for static, non-persisted, non-mutating values.

Example target shape:

```swift
enum AppRoute: Hashable {
    case inventory
    case project(id: String)
    case item(id: String, scope: ItemRouteScope)
    case transaction(id: String, scope: TransactionRouteScope)
    case space(id: String, scope: SpaceRouteScope)
}

enum ItemRouteScope: Hashable {
    case project(projectId: String)
    case inventory
    case accountSearch
}
```

The exact route type can be split per tab if that is cleaner. The invariant is stable IDs, not this exact enum.

## Design Rules

1. Route values identify where to go, not what to display.
2. Route values must be stable across ordinary document edits.
3. A destination may accept an initial model snapshot only as display fallback, not as route identity.
4. Detail views should accept IDs as their primary input.
5. Existing destination content should stay visible while focused listeners refresh.
6. Missing/deleted documents should render a non-loading unavailable state.
7. Static app destinations, such as `inventory`, may remain simple enum cases.
8. Static report enum destinations may remain value-based if they do not represent mutable Firestore documents.

## Current Problem Areas

### Project Routes

Current examples:

- `ProjectsListView` uses `NavigationLink(value: project)`.
- `MainTabView` registers `.navigationDestination(for: Project.self)`.
- `ProjectsPlaceholderView` registers `.navigationDestination(for: Project.self)`.

Problem:

`Project` is mutable and includes fields like name, client, archive state, main image, and budget summary. Those can change while navigation is active.

Target:

- Route by `project.id`.
- `ProjectDetailContainer` accepts `projectId`.
- The container resolves project display data from `AccountContext.allProjects` and/or `ProjectContext.project`.
- The title can use a cached project snapshot until the project listener returns.

### Item Routes

Current examples:

- `SharedItemsList` uses `NavigationLink(value: item)`.
- `ProjectDetailView`, `MainTabView`, `InventoryView`, and `ReviewView` register `.navigationDestination(for: Item.self)`.
- `UniversalSearchView` uses `NavigationLink(value: item)`.
- `FinancesTabView` uses `NavigationLink(value: item)`.

Problem:

`Item` is highly mutable. Name edits, status changes, bookmark changes, transaction/space changes, media updates, thumbnail updates, and price/category edits can all alter the route payload.

Target:

- Route by `item.id`.
- Include route scope so the destination can resolve from the best existing context:
  - project item: `ProjectContext.items`
  - inventory item: `InventoryContext.items`
  - account/search item: `AccountContext.allItems`
- `ItemDetailView` accepts `itemId`, optional scope, and optional initial snapshot.
- `ItemDetailView` keeps its focused item listener, but does not rely on the original route model for identity.

### Transaction Routes

Current examples:

- `ProjectDetailView`, `MainTabView`, and `InventoryView` register `.navigationDestination(for: Transaction.self)`.
- `FinancesTabView` uses `NavigationLink(value: tx)`.

Problem:

`Transaction` is mutable and can be touched by item links, audit recalculation, receipt updates, status updates, and server triggers.

Target:

- Route by `transaction.id`.
- Include route scope:
  - project transaction
  - inventory transaction
  - account/search transaction
- `TransactionDetailView` accepts `transactionId`, optional scope, and optional initial snapshot.
- The destination resolves from context first, then focused listener.

### Space Routes

Current examples:

- `SpacesTabView`, `InventorySpacesSubTab`, and `UniversalSearchView` use `NavigationLink(value: space)`.
- `ProjectDetailView`, `MainTabView`, and `InventoryView` register `.navigationDestination(for: Space.self)`.

Problem:

`Space` is mutable. Name, notes, checklist, and media updates should not alter route identity.

Target:

- Route by `space.id`.
- Include project/inventory/account scope.
- `SpaceDetailView` accepts `spaceId`, optional scope, and optional initial snapshot.

### Invoice Routes

Current examples:

- `ProjectDetailView` registers `.navigationDestination(for: Invoice.self)`.
- `FinancesTabView` uses `NavigationLink(value: invoice)`.

Problem:

`Invoice` is mutable. Status, line items, settlement, and payment state may change.

Target:

- Route by `invoice.id`.
- `InvoiceDetailView` accepts `invoiceId` and optional initial snapshot.
- Resolve from `AccountContext.allInvoices` first.

## Implementation Plan

### Phase 1: Add Route Types

Create a route model file:

- `LedgeriOS/LedgeriOS/Models/NavigationRoutes.swift`

Add stable route types for mutable Firestore entities:

- `ProjectRoute`
- `ItemRoute`
- `TransactionRoute`
- `SpaceRoute`
- `InvoiceRoute`

Recommended first-pass structs:

```swift
struct ProjectRoute: Hashable {
    let id: String
}

struct ItemRoute: Hashable {
    let id: String
    let scope: ItemRouteScope
}

struct TransactionRoute: Hashable {
    let id: String
    let scope: TransactionRouteScope
}

struct SpaceRoute: Hashable {
    let id: String
    let scope: SpaceRouteScope
}

struct InvoiceRoute: Hashable {
    let id: String
}
```

Route scopes should be small enums. Do not store the full model in the route scope.

Risk:

- Too many route types can create boilerplate.

Control:

- Start with explicit structs instead of a giant global enum. If duplication becomes real, consolidate later.

### Phase 2: Add Context Resolver Helpers

Add small pure or context-local lookup helpers.

Preferred files:

- `LedgeriOS/LedgeriOS/Logic/NavigationRouteResolution.swift` for pure lookup functions, or
- computed helper methods on contexts if the lookup needs context-private state.

Needed lookups:

- project by ID from `AccountContext.allProjects`
- item by ID from `ProjectContext.items`, `InventoryContext.items`, or `AccountContext.allItems`
- transaction by ID from `ProjectContext.transactions`, `InventoryContext.transactions`, or `AccountContext.allTransactions`
- space by ID from `ProjectContext.spaces`, `InventoryContext.spaces`, or `AccountContext.allSpaces`
- invoice by ID from `AccountContext.allInvoices`

These helpers should be unit-testable without SwiftUI.

Risk:

- Detail views already have focused listeners; resolver helpers could duplicate logic.

Control:

- Treat resolver helpers as initial/cached display source. Focused listeners remain the live document source where already present.

### Phase 3: Convert Project Navigation

Files:

- `LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift`
- `LedgeriOS/LedgeriOS/Views/MainTabView.swift`
- `LedgeriOS/LedgeriOS/Views/ProjectsPlaceholderView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailContainer.swift`

Changes:

- Replace `NavigationLink(value: project)` with `NavigationLink(value: ProjectRoute(id: projectId))`.
- Replace `.navigationDestination(for: Project.self)` with `.navigationDestination(for: ProjectRoute.self)`.
- Change `ProjectDetailContainer(project:)` to `ProjectDetailContainer(projectId:initialProject:)`.
- Preserve title/subtitle by passing an optional `initialProject` snapshot.
- Keep `ProjectContext.activate(accountId:projectId:userId:member:)`.

Acceptance criteria:

- Editing project fields does not alter route identity.
- Project detail can open with cached title immediately.
- Project listener activation remains idempotent for same project.

### Phase 4: Convert Project Item Navigation

Files:

- `LedgeriOS/LedgeriOS/Components/SharedItemsList.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ItemsTabView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/FinancesTabView.swift`

Changes:

- Add a route-building closure to `SharedItemsList`, or replace `useNavigationLinks` with a typed navigation route mode.
- Replace `NavigationLink(value: item)` with `NavigationLink(value: ItemRoute(id: itemId, scope: .project(projectId: projectId)))` for project contexts.
- Replace `.navigationDestination(for: Item.self)` with `.navigationDestination(for: ItemRoute.self)`.
- Change project-scope `ItemDetailView` construction to use `itemId`, route scope, and optional initial item snapshot.

Acceptance criteria:

- Editing an item name on item detail does not cause the current route value to change.
- Back from item detail returns to an already-rendered items tab.
- Tapping a card kebab menu is not affected by route payload churn.

### Phase 5: Convert Inventory Item/Transaction/Space Navigation

Files:

- `LedgeriOS/LedgeriOS/Views/Inventory/InventoryView.swift`
- `LedgeriOS/LedgeriOS/Views/Inventory/InventoryItemsSubTab.swift`
- `LedgeriOS/LedgeriOS/Views/Inventory/InventoryTransactionsSubTab.swift`
- `LedgeriOS/LedgeriOS/Views/Inventory/InventorySpacesSubTab.swift`

Changes:

- Replace mutable item/transaction/space route values with `ItemRoute`, `TransactionRoute`, and `SpaceRoute`.
- Use `.inventory` route scopes.
- Resolve initial snapshots from `InventoryContext`.

Acceptance criteria:

- Inventory navigation stays stable while inventory listeners update.
- Inventory card/list updates do not rebuild route identity.

### Phase 6: Convert Search And Review Navigation

Files:

- `LedgeriOS/LedgeriOS/Views/Search/UniversalSearchView.swift`
- `LedgeriOS/LedgeriOS/Views/Review/ReviewView.swift`
- `LedgeriOS/LedgeriOS/Views/MainTabView.swift`

Changes:

- Use `ItemRoute(id:scope:.accountSearch)` for search/review item routes.
- Use `TransactionRoute(id:scope:.accountSearch)` if search links to transactions.
- Use `SpaceRoute(id:scope:.accountSearch)` for search spaces.
- Resolve snapshots from `AccountContext`.

Acceptance criteria:

- Search result navigation remains stable when account-level listeners update.
- Review route payloads do not change when item status/review fields change.

### Phase 7: Convert Finance/Invoice Navigation

Files:

- `LedgeriOS/LedgeriOS/Views/Projects/FinancesTabView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/InvoiceDetailView.swift`

Changes:

- Replace `NavigationLink(value: invoice)` with `NavigationLink(value: InvoiceRoute(id: invoiceId))`.
- Replace `.navigationDestination(for: Invoice.self)` with `.navigationDestination(for: InvoiceRoute.self)`.
- Change `InvoiceDetailView` to accept `invoiceId` and optional initial snapshot.
- Resolve from `AccountContext.allInvoices`.

Acceptance criteria:

- Invoice updates do not affect route identity.
- Existing invoice detail behavior is preserved.

### Phase 8: Update Detail View Inputs

Files:

- `LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/SpaceDetailView.swift`
- `LedgeriOS/LedgeriOS/Views/Search/SpaceSearchDetailView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/InvoiceDetailView.swift`

Changes:

- Prefer initializers whose primary argument is an ID.
- Keep compatibility initializers temporarily if that makes the migration safer:

```swift
init(item: Item) {
    self.init(itemId: item.id ?? "", initialItem: item, scope: .unknown)
}
```

- Remove compatibility initializers after all call sites are migrated.

Risk:

- Empty IDs can hide bugs.

Control:

- Avoid creating routes for nil IDs.
- Compatibility initializers should assert/log on nil ID and be removed before completion.

### Phase 9: Update Project Navigation Standard

File:

- `CLAUDE.md`

Replace the current navigation example with the stable-route standard.

Required wording:

- Keep one `NavigationStack` per tab.
- Keep value-based `.navigationDestination(for:)`.
- Do not use mutable Firestore model structs as route values.
- Use stable route structs/enums containing IDs and minimal immutable context.
- Resolve live model data in the destination.

This is a standards update, not just a code refactor.

### Phase 10: Remove Old Mutable Destinations

Search target:

```bash
rg -n "NavigationLink\\(value:|navigationDestination\\(for:" LedgeriOS/LedgeriOS --glob '*.swift'
```

Completion requirement:

- No `NavigationLink(value: item)`.
- No `NavigationLink(value: project)`.
- No `NavigationLink(value: transaction)`.
- No `NavigationLink(value: space)`.
- No `NavigationLink(value: invoice)`.
- No `.navigationDestination(for: Item.self)`.
- No `.navigationDestination(for: Project.self)`.
- No `.navigationDestination(for: Transaction.self)`.
- No `.navigationDestination(for: Space.self)`.
- No `.navigationDestination(for: Invoice.self)`.

Allowed:

- static enum routes like `AppDestination.inventory`
- static report routes like `ReportType.invoice`
- non-Firestore, non-mutating navigation values

## Testing Plan

### Unit Tests

Add Swift Testing coverage for route resolution.

Likely file:

- `LedgeriOS/LedgeriOSTests/NavigationRouteResolutionTests.swift`

Cover:

- project route resolves from account projects by ID
- project item route prefers project items
- inventory item route prefers inventory items
- search item route resolves from account items
- missing item route returns nil/unavailable state
- transaction/space/invoice resolution follows the same scope rules

### Lifecycle Tests

Extend existing loading lifecycle tests if practical:

- `LedgeriOS/LedgeriOSTests/LoadingLifecycleTests.swift`

Cover:

- same-project route ID does not require project listener restart
- project context activation remains idempotent after converting `ProjectDetailContainer` to ID routes

### Build Checks

Run:

```bash
xcodebuild build -project LedgeriOS/LedgeriOS.xcodeproj -scheme LedgeriOS
```

If the test harness is clean, run:

```bash
xcodebuild test -project LedgeriOS/LedgeriOS.xcodeproj -scheme LedgeriOS
```

If unrelated dirty test files still block full tests, run the focused route/lifecycle tests and document the blocker.

### Manual QA

Use a data set with projects, project items, inventory items, spaces, transactions, invoices, and images.

Scenarios:

1. Open a project, open an item, rename the item, remain on detail.
2. Rename the item, immediately tap back, confirm project items list does not show a blocking spinner.
3. On project items list, tap a card kebab menu repeatedly before and after item updates.
4. Open filter menu immediately after returning from item detail.
5. Open transaction detail from project, edit transaction notes/status, tap back.
6. Open space detail, edit name/notes, tap back.
7. Navigate from Search to item/space, update the entity elsewhere, confirm route remains stable.
8. Navigate from Review to an item, change status, confirm route remains stable.
9. Open invoice detail, update invoice-related state, confirm route remains stable.
10. Switch projects and accounts to confirm data ownership still clears at the correct boundary.

Expected results:

- No full-screen loading after simple detail edits.
- No route pop or route mismatch after model updates.
- Menus open immediately from stable presenters.
- Existing content remains visible while focused listeners refresh.
- Missing/deleted records show unavailable state, not infinite loading.

## Rollout Strategy

Do this in small, reviewable slices.

Recommended order:

1. Add route types and resolver tests.
2. Convert project navigation.
3. Convert project item navigation.
4. Convert inventory navigation.
5. Convert search/review navigation.
6. Convert invoice navigation.
7. Remove compatibility initializers and old destinations.
8. Update `CLAUDE.md`.
9. Run focused tests and manual spinner regression.

Do not mix this with unrelated UI styling, filter memoization, or media upload changes.

## Risks And Controls

### Risk: Detail Views Need Initial Data For Fast First Paint

Control:

- Pass optional initial snapshots separately from route identity.
- Resolve from existing contexts before waiting for focused listeners.

### Risk: More Route Types Add Boilerplate

Control:

- Keep route structs tiny.
- Prefer explicitness until the migration is complete.
- Consolidate only after call sites are stable.

### Risk: Some Flows Need Cross-Context Navigation

Control:

- Route scopes make the source explicit.
- If a scope cannot resolve from its preferred context, fall back to account-level context before showing unavailable state.

### Risk: Compatibility Initializers Become Permanent

Control:

- Mark them temporary in comments.
- Remove them in Phase 10.
- Use `rg` completion checks.

## Definition Of Done

- Mutable Firestore models are no longer used as SwiftUI navigation values.
- Detail views are addressable by stable IDs.
- Existing cached/context data is used for immediate display.
- Focused listeners update content without changing route identity.
- Project navigation standard in `CLAUDE.md` is updated.
- Unit tests cover route resolution.
- Focused lifecycle tests still pass.
- Manual QA confirms item rename, back navigation, filter opening, and kebab menu opening do not produce blocking spinners.
