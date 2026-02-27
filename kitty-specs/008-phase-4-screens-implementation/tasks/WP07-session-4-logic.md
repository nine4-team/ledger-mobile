---
work_package_id: "WP07"
title: "Session 4 Logic – Space List + Space Detail Calculations"
phase: "Phase 4 - Session 4"
lane: "planned"
dependencies: ["WP06"]
subtasks:
  - "T036"
  - "T037"
  - "T038"
assignee: ""
agent: ""
shell_pid: ""
review_status: ""
reviewed_by: ""
history:
  - timestamp: "2026-02-26T22:30:00Z"
    lane: "planned"
    agent: "system"
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP07 – Session 4 Logic — Space List + Space Detail Calculations

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- `SpaceListCalculations`: correct checklist progress (X of Y complete), alphabetical sort, name search.
- `SpaceDetailCalculations`: role-gated "Save as Template" (owner/admin only); item grouping by `spaceId`.
- All Swift Testing tests pass: edge cases (0/0, 0/N, N/N, partial), role gate, item grouping.

**To start implementing:** `spec-kitty implement WP07 --base WP06`

---

## Context & Constraints

- **Refs**: `plan.md` (WP07), `spec.md` FR-9.
- **`ChecklistItem.isChecked`** — use this field name (NOT `isCompleted` — confirmed in data-model.md).
- **Checklist progress**: sum `isChecked=true` across ALL checklists for a space, divided by total checklist items.
- **Role values**: `"owner"`, `"admin"`, `"member"`. Save as Template: owner + admin only.
- **Space detail items**: full 10 project-scope filter modes (FR-9.10) — same as `ItemListCalculations.applyFilters()`.
- **Architecture**: Pure logic files in `Logic/`. No SwiftUI, no Firestore.

---

## Subtasks & Detailed Guidance

### Subtask T036 – Create `Logic/SpaceListCalculations.swift`

**Purpose**: Filtering, sorting, search, and progress computation for the spaces list.

**Steps**:
1. Create `Logic/SpaceListCalculations.swift`.
2. Define:
   ```swift
   struct SpaceCardData {
       let space: Space
       let itemCount: Int
       let checklistProgress: ChecklistProgress
   }
   struct ChecklistProgress {
       let completed: Int
       let total: Int
       var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
       var displayText: String { "\(completed) of \(total)" }
   }
   ```
3. Implement `func computeChecklistProgress(for space: Space) -> ChecklistProgress`:
   - Total = sum of `space.checklists?.flatMap(\.items).count ?? 0`.
   - Completed = sum of `space.checklists?.flatMap(\.items).filter(\.isChecked).count ?? 0`.
   - 0/0 → `ChecklistProgress(completed: 0, total: 0)` (display "0 of 0" or hide).
4. Implement `func buildSpaceCards(spaces: [Space], items: [Item]) -> [SpaceCardData]`:
   - For each space: compute itemCount (`items.filter { $0.spaceId == space.id }.count`) and checklistProgress.
5. Implement `func applySearch(spaces: [SpaceCardData], query: String) -> [SpaceCardData]`:
   - Case-insensitive substring on `space.name`.
6. Implement `func sortSpaces(_ spaces: [SpaceCardData]) -> [SpaceCardData]`:
   - Alphabetical by `space.name?.lowercased() ?? ""`.

**Files**:
- `Logic/SpaceListCalculations.swift` (create, ~80 lines)

**Parallel?**: Yes — independent of T037.

---

### Subtask T037 – Create `Logic/SpaceDetailCalculations.swift`

**Purpose**: Role-gated template save and item grouping for space detail.

**Steps**:
1. Create `Logic/SpaceDetailCalculations.swift`.
2. Implement `func canSaveAsTemplate(userRole: String) -> Bool`:
   - Returns `true` if `userRole == "owner" || userRole == "admin"`.
3. Implement `func itemsInSpace(spaceId: String, allItems: [Item]) -> [Item]`:
   - Returns `allItems.filter { $0.spaceId == spaceId }`.
4. Implement `func checklistProgress(for space: Space) -> ChecklistProgress`:
   - Same logic as `SpaceListCalculations.computeChecklistProgress()` — DRY: extract to a shared internal function or call SpaceListCalculations.
5. Implement `func defaultSectionStates() -> [String: Bool]`:
   - Returns: `["media": true, "notes": false, "items": false, "checklists": false]` (expanded/collapsed defaults per FR-9.3).

**Files**:
- `Logic/SpaceDetailCalculations.swift` (create, ~60 lines)

**Parallel?**: Yes.

---

### Subtask T038 – Write Swift Testing suite for space logic modules

**Purpose**: Verify progress computation, role gate, and item grouping.

**Steps**:
1. Create `LedgeriOSTests/Logic/SpaceListCalculationsTests.swift`:
   - `@Test func progressZeroItems()`: space with empty checklists → 0/0.
   - `@Test func progressAllIncomplete()`: 3 items, all `isChecked=false` → 0/3.
   - `@Test func progressAllComplete()`: 3 items, all `isChecked=true` → 3/3.
   - `@Test func progressPartial()`: 2 of 4 complete → 2/4.
   - `@Test func progressAcrossMultipleChecklists()`: 2 checklists with 2 items each, 3 complete → 3/4.
   - `@Test func itemCountBySpaceId()`.
   - `@Test func searchBySpaceName()`.
2. Create `LedgeriOSTests/Logic/SpaceDetailCalculationsTests.swift`:
   - `@Test func ownerCanSaveAsTemplate()`.
   - `@Test func adminCanSaveAsTemplate()`.
   - `@Test func memberCannotSaveAsTemplate()`.
   - `@Test func itemsInSpaceFiltersCorrectly()`.

**Files**:
- 2 test files in `LedgeriOSTests/Logic/` (create, ~70 lines each)

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `ChecklistItem.isChecked` vs `isCompleted` naming | Use `isChecked` — confirmed in data-model.md |
| DRY violation between SpaceList and SpaceDetail progress logic | Extract to a shared internal function or extension |

---

## Review Guidance

- [ ] Checklist progress handles 0/0 correctly (no divide-by-zero).
- [ ] Role gate: owner + admin pass, member fails.
- [ ] All test cases for progress edge cases pass.
- [ ] No SwiftUI/Firestore imports.
- [ ] All tests pass ⌘U.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
