# Issue: "Syncing changes…" banner stuck on WiFi

**Status:** Resolved
**Opened:** 2026-02-11
**Resolved:** 2026-02-11

## Info
- **Symptom:** The "Syncing changes…" banner at the bottom of the Projects screen stays indefinitely, even when on WiFi
- **Affected area:** `src/sync/pendingWrites.ts`, `src/components/SyncStatusBanner.tsx`, `src/sync/syncStatusStore.ts`

### How it works
1. Every Firestore write service calls `trackPendingWrite()` after fire-and-forget writes
2. `trackPendingWrite()` sets `isSyncing = true` in zustand store, then calls `waitForPendingWrites(db)` from Firebase SDK
3. When `waitForPendingWrites` resolves → `isSyncing = false`, banner hides
4. `SyncStatusBanner` shows "Syncing changes…" when `isSyncing === true` and no errors

### Key finding — no timeout
`pendingWrites.ts:21-32`: `waitForPendingWrites(db)` has **no timeout**. If the Firebase SDK has any write it cannot acknowledge (security rule rejection, corrupted data, auth issue), the SDK retries indefinitely and `waitForPendingWrites` **never resolves**. This leaves `isSyncing = true` forever.

### Known Firestore SDK behavior
`waitForPendingWrites` resolves when ALL pending writes are acknowledged. If any single write is rejected by security rules, the SDK retries it indefinitely — `waitForPendingWrites` hangs, it does NOT reject. There is no built-in timeout.

## Experiments

### H1: `waitForPendingWrites` hangs due to a stuck/rejected write
- **Rationale:** No timeout on `waitForPendingWrites`. If any write fails at the server (security rules, etc.), SDK retries forever and the promise never resolves, leaving `isSyncing = true` permanently.
- **Experiment:** Check all Firestore write paths in services against `firestore.rules` for missing rules.
- **Result:** Three paths had NO security rules (implicitly denied):
  1. `accounts/{accountId}/users/{uid}/projectPreferences/{projectId}` — written by `ensureProjectPreferences` (projectPreferencesService.ts:113), triggered automatically on Projects screen load
  2. `accounts/{accountId}/presets/{presetId}` — written by `updateAccountPresets` (accountPresetsService.ts:94)
  3. `accounts/{accountId}/projects/{projectId}/budgetCategories/{categoryId}` — written by `setProjectBudgetCategory` (projectBudgetCategoriesService.ts:116)
- **Verdict:** Confirmed

### H2: Race condition between multiple `trackPendingWrite` calls
- **Rationale:** Multiple rapid writes each call `trackPendingWrite`, creating overlapping `waitForPendingWrites` promises. First to resolve sets `isSyncing = false`, but this is incorrect if the second is still pending.
- **Experiment:** Code review of the ordering.
- **Result:** Actually the opposite problem — the first promise resolving prematurely sets `isSyncing = false` while writes are still pending. But this would cause the banner to *disappear* too early, not stay stuck. Each subsequent `trackPendingWrite` call re-sets `isSyncing = true`, so if the last one hangs, the banner stays.
- **Verdict:** Not the primary cause of "stuck" — but confirms the lack of timeout is the real issue.

## Resolution
_Awaiting user verification (force-close and reopen the app to confirm banner clears)._

- **Root cause:** Three Firestore write paths used by the app had no corresponding security rules, so all writes were implicitly denied. The SDK retried indefinitely, `waitForPendingWrites` never resolved, and `isSyncing` stayed `true` forever.
- **Fix:** Added three missing rules to `firebase/firestore.rules` and deployed with `firebase deploy --only firestore:rules`.
- **Files changed:** `firebase/firestore.rules` (lines 60-68, 132-134)
- **Lessons:** Firestore rules are not recursive — a rule for `projects/{id}` does NOT cover `projects/{id}/budgetCategories/{catId}`. Every subcollection needs its own explicit rule. When adding new service files that write to new paths, always update security rules in the same change.
