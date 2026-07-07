# Stable ID Navigation First Milestone Plan

## Status

Ready for implementation. This plan is the senior-scoped first milestone for the broader stable ID navigation remediation.

Related broader plan:

- `docs/plans/stable-id-navigation-remediation-plan.md`

## Goal

Fix the highest-signal navigation/loading path first:

- Projects list -> project detail
- Project items list -> item detail
- Item rename -> stay on item detail without route identity churn
- Back from item detail -> project items list remains stable
- Item kebab menu and filter menu open without being delayed by route/list rebuilds

This milestone intentionally does **not** convert every navigation route in the app.

## Non-Goals

Do not change:

- Firestore document shapes
- item movement rules
- write tiers
- menu contents
- filtering or sorting behavior
- sheet style behavior
- media upload behavior
- transaction, space, invoice, search, or review navigation unless required to compile

This is a navigation identity and loading-lifecycle slice only.

## Architectural Standard Being Enforced

The app may keep the existing standard of one `NavigationStack` per tab and value-based `.navigationDestination(for:)`.

The standard should change in one important way:

- Do **not** use mutable Firestore model structs as SwiftUI navigation values.
- Use stable route values containing IDs and minimal immutable context.
- Resolve live display data inside the destination from context/listeners.

Bad:

```swift
NavigationLink(value: item) {
    ItemCard(...)
}
```

Good:

```swift
NavigationLink(value: ItemRoute(id: itemId, projectId: projectId)) {
    ItemCard(...)
}
```

## Why This Milestone Comes First

The reported spinner symptoms cluster around item detail and project items:

1. Spinner after editing an item name.
2. Intermittent spinner/delay tapping the item 3-dot menu.
3. Spinner after tapping back from item detail.

The item rename path does not intentionally show a spinner. That means the likely problem is surrounding route/view/list identity churn. Converting the project and item routes first directly tests and fixes that theory with the smallest useful blast radius.

## Required Invariants

1. Editing an item name must not change the current route identity.
2. Project detail route identity must be the project ID, not a mutable `Project` value.
3. Item detail route identity must be the item ID plus minimal project context, not a mutable `Item` value.
4. Detail screens may use an initial model snapshot for first paint, but never as route identity.
5. Existing detail content must stay visible while a focused listener refreshes.
6. Missing/deleted records must render a non-loading unavailable state.
7. Project context activation must remain idempotent for the same project.
8. Opening a menu/filter must remain local UI state, not dependent on route/model rebuilds.

## Phase 0: Update The Project Navigation Standard

File:

- `CLAUDE.md`

Replace the current navigation guidance that shows `NavigationLink(value: item)` with stable route guidance.

Required wording:

- Keep one `NavigationStack` per tab.
- Keep value-based navigation with `.navigationDestination(for:)`.
- Do not pass mutable Firestore models as navigation values.
- Use small `Hashable` route structs/enums containing stable IDs and minimal immutable context.
- Resolve the current model in the destination from `AccountContext`, `ProjectContext`, `InventoryContext`, or a focused listener.
- Whole-model navigation is allowed only for static, non-persisted, non-mutating values.

Acceptance criteria:

- New agents have the right standard before touching route code.

## Phase 1: Add Temporary Lifecycle Instrumentation

Add temporary debug logging or counters around the suspected churn path.

Files:

- `LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailContainer.swift`
- `LedgeriOS/LedgeriOS/State/ProjectContext.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift`
- `LedgeriOS/LedgeriOS/Components/SharedItemsList.swift`
- `LedgeriOS/LedgeriOS/Components/FirebaseImage.swift`

Log these events:

- `ProjectDetailContainer` init/body activation key
- `ProjectContext.activate`
- `ProjectContext.stopListeners`
- `ProjectContext.deactivate`
- `ItemDetailView.onAppear`
- `ItemDetailView.onDisappear`
- `ItemDetailView.startItemListener`
- `SharedItemsList.setupData`
- `SharedItemsList.onDisappear`
- `FirebaseImage.task(id:)`

Keep the instrumentation easy to remove:

- Use a single local helper or clearly searchable prefix, for example `[NavLifecycle]`.
- Do not leave noisy logs in the final release unless they are behind a debug flag.

Acceptance criteria:

- Before refactoring, manually reproduce rename/back/menu/filter once and record whether project/item/list/image lifecycles restart.
- If instrumentation disproves route/view churn, pause and revise this plan before implementation.

## Phase 2: Add First-Milestone Route Types

Create:

- `LedgeriOS/LedgeriOS/Models/NavigationRoutes.swift`

Add only the route types needed for this milestone:

```swift
struct ProjectRoute: Hashable {
    let id: String
}

struct ItemRoute: Hashable {
    let id: String
    let projectId: String?
}
```

Rules:

- `ProjectRoute.id` must be non-empty.
- `ItemRoute.id` must be non-empty.
- `ItemRoute.projectId` is set for project item routes.
- Do not store `Project` or `Item` inside the route.

Acceptance criteria:

- Route structs compile and are imported by project views.
- No broader transaction/space/invoice route types are added in this milestone unless required by compile constraints.

## Phase 3: Add Minimal Route Resolution Helpers

Create:

- `LedgeriOS/LedgeriOS/Logic/NavigationRouteResolution.swift`

Add pure helpers:

```swift
enum NavigationRouteResolution {
    static func project(id: String, in projects: [Project]) -> Project?
    static func item(id: String, projectItems: [Item], accountItems: [Item]) -> Item?
}
```

Resolution rules:

- Project resolves from `AccountContext.allProjects`.
- Project item resolves from `ProjectContext.items` first.
- If not found there, item may fall back to `AccountContext.allItems`.
- Return `nil` if not found.

Acceptance criteria:

- Helpers are pure Swift and testable without SwiftUI or Firestore.
- No listener or context mutation happens in these helpers.

## Phase 4: Add Route Resolution Tests

Create:

- `LedgeriOS/LedgeriOSTests/NavigationRouteResolutionTests.swift`

Use Swift Testing.

Cover:

1. Resolves project by ID.
2. Returns nil for missing project.
3. Resolves item from project items first.
4. Falls back to account items when project item is missing.
5. Returns nil for missing item.
6. Prefers project item over account item when both have same ID but different fields.

Acceptance criteria:

- Tests are deterministic and do not require Firebase.

## Phase 5: Convert Project List To Stable Project Routes

Files:

- `LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift`
- `LedgeriOS/LedgeriOS/Views/MainTabView.swift`
- `LedgeriOS/LedgeriOS/Views/ProjectsPlaceholderView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailContainer.swift`

Changes:

- Replace `NavigationLink(value: project)` with `NavigationLink(value: ProjectRoute(id: projectId))`.
- Replace `.navigationDestination(for: Project.self)` with `.navigationDestination(for: ProjectRoute.self)`.
- Change `ProjectDetailContainer` to accept:

```swift
let projectId: String
let initialProject: Project?
```

- Resolve display project from:
  1. `projectContext.project` if it matches `projectId`
  2. `accountContext.allProjects`
  3. `initialProject`

- Keep `ProjectContext.activate(accountId:projectId:userId:member:)`.

Acceptance criteria:

- Project detail opens by ID.
- Project title/subtitle render immediately from cached/initial data.
- Editing project fields does not change route identity.
- Same-project activation still returns early in `ProjectContext.activate`.

## Phase 6: Convert Project Items To Stable Item Routes

Files:

- `LedgeriOS/LedgeriOS/Components/SharedItemsList.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ItemsTabView.swift`

Preferred implementation:

- Add route support to `SharedItemsList` without making it globally generic.
- For project embedded mode, build `ItemRoute(id: itemId, projectId: projectContext.currentProjectId)`.

Possible API:

```swift
var itemRoute: ((Item) -> ItemRoute?)?
```

Then:

```swift
if let route = itemRoute?(item) {
    NavigationLink(value: route) {
        ItemCard(...)
    }
}
```

Changes:

- Replace project-item `NavigationLink(value: item)` with `NavigationLink(value: ItemRoute(...))`.
- Replace project-level `.navigationDestination(for: Item.self)` with `.navigationDestination(for: ItemRoute.self)`.
- Pass optional initial item snapshot to `ItemDetailView`.

Acceptance criteria:

- Project item cards navigate by item ID.
- Nil item IDs do not create routes.
- Card menu behavior remains unchanged.
- Bulk selection behavior remains unchanged.

## Phase 7: Make Item Detail ID-Primary

File:

- `LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift`

Change primary inputs to:

```swift
let itemId: String
let projectId: String?
let initialItem: Item?
```

Keep a temporary compatibility initializer only if needed during migration:

```swift
init(item: Item) {
    self.init(itemId: item.id ?? "", projectId: item.projectId, initialItem: item)
}
```

Rules:

- The view's route identity is `itemId`.
- `liveItem` should prefer focused listener data.
- Before listener data arrives, `liveItem` should use:
  1. resolved item from `ProjectContext.items`
  2. resolved item from `AccountContext.allItems`
  3. `initialItem`
- If a focused listener refresh is in progress, keep showing the last known item.
- If the listener returns nil for the item, show a non-loading unavailable state.

Important:

- Do not set local loading state for item rename.
- Do not blank the detail view during a listener refresh.
- Keep existing `updateItem(fields:)` fire-and-forget behavior.

Acceptance criteria:

- Rename item updates content when listener returns.
- Rename does not trigger route identity churn.
- Detail remains usable while listener refreshes.
- Deleted/missing item does not spin forever.

## Phase 8: Remove Temporary Compatibility For This Slice

After project/item call sites are migrated:

- Remove temporary `ItemDetailView(item:)` initializer if no longer used by this slice.
- Or keep it only if unconverted non-project routes still require it, with a clear `TODO(stable-id-navigation)` marker.

Search:

```bash
rg -n "NavigationLink\\(value: item\\)|navigationDestination\\(for: Item.self\\)|ItemDetailView\\(item:" LedgeriOS/LedgeriOS --glob '*.swift'
```

Acceptance criteria:

- No project items path uses mutable `Item` as route.
- Any remaining `Item.self` destinations are outside the first milestone and documented as follow-up.

## Phase 9: Remove Temporary Instrumentation Or Gate It

Remove or gate the `[NavLifecycle]` logs added in Phase 1.

Acceptance criteria:

- No noisy lifecycle logs ship in release builds.
- If logs remain, they are behind a debug-only guard.

## Verification Plan

### Code Checks

Run:

```bash
rg -n "NavigationLink\\(value: project\\)|navigationDestination\\(for: Project.self\\)" LedgeriOS/LedgeriOS --glob '*.swift'
```

Expected:

- No project list/detail route uses mutable `Project`.

Run:

```bash
rg -n "NavigationLink\\(value: item\\)|navigationDestination\\(for: Item.self\\)|ItemDetailView\\(item:" LedgeriOS/LedgeriOS --glob '*.swift'
```

Expected for this milestone:

- No project items path uses mutable `Item`.
- Remaining non-project call sites, if any, are documented follow-ups.

### Automated Tests

Run the focused new tests:

```bash
xcodebuild test -project LedgeriOS/LedgeriOS.xcodeproj -scheme LedgeriOS -only-testing:LedgeriOSTests/NavigationRouteResolutionTests
```

If the test harness cannot target that exact suite, run the nearest focused command available and document the result.

Run lifecycle tests:

```bash
xcodebuild test -project LedgeriOS/LedgeriOS.xcodeproj -scheme LedgeriOS -only-testing:LedgeriOSTests/LoadingLifecycleTests
```

If unrelated dirty tests block full scheme testing, do not hide that. Report the blocker.

### Manual QA

Use a project with several items and thumbnails.

Scenarios:

1. Open Projects.
2. Open a project.
3. Open an item from the Items tab.
4. Rename the item.
5. Confirm the detail view does not show a blocking spinner.
6. Tap back immediately after rename.
7. Confirm the project Items tab does not show a blocking spinner.
8. Immediately tap the filter menu.
9. Confirm filter opens immediately.
10. Tap item card kebab menus repeatedly before and after item updates.
11. Confirm menus open immediately and actions are unchanged.
12. Switch to another project.
13. Confirm the new project still activates and shows correct data.
14. Sign out or switch accounts if available.
15. Confirm old project state clears.

Expected results:

- Item rename updates content without route churn.
- Back navigation does not restart project listeners for the same project.
- Filter and kebab menus are not delayed by loading/rebuild state.
- Existing content remains visible during listener refresh.
- Missing/deleted item shows unavailable state, not infinite loading.

## Follow-Up Milestones

Do these only after this milestone is verified:

1. Inventory item/transaction/space routes.
2. Search and Review item/space/transaction routes.
3. Finance transaction and invoice routes.
4. Remove any remaining whole-model mutable route destinations.
5. Consider cache-first thumbnail placeholder changes if spinners remain after route churn is fixed.
6. Consider card view-data extraction if broad `AccountContext` invalidation still causes jank.

## Definition Of Done

- `CLAUDE.md` navigation standard is updated.
- `ProjectRoute` and `ItemRoute` exist.
- Route resolution helpers and tests exist.
- Projects list navigates by `ProjectRoute`.
- Project items navigate by `ItemRoute`.
- `ProjectDetailContainer` is project-ID-primary.
- `ItemDetailView` is item-ID-primary for the project item path.
- Project/item route identity remains stable after item rename.
- Manual QA confirms rename, back, filter, and kebab-menu symptoms are improved or instrumentation shows the remaining cause.
- Temporary instrumentation is removed or debug-gated.
