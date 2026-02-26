---
work_package_id: "WP09"
subtasks:
  - "T053"
  - "T054"
  - "T055"
title: "Tier 3 — List Filter/Sort Logic"
phase: "Phase 2 - Logic Foundation"
lane: "planned"
assignee: ""
agent: ""
shell_pid: ""
review_status: ""
reviewed_by: ""
dependencies: ["WP01"]
history:
  - timestamp: "2026-02-26T07:45:42Z"
    lane: "planned"
    agent: "system"
    shell_pid: ""
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP09 – Tier 3 — List Filter/Sort Logic

## IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP09 --base WP01
```

---

## Objectives & Success Criteria

- Build all filter, sort, and grouping logic for SharedItemsList and SharedTransactionsList
- Pure functions with no UI dependencies
- Comprehensive test coverage for every filter predicate and sort comparator

**Success criteria:**
1. Every `ItemFilterOption` case has a working predicate function
2. Every `ItemSortOption` case has a working comparator function
3. Item grouping logic correctly groups by name+SKU
4. All ~25 tests pass

---

## Context & Constraints

- **RN reference**: `src/hooks/useItemsListState.ts` (filter/sort logic), `src/components/SharedItemsList.tsx` (grouping)
- **Existing models**: `Item` (Models/Item.swift) — has all fields needed for filtering
- **Existing logic pattern**: `ProjectListCalculations.swift` — follow same enum with static functions pattern
- **Type dependency**: `ItemFilterOption`, `ItemSortOption` (from WP01)
- **Existing**: `ScopeFilters.swift` has `ListScope` enum — may be useful reference

**Important**: Check if `ScopedItem` exists or if we need to create it. The RN app uses `ScopedItem` which enriches `Item` with project context (project name, category names). If it doesn't exist, determine whether to:
- a) Create `ScopedItem` as a new type
- b) Use `Item` directly (all fields are on Item already)
- c) Create a type alias

---

## Subtasks & Detailed Guidance

### Subtask T053 – Create item filter predicates and sort comparators

**Purpose**: Pure functions that SharedItemsList uses to filter and sort items.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Logic/ListFilterSortCalculations.swift`
2. Define `enum ListFilterSortCalculations` with static functions:

   **Filter predicates** — each returns `(Item) -> Bool`:
   - `filterPredicate(for option: ItemFilterOption) -> (Item) -> Bool`
     - `.all` → always true
     - `.bookmarked` → item.bookmark == true
     - `.fromInventory` → item.source == "inventory" or similar field
     - `.toReturn` → item.status == "to-return"
     - `.returned` → item.status == "returned"
     - `.noSku` → item.sku is nil or empty
     - `.noName` → item.name is nil or empty
     - `.noProjectPrice` → item.projectPriceCents is nil or 0
     - `.noImage` → item.images is empty
     - `.noTransaction` → item.transactionId is nil
   - `applyFilter(_ items: [Item], filter: ItemFilterOption) -> [Item]`
     - Applies the predicate

   **Sort comparators**:
   - `sortComparator(for option: ItemSortOption) -> (Item, Item) -> Bool`
     - `.createdDesc` → newer first (createdAt descending)
     - `.createdAsc` → older first (createdAt ascending)
     - `.alphabeticalAsc` → A-Z by name
     - `.alphabeticalDesc` → Z-A by name
   - `applySort(_ items: [Item], sort: ItemSortOption) -> [Item]`
     - Returns sorted array

   **Search**:
   - `applySearch(_ items: [Item], query: String) -> [Item]`
     - Case-insensitive search on name, sku, notes
     - Empty query → return all

   **Combined**:
   - `applyAllFilters(_ items: [Item], filter: ItemFilterOption, sort: ItemSortOption, search: String) -> [Item]`
     - Pipeline: filter → search → sort

**Files**: `LedgeriOS/LedgeriOS/Logic/ListFilterSortCalculations.swift` (new, ~100 lines)
**Parallel?**: No.

**Notes**:
- Read `Item.swift` first to confirm field names (status, source, bookmark, etc.)
- The RN app uses string matching for status values — check if Item has a status enum or raw strings
- For createdAt sorting: Firestore Timestamp → Date comparison

### Subtask T054 – Create item grouping logic

**Purpose**: Group items by name+SKU for GroupedItemCard display.

**Steps**:
1. Add to `ListFilterSortCalculations.swift`:
   - `groupItems(_ items: [Item]) -> [ItemGroup]`
     - Groups by normalized (name + SKU) key
     - Items with same name + same SKU → one group
     - Single items → group of 1 (for uniform list handling)
   - Define `ItemGroup`:
     ```swift
     struct ItemGroup: Identifiable {
         let id: String  // group key
         let name: String
         let sku: String?
         let items: [Item]
         var count: Int { items.count }
         var totalCents: Int { items.compactMap(\.projectPriceCents).reduce(0, +) }
     }
     ```
   - `shouldShowGrouped(_ groups: [ItemGroup]) -> Bool`
     - True if any group has count > 1

**Files**: `LedgeriOS/LedgeriOS/Logic/ListFilterSortCalculations.swift` (extend, ~40 lines)
**Parallel?**: No — same file as T053.

### Subtask T055 – Create ListFilterSort tests

**Purpose**: Comprehensive test coverage for all filter/sort/group operations.

**Steps**:
1. Create `LedgeriOS/LedgeriOSTests/ListFilterSortCalculationTests.swift`
2. Create test helper: `makeItem(name:sku:bookmark:status:source:projectPriceCents:images:transactionId:createdAt:) -> Item`
3. Test cases (~25 tests):

   **Filter tests** (one per filter option):
   - `.all` → returns all items
   - `.bookmarked` → only bookmarked items
   - `.noSku` → items where sku is nil or empty
   - `.noName` → items where name is nil or empty
   - `.noProjectPrice` → items where projectPriceCents is nil or 0
   - `.noImage` → items with empty images array
   - `.noTransaction` → items where transactionId is nil
   - `.fromInventory` → items sourced from inventory
   - `.toReturn` → items with to-return status
   - `.returned` → items with returned status

   **Sort tests**:
   - `.createdDesc` → newest first
   - `.createdAsc` → oldest first
   - `.alphabeticalAsc` → A before Z
   - `.alphabeticalDesc` → Z before A

   **Search tests**:
   - Matches name → found
   - Matches SKU → found
   - Case insensitive → found
   - No match → empty
   - Empty query → all items

   **Grouping tests**:
   - 3 items, 2 same name+sku → 2 groups (1 with count 2, 1 with count 1)
   - All unique → N groups of 1
   - Empty → empty
   - `totalCents` computation correct

   **Combined**:
   - Filter + sort + search pipeline produces correct result

**Files**: `LedgeriOS/LedgeriOSTests/ListFilterSortCalculationTests.swift` (new, ~150 lines)
**Parallel?**: No — depends on T053, T054.

---

## Test Strategy

- **Framework**: Swift Testing
- **Test file**: `LedgeriOS/LedgeriOSTests/ListFilterSortCalculationTests.swift`
- **Run command**: `xcodebuild test -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:LedgeriOSTests/ListFilterSortCalculationTests`
- **Expected**: ~25 tests, all passing
- **Test data factory**: Create `makeItem()` helper for clean test setup

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Item field names don't match expected | Read Item.swift first; adjust predicates to match actual fields |
| ScopedItem type missing | Use Item directly or create lightweight wrapper |
| Firestore Timestamp date comparison | Use `.dateValue()` for comparison; handle nil dates |

---

## Review Guidance

- Verify every ItemFilterOption case has a corresponding test
- Check that sort comparators handle nil dates / names gracefully
- Confirm grouping key normalization (trim, lowercase)
- Test edge cases: empty arrays, single item, all items matching filter

---

## Activity Log

- 2026-02-26T07:45:42Z – system – lane=planned – Prompt created.
