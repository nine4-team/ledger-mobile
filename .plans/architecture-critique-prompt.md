# Prompt: Critique the Ledger Mobile Architecture Document

## Your Role

You are a senior software architect reviewing an architecture document for a mobile app. Your job is to find weaknesses, unstated assumptions, missing failure modes, and anything that will bite the team in 6–12 months. Be direct. If a decision is correct, say so briefly and move on. Spend your time on what's wrong or risky.

---

## About the App

**Ledger Mobile** is a project management app for interior designers. Built with Expo (React Native) + Firebase (Auth, Firestore, Storage, Cloud Functions). The Firestore SDK is `@react-native-firebase/*` (native modules, not the JS web SDK).

**Users**: Interior designers. Non-technical. Teams of 2–5 people per account. They work from job sites with poor connectivity.

**Core workflows**:
- Create projects for clients, track items (furniture/fixtures), record transactions (purchases/returns)
- Allocate budgets per project per category (Furnishings, Install, Design Fee, etc.)
- Move items between projects and a shared business inventory
- Attach photos/receipts to items and transactions
- Everything must work offline and sync when connectivity returns

**Data model**: All data lives under `accounts/{accountId}/`. Items, transactions, projects, spaces, budget categories are all Firestore documents scoped to an account. Items can belong to a project or to business inventory (projectId = null).

---

## The Document to Critique

The following is the full text of the architecture document. It was written to be the single authoritative reference, replacing several older documents that were scattered and sometimes contradictory.

<architecture-document>

# Ledger Mobile — Architecture

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

The `Repository` class encapsulates this pattern in `subscribe()` and `subscribeList()` methods, with a `mode` parameter controlling read preference (`'online'` for server-first, `'offline'` for cache-first).

### Scoped listener lifecycle

The `ScopedListenerManager` manages listener lifecycle by scope (e.g., `project:{id}`, `account:{id}`). It:
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

</architecture-document>

---

## Context: The Key Decision This Document Makes

Previous architecture documents for this project took a more defensive stance on data correctness. Specifically, they classified writes by field risk level:

- **Low-risk fields** (text, notes, descriptions): last-write-wins acceptable
- **High-risk fields** (money amounts, budget allocations, category assignments, item ownership): should use request-doc workflows or compare-before-commit UX to prevent silent overwrites

The new architecture document **rejects this field-level classification** and instead classifies writes purely by document count:

- **Single-doc writes**: always fire-and-forget with last-write-wins, regardless of which fields are being written
- **Multi-doc writes**: use request-doc workflows for atomicity

The argument is:
1. Request-docs break offline-first for single-doc edits (the write doesn't apply until the Cloud Function runs)
2. Concurrent single-doc edits are near-zero probability in 2–5 person teams
3. Last-write-wins is easier for users to understand than "pending server approval" states
4. If concurrent editing becomes a real problem, add `updatedAt` checks in Firestore security rules (lightweight, no Cloud Function)

**This is the most important decision in the document. Stress-test it.**

---

## What to Critique

### 1. The conflict stance for money fields

Is last-write-wins on `budgetCents` truly safe for 2–5 person teams? Consider:
- Two designers editing the same project's budget categories simultaneously
- A designer editing a budget while another moves an item (which may create a canonical transaction affecting totals)
- Offline scenarios where two users make conflicting edits that sync later
- The claim that `updatedAt` security rule checks are a sufficient future mitigation

### 2. The tier boundaries

Are there operations currently classified as Tier 1 (single-doc) that should be Tier 2 (request-doc)? For example:
- Linking an item to a transaction (`item.transactionId = X`) — is this truly single-doc, or does it imply the transaction should also be updated?
- Changing `item.budgetCategoryId` — does this affect any derived state on the budget category or project?
- Archiving an entity — the doc says `isArchived: true` is Tier 1, but the `onSpaceArchived` trigger exists to clean up child references. Is this a hidden multi-doc operation masquerading as single-doc?

### 3. Failure modes not addressed

- What happens when a Tier 4 trigger fails? (e.g., `onSpaceArchived` fails to clear items). The doc says "failure doesn't block the user" — but does the user know? Is there a retry mechanism? Can the data get stuck in an inconsistent state?
- What happens when a request-doc Cloud Function fails repeatedly? Is there a dead letter / manual recovery path?
- What happens when a user's device has a large pending write queue (days offline) and comes back online? Does Firestore handle this gracefully at scale, or can the sync flood cause issues?

### 4. The edit screen pattern

The "populate once, then user owns state" pattern (Reliability Rule 2) — what happens if:
- User A opens an edit screen, walks away for 30 minutes, comes back and saves. User B edited the same doc in the meantime. User A's save silently reverts User B's changes (not just on the field they edited, but on ALL fields, since the form writes back the entire form state).
- This is not a concurrent edit in the traditional sense — it's a stale read + full overwrite. Is the architecture aware of this?

### 5. What's missing

- **Error visibility**: the doc says writes use `.catch(err => console.error(...))`. How does the user know a write failed? Is `trackPendingWrite()` sufficient? What if writes fail permanently (e.g., security rule rejection)?
- **Data migration / schema evolution**: no mention of how document schemas change over time. What happens when a new version of the app reads old documents?
- **Storage (photos/receipts)**: mentioned as a core workflow but barely addressed. What happens when a photo upload fails? Is there a retry queue? Can you have an item that references a photo URL that doesn't exist?
- **Testing strategy**: no mention of how to verify these patterns hold. How do you test offline behavior? How do you test that a new feature doesn't accidentally introduce a multi-doc client write?

### 6. The "do NOT build" list

For each item in the "What We Explicitly Do NOT Build" section, evaluate whether the reasoning is sound or whether it's premature optimization of simplicity. Specifically:
- "No compare-before-commit UX" — is there a lightweight version (e.g., timestamp-based staleness warning) that would catch the stale-read-full-overwrite problem without the complexity?
- "No fine-grained per-field permissions" — is this safe given that any team member can overwrite any money field on any project?

---

## Deliverable

Write your critique as a list of findings, ordered by severity (most concerning first). For each finding:

1. **What the doc says** (quote or paraphrase)
2. **What could go wrong** (concrete scenario, not abstract risk)
3. **How likely this is** given the 2–5 user team size and interior design use case
4. **Recommended action** (accept the risk, add a mitigation, or change the architecture)

End with an overall assessment: is this architecture sound for the stated use case, or does it have structural problems that will cause real user pain?
