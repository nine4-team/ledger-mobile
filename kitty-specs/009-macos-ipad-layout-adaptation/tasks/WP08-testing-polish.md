---
work_package_id: WP08
title: Cross-Platform Testing & Polish
lane: "for_review"
dependencies:
- WP03
- WP04
- WP05
- WP06
- WP07
base_branch: 009-macos-ipad-layout-adaptation-WP07
base_commit: caaa1fed075ab30954670ced775265533b6b34f1
created_at: '2026-03-03T22:38:40.340747+00:00'
subtasks:
- T042
- T043
- T044
- T045
- T046
- T047
- T048
phase: Phase 3 - Polish
assignee: ''
agent: "claude-sonnet"
shell_pid: "66410"
review_status: "has_feedback"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-03-01T05:27:35Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP08 – Cross-Platform Testing & Polish

## Important: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

**Reviewed by**: nine4-team
**Status**: ❌ Changes Requested
**Date**: 2026-03-03

## Review Feedback — WP08

### Blockers (must fix)

**Issue 1: Keyboard shortcut conflicts with macOS system defaults**

`LedgerCommands.swift` uses `CommandGroup(after: ...)` which *adds* menu items alongside existing system commands, creating duplicate shortcuts:

- **Cmd+N** (line 9): Conflicts with system "New Window" in a `WindowGroup`. Both your "New Project" and the system "New Window" will have the same shortcut.
- **Cmd+F** (line 31): Conflicts with system "Find" command from `TextEditingCommands`. When a text field is focused, both bindings fight.
- **Cmd+,** (line 38): Conflicts with system "Settings..." that SwiftUI provides automatically via `appSettings` command group. You'll get two Cmd+Comma items.

**Fix:** Use `CommandGroup(replacing: .newItem)` instead of `CommandGroup(after: .newItem)` for the new-item group. Use `CommandGroup(replacing: .textEditing)` for search (or pick a different shortcut like Cmd+Shift+F). Use `CommandGroup(replacing: .appSettings)` for settings. This removes the system defaults and substitutes your custom commands.

**Issue 2: Missing `AdaptiveContentWidth` on project tab views**

`ItemsTabView`, `TransactionsTabView`, and `SpacesTabView` are the only scrollable list views that don't use `AdaptiveContentWidth`. These views appear inside `ProjectDetailView`, and on a maximized 27" display, the detail area can be ~2300px wide after the sidebar. List cards stretching that full width would look inconsistent with how `ProjectsListView`, search results, and settings views are constrained.

**Fix:** Add `AdaptiveContentWidth` wrapping the main `LazyVStack` in each of these three views, matching the pattern used in `ProjectsListView` and `UniversalSearchView`.

### Should Fix (non-blocking)

**Issue 3: `AccountToolbarMenu` has no empty/loading state**

When `discoveredAccounts` is empty (initial load), the menu dropdown is empty with no feedback. Add a fallback `Text("Loading...")` or `Text("No accounts")` item when the array is empty.

**Issue 4: `RootView` minimum window size is too wide for auth screens**

`minWidth: 800` applied to the entire `RootView` means the auth/login screen also enforces an 800pt minimum. This is too wide for a simple sign-in form. Consider applying the min size constraint only to `MainTabView` and using a smaller minimum (e.g., 400x500) for auth views.


## Implementation Command

```bash
spec-kitty implement WP08 --base WP07
```

Depends on WP03, WP04, WP05, WP06, WP07 (all feature WPs must be complete). Use `--base WP07` as it's the last WP in the dependency chain.

---

## Objectives & Success Criteria

- All 7 spec scenarios from spec.md pass acceptance criteria
- No regressions on iPhone (SE through 15 Pro Max)
- iPad orientation transitions work cleanly (sidebar ↔ tabs)
- macOS keyboard shortcuts work correctly
- macOS multi-window works with independent navigation and shared data
- All card layouts are readable on wide screens (up to 27" / 2560px)
- Any issues discovered are fixed before marking this WP complete

## Context & Constraints

- **Spec**: §User Scenarios & Testing — 7 scenarios with acceptance criteria
- **Spec**: §Success Criteria — measurable goals for all platforms
- **Constraint**: This WP is about TESTING and FIXING, not implementing new features. If an issue is found, fix it before marking the test complete.
- **Constraint**: Test on real simulators (not just visual inspection of code). Each test must be run and verified.
- **Constraint**: iPhone SE and iPhone 15 Pro Max are the extremes for iPhone testing. Test both.

## Subtasks & Detailed Guidance

### Subtask T042 – Test Scenario 1: First Launch on Mac

- **Purpose**: Verify the complete macOS first-launch experience end-to-end.
- **Acceptance Criteria** (from spec): User completes sign-in, sees sidebar navigation, and can browse projects without errors.
- **Steps**:
  1. Build and run on macOS (My Mac destination)
  2. Verify: App window opens at approximately 1000x700
  3. Verify: Auth screen appears with Google Sign-In button
  4. Sign in with Google (requires macOS GoogleService-Info.plist in Firebase Console)
  5. If sign-in not available (no macOS Firebase registration), verify the UI renders correctly and skip actual auth
  6. After sign-in (or manually reaching main screen): Verify sidebar is visible on the left
  7. Verify: Projects section is selected by default in sidebar
  8. Verify: Projects list loads from Firestore (cache-first, should be fast)
  9. Click a project → verify detail view shows in the content area
  10. Verify: Sidebar remains visible while viewing project detail
  11. Navigate back → verify projects list is still intact
- **If issues found**: Fix the root cause in the relevant WP's files, then re-test.

### Subtask T043 – Test Scenario 2: Multi-Window Workflow

- **Purpose**: Verify independent navigation and shared data across multiple macOS windows.
- **Acceptance Criteria**: Two windows operate independently. Data changes propagate across windows in real time.
- **Steps**:
  1. Build and run on macOS
  2. Open a second window: File > New Window (or Cmd+N if no creation context)
  3. Window 1: Navigate to Project A's transaction list
  4. Window 2: Navigate to Project B's items
  5. Window 2: Create a new item → verify it appears in Window 2's items list
  6. Window 1: Navigate to Project B → verify the new item is visible
  7. Test: Close Window 2 → verify Window 1 continues working
  8. Test: Resize both windows → verify layouts adapt independently
  9. Test: Account selector in both windows shows same account

### Subtask T044 – Test Scenario 3: iPad Landscape to Portrait Transition

- **Purpose**: Verify sidebar/tab switching during iPad orientation changes.
- **Acceptance Criteria**: Navigation mode switches cleanly between sidebar (landscape) and tabs (portrait). Selected section is preserved across rotations.
- **Steps**:
  1. Build and run on iPad simulator (e.g., iPad Air)
  2. Start in landscape orientation
  3. Verify: Sidebar or adaptable tab bar is visible (`.sidebarAdaptable` gives iPad a toggleable sidebar)
  4. Select "Inventory" in the sidebar/tab bar
  5. Rotate to portrait (Cmd+Left or Cmd+Right in simulator)
  6. Verify: Tab bar appears at bottom with "Inventory" selected
  7. Tap "Settings" tab
  8. Rotate back to landscape
  9. Verify: Sidebar reappears with "Settings" selected
  10. Test: Deep navigation → rotate → verify navigation state preserved

### Subtask T045 – Test Scenario 4: Keyboard-Driven Project Creation

- **Purpose**: Verify keyboard shortcuts trigger correct creation flows.
- **Acceptance Criteria**: Cmd+N triggers the correct creation flow based on context. Form is keyboard-navigable.
- **Steps**:
  1. Build and run on macOS
  2. Navigate to Projects list in sidebar
  3. Press Cmd+N → verify New Project sheet appears
  4. Fill in form using Tab to move between fields
  5. Press Return to submit (or click Done)
  6. Verify: New project appears in the list
  7. Navigate to a project's Transactions tab
  8. Press Cmd+N → verify New Transaction sheet appears (context-sensitive)
  9. Press Escape to dismiss
  10. Navigate to Items tab
  11. Press Cmd+N → verify New Item sheet appears
  12. Test: Cmd+F → verify Search tab is selected or search field is focused
  13. Test: Cmd+, → verify Settings tab is selected
  14. Test: Standard shortcuts work: Cmd+W (close window), Cmd+Q (quit)

### Subtask T046 – Test Scenario 5: Account Switching via Mac Toolbar

- **Purpose**: Verify the toolbar account selector works correctly.
- **Acceptance Criteria**: Account selector is visible in the toolbar. Switching accounts refreshes all data without requiring navigation to Settings.
- **Steps**:
  1. Build and run on macOS (requires a user with multiple accounts)
  2. Verify: Account name is visible in the window toolbar
  3. Click the account name → verify dropdown shows all accounts
  4. Verify: Current account has a checkmark
  5. Select a different account → verify sidebar content refreshes to show that account's data
  6. Test: Navigate to Projects → verify projects belong to the newly selected account
  7. Test: Open Settings → verify account info matches the toolbar selection
  8. If only one account exists: Verify the selector still renders (showing only the current account)

### Subtask T047 – Test Scenario 6: Wide Screen Card Layout

- **Purpose**: Verify no view stretches uncomfortably on wide displays.
- **Acceptance Criteria**: No view stretches uncomfortably on wide screens. Content has reasonable maximum widths.
- **Steps**:
  1. Build and run on macOS
  2. Maximize the window on a large display (or resize to ~2560px wide)
  3. Navigate to Projects list → verify cards are centered with readable width (not edge-to-edge)
  4. Open a project detail → verify content sections are centered with readable line lengths
  5. Navigate to Inventory → verify item cards are centered
  6. Navigate to Search → perform a search → verify results are centered
  7. Navigate to Settings → verify settings list is centered
  8. Open a budget/category view → verify cards use multi-column grid (if implemented)
  9. Open a form sheet (e.g., New Project) → verify form is constrained width on macOS
  10. Test at intermediate widths: 800px, 1200px, 1440px, 1920px — verify smooth transitions
  11. Document any views that still stretch or look wrong

### Subtask T048 – Test Scenario 7: iPhone Experience Unchanged

- **Purpose**: Verify zero regressions on iPhone.
- **Acceptance Criteria**: All existing iPhone screens render correctly with no visual or behavioral changes from pre-Phase 6 behavior.
- **Steps**:
  1. Build and run on iPhone SE (3rd generation) simulator
  2. Navigate through all 4 tabs: Projects, Inventory, Search, Settings
  3. Open a project → navigate to transactions → open a transaction detail → back → back
  4. Create a new item → verify form sheet appears correctly with detents
  5. Open action menus → verify they appear as bottom sheets
  6. Verify: No extra padding, no visual changes, no layout shifts
  7. Build and run on iPhone 15 Pro Max simulator
  8. Repeat the same navigation flow
  9. Verify: Tab bar is at the bottom (no sidebar)
  10. Verify: All cards expand to full screen width (no centering on iPhone — screen is < 720pt)
  11. Verify: All sheets have correct detents and drag indicators
  12. If any regression is found: Fix it immediately before marking complete

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| macOS GoogleService-Info.plist not registered | Skip actual auth testing; verify UI renders correctly |
| iPad rotation doesn't preserve tab selection | May be a SwiftUI framework limitation; document if unfixable |
| Some views missed by layout adaptation WPs | This WP catches them; fix any discovered issues |
| iPhone regression in sheet behavior | Compare with screenshots in `reference/screenshots/dark/` |

## Review Guidance

- All 7 scenarios must have been run and verified (not just code-reviewed)
- Any issues found must be fixed before this WP is marked complete
- iPhone SE and iPhone 15 Pro Max must both be tested
- Document any known limitations or deferred issues

## Activity Log

- 2026-03-01T05:27:35Z – system – lane=planned – Prompt created.

---

### Updating Lane Status

To change a work package's lane, either:
1. **Edit directly**: Change the `lane:` field in frontmatter AND append activity log entry
2. **Use CLI**: `spec-kitty agent tasks move-task WP08 --to <lane> --note "message"`

**Valid lanes**: `planned`, `doing`, `for_review`, `done`
- 2026-03-03T22:38:40Z – claude-opus – shell_pid=19333 – lane=doing – Assigned agent via workflow command
- 2026-03-03T22:54:40Z – claude-opus – shell_pid=19333 – lane=for_review – Ready for review: Fixed macOS platform guards, added AccountToolbarMenu to project, added AdaptiveContentWidth to 8 Settings/Report views. Builds on macOS/iPhone/iPad. 400 tests pass.
- 2026-03-03T23:00:19Z – claude-opus – shell_pid=57410 – lane=doing – Started review via workflow command
- 2026-03-03T23:05:02Z – claude-opus – shell_pid=57410 – lane=planned – Moved to planned
- 2026-03-03T23:06:14Z – claude-sonnet – shell_pid=66410 – lane=doing – Started implementation via workflow command
- 2026-03-03T23:09:51Z – claude-sonnet – shell_pid=66410 – lane=for_review – Ready for review: Fixed all 4 review issues - CommandGroup(replacing:) for newItem/textEditing/appSettings to eliminate shortcut conflicts; AdaptiveContentWidth on ItemsTabView, TransactionsTabView, SpacesTabView; AccountToolbarMenu loading state; RootView per-state min sizes (400x500 auth, 800x600 main). Build passes.
