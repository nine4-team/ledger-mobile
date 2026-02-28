---
work_package_id: WP09
title: Session 5 Logic – Inventory Context
lane: "done"
dependencies: [WP08]
base_branch: 008-phase-4-screens-implementation-WP08
base_commit: 8dd0f94c525a7425ca5e49f0647c6dc69b979705
created_at: '2026-02-28T23:08:55.359206+00:00'
subtasks:
- T043
- T044
- T045
phase: Phase 5 - Session 5
assignee: ''
agent: "claude-opus"
shell_pid: "85231"
review_status: "approved"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-26T22:30:00Z'
  lane: planned
  agent: system
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP09 – Session 5 Logic — Inventory Context

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- `InventoryContext` is a `@MainActor @Observable` class with `activate(accountId:)` / `deactivate()` lifecycle.
- Three Firestore subscriptions scoped to business inventory (no project filter).
- `lastSelectedTab` persists to `UserDefaults("inventorySelectedTab")`.
- No project-scoped data bleeds into inventory subscriptions.
- Injected into the app environment alongside existing contexts.

**To start implementing:** `spec-kitty implement WP09 --base WP08`

---

## Context & Constraints

- **Refs**: `plan.md` (WP09), `spec.md` FR-10, `data-model.md` (InventoryContext section).
- **Pattern**: Mirror `ProjectContext` exactly (`State/ProjectContext.swift`). Read it first as the implementation blueprint.
- **Inventory scope**: items/transactions/spaces where `projectId == nil` (business-owned, not allocated to a project). Verify the existing service APIs support this scope enum — check `ItemsService`, `TransactionsService`, `SpacesService` for `.inventory` scope support.
- **UserDefaults key**: `"inventorySelectedTab"` (String).
- **Architecture**: `@MainActor @Observable final class InventoryContext` in `State/InventoryContext.swift`.
- **Environment injection**: `.environment(inventoryContext)` on the root view — coordinate with `LedgerApp.swift` or `RootView.swift`.

---

## Subtasks & Detailed Guidance

### Subtask T043 – Create `State/InventoryContext.swift`

**Purpose**: State manager for inventory-scoped data, mirroring `ProjectContext` for the Inventory tab.

**Steps**:
1. Create `State/InventoryContext.swift`.
2. Declare `@MainActor @Observable final class InventoryContext`.
3. State properties:
   ```swift
   var items: [Item] = []
   var transactions: [Transaction] = []
   var spaces: [Space] = []
   var lastSelectedTab: Int {
       get { UserDefaults.standard.integer(forKey: "inventorySelectedTab") }
       set { UserDefaults.standard.set(newValue, forKey: "inventorySelectedTab") }
   }
   private var itemsListener: ListenerRegistration?
   private var transactionsListener: ListenerRegistration?
   private var spacesListener: ListenerRegistration?
   ```
4. Implement `func activate(accountId: String)`:
   - Call `ItemsService.subscribe(accountId: accountId, scope: .inventory)` → listener → `self.items = newItems`.
   - Call `TransactionsService.subscribe(accountId: accountId, scope: .inventory)` → listener → `self.transactions = newTransactions`.
   - Call `SpacesService.subscribe(accountId: accountId, scope: .inventory)` → listener → `self.spaces = newSpaces`.
   - Check the exact service method signatures — adapt to what exists.
5. Implement `func deactivate()`:
   - Remove all 3 listeners.
   - Reset `items = []`, `transactions = []`, `spaces = []`.

**Files**:
- `State/InventoryContext.swift` (create, ~80 lines)

**Parallel?**: No — sequential.

**Notes**:
- If services don't have an `.inventory` scope, check how to query Firestore directly: `items` collection where `projectId` field is `null`. Add scope support to the service if needed.
- `ListenerRegistration` must be removed in `deactivate()` to prevent memory leaks.

---

### Subtask T044 – Inject InventoryContext into app environment

**Purpose**: Make `InventoryContext` available throughout the app via SwiftUI environment.

**Steps**:
1. Open `LedgerApp.swift` (or wherever `RootView` is instantiated — check `App/LedgerApp.swift`).
2. Create a `@State private var inventoryContext = InventoryContext()` alongside existing contexts.
3. Add `.environment(inventoryContext)` to the root view chain.
4. In `InventoryView` (WP10), add `@Environment(InventoryContext.self) private var inventoryContext`.
5. Call `inventoryContext.activate(accountId: authManager.accountId)` in `InventoryView.onAppear` and `deactivate()` in `onDisappear`.

**Files**:
- `App/LedgerApp.swift` or `Views/RootView.swift` (modify — add environment injection)

**Parallel?**: No — depends on T043.

---

### Subtask T045 – Write Swift Testing suite for InventoryContext

**Purpose**: Verify scope filtering and UserDefaults persistence.

**Steps**:
1. Create `LedgeriOSTests/State/InventoryContextTests.swift`.
2. `@Test func userDefaultsTabPersists()`:
   - Create `InventoryContext`.
   - Set `inventoryContext.lastSelectedTab = 2`.
   - Create new `InventoryContext` instance.
   - `#expect(new.lastSelectedTab == 2)`.
3. `@Test func activateSubscribesToInventoryScope()` (if testable without Firestore — may need mock):
   - Verify activate calls services with `.inventory` scope parameter.
4. `@Test func deactivateResetsState()`:
   - Set `items = [/* fake item */]`.
   - Call `deactivate()`.
   - `#expect(items.isEmpty)`.

**Files**:
- `LedgeriOSTests/State/InventoryContextTests.swift` (create, ~60 lines)

**Parallel?**: Yes — can start alongside T044.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Services don't support `.inventory` scope | Add scope parameter to service methods; filter by `projectId == nil` |
| `activate()` called multiple times before `deactivate()` | Guard: check if already active, remove existing listeners before adding new ones |
| UserDefaults key collisions | Use namespaced key: `"inventorySelectedTab"` — check for conflicts with existing keys |

---

## Review Guidance

- [ ] `InventoryContext` matches `ProjectContext` pattern exactly (same lifecycle).
- [ ] `activate()` sets up 3 subscriptions scoped to inventory only.
- [ ] `deactivate()` removes all 3 listeners and resets state.
- [ ] `lastSelectedTab` persists across `InventoryContext` instance recreations.
- [ ] Injected into app environment — no crashes when `@Environment(InventoryContext.self)` is used.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-02-27T22:35:24Z – claude-opus – shell_pid=69112 – lane=doing – Assigned agent via workflow command
- 2026-02-27T22:39:30Z – claude-opus – shell_pid=69112 – lane=planned – Unwinding: must follow dependency chain (WP07 → WP08 → WP09)
- 2026-02-28T23:19:03Z – claude-opus – shell_pid=44779 – lane=for_review – Ready for review: InventoryContext with 3 subscriptions (.inventory scope), UserDefaults tab persistence, environment injection, and 4 passing tests
- 2026-02-28T23:21:26Z – claude-opus – shell_pid=85231 – lane=doing – Started review via workflow command
- 2026-02-28T23:22:51Z – claude-opus – shell_pid=85231 – lane=done – Review passed: InventoryContext matches ProjectContext pattern exactly — @MainActor @Observable with protocol-based DI, 3 inventory-scoped subscriptions, UserDefaults tab persistence, environment injection in LedgerApp, and 4 passing Swift Testing tests. Clean 63-line implementation. All success criteria met.
