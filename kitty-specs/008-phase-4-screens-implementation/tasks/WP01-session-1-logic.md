---
work_package_id: "WP01"
title: "Session 1 Logic – Project List + Budget Tab Calculations"
phase: "Phase 1 - Session 1"
lane: "for_review"
dependencies: ["WP00"]
subtasks:
  - "T005"
  - "T006"
  - "T007"
  - "T008"
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

# Work Package Prompt: WP01 – Session 1 Logic — Project List + Budget Tab Calculations

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- `ProjectListCalculations.swift` — pure function module for filtering, sorting, and searching the project list.
- `BudgetTabCalculations.swift` — pure function module for computing budget category rows with correct spend normalization, sorting, and labeling.
- All Swift Testing tests pass: correct alphabetical sort, active/archived filter, budget spend normalization, fee "received" label, pinned categories, overall budget exclusion.

**To start implementing:** `spec-kitty implement WP01 --base WP00`

---

## Context & Constraints

- **Refs**: `plan.md` (WP01), `spec.md` FR-1, FR-3, `data-model.md` (Project, BudgetCategory models).
- **Architecture**: Pure logic modules in `Logic/` — no SwiftUI, no Firestore calls, no side effects. Functions take data in, return computed data out.
- **Testing**: Swift Testing only (`@Test`, `#expect`, `@Suite`). Mirror RN test cases where they exist.
- **Budget category types**: `general`, `itemized`, `fee` (mutually exclusive strings in `BudgetCategory.type`).
- **Spend normalization rules** (FR-3.8 — EXACT):
  - `isCanceled=true` → contributes $0 to spend
  - `status=="returned"` OR negative `amountCents` → subtracts from spend
  - `isCanonicalInventorySale=true` AND `inventorySaleDirection==project_to_business` → subtracts
  - `isCanonicalInventorySale=true` AND `inventorySaleDirection==business_to_project` → adds
  - All others → adds to spend
- **Overall budget exclusion**: categories with `excludeFromOverallBudget=true` are displayed individually but excluded from the "Overall Budget" row aggregate.
- **Budget bar priority** (FR-1.3): (1) pinned categories in user-defined order, (2) top by spend%, (3) "Overall Budget" row if no category has any activity.

---

## Subtasks & Detailed Guidance

### Subtask T005 – Create `Logic/ProjectListCalculations.swift`

**Purpose**: All project list filtering, sorting, and search logic extracted from the view layer.

**Steps**:
1. Create `Logic/ProjectListCalculations.swift`.
2. Define `enum ProjectArchiveFilter { case active, archived }`.
3. Implement `func filterProjects(_ projects: [Project], filter: ProjectArchiveFilter, query: String) -> [Project]`:
   - Active filter: `project.isArchived != true`.
   - Archived filter: `project.isArchived == true`.
   - Query: case-insensitive substring match on `project.name ?? ""` OR `project.clientName ?? ""`.
   - Empty query: return all (after archive filter).
4. Implement `func sortProjects(_ projects: [Project]) -> [Project]`:
   - Alphabetical by `project.name?.lowercased() ?? ""`.
   - Projects with no name: sort by `project.id` (falls last alphabetically — empty string sorts first, but `id` is always present).
   - Case-insensitive: use `localizedCaseInsensitiveCompare`.
5. Implement `func projectEmptyStateText(for filter: ProjectArchiveFilter) -> String`:
   - `.active` → `"No active projects yet."`
   - `.archived` → `"No archived projects yet."`
6. Implement `func budgetBarCategories(categories: [BudgetCategory], budgetProgress: [BudgetProgressRow], pinnedCategoryIds: [String]) -> [BudgetCategory]`:
   - Returns ordered categories for the project card budget bar preview.
   - Priority: (1) pinned categories (in pinnedCategoryIds order), (2) remaining sorted by spend%, (3) append "Overall Budget" row if no category has spend activity.

**Files**:
- `Logic/ProjectListCalculations.swift` (create, ~80 lines)

**Parallel?**: Yes — independent of T006.

**Notes**:
- `Project.isArchived` may be `Bool?` — treat `nil` as not archived.
- `localizedCaseInsensitiveCompare` is the correct Swift sort for locale-aware alphabetical ordering.

---

### Subtask T006 – Create `Logic/BudgetTabCalculations.swift`

**Purpose**: All budget tab computation logic — which categories to show, how to sort them, how to compute spend, and how to label them.

**Steps**:
1. Create `Logic/BudgetTabCalculations.swift` (or extend existing if one exists — check first).
2. Define output types:
   ```swift
   struct BudgetCategoryRow {
       let category: BudgetCategory
       let spentCents: Int
       let budgetCents: Int
       let isOverBudget: Bool
       let spendLabel: String   // "spent" or "received" for fee categories
       let remainingLabel: String
   }
   ```
3. Implement `func computeSpend(for category: BudgetCategory, transactions: [Transaction]) -> Int`:
   - Apply normalization rules (see Context section above).
   - Filter to transactions with `budgetCategoryId == category.id`.
   - Sum cents per rule.
4. Implement `func enabledCategories(_ categories: [BudgetCategory], transactions: [Transaction]) -> [BudgetCategory]`:
   - Enabled = non-zero budget OR non-zero spend.
   - Excludes archived categories.
5. Implement `func sortedCategories(_ categories: [BudgetCategory]) -> [BudgetCategory]`:
   - Fee categories last (where `category.type == "fee"`).
   - Within fee and non-fee groups: alphabetical by name.
6. Implement `func buildBudgetRows(categories: [BudgetCategory], budgetAllocations: [BudgetAllocation], transactions: [Transaction]) -> [BudgetCategoryRow]`:
   - Only enabled categories.
   - Apply sort (T006 step 5).
   - For each: compute spend, budget amount, isOverBudget, spendLabel ("received" if `type=="fee"`, else "spent").
7. Implement `func overallBudgetRow(rows: [BudgetCategoryRow]) -> BudgetCategoryRow`:
   - Sum all rows where `category.excludeFromOverallBudget != true`.

**Files**:
- `Logic/BudgetTabCalculations.swift` (create or extend, ~120 lines)

**Parallel?**: Yes — independent of T005.

**Notes**:
- `BudgetAllocation` is the per-project allocation amount for each `BudgetCategory`. Check `Models/BudgetAllocation.swift` or equivalent.
- Canceled transactions: `transaction.isCanceled == true` → $0 contribution, regardless of amount.
- Returned transactions: check `transaction.status == "returned"` OR `transaction.amountCents ?? 0 < 0`.

---

### Subtask T007 – Write Swift Testing suite for ProjectListCalculations

**Purpose**: Verify all sort, filter, and search behaviors.

**Steps**:
1. Create `LedgeriOSTests/Logic/ProjectListCalculationsTests.swift`.
2. `@Suite struct ProjectListCalculationsTests`.
3. Test cases:
   - `@Test func sortsAlphabetically()`: "Zebra", "apple", "Mango" → ["apple", "Mango", "Zebra"] (case-insensitive).
   - `@Test func activeFilterExcludesArchived()`: mix of archived and active → only active returned.
   - `@Test func archivedFilterIncludesOnlyArchived()`.
   - `@Test func searchByProjectName()`: query "beach" matches "Beach House", not "Mountain Cabin".
   - `@Test func searchByClientName()`: query "smith" matches project with clientName "Smith Family".
   - `@Test func emptyQueryReturnsAll()`.
   - `@Test func projectWithNoNameSortsByID()`.
   - `@Test func emptyStateTextActive()`: expects "No active projects yet."
   - `@Test func emptyStateTextArchived()`: expects "No archived projects yet."

**Files**:
- `LedgeriOSTests/Logic/ProjectListCalculationsTests.swift` (create, ~90 lines)

**Parallel?**: No — depends on T005.

---

### Subtask T008 – Write Swift Testing suite for BudgetTabCalculations

**Purpose**: Verify spend normalization, sorting, fee labels, and overall budget exclusion.

**Steps**:
1. Create `LedgeriOSTests/Logic/BudgetTabCalculationsTests.swift`.
2. `@Suite struct BudgetTabCalculationsTests`.
3. Test cases:
   - `@Test func canceledTransactionContributesZero()`: `isCanceled=true`, amount=$100 → spend=$0.
   - `@Test func returnedTransactionSubtracts()`: `status="returned"`, amount=-$50 → spend contributes -$50.
   - `@Test func canonicalSaleProjectToBusinessSubtracts()`: `isCanonicalInventorySale=true`, `inventorySaleDirection=project_to_business` → negative spend.
   - `@Test func canonicalSaleBusinessToProjectAdds()`.
   - `@Test func feeCategoryLabelIsReceived()`: `type="fee"` → `spendLabel == "received"`.
   - `@Test func generalCategoryLabelIsSpent()`: `type="general"` → `spendLabel == "spent"`.
   - `@Test func feeCategoriesSortLast()`: mix of fee and general → fee categories at end.
   - `@Test func overallBudgetExcludesExcludedCategories()`: category with `excludeFromOverallBudget=true` not in overall total.
   - `@Test func overallBudgetIncludesNonExcludedCategories()`.
   - `@Test func enabledCategoryFilter()`: category with zero budget AND zero spend → excluded.

**Files**:
- `LedgeriOSTests/Logic/BudgetTabCalculationsTests.swift` (create, ~120 lines)

**Parallel?**: No — depends on T006.

---

## Test Strategy

All tests use **Swift Testing** (`@Test`, `#expect`, `@Suite`) — NOT XCTest.

Create in-memory test fixtures (no Firestore needed — pure functions only).

Run: ⌘U in Xcode or `xcodebuild test -scheme LedgeriOS`.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `BudgetTabCalculations.swift` already exists (partial) | Check first; extend rather than replace. Keep existing behavior if it passes tests |
| Spend normalization edge cases (canonical sale with nil direction) | Treat `inventorySaleDirection == nil` on `isCanonicalInventorySale=true` as "adds" (safe default) |
| `BudgetAllocation` model shape unknown | Check existing models — may be embedded in `Project` or a separate collection |

---

## Review Guidance

- [ ] All sort, filter, and search behaviors match the spec (FR-1.1–FR-1.5).
- [ ] All 10 spend normalization combinations covered in tests.
- [ ] Fee categories labeled "received" (not "spent").
- [ ] Overall budget excludes `excludeFromOverallBudget=true` categories.
- [ ] No SwiftUI imports or Firestore calls in logic files.
- [ ] All tests pass with ⌘U.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-02-27T21:54:23Z – unknown – lane=doing – Starting implementation - agent: claude-opus
- 2026-02-27T22:19:37Z – unknown – lane=for_review – Ready for review: ProjectListCalculations + BudgetTabCalculations pure logic with 57 tests, all 300 tests passing
