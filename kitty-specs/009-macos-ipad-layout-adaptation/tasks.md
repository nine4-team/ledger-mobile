# Tasks: macOS + iPad Layout Adaptation

**Feature**: 009-macos-ipad-layout-adaptation
**Date**: 2026-02-28
**Plan**: [plan.md](plan.md) | **Spec**: [spec.md](spec.md)

---

## Subtask Index

| ID | Description | WP | Parallel |
|----|-------------|-----|----------|
| T001 | Add macOS as supported destination in Xcode project | WP01 | |
| T002 | Create macOS App Sandbox entitlements file | WP01 | [P] |
| T003 | Create Platform/PlatformPresenting.swift for GoogleSignIn | WP01 | |
| T004 | Refactor AuthManager for cross-platform GoogleSignIn | WP01 | |
| T005 | Update SignInView to use platform-agnostic auth flow | WP01 | |
| T006 | Wrap UIKit sharing code with platform conditionals | WP01 | [P] |
| T007 | Build verification — macOS target compiles, auth flow works | WP01 | |
| T008 | Refactor MainTabView to iOS 18+ Tab syntax with .sidebarAdaptable | WP02 | |
| T009 | Create LedgerCommands struct with keyboard shortcuts | WP02 | [P] |
| T010 | Add .commands {} to LedgerApp WindowGroup scene | WP02 | |
| T011 | Define Notification.Name extensions for keyboard dispatch | WP02 | [P] |
| T012 | Add notification observers to list views for Cmd+N | WP02 | [P] |
| T013 | Verify iPhone tabs, iPad sidebar toggle, Mac sidebar | WP02 | |
| T014 | Add window sizing constraints to LedgerApp | WP03 | |
| T015 | Add .windowToolbarStyle(.unified) to WindowGroup | WP03 | |
| T016 | Create AccountToolbarMenu component | WP03 | [P] |
| T017 | Add AccountToolbarMenu to MainTabView toolbar | WP03 | |
| T018 | Verify multi-window behavior | WP03 | |
| T019 | Add layout dimension constants to Dimensions.swift | WP04 | |
| T020 | Create AdaptiveContentWidth wrapper component | WP04 | |
| T021 | Apply AdaptiveContentWidth to list views | WP04 | [P] |
| T022 | Apply AdaptiveContentWidth to detail views | WP04 | [P] |
| T023 | Apply AdaptiveContentWidth to form sheets | WP04 | [P] |
| T024 | Add responsive grid columns via onGeometryChange | WP04 | |

---

## Work Package Overview

### Dependency Graph

```
WP01 (Foundation)
 ├── WP02 (Navigation + Shortcuts)
 ├── WP03 (Window Management)  ← parallel with WP02
 └── WP04 (Card Layouts)       ← parallel with WP02, WP03
```

WP02, WP03, and WP04 are independent of each other — all three can run in parallel after WP01 completes.

---

## Phase 1: Foundation

### WP01 — macOS Platform Foundation

**Priority**: P0 (blocking)
**Goal**: macOS target compiles, app launches, and Google Sign-In auth flow works on macOS.
**Prompt**: [WP01-macos-platform-foundation.md](tasks/WP01-macos-platform-foundation.md)
**Dependencies**: None
**Estimated size**: ~450 lines

**Included subtasks**:
- [ ] T001: Add macOS as supported destination in Xcode project
- [ ] T002: Create macOS App Sandbox entitlements file
- [ ] T003: Create Platform/PlatformPresenting.swift for GoogleSignIn
- [ ] T004: Refactor AuthManager for cross-platform GoogleSignIn
- [ ] T005: Update SignInView to use platform-agnostic auth flow
- [ ] T006: Wrap UIKit sharing code with platform conditionals
- [ ] T007: Build verification — macOS target compiles, auth flow works

**Implementation sketch**:
1. Add macOS destination in Xcode project settings (SUPPORTED_PLATFORMS += macosx)
2. Create entitlements file with App Sandbox + network.client
3. Create Platform/PlatformPresenting.swift with #if os() GoogleSignIn abstraction
4. Refactor AuthManager.signInWithGoogle() to remove UIViewController parameter
5. Update SignInView to call simplified auth API
6. Wrap UIActivityViewController usage in ReportPDFSharing.swift and ProjectDetailView.swift
7. Build for macOS simulator/device and verify compilation

**Risks**:
- UIKit references in 4 files (not just AuthManager) — all must be wrapped
- Firebase SPM resolution for macOS may require clean build

---

## Phase 2: Features (Parallel)

### WP02 — Adaptive Navigation & Keyboard Shortcuts

**Priority**: P1
**Goal**: Sidebar on Mac/iPad, tabs on iPhone. Menu bar with keyboard shortcuts.
**Prompt**: [WP02-adaptive-navigation-shortcuts.md](tasks/WP02-adaptive-navigation-shortcuts.md)
**Dependencies**: WP01
**Estimated size**: ~400 lines

**Included subtasks**:
- [ ] T008: Refactor MainTabView to iOS 18+ Tab syntax with .sidebarAdaptable
- [ ] T009: Create LedgerCommands struct with keyboard shortcuts
- [ ] T010: Add .commands {} to LedgerApp WindowGroup scene
- [ ] T011: Define Notification.Name extensions for keyboard dispatch
- [ ] T012: Add notification observers to list views for Cmd+N
- [ ] T013: Verify iPhone tabs, iPad sidebar toggle, Mac sidebar

**Implementation sketch**:
1. Rewrite MainTabView body: Tab("Label", systemImage:) { NavigationStack { ... } }
2. Add .tabViewStyle(.sidebarAdaptable), rename enum to AppSection
3. Create LedgerCommands with CommandGroup entries for Cmd+N, Cmd+F, Cmd+,
4. Define Notification.Name extensions for keyboard dispatch
5. Add .onReceive() to list views (ProjectsListView, InventoryView, etc.)
6. Test on all three platforms

**Parallel opportunities**: T009 (LedgerCommands) and T011/T012 (notifications) can be developed independently of T008 (MainTabView refactor).

---

### WP03 — macOS Window Management & Toolbar

**Priority**: P1
**Goal**: Proper macOS window constraints, unified toolbar, account selector in toolbar, multi-window support.
**Prompt**: [WP03-macos-window-management.md](tasks/WP03-macos-window-management.md)
**Dependencies**: WP01
**Estimated size**: ~350 lines

**Included subtasks**:
- [ ] T014: Add window sizing constraints to LedgerApp
- [ ] T015: Add .windowToolbarStyle(.unified) to WindowGroup
- [ ] T016: Create AccountToolbarMenu component
- [ ] T017: Add AccountToolbarMenu to MainTabView toolbar
- [ ] T018: Verify multi-window behavior

**Implementation sketch**:
1. Add .defaultSize(width: 1000, height: 700), .windowResizability(.contentMinSize) to WindowGroup
2. Add .frame(minWidth: 800, minHeight: 600) to RootView
3. Add .windowToolbarStyle(.unified) to WindowGroup
4. Create AccountToolbarMenu reading from AccountContext environment
5. Add toolbar item to MainTabView with #if os(macOS)
6. Test: open 2 windows, verify independent nav + shared data

**Parallel opportunities**: T016 (AccountToolbarMenu component) can be developed independently.

---

### WP04 — Adaptive Card Layouts

**Priority**: P1
**Goal**: All views render at readable widths on wide screens. No stretching.
**Prompt**: [WP04-adaptive-card-layouts.md](tasks/WP04-adaptive-card-layouts.md)
**Dependencies**: WP01
**Estimated size**: ~400 lines

**Included subtasks**:
- [ ] T019: Add layout dimension constants to Dimensions.swift
- [ ] T020: Create AdaptiveContentWidth wrapper component
- [ ] T021: Apply AdaptiveContentWidth to list views
- [ ] T022: Apply AdaptiveContentWidth to detail views
- [ ] T023: Apply AdaptiveContentWidth to form sheets
- [ ] T024: Add responsive grid columns via onGeometryChange

**Implementation sketch**:
1. Add contentMaxWidth (720), formMaxWidth (560), cardMinWidth (320) to Dimensions.swift
2. Create AdaptiveContentWidth component with frame(maxWidth:).frame(maxWidth: .infinity) centering
3. Wrap list view content in AdaptiveContentWidth (ProjectsListView, InventoryView, UniversalSearchView)
4. Wrap detail view content (ProjectDetailView, ItemDetailView, TransactionDetailView, SpaceDetailView, SpaceSearchDetailView)
5. Wrap form sheets with formMaxWidth (NewProjectView, NewTransactionView, NewItemView, NewSpaceView)
6. Add onGeometryChange responsive grid to BudgetTabView and card grid views

**Parallel opportunities**: T021, T022, T023 touch independent files — all can be done in parallel.

---

## Summary

| WP | Subtasks | Est. Lines | Dependencies | Parallel With |
|----|----------|-----------|--------------|---------------|
| WP01 | 7 (T001-T007) | ~450 | None | — |
| WP02 | 6 (T008-T013) | ~400 | WP01 | WP03, WP04 |
| WP03 | 5 (T014-T018) | ~350 | WP01 | WP02, WP04 |
| WP04 | 6 (T019-T024) | ~400 | WP01 | WP02, WP03 |
| **Total** | **24** | **~1600** | | |
