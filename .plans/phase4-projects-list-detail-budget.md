# Phase 4: Projects List + Project Detail Hub + Budget Tab

## Context

Phase 4 is the screen implementation phase of the SwiftUI migration. The data layer (models, services, state managers) and navigation shell (tabs, auth gate, account selection) are complete. This plan covers the first batch of Phase 4 screens: browse projects → tap into project detail → view budget breakdown with real Firestore data. Other project tabs (Items, Transactions, Spaces, Accounting) render as placeholders to be built next.

## Scope

**Build:** Projects List, Project Detail Hub (5-tab shell), Budget Tab (fully functional)
**Defer:** Items/Transactions/Spaces/Accounting tab content, creation flows, search, settings, inventory

## Implementation Order

```
1. Pure logic + tests (no dependencies)
2. New components: ScrollableTabBar, ProjectCard
3. Screens: ProjectsListView, ProjectDetailView, BudgetTabView, 4 tab placeholders
4. Navigation wiring: MainTabView.swift
5. Build + test verification
```

---

## Step 1: Pure Logic + Tests

### New file: `LedgeriOS/LedgeriOS/Logic/ProjectListCalculations.swift`

`enum ProjectListCalculations` with static functions:
- `filterByArchiveState(projects:showArchived:)` — filter by `isArchived`
- `filterBySearch(projects:query:)` — case-insensitive match on `name` + `clientName`
- `sortByRecent(_:)` — sort by `updatedAt` desc, fallback `createdAt`, nil dates last

### New file: `LedgeriOS/LedgeriOS/Logic/BudgetTabCalculations.swift`

`enum BudgetTabCalculations` with static functions:
- `enabledCategories(allCategories:)` — keep categories with non-zero budget or spend
- `sortCategories(_:)` — fees last, then alphabetical
- `remainingLabel(spentCents:budgetCents:categoryType:)` — "$Y remaining" / "$Y over" / "$X spent/received"
- `spentLabel(spentCents:categoryType:)` — "$X spent" or "$X received" for fees

### New file: `LedgeriOS/LedgeriOSTests/ProjectListCalculationTests.swift`

~12 tests: archive filtering, search matching (name, clientName, case insensitive, empty query), sort order, nil dates.

### New file: `LedgeriOS/LedgeriOSTests/BudgetTabCalculationTests.swift`

~10 tests: enabled categories filtering, sort order (fees last), remaining/spent labels (under budget, over budget, zero budget, fee type).

**Pattern to follow:** `BudgetDisplayCalculations.swift` + `BudgetDisplayCalculationTests.swift`

---

## Step 2: New Components

### New file: `LedgeriOS/LedgeriOS/Components/ScrollableTabBar.swift`

Horizontally scrollable underline tab bar (matches screenshot pattern — different from the bordered `SegmentedControl`):
- Selected tab: bold text in `BrandColors.primary` + 3pt underline
- Unselected: `BrandColors.textSecondary`
- Bottom border: 1pt `BrandColors.borderSecondary`
- `struct TabBarItem: Identifiable { let id: String; let label: String }`
- `struct ScrollableTabBar: View { @Binding var selectedId: String; let items: [TabBarItem] }`
- Reused by ProjectDetailView (5 tabs), ProjectsListView (Active/Archived), and later Inventory (3 tabs)

```swift
import SwiftUI

struct TabBarItem: Identifiable {
    let id: String
    let label: String
}

struct ScrollableTabBar: View {
    @Binding var selectedId: String
    let items: [TabBarItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    let isSelected = item.id == selectedId
                    Button {
                        selectedId = item.id
                    } label: {
                        Text(item.label)
                            .font(isSelected ? Typography.button : Typography.body)
                            .foregroundStyle(isSelected ? BrandColors.primary : BrandColors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.top, Spacing.sm)
                            .padding(.bottom, 10)
                            .overlay(alignment: .bottom) {
                                if isSelected {
                                    Rectangle()
                                        .fill(BrandColors.primary)
                                        .frame(height: 3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
        .background(BrandColors.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrandColors.borderSecondary)
                .frame(height: Dimensions.borderWidth)
        }
    }
}
```

### New file: `LedgeriOS/LedgeriOS/Components/ProjectCard.swift`

Project card matching screenshot 01:
- Uses `Card(padding: 0)` wrapper
- Hero image area: `AsyncImage` or "No image" placeholder on `surfaceTertiary`
- Content: project name (h3), client name (small, secondary), then budget category preview rows
- Budget preview: category name (small, secondary) + `BudgetProgressView(compact: true)` for top categories
- Accepts `let project: Project` + `let budgetPreview: [BudgetProgress.CategoryProgress]`

**Key detail from screenshots:** The card shows category NAME (e.g., "Furnishings") above the progress bar. `BudgetProgressView` doesn't show the name — so `ProjectCard` adds a `Text(category.name)` label above each `BudgetProgressView`.

```swift
import SwiftUI

struct ProjectCard: View {
    let project: Project
    let budgetPreview: [BudgetProgress.CategoryProgress]

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                heroImage

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(project.name.isEmpty ? "Project" : project.name)
                        .font(Typography.h3)
                        .foregroundStyle(BrandColors.textPrimary)

                    Text(project.clientName.isEmpty ? "No client" : project.clientName)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)

                    ForEach(budgetPreview) { cat in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(cat.name)
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                            BudgetProgressView(
                                spentCents: cat.spentCents,
                                budgetCents: cat.budgetCents,
                                compact: true
                            )
                        }
                    }
                }
                .padding(Spacing.cardPadding)
            }
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        if let url = project.mainImageUrl, !url.isEmpty {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                        .frame(height: 140).clipped()
                default:
                    imagePlaceholder
                }
            }
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(BrandColors.surfaceTertiary)
            .frame(height: 100)
            .overlay {
                Text("No image")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textTertiary)
            }
    }
}
```

---

## Step 3: Screens

### New directory: `LedgeriOS/LedgeriOS/Views/Projects/`

### New file: `Views/Projects/ProjectsListView.swift`

Replaces `ProjectsPlaceholderView`. Layout:
- Navigation title "Projects" + toolbar: info icon (left), search magnifier (right)
- `ScrollableTabBar` with Active / Archived
- `ScrollView` → `LazyVStack` of `NavigationLink(value: project)` → `ProjectCard`
- Empty state: `ContentUnavailableView`
- Search via `.searchable(text:isPresented:)` or toggle search bar

**Data source:** Creates its own `ProjectService(syncTracker: NoOpSyncTracker())` locally and manages a Firestore listener via `.task(id: accountId)`. Does NOT depend on `ProjectContext.projects` (that stream only activates after selecting a specific project).

**Computed property `filteredProjects`:** Pipes `projects` through `ProjectListCalculations.filterByArchiveState` → `filterBySearch` → `sortByRecent`.

**Budget preview:** For each project, the card currently won't have real per-project budget progress (that requires activating each project's subscriptions). Instead, show a simplified preview using the denormalized `project.budgetSummary` if available, or empty. Full budget preview requires future work (deferred).

### New file: `Views/Projects/ProjectDetailView.swift`

Project detail hub. Layout:
- `.navigationBarTitleDisplayMode(.inline)` with `ToolbarItem(placement: .principal)` showing project name + client name stacked
- Trailing toolbar: kebab menu button → `.confirmationDialog`
- `ScrollableTabBar` with 5 tabs: Budget, Items, Transactions, Spaces, Accounting
- Content switches on `selectedTab` state
- `.task(id: project.id)` → `projectContext.activate(accountId:projectId:)` to start 7 real-time subscriptions
- `.onDisappear` → `projectContext.deactivate()` to clean up listeners

### New file: `Views/Projects/BudgetTabView.swift`

Budget tab content (screenshot 03). Reads `projectContext.budgetProgress`:
- Each category → `BudgetCategoryRow`: name ("Furnishings Budget"), spent label, remaining/over label (color-coded), `ProgressBar`
- Uses `BudgetTabCalculations.enabledCategories` → `sortCategories`
- "Overall Budget" row at bottom with divider
- Over-budget amounts styled in `StatusColors.overflowBar` color
- Fee categories show "received" instead of "spent"

`BudgetCategoryRow` is a private struct within this file (extract to component later if reused).

### New files: 4 tab placeholders

`Views/Projects/ItemsTabPlaceholder.swift`, `TransactionsTabPlaceholder.swift`, `SpacesTabPlaceholder.swift`, `AccountingTabPlaceholder.swift`

Each reads from `@Environment(ProjectContext.self)` and shows `ContentUnavailableView` with the count (e.g., "5 Items") and "Coming soon" description.

---

## Step 4: Navigation Wiring

### Modify: `LedgeriOS/LedgeriOS/Views/MainTabView.swift`

Replace `ProjectsPlaceholderView()` with `ProjectsListView()` in the Projects tab. Add `.navigationDestination(for: Project.self)` on the `NavigationStack`:

```swift
NavigationStack {
    ProjectsListView()
        .navigationDestination(for: Project.self) { project in
            ProjectDetailView(project: project)
        }
}
```

`Project` already conforms to `Hashable`.

### Delete (optional): `Views/ProjectsPlaceholderView.swift` — replaced by `ProjectsListView`

---

## Step 5: Verification

1. **Unit tests:** Run all tests — new logic tests pass, existing tests don't regress
2. **Build:** `xcodebuild build` succeeds with no new warnings
3. **Manual (iPhone 16e simulator):**
   - Sign in → select account → see project list with real Firestore data
   - Active tab shows active projects, Archived tab shows archived or empty state
   - Project cards show image (or placeholder), name, client, budget previews
   - Tap project → navigates to detail hub
   - Budget tab shows categories with progress bars and Overall Budget
   - Other tabs show placeholder with entity counts
   - Back button returns to list
   - Light + dark mode correct

---

## File Summary

| Action | File | Purpose |
|--------|------|---------|
| Create | `Logic/ProjectListCalculations.swift` | Pure filtering/sorting |
| Create | `Logic/BudgetTabCalculations.swift` | Pure budget row labels |
| Create | `Tests/ProjectListCalculationTests.swift` | ~12 tests |
| Create | `Tests/BudgetTabCalculationTests.swift` | ~10 tests |
| Create | `Components/ScrollableTabBar.swift` | Reusable underline tab bar |
| Create | `Components/ProjectCard.swift` | Project card with budget preview |
| Create | `Views/Projects/ProjectsListView.swift` | Projects list screen |
| Create | `Views/Projects/ProjectDetailView.swift` | Project detail hub |
| Create | `Views/Projects/BudgetTabView.swift` | Budget tab content |
| Create | `Views/Projects/ItemsTabPlaceholder.swift` | Items tab placeholder |
| Create | `Views/Projects/TransactionsTabPlaceholder.swift` | Transactions tab placeholder |
| Create | `Views/Projects/SpacesTabPlaceholder.swift` | Spaces tab placeholder |
| Create | `Views/Projects/AccountingTabPlaceholder.swift` | Accounting tab placeholder |
| Modify | `Views/MainTabView.swift` | Wire navigation |
| Delete | `Views/ProjectsPlaceholderView.swift` | Replaced |

## Execution Strategy

**Step 1 (parallel):** Logic + tests — create 4 files, run tests
**Step 2 (parallel):** Components — create ScrollableTabBar + ProjectCard with previews
**Step 3 (sequential after 1+2):** Screens + navigation — create 7 views, modify MainTabView, build + verify

## Key Files to Reuse

- `Components/BudgetProgressView.swift` — reused in ProjectCard and BudgetTabView
- `Logic/BudgetDisplayCalculations.swift` — pattern for new logic modules
- `State/ProjectContext.swift` — data source for project detail views
- `Services/ProjectService.swift` — create locally in ProjectsListView for list subscription
- `Theme/*` — all spacing, typography, colors, dimensions

## Architecture Notes

### Why ProjectsListView manages its own subscription

`ProjectContext.activate(accountId:projectId:)` subscribes to all projects as a side-effect (for sibling navigation), but requires a `projectId`. Before any project is selected, that stream is empty. So `ProjectsListView` creates a local `ProjectService(syncTracker: NoOpSyncTracker())` and manages its own Firestore listener. This is lightweight — services are thin wrappers around `FirestoreRepository`.

### ScrollableTabBar vs SegmentedControl

The screenshots show two distinct tab patterns:
- **SegmentedControl** (bordered pill toggle) — used for Active/Archived on Projects list
- **ScrollableTabBar** (underline tabs in horizontal scroll) — used in Project Detail hub

Looking more carefully at screenshot 01, the Active/Archived toggle is actually underline-style too, not the bordered SegmentedControl. `ScrollableTabBar` works for both (2 items or 5 items).

### Navigation pattern

```
MainTabView
  └── Tab: Projects
      └── NavigationStack
          ├── ProjectsListView (root)
          │     └── NavigationLink(value: Project) → ProjectCard
          └── .navigationDestination(for: Project.self)
                └── ProjectDetailView(project:)
                      ├── ScrollableTabBar
                      ├── BudgetTabView (reads projectContext)
                      ├── ItemsTabPlaceholder
                      ├── TransactionsTabPlaceholder
                      ├── SpacesTabPlaceholder
                      └── AccountingTabPlaceholder
```

Future sessions add `.navigationDestination(for: Transaction.self)` etc. to `ProjectDetailView`.

## Reference Screenshots

- `reference/screenshots/dark/01_projects_list_.png` — Projects list layout
- `reference/screenshots/dark/03_project_detail_budget.png` — Budget tab layout
- `reference/screenshots/dark/04a_project_detail_items.png` — Items tab (future)
- `reference/screenshots/dark/05_project_detail_transactions.png` — Transactions tab (future)
- `reference/screenshots/dark/06_project_detail_spaces.png` — Spaces tab (future)
