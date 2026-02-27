---
work_package_id: WP10
title: Session 5 Screens – Inventory Screen
lane: planned
dependencies:
- WP09
subtasks:
- T046
- T047
- T048
- T049
phase: Phase 5 - Session 5
assignee: ''
agent: ''
shell_pid: ''
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T22:30:00Z'
  lane: planned
  agent: system
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP10 – Session 5 Screens — Inventory Screen

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- `InventoryView` replaces `InventoryPlaceholderView.swift` with 3 working sub-tabs.
- Items tab shows only business inventory items (no project-scoped data).
- Full filter/sort/bulk operations available, same as project-scoped lists.
- Tab selection restored from `UserDefaults` on app restart.
- Navigation to detail screens reuses `ItemDetailView`, `TransactionDetailView`, `SpaceDetailView`.

**To start implementing:** `spec-kitty implement WP10 --base WP09`

---

## Context & Constraints

- **Refs**: `plan.md` (WP10), `spec.md` FR-10.
- **Data source**: `InventoryContext` (built in WP09) — NOT `ProjectContext`.
- **Reuse**: `SharedItemsList`, `SharedTransactionsList`, space card list — same components as project-scoped views.
- **Detail screens**: `ItemDetailView`, `TransactionDetailView`, `SpaceDetailView` are already built — reuse them directly.
- **NavigationStack**: Inventory tab has its own `NavigationStack` (one per tab — this already exists from Phase 3 shell).
- **Tab persistence**: restore from `inventoryContext.lastSelectedTab` on view appear.

---

## Subtasks & Detailed Guidance

### Subtask T046 – Create `Views/Inventory/InventoryView.swift`

**Purpose**: Root view for the Inventory tab with 3 sub-tabs.

**Steps**:
1. Open `Views/Inventory/InventoryPlaceholderView.swift` (or equivalent) — note its navigation setup.
2. Create `Views/Inventory/InventoryView.swift` to replace it.
3. `@Environment(InventoryContext.self) private var inventoryContext`.
4. `@State private var selectedTab: Int` — initialized from `inventoryContext.lastSelectedTab`.
5. `ScrollableTabBar` with 3 tabs: "Items", "Transactions", "Spaces".
6. Tab content: switch on `selectedTab`:
   - 0: `InventoryItemsSubTab()` (T047)
   - 1: `InventoryTransactionsSubTab()` (T048)
   - 2: `InventorySpacesSubTab()` (T049)
7. On `.onAppear`: call `inventoryContext.activate(accountId: authManager.accountId)`.
8. On `.onDisappear`: call `inventoryContext.deactivate()`.
9. On tab change: update `inventoryContext.lastSelectedTab = selectedTab`.
10. Update `MainTabView.swift` (or equivalent) to use `InventoryView()` instead of `InventoryPlaceholderView()`.

**Files**:
- `Views/Inventory/InventoryView.swift` (create, ~70 lines)
- `MainTabView.swift` or equivalent (modify — replace placeholder reference)

---

### Subtask T047 – Wire inventory Items sub-tab

**Purpose**: Items tab showing inventory-scoped items with full filter/sort/bulk ops.

**Steps**:
1. Create `Views/Inventory/InventoryItemsSubTab.swift` (or implement inline in InventoryView if small).
2. Use `inventoryContext.items` as the data source.
3. Apply `ItemListCalculations` with `.inventory` scope (7 filter modes).
4. Render using `SharedItemsList` (or same pattern as `ItemsTabView` from WP06).
5. Multi-select + `BulkSelectionBar` with same bulk operations (sell to project, reassign to project, delete). Note: inventory items don't have a source project, so "sell to project" is the primary sell flow.
6. Add button → `NewItemView` (stub for WP12).
7. `NavigationLink(value: item)` → `ItemDetailView`.

**Files**:
- `Views/Inventory/InventoryItemsSubTab.swift` (create, ~90 lines)

**Parallel?**: Yes — once T046 skeleton exists.

---

### Subtask T048 – Wire inventory Transactions sub-tab

**Purpose**: Transactions tab showing inventory-scoped transactions.

**Steps**:
1. Create `Views/Inventory/InventoryTransactionsSubTab.swift`.
2. Use `inventoryContext.transactions` as the data source.
3. Apply `TransactionListCalculations` for filter/sort/search.
4. Render using `SharedTransactionsList` (or `TransactionCard` list pattern from WP04).
5. Add button → `NewTransactionView` (stub for WP12).
6. `NavigationLink(value: transaction)` → `TransactionDetailView`.

**Files**:
- `Views/Inventory/InventoryTransactionsSubTab.swift` (create, ~70 lines)

**Parallel?**: Yes.

---

### Subtask T049 – Wire inventory Spaces sub-tab

**Purpose**: Spaces tab showing inventory storage locations.

**Steps**:
1. Create `Views/Inventory/InventorySpacesSubTab.swift`.
2. Use `inventoryContext.spaces` as the data source.
3. Apply `SpaceListCalculations.buildSpaceCards(spaces:items:)` using `inventoryContext.spaces` and `inventoryContext.items`.
4. Render space cards with name, item count, checklist progress.
5. Add button → `NewSpaceView` (stub for WP12) with inventory context.
6. `NavigationLink(value: space)` → `SpaceDetailView`.

**Files**:
- `Views/Inventory/InventorySpacesSubTab.swift` (create, ~60 lines)

**Parallel?**: Yes.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `InventoryPlaceholderView` referenced in multiple places | Grep for all references before replacing — update all call sites |
| Inventory items show project items | Verify `InventoryContext` subscription uses correct scope predicate (`projectId == nil`) |
| Multi-select bulk ops for inventory items have different actions | Items without `projectId` can't "sell to project" until a project is selected — confirm RN behavior |

---

## Review Guidance

- [ ] Inventory tab shows 3 sub-tabs; correct tab restored from UserDefaults.
- [ ] Items tab shows only inventory-scoped items (no project items visible).
- [ ] Full filter/sort/multi-select functionality works in Items sub-tab.
- [ ] Tapping an item navigates to `ItemDetailView`; back navigation returns to inventory.
- [ ] `activate`/`deactivate` lifecycle called correctly on tab appear/disappear.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
