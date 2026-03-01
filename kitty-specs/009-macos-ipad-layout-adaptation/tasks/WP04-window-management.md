---
work_package_id: WP04
title: macOS Window Management & Toolbar
lane: planned
dependencies:
- WP03
subtasks:
- T017
- T018
- T019
- T020
- T021
- T022
phase: Phase 2 - Features
assignee: ''
agent: ''
shell_pid: ''
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-03-01T05:27:35Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP04 – macOS Window Management & Toolbar

## Important: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

> **Populated by `/spec-kitty.review`**

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP04 --base WP03
```

Depends on WP03 (sidebar navigation must be in place for toolbar context).

---

## Objectives & Success Criteria

- macOS window opens at 1000x700 default size
- Window enforces 800x600 minimum size (cannot be resized smaller)
- Unified toolbar style is applied (title + toolbar in one row)
- Account selector appears in the macOS toolbar showing current account name
- Account selector dropdown lists all discovered accounts; selecting one switches context
- Multiple windows can be opened (File > New Window or Cmd+N when no creation context)
- Each window maintains independent navigation state
- All windows share the same authenticated session and reflect data changes in real time

## Context & Constraints

- **Spec**: FR-3 (Window Toolbar with Account Selector), FR-4 (Multiple Window Support), FR-7 (Minimum Window Size)
- **Plan**: Phase C (Window Management)
- **Research**: §6 (macOS Window Management), §7 (Multi-Window Support)
- **Axiom Guidance**: `axiom-app-composition` — WindowGroup, multi-window, `.defaultSize()`
- **Current architecture**: `LedgerApp.swift` uses `WindowGroup { RootView() }`. `AccountContext` is an `@Observable` manager injected via `.environment()`.
- **Constraint**: Window modifiers (`.defaultSize`, `.windowResizability`, `.windowToolbarStyle`) are silently ignored on iOS — safe to include unconditionally.
- **Constraint**: `.frame(minWidth:minHeight:)` must be conditional (`#if os(macOS)`) to avoid constraining iOS layout.
- **Constraint**: Account selector is macOS-only (spec says "On iOS/iPad, the existing account selection flow remains unchanged").

## Subtasks & Detailed Guidance

### Subtask T017 – Add Window Size and Resizability Modifiers

- **Purpose**: Configure the macOS window to open at a comfortable default size and prevent it from being resized too small.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/LedgerApp.swift`
  2. Add scene modifiers to the `WindowGroup`:
     ```swift
     WindowGroup {
         RootView()
             // ... existing environment injections ...
     }
     .defaultSize(width: 1000, height: 700)
     .windowResizability(.contentMinSize)
     ```
  3. `.defaultSize()` sets the initial window dimensions on first launch
  4. `.windowResizability(.contentMinSize)` prevents the window from being resized smaller than the content's minimum size (set in T018)
  5. These modifiers are silently ignored on iOS — no `#if os(macOS)` needed
- **Files**: `LedgeriOS/LedgeriOS/LedgerApp.swift`
- **Parallel?**: No — sequential with T018/T019.
- **Notes**: Per research §6, `.windowResizability(.contentMinSize)` works with `.frame(minWidth:minHeight:)` on the root view.

### Subtask T018 – Add Minimum Frame to RootView

- **Purpose**: Enforce minimum window dimensions so layouts don't break at very small sizes.
- **Steps**:
  1. Read `LedgeriOS/LedgeriOS/Views/RootView.swift`
  2. Add a conditional minimum frame:
     ```swift
     var body: some View {
         Group {
             // ... existing switch on auth state ...
         }
         #if os(macOS)
         .frame(minWidth: 800, minHeight: 600)
         #endif
     }
     ```
  3. Use `#if os(macOS)` here because we specifically don't want to constrain iOS layout
  4. 800x600 ensures the sidebar (typically ~250pt) plus content area (550pt) remain usable
  5. Test: Try resizing the macOS window below 800x600 — it should stop
- **Files**: `LedgeriOS/LedgeriOS/Views/RootView.swift`
- **Parallel?**: No — sequential with T017.
- **Notes**: The `.windowResizability(.contentMinSize)` from T017 uses this frame to determine the minimum.

### Subtask T019 – Add Unified Toolbar Style

- **Purpose**: Apply macOS unified toolbar style for a clean, modern look (title + toolbar in one row).
- **Steps**:
  1. In `LedgerApp.swift`, add to the `WindowGroup`:
     ```swift
     WindowGroup {
         RootView()
         // ...
     }
     .defaultSize(width: 1000, height: 700)
     .windowResizability(.contentMinSize)
     .windowToolbarStyle(.unified)
     ```
  2. `.unified` places the title and toolbar items in a single compact row
  3. This is silently ignored on iOS — no conditional needed
  4. The toolbar style applies to all windows in the group
- **Files**: `LedgeriOS/LedgeriOS/LedgerApp.swift`
- **Parallel?**: No — add alongside T017.
- **Notes**: Other options include `.unifiedCompact` (shorter) and `.expanded` (toolbar below title). `.unified` is the standard choice.

### Subtask T020 – Create AccountToolbarMenu Component

- **Purpose**: Build a toolbar menu that shows the current account name and lets users switch accounts without navigating to Settings.
- **Steps**:
  1. Create new file: `LedgeriOS/LedgeriOS/Components/AccountToolbarMenu.swift`
  2. Implementation:
     ```swift
     #if os(macOS)
     import SwiftUI

     struct AccountToolbarMenu: View {
         @Environment(AccountContext.self) private var accountContext

         var body: some View {
             Menu {
                 ForEach(accountContext.discoveredAccounts, id: \.id) { account in
                     Button {
                         accountContext.selectAccount(account.id)
                     } label: {
                         HStack {
                             Text(account.name)
                             if account.id == accountContext.currentAccountId {
                                 Image(systemName: "checkmark")
                             }
                         }
                     }
                 }
             } label: {
                 Label(
                     accountContext.currentAccount?.name ?? "Account",
                     systemImage: "person.crop.circle"
                 )
             }
         }
     }
     #endif
     ```
  3. The component reads from `AccountContext` (already injected via environment)
  4. `discoveredAccounts` and `currentAccountId` should already be available on `AccountContext` — verify by reading the file
  5. `selectAccount()` triggers the same account-switching logic as `AccountGateView`
  6. Wrap the entire file in `#if os(macOS)` since this component is macOS-only
- **Files**: `LedgeriOS/LedgeriOS/Components/AccountToolbarMenu.swift` (new file)
- **Parallel?**: Yes — can be developed independently of T017-T019.
- **Notes**: Read `AccountContext` to understand the exact property and method names. The names above are approximations based on the codebase exploration.

### Subtask T021 – Add Toolbar Item for Account Selector

- **Purpose**: Place the `AccountToolbarMenu` in the macOS window toolbar.
- **Steps**:
  1. Decide placement: Either in `RootView.swift` or `MainTabView.swift`
  2. Best placement is in `MainTabView.swift` since it's only visible when authenticated:
     ```swift
     // Inside MainTabView's body, after TabView:
     #if os(macOS)
     .toolbar {
         ToolbarItem(placement: .automatic) {
             AccountToolbarMenu()
         }
     }
     #endif
     ```
  3. Or, place it on the NavigationStack/content level rather than the TabView level — test which renders correctly with `.sidebarAdaptable`
  4. Verify the toolbar item appears in the unified toolbar area (not in the sidebar)
  5. Test: Click the account name → dropdown shows all accounts → selecting one switches context
- **Files**: `LedgeriOS/LedgeriOS/Views/MainTabView.swift`
- **Parallel?**: No — requires T020.
- **Notes**: Toolbar placement with `.sidebarAdaptable` may need experimentation. The toolbar item should appear in the window's toolbar, not in the sidebar.

### Subtask T022 – Verify Multi-Window Behavior

- **Purpose**: Confirm that multiple macOS windows work correctly with independent navigation and shared data.
- **Steps**:
  1. Build and run on macOS
  2. Open a second window: File → New Window (or Cmd+N if no creation context is active)
  3. In Window 1: Navigate to Projects → select a project → view transactions
  4. In Window 2: Navigate to Inventory → select an item
  5. Verify: Each window shows different content (independent navigation)
  6. In Window 2: Create a new item or edit an existing one
  7. Verify: The change is reflected in Window 1 when viewing the same project/items list (shared data via Firestore listeners)
  8. Verify: The account selector in both windows shows the same account
  9. Switch accounts in Window 1 → Verify Window 2 also reflects the new account
  10. Close Window 2 → Verify Window 1 continues working normally
- **Files**: N/A (testing)
- **Parallel?**: No — requires all other subtasks in this WP.
- **Notes**: Multi-window works automatically via SwiftUI's `WindowGroup`. Each window gets independent `@State`/`@SceneStorage` but shares `@Observable` objects from environment. If data doesn't sync across windows, check that Firestore real-time listeners in shared managers are working.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Toolbar item doesn't appear with `.sidebarAdaptable` | Try different toolbar placements; may need to be on the root view level |
| Multi-window state isolation issues | SwiftUI's WindowGroup handles this; test early |
| Account switching in one window not reflected in others | Verify `AccountContext` is shared via environment (injected at LedgerApp level) |
| `.windowResizability` not enforcing minimum | Must pair with `.frame(minWidth:minHeight:)` on content |

## Review Guidance

- Window opens at approximately 1000x700 (exact size may vary by OS)
- Window cannot be resized below 800x600
- Toolbar shows unified style with account name
- Account dropdown lists all accounts with checkmark on current
- Two windows can operate simultaneously with independent navigation
- Data changes propagate across windows

## Activity Log

- 2026-03-01T05:27:35Z – system – lane=planned – Prompt created.

---

### Updating Lane Status

To change a work package's lane, either:
1. **Edit directly**: Change the `lane:` field in frontmatter AND append activity log entry
2. **Use CLI**: `spec-kitty agent tasks move-task WP04 --to <lane> --note "message"`

**Valid lanes**: `planned`, `doing`, `for_review`, `done`
