# Prompt Pack — Chat A: Service Layer Refactoring

## Goal

Refactor the service layer so all `create*` functions return document IDs **synchronously** and all write service functions call `trackPendingWrite()`. This is the foundation that all subsequent UI refactoring depends on.

## Required Reading

- Architecture: `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`
- Rules: `CLAUDE.md` § Offline-First Coding Rules

## Rules (non-negotiable)

1. **Never `await` Firestore write operations in UI code.** Fire-and-forget with `.catch()`.
2. **All `create*` service functions must return document IDs synchronously** using `doc(collection(...))` + `setDoc`, not `addDoc`.
3. **Read operations in save handlers must use cache-first mode** (`'offline'`).
4. **All Firestore write service functions must call `trackPendingWrite()`** after the write.

## Part 1A: Refactor `create*` Functions to Pre-generate IDs

`addDoc` won't resolve offline. Fix: pre-generate ID with `doc(collection(...))` (instant, local-only), use `setDoc` fire-and-forget, return ID synchronously.

### Pattern

```typescript
// BEFORE (blocks offline):
export async function createItem(accountId: string, data: any): Promise<string> {
  const docRef = await addDoc(collection(db, path), { ... });
  trackPendingWrite();
  return docRef.id;
}

// AFTER (instant):
export function createItem(accountId: string, data: any): string {
  const docRef = doc(collection(db, path));
  setDoc(docRef, { ... }).catch(err => console.error('[items] create failed:', err));
  trackPendingWrite();
  return docRef.id;
}
```

### Files to Refactor

| File | Function | Notes |
|------|----------|-------|
| `src/data/itemsService.ts` | `createItem` (~line 135) | Change return type from `Promise<string>` to `string` |
| `src/data/transactionsService.ts` | `createTransaction` (~line 46) | Change return type from `Promise<string>` to `string` |
| `src/data/spacesService.ts` | `createSpace` (~line 101) | Change return type from `Promise<string>` to `string` |
| `src/data/budgetCategoriesService.ts` | `createBudgetCategory` (~line 107) | Change return type from `Promise<string>` to `string` |
| `src/data/spaceTemplatesService.ts` | `createSpaceTemplate` (~line 87) | Change return type from `Promise<string>` to `string` |
| `src/data/requestDocs.ts` | `createRequestDoc` (~line 70) | After `setDoc`, still call `trackRequestDocPath(docRef.path)` synchronously since the path is known from the pre-generated ref |

### Import Changes

Each file will need `doc` and `setDoc` imported from `firebase/firestore` (replacing or supplementing `addDoc`). Remove `addDoc` imports if no longer used.

## Part 1B: Refactor `createProject` from Cloud Function to Client-side

The Cloud Function (`firebase/functions/src/index.ts` lines 1276-1343) does:
1. Creates project doc (single-doc write)
2. Creates project preferences with pinned "Furnishings" category (independent single-doc write)
3. Calls `ensureBudgetCategoryPresetsSeeded` (already handled by `onAccountMembershipCreated` trigger at line 1217)

These are two independent single-doc writes — no multi-doc atomicity needed.

### Changes

**File: `src/data/projectService.ts`**
- Change `createProject` from `httpsCallable` to client-side `doc(collection(...))` + `setDoc`
- Return `{ projectId }` synchronously (matching existing `CreateProjectResponse` type)
- Fire-and-forget both the project doc write and the preferences write
- The client can look up the Furnishings category ID from its cached budget categories for pinning

**File: `app/project/new.tsx`** (covered in Chat E, but the service change lands here)

## Part 1C: Add Missing `trackPendingWrite()` + Imports

Add `trackPendingWrite()` calls after every Firestore write that doesn't already have one. Add the import from the sync status module.

| File | Functions Missing Tracking |
|------|---------------------------|
| `src/data/budgetCategoriesService.ts` | `createBudgetCategory`, `updateBudgetCategory`, `deleteBudgetCategory`, `setBudgetCategoryOrder` |
| `src/data/projectBudgetCategoriesService.ts` | `setProjectBudgetCategory` |
| `src/data/businessProfileService.ts` | `saveBusinessProfile` |
| `src/data/projectPreferencesService.ts` | `updateProjectPreferences` |
| `src/data/accountPresetsService.ts` | `updateAccountPresets` |
| `src/data/spaceTemplatesService.ts` | All write functions |
| `src/data/vendorDefaultsService.ts` | `saveVendorDefaults` |

## Part 1D: Fix Cache-first Reads in Save Handlers

Two `getTransaction` calls use `mode: 'online'` (server-first), which blocks on poor connectivity. Change to `mode: 'offline'` (cache-first with server fallback).

| File | Approx Line | Change |
|------|-------------|--------|
| `app/items/[id]/index.tsx` | ~140 | `getTransaction(accountId, transactionId.trim(), 'offline')` |
| `app/items/new.tsx` | ~102 | `getTransaction(accountId, transactionId, 'offline')` |

## Verification

1. `npx tsc --noEmit` — all callers of `create*` functions must still compile (return type changed from `Promise<string>` to `string`; callers that `await` a non-Promise get a TS warning or are harmless).
2. Grep for remaining `addDoc` usage — should only exist in functions with legitimate reasons (none expected).
3. Grep for `trackPendingWrite` — every `setDoc`, `updateDoc`, `deleteDoc` call in `src/data/` should have one nearby.

## Exceptions (do NOT change these)

- `createAccountWithOwner` / `createInvite` / `acceptInvite` — multi-doc server transactions, keep awaited.
- Firebase Storage upload functions (`enqueueUpload`, `processUploadQueue`, `uploadBusinessLogo`) — byte uploads require connectivity, keep awaited.
- Firebase Auth operations — require connectivity, keep awaited.
