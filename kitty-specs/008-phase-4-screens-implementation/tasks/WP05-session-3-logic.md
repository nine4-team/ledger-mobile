---
work_package_id: "WP05"
title: "Session 3 Logic – Item List + Item Detail + Bulk Sale Calculations"
phase: "Phase 3 - Session 3"
lane: "done"
dependencies: ["WP00"]
subtasks:
  - "T026"
  - "T027"
  - "T028"
  - "T029"
assignee: ""
agent: "claude-opus"
shell_pid: "98823"
review_status: "approved"
reviewed_by: "nine4-team"
history:
  - timestamp: "2026-02-26T22:30:00Z"
    lane: "planned"
    agent: "system"
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP05 – Session 3 Logic — Item List + Item Detail + Bulk Sale Calculations

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- `ItemListCalculations`: all 10 project-scope filter modes and 7 inventory-scope modes work independently and in combination.
- `ItemListCalculations`: duplicate grouping produces correct expandable group rows.
- `ItemDetailCalculations`: contextual action menu generates correct operations per item status.
- `BulkSaleResolutionCalculations`: filters out items with `transactionId` for bulk reassign.
- All Swift Testing tests pass.

**To start implementing:** `spec-kitty implement WP05 --base WP00`

---

## Context & Constraints

- **Refs**: `plan.md` (WP05), `spec.md` FR-6 (items tab), FR-7 (item detail), FR-8 (modals), `data-model.md` (Item model, status values).
- **Item status canonical values**: `to-purchase`, `purchased`, `to-return`, `returned`.
- **Project-scope filter modes (10)** (FR-6.2): all, bookmarked, from-inventory, to-return, returned, no-sku, no-name, no-project-price, no-image, no-transaction.
- **Inventory-scope filter modes (7)** (FR-6.2): all, bookmarked, no-sku, no-name, no-project-price, no-image, no-transaction.
- **Sort modes (4)** (FR-6.3): created-desc (default), created-asc, alphabetical-asc, alphabetical-desc.
- **Duplicate grouping** (FR-6.3a): group key = `(name ?? "").lowercased() + "|" + (sku ?? "").lowercased() + "|" + (source ?? "").lowercased()`. Groups with count > 1 become `ItemGroupRow`.
- **Multi-select filter**: multiple filter modes active simultaneously — check RN source for intersection vs union behavior; likely intersection (item must match ALL active filters).
- **Single-item action menu** (FR-6.7): change status, set/clear space, set/clear transaction, sell to business, sell to project, reassign to project, reassign to inventory (no financial record), move to return transaction, make copies, bookmark/unbookmark, delete.
- **Contextual** (FR-7.3): Active items = full operations. Returned/sold items = limited (bookmark + delete only).
- **Architecture**: Pure logic in `Logic/`. No SwiftUI, no Firestore. Return typed structs.

---

## Subtasks & Detailed Guidance

### Subtask T026 – Create `Logic/ItemListCalculations.swift`

**Purpose**: All item list filter, sort, search, and grouping logic.

**Steps**:
1. Create `Logic/ItemListCalculations.swift`.
2. Define:
   ```swift
   enum ItemListScope { case project, inventory }
   enum ItemFilterMode: String, CaseIterable {
       case all, bookmarked, fromInventory, toReturn, returned
       case noSKU, noName, noProjectPrice, noImage, noTransaction
   }
   enum ItemSort { case createdDesc, createdAsc, alphabeticalAsc, alphabeticalDesc }
   ```
3. Implement `func availableFilters(for scope: ItemListScope) -> [ItemFilterMode]`:
   - Project: all 10 modes.
   - Inventory: 7 modes (excludes fromInventory, toReturn, returned).
4. Implement `func applyFilters(items: [Item], modes: Set<ItemFilterMode>) -> [Item]`:
   - Each filter mode:
     - `.all` → no filter.
     - `.bookmarked` → `item.bookmark == true`.
     - `.fromInventory` → `item.projectId == nil` (from business inventory, now in a project).
     - `.toReturn` → `item.status == "to-return"`.
     - `.returned` → `item.status == "returned"`.
     - `.noSKU` → `item.sku == nil || item.sku!.isEmpty`.
     - `.noName` → `item.name == nil || item.name!.isEmpty`.
     - `.noProjectPrice` → `item.projectPriceCents == nil`.
     - `.noImage` → `item.images == nil || item.images!.isEmpty`.
     - `.noTransaction` → `item.transactionId == nil`.
   - Multiple active modes: item must satisfy ALL active non-`.all` modes (intersection).
5. Implement `func applySort(items: [Item], sort: ItemSort) -> [Item]`.
6. Implement `func applySearch(items: [Item], query: String) -> [Item]`:
   - Case-insensitive substring match: name, source, SKU, notes.
   - Empty query → return all.
7. Define output types for grouping:
   ```swift
   enum ItemRow {
       case item(Item)
       case group(key: String, label: String, count: Int, items: [Item], isExpanded: Bool)
   }
   ```
8. Implement `func applyDuplicateGrouping(items: [Item]) -> [ItemRow]`:
   - Build group key: `(name ?? "").lowercased() + "|" + (sku ?? "").lowercased() + "|" + (source ?? "").lowercased()`.
   - Groups with count > 1 → `ItemRow.group`.
   - Singleton items → `ItemRow.item`.
   - Maintain original sort order within groups.

**Files**:
- `Logic/ItemListCalculations.swift` (create, ~150 lines)

**Parallel?**: Yes — independent of T027, T028.

---

### Subtask T027 – Create `Logic/ItemDetailCalculations.swift`

**Purpose**: Action menu generation and display field resolution for item detail.

**Steps**:
1. Create `Logic/ItemDetailCalculations.swift`.
2. Define:
   ```swift
   enum ItemAction: String, CaseIterable {
       case changeStatus, setSpace, clearSpace, setTransaction, clearTransaction
       case sellToBusiness, sellToProject, reassignToProject, reassignToInventory
       case moveToReturn, makeCopies, bookmark, unbookmark, delete
   }
   ```
3. Implement `func availableActions(for item: Item, userRole: String) -> [ItemAction]`:
   - Full actions for `status` in `["to-purchase", "purchased", "to-return"]`.
   - Limited actions for `status == "returned"` or `status == "sold"` (if that exists): only bookmark/unbookmark + delete.
   - `setSpace`: available if `item.spaceId == nil`.
   - `clearSpace`: available if `item.spaceId != nil`.
   - `setTransaction`: available if `item.transactionId == nil`.
   - `clearTransaction`: available if `item.transactionId != nil`.
   - `bookmark` vs `unbookmark`: based on `item.bookmark == true`.
4. Implement `func displayPrice(for item: Item) -> Int?`:
   - Returns `item.projectPriceCents` if non-nil, else `item.purchasePriceCents`.
5. Implement `func resolveSpaceName(spaceId: String?, spaces: [Space]) -> String?`:
   - Look up space by id, return `space.name`.
6. Implement `func resolveCategoryName(categoryId: String?, categories: [BudgetCategory]) -> String?`:
   - Look up category by id, return `category.name`.

**Files**:
- `Logic/ItemDetailCalculations.swift` (create, ~80 lines)

**Parallel?**: Yes.

---

### Subtask T028 – Create `Logic/BulkSaleResolutionCalculations.swift`

**Purpose**: Category resolution and eligibility filtering for bulk sell operations.

**Steps**:
1. Create `Logic/BulkSaleResolutionCalculations.swift`.
2. Implement `func eligibleForBulkReassign(items: [Item]) -> [Item]`:
   - Filters out items where `item.transactionId != nil` (must unlink from transaction first).
3. Implement `func resolveSaleCategories(items: [Item], categories: [BudgetCategory]) -> [String: String?]`:
   - Returns a map of `itemId → categoryId?`.
   - For items with `item.budgetCategoryId != nil`: use that.
   - For items without a category: need user to pick → return `nil` for those items (caller prompts user).
4. Implement `func itemsNeedingCategoryResolution(items: [Item]) -> [Item]`:
   - Returns items where `item.budgetCategoryId == nil` (user must choose category for sell flow).

**Files**:
- `Logic/BulkSaleResolutionCalculations.swift` (create, ~60 lines)

**Parallel?**: Yes.

---

### Subtask T029 – Write Swift Testing suite for all 3 modules

**Purpose**: Comprehensive test coverage for item logic modules.

**Steps**:
1. Create `LedgeriOSTests/Logic/ItemListCalculationsTests.swift`:
   - Each of the 10 filter modes individually.
   - Two modes combined (intersection — item must match both).
   - Duplicate grouping: 3 items with same name/sku/source → 1 group row.
   - Duplicate grouping: items with different names → 3 item rows.
   - Sort: created-desc produces newest first.
   - Search: "lamp" matches "Table Lamp" (name), "Lamp shade" (SKU).
   - Project scope has 10 filter modes; inventory scope has 7.
2. Create `LedgeriOSTests/Logic/ItemDetailCalculationsTests.swift`:
   - `to-purchase` status → all actions available.
   - `returned` status → only bookmark/unbookmark + delete.
   - `setSpace` only if spaceId nil; `clearSpace` only if spaceId non-nil.
   - `displayPrice` returns projectPriceCents when set; falls back to purchasePriceCents.
3. Create `LedgeriOSTests/Logic/BulkSaleResolutionCalculationsTests.swift`:
   - Items with `transactionId` excluded from `eligibleForBulkReassign`.
   - Items without category → in `itemsNeedingCategoryResolution`.

**Files**:
- 3 test files in `LedgeriOSTests/Logic/` (create, ~60 lines each = ~180 total)

**Parallel?**: Partial — each test file can start once its implementation is done.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Multi-select filter intersection vs union unclear | Read RN `src/` items filter logic; default to intersection |
| `ItemRow` enum complicates `List` rendering | Use `ForEach` with `.id(\.self)` on the enum's associated values |
| Status for sold items not in canonical values | Check if "sold" is a status or if sold items use "purchased" + a different field |

---

## Review Guidance

- [ ] All 10 project-scope filter modes individually tested.
- [ ] Duplicate grouping: same name+sku+source groups correctly regardless of case.
- [ ] Action menu: `returned` status items get limited menu.
- [ ] `eligibleForBulkReassign` excludes items with `transactionId`.
- [ ] No SwiftUI/Firestore imports in logic files.
- [ ] All tests pass ⌘U.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-02-27T22:43:46Z – unknown – lane=doing – Starting implementation, agent: claude-opus
- 2026-02-27T22:58:08Z – unknown – lane=for_review – Ready for review: Added ItemDetailCalculations, BulkSaleResolutionCalculations, extended ListFilterSortCalculations with multi-filter/scope/source. All 326 tests pass.
- 2026-02-27T22:58:48Z – claude-opus – shell_pid=98823 – lane=doing – Started review via workflow command
- 2026-02-27T23:02:59Z – claude-opus – shell_pid=98823 – lane=done – Review passed: All 3 logic modules correct. 10 filter modes tested individually + multi-filter OR logic matches RN source. Grouping is case-insensitive with source in key. Returned items get limited action menu. BulkSaleResolution correctly filters by transactionId and budgetCategoryId. No SwiftUI/Firestore imports in logic. All tests pass. Reviewed by claude-opus.
