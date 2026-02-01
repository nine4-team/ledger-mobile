# Scope switching + sync lifecycle (Project ↔ Business Inventory) — Feature spec (cross-cutting)

This doc consolidates the **cross-cutting scope model** used to prevent “two codepaths” drift between:
- **Project workspace** (project-scoped Items/Transactions)
- **Business Inventory workspace** (inventory-scoped Items/Transactions)

It defines how shared UI modules (Items + Transactions) change behavior by **scope configuration** without forking, and how “sync”/listener lifecycles behave when the user switches scope or the app backgrounds/resumes.

---

## Intent / problem statement

In the current web app, we have separate implementations for “project” vs “business inventory” items/transactions. Over time, those implementations drift: a fix ships in one place but not the other.

**The scope switching system exists to prevent that drift** by making “project vs inventory” a configuration and data-path difference, not a duplicated implementation difference.

---

## Compatibility constraints (must obey)

- Must remain compatible with `OFFLINE_FIRST_V2_SPEC.md` (repo canonical):
  - Firestore-native offline persistence is the baseline (“Magic Notebook”; Firestore is canonical).
  - Scoped/bounded listeners are allowed; no “listen to everything”.
  - Multi-doc invariant correctness uses request-doc workflows.
- This spec is **not** a bespoke “sync engine” doc. Any older docs that describe “outbox/delta sync/change-signal” are historical reference unless reaffirmed by `OFFLINE_FIRST_V2_SPEC.md`.

---

## Definitions

### Scope

- **Project scope**: the active workspace is a specific project (`projectId` is required).
- **Inventory scope**: the active workspace is Business Inventory (no `projectId`).

### Shared modules (non-negotiable)

**Items** and **Transactions** must be implemented as shared domain modules + shared UI primitives reused across scopes.

Source of truth:
- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`

---

## Core invariants (hard requirements)

### 1) One implementation; scope drives behavior

- There must not be separate “ProjectTransactionsList” vs “BusinessInventoryTransactionsList” logic forks.
- Scope differences must be expressed through:
  - A **single scope config object** (see below)
  - Scope-specific collection paths / queries
  - Capability gating and permissions checks

### 2) No implicit `projectId` assumptions

Shared modules must never assume `projectId` exists. They must branch explicitly on `scope`.

### 3) Scope switching is explicit and centralized

Project shells and Business Inventory shells own:
- Routing
- Route params
- Creating the scope config object

Shared modules own:
- UI behavior within a scope
- List state persistence/restoration keyed by scope
- Rendering/gating from the scope config + permissions

---

## Scope config object (contract)

The **single scope config object** is the key drift-prevention primitive. Shared UI modules consume exactly one object rather than a forest of ad-hoc booleans.

Canonical contract + examples:
- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md` (section: “Scope config object (contract)”)

Inventory screen contracts that must align to the same contract:
- `40_features/business-inventory/ui/screens/BusinessInventoryItemsScopeConfig.md`
- `40_features/business-inventory/ui/screens/BusinessInventoryTransactionsScopeConfig.md`

Project entrypoint specs that must reuse the same shared modules:
- `40_features/project-items/feature_spec.md`
- `40_features/project-transactions/feature_spec.md`

---

## Listener scoping + lifecycle (runtime “sync” behavior)

### Goal

Bound realtime updates and prevent listener leaks by scoping listeners to the active workspace and detaching them when:
- the scope changes (project switch, leaving BI)
- the app backgrounds
- the owning screen unmounts

### Source of truth

Implementation + conventions:
- `src/data/LISTENER_SCOPING.md`
- `src/data/listenerManager.ts` (`ScopedListenerManager`)
- `src/data/useScopedListeners.ts` (`useScopedListeners`, `useScopedListenersMultiple`)

### Required rules

- **Maximum 1–2 active scopes at a time** (avoid unbounded listener growth).
- **Detach scopes when navigating away** (do not accumulate).
- **Never create unbounded “global” listeners** (no `global:*`, no “all projects”).

### Recommended scope IDs

Use stable string IDs (examples; exact names are implementation-defined but must be consistent):
- `project:${projectId}`
- `inventory` (or `inventory:main`)
- `account:${accountId}` only for small, bounded metadata (membership, flags), not entity lists

---

## Navigation + list UI state: scope-keyed (prevent UX drift)

Long list screens (Items list, Transactions list) must persist and restore UI state keyed by a stable scope-aware key, so:
- project list state doesn’t bleed into inventory list state (and vice versa)
- shared list modules implement persistence once

Canonical rules + examples:
- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md` (section: “List state + scroll restoration”)

Navigation source of truth:
- `40_features/navigation-stack-and-context-links/feature_spec.md`

---

## Scope switching flows (behavioral contract)

### A) Project → Project (user selects a different project)

Requirements:
- Detach listeners for `project:${oldProjectId}`.
- Attach listeners for `project:${newProjectId}`.
- Shared modules receive a new `ScopeConfig` with `scope: 'project'` and the new `projectId`.
- List modules use `listStateKey = project:${newProjectId}:items|transactions` (no reuse of old keys).

### B) Project → Inventory (user enters Business Inventory)

Requirements:
- Detach listeners for `project:${projectId}`.
- Attach listeners for `inventory`.
- Shared modules receive `ScopeConfig` with `scope: 'inventory'`.
- List modules use `listStateKey = inventory:items|transactions`.

### C) Inventory → Project (user leaves BI / returns to project work)

Requirements:
- Detach listeners for `inventory`.
- Attach listeners for the active project scope (if one is selected), otherwise none.

### D) Foreground → Background → Foreground

Requirements (must match listener manager behavior):
- On background: minimize realtime work by detaching active scope listeners.
- On resume: reattach active scope listeners and allow Firestore-native cache reconciliation to converge the UI.

---

## Acceptance criteria (implementation-ready)

- Shared Items/Transactions UI is implemented once and used in both contexts:
  - Project entrypoints compose it with `ScopeConfig(scope='project', projectId=...)`.
  - Business Inventory entrypoints compose it with `ScopeConfig(scope='inventory')`.
- No duplicated project-vs-inventory list/menu/detail logic exists outside the wrappers.
- Listener behavior:
  - At most 1–2 scopes are active at a time.
  - Listeners detach on background and scope change.
  - Listener scope IDs follow the conventions in `src/data/LISTENER_SCOPING.md`.
- List state behavior:
  - Each list screen uses a stable scope-keyed `listStateKey`.
  - Switching scope does not carry over filters/sorts/search between project and inventory unless explicitly designed.

---

## Related specs (cross-links)

- Offline-first architecture baseline: `OFFLINE_FIRST_V2_SPEC.md`
- Connectivity + sync status UX: `40_features/connectivity-and-sync-status/feature_spec.md`
- Business inventory feature: `40_features/business-inventory/feature_spec.md`
- Shared Items/Transactions modules (canonical): `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`

