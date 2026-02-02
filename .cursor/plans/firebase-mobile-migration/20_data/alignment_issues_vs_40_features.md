# Alignment issues: `20_data` vs `40_features` (fresh pass)

This file captures mismatches found between:

- `/.cursor/plans/firebase-mobile-migration/20_data/*` (data model + contracts), and
- `/.cursor/plans/firebase-mobile-migration/40_features/**` (feature specs; product truth).

Hard constraint reminder:

- Do not change `src/data/requestDocs.ts` (hands-off). This file is used as a read-only reality check for “drift”.

## Review scope (this pass)

All of the following feature specs were reviewed:

- `40_features/auth-and-invitations/feature_spec.md`
- `40_features/budget-and-accounting/feature_spec.md`
- `40_features/business-inventory/feature_spec.md`
- `40_features/connectivity-and-sync-status/feature_spec.md`
- `40_features/inventory-operations-and-lineage/feature_spec.md`
- `40_features/invoice-import/feature_spec.md`
- `40_features/navigation-stack-and-context-links/feature_spec.md`
- `40_features/projects/feature_spec.md`
- `40_features/project-items/feature_spec.md`
- `40_features/project-transactions/feature_spec.md`
- `40_features/reports-and-printing/feature_spec.md`
- `40_features/spaces/feature_spec.md`
- `40_features/settings-and-admin/feature_spec.md`
- `40_features/pwa-service-worker-and-background-sync/feature_spec.md`
- `40_features/_cross_cutting/app-safety-and-diagnostics/feature_spec.md`
- `40_features/_cross_cutting/billing-and-entitlements/feature_spec.md`
- `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md`
- `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`
- `40_features/_cross_cutting/scope-switching-and-sync-lifecycle/feature_spec.md`

Canonical data sources used for alignment:

- `20_data/data_contracts.md` (canonical entity shapes)
- `20_data/firebase_data_model.md` (canonical Firestore paths)
- `src/data/*` (data layer helpers; checked for drift only)

## Per-feature alignment matrix (summary)

Status legend:

- **ALIGNED**: feature’s assumed paths/shapes are explicitly present in `20_data` (or trivially derivable without inventing semantics).
- **MISMATCH (HIGH/MED/LOW)**: a gap that would cause incorrect implementation/security/rules/invariants (HIGH), drift/inconsistent UX (MED), or doc clarity issues (LOW).

| Feature | Primary entities touched | Status | Root cause(s) |
|---|---|---|---|
| Auth + invitations | Member, Invite, (Account context) | **ALIGNED** | — |
| Projects | Project, ProjectBudgetCategory, ProjectPreferences, Billing* | **ALIGNED** | — |
| Budget + Accounting | BudgetCategory, ProjectBudgetCategory, Transaction, Item, ProjectPreferences | **ALIGNED** | — |
| Project Items | Item, Transaction (linkage), canonical INV_* semantics | **ALIGNED** | — |
| Project Transactions | Transaction, Item (itemization), embedded media refs | **ALIGNED** | — |
| Business Inventory | Item, Transaction, embedded media refs | **ALIGNED** | — |
| Inventory ops + lineage | RequestDoc, LineageEdge, Item, Transaction | **ALIGNED** | — |
| Spaces | Space, SpaceTemplate, Item(spaceId), embedded media refs | **ALIGNED** | — |
| Settings + Admin | Business profile, presets, Member, Invite, Billing* | **ALIGNED** | — |
| Reports + share/print | Business profile, Project, Items, Transactions, Spaces, BudgetCategory | **ALIGNED** | — |
| Invoice import | RequestDoc, Transaction(+PDF receipt), Item(+images), BudgetCategory | **ALIGNED** | — |
| Billing + entitlements (x-cut) | BillingEntitlements, BillingUsage, RequestDoc (account-scoped) | **ALIGNED** | — |
| Roles v2 (x-cut) | Member.allowedBudgetCategoryIds, Item.createdBy, Item.inheritedBudgetCategoryId, canonical txn visibility | **ALIGNED** | — |
| Scope switching + sync lifecycle (x-cut) | (listener scopes only) | **ALIGNED** | — |
| Connectivity + sync status | RequestDoc status + error fields, “pending writes” | **ALIGNED** | — |
| Offline media lifecycle (x-cut) | embedded media refs on many entities, local media records/queue | **ALIGNED** | — |
| Navigation + list-state | (no domain shapes) | **ALIGNED** | — |
| PWA background sync (policy) | (no domain shapes) | **ALIGNED** | — |
| App safety + diagnostics | (no domain shapes) | **ALIGNED** | — |

## Per-feature notes (entities → required shapes/paths → mapping → status)

### `auth-and-invitations`

- **Entities touched**: `Member`, `Invite`, plus an implied “account context” record for selecting/remembering `accountId`.
- **Firestore paths assumed**:
  - `accounts/{accountId}/members/{uid}`
  - `accounts/{accountId}/invites/{inviteId}`
- **Required fields/invariants**:
  - Server-owned invite acceptance (callable `acceptInvite`), client must not write memberships.
  - Membership-gated account context selection (must not “guess” accountId offline).
- **20_data mapping**:
  - `Member`, `Invite` exist in `data_contracts.md` and paths exist in `firebase_data_model.md`.
  - Account context is **local-only** (device storage) and validated against `Member` when online (see GAP G).
- **Status**: **ALIGNED**.

### `projects`

- **Entities touched**: `Project`, `ProjectBudgetCategory`, `ProjectPreferences`, plus billing gating (`BillingEntitlements`, `BillingUsage`).
- **Firestore paths assumed**:
  - `accounts/{accountId}/projects/{projectId}`
  - `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`
  - `accounts/{accountId}/users/{userId}/projectPreferences/{projectId}`
- **Required fields/invariants**:
  - Project create is server-enforced (no direct client create).
  - Seeds pinned categories (Furnishings) for the creator.
  - Mentions “update `meta/sync` once” (ambiguous under Firestore-native baseline).
- **20_data mapping**:
  - `Project`, `ProjectBudgetCategory`, `ProjectPreferences` are present in `data_contracts.md`.
  - Paths are present in `firebase_data_model.md`.
  - `meta/sync` is not part of the Firestore-native baseline and is intentionally not modeled in `20_data`.
- **Status**: **ALIGNED** (doc wording corrected; no `meta/sync` dependency).

### `budget-and-accounting`

- **Entities touched**: `BudgetCategory` (presets), `ProjectBudgetCategory`, `ProjectPreferences`, `Transaction`, `Item` (canonical attribution uses `inheritedBudgetCategoryId`).
- **Firestore paths assumed**:
  - Project budgets: `accounts/{accountId}/projects/{projectId}/budgetCategories/{budgetCategoryId}`
  - Category presets: `accounts/{accountId}/presets/budgetCategories/{budgetCategoryId}` (spec wording corrected)
  - Items/transactions: project-scope collections under the project.
- **Required fields/subshapes/invariants**:
  - Canonical attribution: `INV_*` rows attributed by linked items grouped by `item.inheritedBudgetCategoryId`.
  - Fee categories by explicit `metadata.categoryType === "fee"`; exclude-from-overall by explicit boolean.
  - Money persistence must follow the canonical cents model in `data_contracts.md` (spec wording corrected to reference `*Cents` persisted fields).
- **20_data mapping**:
  - Field-level contracts are present in `data_contracts.md`.
  - Paths are present in `firebase_data_model.md`.
  - Roles v2 canonical transaction visibility selectors are now explicit in `data_contracts.md` (`Transaction.budgetCategoryIds`, `Transaction.uncategorizedItemCreatorUids`) and in the Roles v2 spec.
- **Status**: **ALIGNED**.

### `project-items`

- **Entities touched**: `Item` (including required `inheritedBudgetCategoryId`), `Transaction` (linkage via `item.transactionId`), canonical inventory semantics (`INV_PURCHASE_*`, `INV_SALE_*`).
- **Firestore paths assumed**:
  - Project items: `accounts/{accountId}/projects/{projectId}/items/{itemId}`
  - Inventory items: `accounts/{accountId}/inventory/items/{itemId}`
- **Required fields/invariants**:
  - `item.inheritedBudgetCategoryId` is required (nullable allowed).
  - `item.createdBy` is required for Roles v2 “own uncategorized” rule.
  - `INV_*` category attribution must be item-driven; `transaction.budgetCategoryId` must not be relied on for canonical rows.
- **20_data mapping**:
  - `Item` contract explicitly includes `createdBy` and `inheritedBudgetCategoryId`.
  - `Transaction` contract covers `INV_*` semantics and optional canonical selector fields.
- **Status**: **ALIGNED**.

### `project-transactions`

- **Entities touched**: `Transaction`, `Item` (itemization + linkage), `BudgetCategory` (pickers/filters), `VendorDefaults`, embedded media refs.
- **Firestore paths assumed**:
  - Transactions (project/inventory): `accounts/{accountId}/projects/{projectId}/transactions/{transactionId}` and `accounts/{accountId}/inventory/transactions/{transactionId}`
  - Vendor defaults: `accounts/{accountId}/presets/vendorDefaults/current`
- **Required fields/subshapes/invariants**:
  - Receipt attachments include **images + PDFs** (explicit in spec).
  - Embedded media arrays: `receiptImages[]`, `otherImages[]`, and legacy `transactionImages[]` mirroring.
  - Canonical rows should be treated as uncategorized; category filter for canonical rows must be item-driven.
  - When editing a non-canonical transaction’s `budgetCategoryId`, linked items must have `item.inheritedBudgetCategoryId` updated.
  - Money persistence must follow the canonical cents model in `data_contracts.md` (`amountCents`, etc.).
- **20_data mapping**:
  - Transaction embedded media arrays exist in `data_contracts.md` and use the canonical `AttachmentRef` contract (explicit `kind: "image" | "pdf"`).
  - Vendor defaults contract exists.
  - The “edit transaction category updates linked items” rule is now called out as a cross-entity invariant in `20_data/data_contracts.md` → `Entity: Transaction`.
- **Status**: **ALIGNED** — attachment contract is now canonical (`AttachmentRef`), and the cross-entity invariant is documented in `20_data/data_contracts.md` → `Entity: Transaction`.

### `business-inventory`

- **Entities touched**: inventory-scope `Item` and `Transaction`, media (item images, receipts), and allocation flows (request-doc invariants).
- **Firestore paths assumed**:
  - Inventory items/transactions: `accounts/{accountId}/inventory/items/{itemId}`, `accounts/{accountId}/inventory/transactions/{transactionId}`
- **Required fields/subshapes/invariants**:
  - Item images: add/remove/set primary (implies a canonical persisted item-image field/shape).
  - Inventory transaction create requires a category in UX (constraint, not necessarily a universal contract rule).
- **20_data mapping**:
  - `Item` contract now includes `images[]` as the canonical item media field.
- **Status**: **MISMATCH (MED)** — item image shape is now aligned, but attachment representation/state is still unresolved for receipts (PDF vs image + uploading/failed/done) (see GAP B).
- **Status**: **ALIGNED** — receipt + item image attachment representation/state is now canonical via `AttachmentRef` + derived local upload state (see GAP B adopted default).

### `inventory-operations-and-lineage`

- **Entities touched**: `RequestDoc` (project/inventory scoped), `LineageEdge` (account-wide), `Item` pointers (`originTransactionId`, `latestTransactionId`), canonical `INV_*` transactions.
- **Firestore paths assumed**:
  - Requests:
    - `accounts/{accountId}/projects/{projectId}/requests/{requestId}`
    - `accounts/{accountId}/inventory/requests/{requestId}`
  - Lineage edges: `accounts/{accountId}/lineageEdges/{edgeId}`
- **Required fields/subshapes/invariants**:
  - Request docs require `opId` idempotency key and structured payloads (ITEM_SALE_*).
  - Payload shapes include `expected` precondition snapshots for conflict detection.
- **20_data mapping**:
  - RequestDoc contract exists with `opId` and canonical paths enumerated.
  - Payload shapes are now codified under `Entity: RequestDoc` (“Known request payload schemas”).
- **Status**: **ALIGNED**.

### `spaces`

- **Entities touched**: `Space` (project/inventory scoped), `SpaceTemplate` (presets), `Item.spaceId` (scope-consistency), `Space.images[]`, `Space.checklists[]`.
- **Firestore paths assumed**:
  - Project spaces: `accounts/{accountId}/projects/{projectId}/spaces/{spaceId}`
  - Inventory spaces: `accounts/{accountId}/inventory/spaces/{spaceId}`
  - Templates: `accounts/{accountId}/presets/spaceTemplates/{templateId}`
- **Required fields/subshapes/invariants**:
  - Item↔space scope consistency: project item can only reference project space; inventory item can only reference inventory space.
  - Template normalization: checklist items forced to `isChecked=false` on create.
- **20_data mapping**:
  - `Space` and `SpaceTemplate` contracts exist and paths match `firebase_data_model.md`.
- **Status**: **ALIGNED**.

### `settings-and-admin`

- **Entities touched**:
  - Business profile (name + logo)
  - Presets: `BudgetCategory`, `VendorDefaults`, `SpaceTemplate`
  - `Member`, `Invite`
  - Billing gating for invites/users (free tier userCount limit)
- **Firestore paths assumed**:
  - Presets + membership/invites + billing are all explicitly covered by `20_data` **except** business profile.
  - The spec refers to “`accounts` / business profile fields (name, logo URL, versioning metadata)” but does not provide a canonical document path.
- **Required fields/subshapes/invariants**:
  - Admin-only business profile update (online-required by default).
  - Business profile logo participates in the offline media lifecycle and has UI-visible “uploading/failed/done” state.
- **20_data mapping**:
  - `BusinessProfile` exists in `data_contracts.md` and `firebase_data_model.md` at:
    - `accounts/{accountId}/businessProfile/current`
- **Status**: **ALIGNED** — business profile is defined and its logo uses the canonical attachment contract (`AttachmentRef` + derived local upload state).

### `reports-and-printing`

- **Entities touched**: Project, Items, Transactions, Spaces, BudgetCategory, and **Business profile** (branding).
- **Firestore paths assumed**:
  - Project-scoped: project/items/transactions/spaces.
  - Account-scoped presets: budget categories.
  - Business profile: `accounts/{accountId}/businessProfile/current`
- **Required fields/subshapes/invariants**:
  - Category attribution for reporting must support canonical item-driven attribution.
  - Report headers use business name + logo, and warn if logo media is `local_only|uploading|failed`.
  - Reports must read “cents” fields (`amountCents`, `purchasePriceCents`, etc.) and format for display; do not persist floats/decimals.
- **20_data mapping**:
  - Attribution model is present (items + transactions + `inheritedBudgetCategoryId`).
  - Business profile path/shape exists.
  - Remaining gap: how we represent “PDF vs image” and “uploading vs failed” for attachments in a consistent way (see GAP B).
- **Status**: **ALIGNED**.

### `invoice-import`

- **Entities touched**: Transaction + Items created together via request-doc workflow; embedded media includes invoice **PDF receipt** and Wayfair thumbnail images for items.
- **Firestore paths assumed**:
  - Project requests: `accounts/{accountId}/projects/{projectId}/requests/{requestId}`
  - Transactions/items in project scope.
- **Required fields/subshapes/invariants**:
  - Request-doc payload shape for “create transaction with items”.
  - Receipts accept PDFs; item images must exist as a canonical item media field.
  - Offline media lifecycle applies (local placeholders + upload queue + retries).
  - Draft “amount / prices” must be persisted via the canonical cents fields on `Transaction`/`Item`.
- **20_data mapping**:
  - RequestDoc includes a minimal “invoice import create transaction + items” payload schema.
  - PDF-vs-image media representation is now canonical via `AttachmentRef.kind = "image" | "pdf"` (see `20_data/data_contracts.md`).
  - Item media fields are now canonical (`item.images[]`).
- **Status**: **ALIGNED**.

### `connectivity-and-sync-status`

- **Entities touched**: request-doc state (pending/applied/failed + error fields), plus “pending local writes” (runtime/SDK state, not Firestore schema).
- **Firestore paths assumed**: none beyond “request docs exist”.
- **Status**: **ALIGNED** (schema-wise).

### `_cross_cutting/billing-and-entitlements`

- **Entities touched**: `BillingEntitlements`, `BillingUsage`, plus account-scoped gated creates via request-doc.
- **Firestore paths assumed**:
  - `accounts/{accountId}/billing/entitlements/current`
  - `accounts/{accountId}/billing/usage`
  - `accounts/{accountId}/requests/{requestId}` (account-scoped request-docs)
- **Required fields/subshapes/invariants**:
  - Server-owned enforcement snapshot + counters.
  - Create project (and other gated creates) should use request-doc workflow.
  - Status vocabulary includes `denied` in addition to `failed` for explicit policy rejection.
- **20_data mapping**:
  - Billing docs and paths exist in `data_contracts.md` and `firebase_data_model.md`.
  - RequestDoc includes `denied` in its contract, and account-scoped request path exists in `data_contracts.md`.
  - `src/data/requestDocs.ts` now supports account-scoped requests and models `opId` + `denied`.
- **Status**: **ALIGNED**.

### `_cross_cutting/category-scoped-permissions-v2` (Roles v2)

- **Entities touched**:
  - `Member.allowedBudgetCategoryIds` (map/set recommended)
  - `Item.createdBy` and `Item.inheritedBudgetCategoryId`
  - canonical transaction visibility derived from linked items
- **Required invariants**:
  - Scoped users can read canonical `INV_*` transaction **only if** at least one linked item is in-scope.
  - Enforcement must be server-side and must not depend on “subscribe to everything then filter”.
- **20_data mapping**:
  - `Member.allowedBudgetCategoryIds` exists (map/set shape) and item selectors exist.
  - Canonical transaction visibility selectors are now explicit and canonical in `data_contracts.md`:
    - `Transaction.budgetCategoryIds`
    - `Transaction.uncategorizedItemCreatorUids`
- **Status**: **ALIGNED**.

### `_cross_cutting/offline-media-lifecycle`

- **Entities touched**: embedded media refs on transactions/spaces/items/business profile; local media cache records; durable upload queue jobs.
- **Required subshapes/invariants**:
  - UI state machine: `local_only | uploading | uploaded | failed`.
  - Works for images and PDFs.
  - Cleanup/orphan policies.
- **20_data mapping**:
  - `data_contracts.md` defines only `{ url, isPrimary? }` and leaves state+metadata TBD.
  - `Item` media fields exist (`item.images[]`).
  - `BusinessProfile` exists (`accounts/{accountId}/businessProfile/current`).
- **Status**: **ALIGNED** (attachment contract and derived local state are now canonical; see GAP B adopted default).

### `_cross_cutting/scope-switching-and-sync-lifecycle`

- **Entities touched**: none (this is runtime listener scoping + list state).
- **Data layer pointers**: `src/data/LISTENER_SCOPING.md`, `src/data/listenerManager.ts`, `src/data/useScopedListeners.ts`.
- **Status**: **ALIGNED** (schema-wise).

### `navigation-stack-and-context-links`

- **Entities touched**: none (navigation/list-state only).
- **Status**: **ALIGNED**.

### `pwa-service-worker-and-background-sync`

- **Entities touched**: none (policy/scheduling only under Firestore-native baseline).
- **Status**: **ALIGNED**.

### `_cross_cutting/app-safety-and-diagnostics`

- **Entities touched**: none (no new Firestore entity contracts required).
- **Status**: **ALIGNED**.

## Gaps & fixes (canonical resolutions; doc-only recommendations)

### Strong defaults (proposed; not yet adopted)

This section is intentionally **recommendations only**. It is here so implementers have “strong defaults” written down while the project decides whether to formally adopt them.

### GAP A) Business profile doc path + shape (RESOLVED)

- **Where it shows up**: `settings-and-admin`, `reports-and-printing`, `_cross_cutting/offline-media-lifecycle`.
- **Why it matters**: reports need deterministic branding inputs; admin gating + media lifecycle need a canonical write target.
RESOLVED:
- `BusinessProfile` is now canonicalized:
  - Contract: `20_data/data_contracts.md` → `Entity: BusinessProfile`
  - Path: `accounts/{accountId}/businessProfile/current`

### GAP B) Offline media state machine is now representable in the canonical contracts (RESOLVED)

- **Where it shows up**: transactions receipts (images+PDFs), space images, business logo, item images.
- **Why it matters**: multiple features require consistent UI for `local_only/uploading/uploaded/failed` and consistent retry/cleanup semantics.
RESOLVED (canonical; adopted):
- Persist attachments on domain entities as `AttachmentRef` (embedded; no attachment docs baseline):
  - includes explicit `kind: "image" | "pdf"` (no URL inference)
  - allows `url = offline://<mediaId>` placeholders
  - defined in `20_data/data_contracts.md` → “Embedded media references (URLs + `offline://` placeholders)”
- Track upload state locally and derive UI state:
  - `local_only | uploading | failed | uploaded` lives in a durable local upload queue + local media cache
  - described in `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`

### GAP C) Item media fields (RESOLVED)

- **Where it shows up**: business inventory item create/edit/detail, invoice import (Wayfair thumbnails), offline media lifecycle.
- **Why it matters**: multiple features require adding/removing images and setting primary image; without a canonical persisted shape, implementations will diverge.
RESOLVED:
- `Entity: Item` now includes `images?: Array<{ url: string; isPrimary?: boolean }>` in `data_contracts.md`.

### GAP E) Request-doc payloads are specified in feature specs but not codified in `20_data` (MED)

- **Where it shows up**: inventory operations and invoice import.
- **Why it matters**: implementers need concrete payload fields and conflict-detection `expected` shapes to build Functions correctly and idempotently.
- **Proposed canonical resolution (doc-only)**:
  - Codify the inventory operations payloads directly under `Entity: RequestDoc` (done).
  - Add a minimal “invoice import create transaction + items” request payload schema under `Entity: RequestDoc` without standardizing a `type` string yet (done).

### GAP G) Account context source-of-truth is canonicalized via local device storage (RESOLVED)

- **Where it shows up**: auth bootstrap (choosing/remembering accountId).
- **Why it matters**: offline-safe startup depends on a deterministic “last validated accountId” source.
RESOLVED:
- Store the last-selected (and last-validated) `accountId` **on-device**.
- When online, revalidate membership by checking `accounts/{accountId}/members/{uid}`; if invalid, clear the stored account and force re-pick.

### GAP H) `meta/sync` wording is still present in a feature spec but not defined (MED)

RESOLVED:
- `meta/sync` wording was removed from `40_features/projects/feature_spec.md` to align with the Firestore-native baseline.

### GAP I) Money field naming/typing drift across feature specs (MED)

- **Where it shows up**: budget/accounting, reports/printing, invoice import (and parity references to legacy web).
- **Why it matters**: `20_data/data_contracts.md` mandates **integer cents** persisted in Firestore; if a feature is implemented using decimal floats or ambiguous names (`amount`, `purchasePrice`) it will silently corrupt rollups and exports.
- **Proposed canonical resolution (doc-only)**:
  - Add a short cross-cutting note in `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md` (done).
  - Update `40_features/budget-and-accounting/feature_spec.md` to explicitly reference persisted `*Cents` fields in rollup logic (done).
  - For report specs, explicitly reference the cents fields by name when describing computations (still required; Reports remains HIGH due to BusinessProfile/media gaps).

### GAP J) Request-doc helper drift (RESOLVED)

- **Where it shows up**: `_cross_cutting/billing-and-entitlements` (gated creates), and any other account-scoped request-doc workflow.
- **Resolution**: We are adopting the canonical RequestDoc contract (no adapter/shim guidance):
  - support account/project/inventory request-doc paths
  - require `opId`
  - support `status: pending | applied | failed | denied`
  - use one canonical denial code: `ENTITLEMENT_DENIED`
  - see `20_data/data_contracts.md` → `Entity: RequestDoc` and `20_data/request_docs_plan.md`

## Request-doc implementation note (single contract)

Reality check (repo state today):
- `src/data/requestDocs.ts` currently supports project + inventory scopes only and does not model `opId` or `denied`.

Implementation direction (greenfield / roll-out once):
- Implement request docs per the canonical contract in:
  - `20_data/data_contracts.md` → `Entity: RequestDoc`
  - `20_data/request_docs_plan.md`

Minimum requirements for implementation:
- Request paths: account + project + inventory
- RequestDoc fields include `opId`
- Status supports: `pending | applied | failed | denied`
- Denial uses: `errorCode="ENTITLEMENT_DENIED"` (single canonical code)
