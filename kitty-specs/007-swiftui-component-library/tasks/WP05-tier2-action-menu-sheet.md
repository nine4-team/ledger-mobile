---
work_package_id: WP05
title: Tier 2 — ActionMenuSheet
lane: "doing"
dependencies: [WP01]
base_branch: 007-swiftui-component-library-WP01
base_commit: 125de502fd2f1682240a1147bc6176e85c037cba
created_at: '2026-02-26T08:15:02.342898+00:00'
subtasks:
- T029
- T030
- T031
- T032
- T033
- T034
phase: Phase 2 - Tier 2 Components
assignee: ''
agent: "claude-opus"
shell_pid: "4335"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T07:45:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP05 – Tier 2 — ActionMenuSheet

## IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP05 --base WP01
```

---

## Objectives & Success Criteria

- Build the ActionMenuSheet component — the most important shared component in the library
- Create ActionMenuCalculations logic with tests
- Replace all `.confirmationDialog()` usage for action menus in existing views (3 files)
- ActionMenuSheet supports hierarchical menus, submenu expansion, destructive styling, multi-select mode

**Success criteria:**
1. ActionMenuSheet presents via `.sheet()` with branded bottom-sheet styling
2. Hierarchical menu items expand inline with checkmark selection state
3. Multi-select mode keeps sheet open after selection
4. Deferred action pattern works (action executes after dismiss animation)
5. `.confirmationDialog()` replaced in ProjectsPlaceholderView, InventoryPlaceholderView, ProjectDetailView

---

## Context & Constraints

- **Reference screenshot**: `reference/screenshots/dark/15_bottom_sheet_menu.png` — hierarchical action menu with icons and chevrons
- **RN source**: `src/components/BottomSheetMenuList.tsx` — the primary reference for behavior
- **Research decisions**: R1 (deferred action via `.onDismiss`), R5 (submenu expansion state)
- **Convention violation found**: Current `.confirmationDialog()` usage gives plain action sheets (no header/icons/submenus). Must replace.
- **CLAUDE.md rule**: `.confirmationDialog()` only for simple destructive confirmations. All action menus use ActionMenuSheet.
- **Type dependency**: ActionMenuItem, ActionMenuSubitem (from WP01)

---

## Subtasks & Detailed Guidance

### Subtask T029 – Create ActionMenuCalculations logic

**Purpose**: Pure functions for menu selection resolution and expansion state.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Logic/ActionMenuCalculations.swift`
2. Define `enum ActionMenuCalculations` with static functions:
   - `toggleExpansion(currentKey: String?, tappedKey: String) -> String?`
     - If currentKey == tappedKey → nil (collapse). Otherwise → tappedKey (expand new)
   - `isSubactionSelected(item: ActionMenuItem, subactionKey: String) -> Bool`
     - Returns item.selectedSubactionKey == subactionKey
   - `hasSubactions(_ item: ActionMenuItem) -> Bool`
     - Returns (item.subactions ?? []).isEmpty == false
   - `isDestructiveItem(_ item: ActionMenuItem) -> Bool`
     - Returns item.isDestructive
   - `resolveMenuAction(item: ActionMenuItem, expandedKey: String?) -> MenuActionResult`
     - If item has subactions and isn't expanded → expand it
     - If item is actionOnly or has no subactions → execute onPress
     - Returns `.expand(key)` or `.executeAction`

3. Define `MenuActionResult` enum:
   ```swift
   enum MenuActionResult {
       case expand(String)      // expand submenu for this key
       case collapse            // collapse currently expanded
       case executeAction       // run the item's onPress
   }
   ```

**Files**: `LedgeriOS/LedgeriOS/Logic/ActionMenuCalculations.swift` (new, ~45 lines)
**Parallel?**: No — used by T031.

### Subtask T030 – Create ActionMenuCalculation tests

**Purpose**: Verify menu logic correctness.

**Steps**:
1. Create `LedgeriOS/LedgeriOSTests/ActionMenuCalculationTests.swift`
2. Test cases (~12 tests):
   - `toggleExpansion`: nil + tap → expand, same key + tap → collapse, different key + tap → switch
   - `isSubactionSelected`: matching key → true, different key → false, nil → false
   - `hasSubactions`: with subactions → true, empty → false, nil → false
   - `isDestructiveItem`: destructive → true, default → false
   - `resolveMenuAction`: item with subactions (not expanded) → expand, item with subactions (already expanded) → collapse, actionOnly → executeAction, no subactions → executeAction

**Files**: `LedgeriOS/LedgeriOSTests/ActionMenuCalculationTests.swift` (new, ~80 lines)
**Parallel?**: No — depends on T029.

**Notes**: Create helper factory functions for test ActionMenuItem instances to reduce boilerplate.

### Subtask T031 – Create ActionMenuSheet component

**Purpose**: The core action menu component replacing all `.confirmationDialog()` for action menus. Branded bottom sheet with hierarchical items, icons, submenus.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/ActionMenuSheet.swift`
2. Parameters:
   - `title: String?` — optional header
   - `items: [ActionMenuItem]`
   - `closeOnItemPress: Bool = true` — false for multi-select mode
   - `onDismissAction: Binding<(() -> Void)?>`? — alternative: use internal `@State pendingAction`
3. State:
   - `@State private var expandedItemKey: String?`
   - `@State private var pendingAction: (() -> Void)?`
   - `@Environment(\.dismiss) private var dismiss`
4. Layout (ScrollView > VStack):
   - **Header** (optional): title text (Typography.h2) with drag indicator above
   - **Menu items** (ForEach items):
     - Each row (Button):
       - HStack: icon (Image(systemName:), 24pt, primary color) | label (Typography.body) | Spacer | chevron.right if hasSubactions
       - If isDestructive: text color = BrandColors.destructive
       - Tap behavior: Use `ActionMenuCalculations.resolveMenuAction()`:
         - `.expand(key)` → set expandedItemKey
         - `.collapse` → set expandedItemKey = nil
         - `.executeAction` → if closeOnItemPress: set pendingAction, dismiss. else: execute directly
     - **Expanded submenu** (if expandedItemKey == item.id):
       - Indented VStack of subaction rows
       - Each subaction row: icon | label | checkmark if selected
       - Tap: execute subaction.onPress, optionally dismiss
   - Dividers between items
5. **Deferred action pattern**:
   - The presenting view should use:
     ```swift
     @State private var showMenu = false
     @State private var menuPendingAction: (() -> Void)?

     .sheet(isPresented: $showMenu, onDismiss: {
         menuPendingAction?()
         menuPendingAction = nil
     }) {
         ActionMenuSheet(title: "Options", items: menuItems) { action in
             menuPendingAction = action
             showMenu = false
         }
         .presentationDetents([.medium, .large])
         .presentationDragIndicator(.visible)
     }
     ```
   - Alternatively, ActionMenuSheet can accept a `onSelectAction: ((() -> Void) -> Void)?` callback that the consuming view uses to capture the pending action.
   - **Recommendation**: Keep it simple. ActionMenuSheet calls `dismiss()` and the consuming view's `onDismiss` block runs the action.
6. Add `#Preview` block with:
   - Simple menu (3 items, no submenus)
   - Hierarchical menu (item with subactions, one selected)
   - Destructive item
   - Multi-select mode (closeOnItemPress: false)

**Files**: `LedgeriOS/LedgeriOS/Components/ActionMenuSheet.swift` (new, ~150 lines)
**Parallel?**: No — this is the most complex component in the WP.

**Notes**:
- Match the visual from screenshot `15_bottom_sheet_menu.png`: branded header, icons on left, chevrons on right, clean dividers.
- Animation: Use `withAnimation { expandedItemKey = ... }` for smooth submenu expansion.
- Multi-select mode: When `closeOnItemPress` is false, tapping an item executes its action directly without dismissing.

### Subtask T032 – Replace `.confirmationDialog()` in ProjectsPlaceholderView

**Purpose**: Replace the plain action sheet with ActionMenuSheet.

**Steps**:
1. Read `LedgeriOS/LedgeriOS/Views/ProjectsPlaceholderView.swift`
2. Identify the `.confirmationDialog("Create New", ...)` with 3 buttons
3. Replace with:
   - `@State private var showCreateMenu = false`
   - `@State private var createMenuPendingAction: (() -> Void)?`
   - ActionMenuSheet with items: "Create Item" (icon: "plus.circle"), "Create Transaction" (icon: "plus.circle"), "Create Project" (icon: "folder.badge.plus")
   - `.sheet(isPresented:onDismiss:)` wrapper with deferred action pattern

**Files**: `LedgeriOS/LedgeriOS/Views/ProjectsPlaceholderView.swift` (edit)
**Parallel?**: Yes — after T031.

### Subtask T033 – Replace `.confirmationDialog()` in InventoryPlaceholderView

**Purpose**: Same pattern as T032 for inventory view.

**Steps**:
1. Read `LedgeriOS/LedgeriOS/Views/InventoryPlaceholderView.swift`
2. Replace `.confirmationDialog("Create New", ...)` with ActionMenuSheet
3. Items: "Create Item", "Create Transaction"

**Files**: `LedgeriOS/LedgeriOS/Views/InventoryPlaceholderView.swift` (edit)
**Parallel?**: Yes — after T031.

### Subtask T034 – Replace `.confirmationDialog()` in ProjectDetailView

**Purpose**: Replace action sheet for project options. Keep destructive delete as `.confirmationDialog()`.

**Steps**:
1. Read `LedgeriOS/LedgeriOS/Views/ProjectDetailView.swift`
2. Identify `.confirmationDialog("Project Options", ...)` with buttons including Delete (destructive)
3. Replace non-destructive options ("Edit Project", "Export Transactions") with ActionMenuSheet
4. Keep "Delete Project" as a separate `.confirmationDialog()` — this is a simple destructive confirmation (per CLAUDE.md convention)
5. Flow: ActionMenuSheet shows Edit/Export options. If user selects "Delete", it opens a `.confirmationDialog()` for confirmation.
6. Use deferred action pattern: ActionMenuSheet → dismiss → `.onDismiss` triggers the delete confirmation dialog.

**Files**: `LedgeriOS/LedgeriOS/Views/ProjectDetailView.swift` (edit)
**Parallel?**: Yes — after T031.

**Notes**: This is the trickiest replacement because it involves sheet-on-sheet sequencing. The ActionMenuSheet dismisses first, then `.onDismiss` triggers the delete confirmation dialog or navigates to edit.

---

## Test Strategy

- **Framework**: Swift Testing
- **Test file**: `LedgeriOS/LedgeriOSTests/ActionMenuCalculationTests.swift`
- **Run command**: `xcodebuild test -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:LedgeriOSTests/ActionMenuCalculationTests`
- **Expected**: ~12 tests, all passing
- Manual verification: Test ActionMenuSheet in simulator for animation smoothness and deferred action timing

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Deferred action fires before animation completes | `.onDismiss` guarantees post-animation execution |
| Sheet-on-sheet sequencing (T034) | Use `.onChange(of:)` to trigger secondary sheet after first dismisses |
| Multi-select mode keeps accumulating actions | Clear pending action on dismiss; execute directly in multi-select mode |

---

## Review Guidance

- Compare ActionMenuSheet visual output with screenshot `15_bottom_sheet_menu.png`
- Test deferred action pattern: tap item → sheet dismisses → action executes
- Verify submenu expansion/collapse animation is smooth
- Check that `.confirmationDialog()` is removed from all 3 files (except destructive delete in ProjectDetailView)
- Test multi-select mode: tapping items doesn't dismiss sheet

---

## Activity Log

- 2026-02-26T07:45:42Z – system – lane=planned – Prompt created.
- 2026-02-26T08:15:02Z – claude-opus – shell_pid=74281 – lane=doing – Assigned agent via workflow command
- 2026-02-26T08:28:39Z – claude-opus – shell_pid=74281 – lane=for_review – Ready for review: ActionMenuSheet component with 16 passing tests, .confirmationDialog() replaced in 3 views
- 2026-02-26T08:29:09Z – claude-opus – shell_pid=4335 – lane=doing – Started review via workflow command
