# Research: Item List Picker Normalization

## Decision Log

### D1: Extraction Strategy — Custom Hook (`usePickerMode`)

**Decision:** Extract all picker-specific logic into a `usePickerMode` hook in its own file (`src/hooks/usePickerMode.ts`), rather than inlining into SharedItemsList.

**Rationale:**
- SharedItemsList is already 1,342 lines; adding picker rendering inline would push it past 1,500
- The hook encapsulates stateful derived values (`eligibleIds`, `allEligibleSelected`) and handler factories (`renderAddButton`, `getItemPickerProps`)
- Clean separation: SharedItemsList calls the hook when `picker={true}` and spreads the results
- Previous absorptions of components into SharedItemsList caused regressions (4 fix plans in `.plans/`); isolating picker logic reduces blast radius

**Alternatives considered:**
- *Inline all picker logic in SharedItemsList* — rejected due to god-component risk and test difficulty
- *Render helper utility function* — rejected because it can't own derived state (eligibleIds, allEligibleSelected) without being a hook

### D2: Migration Staging — 4 Work Packages

**Decision:** Staged migration across 4 work packages, each independently testable.

**Rationale:**
- Previous SharedItemsList migrations surfaced edge cases per `.plans/shared-items-list-fixes.md` (4 regressions from feature 005)
- Each stage has a clear rollback point
- SpaceDetail migrated first because it exercises the most picker features (onAddSingle + addedIds)

**Stages:**
1. WP01: Create `usePickerMode` hook + add picker props to SharedItemsList (no consumers changed)
2. WP02: Migrate SpaceDetailContent (full picker features: onAddSingle, addedIds, 2 tabs)
3. WP03: Migrate TransactionDetailScreen (bulk-only, 2-3 dynamic tabs)
4. WP04: Delete SharedItemPicker + clean up exports

### D3: State Management Bridge

**Decision:** Consumers adopt `useItemsManager` for picker selection state. No string[] adapter needed.

**Rationale:**
- `useItemsManager` uses `Set<string>` for selectedIds — O(1) lookup, already battle-tested
- Current picker consumers manage state with `useState<string[]>` — simple to replace with `useItemsManager`
- SharedItemsList's embedded mode already delegates selection to external manager
- The adapter pattern (converting Set→Array) already exists in consumers like SpaceDetailContent (line 743-752)

**What changes for consumers:**
- Replace `const [pickerSelectedIds, setPickerSelectedIds] = useState<string[]>([])` with `const pickerManager = useItemsManager({ items: activePickerItems, ... })`
- Tab switching calls `pickerManager.clearSelection()` instead of `setPickerSelectedIds([])`

### D4: Grouping Alignment

**Decision:** Picker mode adopts SharedItemsList's composite key grouping (`name::sku::source`).

**Rationale:**
- SharedItemPicker groups by `name.toLowerCase()` only — incorrectly merges items that share a name but differ in SKU/source
- SharedItemsList's composite key is more precise and already tested
- Behavior change is strictly an improvement (items that shouldn't be grouped won't be)

### D5: Tab Handling Stays in Parents

**Decision:** SharedItemsList remains tab-unaware. Tab bar rendering and tab state management stay in SpaceDetailContent and TransactionDetailScreen.

**Rationale:**
- Tab logic is consumer-specific (SpaceDetail has 2 fixed tabs, TransactionDetail has 2-3 dynamic tabs)
- SharedItemsList doesn't need to know about tabs to render a list of items
- Tab bar JSX from SharedItemPicker is ~60 lines — simple to extract into parents or a small shared `PickerTabBar` component

### D6: ItemPickerControlBar Reused

**Decision:** Keep `ItemPickerControlBar.tsx` as a separate file. Import it into SharedItemsList's picker render path.

**Rationale:**
- Its layout (inline search + select-all + add button in one row) is fundamentally different from `ItemsListControlBar` (multi-row toolbar with sort/filter)
- Only 150 lines, well-tested
- Merging the two control bars would create unnecessary conditional complexity

---

## Component Analysis

### SharedItemsList (1,342 lines)

**Dual-mode architecture:**
| Aspect | Standalone | Embedded |
|--------|-----------|----------|
| Data | Internal subscription + refresh | External `items` + `manager` props |
| Selection | Internal `internalSelectedIds` (array) | External manager |
| Controls | `ItemsListControlBar` + `BulkSelectionBar` | None (parent controls) |
| Scroll | `FlatList` | Plain `View` with `map()` (parent scroll) |
| Body tap | Navigate to item detail | Navigate via `onItemPress` |

**Key internals:**
- Grouping: composite key `[name, sku, source].join('::').toLowerCase()` (line 424)
- Expansion state: persisted in `state.filters[collapsed:${groupId}]` (line 486)
- Selection delegation: `setItemSelected()` and `setGroupSelection()` check `embedded` flag to route to manager or internal state
- `headerAction` prop exists on ItemCard but is **not used** in SharedItemsList today

**Picker mode integration points:**
1. Control bar conditional: render `ItemPickerControlBar` when `picker={true}` instead of `ItemsListControlBar`
2. Item card props mapping: hook provides `getItemCardProps(item)` that remaps body tap, adds headerAction, applies eligibility styling
3. Group card props mapping: hook provides `getGroupCardProps(groupItems)` that filters eligibleIds, computes group selection, adds onPress for collapsed body tap
4. Select-all override: hook provides `handleSelectAll` that respects eligibility

### SharedItemPicker (501 lines)

**What gets absorbed:**
- Eligibility checking + locked item styling (opacity 0.6) → `usePickerMode`
- `renderAddButton` (Add/Added badge factory) → `usePickerMode`
- `handleSelectAll` (eligibility-filtered) → `usePickerMode`
- `handleGroupToggle` (eligibility-filtered) → `usePickerMode`
- `handleItemToggle` → handled by existing SharedItemsList selection
- Search filtering → uses SharedItemsList's existing search (more comprehensive: searches name, notes, source, SKU)
- Tab bar JSX → extracted to parent components
- `ItemPickerControlBar` integration → reused as-is in SharedItemsList

**What SharedItemPicker does that SharedItemsList doesn't (must be added):**
1. Body tap toggles selection (not navigation)
2. `headerAction` on item cards (Add button / Added badge)
3. Eligibility-aware rendering (locked items, status labels)
4. Eligibility-aware select-all
5. Eligibility-aware group selection
6. No bookmark/status/menu in picker context

### useItemsManager Hook

**API (key methods for picker):**
- `selectedIds: Set<string>` — O(1) lookup
- `toggleSelection(id)` — add or remove single item
- `selectAll()` — selects all filtered items (no eligibility awareness)
- `clearSelection()` — empty selection
- `filteredAndSortedItems` — derived item list

**Gap:** `selectAll()` selects ALL filtered items, not just eligible ones. The `usePickerMode` hook must override this with eligibility-filtered logic.

**Gap:** No `setGroupSelection(ids, selected)`. Consumers implement this as an adapter loop calling `toggleSelection()` per ID.

### Consumer Analysis

| Aspect | SpaceDetailContent | TransactionDetailScreen |
|--------|-------------------|----------------------|
| Tabs | 2 fixed: current/outside | 2-3 dynamic: suggested/project?/outside |
| `onAddSingle` | YES | NO |
| `addedIds` | YES (`spaceItemIds` Set) | NO |
| Eligibility | Strict: blocks linked items | Lenient: allows re-link with dialog |
| Conflict handling | Silent relocation | Dialog-based confirmation |
| Default tab | 'current' | 'suggested' |
| Modal wrapper | BottomSheet (85% height) | BottomSheet (85% height) |

---

## Hook Design: `usePickerMode`

### Input

```typescript
type UsePickerModeConfig = {
  enabled: boolean;                          // false when picker={false}
  items: ScopedItem[];                       // current visible items
  eligibilityCheck?: ItemEligibilityCheck;
  onAddSingle?: (item: ScopedItem | Item) => void | Promise<void>;
  addedIds?: Set<string>;
  selectedIds: string[];                     // from manager adapter (array form)
  setItemSelected: (id: string, next: boolean) => void;
  setGroupSelection: (ids: string[], next: boolean) => void;
};
```

### Output

```typescript
type UsePickerModeReturn = {
  /** Eligible item IDs (passes isEligible and not in addedIds) */
  eligibleIds: string[];

  /** True when all eligible visible items are selected */
  allEligibleSelected: boolean;

  /** Select-all handler that respects eligibility */
  handleSelectAll: () => void;

  /** Build ItemCardProps overrides for a single item in picker mode */
  getPickerItemProps: (item: ScopedItem | Item, baseOnPress?: () => void) => Partial<ItemCardProps>;

  /** Build GroupedItemCard overrides for a group in picker mode */
  getPickerGroupProps: (groupItems: ScopedItem[], groupIds: string[]) => {
    onPress: (() => void) | undefined;
    onSelectedChange: ((next: boolean) => void) | undefined;
    selected: boolean;
  };

  /** Render add button / added badge for an item */
  renderAddButton: (item: ScopedItem | Item, locked: boolean) => React.ReactNode | undefined;
};
```

### Implementation Notes

- All memoized with `useMemo`/`useCallback` for render performance
- `eligibleIds` computed once per render: `items.filter(eligible).filter(!added).map(id)`
- `getPickerItemProps` returns: `{ onPress, onSelectedChange, headerAction, style, onBookmarkPress: undefined, onStatusPress: undefined, menuItems: undefined }`
- `renderAddButton` extracted from SharedItemPicker's existing implementation (lines 207-250)
- When `enabled === false`, all methods return no-ops/undefined — zero overhead in non-picker mode

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SharedItemsList regressions in non-picker mode | Medium | High | Staged migration; picker logic isolated in hook; all picker props are optional with no effect when absent |
| Selection state sync bugs (Set vs Array) | Low | Medium | Adapter pattern already proven in SpaceDetailContent; unit test the bridge |
| Grouped item body-tap regression | Medium | Medium | Explicit test scenario in spec (Scenario 3); hook's `getPickerGroupProps` centralizes this logic |
| Missing headerAction on grouped children | Low | Low | Spec FR-5 covers this; GroupedItemCard already spreads `{...item}` so it "just works" if items array includes headerAction |
| Tab bar extraction breaks styling | Low | Low | Tab bar is self-contained JSX (~60 lines); styles are inline |
