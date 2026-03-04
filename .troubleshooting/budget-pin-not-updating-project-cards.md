# Issue: Pinning budget categories doesn't update project card bars

**Status:** Resolved
**Opened:** 2026-03-03
**Resolved:** 2026-03-03

## Info
- **Symptom:** When user pins budget categories in BudgetTabView, the BudgetProgressPreview on project cards does not update to show the pinned categories. The bars shown remain unchanged.
- **Affected area:** ProjectsListView (project cards), ProjectPreferencesService (unused subscription)

### Root Cause
`ProjectsListView` had no Firestore subscription for project preferences. `pinnedCategoryIds` was hardcoded to `[]` at line 135. The service method `subscribeToAllProjectPreferences` existed but was never called.

## Experiments

### H1: ProjectsListView passes hardcoded empty pinnedCategoryIds
- **Rationale:** No preferences subscription exists at the list level
- **Experiment:** Read ProjectsListView to check what's passed to budgetBarCategories
- **Result:** `ProjectsListView.swift:135` — `pinnedCategoryIds: []` hardcoded.
- **Verdict:** Confirmed — root cause

## Resolution

- **Root cause:** ProjectsListView never subscribed to project preferences, so pinned category IDs were always empty.
- **Fix:** Added real-time Firestore subscription to all project preferences in ProjectsListView. Pinned categories now flow through to budgetBarCategories. Default (no pins) shows top 1 by spend %; with pins, shows all pinned categories.
- **Files changed:** `LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift`
- **Lessons:** When a feature works in a detail view but not a list view, check whether the list view has its own data subscription — detail-level context managers (like ProjectContext) don't propagate to list views.
