# Budget Tracker Visual Parity Fixes

## Reference: React Native Design (from screenshots)

### Budget Tab (project detail)
Each category row:
1. Title — e.g. "Furnishings Budget" (bold, 15pt)
2. Amount row — "$87,305 spent" (left) / "$7,955 over" in red, or "$659 remaining" (right) — caption
3. Progress bar — no percentage label anywhere

### Project Cards (projects list)
Each card shows up to 2 budget categories:
1. Category name — e.g. "Furnishings"
2. Amount row — "$100,936 spent" (left) / "$2,264 remaining" (right)
3. Thin progress bar

---

## Deviations to Fix

### Fix 1: Remove extra label line from BudgetTabView (the "extra line")
`BudgetCategoryRow` renders: title → spent/remaining HStack → `BudgetProgressView(compact: true)`.
`BudgetProgressView` also renders its OWN label row: "$X / $Y" + "50%". This creates two lines of text above the bar.

**Fix:** Replace `BudgetProgressView` in `BudgetCategoryRow` and `overallBudgetRow` with a bare `ProgressBar`. The rows already have their own labels.

**Files:** `BudgetTabView.swift`

### Fix 2: Remove percentage from BudgetProgressView (or delete it)
`BudgetProgressView` shows a "50%" percentage on the right. RN never shows a percentage. After Fix 1, `BudgetProgressView` may be unused — delete it if so.

**Files:** `BudgetProgressView.swift` (likely delete)

### Fix 3: Use BudgetProgressPreview in ProjectCard
`ProjectCard` uses `BudgetProgressView` (wrong format — "Spent $X of $Y" + percentage). It should use `BudgetProgressPreview` (category name, amounts left/right, thin 4px bar) which already exists and matches the RN design.

**Files:** `ProjectCard.swift`

### Fix 4: Wire up budget data on project cards
`budgetPreviewFor()` in `ProjectsListView` always returns `[]`. `ProjectListCalculations.budgetBarCategories()` exists and has tests — it takes categories + pinnedCategoryIds and returns the right ordered list. Need to hook this up so project cards actually show budget bars.

The project list has access to `BudgetProgress` per project via `ProjectContext` or denormalized data. Need to investigate what's available in the list context.

**Files:** `ProjectsListView.swift`, `ProjectCard.swift` (may need to pass pinnedCategoryIds)

### Fix 5: Add pin UI to BudgetTabView
The Swift app reorders pinned categories (logic works) but provides no way for users to pin/unpin. The RN uses long-press on each row to show an action sheet.

What's already there:
- `BudgetTabCalculations.applyPinning()` — exists and tested
- `ProjectPreferences.pinnedBudgetCategoryIds` — model exists
- `ProjectPreferencesService.subscribeToProjectPreferences()` — read works
- `BudgetTabView` reads pinnedCategoryIds from ProjectContext

What's missing:
- `ProjectPreferencesService` has no write method for pinning
- `BudgetCategoryRow` has no long-press gesture
- No pin icon shown on rows

**Fix:**
1. Add `updatePinnedCategories(accountId:userId:projectId:pinnedIds:)` to `ProjectPreferencesService`
2. Add a toggle handler to `BudgetTabView` that calls the service
3. Add long-press gesture + pin icon to `BudgetCategoryRow` (match RN: pin icon right of bar, action sheet on long-press)
4. Overall Budget row never shows a pin (matches RN's `reservePinSpace` concept — just show a spacer for alignment)

**Files:** `ProjectPreferencesService.swift`, `BudgetTabView.swift`

---

## Execution Order
1. Fix 1 — Remove extra label from BudgetTabView (most visible)
2. Fix 2 — Delete BudgetProgressView if unused
3. Fix 3 — Use BudgetProgressPreview in ProjectCard
4. Fix 4 — Wire up budget data on project cards (investigate first)
5. Fix 5 — Add pin write service + pin UI to budget tab rows
