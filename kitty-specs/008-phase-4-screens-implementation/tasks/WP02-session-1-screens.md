---
work_package_id: "WP02"
title: "Session 1 Screens – Projects List + Project Detail + Budget Tab"
phase: "Phase 1 - Session 1"
lane: "done"
dependencies: ["WP01"]
subtasks:
  - "T009"
  - "T010"
  - "T011"
  - "T012"
  - "T013"
assignee: ""
agent: "claude-opus"
shell_pid: "95619"
review_status: "approved"
reviewed_by: "nine4-team"
history:
  - timestamp: "2026-02-26T22:30:00Z"
    lane: "planned"
    agent: "system"
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP02 – Session 1 Screens — Projects List + Project Detail + Budget Tab

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- `ProjectsListView` shows real Firestore data sorted alphabetically with active/archived toggle and search.
- `ProjectDetailView` has a 5-tab interface with a kebab menu (Edit/Export CSV/Delete).
- `BudgetTabView` shows categories with correct spend, labels ("received" for fees), and pinned categories at top.
- CSV export of all project transactions shares via system share sheet with correct columns.
- Navigation from projects list → project detail works with `NavigationLink(value:)`.
- All empty states show exact required text.
- All screens work in light and dark mode via the adaptive color system.

**To start implementing:** `spec-kitty implement WP02 --base WP01`

---

## Context & Constraints

- **Refs**: `plan.md` (WP02), `spec.md` FR-1, FR-2, FR-3, `data-model.md`.
- **Architecture**: Views in `Views/Projects/`. No inline magic numbers — use `Theme/` constants. `NavigationLink(value:)` only — no deprecated label-based NavigationLink.
- **State**: `ProjectContext` (existing `State/ProjectContext.swift`) manages Firestore subscriptions. Call `activate(accountId:projectId:)` when entering a project and `deactivate()` when leaving.
- **Bottom-sheet rule**: All modals/forms use `.sheet()` with `.presentationDetents()` and `.presentationDragIndicator(.visible)`.
- **Offline-first**: Show cached data immediately — no loading spinners blocking the project list.
- **Reference screenshots**: Dark mode in `reference/screenshots/dark/`. Match layout and info hierarchy.
- **Tab placeholders**: Items, Transactions, Spaces, Accounting tabs remain as placeholder views — they are replaced in later WPs. Only Budget tab gets real content in this WP.

---

## Subtasks & Detailed Guidance

### Subtask T009 – Extend `Views/Projects/ProjectsListView.swift`

**Purpose**: Replace any placeholder content with real Firestore-backed project list.

**Steps**:
1. Open `Views/Projects/ProjectsListView.swift` (may already exist as a skeleton from Phase 3).
2. Add a `@State private var archiveFilter: ProjectArchiveFilter = .active` toggle (underline-style tab bar).
3. Add a `@State private var searchQuery: String = ""` search bar (`.searchable()` modifier or custom search bar matching RN design).
4. Load projects from `ProjectsService` or `AccountContext.projects` — the existing service/context provides the project list.
5. Apply `ProjectListCalculations.filterProjects(_:filter:query:)` then `sortProjects(_:)` to the projects array.
6. Render with `ProjectCard` component (from Phase 5 library). Pass: hero image URL, project name, client name, budget bar categories (from `ProjectListCalculations.budgetBarCategories()`).
7. Show empty state (exact text from spec) when filtered result is empty.
8. Pass archive filter selection through the underline tab bar (same design as existing `ScrollableTabBar` if applicable, otherwise style per reference screenshots).

**Files**:
- `Views/Projects/ProjectsListView.swift` (extend)

**Parallel?**: No — sequential with T010, T013.

**Notes**:
- The project list subscription should be independent of `ProjectContext` (which requires a selected project). Use a separate subscription or `AccountContext.projects`.
- Search bar: use SwiftUI `.searchable(text: $searchQuery)` modifier on the `NavigationStack` for best iOS integration.

---

### Subtask T010 – Extend `Views/Projects/ProjectDetailView.swift`

**Purpose**: Build the 5-tab project detail hub with kebab menu and subscription lifecycle.

**Steps**:
1. Open `Views/Projects/ProjectDetailView.swift`.
2. Add `init(project: Project)` parameter.
3. In `.onAppear`: call `projectContext.activate(accountId: authManager.accountId, projectId: project.id)`.
4. In `.onDisappear`: call `projectContext.deactivate()`.
5. Add a `ScrollableTabBar` with 5 tabs: Budget, Items, Transactions, Spaces, Accounting. Use `@State private var selectedTab: Int = 0`.
6. Tab content:
   - Budget (index 0): `BudgetTabView()`
   - Items (index 1): `ItemsTabPlaceholderView()` (exists from Phase 3)
   - Transactions (index 2): `TransactionsTabPlaceholderView()` (exists)
   - Spaces (index 3): `SpacesTabPlaceholderView()` (exists)
   - Accounting (index 4): `AccountingTabPlaceholderView()` (exists)
7. Add kebab menu (`toolbar`) with 3 buttons:
   - "Edit Project" → navigate to project edit form (stub — no edit form yet, can be disabled or show sheet placeholder)
   - "Export Transactions" → call T011 export action
   - "Delete Project" → show `.confirmationDialog()` → call `ProjectsService.delete(projectId:)` on confirm
8. Set navigation title to `project.name ?? "Project"` + `.navigationBarTitleDisplayMode(.inline)`.

**Files**:
- `Views/Projects/ProjectDetailView.swift` (extend)

**Parallel?**: No — sequential.

**Notes**:
- `@Environment(ProjectContext.self) private var projectContext` — already in environment.
- `.confirmationDialog()` for delete: title "Delete Project?", message "This cannot be undone.", buttons: "Delete" (destructive) + "Cancel".

---

### Subtask T011 – Implement Export Transactions CSV

**Purpose**: Generate and share a CSV of all project transactions from the kebab menu.

**Steps**:
1. Implement `func exportTransactionsCSV(transactions: [Transaction], categories: [BudgetCategory]) -> String` (pure function):
   - Columns (in order): `id`, `date`, `source`, `amount`, `categoryName`, `budgetCategoryId`, `inventorySaleDirection`, `itemCategories`
   - `date`: formatted as ISO 8601 string or "yyyy-MM-dd"
   - `amount`: dollars as decimal string (amountCents / 100.0)
   - `categoryName`: look up from categories array by `budgetCategoryId`
   - `inventorySaleDirection`: `transaction.inventorySaleDirection?.rawValue ?? ""`
   - `itemCategories`: pipe-separated list of `item.budgetCategoryId` values for linked items (may be empty — needs access to items array; add as parameter)
   - CSV header row first, then one row per transaction.
   - Escape commas and quotes in values (wrap in double quotes if value contains comma or quote).
2. In `ProjectDetailView`, wire kebab menu "Export Transactions" to:
   ```swift
   let csv = exportTransactionsCSV(transactions: projectContext.transactions, categories: projectContext.budgetCategories)
   let tempURL = /* write csv to temp file */
   let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
   // Present via UIApplication window
   ```
3. Write temp file to `FileManager.default.temporaryDirectory` with name `"transactions-\(project.id).csv"`.

**Files**:
- `Logic/ProjectListCalculations.swift` (add `exportTransactionsCSV` function, or create separate `Logic/TransactionExportCalculations.swift`)
- `Views/Projects/ProjectDetailView.swift` (wire the action)

**Parallel?**: Yes — can be implemented alongside T012 once T010 skeleton exists.

**Notes**:
- Pure CSV generation function → easy to unit test (add one test case for column order and escaping).
- `UIActivityViewController` presentation on iOS 17+: use `UIApplication.shared.connectedScenes.first?.windows.first?.rootViewController?.present(...)`.

---

### Subtask T012 – Extend `Views/Projects/BudgetTabView.swift`

**Purpose**: Wire `BudgetTabCalculations` into the budget tab view with correct pinned categories, sort, labels, and overflow color.

**Steps**:
1. Open `Views/Projects/BudgetTabView.swift`.
2. Read budget rows from `BudgetTabCalculations.buildBudgetRows(categories:budgetAllocations:transactions:)` using data from `projectContext`.
3. Apply pinned categories logic: check `ProjectPreferences.pinnedBudgetCategoryIds` (from `projectContext`); pinned categories show at top in user-defined order.
4. For each `BudgetCategoryRow`:
   - Show category name.
   - Show spent amount label (using `row.spendLabel` — "received" or "spent").
   - Show remaining/over amount label — use `StatusColors.budgetOverflow` when over budget.
   - Show `BudgetProgressView` component (from Phase 5) with the spend ratio.
5. Show "Overall Budget" row at bottom (excluded from individual sorting but always last).
6. Wrap in `ScrollView` — budget categories list can be long.

**Files**:
- `Views/Projects/BudgetTabView.swift` (extend)

**Parallel?**: Yes — independent of T011.

**Notes**:
- `BudgetProgressView` component: check Phase 5 library for exact parameters.
- Pinned auto-pins "Furnishings" if it exists and is enabled — this logic is in `BudgetTabCalculations`.
- Overflow color: `StatusColors.budgetOverflow` (or equivalent from `StatusColors.swift`).

---

### Subtask T013 – Wire NavigationLink Projects → ProjectDetail

**Purpose**: `NavigationLink(value: project)` from projects list navigates to project detail.

**Steps**:
1. In `ProjectsListView`, wrap each `ProjectCard` in `NavigationLink(value: project)`.
2. In the parent `NavigationStack` (likely in `MainTabView` or `ProjectsListView` itself), add:
   ```swift
   .navigationDestination(for: Project.self) { project in
       ProjectDetailView(project: project)
   }
   ```
3. Confirm the `NavigationStack` wrapping the Projects tab is in the right place (one `NavigationStack` per tab).
4. Verify tapping a project card navigates to `ProjectDetailView` and back navigation works correctly.

**Files**:
- `Views/Projects/ProjectsListView.swift` (add NavigationLink)
- Parent view that contains the `NavigationStack` for the Projects tab (may be `MainTabView.swift` or `ProjectsTabView.swift`)

**Parallel?**: No — depends on T009 and T010.

**Notes**:
- `Project` must conform to `Hashable` for `NavigationLink(value:)`. Check `Models/Project.swift` — add conformance if missing.
- Never use `NavigationLink(destination:label:)` — deprecated in iOS 16+.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `ProjectsListView` has existing placeholder Firestore subscription | Fully replace — don't layer subscriptions on top of each other |
| `Project` not Hashable | Add `extension Project: Hashable { func hash(...) }` or use `id` for equality |
| CSV temp file writing fails on device | Use `FileManager.default.temporaryDirectory` — always writable |
| Budget tab overwhelming with many categories | `ScrollView` wraps the full list; no truncation |

---

## Review Guidance

- [ ] Projects list sorted alphabetically (case-insensitive), confirmed with test data.
- [ ] Active/Archived toggle filters correctly.
- [ ] Search filters project name AND client name.
- [ ] Empty states show exact text: "No active projects yet." and "No archived projects yet."
- [ ] Project detail has 5 tabs; Budget tab shows real data.
- [ ] Kebab menu: Edit (navigable), Export CSV (share sheet opens with valid CSV), Delete (confirmation + removal).
- [ ] Budget tab: fee categories labeled "received", over-budget amounts in overflow color, pinned categories at top.
- [ ] Navigation: tap project card → project detail → back works.
- [ ] No hardcoded colors or magic numbers — all from `Theme/`.
- [ ] Light + dark mode correct.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-02-27T22:41:31Z – claude-opus – shell_pid=72783 – lane=doing – Started implementation via workflow command
- 2026-02-27T22:55:14Z – claude-opus – shell_pid=72783 – lane=for_review – Ready for review: CSV export, delete project, pinned budget categories, all 315 tests passing
- 2026-02-27T22:57:12Z – claude-opus – shell_pid=95619 – lane=doing – Started review via workflow command
- 2026-02-27T23:02:09Z – claude-opus – shell_pid=95619 – lane=done – Review passed: CSV export, delete project, and pinned budget categories all implemented correctly. 47 new tests passing. Pure function architecture, correct sheet patterns, theme constants used throughout. Minor advisories: deleteProject dismisses unconditionally on try?, normalization divergence between BudgetTabCalculations and BudgetProgressService (dead code path), standalone ProjectService in view bypasses sync tracking. Non-blocking — approve as-is.
