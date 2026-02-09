# Prompt: Write Canonical Architecture Document for Ledger Mobile

## Your Task

Write a single, authoritative architecture document for Ledger Mobile that replaces the scattered guidance currently spread across multiple files. The new document should be practical, honest about tradeoffs, and focused on reliability for non-technical users.

Write it to: `.cursor/plans/firebase-mobile-migration/10_architecture/ARCHITECTURE.md`

---

## About This App

Ledger Mobile is an interior design project management app built with Expo (React Native) + Firebase. The primary users are interior designers who are NOT technical. They need to:

- Create projects, track items (furniture/fixtures), record transactions (purchases/sales)
- Allocate budgets per project per category (Furnishings, Install, Design Fee, etc.)
- Move items between projects and business inventory
- Capture photos/receipts attached to items and transactions
- Work reliably on job sites with poor connectivity

The team size per account is small (2-5 users). The app must work offline and sync when connectivity returns.

## Tech Stack

- **Client**: Expo (React Native), TypeScript, Expo Router
- **Backend**: Firebase (Auth, Firestore, Storage, Cloud Functions)
- **Firestore SDK**: `@react-native-firebase/*` (native modules, NOT the JS web SDK)
- **Offline persistence**: Firestore native SDK handles this automatically — local cache + queued writes

---

## What Works Today (preserve these patterns)

### 1. Fire-and-forget single-doc writes

All Firestore writes in UI code are fire-and-forget. The user taps Save, the write is queued locally, navigation happens immediately. No spinners waiting for server acknowledgment.

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

**Why this works**: Firestore applies writes to the local cache instantly. The user sees their changes immediately. The SDK syncs to the server in the background. If they're offline, the write queues and syncs later.

**Rule**: Never `await` Firestore writes in UI code. Exceptions: Firebase Auth operations, Firebase Storage uploads (actual byte transfers), local SQLite operations.

### 2. Cache-first subscriptions with getDocsFromCache prelude

The subscription pattern uses `getDocsFromCache` before `onSnapshot` because React Native Firebase's `onSnapshot` does NOT read from cache first — it waits for a server round-trip (5-7 second delay).

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

**Critical**: This double-callback pattern is intentional. Do NOT remove `getDocsFromCache` thinking `onSnapshot` handles cache-first — that's only true in the JS web SDK, not React Native Firebase.

### 3. Request-doc workflows for multi-doc atomic operations

When a user action must update multiple documents atomically (and partial application would create inconsistent state), the client creates a request document. A Cloud Function processes it in a Firestore transaction.

Currently implemented for:
- `ITEM_SALE_PROJECT_TO_BUSINESS` — move item from project to business inventory
- `ITEM_SALE_BUSINESS_TO_PROJECT` — move item from business inventory to project
- `ITEM_SALE_PROJECT_TO_PROJECT` — transfer item between projects

These operations touch: item doc, canonical sale transaction doc, lineage edges — all atomically with precondition checks.

```ts
// Client: fire-and-forget, works offline
const opId = generateRequestOpId();
createRequestDoc('ITEM_SALE_PROJECT_TO_BUSINESS', payload, scope, opId);

// Server: Cloud Function processes in transaction
// - Validates item hasn't moved since user initiated
// - Updates item, creates/updates canonical transaction, appends lineage
// - Sets request status to 'applied' or 'failed'
```

### 4. Callable Functions for server-owned creation

Operations where the server must be the authority:
- `createAccount` — creates account + owner membership atomically
- `createProject` — creates project + seeds preferences + ensures budget presets
- `acceptInvite` — validates token + creates membership + marks invite used

### 5. Data layer boundary

All Firestore SDK usage lives in `src/data/` service files. Screens in `app/` never import from `@react-native-firebase/firestore` directly. They call service functions.

### 6. Pending write visibility

Every write service function calls `trackPendingWrite()` after the Firestore write, so the app can show a sync status indicator.

---

## What's Over-Engineered in the Current Architecture Docs (simplify or remove)

### The conflict stance for single-doc writes is too aggressive

The current docs say high-risk fields (money, category allocation) should use request-doc workflows or compare-before-commit UX. This is wrong for single-doc edits because:

1. **It breaks offline-first.** Request-docs require server processing. Routing `budgetCents` through a request-doc means the edit doesn't apply until the Cloud Function runs. The user would see a "pending" state instead of their change. This contradicts the core principle that mutations are "done" when accepted locally.

2. **The probability of concurrent single-doc edits is near zero.** For a 2-5 person interior design team, two people editing the same budget field on the same project at the same time essentially doesn't happen.

3. **Last-write-wins is easy to understand.** If User A sets a budget to $5,000, they see $5,000. If User B then sets it to $7,000, everyone sees $7,000. No one is confused. Compare this to a "your edit is pending server approval" UX — that's confusing.

**The correct stance**: Request-doc workflows are for multi-doc operations where partial application creates inconsistent state. Single-doc edits (even to money fields) use fire-and-forget with last-write-wins. If concurrent editing becomes a real problem later, add lightweight conflict detection via Firestore security rules (check `updatedAt` matches what the client read), NOT request-docs.

### The "Phase 4 — Correctness framework" scope is too broad

The existing spec's Phase 4 implies every high-risk write needs a request-doc handler. In practice, only operations that are genuinely multi-doc and can create inconsistent state need this treatment.

---

## The Practical Risk Tiers (use these in the new doc)

### Tier 1: Request-doc required

**When**: A user action must update multiple documents atomically, AND partial application creates state that is hard to recover from.

**Examples**:
- Moving items between projects/inventory (item + transaction + lineage)
- Any future operation that updates a parent + multiple children atomically
- Operations that require server-side precondition validation ("has this item already been moved?")

**Pattern**: Client creates request doc (works offline). Cloud Function processes in Firestore transaction. Status tracked on request doc.

### Tier 2: Callable Function required

**When**: The operation creates foundational entities where the server must be the authority, OR the operation touches security-sensitive state.

**Examples**:
- Account creation (account doc + membership doc)
- Project creation (project doc + preferences + preset seeding)
- Invite acceptance (token validation + membership creation)
- Any future entitlement/billing checks

**Pattern**: Client calls `httpsCallable()`. Server validates, runs transaction, returns result. These require connectivity.

### Tier 3: Single-doc fire-and-forget (the default)

**When**: Everything else. A user edits a field on one document.

**Examples**:
- Editing project name, description, client name
- Setting budget amounts per category
- Editing item details (name, price, SKU, notes)
- Editing transaction details (amount, date, source)
- Changing an item's space assignment
- Linking/unlinking an item to a transaction
- Archiving/unarchiving entities (soft delete via `isArchived`)

**Pattern**: Service function calls `setDoc(ref, data, { merge: true })` fire-and-forget. `trackPendingWrite()`. UI navigates immediately.

**Note on "high-risk" fields in this tier**: Fields like `budgetCents`, `amountCents`, `purchasePriceCents` live here. Last-write-wins is acceptable because:
- These are single-document updates
- Concurrent edits are rare in small teams
- The Firestore local cache ensures the writing user sees their value immediately
- If concurrent editing becomes a problem, add `updatedAt` security rule checks (lightweight, no Cloud Function needed)

### Tier 4: Server trigger (background cleanup/audit)

**When**: The system needs to react to a document change with additional bookkeeping, but it's not user-facing or latency-critical.

**Examples**:
- `onSpaceArchived` — clear `spaceId` from items when a space is soft-deleted
- `onItemTransactionIdChanged` — append association lineage edge for audit trail
- `onAccountMembershipCreated` — seed budget category presets

**Pattern**: Firestore `onDocumentCreated`/`onDocumentUpdated` trigger. Runs in background. Failure doesn't block the user.

---

## Reliability Principles (what makes this not fragile)

These are the rules that prevent "weird shit" — items not appearing, duplicates, edits not persisting.

### 1. The subscription is the source of truth for the UI, not local component state

Screens subscribe to Firestore data via `onSnapshot` listeners. The UI renders what the subscription returns. When a write happens, Firestore updates the local cache, which triggers the subscription, which updates the UI. The loop is: **write → local cache update → subscription fires → UI updates**.

Don't build parallel state that can drift from the subscription. Edit screens are the exception — they copy subscription data into form state once, then let the user edit. On save, the form state is written back.

### 2. Edit screens: populate once, then user owns the state

For edit screens, the pattern is:
1. Subscribe to the document/collection
2. On first callback(s), populate form state
3. Once the user starts editing, stop accepting subscription updates (so their edits aren't overwritten)
4. On save, write all form values back (fire-and-forget)
5. Navigate away immediately

```ts
const userHasEdited = useRef(false);

// Subscription populates form until user starts editing
useEffect(() => {
  const unsub = subscribeToData(id, (data) => {
    if (!userHasEdited.current) {
      setFormState(data);
    }
    setIsLoading(false);
  });
  return unsub;
}, [id]);

// User interaction locks out subscription overwrites
const handleChange = (value) => {
  userHasEdited.current = true;
  setFormState(prev => ({ ...prev, field: value }));
};
```

### 3. IDs are generated client-side before the write

All `create*` functions generate the document ID synchronously using `doc(collection(db, path))`, then use `setDoc` (not `addDoc`). This means the ID is available immediately for navigation, linking, etc. — without waiting for a server round-trip.

```ts
export function createItem(accountId: string, data: Partial<Item>): string {
  const ref = doc(collection(db, `accounts/${accountId}/items`));
  setDoc(ref, { ...data, createdAt: serverTimestamp() }).catch(...);
  trackPendingWrite();
  return ref.id; // available immediately
}
```

### 4. Never show loading states that block on server acknowledgment

If local/cached data exists, show it immediately. Use the `getDocsFromCache` + `onSnapshot` pattern. Loading states are only for the initial data fetch, not for write acknowledgment.

### 5. Writes must be idempotent

Use `setDoc` with `{ merge: true }` so that re-executing the same write (e.g., retry, duplicate tap) doesn't corrupt data. For request-doc operations, use `opId` for server-side deduplication.

### 6. Soft deletes, not hard deletes

Set `isArchived: true` (or `deletedAt: timestamp`) instead of deleting documents. This prevents listener-safe issues, allows undo, and avoids "item disappeared" confusion.

---

## Existing Files to Reference

Read these to understand current implementation (but don't treat them as authoritative — the NEW document you write IS the authority):

- `src/data/requestDocs.ts` — client-side request-doc helpers
- `firebase/functions/src/index.ts` — all Cloud Functions (request handlers, callables, triggers)
- `src/data/repository.ts` — repository pattern implementation
- `src/data/listenerManager.ts` — scoped listener lifecycle
- `src/data/LISTENER_SCOPING.md` — listener scoping conventions
- `src/sync/pendingWrites.ts` — pending write tracking
- `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md` — good for UX invariants (Invariant A-D), over-prescriptive on conflict stance
- `.cursor/plans/firebase-mobile-migration/10_architecture/target_system_architecture.md` — good for system diagram and module boundaries
- `.cursor/plans/firebase-mobile-migration/10_architecture/security_model.md` — good for rules/functions guidance
- `.cursor/plans/firebase-mobile-migration/00_working_docs/OFFLINE_FIRST_V2_SPEC.md` — good for request-doc spec, over-prescriptive on applying request-docs to single-doc writes

---

## Structure for the New Document

Suggested outline (adjust as needed):

1. **What this app is** — 2-3 sentences. Interior design project management. Small teams. Must work offline.
2. **Core principle** — Firestore native SDK is the local database. Writes apply locally instantly. Sync is background and automatic.
3. **The four write tiers** — Request-doc, Callable Function, Single-doc fire-and-forget, Server trigger. When to use each. Examples.
4. **Reliability rules** — The 6 rules above that prevent broken behavior.
5. **Subscription patterns** — Cache-first double-callback, edit screen populate-once pattern.
6. **Module boundaries** — Data layer owns all Firestore access. Screens call service functions.
7. **What we explicitly do NOT build** — Custom sync engine, outbox, cursor pulls, conflict resolution tables, request-doc workflows for single-doc edits.

Keep it under 300 lines. This is a document people will actually read and follow. Every sentence should earn its place.
