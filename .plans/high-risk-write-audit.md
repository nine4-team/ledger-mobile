# Audit: High-Risk Client Writes vs Architecture Requirements

## Problem Statement

Our architecture defines a clear conflict stance for multi-user scenarios:

> **Low-risk fields** (text, notes, descriptions): last-write-wins with auditability is acceptable.
> **High-risk fields** (money, tax, category allocation): do NOT silently overwrite if the remote changed since the user's base version.

For high-risk edits, the architecture requires one of:
- **Request-doc workflow** (server validates base conditions and either applies or fails)
- **Explicit "compare before commit" UX** (re-read, show diff, ask user to confirm)

We have a working request-doc framework (`src/data/requestDocs.ts` + Cloud Functions in `firebase/functions/src/index.ts`), but it's currently only wired up for inventory sale operations (`ITEM_SALE_*`). Many other write paths may touch high-risk fields via direct client `setDoc`/`updateDoc` calls with no conflict detection.

This audit should find every place where the app violates these architectural requirements so we can prioritize remediation.

---

## Architecture References (read these first)

1. **Conflict stance + correctness rules**: `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md` — sections "Conflict stance" and "Correctness rules for writes"
2. **Target architecture**: `.cursor/plans/firebase-mobile-migration/10_architecture/target_system_architecture.md` — sections "Module boundaries" and "Key design choices"
3. **Security model**: `.cursor/plans/firebase-mobile-migration/10_architecture/security_model.md` — sections "What must be callable Functions", "Request-doc workflows", and "Threat model notes"
4. **Offline-first v2 spec**: `.cursor/plans/firebase-mobile-migration/00_working_docs/OFFLINE_FIRST_V2_SPEC.md` — section "Request-doc operations"

### Key Rules from These Docs

From `offline_first_principles.md`:
- Direct client writes are allowed for **single-doc** changes
- Multi-doc client updates are "the easiest way to create inconsistent state offline" — use request-docs instead
- For high-risk fields: request-doc workflow or compare-before-commit UX

From `security_model.md`:
- "Client tampering with money/critical fields" must be mitigated via callable Functions or stricter rule validation
- Request docs are the **default mechanism** for multi-doc correctness
- Cloud Functions are the only writers of `status = applied|failed`

From `OFFLINE_FIRST_V2_SPEC.md`:
- "Request-doc workflows are not 'optional correctness.'"
- Direct client writes allowed only for **single-doc changes** or **provably safe** multi-doc changes (rare; must be justified)

---

## What Exists Today

### Request-doc infrastructure (working)
- **Client**: `src/data/requestDocs.ts` — `createRequestDoc()`, `subscribeToRequest()`, types
- **Server**: `firebase/functions/src/index.ts` — `processRequestDoc()`, `setRequestApplied()`, `setRequestFailed()`
- **Triggers**: `onAccountRequestCreated`, `onProjectRequestCreated`, `onInventoryRequestCreated`

### Request-doc handlers (implemented)
- `ITEM_SALE_PROJECT_TO_BUSINESS` — inventory sale with lineage edges, canonical transaction management
- `ITEM_SALE_BUSINESS_TO_PROJECT` — inventory purchase with lineage edges
- `ITEM_SALE_PROJECT_TO_PROJECT` — cross-project transfer with lineage edges
- `PING` — health check

### Callable Functions (server-owned operations)
- `createAccount` — creates account + owner membership atomically
- `createProject` — creates project + seeds preferences atomically
- `acceptInvite` — validates token + creates membership + marks invite used

### Server triggers (cleanup/audit)
- `onSpaceArchived` — clears spaceId from items when a space is soft-deleted
- `onItemTransactionIdChanged` — appends association lineage edge on item.transactionId change

---

## Audit Scope

### Step 1: Catalog all write functions in `src/data/`

For every file in `src/data/`, find all exported functions that call `setDoc`, `updateDoc`, `addDoc`, or `deleteDoc`. For each, document:

- **Function name** and file path
- **Collection/doc path** it writes to
- **Fields written** (from the payload)
- **Single-doc or multi-doc** (does the function write to more than one document?)
- **Caller(s)** — which screen(s) or handler(s) call this function

Files to check (all of `src/data/`):
- `accountsService.ts`
- `accountMembersService.ts`
- `accountPresetsService.ts`
- `budgetCategoriesService.ts`
- `budgetProgressService.ts`
- `businessProfileService.ts`
- `inventoryOperations.ts`
- `invitesService.ts`
- `itemsService.ts`
- `projectBudgetCategoriesService.ts`
- `projectService.ts`
- `projectPreferencesService.ts`
- `reportDataService.ts`
- `repository.ts`
- `resolveItemMove.ts`
- `spaceTemplatesService.ts`
- `spacesService.ts`
- `transactionsService.ts`
- `vendorDefaultsService.ts`
- `requestDocs.ts`

Also check `app/` screens for any direct Firestore write calls that bypass the data layer (architecture violation: "Forbidden: direct Firebase SDK usage scattered across screens").

### Step 2: Classify each write by risk level

**High-risk fields** (per architecture):
- Money: `amountCents`, `budgetCents`, `purchasePriceCents`, `projectPriceCents`, `marketValueCents`, `costCents`, any `*Cents` field
- Category allocation: `budgetCategoryId`, budget category assignments
- Inventory state: `projectId` on items (which project owns it), `transactionId` on items (which transaction it belongs to), `status` on items
- Lineage: any field that affects item provenance or audit trail

**Low-risk fields** (last-write-wins acceptable):
- Text: `name`, `description`, `notes`, `source`, `sku`, `clientName`
- Display: `order`, `slug`, `isArchived`, `mainImageUrl`
- Metadata: `updatedAt`, `updatedBy`, `createdAt`, `createdBy`
- Preferences: pinned categories, sort order, view settings

### Step 3: Identify violations

For each high-risk write, determine:

1. **Is it single-doc?** If yes, does it have any conflict detection (version check, compare-before-commit, or request-doc)?
2. **Is it multi-doc?** If yes, does it use a request-doc workflow or Cloud Function? If not, it's a violation.
3. **Can a concurrent edit silently overwrite another user's changes to money/category fields?** If yes, it's a violation.

### Step 4: Check for direct Firestore calls in `app/`

Search `app/` for any imports from `@react-native-firebase/firestore` (direct SDK usage). The architecture says all Firebase usage should be in the data layer, not scattered across screens.

### Step 5: Identify multi-doc client writes

Search for patterns where a single user action writes to multiple documents from client code. Examples:
- A save handler that calls multiple `updateItem()` / `updateTransaction()` in a loop
- A handler that updates a parent doc AND child docs
- Any `Promise.all([write1, write2, ...])` or sequential writes in the same handler

---

## Deliverable

A table with this format:

| Service Function | File | Collection | High-Risk Fields | Single/Multi-Doc | Has Conflict Detection | Violation? | Notes |
|---|---|---|---|---|---|---|---|
| `setProjectBudgetCategory` | projectBudgetCategoriesService.ts | projects/{id}/budgetCategories/{id} | `budgetCents` | Single | No | YES — money field, no conflict detection | Currently sends all values on save |
| `updateItem` | itemsService.ts | items/{id} | `purchasePriceCents`, `projectPriceCents`, `budgetCategoryId` | Single | No | YES — money + category fields | |
| `updateTransaction` | transactionsService.ts | transactions/{id} | `amountCents`, `budgetCategoryId` | Single | No | YES — money + category fields | |
| ... | | | | | | | |

Plus a separate list of:
1. **Multi-doc client writes** that should be request-doc workflows
2. **Direct Firestore calls in `app/`** that bypass the data layer
3. **Recommended prioritization** — which violations are highest risk for data corruption in a multi-user scenario

---

## Context: What "Good" Looks Like

The inventory sale operations are the gold standard in this codebase:

**Client side** (`src/data/inventoryOperations.ts` or wherever sale is triggered):
```ts
createRequestDoc('ITEM_SALE_PROJECT_TO_BUSINESS', payload, scope, opId);
```

**Server side** (`firebase/functions/src/index.ts`):
- Validates preconditions in a transaction (`item.projectId` hasn't changed, `item.transactionId` matches expected)
- Applies all changes atomically (item update + canonical transaction + lineage edges)
- Sets request status to `applied` or `failed`

This is the pattern that all high-risk writes should follow. The question is: which writes currently skip this and go straight to `setDoc`/`updateDoc`?
