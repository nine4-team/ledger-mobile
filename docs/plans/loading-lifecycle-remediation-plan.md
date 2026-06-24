# Loading Lifecycle Remediation Plan

## Goal

Stop simple UI operations from showing blocking spinners by fixing state ownership and listener lifecycle.

This is not a "hide the spinner" fix. The app should stop treating ordinary navigation, menu opening, and picker opening as reasons to rebuild Firestore subscriptions.

## Target Design

`AccountContext` owns account-scoped data for the selected account:

- `account`
- `member`
- `allProjects`
- `allItems`
- `allTransactions`
- `allSpaces`
- `allBudgetCategories`
- `allInvoices`

`ProjectContext` owns the currently active project:

- project detail
- project items
- project transactions
- project spaces
- project budgets
- project notes
- project preferences

`InventoryContext` owns inventory-scoped data:

- inventory items
- inventory transactions
- inventory spaces

Views own only UI state:

- selected ids
- search text
- filter and sort values
- sheet booleans
- form fields

Pickers and menus should not own Firestore listeners if the data already exists in a context.

## Required Invariants

1. Activating the same account twice must not clear account data or restart listeners.
2. Activating the same project twice must not stop and recreate project listeners.
3. Pushing a child screen from a project must not stop project listeners.
4. Opening a project picker must render immediately from cached `accountContext.allProjects`.
5. Opening a destination picker must always show "Business Inventory" immediately.
6. Switching to a different project must still stop old project listeners and subscribe to the new project.
7. Switching accounts or signing out must clear account/project/inventory state and stop listeners.
8. If cached data exists, the UI should keep showing it while listeners refresh in the background.

## Current Design Problems

### `ProjectContext.activate()` always stops listeners

Same-project re-entry does unnecessary listener teardown and rebuild. With financial access filtering, each listener refresh also recomputes visible transactions, categories, and budget progress.

### `ProjectDetailView.onDisappear` stops project listeners

SwiftUI `onDisappear` can happen when pushing child screens, not only when backing out of a project. Child navigation should not tear down the active project data pipeline.

### `ProjectPickerList` creates its own project listener

This duplicates `AccountContext.allProjects` and intentionally shows `LoadingScreen("Loading projects...")` for what should be an instant picker.

### `DestinationPickerSheet` creates its own project listener

It hides even "Business Inventory" behind a loading screen. That is bad UX and bad data ownership.

### `InventoryContext.activate()` clears and restarts every time

This is probably less responsible for the filter-menu symptom, but same-account activation should still be idempotent.

## Implementation Plan

### Phase 1: Listener Lifecycle Guards

- Add active account/user tracking to `AccountContext`.
- If `activate(accountId:userId:)` is called for the same active account/user and listeners exist, return.
- Add active account/project/user tracking to `ProjectContext`.
- If `activate(accountId:projectId:userId:member:)` is called for the same active project and listeners exist, only update financial access, then return.
- Add active account tracking to `InventoryContext`.
- If `activate(accountId:)` is called for the same account and listeners exist, return.

Risk:

- The guard must not block account switch, project switch, or user/member changes that require recomputation.

Control:

- Use account id, project id, user id, and listener existence in the guard.
- Let member changes continue to call `updateFinancialAccess`.

### Phase 2: Fix Project Listener Ownership

- Remove `projectContext.stopListeners()` from `ProjectDetailView.onDisappear`.
- Add an explicit `ProjectContext.deactivate()` that stops listeners and clears project state.
- Call `projectContext.deactivate()` on account switch/sign-out from a root-level owner, not from child navigation.

Risk:

- Project listeners may live longer after backing out to the project list.

Control:

- This is acceptable short-term because switching projects replaces them, and account switch/sign-out clears them.
- If needed, later add navigation-path-aware teardown at the owning `NavigationStack`, not `ProjectDetailView.onDisappear`.

### Phase 3: Convert Pickers To Cached Data Consumers

- Make `ProjectPickerList` read `accountContext.allProjects.sorted(...)`.
- Remove `FirebaseFirestore`, local `projects`, `isLoading`, `listener`, `.task`, and `.onDisappear` from `ProjectPickerList`.
- Make `DestinationPickerSheet` read active projects from `accountContext.allProjects`.
- Always render Business Inventory immediately.

Risk:

- If `allProjects` has not arrived yet, picker can show empty state briefly.

Control:

- That is still better than a blocking spinner, and `AccountContext` should already be active before main app flows.
- If needed, add a non-blocking "No projects yet" state only after account projects have actually loaded.

### Phase 4: Defer Unrelated Work

Do not touch these in the first pass:

- filter/sort memoization
- save-button/write spinners
- image placeholders
- broad `ProjectsListView` refactors

Only revisit them after the lifecycle/loading gates are fixed and manually tested.

## Verification Plan

### Code Checks

- Confirm no local project listener remains in `ProjectPickerList`.
- Confirm no local project listener remains in `DestinationPickerSheet`.
- Confirm `ProjectDetailView` no longer stops listeners on disappear.
- Confirm same-account/project activation has an early return.
- Confirm sign-out/account switch deactivates project and inventory state.

### Build Checks

- Build the app target.
- Full scheme build currently fails in unrelated dirty test files under `LedgeriOSTests`; after those are fixed, run the full test scheme.

### Manual Repro

1. Launch app into selected account.
2. Open Projects.
3. Open a project.
4. Open an item detail, return to project.
5. Immediately tap filter.
6. Open transaction detail, return, immediately tap filter.
7. Open Sell to Project picker.
8. Open Reassign to Project picker.
9. Open Quick Note project picker.
10. Open New Item destination picker.
11. Switch to another project.
12. Switch account or sign out.

Expected results:

- No project data blanking on child navigation.
- Filter sheet is not delayed by project listener restart.
- Project picker opens without "Loading projects...".
- Destination picker shows Business Inventory immediately.
- Switching projects still loads the correct project.
- Account switch/sign-out clears old state.

## Current Uncommitted Edit Assessment

The current uncommitted edits match this plan directionally:

- `ProjectContext` idempotent activation: good.
- `InventoryContext` idempotent activation: good.
- `AccountContext` idempotent activation: good.
- `ProjectDetailView` no longer stops listeners on disappear: good, but needs root-level cleanup.
- `ProjectContext.deactivate()` and root cleanup: good design direction.
- `ProjectPickerList` uses `accountContext.allProjects`: good.
- `DestinationPickerSheet` uses `accountContext.allProjects`: good.

Review carefully before calling implementation done:

- Root cleanup on `accountContext.currentAccountId` change should not accidentally deactivate project/inventory during normal initial account selection in a way that races `MainTabView.task`.
- Empty-state behavior in project pickers before `allProjects` arrives should be manually checked.
- `ProjectContext.activate()` should restart preferences listener if `userId` changes, so including `userId` in the idempotence key is intentional.
