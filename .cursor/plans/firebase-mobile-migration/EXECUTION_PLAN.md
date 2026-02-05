# Execution plan (implementation order) — Firebase Mobile Ledger

This document is the **central “what gets built when” plan** for the Firebase mobile migration.

## Start here (single entry point)

If you only read a handful of docs, read these in order:

- `README.md` (canonical navigation index for this doc set)
- `EXECUTION_PLAN.md` (this file; implementation order)
- `OFFLINE_FIRST_V2_SPEC.md` (canonical architecture constraints)
- `40_features/feature_list.md` (what we’re building)
- `40_features/_authoring/feature_speccing_workflow.md` (how to run feature work)
- `40_features/_authoring/templates/definition_of_done.md` (spec-complete criteria)
- `CHANGELOG.md` (what moved/changed in the doc set)

It answers:
- “What do I need to implement vs what is doc-only?”
- “What order should we build things in to avoid rework and drift?”

This is intentionally different from:
- `ROADMAP.md` (roadmap of the **docs** we plan to write / structure)
- `40_features/feature_list.md` (scope inventory)
- `40_features/_authoring/templates/definition_of_done.md` (spec quality controller)

---

## How to know what you need to implement

### 1) Treat acceptance criteria as the “build list”

For a given feature folder `40_features/<feature>/`:
- **Implement what is required by** `acceptance_criteria.md` (the checklist).
- Use `feature_spec.md` and `ui/screens/*.md` as the detailed behavior/contracts that explain *how* to meet acceptance.

### 2) Cross-cutting feature folders are specs, not code locations

`40_features/_cross_cutting/` contains **shared contracts/specs**. You still implement the actual systems in app code (typically under `src/` and `app/`), but you implement them **once** and reuse them everywhere.

### 3) Doc-only vs code-required (rule of thumb)

- **Doc-only**:
  - screen contracts (`ui/screens/*.md`) unless they introduce new shared primitives
  - parity evidence notes / links
- **Code-required**:
  - anything in acceptance criteria
  - anything described as “cross-cutting subsystem” (e.g., offline media lifecycle)
  - anything that affects correctness/cost/security (request-doc workflows, permissions, listener scoping, etc.)

---

## Implementation rule (source of truth)

This doc is only about **implementation order**.

Implement from:
- `40_features/<feature>/acceptance_criteria.md` (what must exist)
- `40_features/<feature>/feature_spec.md` + `ui/screens/*.md` (details/edge cases)

---

## Legacy web app parity references (read-only context)

Many specs are parity-grounded against the legacy web app. If a spec mentions “web app behavior” but does **not** include a concrete file path, use these pointers to resolve the exact source:

- **Web app repo (parity evidence only)**: `/Users/benjaminmackenzie/Dev/ledger`
- **Cross-cutting UI parity index**: `40_features/_cross_cutting/ui/README.md`
- **Canonical shared UI contracts**: `40_features/_cross_cutting/ui/shared_ui_contracts.md`
- **UI parity inventory matrix**: `40_features/_cross_cutting/ui/ui_parity_inventory_matrix.md`
- **Parity evidence workflow (examples + rules)**: `40_features/_cross_cutting/ui/shared_ui_speccing_workflow.md`
- **Alignment/gap notes**: `20_data/alignment_issues_vs_40_features.md`

If you add or clarify parity evidence while implementing, include a full web app path (and function/component when helpful) in the spec or acceptance criteria.

---

## Architectural baseline (do not fight it)

Canonical architecture source:
- `OFFLINE_FIRST_V2_SPEC.md`

Key implications for execution:
- Firestore (native RN SDK) is **canonical** with offline persistence.
- Scoped/bounded listeners are allowed; no unbounded “listen to everything”.
- Multi-doc invariant operations use **request-doc workflows** (Cloud Function applies the transaction).
- SQLite is allowed only as a **derived search index** (index-only; non-authoritative).
  - For **Ledger Mobile**, the derived search index is **required** (search is not optional).

---

## Build order (phased)

### Phase 0 — Hard guardrails + “can ship a dev client”

**Goal**: you can run the app in a native dev client and enforce “no accidental web SDK” regressions.

Prereq: relevant feature specs are “spec complete” per `40_features/_authoring/templates/definition_of_done.md`.

Implement / verify:
- Native Firebase wiring (Auth/Firestore/Functions)
- `npm run check:native-only` passes and is used routinely
- Minimal app boot with navigation shell

Primary references:
- `OFFLINE_FIRST_V2_SPEC.md`
- `30_app_skeleton/app_skeleton_spec.md`

---

### Phase 1 — Auth + account context + protected navigation

**Goal**: a user can sign in, resolve account context, and enter the app safely.

Implement:
- Auth flows + invite acceptance (as scoped by `auth-and-invitations`)
- Account membership resolution and “no access” handling

Primary references:
- `40_features/auth-and-invitations/feature_spec.md`
- `10_architecture/security_model.md`

Status:
- ✅ Done for Phase 1 scope (auth timeout, offline gating, invite flow, account context, server-owned acceptance).
- ⚠️ Deferred: Google sign-in (required for parity) is not implemented yet.

---

### Phase 2 — Cross-cutting runtime primitives (reused everywhere)

**Goal**: build the shared “platform” pieces before domain modules so features don’t implement their own versions.

Implement:
- **Scoped listener lifecycle plumbing** (attach/detach on background/resume; bounded scope IDs)
  - Source: `src/data/listenerManager.ts`, `src/data/useScopedListeners.ts`, `src/data/LISTENER_SCOPING.md`
- **Global sync UX** (connectivity banner, pending/failed surfacing, retry affordances)
  - Source: `40_features/connectivity-and-sync-status/feature_spec.md`
- **Request-doc framework** (client helper + rules + Cloud Function pattern)
  - Source: `OFFLINE_FIRST_V2_SPEC.md` (request-doc section) + feature specs that require multi-doc invariants
- **Offline media lifecycle** (local cache, placeholder states, upload queue, cleanup)
  - Source: `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`
- **Derived offline search index (SQLite/FTS; index-only, required for this product)**
  - Source: `OFFLINE_FIRST_V2_SPEC.md` (Offline “Item Search Index” module)
  - Product requirements: feature specs under `project-items/`, `business-inventory/`, and any search-heavy lists

Status:
- ✅ Complete for Phase 2 scope: shared primitives exist (listener lifecycle, global sync UX shell, request-doc framework plumbing, offline media store/queue, search-index module).
- ⚠️ Follow-ups belong to later phases:
  - Request-doc handlers beyond the starter template are implemented per-feature when multi-doc invariants are introduced.
  - Search index integration happens when the first search-heavy item lists ship (Phase 4+), using the Phase 2 module.

---

### Phase 3 — Scope switching + shared module contracts (anti-drift foundation)

**Goal**: guarantee “project vs inventory” does not fork implementations.

Implement:
- Shared Items + Transactions module shape + `ScopeConfig` contract consumption (no implicit `projectId`)
  - Source: `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`
- Scope switching + listener scoping behavior
  - Source: `40_features/_cross_cutting/scope-switching-and-sync-lifecycle/feature_spec.md`
- List state persistence keyed by scope (`listStateKey`)
  - Source: `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`
  - Source: `40_features/navigation-stack-and-context-links/feature_spec.md`

Status:
- ✅ Done for Phase 3 scope: shared Items/Transactions modules used across Projects and Inventory, `ScopeConfig` enforced (no implicit `projectId`), scope-keyed list state + restore hints, scope switching hook that detaches/activates listener scopes, real list data with scoped listeners, full project/inventory scope-switch flows tied to selection, and back-target fallback for deep links.

---

### Phase 4 — Core workspaces + shared domain modules

**Goal**: implement the core reusable modules once, then compose them in each workspace shell.

Implement (recommended order):
- Projects workspace shell
- Shared Items module (list/detail/form + bulk actions + images)
- Shared Transactions module (list/detail/form + receipts + export/share)
- Spaces module (CRUD + checklists + media)
- Business Inventory workspace shell (composes shared modules with `scope: 'inventory'`)
- Inventory operations + lineage (request-doc / server-owned invariants)

Primary references:
- `40_features/projects/…`
- `40_features/project-items/…`
- `40_features/project-transactions/…`
- `40_features/spaces/…`
- `40_features/business-inventory/…`
- `40_features/inventory-operations-and-lineage/…`

Status / known gaps (important):
Status:
- ✅ Transactions gap closed: “Add existing items” now uses a picker flow (Suggested/Project/Outside, search, select-all, duplicate grouping, conflict confirm) with parity “re-home then link” behavior.
- ✅ Spaces gap closed: “Add existing items” now supports outside items (other projects + business inventory), blocks transaction-linked items, and runs canonical pull-in operations before assigning `spaceId`.
- ✅ Phase 4 follow-up closed: shared add-item picker UI + outside-items hook + conflict dialog + move helper are now shared and used in Transactions/Spaces.
- ✅ Filter and sort menus gap closed: Items + Transactions list filter and sort menus are now implemented to spec with full menu structure using BottomSheetMenuList:
  - Items list: Filter menu with all required modes (all, bookmarked, from-inventory, to-return, returned, no-sku, no-description, no-project-price, no-image, no-transaction) and Sort menu (alphabetical, creationDate).
  - Transactions list: Filter menu with submenus for status, reimbursement, receipt, type, completeness, budget category, purchased by, and source; Sort menu with all modes (date-desc, date-asc, created-desc, created-asc, source, amount).
  - Both lists persist filter/sort state via ListStateStore and display active filter/sort indicators in the control bar.
- ⚠️ Follow-up (optional): consider moving the transaction “re-home then link” logic (when adding an outside item to a transaction: update `item.projectId` / clear `spaceId` as needed, then set `item.transactionId`) into the canonical inventory-ops request-doc flows—but only after those server-owned invariants explicitly cover transaction linking/unlinking rules (conflict reassignment, canonical vs non-canonical behavior, `inheritedBudgetCategoryId`).

---

### Phase 5 — Secondary modules + outputs

Implement:
- Budget + accounting rollups
- Reports + share/print surfaces
- Invoice import

Primary references:
- `40_features/budget-and-accounting/…`
- `40_features/reports-and-printing/…`
- `40_features/invoice-import/…`

---

### Phase 6 — Migration tooling + verification + ops

Implement:
- Migration scripts/runbook + verification checklist
- Emulator + 2-device test plan (offline + queued writes + media + request-doc)
- Observability + cost guardrails (listener counts, reads/writes, storage egress, crash-free)

Primary references:
- `50_migration/README.md` (and planned docs under `50_migration/` per `ROADMAP.md`)
- `60_testing/README.md` (and planned `test_plan.md`)
- `70_ops/observability_and_cost_guardrails.md`

---

## “What’s missing?” quick test

If you’re unsure whether something needs implementation, ask:
- Is it in any feature’s `acceptance_criteria.md`? If yes: implement.
- Is it a cross-cutting subsystem needed by 2+ features (media, request-doc, list state, scope config)? If yes: implement once, early.
- Is it only parity evidence or authoring scaffolding? If yes: doc-only.

