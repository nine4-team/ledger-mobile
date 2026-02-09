# Offline-First Architecture Audit Results

**Date:** 2026-02-08
**Status:** Complete
**Auditor:** Service Layer + UI Code — addDoc usage, async create functions, missing trackPendingWrite, awaited writes in UI

---

## Critical Violations

_No critical violations found in UI code (`app/`, `src/components/`, `src/screens/`)._

**UI Code Audit scope:** All files in `app/`, `src/components/`, and `src/screens/` were searched for:
- Direct Firestore write awaits (`await setDoc`, `await updateDoc`, `await deleteDoc`, `await addDoc`)
- Awaited service function calls that wrap Firestore writes (`await create*`, `await update*`, `await delete*`, `await save*`)
- Loading states that block on Firestore write completion (`isSubmitting`, `isSaving`, `isCreating`, `isDeleting`, `isUpdating`)

**Results:** Zero direct `await setDoc/updateDoc/deleteDoc/addDoc` calls in any UI code. Zero awaited service function calls that wrap Firestore writes in UI code. All screen handlers that call Firestore write services use fire-and-forget patterns correctly.

**Confirmed compliant patterns (not violations):**
- `await saveLocalMedia(...)` / `await deleteLocalMediaByUrl(...)` -- local SQLite ops (allowed exception), found in 12+ handlers across item/space/transaction screens
- `await enqueueUpload(...)` -- local state persistence (allowed exception), found in import invoice screens
- `await createInvite(...)` / `await createAccountWithOwner(...)` in `app/(tabs)/settings.tsx` -- explicitly allowed exceptions
- `await createAccount(...)` (Cloud Functions `httpsCallable`) in `app/account-select.tsx` -- server operation, same class as Auth ops
- `createRequestDoc(...)` in import screens -- called without `await` (fire-and-forget), compliant

**Design pattern notes (not violations, but fragile contracts to track):**

**1. SpaceForm `isSubmitting` pattern**
- **File:** `src/components/SpaceForm.tsx:38,88-108`
- **Type:** Loading state pattern -- currently safe but fragile
- The component awaits `onSubmit` (typed `Promise<void>`) and wraps it in `setIsSubmitting(true/false)`. All 4 parent callers (`app/business-inventory/spaces/new.tsx`, `app/business-inventory/spaces/[spaceId]/edit.tsx`, `app/project/[projectId]/spaces/new.tsx`, `app/project/[projectId]/spaces/[spaceId]/edit.tsx`) fire-and-forget their Firestore writes + `router.replace()`, so `isSubmitting` resolves instantly. However, a future caller that awaits a Firestore write in `onSubmit` would trigger a "spinner of doom." Consider changing `onSubmit` type to `void` and removing `isSubmitting`.

**2. CategoryFormModal `await onSave` pattern**
- **File:** `src/components/budget/CategoryFormModal.tsx:192-206`
- **Type:** Awaited callback -- currently safe
- The modal does `await onSave(...)` and accepts `isSaving` prop. The only caller (`src/screens/BudgetCategoryManagement.tsx:203`) passes a synchronous handler and `isSaving={false}` (hardcoded). No blocking occurs today.

**3. Import invoice screens `isCreating` pattern**
- **Files:** `src/screens/ImportAmazonInvoice.tsx:41,122-171` and `src/screens/ImportWayfairInvoice.tsx:42,138-211`
- **Type:** Loading state gating local operations only -- compliant
- `isCreating` blocks while `saveLocalMedia` and `enqueueUpload` execute (local SQLite/state ops). The Firestore write (`createRequestDoc`) is fire-and-forget. The spinner is appropriate here.

**Service Layer (previous audit):** All `create*` functions (except known exceptions) use `doc(collection(...))` + `setDoc` correctly and return IDs synchronously. All writes have `trackPendingWrite()` calls. No `addDoc` usage outside of known exceptions.

## High Violations

### 1. `updateItem` awaits Firestore write
**File:** `src/data/itemsService.ts:122`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function updateItem(
  accountId: string,
  itemId: string,
  data: ItemWrite
): Promise<void> {
  // ...
  await setDoc(
    doc(db, `accounts/${accountId}/items/${itemId}`),
    { ...normalizeItemWrite(data), updatedAt: serverTimestamp(), updatedBy: uid },
    { merge: true }
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`.

### 2. `deleteItem` awaits Firestore write
**File:** `src/data/itemsService.ts:161`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function deleteItem(accountId: string, itemId: string): Promise<void> {
  if (!isFirebaseConfigured || !db) { return; }
  await deleteDoc(doc(db, `accounts/${accountId}/items/${itemId}`));
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`.

### 3. `updateTransaction` awaits Firestore write
**File:** `src/data/transactionsService.ts:73`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function updateTransaction(
  accountId: string,
  transactionId: string,
  data: Partial<Transaction>
): Promise<void> {
  // ...
  await setDoc(
    doc(db, `accounts/${accountId}/transactions/${transactionId}`),
    { ...data, updatedAt: serverTimestamp() },
    { merge: true }
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`.

### 4. `deleteTransaction` awaits Firestore write
**File:** `src/data/transactionsService.ts:88`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function deleteTransaction(accountId: string, transactionId: string): Promise<void> {
  if (!isFirebaseConfigured || !db) { return; }
  await deleteDoc(doc(db, `accounts/${accountId}/transactions/${transactionId}`));
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`.

### 5. `updateSpace` awaits Firestore write
**File:** `src/data/spacesService.ts:135`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function updateSpace(
  accountId: string,
  spaceId: string,
  data: Partial<Space>
): Promise<void> {
  // ...
  await setDoc(
    doc(db, `accounts/${accountId}/spaces/${spaceId}`),
    { ...data, updatedAt: serverTimestamp() },
    { merge: true }
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`.

### 6. `deleteSpace` awaits Firestore write (soft-delete)
**File:** `src/data/spacesService.ts:150`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function deleteSpace(accountId: string, spaceId: string): Promise<void> {
  // ...
  await setDoc(
    doc(db, `accounts/${accountId}/spaces/${spaceId}`),
    { isArchived: true, updatedAt: serverTimestamp() },
    { merge: true }
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`.

### 7. `updateSpaceTemplate` awaits Firestore write
**File:** `src/data/spaceTemplatesService.ts:118`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function updateSpaceTemplate(
  accountId: string,
  templateId: string,
  data: Partial<SpaceTemplate>
): Promise<void> {
  // ...
  await setDoc(
    doc(db, `accounts/${accountId}/presets/default/spaceTemplates/${templateId}`),
    { ...data, checklists: normalizeChecklists(data.checklists ?? null), updatedAt: now },
    { merge: true }
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`. Note: `setSpaceTemplateArchived` calls this, so it will also need to be updated.

### 8. `setSpaceTemplateOrder` awaits Firestore writes
**File:** `src/data/spaceTemplatesService.ts:146`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function setSpaceTemplateOrder(
  accountId: string,
  orderedIds: string[]
): Promise<void> {
  // ...
  await Promise.all(
    orderedIds.map((id, index) =>
      setDoc(
        doc(db, `accounts/${accountId}/presets/default/spaceTemplates/${id}`),
        { order: index, updatedAt: now },
        { merge: true }
      )
    )
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, use `Promise.all(...).catch()` for fire-and-forget, change return type to `void`.

### 9. `updateBudgetCategory` awaits Firestore write
**File:** `src/data/budgetCategoriesService.ts:151`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function updateBudgetCategory(
  accountId: string,
  categoryId: string,
  data: Partial<BudgetCategory>
): Promise<void> {
  // ...
  await setDoc(
    doc(firestore, `accounts/${accountId}/presets/default/budgetCategories/${categoryId}`),
    { ...data, ...(hasMetadata ? { metadata: data.metadata ?? null } : {}), updatedAt: now },
    { merge: true }
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`. Note: `setBudgetCategoryArchived` calls this, so it will also need to be updated.

### 10. `deleteBudgetCategory` awaits Firestore write
**File:** `src/data/budgetCategoriesService.ts:175`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function deleteBudgetCategory(accountId: string, categoryId: string): Promise<void> {
  // ...
  await deleteDoc(doc(db, `accounts/${accountId}/presets/default/budgetCategories/${categoryId}`));
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`.

### 11. `setBudgetCategoryOrder` awaits Firestore writes
**File:** `src/data/budgetCategoriesService.ts:188`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function setBudgetCategoryOrder(
  accountId: string,
  orderedIds: string[]
): Promise<void> {
  // ...
  await Promise.all(
    orderedIds.map((id, index) =>
      setDoc(
        doc(firestore, `accounts/${accountId}/presets/default/budgetCategories/${id}`),
        { order: index, updatedAt: now },
        { merge: true }
      )
    )
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, use `Promise.all(...).catch()` for fire-and-forget, change return type to `void`.

### 12. `updateAccountPresets` awaits Firestore write
**File:** `src/data/accountPresetsService.ts:85`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function updateAccountPresets(
  accountId: string,
  data: Partial<Omit<AccountPresets, 'id' | 'accountId' | 'createdAt' | 'updatedAt'>>
): Promise<void> {
  // ...
  await setDoc(
    doc(db, `accounts/${accountId}/presets/default`),
    { ...data, updatedAt: now },
    { merge: true }
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`.

### 13. `saveVendorDefaults` awaits Firestore write
**File:** `src/data/vendorDefaultsService.ts:54`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function saveVendorDefaults(accountId: string, vendors: string[]): Promise<void> {
  // ...
  await setDoc(
    doc(db, `accounts/${accountId}/presets/default/vendors/default`),
    { vendors, updatedAt: now },
    { merge: true }
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`. Note: `replaceVendorSlots` awaits this, so it will also need to be updated.

### 14. `updateProjectPreferences` awaits Firestore write
**File:** `src/data/projectPreferencesService.ts:110`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function updateProjectPreferences(
  accountId: string,
  userId: string,
  projectId: string,
  data: Partial<...>
): Promise<void> {
  // ...
  await setDoc(
    ref,
    { ...data, updatedAt: serverTimestamp() },
    { merge: true }
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`.

### 15. `saveBusinessProfile` awaits Firestore write
**File:** `src/data/businessProfileService.ts:57`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
export async function saveBusinessProfile(
  accountId: string,
  updates: Pick<BusinessProfile, 'businessName' | 'logo'>,
  updatedBy?: string | null
): Promise<void> {
  // ...
  await setDoc(
    doc(db, `accounts/${accountId}/profile/default`),
    { accountId, businessName: updates.businessName.trim(), logo: updates.logo ?? null, updatedBy: updatedBy ?? null, updatedAt: now },
    { merge: true }
  );
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`.

### 16. `FirestoreRepository.upsert` awaits Firestore write
**File:** `src/data/repository.ts:117`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
async upsert(id: string, data: Partial<T>): Promise<void> {
  if (!isFirebaseConfigured || !db) { return; }
  await setDoc(doc(db, `${this.collectionPath}/${id}`), data as object, { merge: true });
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`. Note: this is used by `updateProject` in `projectService.ts`, which also awaits the result.

### 17. `FirestoreRepository.delete` awaits Firestore write
**File:** `src/data/repository.ts:125`
**Type:** Awaited write in service
**Severity:** High
**Snippet:**
```typescript
async delete(id: string): Promise<void> {
  if (!isFirebaseConfigured || !db) { return; }
  await deleteDoc(doc(db, `${this.collectionPath}/${id}`));
  trackPendingWrite();
}
```
**Fix:** Remove `async`/`await`, make fire-and-forget with `.catch()`, change return type to `void`. Note: this is used by `deleteProject` in `projectService.ts`, which also awaits the result.

## Medium Violations

**Audit scope:** Read modes in save/submit handlers, service function default modes, and reads driving save logic across `app/` and `src/data/`.

### 1. `ensureProjectPreferences` uses bare `getDoc` (server-first read) in read-then-write flow
**File:** `src/data/projectPreferencesService.ts:67`
**Type:** Read with wrong default mode
**Severity:** Medium
**Snippet:**
```typescript
export async function ensureProjectPreferences(
  accountId: string,
  projectId: string
): Promise<ProjectPreferences | null> {
  // ...
  const ref = doc(db, `accounts/${accountId}/users/${uid}/projectPreferences/${projectId}`);
  const snapshot = await getDoc(ref);  // <-- bare getDoc, server-first

  // Only create if doesn't exist
  if (snapshot.exists) return null;

  // Subsequent reads correctly use 'offline':
  const budgetCategories = await refreshBudgetCategories(accountId, 'offline');
  const projectBudgets = await refreshProjectBudgetCategories(accountId, projectId, 'offline');
```
**Fix:** Replace `await getDoc(ref)` with a cache-first read pattern (`getDocFromCache` with `getDocFromServer` fallback), consistent with how the subsequent reads use `'offline'` mode. This function is called from the home screen's `useEffect` and will stall on initial load when the device is offline because the bare `getDoc` attempts a server read first.

### 2. `fetchProjectPreferencesMap` uses bare `getDocs` with no mode parameter
**File:** `src/data/projectPreferencesService.ts:137`
**Type:** Read with wrong default mode
**Severity:** Medium
**Snippet:**
```typescript
export async function fetchProjectPreferencesMap(params: {
  accountId: string;
  userId: string;
  projectIds: string[];
}): Promise<Record<string, ProjectPreferences>> {
  // ...
  for (const chunk of chunks) {
    const snapshot = await getDocs(  // <-- bare getDocs, no mode parameter
      query(
        collection(db, `accounts/${accountId}/users/${userId}/projectPreferences`),
        where(FieldPath.documentId(), 'in', chunk)
      )
    );
```
**Fix:** Add a `mode: 'online' | 'offline' = 'offline'` parameter and use the cache-first/server-first preference pattern (like `refreshBudgetCategories` does). This function is called from the home screen's `useEffect` on every project list change. The bare `getDocs` will attempt server-first reads, causing the home screen to stall when offline. The caller at `app/(tabs)/index.tsx:136` should pass `'offline'` once the parameter is available.

### 3. Service `refresh*` functions default to `'online'` mode (footgun for future callers)
**File:** Multiple files in `src/data/`
**Type:** Service functions with wrong default mode
**Severity:** Medium
**Snippet:**
```typescript
// src/data/budgetCategoriesService.ts:65
export async function refreshBudgetCategories(accountId: string, mode: 'online' | 'offline' = 'online')

// src/data/projectBudgetCategoriesService.ts:54
export async function refreshProjectBudgetCategories(accountId: string, projectId: string, mode: 'online' | 'offline' = 'online')

// src/data/budgetProgressService.ts:124
export async function refreshProjectBudgetProgress(accountId: string, projectId: string, mode: 'online' | 'offline' = 'online')

// src/data/spacesService.ts:75
export async function refreshSpaces(accountId: string, projectId: string | null, mode: 'online' | 'offline' = 'online')

// src/data/scopedListData.ts:190
export async function refreshScopedItems(accountId: string, scopeConfig: ScopeConfig, mode: 'online' | 'offline' = 'online')

// src/data/scopedListData.ts:207
export async function refreshScopedTransactions(accountId: string, scopeConfig: ScopeConfig, mode: 'online' | 'offline' = 'online')

// src/data/accountPresetsService.ts:51
export async function refreshAccountPresets(accountId: string, mode: 'online' | 'offline' = 'online')

// src/data/spaceTemplatesService.ts:55
export async function refreshSpaceTemplates(accountId: string, mode: 'online' | 'offline' = 'online')

// src/data/invitesService.ts:85
export async function fetchPendingInvites(accountId: string, mode: 'online' | 'offline' = 'online')

// src/data/itemsService.ts:102
const { limit: limitCount = 200, mode = 'online' } = options;  // listItemsByProject

// src/data/repository.ts:50
private mode: RepositoryMode = 'online'  // FirestoreRepository constructor

// src/data/repository.ts:212
export function createRepository<T>(path: string, mode: RepositoryMode = 'online')
```
**Fix:** Change the default mode from `'online'` to `'offline'` across all `refresh*`/`fetch*`/`list*` service functions and the `createRepository` helper. The offline-first architecture rule states that reads in save handlers must use cache-first mode. By defaulting to `'offline'`, callers that forget to specify a mode will be safe. The only callers that should use `'online'` are explicit pull-to-refresh handlers, which already pass `'online'` explicitly (e.g., `screen-two.tsx:47-49` and `index.tsx:233`). This is a "defense in depth" change -- all current callers are compliant, but the default is a footgun that violates the principle of least surprise.

### Compliant patterns (no violations)

The following patterns were audited and found to be compliant:

- **`app/items/new.tsx:100`** -- `getTransaction(accountId, transactionId, 'offline')` in `handleSubmit` -- correctly uses `'offline'` mode for a read that drives save logic (fetching budget category from linked transaction).
- **`app/items/[id]/index.tsx:141`** -- `getTransaction(accountId, transactionId.trim(), 'offline')` in `handleLinkTransaction` -- correctly uses `'offline'` mode.
- **`app/(tabs)/screen-two.tsx:47-49`** -- `refreshScopedItems/refreshScopedTransactions/refreshSpaces` with `'online'` -- correctly in a pull-to-refresh handler (`handleRefresh`), which is an allowed exception.
- **`app/(tabs)/index.tsx:173,200`** -- `refreshProjectBudgetCategories` and `refreshProjectBudgetProgress` with `'offline'` -- correctly uses cache-first in `useEffect` data load.
- **`app/(tabs)/index.tsx:233`** -- `createRepository(..., 'online')` in `handleRefresh` -- correctly uses server-first for explicit pull-to-refresh.
- **`app/(tabs)/settings.tsx:870`** -- `fetchPendingInvites(accountIdValue, isOnline ? 'online' : 'offline')` -- correctly adapts mode based on connectivity status.
- **All save/submit handlers in `app/`** -- No handler performs an inline Firestore read immediately before a write using `'online'` mode. Data for forms comes from subscriptions (`subscribeToItem`, `subscribeToTransaction`, etc.) or React state, not from inline reads.

## Low Violations

**Audit scope:** Hooks (`src/hooks/`), stores (`src/data/*Store.ts`), and context stores (`src/auth/accountContextStore.ts`).

_No violations found in hooks and stores._

**Files audited:** 7 files
- `src/hooks/useNetworkStatus.ts` — Only awaits `checkFirebaseHealth()` (a read-only health check). No Firestore writes. Clean.
- `src/hooks/useOutsideItems.ts` — Only awaits `listItemsByProject()` read operations with `mode: 'offline'`. No Firestore writes. Clean.
- `src/hooks/useOptionalIsFocused.ts` — No awaits, no Firestore interaction. Clean.
- `src/hooks/useResponsiveGrid.ts` — No awaits, no Firestore interaction. Clean.
- `src/hooks/useDebouncedValue.ts` — No awaits, no Firestore interaction. Clean.
- `src/data/listStateStore.ts` — Zustand store. Only interacts with AsyncStorage (local). No Firestore writes. Clean.
- `src/data/projectContextStore.ts` — Zustand store. Only interacts with AsyncStorage (local). No Firestore writes. Clean.
- `src/auth/accountContextStore.ts` — Zustand store. Only performs Firestore reads (membership validation) and AsyncStorage writes. No Firestore writes. Clean.

**What was checked:**
1. No hooks contain `await setDoc`, `await updateDoc`, `await deleteDoc`, or `await addDoc` — confirmed zero matches.
2. No hooks await service-layer write functions (`await create*`, `await update*`, `await delete*`, `await save*`) — confirmed zero matches.
3. No hooks or stores use `isSubmitting`, `isSaving`, `isCreating`, `isDeleting`, or `isUpdating` loading states — confirmed zero matches.
4. All stores (`listStateStore`, `projectContextStore`, `accountContextStore`) only interact with AsyncStorage (local SQLite/key-value) and Firestore reads — no Firestore write operations.

**Positive finding — UI callers correctly use fire-and-forget:**
All `app/` screens and `src/components/` files that call the awaited service functions (flagged in High Violations above) do so **without `await`** and with `.catch()` for error logging. This means the UI is not blocking on the service-layer `await` — the promise floats. Examples:
- `updateSpace(accountId, spaceId, {...}).catch(err => console.warn(...))`
- `deleteItem(accountId, id).catch(err => console.warn(...))`
- `updateTransaction(accountId, id, {...}).catch(err => console.warn(...))`
- `updateBudgetCategory(accountId, id, {...}).catch(error => console.error(...))`

This fire-and-forget call pattern at the UI layer mitigates the impact of the High Violations in the service layer. However, fixing the service-layer awaits (High Violations #1–17) is still recommended because: (a) it prevents accidental future `await` usage by new callers, (b) it ensures `trackPendingWrite()` is called immediately rather than after write acknowledgment, and (c) it aligns the service function signatures with their intended fire-and-forget semantics.

---

## Summary

**Audit scope:** All files in `src/data/` — service layer functions that interact with Firestore.

**Files audited:** 13 files
- `accountPresetsService.ts`, `accountsService.ts`, `budgetCategoriesService.ts`, `businessProfileService.ts`, `invitesService.ts`, `itemsService.ts`, `projectBudgetCategoriesService.ts`, `projectPreferencesService.ts`, `projectService.ts`, `repository.ts`, `requestDocs.ts`, `spacesService.ts`, `spaceTemplatesService.ts`, `transactionsService.ts`, `vendorDefaultsService.ts`

**Known exceptions (not flagged):**
- `createAccountWithOwner` (`accountsService.ts`) — uses `addDoc` + awaited writes intentionally
- `createInvite` (`invitesService.ts`) — uses `addDoc` + awaited writes intentionally
- `ensureProjectPreferences` (`projectPreferencesService.ts`) — legitimately async (does reads before conditional write; write itself is already fire-and-forget)

**What is compliant:**
- All `create*` functions (except known exceptions) use `doc(collection(...))` + `setDoc` correctly and return IDs synchronously
- All Firestore write functions call `trackPendingWrite()` after writes
- All `create*` functions use fire-and-forget `.catch()` pattern correctly

**Single violation pattern found:** 17 high-severity instances of awaited Firestore writes in update/delete/save service functions. These are all pure write operations that should use fire-and-forget with `.catch()` instead of `await`, because awaiting causes the UI to block when the device is offline or on a slow network.

**Downstream impact:** Changing `repository.ts` `upsert`/`delete` to fire-and-forget will automatically fix `updateProject` and `deleteProject` in `projectService.ts` (which delegate to the repository). Similarly, fixing `updateSpaceTemplate` will fix `setSpaceTemplateArchived`, fixing `updateBudgetCategory` will fix `setBudgetCategoryArchived`, and fixing `saveVendorDefaults` will fix `replaceVendorSlots`.

**Recommended fix order:**
1. `repository.ts` (fixes generic repo + projectService callers)
2. `itemsService.ts` (high-traffic: items are edited/deleted frequently)
3. `transactionsService.ts` (high-traffic: transactions are edited/deleted frequently)
4. `spacesService.ts` (update + soft-delete)
5. `budgetCategoriesService.ts` (update, delete, reorder)
6. `spaceTemplatesService.ts` (update, reorder)
7. `accountPresetsService.ts`, `vendorDefaultsService.ts`, `projectPreferencesService.ts`, `businessProfileService.ts` (lower traffic)
