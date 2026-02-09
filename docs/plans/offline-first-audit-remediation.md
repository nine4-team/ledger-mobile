# Plan: Resolve Offline-First Audit Violations

## Context

The audit at `docs/audits/offline-first-audit-2026-02-08.md` found **17 high-severity** and **3 medium-severity** violations of our offline-first architecture. All high violations are the same pattern: service-layer `update*`/`delete*`/`save*` functions that `await` Firestore writes instead of using fire-and-forget. While UI callers already use fire-and-forget (`.catch()`), the service signatures are misleading and `trackPendingWrite()` fires late (after server ack instead of immediately).

Two medium violations are bare `getDoc`/`getDocs` calls in `projectPreferencesService` that can stall the home screen when the server is unreachable. (The audit's third medium recommendation — flipping all `refresh*` defaults from `'online'` to `'offline'` — was dropped; it goes beyond the architecture spec, which relies on Firestore's native server-first-with-cache-fallback behavior.)

## Phase 1 — High Violations: Remove awaited writes in service layer (17 functions across 9 files)

For each function: remove `async`/`await`, add `.catch()` to the write, change return type from `Promise<void>` to `void`. Move `trackPendingWrite()` after the fire-and-forget call (already in the right place, just executes immediately now).

**Template transformation:**
```typescript
// BEFORE
export async function updateFoo(...): Promise<void> {
  await setDoc(ref, data, { merge: true });
  trackPendingWrite();
}

// AFTER
export function updateFoo(...): void {
  setDoc(ref, data, { merge: true }).catch(err => console.error('[service] updateFoo failed:', err));
  trackPendingWrite();
}
```

### Step 1: `src/data/repository.ts` (lines ~117, ~125)
- `upsert()` — remove async/await, add .catch()
- `delete()` — remove async/await, add .catch()
- This auto-fixes `updateProject` and `deleteProject` in `projectService.ts` (they delegate to repo) — update those to remove async/await too

### Step 2: `src/data/itemsService.ts` (lines ~122, ~161)
- `updateItem()` — remove async/await, add .catch()
- `deleteItem()` — remove async/await, add .catch()

### Step 3: `src/data/transactionsService.ts` (lines ~73, ~88)
- `updateTransaction()` — remove async/await, add .catch()
- `deleteTransaction()` — remove async/await, add .catch()

### Step 4: `src/data/spacesService.ts` (lines ~135, ~150)
- `updateSpace()` — remove async/await, add .catch()
- `deleteSpace()` — remove async/await, add .catch()

### Step 5: `src/data/budgetCategoriesService.ts` (lines ~151, ~175, ~188)
- `updateBudgetCategory()` — remove async/await, add .catch()
- `deleteBudgetCategory()` — remove async/await, add .catch()
- `setBudgetCategoryOrder()` — remove async/await, use `Promise.all(...).catch()`
- Also fix `setBudgetCategoryArchived()` which awaits `updateBudgetCategory`

### Step 6: `src/data/spaceTemplatesService.ts` (lines ~118, ~146)
- `updateSpaceTemplate()` — remove async/await, add .catch()
- `setSpaceTemplateOrder()` — remove async/await, use `Promise.all(...).catch()`
- Also fix `setSpaceTemplateArchived()` which awaits `updateSpaceTemplate`

### Step 7: Remaining lower-traffic services
- `src/data/accountPresetsService.ts` (~line 85): `updateAccountPresets()`
- `src/data/vendorDefaultsService.ts` (~line 54): `saveVendorDefaults()` + fix `replaceVendorSlots()` which awaits it
- `src/data/projectPreferencesService.ts` (~line 110): `updateProjectPreferences()`
- `src/data/businessProfileService.ts` (~line 57): `saveBusinessProfile()`
- `src/data/projectService.ts`: `updateProject()` and `deleteProject()` — remove async/await (they delegate to the now-synchronous repo methods)

## Phase 2 — Medium Violations: Fix bare reads in projectPreferencesService

Both functions are called from the home screen's `useEffect`. Bare `getDoc`/`getDocs` attempt server-first with no explicit fallback — if the server is unreachable, Firestore may stall before falling back, violating Invariant A ("no spinners of doom").

### Step 8: `src/data/projectPreferencesService.ts` (~line 67)
- `ensureProjectPreferences`: Replace bare `getDoc(ref)` with the same cache-then-server fallback pattern used in `repository.ts:getDocWithPreference` (`getDocFromCache` → `getDocFromServer` → `getDoc`)

### Step 9: `src/data/projectPreferencesService.ts` (~line 137)
- `fetchProjectPreferencesMap`: Replace bare `getDocs(query(...))` with cache-then-server fallback (`getDocsFromCache` → `getDocsFromServer` → `getDocs`)

## Verification

1. Run `npx tsc --noEmit` — confirm no new type errors (pre-existing errors in MEMORY.md are expected)
2. Search for `await setDoc`, `await deleteDoc`, `await updateDoc` across `src/data/` — confirm zero matches outside known exceptions (`createAccountWithOwner`, `createInvite`)
3. Search for `: Promise<void>` in modified service functions — confirm all changed to `: void`
4. Confirm bare `getDoc`/`getDocs` no longer used in `projectPreferencesService.ts`
