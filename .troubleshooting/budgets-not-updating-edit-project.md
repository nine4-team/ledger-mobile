# Issue: Budgets don't update when set in edit project

**Status:** Active
**Opened:** 2026-02-11
**Resolved:** _pending_

## Info
- **Symptom:** When the user sets/updates budgets in the "edit project" screen, the changes don't appear anywhere — not in the project detail budget tab or the projects list cards.
- **Affected area:** `app/project/[projectId]/edit.tsx`, `src/components/budget/CategoryBudgetInput.tsx`

### Key code paths
- Edit screen: `app/project/[projectId]/edit.tsx`
  - `localBudgets` state (Record<string, number | null>) holds budget values
  - `handleBudgetChange(categoryId, cents)` at line 138 updates `localBudgets` via `setLocalBudgets`
  - `handleSubmit()` at line 144 reads `localBudgets` to write to Firestore
  - Save loop at line 200-203 iterates `budgetCategories` and looks up `localBudgets[category.id]`

- Budget input: `src/components/budget/CategoryBudgetInput.tsx`
  - `onChange(cents)` is ONLY called in `handleBlur` (line 155) — NOT on text change
  - User types values, but parent state isn't updated until blur fires

- Budget writes: `src/data/projectBudgetCategoriesService.ts`
  - `setProjectBudgetCategory()` uses `setDoc(ref, payload, { merge: true })` fire-and-forget
  - Path: `accounts/{accountId}/projects/{projectId}/budgetCategories/{categoryId}`

- Budget consumers:
  - ProjectShell uses `subscribeToProjectBudgetCategories()` (real-time)
  - Projects list uses `refreshProjectBudgetCategories(_, _, 'offline')` (one-time cache-first fetch)

## Experiments

### H1: React state timing — blur + press race condition
- **Rationale:** `CategoryBudgetInput` only calls `onChange(cents)` on blur. When the user taps Save while an input is focused, blur and onPress fire in the same event cycle. React 18 batches state updates — `setLocalBudgets` from blur is QUEUED but not committed before `handleSubmit` reads `localBudgets`. So `handleSubmit` reads the OLD state and writes old/null values to Firestore.
- **Experiment:** Trace the event flow: blur fires → `onChange(cents)` → `handleBudgetChange` → `setLocalBudgets(prev => ...)` (queued). Then onPress fires → `handleSubmit` reads `localBudgets` (still old). If this is the cause, `localBudgets` in handleSubmit won't contain the latest edit.
- **Result:** Code review confirms: `CategoryBudgetInput.handleBlur` (line 155) calls `onChange(cents)` which calls `handleBudgetChange` which calls `setLocalBudgets` (state setter — async/batched). Then `handleSubmit` fires and reads `localBudgets` (closure over previous render's state). For a new budget (no prior value), `localBudgets[category.id]` is `undefined`, which becomes `null` via `?? null` at line 201. For an existing budget being changed, the OLD value is read. The ref `userHasEditedBudgets` IS updated synchronously (line 139), but `localBudgets` state is not.
- **Verdict:** Confirmed — the root cause is the blur/press race condition with React batched state updates.

### H2: `budgetCategories.forEach` writes null for unedited categories
- **Rationale:** The save loop at line 200 iterates ALL account-level categories. For categories not in `localBudgets`, it writes `null`. This could overwrite existing budgets.
- **Experiment:** Check if `localBudgets` is populated by the subscription for all existing project budgets before save.
- **Result:** The subscription at line 85-91 DOES populate `localBudgets` with existing budget values. So for categories with existing budgets that the user didn't edit, the correct value is preserved. For categories without existing budgets, `null` is written — which is correct (no budget). This is NOT the primary issue — the real problem is H1 where even the EDITED category gets the wrong value.
- **Verdict:** Not the root cause (minor inefficiency but not the bug).

## Resolution
_Do not fill this section until the fix is verified — either by a passing
test/build or by explicit user confirmation. Applying a fix is not verification._

- **Root cause:**
- **Fix:**
- **Files changed:**
- **Lessons:**
