# Issue: Budget category badge missing in transaction detail view

**Status:** Active — root cause identified, architectural fix pending
**Opened:** 2026-03-05
**Resolved:** _pending_

## Info
- **Symptom:** Budget category badge (e.g. "Furnishings") shows on transaction cards in list views but does not appear in TransactionDetailView. Badge appears briefly then disappears.
- **Affected area:** `ProjectContext.swift` lifecycle, `ProjectDetailView.swift` `.onDisappear`

### Background Research

**Card badge source (works):**
- `UniversalSearchView.swift:150` — resolves via `categoryName(for:)` which uses `accountContext.allBudgetCategories` (line 207)
- `TransactionsTabView.swift:199` — resolves via `categoryLookup` built from `projectContext.budgetCategories`

**Detail badge source (broken):**
- `TransactionDetailView.swift` — builds `categoryLookup` from `projectContext.budgetCategories`
- `selectedCategory` resolves via that lookup
- Badge renders via `badgeItems()`

## Experiments

### H1: TransactionDetailView uses projectContext.budgetCategories which is empty outside project scope
- **Rationale:** projectContext is only activated inside ProjectDetailView. Search and Inventory tabs don't activate it.
- **Result:** Confirmed that categoryLookup depends on `projectContext.budgetCategories`.
- **Verdict:** Confirmed — but this is a secondary symptom, not the root cause for in-project navigation.

### H2 (ruled out): accountContext.allBudgetCategories as fallback
- **Rationale:** Account-level categories are always populated.
- **Result:** User rejected. Projects use a subset of budget categories — account-level data is the wrong scope. Using it as a fallback would show categories the project doesn't use.
- **Verdict:** Ruled out — incorrect approach.

### H3 (ruled out): Redundant Firestore listener on TransactionDetailView overwrites budgetCategoryId
- **Rationale:** TransactionDetailView had its own `startTransactionListener()` that subscribed to the transaction document. Initial hypothesis was that Firestore re-decode dropped `budgetCategoryId`.
- **Result:** Removed the redundant listener, replaced with computed property reading from `projectContext.transactions`. Badge still disappeared. Debug prints confirmed `budgetCategoryId` is always present on the transaction — the issue is that `categoryLookup` keys go empty, not that the ID is missing.
- **Verdict:** Ruled out. Listener removal was correct cleanup but not the badge fix.

### H4: ProjectDetailView.onDisappear calls deactivate() during NavigationStack push
- **Rationale:** Debug prints showed `categoryLookup` keys going from 8 entries to `[]` shortly after navigation.
- **Experiment:** Traced call chain: `ProjectDetailView.swift:123-125` has `.onDisappear { projectContext.deactivate() }`. SwiftUI fires `.onDisappear` on the parent when a child pushes onto the same NavigationStack. `deactivate()` (ProjectContext.swift:134-147) clears ALL data arrays including `budgetCategories = []`.
- **Result:** Confirmed. The badge appears initially (data is populated), then disappears when SwiftUI fires `.onDisappear` on ProjectDetailView as TransactionDetailView pushes onto the stack.
- **Verdict:** **Confirmed — this is the root cause.**

## Root Cause

`ProjectContext.deactivate()` couples listener lifecycle with data lifecycle. It both removes Firestore listeners AND clears all cached data to empty arrays/nil. `ProjectDetailView.onDisappear` calls `deactivate()`, and SwiftUI fires `.onDisappear` when a child pushes onto the NavigationStack — not just on back-navigation.

**Chain:** Push to detail view → `.onDisappear` fires on ProjectDetailView → `deactivate()` → `budgetCategories = []` → `categoryLookup` empty → badge gone.

This affects all 15 views that read from `projectContext` via `@Environment`, not just TransactionDetailView.

## Resolution

**Fix:** Split `deactivate()` into `stopListeners()` (removes listeners only) and `clearData()` (resets arrays). `ProjectDetailView.onDisappear` should call `stopListeners()` only, preserving cached data for child views on the stack. `activate()` calls both when switching projects.

See prompt in conversation for full implementation plan.

**Files to change:**
- `LedgeriOS/LedgeriOS/State/ProjectContext.swift` — split deactivate()
- `LedgeriOS/LedgeriOS/Views/Projects/ProjectDetailView.swift` — use stopListeners() instead of deactivate()

**Cleanup:** Remove `[BudgetDebug]` print statements from ProjectContext.swift (lines 94, 108, 150, 156) after fix is verified.
