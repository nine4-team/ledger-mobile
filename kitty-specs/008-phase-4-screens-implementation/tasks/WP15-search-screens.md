---
work_package_id: WP15
title: Session 7b Screens – Universal Search
lane: "doing"
dependencies:
- WP14
base_branch: 008-phase-4-screens-implementation-WP14
base_commit: 940e7822b73dabe187574111731d7b36f0923db0
created_at: '2026-03-01T00:01:56.534836+00:00'
subtasks:
- T068
- T069
- T070
phase: Phase 7 - Session 7b
assignee: ''
agent: "claude-opus"
shell_pid: "88807"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T22:30:00Z'
  lane: planned
  agent: system
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP15 – Session 7b Screens — Universal Search

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- `UniversalSearchView` replaces `SearchPlaceholderView.swift`.
- Search bar auto-focuses on mount.
- Initial state: centered search icon + "Start typing to search".
- 3 result tabs with result counts.
- Debounce ~400ms.
- Per-tab empty states: "No items found", "No transactions found", "No spaces found".
- Tapping a result navigates to the correct detail screen.

**To start implementing:** `spec-kitty implement WP15 --base WP14`

---

## Context & Constraints

- **Refs**: `plan.md` (WP15), `spec.md` FR-13.
- **Data scope**: search across ALL data the user has access to — all projects' items/transactions/spaces + inventory. This may require `AccountContext` to expose a cross-project data feed or querying across all project contexts. Think carefully about the data source.
- **Debounce**: use Combine's `Publisher` or a Swift Concurrency approach. Target: ~400ms.
- **Auto-focus**: `@FocusState private var searchFocused: Bool = false` → `.focused($searchFocused)` on search field → `.onAppear { searchFocused = true }`.
- **Initial state** (before typing): centered `Image(systemName: "magnifyingglass")` at large size + `Text("Start typing to search")` below it.
- **Exact no-results strings** (FR-13.1): "No items found", "No transactions found", "No spaces found".
- **Per-entity result counts** in tab labels: "Items (42)", "Transactions (3)", "Spaces (0)".
- **Navigation**: Search tab has its own `NavigationStack` (from Phase 3). Use `NavigationLink(value:)` + `.navigationDestination(for:)` for each entity type.

---

## Subtasks & Detailed Guidance

### Subtask T068 – Create `Views/Search/UniversalSearchView.swift`

**Purpose**: The main search screen shell with search bar, initial state, debounce, and 3 result tabs.

**Steps**:
1. Create `Views/Search/UniversalSearchView.swift`.
2. State:
   ```swift
   @FocusState private var searchFocused: Bool
   @State private var query: String = ""
   @State private var debouncedQuery: String = ""
   @State private var selectedTab: Int = 0
   ```
3. Debounce implementation:
   ```swift
   // Option A: Combine
   @State private var querySubject = PassthroughSubject<String, Never>()
   // In .onAppear: querySubject.debounce(for: .milliseconds(400), scheduler: RunLoop.main)
   //              .assign(to: &$debouncedQuery)

   // Option B: Swift Concurrency
   // In .onChange(of: query): cancel previous task, start new Task { try await Task.sleep(for: .milliseconds(400)); debouncedQuery = query }
   ```
   Choose one approach; Combine is simpler for this use case.
4. Search bar: use SwiftUI `TextField` styled as a search bar (with magnifying glass icon + clear button). Set `.focused($searchFocused)`.
5. `.onAppear { searchFocused = true }`.
6. **Initial state** (when `query.isEmpty`):
   ```swift
   VStack(spacing: Spacing.md) {
       Image(systemName: "magnifyingglass")
           .font(.largeTitle)
           .foregroundStyle(BrandColors.textSecondary)
       Text("Start typing to search")
           .font(Typography.body)
           .foregroundStyle(BrandColors.textSecondary)
   }
   .frame(maxWidth: .infinity, maxHeight: .infinity)
   ```
7. **Results state** (when `!debouncedQuery.isEmpty`):
   - `ScrollableTabBar` with 3 tabs including result counts.
   - Tab content: T069.

**Files**:
- `Views/Search/UniversalSearchView.swift` (create, ~120 lines)

---

### Subtask T069 – Wire search results

**Purpose**: Connect `SearchCalculations.search()` to the search UI with the correct data source.

**Steps**:
1. Determine data source for universal search. Options:
   - **Simple**: use current `ProjectContext.items/transactions/spaces` (only current project — limited).
   - **Better**: maintain a cross-project data subscription in `AccountContext` with all items/transactions/spaces the user has access to.
   - **Recommended**: Add `AccountContext.allItems: [Item]`, `allTransactions: [Transaction]`, `allSpaces: [Space]` subscriptions (account-scoped, no project filter). Check if `AccountContext` already does this or add it.
2. In `UniversalSearchView`, read `accountContext.allItems`, `.allTransactions`, `.allSpaces`, `.budgetCategories`.
3. On `debouncedQuery` change: call `SearchCalculations.search(query:items:transactions:spaces:categories:)` → store result in `@State var searchResults: SearchResults`.
4. For each tab:
   - Items tab: `ForEach(searchResults.items)` using `ItemCard` components.
   - Transactions tab: `ForEach(searchResults.transactions)` using `TransactionCard` components.
   - Spaces tab: `ForEach(searchResults.spaces)` using space card rows.
5. Per-tab counts: update tab labels with result counts.
6. Per-tab empty states: show exact text when tab is selected and results are empty.

**Files**:
- `Views/Search/UniversalSearchView.swift` (modify T068 skeleton)
- `State/AccountContext.swift` (may need to add cross-project subscriptions)

---

### Subtask T070 – Wire result navigation

**Purpose**: Tapping a search result navigates to the correct detail screen.

**Steps**:
1. In `UniversalSearchView`, add `.navigationDestination(for: Item.self)` → `ItemDetailView`.
2. Add `.navigationDestination(for: Transaction.self)` → `TransactionDetailView`.
3. Add `.navigationDestination(for: Space.self)` → `SpaceDetailView`.
4. Wrap each result card in `NavigationLink(value: entity)`:
   ```swift
   NavigationLink(value: item) {
       ItemCard(item: item, ...)
   }
   ```
5. Confirm back navigation from detail views returns to search with query preserved.

**Files**:
- `Views/Search/UniversalSearchView.swift` (modify)

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Cross-project data not available in `AccountContext` | Add account-scoped subscriptions to `AccountContext`; this is a small addition |
| Auto-focus not working on iOS | Use `.onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { searchFocused = true } }` (slight delay sometimes needed) |
| Debounce cancellation of previous task (Swift Concurrency approach) | Use `@State private var debounceTask: Task<Void, Never>? = nil`; cancel before starting new |
| Large datasets causing search lag | `SearchCalculations.search()` is synchronous — run on background queue if >500ms: use `Task { await MainActor.run { searchResults = ... } }` |

---

## Review Guidance

- [ ] Search bar auto-focuses on screen mount.
- [ ] Initial state (empty query): search icon + "Start typing to search" centered.
- [ ] Debounce: rapid typing doesn't cause excessive search calls.
- [ ] Result tabs show counts: "Items (42)", "Transactions (3)", "Spaces (0)".
- [ ] Per-tab empty states show exact strings from FR-13.1.
- [ ] Tapping an item navigates to `ItemDetailView`; back returns to search with query preserved.
- [ ] Amount search: type "40" → transactions with amountCents in 4000...4099 appear.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-03-01T00:01:56Z – claude-opus – shell_pid=88807 – lane=doing – Assigned agent via workflow command
