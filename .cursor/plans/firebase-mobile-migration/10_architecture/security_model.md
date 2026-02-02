# Security Model (Auth, Membership, Rules, Functions)

This doc defines the security model for the Firebase migration: **who can access what**, and **how we enforce it** via Firebase Auth, Firestore Rules, Storage Rules, and callable Cloud Functions.

This model is designed to support the architecture in:

- [`target_system_architecture.md`](./target_system_architecture.md)
- [`OFFLINE_FIRST_V2_SPEC.md`](../../../../OFFLINE_FIRST_V2_SPEC.md)

---

## Goals

- **Account isolation**: a user never reads/writes data outside accounts they belong to.
- **Principle of least privilege**: only owners/admins can perform dangerous operations. (have we defined dangerous?)
- **Offline-ready compatible**: rules support Firestore-native offline (cached reads, queued writes).
- **Rules are simple; correctness is server-owned**: complex multi-doc invariants go through callable Functions (request-doc workflows).

---

## Core concepts

### Actor

- `uid`: Firebase Auth user id
- `email`: verified email (where applicable)

### Account

- A top-level tenant boundary for all data.
- All entity docs include `accountId` and rules verify membership in that account.

### Membership + roles

Account membership is expressed on the account user document keyed by `uid`:

`accounts/{accountId}/users/{uid}`

Fields (suggested):

- `role`: `"admin" | "user"` (account-level role)
- `joinedAt`, `joinedBy`
- Optional (only if you need offboarding without deleting the doc):
  - `disabledAt?: Timestamp | null`
  - `disabledBy?: string | null`

System owners are **global**, matching the current app:

- Store them as either a Firebase Auth custom claim (e.g. `request.auth.token.role == "owner"`)
  or a rules-checkable allowlist doc like `systemOwners/{uid}`.
- In rules: allow access if the requester is a system owner **OR** has an active account user doc.

Role semantics:

- **admin**: manage presets/business profile; can invite/remove users
- **user**: project work (items/transactions/spaces/media) within the account
- **owner (system)**: can access all accounts; can manage users/roles across accounts

### Authorization model (now + future)

This migration starts with **coarse roles** (`owner` system-wide, plus `admin/user` per account) but must stay compatible with a future where an admin can restrict what a user can **see** and **do** (e.g., “only kitchen budget-category work”).

This doc stays focused on **enforcement** (Rules/Functions + data shape). Product-level definitions (“what exact capabilities exist”) should live in feature specs and the master feature list.

#### Now (MVP): role-gated capabilities

- **Account membership** gates all reads/writes.
- **Role** gates “dangerous” operations and configuration surfaces:
  - membership management / invites
  - business profile + presets (budget categories, vendors, taxes, templates)
  - destructive operations (delete project, mass delete, etc.)

#### Future: scoped visibility + fine-grained permissions (budget-category + ownership)

Planned direction: an admin can assign an account user a **visibility scope** such that they only see:

- transactions/items/spaces/projects related to a permitted **budget category** (or set of categories), and/or
- records they **created** (ownership fallback), depending on policy.

Key constraint: Firestore Rules cannot “query”; they can only validate against:

- the current document
- `request.auth`
- and `get()`/`exists()` of specific docs by path

So, for scoped visibility to be enforceable (and not just a UI filter), we need explicit, rules-checkable shapes:

##### A) Store scopes in path-addressable ACL docs (recommended for rules)

Example:

- `accounts/{accountId}/permissions/{uid}`: coarse switches (enabled features, allowed operations)
- `accounts/{accountId}/permissions/{uid}/budgetCategories/{budgetCategoryId}`: per-category allow docs

Then rules can do:

- allow read/write of a transaction with `budgetCategoryId` only if:
  - member is active, and
  - `exists(accounts/{accountId}/permissions/{uid}/budgetCategories/{budgetCategoryId})`

This scales better than large arrays (rules are simpler; avoids hitting array-size limits).

##### B) Denormalize “security-critical selectors” onto docs

If an entity’s visibility depends on budget category, that entity should carry a **direct selector** that rules can check without complex joins:

- Non-canonical transactions should carry `budgetCategoryId` (good).
- Items need a category selector for rules-checkable scoped visibility and for canonical inventory budgeting; use:
  - **(preferred)** `item.inheritedBudgetCategoryId` (server-owned/derived) when items are linked to a **non-canonical** transaction or otherwise categorized.
  - avoid rule-time joins like `get(transaction).data.budgetCategoryId` as the primary visibility mechanism (more complex/brittle and does not work for canonical-item attribution rules).

Naming note:

- The current web app uses `Transaction.categoryId`. For the Firebase/RN model we prefer `budgetCategoryId` for clarity.
- If you maintain an interop layer, map `categoryId` → `budgetCategoryId` at the boundary (import/adapters), not inside rules logic.

##### C) Ownership fallback requires `createdBy`

If “see your own created records” is part of the policy, entities must include `createdBy` (uid) and rules must enforce it on create:

- `request.resource.data.createdBy == request.auth.uid`

##### D) Make scoping explicit in rules and in callable Functions

When scoped visibility is enabled for an account/member:

- **Rules** should enforce category allowlists on reads and writes for category-bound entities
- **Callable Functions** should validate permissions server-side for multi-doc operations (allocation/sale/rollups) and should be the only writer of any denormalized security fields (like `item.inheritedBudgetCategoryId`)

##### E) Keep a safe “default” for accounts without scoping

To remain backward-compatible (and keep MVP simple), scope enforcement should be designed as:

- “no scope docs present” => account-wide access (current behavior)
- “scope docs present” => scoped access enforced

### Project access

Default assumption (simple, scalable enough for now):

- Project access is **account-wide** (any active account user can access account projects).
- If you later need per-project ACLs, add:
  - `accounts/{accountId}/projects/{projectId}/users/{uid}` (or a compact allowlist)
  - and update rules accordingly.

---

## Firestore collection layout (security-relevant)

All docs must include `accountId` (and `projectId` where applicable).

Recommended high-level layout:

- `accounts/{accountId}`
  - `users/{uid}` (account user: membership/role)
  - `invites/{inviteId}` (or `invites/{tokenHash}`) — invite issuance + status
  - `projects/{projectId}`
    - `budgetCategories/{budgetCategoryId}` (per-project budget allocations)
  - `items/{itemId}`
  - `transactions/{transactionId}`
  - `spaces/{spaceId}`
  - `requests/{requestId}` (request-doc workflows for multi-doc correctness)
  - `presets/default/...` (budget categories, vendor defaults, space templates, etc.)

Notes:

- This architecture does not require a `meta/sync` change-signal doc; collaboration is driven by scoped listeners on bounded queries.
- If you do introduce “meta” documents later (for example: project summaries, counters, or scope-level configuration), treat them as normal secured documents, not as a sync primitive.

---

## Rules principles (how we write rules safely)

### Baseline: authentication required

- All reads/writes require `request.auth != null`

### Membership gate (account boundary)

- A request is allowed only if:
  - the doc’s `accountId` matches the path account id, and
  - requester is a **system owner**, OR:
    - an account user doc exists for `request.auth.uid`, and
    - membership is not disabled (e.g. `disabledAt == null`, if you include that field)

### Validate server-owned sync fields

For entity docs that are directly client-writable, keep required fields minimal and rules-friendly:

- `accountId` (string; must match the path)
- `createdAt`/`updatedAt` timestamps (where the product needs them)
- `createdBy`/`updatedBy` (uid) when ownership/auditability matters
- `deletedAt` tombstone (timestamp or null) if you need soft deletes

Avoid inventing a global `version`/`lastMutationId` contract unless the product explicitly needs it; this architecture does not depend on a bespoke sync engine.

### Prefer “append-only” over “rewrite big arrays”

For relationships, prefer foreign keys on child docs (`item.projectId`, `item.transactionId`, etc.) rather than updating arrays on parent docs. This reduces:

- rule complexity
- write volume
- conflict surface

---

## What must be callable Functions (server-owned writes)

Use callable Functions when any of these are true:

- The operation touches **multiple documents** and must be atomic/correct.
- The operation requires **read-before-write** beyond simple version checks.
- The operation would require complex rule logic that’s hard to secure.

Examples (from existing app behavior / sync spec intent):

- Inventory allocation/sale operations that update multiple docs
- Lineage pointers / canonical relationships
- Rollups (project totals, counts) that must match canonical state
- Invitation acceptance (token validation → create account user → mark invite used)
- Entitlement/billing-gated operations (e.g., “create project beyond free limit”)

Callable Functions should:

- validate membership + role server-side
- run a Firestore transaction/batch
- write server-owned fields (`updatedAt`, `updatedBy`, derived selectors, rollups)
- update request status (`pending` → `applied|failed`) for request-doc workflows

---

## Request-doc workflows (security-critical)

Request docs are the default mechanism for multi-doc correctness:

- Client creates a request doc (works offline via queued writes).
- Server processes and applies changes in a transaction.
- Server records status on the request doc for debuggable UX.

Recommended shape (example path):

- `accounts/{accountId}/requests/{requestId}`

Rules must enforce:

- **Create**: allowed for authenticated account members, but only with:
  - `status == "pending"`
  - `createdBy == request.auth.uid`
  - no server-only fields set (`appliedAt`, `errorCode`, `errorMessage`, etc.)
- **Update**: clients should not be able to forge server results:
  - disallow changing `status` away from `"pending"`
  - or disallow client updates entirely (preferred; treat requests as append-only)
- **Read**: allowed for account members so UX can show pending/applied/failed.

Cloud Functions are the only writers of:

- `status = "applied" | "failed"`
- `appliedAt`
- error fields

This is a correctness and security boundary, not just a UX convenience.

---

## Invitations and account/user management

### Invite issuance

Allowed:

- owners/admins create invites in `accounts/{accountId}/invites/*`
- invite documents contain:
  - target email (or hashed email)
  - role to grant on acceptance
  - expiration
  - status

Not allowed:

- non-admin members creating invites
- clients directly creating account user docs for other users

### Invite acceptance

Invite acceptance should be a callable Function:

- inputs: invite token, optional profile data
- server validates token + expiry + status
- server creates `accounts/{accountId}/users/{uid}` with role
- server marks invite as used

This avoids fragile rules around “only the invited person can accept”.

---

## Storage security (receipts/images/PDFs)

Use Storage paths that include tenant and project boundaries:

`attachments/{accountId}/{projectId}/{attachmentId}/{filename}`

Storage rules:

- require authenticated user
- require membership in `accounts/{accountId}/users/{uid}`
- optionally require App Check

Integrity linkage:

- after upload, client (or function) updates the owning entity’s embedded `AttachmentRef`:
  - replace `offline://<mediaId>` with the remote URL
  - do not create a standalone Firestore attachment doc in the baseline model

---

## App Check

Enable **Firebase App Check** early (for Firestore + Functions + Storage) to reduce automated abuse.

- iOS: DeviceCheck/App Attest (depending on your iOS targets)
- Debug tokens for dev

---

## Threat model notes (practical)

- **Cross-tenant reads/writes**: prevented by membership checks keyed off path `accountId`
- **Client tampering with money/critical fields**: mitigate via:
  - callable Functions for critical operations, or
  - stricter rule validation + conflict detection
- **Request spam** (creating many request docs): mitigate via:
  - App Check
  - rules constraints on request shape/size
  - server-side rate limiting/abuse detection (Functions/Cloud Armor patterns)

