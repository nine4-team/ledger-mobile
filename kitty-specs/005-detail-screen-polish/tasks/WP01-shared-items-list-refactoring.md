---
work_package_id: WP01
title: SharedItemsList Refactoring
lane: "doing"
dependencies: []
base_branch: main
base_commit: b730a204c881407cf6c7f9771857319074ad1bc3
created_at: '2026-02-10T20:27:14.617855+00:00'
subtasks:
- T001
- T002
- T003
- T004
phase: Phase 1 - Foundation
shell_pid: "87351"
agent: "claude-sonnet-4.5"
history:
- timestamp: '2026-02-10T19:00:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP01 – SharedItemsList Refactoring

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately (right below this notice).
- **You must address all feedback** before your work is complete. Feedback items are your implementation TODO list.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.
- **Report progress**: As you address each feedback item, update the Activity Log explaining what you changed.

---

## Review Feedback

> **Populated by `/spec-kitty.review`** – Reviewers add detailed feedback here when work needs changes. Implementation must address every item listed below before returning for re-review.

*[This section is empty initially. Reviewers will populate it if the work is returned from review. If you see feedback here, treat each item as a must-do before completion.]*

---

## Markdown Formatting
Wrap HTML/XML tags in backticks: `` `<div>` ``, `` `<script>` ``
Use language identifiers in code blocks: ````typescript`, ````bash`

---

## Objectives & Success Criteria

**Goal**: Refactor SharedItemsList component to support both standalone (full-page) and embedded (detail screen section) usage modes with configurable bulk actions.

**Success Criteria**:
- SharedItemsList accepts new props: `embedded`, `manager`, `items`, `bulkActions`, `onItemPress`, `getItemMenuItems`
- When `embedded={false}` (default), component behaves exactly as before (backward compatible)
- When `embedded={true}`, component hides top controls and uses external state/data
- BulkSelectionBar extracted as reusable component
- Bulk selection toggle correctly deselects all when all items are selected
- Project items tab and Inventory items tab still work (no regressions)

**Independent Test**:
1. Standalone mode: Navigate to project items tab or inventory items tab → verify grouping, search, bulk selection work as before
2. Embedded mode: Temporarily use in any detail screen → verify it renders without top controls and uses external state

---

## Context & Constraints

**Problem Statement**: Feature 004 created ItemsSection component for detail screens, but it lacks key features present in SharedItemsList (grouped cards, selector circles, status badges, proper bulk UI). Instead of fixing ItemsSection, we're refactoring SharedItemsList to support both standalone and embedded usage patterns.

**Reference Documents**:
- **Spec**: `kitty-specs/005-detail-screen-polish/spec.md` (User Story 1 - Correct Item List Component)
- **Plan**: `kitty-specs/005-detail-screen-polish/plan.md` (Component Refactoring Strategy, Option A)
- **Research**: `kitty-specs/005-detail-screen-polish/research.md` (Q1: SharedItemsList analysis, Q2: ItemsSection comparison)
- **Quickstart**: `kitty-specs/005-detail-screen-polish/quickstart.md` (§1: Using SharedItemsList in Embedded Mode)

**Constraints**:
- **Backward compatibility**: Existing standalone usage in project/inventory tabs MUST NOT break
- **Offline-first**: All patterns must preserve offline-first architecture (no awaited writes, cache-first reads)
- **Theme-aware**: All UI must use theme tokens (no hardcoded colors)

**Architectural Decision** (from plan.md):
Extract shared logic from SharedItemsList rather than creating a third component or fixing ItemsSection. This maintains a single source of truth for item list behavior and ensures visual consistency across all screens.

---

## Subtasks & Detailed Guidance

### Subtask T001 – Add embedded mode configuration props to SharedItemsList

**Purpose**: Add new optional props that enable external control when SharedItemsList is used in embedded mode (detail screen sections).

**Current State** (`src/components/SharedItemsList.tsx`):
```typescript
type SharedItemsListProps = {
  scopeConfig: ScopeConfig;  // Required
  listStateKey: string;      // Required
  refreshToken?: number;
};
```

**Target State**:
```typescript
type SharedItemsListProps = {
  // Existing props (for standalone mode)
  scopeConfig?: ScopeConfig;        // ← Make optional (not used in embedded)
  listStateKey?: string;             // ← Make optional (not used in embedded)
  refreshToken?: number;

  // New props for embedded mode
  embedded?: boolean;                 // When true, hide top controls, use external state
  manager?: UseItemsManagerReturn;    // External state manager (from useItemsManager)
  items?: ScopedItem[];               // External item data (already filtered/sorted)
  bulkActions?: BulkAction[];         // Custom bulk actions for this context
  onItemPress?: (id: string) => void; // Item tap handler
  getItemMenuItems?: (item: ScopedItem) => AnchoredMenuItem[]; // Context menu items
  emptyMessage?: string;              // Custom empty state message
};

type BulkAction = {
  id: string;
  label: string;
  onPress: (selectedIds: string[]) => void;
  destructive?: boolean;  // If true, render in red/destructive style
};
```

**Steps**:
1. Update `SharedItemsListProps` type definition
2. Add TypeScript union check: if `embedded={true}`, require `manager`, `items`, `bulkActions`
3. Add development-mode prop validation warnings (e.g., "Warning: embedded mode requires manager prop")
4. Add default values: `embedded` defaults to `false`, other new props default to `undefined`

**Files**:
- `src/components/SharedItemsList.tsx` (~5 lines added to type definition)

**Validation**:
- TypeScript compilation succeeds
- No type errors when using SharedItemsList in standalone mode (existing usage)
- Type errors if using `embedded={true}` without required props

**Notes**:
- Do NOT change any component logic yet - this subtask only updates types
- Existing components using SharedItemsList should continue to compile without changes
- The `manager` prop should be typed as `UseItemsManagerReturn<string, string>` (generic)

---

### Subtask T002 – Extract BulkSelectionBar into separate component

**Purpose**: Extract the sticky bottom bar UI (shows "{N} selected" + "Bulk Actions" button) from SharedItemsList into a reusable component that both standalone and embedded modes can use.

**Current Location**: Inside `SharedItemsList.tsx` (inline JSX)

**Target Location**: New file `src/components/BulkSelectionBar.tsx`

**Component Interface**:
```typescript
type BulkSelectionBarProps = {
  selectedCount: number;          // Number of items selected
  onBulkActionsPress: () => void; // Opens bulk actions bottom sheet
  onClearSelection: () => void;   // Clears all selections
};

export function BulkSelectionBar({
  selectedCount,
  onBulkActionsPress,
  onClearSelection,
}: BulkSelectionBarProps) {
  const theme = useTheme();

  if (selectedCount === 0) return null;

  return (
    <View style={[styles.container, { backgroundColor: theme.colors.background, borderTopColor: theme.colors.border }]}>
      <AppText variant="body">{selectedCount} selected</AppText>
      <View style={styles.actions}>
        <AppButton
          title="Clear"
          variant="secondary"
          onPress={onClearSelection}
          size="small"
        />
        <AppButton
          title="Bulk Actions"
          variant="primary"
          onPress={onBulkActionsPress}
          size="small"
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderTopWidth: 1,
    // Shadow for elevation
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 8,
  },
  actions: {
    flexDirection: 'row',
    gap: 8,
  },
});
```

**Steps**:
1. Create new file `src/components/BulkSelectionBar.tsx`
2. Extract sticky bottom bar JSX from SharedItemsList into new component
3. Replace inline JSX in SharedItemsList with `<BulkSelectionBar ... />`
4. Update imports in SharedItemsList
5. Ensure styling matches current behavior (sticky positioning, border, shadow)

**Files**:
- `src/components/BulkSelectionBar.tsx` (new file, ~80 lines)
- `src/components/SharedItemsList.tsx` (modified, replace inline JSX with component usage)

**Validation**:
- Bulk selection bar appears at bottom when items are selected
- Bar is sticky (stays at bottom during scroll)
- Bar hides when selection is cleared
- "Clear" button clears all selections
- "Bulk Actions" button opens bottom sheet
- Styling matches previous behavior (colors, borders, shadows)

**Notes**:
- Use `theme.colors` for all colors (no hardcoded values)
- Position must be `absolute` with `bottom: 0` for sticky behavior
- Shadow/elevation provides visual separation from content
- Component should be framework-agnostic (reusable in any context)

---

### Subtask T003 – Fix bulk selection toggle logic to deselect when all selected

**Purpose**: Fix the "Select All" button to toggle correctly: when all items are already selected, it should deselect all items instead of re-selecting.

**Current Behavior** (bug identified in research.md):
```typescript
const handleBulkSelect = () => {
  manager.selectAll();  // ← Always selects, never deselects
};
```

**Target Behavior**:
```typescript
const handleBulkSelect = () => {
  const allItemIds = items.map(item => item.id);
  const allSelected = allItemIds.length > 0 &&
    allItemIds.every(id => manager.selectedIds.includes(id));

  if (allSelected) {
    manager.clearSelection();  // Deselect all
  } else {
    manager.selectAll();       // Select all
  }
};
```

**Button Label Update**:
```typescript
<AppButton
  title={allSelected ? "Deselect All" : "Select All"}
  onPress={handleBulkSelect}
/>
```

**Steps**:
1. Locate bulk select button handler in SharedItemsList (or wherever it exists)
2. Calculate `allSelected` boolean by comparing item IDs to `manager.selectedIds`
3. Update handler to conditionally call `clearSelection()` or `selectAll()`
4. Update button label to show "Deselect All" when all selected
5. Apply same fix to any other bulk select toggles in the codebase (check ItemsSection too)

**Files**:
- `src/components/SharedItemsList.tsx` (bulk select handler, ~10 lines modified)
- `src/components/ItemsSection.tsx` (if bulk select exists, apply same fix)

**Validation**:
- When no items selected → button says "Select All" → tapping selects all
- When some items selected → button says "Select All" → tapping selects remaining
- When all items selected → button says "Deselect All" → tapping deselects all
- Behavior works in both standalone mode (project items tab) and future embedded mode

**Notes**:
- Use `every()` method to check if all items are selected (efficient)
- Handle edge case: empty item list (don't show button at all)
- This fix is critical for FR-003 (spec requirement)

---

### Subtask T004 – Update SharedItemsList conditional rendering based on embedded mode

**Purpose**: Implement the dual-mode rendering logic where `embedded={true}` hides top controls and uses external state/data, while `embedded={false}` (default) maintains current standalone behavior.

**Implementation Pattern**:
```typescript
export function SharedItemsList({
  // Standalone props
  scopeConfig,
  listStateKey,
  refreshToken,

  // Embedded props
  embedded = false,
  manager: externalManager,
  items: externalItems,
  bulkActions: externalBulkActions,
  onItemPress: externalOnItemPress,
  getItemMenuItems: externalGetItemMenuItems,
  emptyMessage = "No items found",
}: SharedItemsListProps) {
  // Choose state source
  const internalManager = useItemsManager({ listStateKey, ... });
  const manager = embedded ? externalManager! : internalManager;

  // Choose data source
  const internalItems = useScopedItems({ scopeConfig, ... });
  const items = embedded ? externalItems! : internalItems;

  // Choose bulk actions
  const defaultBulkActions = [...]; // Current hardcoded actions
  const bulkActions = embedded ? externalBulkActions! : defaultBulkActions;

  // Choose handlers
  const defaultOnItemPress = (id: string) => router.push(`/items/${id}`);
  const onItemPress = embedded ? externalOnItemPress! : defaultOnItemPress;

  // Render top controls only in standalone mode
  const renderTopControls = () => {
    if (embedded) return null;  // ← Hide in embedded mode

    return (
      <View style={styles.topControls}>
        <SearchBar ... />
        <SortFilterBar ... />
      </View>
    );
  };

  return (
    <View style={styles.container}>
      {renderTopControls()}

      <FlatList
        data={items}
        renderItem={renderItem}
        ...
      />

      <BulkSelectionBar
        selectedCount={manager.selectedIds.length}
        onBulkActionsPress={openBulkSheet}
        onClearSelection={manager.clearSelection}
      />

      <BulkActionsSheet
        visible={bulkSheetVisible}
        selectedIds={manager.selectedIds}
        actions={bulkActions}  // ← Use configurable actions
        onClose={closeBulkSheet}
      />
    </View>
  );
}
```

**Steps**:
1. Add conditional logic to choose state source (`internalManager` vs `externalManager`)
2. Add conditional logic to choose data source (`internalItems` vs `externalItems`)
3. Add conditional logic to choose bulk actions (hardcoded vs `externalBulkActions`)
4. Add conditional logic to choose handlers (`defaultOnItemPress` vs `externalOnItemPress`)
5. Wrap top controls (search, sort, filter) in conditional render (`if (embedded) return null`)
6. Update BulkActionsSheet to use `bulkActions` prop instead of hardcoded actions
7. Add prop validation warnings in development mode

**Files**:
- `src/components/SharedItemsList.tsx` (~50 lines modified, conditional logic added throughout)

**Validation**:
- **Standalone mode** (`embedded={false}` or omitted):
  - Top controls visible (search, sort, filter)
  - Uses internal state from `useItemsManager`
  - Fetches items from Firestore using `scopeConfig`
  - Uses hardcoded bulk actions (current behavior)
  - Navigates to `/items/:id` on tap

- **Embedded mode** (`embedded={true}`):
  - Top controls hidden
  - Uses external state from `manager` prop
  - Renders items from `items` prop (no Firestore queries)
  - Uses custom bulk actions from `bulkActions` prop
  - Calls `onItemPress` handler from prop

**Edge Cases**:
- Warn if `embedded={true}` but `manager` is undefined
- Warn if `embedded={true}` but `items` is undefined
- Warn if `embedded={true}` but `bulkActions` is undefined
- Handle empty item list gracefully (show `emptyMessage`)

**Notes**:
- Use `!` operator to assert non-null when using external props (already validated by types)
- Keep internal logic identical (grouping, rendering, collapse state)
- This subtask completes the refactoring - subsequent WPs will use embedded mode

---

## Test Strategy

**Visual QA** (manual verification):

1. **Standalone mode regression test**:
   - Navigate to project items tab
   - Verify: Search bar visible, sort/filter controls visible
   - Verify: Items grouped correctly (by name/SKU/source)
   - Verify: Selector circles appear on cards
   - Verify: Status badges appear where applicable
   - Select some items → verify bulk bar appears at bottom
   - Tap "Bulk Actions" → verify sheet opens with correct actions
   - Tap "Select All" when none selected → all selected
   - Tap "Deselect All" when all selected → all deselected
   - Repeat for inventory items tab

2. **Embedded mode smoke test** (temporary test code):
   - In any detail screen, temporarily import SharedItemsList with `embedded={true}`
   - Pass `manager` from `useItemsManager`, `items` from state, `bulkActions` array
   - Verify: Top controls hidden
   - Verify: Items render using provided data
   - Verify: Bulk actions use custom array (not hardcoded)
   - Verify: onItemPress handler fires
   - Remove temporary test code after validation

3. **Bulk toggle fix verification**:
   - In project items tab, select no items → button says "Select All"
   - Tap → all items selected → button says "Deselect All"
   - Tap again → all items deselected → button says "Select All"
   - Select half the items → button says "Select All" (not "Deselect All")
   - Tap → remaining items selected → button says "Deselect All"

**No automated tests required** (per feature specification).

---

## Risks & Mitigations

**Risk 1**: Breaking existing standalone usage
- **Severity**: High (project/inventory tabs could break)
- **Mitigation**: Maintain strict backward compatibility (all new props optional, defaults preserve current behavior)
- **Detection**: Manual test project/inventory tabs after changes

**Risk 2**: Component becomes too complex with dual modes
- **Severity**: Medium (harder to maintain)
- **Mitigation**: Use clear conditional logic, consider extracting shared hooks if complexity grows
- **Detection**: Code review for readability

**Risk 3**: Prop validation warnings too aggressive
- **Severity**: Low (noisy console)
- **Mitigation**: Only warn in development mode, use clear messages
- **Detection**: Test in development mode

**Risk 4**: BulkSelectionBar extraction causes styling regressions
- **Severity**: Medium (bulk bar may not appear correctly)
- **Mitigation**: Preserve exact styles during extraction, verify sticky positioning works
- **Detection**: Visual test of bulk bar in project items tab

---

## Review Guidance

**Key Acceptance Checkpoints**:
1. ✅ TypeScript compilation succeeds with no errors
2. ✅ Project items tab works exactly as before (no regressions)
3. ✅ Inventory items tab works exactly as before (no regressions)
4. ✅ BulkSelectionBar is extracted and reusable
5. ✅ Bulk toggle deselects when all items selected
6. ✅ Embedded mode props exist and are properly typed
7. ✅ Conditional rendering logic is clear and correct
8. ✅ No hardcoded colors (all use theme tokens)

**Review Questions**:
- Does the refactoring maintain backward compatibility?
- Is the embedded mode implementation clear and testable?
- Are edge cases handled (undefined props, empty lists)?
- Is the BulkSelectionBar component reusable in other contexts?

**Testing Checklist**:
- [ ] Project items tab: search, sort, filter, grouping all work
- [ ] Inventory items tab: same as above
- [ ] Bulk selection: select all, deselect all, partial selection all work correctly
- [ ] Bulk bar: appears at bottom, sticky during scroll, hides when cleared
- [ ] Theme support: test in light and dark mode (no hardcoded colors)

---

## Activity Log

> **CRITICAL**: Activity log entries MUST be in chronological order (oldest first, newest last).

**Valid lanes**: `planned`, `doing`, `for_review`, `done`

**Initial entry**:
- 2026-02-10T19:00:00Z – system – lane=planned – Prompt generated via /spec-kitty.tasks
- 2026-02-10T20:27:14Z – claude-agent – shell_pid=74879 – lane=doing – Assigned agent via workflow command
- 2026-02-10T20:34:27Z – claude-agent – shell_pid=74879 – lane=for_review – Ready for review: All subtasks complete. SharedItemsList refactored to support embedded mode with custom bulk actions and menu items. BulkSelectionBar extracted as reusable component. Bulk toggle fixed to deselect when all selected. Full backward compatibility maintained.
- 2026-02-10T20:37:41Z – claude-sonnet-4.5 – shell_pid=87351 – lane=doing – Started review via workflow command
