# Plan: Address All Architecture Critique Findings

## Context

An [architecture critique](.plans/architecture-critique-findings.md) identified 10 findings across the Ledger Mobile codebase. Since this is a greenfield project, we establish correct patterns now rather than retrofitting later. This plan addresses all 10 findings across 6 phases: 1 new file, 13 modified files.

---

## Phase 1: Foundation Infrastructure (parallelizable) ✅ COMPLETE

**Status**: Completed 2026-02-08
**Files changed**: 1 new, 3 modified
**TypeScript**: No new errors introduced

All four tasks are independent — execute in parallel.

### 1A. Create `useEditForm<T>` hook (Finding 1 + 8)

**New file**: `src/hooks/useEditForm.ts`

A minimal hook that tracks which form fields changed relative to an initial snapshot.

**API**:
```ts
useEditForm<T>(initialData: T | null) → {
  values: T                          // current form state
  setField(key, value)               // update one field, marks hasEdited
  setFields(updates)                 // update multiple fields
  hasEdited: boolean                 // user has touched the form
  getChangedFields(): Partial<T>     // only fields that differ from snapshot
  hasChanges: boolean                // getChangedFields() is non-empty
  shouldAcceptSubscriptionData: bool // true until first setField call
  reset()                           // re-accept subscription data
}
```

**Behavior**:
- Stores `snapshot` ref: captured from first non-null `initialData` (updated by subscription until user edits)
- `getChangedFields()` does shallow per-key comparison against snapshot
- Normalizes `null` ≈ `undefined` for comparison (Firestore doesn't store `undefined`)
- Does NOT handle validation, submission, or error state — each screen owns that

✅ **Completed**: Implemented as specified with full TypeScript generics and proper memoization.

### 1B. Fix `ScopedListenerManager.attachScope()` (Finding 6)

**Modify**: `src/data/listenerManager.ts`

**Bug**: `attachScope()` (line 176) sets `scope.isAttached = true` even if ALL factories returned `null` (threw errors). Result: scope thinks it's attached but no listeners are running. User sees stale data silently.

**Fix**:
1. After calling all factories, check if any succeeded (non-null `unsubscribe`)
2. Only set `isAttached = true` if at least one listener attached
3. If all fail, schedule retry with exponential backoff (1s, 2s, 4s — max 3 attempts)
4. Clear retry timeouts in `detach()` and `cleanup()`

✅ **Completed**: Added `retryTimeout` and `retryAttempt` fields to `ScopeListeners`. Updated `attachScope()` to track success, conditionally set `isAttached`, and schedule retries on failure. Cleanup logic added to `detach()` and `cleanup()`.

### 1C. Media foreground auto-retry (Finding 5)

**Modify**: `app/_layout.tsx`

**Changes**:
1. Add `AppState` listener: when app returns to foreground (`background → active`), call `processUploadQueue()` (fire-and-forget with `.catch()`)
2. Chain `processUploadQueue()` after `hydrateMediaStore()` on startup via `.then()` — processes any uploads left from a previous session

✅ **Completed**: Added `AppState` import and listener in separate useEffect. Chained `processUploadQueue()` after hydration. Both use fire-and-forget with `.catch(console.error)`.

### 1D. Media stale cache cleanup (Finding 5)

**Modify**: `src/offline/media/mediaStore.ts`

**Add** `cleanupStaleMedia(maxAgeMs = 7 days)`:
- Removes MediaRecords with status `uploaded` AND `createdAt` older than threshold (local copies of already-synced files)
- Deletes corresponding local files from FileSystem cache
- Removes associated completed jobs

**Reason**: The existing `cleanupOrphanedMedia()` requires knowing ALL referenced media IDs (impractical at startup). Age-based cleanup for uploaded files is simpler and handles the storage growth problem.

**Wire up**: Call `cleanupStaleMedia()` in `app/_layout.tsx` after hydration (non-blocking).

✅ **Completed**: Implemented `cleanupStaleMedia()` function with default 7-day threshold (SEVEN_DAYS_MS constant). Wired up in `_layout.tsx` to run after hydration alongside `processUploadQueue()`.

---

## Phase 2: Edit Screen Migrations (depends on 1A)

Migrate all 6 edit screens to use `useEditForm` / partial writes. Order: simplest → most complex.

### 2A. Project Edit — `app/project/[projectId]/edit.tsx`

Already has partial writes for basic fields and `userHasEditedBudgets` for budgets. Migrate the basic fields (name, clientName, description) to `useEditForm` for consistency. Budget handling stays as-is (separate collection, separate writes).

### 2B–2C. Space Edits — `app/business-inventory/spaces/[spaceId]/edit.tsx`, `app/project/[projectId]/spaces/[spaceId]/edit.tsx`

2 fields each (name, notes). Add change detection in the edit screen's `handleSubmit` — compare `values` against the `initialValues` passed to `SpaceForm`. Only send changed fields to `updateSpace()`. No changes to `SpaceForm` component itself.

### 2D. Settings Budget Category — `app/(tabs)/settings.tsx`

3 fields (name, slug, metadata). Inline comparison in `handleSaveCategoryDetails` against the existing category. No hook needed — this is a modal form with simple fields.

### 2E. Item Edit — `app/items/[id]/edit.tsx`

9 fields. Replace 9 `useState` calls with `useEditForm<ItemFormValues>`. Price fields: hook tracks cents values (data-model types); separate display strings for the three price inputs convert on change via `setField`.

### 2F. Transaction Edit — `app/transactions/[id]/edit.tsx`

13 fields — most complex migration. Same `useEditForm` pattern. Special considerations:
- Tax/subtotal computation stays in save handler — computed values go through `getChangedFields()`
- `budgetCategoryId` change propagation to linked items (lines 248-252) still fires if that field is in the changed set

For all screens:
- Add `userHasEdited` protection (provided by `shouldAcceptSubscriptionData` from the hook)
- If `hasChanges` is false on save, skip the write and just navigate

---

## Phase 3: Defensive Rendering (Finding 4, parallelizable with Phase 2)

### 3A. Item detail space label — `app/items/[id]/index.tsx`

**Line 298**: Change fallback from raw document ID to user-friendly text:
```ts
// Before:
spaces[item.spaceId]?.name?.trim() || item.spaceId
// After:
spaces[item.spaceId]?.name?.trim() || 'Unknown space'
```

### 3B. Report data service — `src/data/reportDataService.ts`

Verify `resolveSpaceName` handles missing spaces gracefully (returns `null` when space not in map — acceptable since UI just omits the label).

---

## Phase 4: Request-Doc Failure Visibility (Finding 7, parallelizable)

**Modify**: `src/components/SyncStatusBanner.tsx`

When `failedRequestDocs > 0`, read specific error messages from `getTrackedRequestsSnapshot()` (already exported from `src/sync/requestDocTracker.ts:172`) and display them instead of generic "Some changes could not sync."

```ts
if (failedRequestDocs === 1) → show the specific errorMessage
if (failedRequestDocs > 1)  → "N operations failed. Tap Retry or Dismiss."
```

Small change, uses existing infrastructure. No new components.

---

## Phase 5: Architecture Doc Updates (Findings 2, 3, 9, 10 — do last)

**Modify**: `.cursor/plans/firebase-mobile-migration/10_architecture/ARCHITECTURE.md`

### 5A. Rewrite "high-risk fields" justification (Finding 3)

Replace the probability argument ("concurrent edits are rare") with the data model argument:
- `budgetCents`, `purchasePriceCents`, etc. are **source/planning data, not derived totals**
- Each is a user's direct input on a single document — the correct value is whatever they last entered
- Actual spend totals are **computed at read time** from transaction documents via `buildBudgetProgress()` — never stored as a competing field
- Fallback: `updatedAt` security rule checks if needed (one-line rule, no Cloud Function)

### 5B. Add "Known Limitations" section (Finding 2)

Document silent security rule failures: Firestore applies writes optimistically to local cache even if server rejects them. User may see "phantom" values that never sync. Accepted for MVP.

### 5C. Add schema evolution stance (Finding 9)

Document the pattern: new optional fields + `merge: true` + `undefined` handling in reads. No formal migration framework for MVP. If breaking changes needed: `schemaVersion` field + read-time normalizer.

### 5D. Update "Do NOT Build" list (Finding 10)

Add: "Full-form overwrites on edit screens — always use `getChangedFields()` to send only modified fields."

Update: Distinguish "lightweight staleness check" from "full compare-before-commit UX" — the former is cheap and is what `useEditForm` provides.

---

## Verification

### Phase 1 ✅
- ✅ `tsc` passes with no new errors (verified 2026-02-08, all errors are pre-existing)
- **1A**: `useEditForm` — supply `initialData`, call `setField`, verify `getChangedFields()` returns only changed fields; verify `shouldAcceptSubscriptionData` flips to `false` after first edit
- **1B**: Attach a scope with a factory that throws → verify `isAttached` stays `false`; mix good/bad factories → verify `isAttached` is `true`
- **1C**: Enqueue upload, background app, foreground → verify queue processes automatically
- **1D**: Create uploaded records older than threshold → verify `cleanupStaleMedia` removes them

**Note**: Full manual/integration testing deferred until all edit screens migrated in Phase 2.

### Phase 2
For each migrated screen:
- Open edit, make NO changes, save → verify update service function is NOT called (or called with empty partial that's a no-op)
- Open edit, change ONE field, save → verify only that field is in the update payload
- Open edit, wait for subscription callback → verify form values are NOT overwritten after user starts editing

### Phase 3
- Archive a space, view an item referencing that space → verify "Unknown space" label, not raw ID

### Phase 4
- Trigger a failed request-doc → verify `SyncStatusBanner` shows the specific error message, not generic text

---

## File Change Summary

| File | Type | Finding(s) |
|------|------|------------|
| `src/hooks/useEditForm.ts` | NEW | F1, F8 |
| `src/data/listenerManager.ts` | MODIFY | F6 |
| `src/offline/media/mediaStore.ts` | MODIFY | F5 |
| `app/_layout.tsx` | MODIFY | F5 |
| `app/items/[id]/edit.tsx` | MODIFY | F1 |
| `app/transactions/[id]/edit.tsx` | MODIFY | F1 |
| `app/project/[projectId]/edit.tsx` | MODIFY | F1 |
| `app/business-inventory/spaces/[spaceId]/edit.tsx` | MODIFY | F1 |
| `app/project/[projectId]/spaces/[spaceId]/edit.tsx` | MODIFY | F1 |
| `app/(tabs)/settings.tsx` | MODIFY | F1 |
| `app/items/[id]/index.tsx` | MODIFY | F4 |
| `src/components/SyncStatusBanner.tsx` | MODIFY | F7 |
| `ARCHITECTURE.md` | MODIFY | F2, F3, F9, F10 |

**Total**: 1 new file, 12 modified files.
