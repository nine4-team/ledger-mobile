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

**On "high-risk" fields** (budgetCents, amountCents, purchasePriceCents): these stay in Tier 1. Last-write-wins is correct because these are source/planning data on single-owner documents — not derived totals. See [High-Risk Fields](#high-risk-fields-why-conflict-detection-is-not-required) for the full argument.

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

The `useEditForm<T>` hook (`src/hooks/useEditForm.ts`) encapsulates this pattern:

```ts
const form = useEditForm<ItemFormValues>(item);

// form.values           — current form state
// form.setField(k, v)   — update one field, marks hasEdited
// form.hasChanges       — true if any field differs from snapshot
// form.getChangedFields() — only the fields that changed (for partial writes)
// form.shouldAcceptSubscriptionData — true until first setField call
```

**Behavior**: The hook captures a snapshot from the first non-null `initialData`. Subscription updates flow through until the user makes their first edit (`setField`), then the form freezes and only tracks user changes. On save, `getChangedFields()` returns only modified fields for a partial write.

All edit screens (project, spaces, budget categories, items, transactions) use this hook. See [Edit Form Patterns](#edit-form-patterns) for details.

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

## Edit Form Patterns

All edit screens use the `useEditForm<T>` hook (`src/hooks/useEditForm.ts`) for state management and change tracking.

### Basic Usage

```ts
// In an edit screen component
const form = useEditForm<ProjectFormValues>(project);

const handleSave = () => {
  if (!form.hasChanges) {
    router.back(); // No changes — skip the write entirely
    return;
  }
  const changes = form.getChangedFields();
  updateProject(accountId, projectId, changes).catch(console.error);
  router.back(); // Navigate immediately (fire-and-forget)
};
```

### How It Works

1. **Snapshot capture**: First non-null `initialData` is stored as the comparison baseline
2. **Subscription passthrough**: Until the user edits, subscription updates flow through to form state
3. **Edit freeze**: After the first `setField()` call, subscription updates are ignored — the user owns the form
4. **Change detection**: `getChangedFields()` does shallow per-key comparison against the snapshot, normalizing `null` ≈ `undefined` (Firestore doesn't store `undefined`)

### Why Partial Writes Matter

`getChangedFields()` ensures only modified fields are written to Firestore:

- **Reduces write costs** — Firestore charges per field written
- **Improves offline performance** — smaller payloads in the sync queue
- **Prevents unintentional overwrites** — subscription-delivered fields aren't sent back
- **Enables no-change detection** — skip writes entirely when `hasChanges` is false

### Screens Using This Pattern

| Screen | File | Fields |
|--------|------|--------|
| Project edit | `app/project/[projectId]/edit.tsx` | name, clientName, description |
| Space edit (business) | `app/business-inventory/spaces/[spaceId]/edit.tsx` | name, notes |
| Space edit (project) | `app/project/[projectId]/spaces/[spaceId]/edit.tsx` | name, notes |
| Budget category edit | `app/(tabs)/settings.tsx` | name, slug, metadata |
| Item edit | `app/items/[id]/edit.tsx` | 9 fields (name, prices, quantity, etc.) |
| Transaction edit | `app/transactions/[id]/edit.tsx` | 13 fields (most complex) |

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

## High-Risk Fields: Why Conflict Detection Is Not Required

Fields like `budgetCents`, `purchasePriceCents`, `estimatedPriceCents`, and `salePriceCents` are **source/planning data, not derived totals**. They represent direct user input on a single document, and the correct value is whatever the user last entered.

### Key Distinctions

**Source Data (no conflict detection needed)**:
- `budgetCents`: User's planned budget allocation for a category (single source of truth per document)
- `purchasePriceCents`: Actual price paid for an item (single transaction, single value)
- `estimatedPriceCents`: User's estimate for an item (planning value, not aggregated)
- `salePriceCents`: Actual sale price for an item (single transaction, single value)

Each of these is:
- **Direct user input** on a specific document (not computed from other sources)
- **Single-owner data**: Only one user edits planning values for a project/item at a time
- **Not aggregated**: These are not sums or totals that could accumulate incorrectly

**Derived Totals (different story)**:
- Actual spend totals are **computed at read time** from transaction documents (internal `buildBudgetProgress()` in `src/data/budgetProgressService.ts`)
- Never stored as competing fields that could drift
- Always reflect current transaction state (source of truth is the transactions collection)

### Fallback: Security Rule Checks

If concurrent edits become a concern (e.g., collaborative budget editing), Firestore security rules can enforce `updatedAt` timestamp checks:

```javascript
// Security rule: Reject writes if document was modified since last read
allow update: if request.resource.data.updatedAt == resource.data.updatedAt;
```

This is a **one-line rule** that provides lightweight staleness detection without complex application logic or Cloud Functions.

### Why `getChangedFields()` Is Still Important

Even without conflict detection, partial writes via `getChangedFields()` are critical:
- **Reduces Firestore write costs** (only send modified fields)
- **Improves offline performance** (smaller payloads)
- **Prevents unintentional overwrites** (e.g., subscription updates during editing)
- **Provides user feedback** (e.g., skip save when `hasChanges` is false)

The `useEditForm` hook (`src/hooks/useEditForm.ts`) provides this functionality across all edit screens.

---

## Schema Evolution Strategy

This documents how the app handles schema changes over time as new fields are added or data structures change.

### MVP Pattern: Optional Fields + Merge Writes

**Pattern**: All new fields are optional, and writes use `{ merge: true }` to avoid overwriting existing data.

**Example — Adding a new field**:

```typescript
// New field: `estimatedCompletionDate` added to Project type
interface Project {
  id: string;
  name: string;
  // ... existing fields
  estimatedCompletionDate?: Timestamp; // New optional field
}

// Write with merge: true
setDoc(projectRef, {
  estimatedCompletionDate: newDate,
  updatedAt: serverTimestamp(),
}, { merge: true });

// Read with undefined handling
const project = projectSnap.data() as Project;
const completionDate = project.estimatedCompletionDate ?? null;
```

**Key Principles**:
1. **Always optional**: New fields use `?` in TypeScript types
2. **Merge writes**: Use `{ merge: true }` or partial `setDoc` to preserve existing fields
3. **Undefined handling**: Read code handles `undefined` gracefully (use `??` operator for defaults)
4. **No schema version**: No `schemaVersion` field or formal migration framework for MVP

**Benefits**:
- Simple: No migration code to maintain
- Offline-friendly: No need to run migrations before offline writes
- Backward compatible: Old clients can read new documents (ignore unknown fields)

**Limitations**:
- Cannot rename fields (old field remains forever, or requires manual cleanup)
- Cannot change field types (e.g., string → number) without read-time conversion
- Cannot remove required fields (would break old clients)

### Breaking Changes (When MVP Pattern Isn't Enough)

If a breaking change is needed (e.g., rename field, change type, remove required field):

**Option 1: Read-Time Normalization** (preferred for one-off conversions)

```typescript
// Normalize old schema to new schema at read time
const normalizeProject = (raw: any): Project => {
  return {
    id: raw.id,
    name: raw.name || raw.projectName, // Handle old field name
    estimatedBudgetCents: typeof raw.estimatedBudget === 'string'
      ? parseFloat(raw.estimatedBudget) * 100  // Convert old string format to cents
      : raw.estimatedBudgetCents ?? 0,
    // ... other fields
  };
};
```

**Option 2: Schema Version + Migration** (for complex multi-step migrations)

```typescript
interface Project {
  schemaVersion: number; // 1, 2, 3...
  // ... fields
}

const migrateProject = (raw: any): Project => {
  const version = raw.schemaVersion ?? 1;
  if (version === 1) {
    // Migrate v1 → v2
    return { ...raw, schemaVersion: 2, newField: defaultValue };
  }
  return raw;
};
```

### Current Schema State

As of MVP, no documents have `schemaVersion` fields. All types are at implicit "version 1." If breaking changes are introduced in the future, add `schemaVersion` to affected types and implement migrations at read time.

---

## Known Limitations (Accepted for MVP)

These are architectural tradeoffs made consciously for the MVP. Future iterations may address them if they become pain points.

### Silent Security Rule Failures

**Behavior**: Firestore applies writes optimistically to the local cache even if the server later rejects them due to security rule violations. Users may see "phantom" values that never sync to the server.

**Example**:
- User edits a document they don't have permission to modify
- Edit appears immediately in the app (offline-first, optimistic write)
- Server rejects the write due to security rules
- User sees the edited value locally, but other users never see it
- No immediate error message to the user (only shows up in sync banner later)

**Why This Happens**:
- Firestore SDK applies writes to local cache before server validation (by design for offline support)
- Security rules only run on the server (not in client SDK)
- No synchronous feedback on security rule failures

**Mitigation Strategies (Implemented)**:
1. **Pending write tracking**: All writes call `trackPendingWrite()` (`src/sync/pendingWrites.ts`) for sync status visibility
2. **Sync status banner**: `SyncStatusBanner` component shows failed operations with error messages
3. **Defensive permissions**: Security rules designed to be permissive for authenticated account members (reduces failure scenarios)

**Mitigation Strategies (Not Implemented for MVP)**:
1. **Pre-write permission checks**: Client-side validation that mirrors security rules (complex, error-prone, duplicates logic)
2. **Rollback on failure**: Revert local cache when server rejects write (requires custom logic, breaks offline-first guarantees)
3. **Blocking writes**: Await server acknowledgment before showing success (defeats offline-first, poor UX)

**Accepted Tradeoff**: For MVP, we accept that users may occasionally see phantom values. The sync banner provides visibility when failures occur, and defensive security rules minimize the risk.

**Future Improvement**: If this becomes a frequent issue, consider pre-write permission validation (mirror rules in client) or more aggressive sync banner notifications (foreground alerts for failures).

---

## Do NOT Build (Anti-Patterns)

These are patterns we explicitly reject for this architecture. If you're considering building one of these, review the rationale first.

### Existing Rejections

- **Custom sync engine or outbox** — Firestore's native SDK handles offline persistence and sync
- **Cursor-based pulls** — `onSnapshot` provides real-time updates
- **Client-side conflict resolution** — last-write-wins for single docs; server-side transactions for multi-doc
- **Request-doc workflows for single-doc edits** — even for money fields. Last-write-wins is correct (see [High-Risk Fields](#high-risk-fields-why-conflict-detection-is-not-required))
- **Fine-grained per-field permissions** — simple role-based access is sufficient for MVP

### Full-Form Overwrites on Edit Screens

**Anti-Pattern**: Sending all form fields to Firestore on save, even if only one field changed.

```typescript
// BAD: Overwrites all fields, even unchanged ones
const handleSave = () => {
  updateDoc(itemRef, {
    name: name,
    description: description,
    spaceId: spaceId,
    status: status,
    estimatedPriceCents: estimatedPriceCents,
    purchasePriceCents: purchasePriceCents,
    salePriceCents: salePriceCents,
    quantity: quantity,
    tags: tags,
  });
};
```

**Why It's Bad**:
- **Cost**: Firestore charges per field written (9 field writes vs 1 field write)
- **Offline performance**: Larger payloads slow down sync queue
- **Conflict risk**: Overwrites fields that may have changed via subscription
- **No-change detection**: Can't skip write if user saved without edits

**Correct Pattern**: Use `getChangedFields()` to send only modified fields:

```typescript
// GOOD: Only sends changed fields
const handleSave = () => {
  if (!form.hasChanges) {
    router.back();
    return;
  }
  const changedFields = form.getChangedFields();
  updateItem(accountId, itemId, changedFields).catch(console.error);
  router.back();
};
```

**Implemented in**: `useEditForm` hook (`src/hooks/useEditForm.ts`), used by all edit screens.

### Full Compare-Before-Commit UX

**Anti-Pattern**: Blocking saves while fetching latest server data for comparison, showing diff UI, requiring user confirmation.

```typescript
// BAD: Blocks save, fetches server data, shows diff modal
const handleSave = async () => {
  setIsLoading(true);
  const latestItem = await fetchLatestFromServer(itemId); // Blocks on network
  const conflicts = compareFields(form.values, latestItem);
  if (conflicts.length > 0) {
    setShowConflictModal(true); // User must resolve conflicts
  } else {
    await updateDoc(itemRef, form.values);
  }
  setIsLoading(false);
};
```

**Why It's Bad for MVP**:
- **Offline-hostile**: Requires network call before save (breaks offline-first)
- **Slow UX**: Users wait for server round-trip on every save
- **Complex UI**: Requires conflict resolution modal, diff viewer
- **Overkill**: Only needed for high-conflict scenarios (collaborative real-time editing)

**What We Build Instead**: Lightweight staleness check via `useEditForm`.

### Staleness Check Comparison

| Feature | Lightweight Check (Implemented) | Full Compare-Before-Commit (Not Built) |
|---------|--------------------------------|----------------------------------------|
| Network call on save | No | Yes (fetch latest) |
| Detects user edits | Yes | Yes |
| Detects concurrent edits | No | Yes |
| Shows diff UI | No | Yes |
| Blocks save on conflict | No | Yes |
| Offline-friendly | Yes | No |
| User friction | Low | High |
| Appropriate for | Single-user editing, low conflict | Real-time collaboration, high conflict |

**Lightweight staleness check (what we built)**:
- Tracks which fields user edited, prevents subscription overwrites during editing
- `useEditForm` hook compares form state to initial snapshot (no network call)
- Zero network overhead, zero latency
- Does NOT detect concurrent edits from other users

**Full compare-before-commit UX (what we don't build)**:
- Fetches latest server data before save (network call)
- Shows diff UI for conflicts (modal, side-by-side view)
- Requires user to resolve conflicts (choose version, merge manually)
- Appropriate for high-conflict scenarios (e.g., Google Docs-style collaboration)

**When to Reconsider**: If usage patterns show frequent concurrent edits with data loss, revisit this decision. For MVP with small teams (2–5 users), the lightweight approach is sufficient.
