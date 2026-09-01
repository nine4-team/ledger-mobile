# Current Firebase Backend Contract

Status: M0 static-source characterization; production-shape confirmation pending
Last reviewed: 2026-08-31
Evidence: `EVID-SOURCE-BACKEND-001`

## Purpose and Boundary

This document records what the current Ledger Firebase boundary actually does
before any Supabase/PowerSync target mapping is approved. It is descriptive,
not a recommendation to recreate Firebase behavior literally. Product specs and
the decision log remain authoritative where the redesigned product deliberately
changes behavior.

The characterization is based on production rules, Storage rules, Functions
source, iOS services, MCP server source, indexes, tests, and migration/audit
tools. It has not yet been reconciled against a canonical read-only production
export. Counts, undocumented fields, extinct collections, malformed records,
and historical path variants therefore remain unproven.

## Executive Findings

- Account membership documents are the current authorization authority. No
  active custom-claim authorization was found.
- Most account-scoped Firestore data grants every account member full CRUD;
  category-scoped financial access is largely an application presentation
  policy, not backend enforcement.
- Firebase Storage permits unauthenticated reads and writes to every object.
- The iOS app writes most domain data directly to Firestore. Cloud Functions
  then repair, derive, or denormalize accounting and lineage state.
- The MCP server uses the Admin SDK and therefore bypasses Firestore and Storage
  rules. Its own account resolution and command checks are security boundaries.
- Several rule and Function paths are starter/template or apparently unused
  surfaces. They are still tracked so migration does not confuse scaffolding
  with shipped behavior.
- Production and test Firestore rules are materially different. Emulator rule
  success is not proof of production authorization parity.

## Identity, Accounts, and Authorization

### Authentication

The app supports Firebase email/password signup and signin plus Google signin.
`AuthManager` observes Firebase auth state and stores the current Firebase user
in memory. Signout calls only `FirebaseAuth.signOut()`; it does not clear the
pending media directory or define a local-database disposition.

The app sends Firebase ID tokens as bearer tokens to public HTTP Functions for
account creation and invite acceptance. Those Functions verify the token with
Firebase Admin Auth. No current use of Firebase custom claims was found;
`role`, `companyFinancialAccess`, and `allowedFeeCategoryIds` live in membership
documents.

### Account discovery

Memberships live at `accounts/{accountId}/users/{uid}`. The iOS app performs a
cache-first `collectionGroup("users") where uid == current uid` query and can
return multiple accounts. MCP has both first-account and all-account resolvers;
the OAuth flow currently uses the first membership returned and may fall back
to `LEDGER_ACCOUNT_ID` when resolution fails.

### Membership and invites

- Account documents are readable by members but cannot be created, updated, or
  deleted by clients under production rules.
- Membership creation/deletion is server-only. Owners/admins may update only
  `role`, `companyFinancialAccess`, `allowedFeeCategoryIds`, and `updatedAt`.
- Any account member may currently create, update, or delete invite documents;
  the rule does not require admin status.
- Invite preview is public to possession of the token. Acceptance requires a
  verified Firebase user whose email matches and whose Firebase account was
  created within the preceding 15 minutes. Acceptance atomically creates or
  updates membership and marks the invite accepted.
- Invite tokens are queried with a collection-group index. A legacy fallback
  treats the token as a document ID and scans at most 100 accounts.
- The app recognizes both `ledger-nine4://invite?token=...` and
  `https://ledger-nine4.web.app/invite?token=...`.

### MCP OAuth

MCP verifies a Firebase ID token, resolves an account, stores one-time PKCE
authorization codes in root collection `_mcp_auth_codes`, and issues its own
HMAC JWT access/refresh tokens. Client registrations are process-memory only.
Issued JWT payloads currently omit `exp`; although the response says
`expires_in: 31536000`, signature verification treats tokens without `exp` as
non-expiring. This must not be copied into the target design.

## Firestore Path Catalog

| Current path | Current behavior and authority | M0 disposition |
|---|---|---|
| `health/ping` | Any authenticated user may read; connectivity/health probe | replace |
| `users/{uid}` | Starter global profile; self path or existing document `uid` may authorize read/write; no app call site found | retire |
| `accounts/{accountId}` | Member-readable account root; client create/update/delete denied; server account bootstrap writes | replace |
| `accounts/{accountId}/users/{uid}` | Membership, role, financial-access settings; server creates, admin updates limited fields | replace |
| `**/users/{uid}` | Collection-group account discovery restricted by document `uid == auth.uid` | replace |
| `.../users/{uid}/projectPreferences/{projectId}` | Per-user pinned project categories; all account members currently have CRUD, not only the owning user | replace |
| `.../presets/{presetId}` | Account preset root/default category pointer; member CRUD | replace |
| `.../presets/{presetId}/budgetCategories/{id}` | Account category definitions and accounting metadata; member CRUD | redesign |
| `.../presets/{presetId}/vendors/{id}` | Vendor defaults; member CRUD | replace |
| `.../presets/{presetId}/spaceTemplates/{id}` | Space templates; member CRUD | replace |
| `.../profile/{profileId}` | Business profile; member CRUD | replace |
| `.../invites/{inviteId}` | Invite/token/status records; member CRUD plus privileged Function acceptance | replace |
| `users/{uid}/quota/{objectKey}` | Starter server-written quota counter; no app caller found | retire |
| `users/{uid}/objects/{objectId}` | Starter quota-owned object path; no app caller found | retire |
| `.../requests/{requestId}` | Account request-doc scaffold; constrained pending creates, no handler/writer found | retire |
| `.../projects/{projectId}/requests/{requestId}` | Project request-doc scaffold; constrained pending creates, no handler/writer found | retire |
| `.../inventory/requests/{requestId}` | Inventory request-doc scaffold; constrained pending creates, no handler/writer found | retire |
| `.../items/{itemId}` | Core Item records; member read/delete; create/update enforce nonnegative prices and project price not below nonzero cost | redesign |
| `.../protoItems/{protoItemId}` | Legacy quick-draft records; member CRUD; target stops creating them but migration compatibility is required | migrate |
| `.../projects/{projectId}` | Project records and denormalized `budgetSummary`; member CRUD | redesign |
| `.../projects/{projectId}/budgetCategories/{id}` | Per-project budget allocation; member CRUD | redesign |
| `.../projects/{projectId}/feeInstallments/{id}` | Fee installment schedule/state; member CRUD | redesign |
| `.../projects/{projectId}/notes/{id}` | Project notes; member CRUD | replace |
| `.../spaces/{spaceId}` | Account/project Spaces; member CRUD; archive trigger clears Item links | replace |
| `.../spaces/{spaceId}/reviewNotes/{id}` | Space review notes; member CRUD | replace |
| `.../transactions/{transactionId}` | Current accounting records; member create/read, constrained update, delete only with empty `itemIds`; trigger-derived audit/budget data | redesign |
| `.../invoices/{invoiceId}` | Current invoice records including embedded/flat membership variants; member CRUD | redesign |
| `.../invoiceEvents/{eventId}` | Immutable-after-create payment-correction trail, but any member may create an event | redesign |
| `.../lineageEdges/{edgeId}` | Append-only-after-create movement/association evidence; any member may create despite “server-produced” comments | redesign |

Paths abbreviated with `...` are below `accounts/{accountId}`.

## Server-Only and Dynamically Addressed Data

These paths are not fully represented by production client rules:

| Path | Producer/consumer | Required treatment |
|---|---|---|
| `accounts/{id}/transactionRepricingEvents/{hash}` | Item-price Function idempotency marker; MCP deletion preflight reads it | profile; retain as source evidence or transform into target operation idempotency evidence |
| `accounts/{id}/transactionDeletionTombstones/{txId}` | MCP destructive transaction deletion stores complete pre-delete evidence | profile and migrate audit evidence |
| `_mcp_auth_codes/{code}` | MCP OAuth one-time code, deleted on consumption/expiry | do not migrate as durable business data; replace OAuth mechanism |
| `users/{uid}/quota/*`, `users/{uid}/objects/*` | Starter quota Function using a caller-supplied collection path | confirm absent/unused, then retire |
| Arbitrary `collectionPath` accepted by `createWithQuota` | Admin-SDK dynamic write after only `{uid}` substitution | security hazard; retire Function rather than reproduce |

Read-only audit/repair scripts also use collection-group queries for projects,
items, transactions, invoices, lineage, and budget categories. Those scripts
are migration evidence, not proof that all collection groups are application
APIs.

## Cloud Function Contract

| Function | Trigger/API | Current effect | Disposition |
|---|---|---|---|
| `enforceItemProjectPriceFloor` | Item write | Repairs `projectPriceCents` to at least purchase cost | redesign as target constraint/command invariant |
| `createWithQuota` | Callable | Starter quota transaction with unrestricted caller-supplied collection path | retire |
| `onItemTransactionIdChanged` | Item update | Appends idempotent association edge and optional Return-intent edge | redesign into authoritative commands/provenance |
| `onLineageEdgeCreated` | Edge create | Recomputes source transaction completeness/audit | redesign into synchronous target projection/invariant |
| `onItemPriceChanged` | Item update | Reprices eligible unpaid project Inventory Purchase, records idempotency marker, recomputes completeness for linked/lineage transactions, preserves paid invoices | redesign |
| `onSpaceArchived` | Space update | Clears `spaceId` from scoped Items in batches; logs but suppresses failure | redesign into atomic/repairable command semantics |
| `onAccountMembershipCreated` | Membership create | Idempotently seeds four default budget categories and default pointer | replace with target account-bootstrap transaction |
| `createAccount` | Callable | Creates account/owner membership and seeds presets; no app caller found | retire duplicate API |
| `createAccountHttp` | Public HTTP + bearer | Current app account bootstrap API | replace |
| `createProject` | Callable | Creates Project and preference after seeding presets; no app caller found | retire; current app writes Projects directly and target flow changes |
| `previewInviteHttp` | Public HTTP | Token-based invite preview | replace with rate-limited target endpoint |
| `acceptInvite` | Callable | Duplicate invite acceptance; no app caller found | retire duplicate API |
| `acceptInviteHttp` | Public HTTP + bearer | Current app invite acceptance API | replace |
| `onTransactionWritten` | Transaction write | Recalculates affected project summaries and transaction completeness/audit | redesign as transactional command/projection |
| `onProjectBudgetCategoryWritten` | Project category write | Recalculates project budget summary | redesign |
| `onAccountBudgetCategoryWritten` | Account category write | Recomputes affected transaction completeness and all project summaries | redesign |
| `backfillBudgetSummaries` | Callable | Auth-only, account-ID-selected project backfill; does not verify membership | retain only as source evidence; replace with restricted migration/reconciliation tooling |
| `backfillIsComplete` | Callable | Auth-only, account-ID-selected transaction audit backfill; does not verify membership | retain only as source evidence; replace with restricted migration/reconciliation tooling |

`createProject`, `backfillBudgetSummaries`, and `backfillIsComplete` authenticate
the caller but do not verify membership in the supplied `accountId`. Because
Admin SDK writes bypass rules, these are current privilege-boundary defects,
even if their exposed call paths are unused or operator-only.

## Derived Accounting and Lineage Behavior

Current Functions maintain data after direct client writes:

- Project `budgetSummary` reads account categories, project allocations, and
  project Transactions. Returns/Sales subtract spend; excluded categories do
  not contribute to overall totals.
- `isComplete` applies only to canonical movement records and itemized
  Purchase/Return transactions. It reconciles receipt subtotal against active
  and historical lineage Item prices within one percent.
- Inventory-sourced project Purchases/Returns use project price; vendor and
  project-to-inventory acquisition records use purchase cost.
- Paid Invoice membership freezes Item repricing, including legacy `lines` and
  current flat `itemIds` representations.
- Price-trigger idempotency relies on `transactionRepricingEvents` records.
- Several trigger failures are logged and suppressed, so eventual derived state
  can be stale without making the initiating write fail.

The target must not re-create this as a web of asynchronous repair triggers.
The behavior must be assigned deliberately to atomic commands, constraints,
append-only evidence, or explicitly rebuildable projections.

## Storage and Media Contract

### Authorization and namespaces

Production `storage.rules` is `allow read, write: if true` for all paths. Object
names conventionally use
`accounts/{accountId}/{entityType}/{entityId}/{filename}`, but the rules do not
enforce account, entity, content type, size, or authentication.

Known entity namespaces include Items, Projects, Spaces, Transactions, and
proto/quick-draft Items. Item deletion logic distinguishes objects owned by the
Item namespace from shared/external objects; non-owned objects are detached but
preserved.

### Object and reference behavior

- iOS uploads original bytes, sets content type, then obtains permanent
  token-bearing HTTPS download URLs.
- Existing records may also contain `gs://` URLs. iOS resolves those through
  Firebase Storage and caches the HTTPS URL in memory.
- MCP hardcodes bucket `ledger-nine4.firebasestorage.app` and recognizes only
  Firebase HTTPS download URLs when parsing object paths.
- Image attachments can embed original URL, small/medium thumbnail URLs,
  filename, content type, kind, and primary ordering.
- Thumbnails are JPEG, at most 300px and 800px. Failure to generate/upload a
  thumbnail does not fail the original upload.
- Promoting quick-draft photos copies and verifies objects into the final Item
  namespace while preserving draft originals, so duplicates can exist.

### Offline upload queue

Pending bytes and JSON metadata are stored in application support under
`PendingUploads`. Entries survive restart, retry up to ten processing attempts,
and write the resulting URLs back to a dynamically selected entity collection
and field/attachment array. The queue:

- checks that the destination Firestore document still exists;
- removes an orphaned local entry when the destination is gone;
- best-effort deletes newly uploaded original/thumbnails if the destination is
  deleted during processing;
- exposes manual retry and user-approved discard after max attempts; and
- is global to the app container, with no observed signout/account-removal
  cleanup, encryption policy, or per-user directory separation.

Target media design must preserve durable offline capture while resolving the
logout/account-switch security and data-loss policy before local deletion.

## Query and Index Contract — Static Review Complete

Configured Firestore indexes explicitly include:

- `lineageEdges(itemId ASC, createdAt ASC)`;
- collection-group `users.uid`;
- collection-group `invites.token`; and
- legacy collection-group `members.uid`.

The deterministic line/symbol catalog and reviewed semantic contract now live
in `query-contract.generated.json`, `query-contract.generated.md`, and
`current-query-contract.md`. They cover iOS listeners and offline expectations,
MCP/Function online queries, dynamic filter combinations, ordering, pagination,
migration/audit reads, and declared index consumers.

Static query characterization is complete, so `MAN-INDEX-001` is
characterized. Runtime query frequency, missing-index failures, and console-only
deployed indexes remain production-evidence gaps. They must not be inferred
from absence in `firebase/firestore.indexes.json`.

## Production/Test Rule Drift

`firebase/firestore.test.rules` is not equivalent to production rules. Among
the observed differences:

- test rules do not enforce the Item project-price floor;
- test transaction deletion does not require empty `itemIds`;
- test lineage permits full CRUD while production permits read/create only;
- several production paths are absent, including fee installments, project
  notes, and invoice events; and
- the test rules file is a manually duplicated policy rather than the file used
  by the rules test runner, while `firebase/test/rules.test.mjs` does load the
  production rules file.

Each future security claim must identify the exact deployed rules/policies it
tested.

## Required Production-Read Confirmation

Before M0/M1 can close, a read-only export/profile must confirm:

1. every root and account subcollection, including unknown/dynamic paths;
2. document counts and field/type/enum variants per account;
3. Auth providers, disabled/deleted users, and membership orphans;
4. Storage object counts, bytes, metadata, namespaces, duplicates, and dangling
   Firestore references;
5. the existence/counts of template request/quota/object collections;
6. server-only marker, tombstone, and OAuth-code collections;
7. query/index usage and missing-index failures; and
8. derived-state drift in budget summaries, completeness audits, lineage, and
   media references.

This production confirmation must be read-only and produce a versioned,
hashed artifact. It is not permission to migrate or mutate production.
