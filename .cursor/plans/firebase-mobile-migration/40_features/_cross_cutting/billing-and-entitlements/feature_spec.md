# Billing and entitlements (RevenueCat) — Feature spec (cross-cutting)

This doc defines the **monetization enforcement contract** for the Firebase mobile migration (React Native + Firebase), compatible with:

- `OFFLINE_FIRST_V2_SPEC.md` (Firestore-native offline persistence + scoped listeners + request-doc workflows)
- Firestore Rules constraints (no aggregate queries, no server-side “count” in rules)
- server-owned invariants (Callable Cloud Functions)

It is intentionally **provider-aware** (RevenueCat) but **provider-agnostic at the enforcement boundary**: Firestore holds a server-owned “enforcement snapshot” that Functions/Roles/UI can rely on without embedding RevenueCat-specific state machines everywhere.

---

## Where it’s used

- Projects: create project must be entitlement-gated (see `40_features/projects/feature_spec.md`)
- Items (planned): create/edit must enforce free-tier limits
- Transactions (planned): create/edit must enforce free-tier limits

---

## Goals

- Allow a free tier with explicit limits:
  - **maxProjects = 1** (per account)
  - **maxItems = 20**
  - **maxTransactions = 5**
  - **maxUsers = 1**
- Allow upgrade to **Pro** that increases/removes limits.
- Enforce limits **server-side** (clients cannot bypass).
- Provide predictable UX offline (clear messaging; no “mystery failures”).

---

## Non-goals

- Implementing payment flows (purchase UI, paywall UI design, App Store / Play Billing specifics).
- Defining every RevenueCat field or mirroring the entire RevenueCat customer object in Firestore.

---

## Definitions

### Plan types (product language)

- **Free**
- **Pro**

These are product-level plan types. They are not necessarily 1:1 with store products; RevenueCat is the source of truth.

### Enforcement snapshot (server-owned)

We store a minimal, server-owned document in Firestore that represents:

- whether the account is currently entitled to Pro behavior
- what limits apply right now

This is what the client reads for UX and what callable Functions use for allow/deny decisions.

---

## Data model (recommended)

### Entitlements snapshot

Path:

- `accounts/{accountId}/billing/entitlements/current`

Recommended fields (v1):

- `accountId: string` (redundant but helps debugging / validation)
- `planType: "free" | "pro"` (product language, not store product)
- `limits`:
  - `maxProjects: number`
  - `maxItems: number`
  - `maxTransactions: number`
  - `maxUsers: number`
- `updatedAt: Timestamp`
- `source` (optional but recommended for auditing/debug):
  - `provider: "revenuecat"`
  - `environment?: "sandbox" | "production"`
  - `appUserId?: string`
  - `lastSyncedAt?: Timestamp`

Rules:

- Treat this doc as **server-owned** (written only by Functions / trusted backend).
- Clients can read it for gating UX.

### Usage (server-owned counters)

To enforce limits without expensive queries and without rules-time aggregation, maintain server-owned counters:

- `accounts/{accountId}/billing/usage`
  - `projectCount: number`
  - `itemCount: number`
  - `transactionCount: number`
  - `userCount: number`
  - `updatedAt: Timestamp`

Notes:

- These are **account-level** counters and are **not** fields on `Project` documents.
- These are updated only by server-owned operations (callable Functions / trusted backend).
- Counters should be updated transactionally with the operation that changes them.

---

## Enforcement points (Rules vs Functions vs Client)

### Source of truth

- **Cloud Functions** are the source of truth for **limit-enforced creates** (and any multi-doc operation).
- **Firestore Rules** should disallow direct client creates where enforcement depends on counts/limits.
- **Client UX** uses the snapshot to preflight and show the right messaging, but cannot be relied on for enforcement.

### Gated operations (v1)

#### Create project (required)

- Disallow direct client `create` to `accounts/{accountId}/projects/{projectId}`.
- Prefer a **request-doc workflow** so the create can be queued offline and applied server-side when online:
  - client creates: `accounts/{accountId}/requests/{requestId}` with:
    - `type: "createProject"`
    - `status: "pending"`
    - `opId: "<stable idempotency key for this logical create>"`
    - required fields in `payload`
  - Function processes request in a Firestore transaction:
    - validates membership + role (see `10_architecture/security_model.md`)
    - reads `accounts/{accountId}/billing/entitlements/current`
    - reads `accounts/{accountId}/billing/usage.projectCount`
    - enforces: `projectCount < limits.maxProjects` (unless “unlimited” in Pro policy)
    - writes the new project doc
    - increments `billing/usage.projectCount`
    - marks request `status` (`applied | denied | failed`) with debuggable error info
      - if denied due to entitlements/limits, use `errorCode="ENTITLEMENT_DENIED"`

#### Create item / transaction (planned)

Same pattern as project creation:

- disallow direct client creates where a limit must be enforced
- provide server-owned create processing (prefer request-doc workflows) that enforce `itemCount` / `transactionCount`

#### Add user to account (required)

User additions (invites/acceptance, role grants, or membership creation) must be entitlement-gated:

- disallow direct client creates to `accounts/{accountId}/memberships/{membershipId}` (or equivalent)
- server-owned workflow validates `userCount < limits.maxUsers`
- increments `billing/usage.userCount` when a membership becomes active

---

## Offline behavior contract

### Guiding principle

Upgrade requires network, so offline behavior must prioritize:

- avoiding “local drafts that later disappear”
- giving a clear “go online to upgrade/verify” path when limits might be exceeded

### Policy (v1)

When offline, for any **gated create** (project/item/transaction):

- If the app can prove (from **cached** `billing/entitlements/current` + **cached** `billing/usage`) that the operation is **under the limit**, it may proceed locally (pending state) and will sync when online.
- If the app cannot prove it is under the limit (missing cache, stale cache, or already at limit), the app must:
  - block the operation
  - show a clear message: “Connect to verify your plan / upgrade to Pro”
  - provide an upgrade CTA that works once online

Rationale:

- This preserves conversion (upgrade CTA appears immediately when online).
- It avoids confusing local-only drafts when enforcement later denies on reconnect.

---

## RevenueCat integration contract (high-level)

This spec assumes RevenueCat is the source of truth for plan entitlements.

Minimum requirement:

- A server-owned path updates `accounts/{accountId}/billing/entitlements/current` to match RevenueCat-derived access.

Implementation choices (acceptable):

- RevenueCat webhooks → Cloud Function → update entitlements snapshot
- Client purchase completes → client triggers a “refresh entitlements” callable that re-validates with RevenueCat server-side → updates snapshot

Regardless of mechanism:

- Firestore entitlements snapshot must remain the stable enforcement boundary.

---

## Parity evidence

This is a **net-new** feature area in the migration plan (not implemented in the current web app); it is referenced as:

- `40_features/feature_list.md` → C3 “Monetization: free tier + upgrade gating (entitlements)”
- `40_features/projects/feature_spec.md` references this doc for server-enforced project creation

