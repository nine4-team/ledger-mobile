956547956547956547956547956547956547956547956547# Ledger Mobile — Architecture

Ledger Mobile is an interior design project management app for small teams (2–5 users). Designers create projects, track items and transactions, manage budgets by category, and capture photos — often from job sites with poor or no connectivity. The app must work offline and sync transparently when connectivity returns.

**Tech stack**: Expo (React Native), TypeScript, Expo Router, Firebase (Auth, Firestore, Storage, Cloud Functions). The Firestore SDK is `@react-native-firebase/*` (native modules), NOT the JS web SDK.

---

## Core Principle

**Firestore's native SDK is the local database.** Every write applies to the local cache instantly. The SDK syncs to the server in the background. The user never waits for server acknowledgment. Offline is not an error state — it's the default operating mode.

This means: no custom sync engine, no outbox table, no cursor-based pulls, no client-side conflict resolution. The SDK handles all of this.

---

## The Four Write Tiers

Every mutation in the app falls into one of four tiers. Use the lowest tier that satisfies the requirements.

### Tier 1: Single-Doc Fire-and-Forget (the default)

**When**: A user edits fields on one document. This is the vast majority of writes.

**Examples**: editing project name, setting budget amounts, editing item details (name, price, SKU, notes), editing transaction details, changing space assignments, linking items to transactions, archiving/unarchiving entities.

**Pattern**:

```ts
// Service layer (src/data/*)
export function updateItem(accountId: string, itemId: string, data: Partial<Item>): void {
  const ref = doc(db, `accounts/${accountId}/items/${itemId}`);
  setDoc(ref, { ...data, updatedAt: serverTimestamp() }, { merge: true })
    .catch(err => console.error('[items] update failed:', err));
  trackPendingWrite();
}

// Screen layer (app/*)
updateItem(accountId, itemId, { name: name.trim(), notes: notes.trim() });
router.back(); // navigate immediately, don't await
```

**Rules**:
- Never `await` Firestore writes in UI code
- Always call `trackPendingWrite()` after the write
- Use `setDoc` with `{ merge: true }` for idempotency
- Navigate immediately after writing

**On "high-risk" fields** (budgetCents, amountCents, purchasePriceCents): these stay in Tier 1. Last-write-wins is acceptable because concurrent edits are rare in small teams, and the Firestore local cache ensures the writing user sees their value immediately. If this becomes a problem, add lightweight `updatedAt` checks in security rules — not request-docs.

### Tier 2: Request-Doc (multi-doc atomic operations)

**When**: A user action must update multiple documents atomically, AND partial application would create inconsistent state.

**Examples**: moving items between projects/inventory (touches item doc + canonical sale transaction + lineage edges), any future operation that updates a parent + multiple children atomically.

**Pattern**: Client creates a request document (fire-and-forget, works offline). A Cloud Function triggers on creation, processes the operation in a Firestore transaction, and sets the request status to `applied` or `failed`.

```ts
// Client: fire-and-forget
const opId = generateRequestOpId();
createRequestDoc('ITEM_SALE_PROJECT_TO_BUSINESS', payload, scope, opId);

// Server: Cloud Function processes atomically
// - Validates preconditions (item hasn't moved since user initiated)
// - Updates item, creates/updates canonical transaction, appends lineage
// - Sets request status to 'applied' or 'failed'
// - Deduplicates via opId
```

Currently implemented request types:
- `ITEM_SALE_PROJECT_TO_BUSINESS` — move item from project to business inventory
- `ITEM_SALE_BUSINESS_TO_PROJECT` — move item from business inventory to project
- `ITEM_SALE_PROJECT_TO_PROJECT` — transfer item between projects

**Key files**: `src/data/requestDocs.ts` (client helpers), `firebase/functions/src/index.ts` (handlers).

### Tier 3: Callable Function (server-owned creation)

**When**: The operation creates foundational entities where the server must be the authority, or touches security-sensitive state. These require connectivity.

**Examples**:
- `createAccount` — creates account + owner membership + seeds budget presets
- `createProject` — creates project + seeds preferences + pins default budget category
- `acceptInvite` — validates token + creates membership + marks invite used

**Pattern**: Client calls `httpsCallable()`. Server validates auth, runs a Firestore transaction, returns the result.

### Tier 4: Server Trigger (background cleanup)

**When**: The system reacts to a document change with bookkeeping that isn't user-facing or latency-critical. Failure doesn't block the user.

**Examples**:
- `onSpaceArchived` — clears `spaceId` from items when a space is soft-deleted
- `onItemTransactionIdChanged` — appends lineage edges for audit trail
- `onAccountMembershipCreated` — seeds budget category presets

**Pattern**: Firestore `onDocumentCreated` / `onDocumentUpdated` trigger. Runs in the background.

---

## Reliability Rules

These prevent broken behavior: items not appearing, duplicates, edits not persisting, loading hangs.

### 1. Subscriptions are the UI source of truth

Screens subscribe to Firestore via `onSnapshot` listeners. The UI renders what the subscription returns. When a write happens, Firestore updates the local cache, which triggers the subscription, which updates the UI.

**The loop**: write → local cache update → subscription fires → UI updates.

Don't build parallel state that drifts from the subscription. Edit screens are the exception (see rule 2).

### 2. Edit screens: populate once, then user owns the state

```ts
const userHasEdited = useRef(false);

useEffect(() => {
  const unsub = subscribeToData(id, (data) => {
    if (!userHasEdited.current) {
      setFormState(data);
    }
    setIsLoading(false);
  });
  return unsub;
}, [id]);

const handleChange = (value) => {
  userHasEdited.current = true;
  setFormState(prev => ({ ...prev, field: value }));
};
```

Subscribe to the document. Populate form state from the first callback(s). Once the user starts editing, stop accepting subscription updates. On save, write form values back (fire-and-forget) and navigate away.

### 3. Client-side ID generation

All `create*` service functions generate the document ID synchronously using `doc(collection(db, path))`, then use `setDoc`. The ID is available immediately for navigation and linking — no server round-trip needed.

```ts
export function createItem(accountId: string, data: Partial<Item>): string {
  const ref = doc(collection(db, `accounts/${accountId}/items`));
  setDoc(ref, { ...data, createdAt: serverTimestamp() }).catch(...);
  trackPendingWrite();
  return ref.id; // available immediately
}
```

### 4. No loading states that block on server acknowledgment

If local/cached data exists, show it immediately. Loading states are only for the initial data fetch (cache empty), not for write acknowledgment. Never gate UI on `isSaving` or `isSubmitting` that waits for a Firestore write to resolve.

### 5. Idempotent writes

Use `setDoc` with `{ merge: true }` so re-executing a write (retry, duplicate tap) doesn't corrupt data. For request-doc operations, use `opId` for server-side deduplication.

### 6. Soft deletes

Set `isArchived: true` instead of deleting documents. This prevents listener-triggered bugs, allows undo, and avoids "item disappeared" confusion.

---

## Subscription Patterns

### Cache-first double-callback

React Native Firebase's `onSnapshot` does NOT read from cache first — it waits for a server round-trip (5–7 second delay on first callback). Use `getDocsFromCache` as a prelude for instant loading.

```ts
export function subscribeToItems(accountId: string, onChange: (items: Item[]) => void): Unsubscribe {
  const ref = collection(db, `accounts/${accountId}/items`);

  // Instant cache response
  getDocsFromCache(ref)
    .then(snapshot => onChange(snapshot.docs.map(d => ({ ...d.data(), id: d.id }))))
    .catch(() => onChange([]));

  // Real-time updates (first callback waits for server)
  return onSnapshot(ref, snapshot => {
    onChange(snapshot.docs.map(d => ({ ...d.data(), id: d.id })));
  });
}
```

**This double-callback is intentional.** Do NOT remove `getDocsFromCache` thinking `onSnapshot` handles cache-first — that's only true in the JS web SDK.

The `Repository` class (`src/data/repository.ts`) encapsulates this pattern in `subscribe()` and `subscribeList()` methods, with a `mode` parameter controlling read preference (`'online'` for server-first, `'offline'` for cache-first).

### Scoped listener lifecycle

The `ScopedListenerManager` (`src/data/listenerManager.ts`) manages listener lifecycle by scope (e.g., `project:{id}`, `account:{id}`). It:
- Detaches all listeners when the app goes to background
- Reattaches when the app resumes
- Cleans up when a scope is removed (e.g., navigating away from a project)

Limits: 5–10 listeners per scope, 1–2 active scopes at a time. Don't create unbounded global listeners.

---

## Module Boundaries

### Data layer (`src/data/`)

All Firestore SDK usage lives here. Screens never import from `@react-native-firebase/firestore` directly.

This layer contains:
- **Service files** — subscription functions, write functions, CRUD operations per entity
- **`repository.ts`** — generic repository with cache-first subscribe/subscribeList
- **`listenerManager.ts`** — scoped listener lifecycle management
- **`requestDocs.ts`** — client-side request-doc creation helpers

### Sync layer (`src/sync/`)

- **`pendingWrites.ts`** — tracks pending writes via `trackPendingWrite()` so the app can show sync status

### Screen layer (`app/`)

Screens call service functions from `src/data/`. They never touch Firestore directly. They own form state for edit screens and delegate all persistence to the data layer.

### Cloud Functions (`firebase/functions/`)

All server-side logic: request-doc handlers, callable functions, Firestore triggers. The single entry point is `firebase/functions/src/index.ts`.

---

## Security Model (summary)

- **Account isolation**: all data scoped under `accounts/{accountId}/`. Security rules enforce that users can only read/write within accounts they're members of.
- **Membership + roles**: owner, admin, user. Checked in security rules and callable functions.
- **Request-doc security**: clients can create requests (`status: 'pending'`). Only Cloud Functions can set `status: 'applied'` or `'failed'`.
- **Storage**: scoped by tenant/project path. Rules enforce authenticated access within account boundaries.
- **Auth operations**: `createAccount`, `acceptInvite` are callables that validate identity server-side.

---

## What We Explicitly Do NOT Build

- **Custom sync engine or outbox** — Firestore's native SDK handles offline persistence and sync
- **Cursor-based pulls** — `onSnapshot` provides real-time updates
- **Client-side conflict resolution** — last-write-wins for single docs; server-side transactions for multi-doc
- **Request-doc workflows for single-doc edits** — even for money fields. Last-write-wins is correct for small teams
- **Compare-before-commit UX** — no "someone else edited this" dialogs. Too complex, too rare to justify
- **Fine-grained per-field permissions** — simple role-based access is sufficient for MVP
