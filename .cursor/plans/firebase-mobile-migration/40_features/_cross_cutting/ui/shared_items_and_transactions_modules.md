# Shared Items + Transactions modules (canonical UI reuse + scope config contracts)

This document defines the **shared module contract** for **Items** and **Transactions** UI + domain modules used across:

- **Project scope** (within a specific project)
- **Business Inventory scope** (inventory workspace; no `projectId`)

This exists to prevent the drift failure mode in the web app (separate project vs inventory implementations).

If a feature spec references “Scope config object (contract)” or “List state + scroll restoration”, it is referring to this file.

## Non-negotiables

- **One implementation** of Items and Transactions modules. Project and Business Inventory routes are **wrappers** that pass scope config; they must not fork logic.
- Shared modules must never assume `projectId` exists; they must branch explicitly on `scope`.
- **Money fields are cents**: all persisted currency values are integer cents per `20_data/data_contracts.md` (e.g. `amountCents`, `purchasePriceCents`, `projectPriceCents`).
  - Shared modules must not persist floats/decimals.
  - Any “amount” UX wording must map to the corresponding `*Cents` field in storage.
- Shared modules must be compatible with `OFFLINE_FIRST_V2_SPEC.md`:
  - Firestore-native offline persistence is the baseline (Firestore is canonical).
  - Listener usage must be scoped/bounded (no unbounded “listen to everything”).
  - Multi-doc invariants use request-doc workflows (Cloud Function applies a transaction).

## Canonical cross-links

- **Scope switching system** (why this exists + listener lifecycle): `40_features/_cross_cutting/scope-switching-and-sync-lifecycle/feature_spec.md`
- **Shared UI semantics** (bulk actions, messaging, empty/loading/error): `40_features/_cross_cutting/ui/shared_ui_contracts.md`
- **Item entity contract**: `20_data/data_contracts.md` → `Entity: Item`
- **Transaction entity contract**: `20_data/data_contracts.md` → `Entity: Transaction`

---

## Scope config object (contract)

### Intent

Shared Items/Transactions modules receive exactly **one scope config object** so “project vs inventory” differences are expressed as:

- a small set of **capabilities** (what’s enabled)
- a small set of **fields/UI toggles** (what’s shown)
- the scope-specific **routing/query context**

…rather than ad-hoc boolean props scattered across components.

### Type (canonical shape)

```ts
export type Scope = 'project' | 'inventory'

export type ScopeConfig = {
  scope: Scope

  /**
   * Required when scope === 'project'.
   * Must be absent when scope === 'inventory' (to prevent accidental implicit assumptions).
   */
  projectId?: string

  /**
   * Small capability set used to gate behaviors.
   * Missing fields default to canonical shared-module defaults (implementation-defined).
   */
  capabilities?: {
    // Transactions
    canExportCsv?: boolean
    supportsInventoryOnlyStatusFilter?: boolean

    // Items
    canAllocateToProject?: boolean
  }

  /**
   * Small UI field toggles.
   */
  fields?: {
    showBusinessInventoryLocation?: boolean
  }
}
```

### Valid shapes (required)

- **Project scope**

```ts
const projectScopeConfig: ScopeConfig = {
  scope: 'project',
  projectId,
}
```

- **Inventory scope**

```ts
const inventoryScopeConfig: ScopeConfig = {
  scope: 'inventory',
  capabilities: {
    canExportCsv: false,
    canAllocateToProject: true,
  },
  fields: {
    showBusinessInventoryLocation: true,
  },
}
```

### Defaults (recommended; shared-module owned)

Defaults are intentionally simple:

- Transactions:
  - `canExportCsv` defaults to `false` (project wrapper enables it explicitly)
- Items:
  - `canAllocateToProject` defaults to `false` (inventory wrapper enables it explicitly)
- UI toggles:
  - `showBusinessInventoryLocation` defaults to `false` (inventory wrapper enables it)

### Evidence (web parity pointers)

- Inventory-scope capability deltas are documented in:
  - `40_features/business-inventory/ui/screens/BusinessInventoryItemsScopeConfig.md`
  - `40_features/business-inventory/ui/screens/BusinessInventoryTransactionsScopeConfig.md`
- Drift prevention motivation + invariants: `ledger/src/pages/BusinessInventory.tsx`, `ledger/src/pages/TransactionsList.tsx`, `ledger/src/pages/InventoryList.tsx`

---

## List state + scroll restoration

### Intent

List UX must be stable when the user navigates list → detail → back:

- search/filter/sort state is preserved
- scroll restoration is best-effort and **anchor-first**
- project list state does not bleed into inventory list state

This behavior is owned by the **shared list modules** (Items list and Transactions list), not by wrapper routes.

### Required keying (`listStateKey`)

Shared list modules must store state under a stable key:

- Project items: `project:${projectId}:items`
- Project transactions: `project:${projectId}:transactions`
- Inventory items: `inventory:items`
- Inventory transactions: `inventory:transactions`

### Persisted list state (minimum; required)

List state must include at least:

- **search** query string
- **active filters** (shape is list-owned; must be serializable)
- **active sort mode**

Notably:

- Selection state is **not** required to persist across navigation (recommended default: clear on leaving the list).

### Restore hint contract (required; anchor-first)

When navigating list → detail, the list module records a restore hint for its own `listStateKey`:

- preferred: `anchorId = <opened entity id>`
- optional fallback: `scrollOffset` (implementation-defined)

When returning to the list:

- attempt **anchor-first** restoration (scroll to the row for `anchorId` if it exists in the current filtered list)
- fall back to offset if anchor cannot be resolved
- clear the restore hint after the first restore attempt (avoid “sticky” restores)

### Evidence (web parity pointers)

- Transactions list:
  - URL params + state persistence: `ledger/src/pages/TransactionsList.tsx`
  - scroll restore via `restoreScrollY`: `ledger/src/pages/TransactionsList.tsx`
- Items list:
  - filtered list + next/prev navigation depends on the same state: `ledger/src/pages/InventoryList.tsx`, `ledger/src/pages/ItemDetail.tsx`
- Inventory scope state keys:
  - `bizItemSearch` / `bizTxSearch` patterns: `ledger/src/pages/BusinessInventory.tsx`

---

## Wrapper vs shared module responsibilities (anti-fork)

### Wrappers (project shell / business inventory shell) own

- Routing + route params (Expo Router)
- Constructing `ScopeConfig`
- Attaching **scope-level listeners** (via `src/data/useScopedListeners.ts`) as required by the active workspace shell

### Shared modules own

- UI behaviors within a scope (including which controls are visible/enabled based on `ScopeConfig`)
- List state persistence + restoration keyed by `listStateKey`
- Consistent action registry generation and gating (scope + permissions + entity state)

