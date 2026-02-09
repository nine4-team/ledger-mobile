# Offline-First Architecture Audit Prompt

Use this prompt with an AI assistant to perform a comprehensive audit of offline-first violations in the codebase.

---

## Your Task

Perform a thorough audit of this React Native/Expo codebase to identify violations of offline-first architecture principles. This is a critical review — the app must work seamlessly when connectivity is poor or absent.

## Critical Rules (from CLAUDE.md)

These are **non-negotiable**. Violating them causes the app to hang when connectivity is poor.

1. **Never `await` Firestore write operations in UI code.** Use fire-and-forget with `.catch()` for error logging. Navigation and UI state updates happen immediately.
2. **All `create*` service functions must return document IDs synchronously** using pre-generated IDs via `doc(collection(...))`, not `addDoc`.
3. **Read operations in save/submit handlers must use cache-first mode** (`mode: 'offline'`). Server-first reads (`mode: 'online'`) are only for explicit pull-to-refresh.
4. **No "spinners of doom"** — never show loading states that block on server acknowledgment. If local data exists, show it immediately.
5. **Only actual byte uploads (Firebase Storage) and Firebase Auth operations may require connectivity.** All Firestore writes (including request-doc creation) must work offline.
6. **All Firestore write service functions must call `trackPendingWrite()`** after the write for sync status visibility.

## What to Search For

### 1. Awaited Firestore Writes in UI Code

**Search pattern:**
```bash
grep -rn "await.*\(setDoc\|updateDoc\|deleteDoc\|addDoc\)" app/ src/components/ src/screens/
```

**What to check:**
- Any `await setDoc(...)`, `await updateDoc(...)`, `await deleteDoc(...)`, `await addDoc(...)` in:
  - Component files (`*.tsx` in `app/`, `src/components/`, `src/screens/`)
  - Event handlers (onPress, onSubmit, handleSave, etc.)
  - Hooks that are triggered by user actions

**Exceptions allowed:**
- Inside try-catch blocks that show specific error messages to the user
- Auth operations (`auth.signIn`, `auth.createUser`, etc.)
- Firebase Storage uploads (`uploadBytes`, `uploadString`)

**Fix pattern:**
```typescript
// BEFORE (blocking):
await setDoc(ref, data);
trackPendingWrite();
router.back();

// AFTER (fire-and-forget):
setDoc(ref, data).catch(err => console.error('[context] write failed:', err));
trackPendingWrite();
router.back();
```

---

### 2. Service Functions Using `addDoc` Instead of Pre-Generated IDs

**Search pattern:**
```bash
grep -rn "addDoc" src/data/
```

**What to check:**
- Any `create*` service function that uses `addDoc(collection(...), data)` instead of `doc(collection(...))`
- Functions that return `Promise<string>` (the ID) but use `await addDoc`

**Why this is bad:**
`addDoc` requires a server round-trip to generate the ID. With poor connectivity, this blocks for 10-60+ seconds.

**Fix pattern:**
```typescript
// BEFORE:
export async function createItem(accountId: string, data: ItemInput): Promise<string> {
  const ref = await addDoc(collection(db, `accounts/${accountId}/items`), data);
  trackPendingWrite();
  return ref.id;
}

// AFTER:
export function createItem(accountId: string, data: ItemInput): string {
  const ref = doc(collection(db, `accounts/${accountId}/items`));
  setDoc(ref, data).catch(err => console.error('[itemsService] createItem failed:', err));
  trackPendingWrite();
  return ref.id;
}
```

---

### 3. `'online'` Mode Reads in Save/Submit Handlers

**Search pattern:**
```bash
grep -rn "refresh.*'online'" src/data/
grep -rn "mode.*:.*'online'" src/data/
```

**What to check:**
- Any `refresh*` or `fetch*` service function calls with `'online'` mode
- Reads that happen inside save/submit/create flows (not pull-to-refresh)

**Context clues for save flows:**
- Inside `handleSave`, `handleSubmit`, `onCreate`, etc.
- Called after a Firestore write to read the result
- Called to validate data before saving

**Exceptions allowed:**
- Explicit user-triggered refresh (pull-to-refresh, "Sync Now" button)
- Initial data load on screen mount (debatable, but common pattern)

**Fix pattern:**
```typescript
// BEFORE:
const categories = await refreshBudgetCategories(accountId, 'online');

// AFTER (in save handlers):
const categories = await refreshBudgetCategories(accountId, 'offline');
```

---

### 4. Loading States That Block on Firestore Write Completion

**Search pattern:**
```bash
grep -rn "isSubmitting\|isSaving\|isCreating" app/ src/components/ src/screens/
```

**What to check:**
- Any `isSubmitting`, `isSaving`, `isCreating` state that:
  - Is set to `true` before a Firestore write
  - Is set to `false` after awaiting the write
  - Blocks navigation, disables forms, or shows a spinner until the write completes

**Why this is bad:**
If the write is awaited, the UI hangs until the server acknowledges. This can take 60+ seconds offline.

**Exceptions allowed:**
- Loading states for **reads** (fetching data from Firestore)
- Loading states for **Storage uploads** (byte transfers require connectivity)
- Loading states for **Auth operations** (sign in, create account)

**Fix pattern:**
```typescript
// BEFORE:
const [isSaving, setIsSaving] = useState(false);
const handleSave = async () => {
  setIsSaving(true);
  await setDoc(ref, data);
  setIsSaving(false);
  router.back();
};

// AFTER:
const handleSave = () => {
  setDoc(ref, data).catch(err => console.error('[context] save failed:', err));
  trackPendingWrite();
  router.back();
};
```

---

### 5. Missing `trackPendingWrite()` Calls After Firestore Writes

**Search pattern:**
```bash
# Find all setDoc/updateDoc/deleteDoc calls
grep -rn "setDoc\|updateDoc\|deleteDoc" src/data/

# Then manually verify each has trackPendingWrite() after it
```

**What to check:**
- Every `setDoc`, `updateDoc`, `deleteDoc` call in service files should be followed by `trackPendingWrite()`
- Exception: Writes inside transactions (tracked differently)

**Why this matters:**
`trackPendingWrite()` increments a counter that shows the user when there are unsynced changes.

---

### 6. Service Functions That Should Be Synchronous But Return `Promise`

**Search pattern:**
```bash
grep -rn "^export async function create" src/data/
```

**What to check:**
- `create*` functions that:
  - Only write to Firestore (no reads, no Storage uploads)
  - Return a generated ID
  - Use `await` on the write

**These should be synchronous:**
```typescript
// BEFORE:
export async function createSpace(accountId: string, projectId: string, data: SpaceInput): Promise<string> {
  const ref = doc(collection(db, `accounts/${accountId}/projects/${projectId}/spaces`));
  await setDoc(ref, { ...data, createdAt: serverTimestamp() });
  trackPendingWrite();
  return ref.id;
}

// AFTER:
export function createSpace(accountId: string, projectId: string, data: SpaceInput): string {
  const ref = doc(collection(db, `accounts/${accountId}/projects/${projectId}/spaces`));
  setDoc(ref, { ...data, createdAt: serverTimestamp() }).catch(err => console.error('[spacesService] createSpace failed:', err));
  trackPendingWrite();
  return ref.id;
}
```

---

### 7. Edge Case: Reads That Drive Subsequent Logic in Save Handlers

**What to check:**
- Reads inside save handlers that are used to compute the data being written
- Example: Reading current budget before saving a transaction to validate against it

**Pattern to look for:**
```typescript
const handleSave = async () => {
  const budget = await getBudgetCategory(categoryId);  // <-- Read
  const newTransaction = { amount, categoryId, budgetLimit: budget.limit };  // <-- Uses read result
  await saveTransaction(newTransaction);  // <-- Depends on read
};
```

**These reads CAN be awaited, but MUST use `'offline'` mode:**
```typescript
const budget = await getBudgetCategory(categoryId, 'offline');  // <-- Cache-first
```

---

## Output Format

For each violation found, report:

1. **File path and line number**
2. **Violation type** (e.g., "Awaited Firestore write in UI code")
3. **Code snippet** (5-10 lines of context)
4. **Severity**: Critical / High / Medium / Low
5. **Recommended fix** (brief description or code example)

Group by severity, with Critical issues first.

At the end, provide:
- **Total violations count** by type
- **Summary of most common patterns**
- **Prioritized fix list** (which files to address first)

---

## Example Output

### Critical Violations

#### 1. Awaited Firestore write in UI code
**File:** `app/items/new.tsx:87`
**Snippet:**
```typescript
const handleSubmit = async () => {
  setIsSubmitting(true);
  await setDoc(ref, data);  // <-- BLOCKS until server responds
  setIsSubmitting(false);
  router.back();
};
```
**Fix:** Remove `await`, call `.catch()` for errors, remove `isSubmitting` state
```typescript
const handleSubmit = () => {
  setDoc(ref, data).catch(err => console.error('[items/new] save failed:', err));
  trackPendingWrite();
  router.back();
};
```

---

### High Violations

#### 2. Service function uses addDoc instead of pre-generated ID
**File:** `src/data/transactionsService.ts:45`
**Snippet:**
```typescript
export async function createTransaction(accountId: string, data: TransactionInput): Promise<string> {
  const ref = await addDoc(collection(db, `accounts/${accountId}/transactions`), data);
  return ref.id;
}
```
**Fix:** Use `doc(collection(...))` to generate ID synchronously
```typescript
export function createTransaction(accountId: string, data: TransactionInput): string {
  const ref = doc(collection(db, `accounts/${accountId}/transactions`));
  setDoc(ref, data).catch(err => console.error('[transactionsService] createTransaction failed:', err));
  trackPendingWrite();
  return ref.id;
}
```

---

## Files to Audit

### High Priority (User-facing write flows)
- `app/items/new.tsx`, `app/items/[id]/edit.tsx`
- `app/transactions/new.tsx`, `app/transactions/[id]/edit.tsx`
- `app/project/new.tsx`, `app/project/[id]/edit.tsx`
- `app/project/[id]/spaces/new.tsx`, `app/project/[id]/spaces/[spaceId].tsx`
- `app/(tabs)/settings.tsx`

### Medium Priority (Service layer)
- `src/data/*Service.ts` (all service files)
- Especially: `itemsService.ts`, `transactionsService.ts`, `projectsService.ts`, `spacesService.ts`

### Lower Priority (Components)
- `src/components/**/*.tsx` (shared components that might trigger saves)
- `src/screens/**/*.tsx` (if any screen-level logic exists outside `app/`)

---

## Pre-Existing Known Issues (Ignore These)

From MEMORY.md, these are known pre-existing TypeScript errors (not related to offline-first):
- `__tests__/` files: missing `@types/jest`
- `SharedItemsList.tsx`, `SharedTransactionsList.tsx`: icon type mismatches
- `resolveItemMove.ts`: variable shadowing (`budgetCategoryId`)
- `settings.tsx`: `BudgetCategoryType` union mismatch
- `accountContextStore.ts`: null handling

---

## Context: Recent Refactor

A recent offline-first refactor was completed (see `.claude/plans/offline-first-refactor/`). Many violations were fixed, but some may remain in:
- Newly added features after the refactor
- Edge cases missed in the original audit
- Service functions that were overlooked

Your job is to catch what was missed.

---

## Begin Audit

Start by running the grep commands above to identify candidate violations, then manually review each to confirm whether it's a true violation or an acceptable exception. Good luck!
