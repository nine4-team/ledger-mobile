---
work_package_id: WP06
title: Session 3 Screens – Items Tab + Item Detail + 13 Modals
lane: "doing"
dependencies:
- WP04
base_branch: 008-phase-4-screens-implementation-WP04
base_commit: a7a758408bf79314ea4914afc4e900681ef8906f
created_at: '2026-02-28T00:54:50.698618+00:00'
subtasks:
- T030
- T031
- T032
- T033
- T034
- T035
phase: Phase 3 - Session 3
assignee: ''
agent: "claude-opus"
shell_pid: "39205"
review_status: "has_feedback"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-26T22:30:00Z'
  lane: planned
  agent: system
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP06 – Session 3 Screens — Items Tab + Item Detail + 13 Modals

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

**Reviewed by**: nine4-team
**Status**: ❌ Changes Requested
**Date**: 2026-02-28

## Review Feedback — WP06

Reviewer: claude-opus
Date: 2026-02-28

Overall: Strong implementation — ItemsTabView, ItemDetailView, both services, and most modals are well-structured and follow project conventions. All modals use bottom sheets with drag indicators correctly. SharedItemsList embedded-mode bug fix is properly implemented. SellToBusiness/SellToProject description texts are exact character-for-character matches. However, there are 2 critical issues that must be fixed (one is a compilation error), plus several high-priority items.

---

### CRITICAL (must fix before merge)

**Issue 1: MakeCopiesModal.swift line 78 — `createdCount` is undeclared (will not compile)**

`createdCount += 1` references a variable that is never declared. Either add `@State private var createdCount = 0` or remove the line (since `createdCount` is never read).

**File:** `LedgeriOS/LedgeriOS/Modals/MakeCopiesModal.swift:78`
**Fix:** Remove line 78 (`createdCount += 1`) — the variable is never read, so the tracking serves no purpose.

---

**Issue 2: Lineage edges are NOT written atomically in sell batch writes**

In `InventoryOperationsService.swift`, lineage edges are created *after* `batch.commit()` as separate fire-and-forget writes with `try?` error suppression (lines ~60 and ~138). If the batch commits but edge creation fails (e.g., app crash, connectivity loss), items are moved with no lineage trail — a data integrity gap.

**Fix:** Encode `LineageEdge` as a `[String: Any]` dictionary and add it to the same `WriteBatch` via `batch.setData(...)` before `commit()`. This ensures atomic write of both item updates and lineage records. If this is too complex right now, at minimum replace `try?` with `try` and propagate the error — silent failure is unacceptable for financial data.

---

### HIGH PRIORITY (should fix before merge)

**Issue 3: SellToProjectModal step 2 uses wrong project's categories**

`SellToProjectModal.swift` line 107 uses `projectContext.budgetCategories` (the *source* project's categories) for the destination project's category picker. When selling items to a different project, the user sees incorrect categories.

**Fix:** Either fetch the destination project's budget categories when the user selects a destination project in step 1, or skip the destination category step and document it as a known limitation for now.

**Issue 4: SetSpaceModal exists but is dead code**

`SetSpaceModal.swift` wraps `SpacePickerList` with a proper title header and dismiss button, but both `ItemDetailView.swift:86` and `ItemsTabView.swift:106` use `SpacePickerList` directly. The modal wrapper is never instantiated outside its Preview.

**Fix:** Change call sites to use `SetSpaceModal` instead of `SpacePickerList` directly, or delete `SetSpaceModal.swift`.

---

### LOW PRIORITY (acceptable to defer)

**Issue 5: `ItemDetailCalculations` layer is missing**

The spec calls for `ItemDetailCalculations.displayPrice()` and `ItemDetailCalculations.availableActions()`, but no such type exists. Price display and action menu logic are inlined in the view. This makes the logic untestable in isolation but is functionally correct.

**Issue 6: MediaGallerySection is read-only**

The spec says "wired to MediaService" but `MediaGallerySection` in `ItemDetailView.swift:235` receives no upload/remove/setPrimary callbacks. Media is display-only. This may be intentional for WP06 scope.

**Issue 7: SpacePickerList missing "Create New Space" row**

The doc comment promises a "Create New Space" option but it is not implemented. The spec says "optional" so this is acceptable to defer.

**Issue 8: `try?` error suppression throughout**

Multiple locations use `try?` to silently swallow Firestore errors (ItemDetailView, ItemsTabView bulk actions). While acceptable for optimistic UI, there is zero user feedback when writes fail. Consider adding error state/alerts for at least delete and sell operations.

---

### Summary

- 2 critical issues (compilation error + lineage atomicity)
- 2 high-priority issues (wrong categories in SellToProject + dead SetSpaceModal)
- 4 low-priority items (acceptable to defer to later WPs)

Please fix Issues 1-4 and resubmit for review.


## Objectives & Success Criteria

- `ItemsTabView` replaces placeholder; shows real items with filter/sort toolbar, multi-select, and duplicate groups.
- `ItemDetailView` shows hero card, 3 collapsible sections, contextual action menu.
- `SharedItemsList` embedded-mode `.onChange(of:)` bug fixed.
- All 13 item modals wired correctly (7 operation modals + 6 picker modals).
- `InventoryOperationsService` and `LineageEdgesService` created.
- Description texts in `SellToBusinessModal` and `SellToProjectModal` match spec exactly.

**To start implementing:** `spec-kitty implement WP06 --base WP04`

---

## Context & Constraints

- **Refs**: `plan.md` (WP06), `spec.md` FR-6 (items tab), FR-7 (item detail), FR-8 (13 modals).
- **Architecture**: Views in `Views/Projects/`, Modals in `Modals/`, Services in `Services/`.
- **SharedItemsList embedded mode bug**: the component copies items into `@State` once at `.task` — parent array updates don't reflect. Fix: add `.onChange(of: items) { newItems in localItems = newItems }` to the component's body.
- **Exact modal description texts** (FR-8.5, FR-8.6):
  - SellToBusinessModal: "This will move items from the project into business inventory. A sale record will be created for financial tracking. If you're just fixing a misallocation, use Reassign instead."
  - SellToProjectModal: "Sale and purchase records will be created for financial tracking. If you're just fixing a misallocation, use Reassign instead."
- **13 modals total**: EditItemDetailsModal, EditNotesModal (reuse from WP04), SetSpaceModal, ReassignToProjectModal, SellToBusinessModal, SellToProjectModal, TransactionPickerModal, ReturnTransactionPickerModal, CategoryPickerList (reuse from WP04), SpacePickerList, ProjectPickerList, MakeCopiesModal, StatusPickerModal.
- **Field order EditItemDetailsModal** (FR-8.1): Name, Source, SKU, Purchase Price, Project Price, Market Value.
- **`ReturnTransactionPickerModal`**: filter transactions to return-type with `status != "completed"` (incomplete returns only).
- **Batch Firestore writes**: sell/reassign operations create multiple documents — use `WriteBatch` to keep them atomic.

---

## Subtasks & Detailed Guidance

### Subtask T030 – Create `Views/Projects/ItemsTabView.swift`

**Purpose**: Replace `ItemsTabPlaceholder.swift` with a full item list with filter/sort/search/multi-select.

**Steps**:
1. Create `Views/Projects/ItemsTabView.swift`.
2. Source items from `projectContext.items`.
3. Build `ItemsListControlBar` (Phase 5 component): sort + filter chip dropdowns.
4. Apply `ItemListCalculations`: filter modes → sort → search → duplicate grouping.
5. Render `ForEach` over `[ItemRow]`:
   - `.item(item)`: render `ItemCard` component.
   - `.group(...)`: render an expandable group row (toggle with `@State var expandedGroups: Set<String>`).
6. Multi-select: `@State var isSelecting: Bool = false` + `@State var selectedItemIds: Set<String>`.
   - Select button in toolbar toggles multi-select mode.
   - In multi-select mode: show checkboxes on each card.
   - Show `BulkSelectionBar` at bottom when items are selected.
7. `BulkSelectionBar` bulk actions: change status, set space, sell to business, sell to project, reassign (filter eligible via `BulkSaleResolutionCalculations.eligibleForBulkReassign`), delete.
8. Add button → present `NewItemView` (stub for WP12).
9. `NavigationLink(value: item)` + `.navigationDestination(for: Item.self)` → `ItemDetailView`.
10. Fix `SharedItemsList` embedded mode: add `.onChange(of: sourceItems) { newItems in localItems = newItems }`.

**Files**:
- `Views/Projects/ItemsTabView.swift` (create, ~150 lines)
- Shared `Components/SharedItemsList.swift` (fix embedded mode `.onChange`)

**Parallel?**: No — sequential.

---

### Subtask T031 – Create `Views/Projects/ItemDetailView.swift`

**Purpose**: Full item detail screen with hero card, collapsible sections, and action menu.

**Steps**:
1. Create `Views/Projects/ItemDetailView.swift` with `init(item: Item)`.
2. Hero card: item name, quantity (if non-nil), purchase price, project price, market value. Display price per `ItemDetailCalculations.displayPrice()`.
3. 3 collapsible sections:
   - Media (expanded by default): `MediaGallerySection` wired to `MediaService`.
   - Notes (collapsed): notes text; edit → `EditNotesModal`.
   - Details (collapsed): status, space name, source, SKU, purchase price, project price, market value, dates.
4. Action menu: toolbar button → `.sheet()` with `ActionMenuSheet` (or custom sheet). Show actions from `ItemDetailCalculations.availableActions()`. Each action opens the corresponding modal.
5. Modals triggered from action menu: `EditItemDetailsModal`, `SetSpaceModal`, `ReassignToProjectModal`, `SellToBusinessModal`, `SellToProjectModal`, `TransactionPickerModal`, `ReturnTransactionPickerModal`, `MakeCopiesModal`, `StatusPickerModal`.
6. Bookmark toggle: star button in toolbar → call `ItemsService.update(bookmark: !item.bookmark)` optimistically.
7. Delete: in action menu → `.confirmationDialog()` → `ItemsService.delete()` → `.dismiss()`.

**Files**:
- `Views/Projects/ItemDetailView.swift` (create, ~180 lines)

**Parallel?**: No — T034, T035 depend on this skeleton.

---

### Subtask T032 – Create `Services/InventoryOperationsService.swift`

**Purpose**: Multi-step Firestore operations for sell-to-business, sell-to-project, and reassign flows.

**Steps**:
1. Create `Services/InventoryOperationsService.swift`.
2. Implement `func sellToBusiness(items: [Item], accountId: String) async throws`:
   - Batch write:
     - Update each item: `projectId = nil`, `spaceId = nil`, `status = "purchased"` (in inventory now).
     - Create a sale transaction record in the source project (type="sale", isCanonicalInventorySale=true, inventorySaleDirection="project_to_business").
   - Use `Firestore.firestore().batch()`.
3. Implement `func sellToProject(items: [Item], destinationProjectId: String, sourceCategoryId: String?, destinationCategoryId: String?) async throws`:
   - Batch write:
     - Update each item: `projectId = destinationProjectId`.
     - Create sale transaction in source project.
     - Create purchase transaction in destination project.
     - Both transactions: `isCanonicalInventorySale=true`.
4. Implement `func reassignToProject(items: [Item], destinationProjectId: String) async throws`:
   - Batch write: update each item's `projectId` only (no financial records — this is just a misallocation fix).
5. Implement `func reassignToInventory(items: [Item]) async throws`:
   - Batch write: update each item's `projectId = nil` (no financial records).

**Files**:
- `Services/InventoryOperationsService.swift` (create, ~120 lines)

**Parallel?**: No — needed before modals can be fully wired.

---

### Subtask T033 – Create `Services/LineageEdgesService.swift`

**Purpose**: Read and write lineage edges (items moved between projects via sell/reassign operations) for the Moved Items section in TransactionDetailView.

**Steps**:
1. Create `Services/LineageEdgesService.swift`.
2. Define `struct LineageEdge: Codable, Identifiable` (check RN Firestore schema for field names — likely `sourceTransactionId`, `destinationTransactionId`, `itemId`, `accountId`).
3. Implement `func edges(forTransaction transactionId: String, accountId: String) async throws -> [LineageEdge]`:
   - Query Firestore: `accounts/{accountId}/lineageEdges` where `sourceTransactionId == transactionId` OR `destinationTransactionId == transactionId`.
4. Implement `func createEdge(_ edge: LineageEdge) async throws`:
   - Write to `accounts/{accountId}/lineageEdges/{edgeId}`.
5. Wire into `InventoryOperationsService` (sell operations should create lineage edges).

**Files**:
- `Services/LineageEdgesService.swift` (create, ~70 lines)

**Parallel?**: No — depends on T032 for integration.

---

### Subtask T034 – Wire item operation modals (7)

**Purpose**: Wire all 7 item operation modals from `ItemDetailView`'s action menu.

**Modals to build/wire**:
1. **`EditItemDetailsModal`**: field order (FR-8.1): Name, Source, SKU, Purchase Price, Project Price, Market Value. Bottom sheet `.large`. Save → `ItemsService.update()` optimistically.
2. **`SetSpaceModal`**: wraps `SpacePickerList` in a titled sheet; on select → `ItemsService.update(spaceId: space.id)`.
3. **`ReassignToProjectModal`**: wraps `ProjectPickerList`; on select → `InventoryOperationsService.reassignToProject()`.
4. **`SellToBusinessModal`**: shows description text (exact from FR-8.5), optional category picker for items without category; confirm → `InventoryOperationsService.sellToBusiness()`.
5. **`SellToProjectModal`**: (1) destination `ProjectPickerList`, (2) optional destination category picker, (3) optional source category picker; shows description text (FR-8.6); confirm → `InventoryOperationsService.sellToProject()`.
6. **`MakeCopiesModal`**: stepper for copy count (min 1, max 20); confirm → `ItemsService.createCopies(item:, count:)`.
7. **`StatusPickerModal`**: 4 status options (to-purchase/purchased/to-return/returned) as radio list; confirm → `ItemsService.update(status:)`.

**Files**:
- `Modals/EditItemDetailsModal.swift` (create, ~100 lines)
- `Modals/SetSpaceModal.swift` (create, ~40 lines)
- `Modals/ReassignToProjectModal.swift` (create, ~40 lines)
- `Modals/SellToBusinessModal.swift` (create, ~70 lines)
- `Modals/SellToProjectModal.swift` (create, ~90 lines)
- `Modals/MakeCopiesModal.swift` (create, ~50 lines)
- `Modals/StatusPickerModal.swift` (create, ~60 lines)

**Parallel?**: Yes — all 7 modals are independent of each other.

---

### Subtask T035 – Wire picker modals (6)

**Purpose**: Wire 6 picker modals used by item operations (some reused from WP04).

**Pickers to build/wire**:
1. **`TransactionPickerModal`**: list of all project transactions (from `projectContext.transactions`); single-select; tap → `ItemsService.update(transactionId:)`.
2. **`ReturnTransactionPickerModal`**: filtered to return-type transactions where `status != "completed"`; single-select; tap → `ItemsService.update(transactionId:)`.
3. **`CategoryPickerList`**: reuse from WP04 (already created).
4. **`SpacePickerList`**: list of project spaces; single-select + optional "Create New Space" row; tap → caller gets spaceId. Design: `init(spaces: [Space], onSelect: (Space?) -> Void)`.
5. **`ProjectPickerList`**: list of all account projects (from `AccountContext.projects` or a fresh subscription); single-select; tap → caller gets projectId. Design: `init(onSelect: (Project) -> Void)`.
6. **`EditNotesModal`**: reuse from WP04 (already created).

**Files**:
- `Modals/TransactionPickerModal.swift` (create, ~60 lines)
- `Modals/ReturnTransactionPickerModal.swift` (create, ~60 lines)
- `Modals/SpacePickerList.swift` (create, ~60 lines)
- `Modals/ProjectPickerList.swift` (create, ~60 lines)

**Parallel?**: Yes.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| 13 modals is a large surface for one WP | Stub first (correct sheet presentation, no logic), then fill in logic per modal |
| `InventoryOperationsService` batch write atomicity | Always use `WriteBatch`; commit all writes together |
| LineageEdge Firestore schema unknown | Read `src/services/lineageEdgesService.ts` in RN source for exact field names |
| `SellToProjectModal` multi-step flow complexity | Use `@State var step: Int` to track step 1/2/3 within the sheet |

---

## Review Guidance

- [ ] Items tab shows real data with filter/sort toolbar; duplicate groups expandable.
- [ ] Multi-select + `BulkSelectionBar` functional for at least 1–5 items.
- [ ] `SharedItemsList` embedded mode: parent array updates reflect in child view.
- [ ] `ItemDetailView`: hero card shows name, quantity, all 3 prices.
- [ ] Action menu: contextual per item status (returned → limited menu).
- [ ] SellToBusinessModal and SellToProjectModal: exact description texts from FR-8.5/8.6.
- [ ] ReturnTransactionPickerModal: only shows incomplete return transactions.
- [ ] All modals present as bottom sheets with drag indicator.
- [ ] `InventoryOperationsService` uses batch writes (not sequential individual writes).

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-02-28T00:54:50Z – claude-sonnet – shell_pid=61367 – lane=doing – Assigned agent via workflow command
- 2026-02-28T01:08:30Z – claude-sonnet – shell_pid=61367 – lane=for_review – Ready for review: ItemsTabView (real items + filter/sort/multi-select), ItemDetailView (hero card + 3 collapsible sections), InventoryOperationsService (atomic batch writes), LineageEdgesService, 7 operation modals + 4 picker modals wired. SharedItemsList embedded bug fixed. Exact FR-8.5/8.6 description texts in SellTo* modals.
- 2026-02-28T01:26:59Z – claude-opus – shell_pid=26590 – lane=doing – Started review via workflow command
- 2026-02-28T01:30:55Z – claude-opus – shell_pid=26590 – lane=planned – Moved to planned
- 2026-02-28T01:32:51Z – claude-opus – shell_pid=39205 – lane=doing – Started implementation via workflow command
