# Feature specs sweep checklist (Offline Data v2 alignment)

This document is the **sweep controller** for bringing feature specs up to parity quality and ensuring they reference the correct architecture.

Primary architecture source of truth:
- `OFFLINE_FIRST_V2_SPEC.md`

Parity source of truth for “what the current app does”:
- `/Users/benjaminmackenzie/Dev/ledger` (the app we are migrating from)

---

## How to use this checklist

- Work **chunk-by-chunk**.
- For a chunk, copy the prompt into a new AI/dev chat (or use it as a human checklist) and sweep the listed folders.
- When a folder is corrected, check it off.

### What “swept” means (definition of done per folder)

For a given `40_features/<feature>/` folder, we consider it swept when:

- [ ] **Architecture references are correct** and consistent with `OFFLINE_FIRST_V2_SPEC.md`:
  - Firestore-native offline persistence is the baseline (Firestore is canonical).
  - Scoped/bounded listeners are allowed; **no** “listen to everything”.
  - Multi-doc correctness uses **request-doc workflows** (server applies changes in a Firestore transaction).
  - SQLite is used only as an **optional derived search index** (index-only), if the product requires robust offline item search.
- [ ] **Search behavior is explicit** anywhere a spec says “search”:
  - Exact match fields are listed (project vs inventory scope can differ).
  - Any normalization is called out (e.g., fuzzy SKU normalization).
- [ ] **Multi-entity operations are explicit**:
  - If an operation touches multiple docs or needs invariants, the spec clearly states “request doc + Cloud Function transaction”.
  - Idempotency/retry semantics are described.
- [ ] **Parity evidence is present**:
  - Non-obvious behaviors point to `/Users/benjaminmackenzie/Dev/ledger/...` code (file + function/component), or are labeled **Intentional delta**.
- [ ] **No stale architecture language remains**:
  - Remove/replace “outbox”, “delta sync”, “change-signal listener”, “SQLite is source of truth” language unless it is explicitly framed as **web parity** with an **intentional delta** for mobile.

---

## Chunk 0 — Sweep setup + scope list (meta)

### Folders / docs to sweep
- [x] `40_features/feature_list.md` (update any remaining architecture notes to match `OFFLINE_FIRST_V2_SPEC.md`)
- [x] `40_features/_authoring/` (optional: ensure templates/workflow don’t imply the old sync-engine)

### Sweep prompt (copy/paste)

Use `OFFLINE_FIRST_V2_SPEC.md` as the canonical architecture. Sweep `40_features/feature_list.md` and `_authoring/` for stale references to “SQLite source of truth / outbox / delta sync / change-signal”. Replace with Firestore-native offline persistence + scoped listeners + request-doc workflows, and ensure the checklist guidance for feature authors requires explicit search fields where relevant. Keep parity notes clearly labeled as parity (web) vs intentional delta (mobile).

---

## Chunk 1 — Foundation UX + navigation

### Folders to sweep
- [x] `40_features/auth-and-invitations/`
- [x] `40_features/connectivity-and-sync-status/`
- [x] `40_features/navigation-stack-and-context-links/`
- [x] `40_features/settings-and-admin/`

### Sweep prompt (copy/paste)

Sweep the listed feature folders for architecture alignment and missing detail.

Rules:
- Align all architecture references to `OFFLINE_FIRST_V2_SPEC.md` (Firestore-native offline persistence + scoped listeners + request-doc for multi-doc correctness).
- Remove/replace “outbox/delta-sync/change-signal” language unless it is explicitly “web parity” with an “Intentional delta” note.
- Ensure offline UX states are explicit (cache-first reads, queued writes, pending/applied/failed for request-doc operations).
- For any “search” behavior in these features, list the exact fields matched.

Parity evidence:
- When you describe behaviors, cite `/Users/benjaminmackenzie/Dev/ledger/...` files and functions/components.

Output:
- Make minimal edits directly in the docs in these folders (feature_spec, acceptance_criteria, README, UI screen contracts, prompt packs).

---

## Chunk 2 — Workspaces + shared domain modules (core parity)

### Folders to sweep
- [x] `40_features/projects/`
- [x] `40_features/project-items/`
- [x] `40_features/project-transactions/`
- [x] `40_features/spaces/`
- [x] `40_features/business-inventory/`

### Sweep prompt (copy/paste)

Sweep the listed workspaces/modules for missing implementation-critical detail and architecture alignment.

Must-do checks:
- Architecture: align to `OFFLINE_FIRST_V2_SPEC.md` (Firestore canonical; scoped listeners; request-doc workflows).
- Search: every spec that mentions searching items/transactions/spaces must list the exact matched fields (and any normalization rules) based on `/Users/benjaminmackenzie/Dev/ledger` parity code.
- Shared-module contracts: ensure scope-specific behavior is captured as config/contract (not duplicated “project vs inventory” implementations).
- Multi-doc operations: any cross-entity change must be described as request-doc + Cloud Function transaction + idempotency.
- Offline UX: make pending/queued/applied/failed states explicit and consistent.

Parity evidence:
- Add “Observed in …” pointers into `/Users/benjaminmackenzie/Dev/ledger/...` for list state persistence, filters, sort modes, grouping, and any non-obvious UX rules.

Output:
- Edit docs in-place; keep deltas small but make missing fields/rules explicit.

---

## Chunk 3 — Cross-workspace correctness + rollups

### Folders to sweep
- [x] `40_features/inventory-operations-and-lineage/`
- [x] `40_features/budget-and-accounting/`

### Sweep prompt (copy/paste)

Sweep correctness-oriented features for architecture alignment and invariants clarity.

Must-do checks:
- Replace any remaining old sync-engine assumptions with `OFFLINE_FIRST_V2_SPEC.md` (request-doc workflows for multi-doc correctness).
- Make idempotency explicit: request id / op id, retry rules, and partial completion semantics.
- Ensure budgeting/canonical attribution rules cite the correct item/transaction fields and specify how canonical rows should behave.
- Ensure any mention of “search” includes explicit fields.

Parity evidence:
- Cite `inventoryService.ts`, `operationQueue.ts`, lineage service, and budgeting UI/service code in `/Users/benjaminmackenzie/Dev/ledger`.

Output:
- Update feature_spec, acceptance_criteria, flows, and prompt packs as needed.

---

## Chunk 4 — Import + reporting outputs

### Folders to sweep
- [x] `40_features/invoice-import/`
- [x] `40_features/reports-and-printing/`

### Sweep prompt (copy/paste)

Sweep these folders for (a) architecture alignment, (b) missing field-level requirements, and (c) offline-first UX correctness.

Must-do checks:
- Ensure any multi-doc operations are framed as request-doc workflows if needed.
- Ensure media/attachment flows align with Offline Data v2 (offline persistence + queued uploads; consistent error/pending UX).
- Ensure reporting computation inputs are explicit (which entities/fields are used).
- If these features mention searching/filtering, list exact fields.

Parity evidence:
- Cite the relevant import/report pages/services in `/Users/benjaminmackenzie/Dev/ledger`.

---

## Chunk 5 — Web-only parity knowledge (RN translation)

### Folders to sweep
- [x] `40_features/pwa-service-worker-and-background-sync/`

### Sweep prompt (copy/paste)

Sweep this folder as “parity knowledge”, not a literal RN implementation.

Must-do checks:
- Remove any implication that RN must implement service workers.
- Preserve user-visible expectations (offline use, queued operations, retry UX), but map them to `OFFLINE_FIRST_V2_SPEC.md` primitives.
- Ensure “background sync” is described as best-effort and not required for correctness.

---

## Chunk 6 — Cross-cutting feature folders (shared policy/specs)

### Folders to sweep
- [x] `40_features/_cross_cutting/offline-media-lifecycle/`
- [x] `40_features/_cross_cutting/category-scoped-permissions-v2/`
- [x] `40_features/_cross_cutting/billing-and-entitlements/`
- [x] `40_features/_cross_cutting/ui/` (and referenced UI component docs)

### Sweep prompt (copy/paste)

Sweep cross-cutting specs for consistency and “single source of truth” quality.

Must-do checks:
- Align architecture references to `OFFLINE_FIRST_V2_SPEC.md`.
- Ensure the shared UI/module contracts are explicit and referenced by feature folders (avoid duplicated specs).
- If any cross-cutting doc implies search behavior, ensure it points to the canonical search-field contracts (project vs inventory).
- Ensure permissions/entitlements specs correctly force server-owned operations where needed (e.g., creation gated by entitlements; rules limitations).

Output:
- Update the cross-cutting docs and ensure they are linked by dependent features.

