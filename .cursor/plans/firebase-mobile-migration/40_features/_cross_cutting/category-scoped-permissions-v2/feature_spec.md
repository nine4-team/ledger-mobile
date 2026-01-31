# Category-scoped access control (Roles v2) — Feature spec (cross-cutting)

This doc defines **category-driven scoped permissions** for the React Native + Firebase migration, aligned with `OFFLINE_FIRST_V2_SPEC.md` (Firestore-native offline persistence + scoped listeners + request-doc workflows) and the canonical attribution model.

Evidence / canonical attribution sources:
- `40_features/project-items/flows/inherited_budget_category_rules.md` (stable selector: `item.inheritedBudgetCategoryId`)
- `40_features/project-transactions/feature_spec.md` (canonical `INV_*` rows: `transaction.budgetCategoryId = null`; filters/attribution are item-driven)
- `40_features/budget-and-accounting/feature_spec.md` (budget rollups and category filters must use item-driven attribution for canonical rows)

---

## 1) Definitions

### Roles
- **Admin**: account member with full read/write access across all categories and all records in account scope (subject to normal product constraints).
- **Scoped user**: account member whose access is restricted to a set of budget categories (`allowedBudgetCategoryIds`), plus a limited “own uncategorized” exception for items.

### Category scope
- **`allowedBudgetCategoryIds`**: the set of budget category IDs the scoped user is allowed to access *within an account*. This is evaluated server-side for reads and writes.
- **Item category attribution key**: `item.inheritedBudgetCategoryId` (the *effective* budget category used for attribution/filters/visibility, including inheritance rules).
  - Naming note: this intentionally maps to the transaction field `transaction.budgetCategoryId` (and the `presets/budgetCategories/{budgetCategoryId}` collection).
  - If we ever rename this for ergonomics, prefer something unambiguous like `effectiveBudgetCategoryId` rather than `budgetCategoryId` (since it is not necessarily “directly set on the item”).
- **Uncategorized item**: `item.inheritedBudgetCategoryId == null`.

### Transactions: canonical vs non-canonical
- **Non-canonical transaction**: a user-entered transaction where category attribution is transaction-driven via `transaction.budgetCategoryId`.
- **Canonical inventory transaction**: a system row whose id begins with `INV_PURCHASE_`, `INV_SALE_`, or `INV_TRANSFER_`.
  - Canonical rows are treated as `transaction.budgetCategoryId = null` **by design**.
  - Category attribution and filtering for canonical rows is **item-driven** via linked items’ `item.inheritedBudgetCategoryId` (see evidence sources above).

---

## 2) Core rules (recommended model)

### 2.1 Category options UI (pickers + filters)
- **Scoped users** only see categories in `allowedBudgetCategoryIds` in all category pickers and filters.
- **Admins** see all categories.

Note: UI gating is required for UX, but does not replace server-side enforcement (see §4).

### 2.2 Item read visibility
- If `item.inheritedBudgetCategoryId == null`:
  - **Scoped user** can read **only their own** uncategorized items (`item.createdBy == me`).
  - **Admin** can read all uncategorized items (including others’).
- If `item.inheritedBudgetCategoryId != null`:
  - **Scoped user** can read iff `item.inheritedBudgetCategoryId ∈ allowedBudgetCategoryIds`.
  - **Admin** can read all items.

### 2.3 Item writes
- **Create**:
  - **Scoped user** may create items with `item.inheritedBudgetCategoryId == null` (supporting minimal-field capture).
  - **Admin** may create items in any state.
- **Update category**:
  - **Scoped user** may set `null → allowedCategoryId` later.
  - Once `item.inheritedBudgetCategoryId` is non-null, **scoped user cannot change it across categories** (`A → B` is disallowed).
  - **Admin** may recategorize (see §3 for explicit decision).

### 2.4 Transaction read visibility
- **Non-canonical transactions**:
  - **Scoped user** can read iff `transaction.budgetCategoryId ∈ allowedBudgetCategoryIds`.
  - **Admin** can read all.
- **Canonical inventory transactions (`INV_*`)**:
  - Do **not** treat these as globally-visible “uncategorized” just because `transaction.budgetCategoryId == null`.
  - **Scoped user** may read a canonical transaction **only if** it has **at least one linked item** the user is allowed to read under the **item visibility** rules above (i.e., via `item.inheritedBudgetCategoryId` and the uncategorized ownership exception).
  - **Admin** can read all canonical transactions.

Implementation note (for intent): “linked item” refers to the items associated to the transaction in the existing model used for canonical attribution (see `40_features/project-transactions/feature_spec.md` and `40_features/budget-and-accounting/feature_spec.md`).

---

## 3) Edge cases + decisions (explicit)

### 3.1 “Null means private” does not apply symmetrically
- Canonical transactions have `budgetCategoryId == null` **by design** (`INV_*` semantics).
- Therefore: **do not** apply “`null` means private / only mine” rules to transactions the same way as items.
  - Items use `inheritedBudgetCategoryId == null` as “uncategorized item” with a restricted “only creator” read exception for scoped users.
  - Transactions use `budgetCategoryId == null` as “canonical system row”, and visibility is derived from linked items.

### 3.2 Transaction Detail behavior for scoped users (canonical rows)
For a canonical `INV_*` transaction shown to a scoped user:
- **Show only in-scope linked items** (items the user is allowed to read).
- **Hide out-of-scope linked items** entirely (no counts, no redacted placeholders).
- Totals, category chips, and budget attribution UI must follow the canonical attribution model:
  - attribution = group linked items by `item.inheritedBudgetCategoryId` (evidence: `40_features/budget-and-accounting/feature_spec.md`, `40_features/project-items/flows/inherited_budget_category_rules.md`).

### 3.3 Recategorization
- **Admin-only**: recategorization (`item.inheritedBudgetCategoryId A → B`) is admin-only in Roles v2.
- Future extension (not implemented here): an explicit capability (e.g., “canRecategorize”) could permit this for select non-admins.

### 3.4 Budget rollups + filters
- Category-based rollups and filters must use the canonical attribution model already specified:
  - non-canonical uses `transaction.budgetCategoryId`
  - canonical `INV_*` uses linked items’ `item.inheritedBudgetCategoryId`
  - Evidence: `40_features/project-transactions/feature_spec.md` and `40_features/budget-and-accounting/feature_spec.md` (and the shared rules in `40_features/project-items/flows/inherited_budget_category_rules.md`).

---

## 4) Enforcement points (Rules vs Functions vs Client)

### 4.1 Source of truth
- **Firebase Rules / server-side enforcement is the source of truth** for:
  - read access (which docs can be replicated/fetched)
  - write access (which creates/updates are accepted)
- **Client UI gating** is required for a coherent UX, but is **not sufficient**.

### 4.2 Reads and the “no large listeners” constraint
This migration prohibits subscribing to large collections; reads must be **scoped/bounded** to the active workspace context (project vs inventory) and enforced server-side.

Roles v2 must therefore be enforced in **query shape**, not “fetch everything then filter client-side”.

### 4.3 Offline implications (decision)
Decision (preferred):
- **Firestore Rules are the enforcement source of truth**, and the client must only issue **scoped queries/listeners** that can never return out-of-scope docs.
- This keeps UI behavior consistent with server visibility without relying on client-side filtering or a bespoke sync engine.

Offline implication:
- With Firestore-native offline persistence, the device may retain **previously-fetched** documents in its local cache. This spec does **not** rely on cache pruning for correctness; it relies on server-side enforcement + scoped query shapes for what can be shown/used going forward.
- If `allowedBudgetCategoryIds` changes, the client must update query/listener scopes immediately so subsequent reads reflect the new visibility set.

### 4.4 Where to enforce canonical transaction visibility
Because canonical `INV_*` visibility is **derived from linked items**, enforcement must ensure:
- a scoped user cannot read a canonical transaction unless there exists at least one in-scope linked item.

Recommended approach (no new product capability; implementation strategy only):
- Maintain a server-authoritative, queryable “visibility index” for canonical transactions keyed by category (and/or by member scope) to support **scoped queries** without large listeners.
- If an implementation chooses a different approach, it must still satisfy:
  - no “subscribe to everything”
  - no client-side filtering of unauthorized canonical transactions after downloading them

If this requires an intentional delta from current planned sync primitives, label it explicitly in the implementation doc(s), not here.

---

## 5) Data shape recommendation (schema only; no code)

Store per-member entitlements under account membership:

- `accounts/{accountId}/members/{uid}`
  - `isAdmin: boolean`
  - `allowedBudgetCategoryIds: map<budgetCategoryId, true>` (preferred) or `allowedBudgetCategoryIds: array<string>`

Recommendation:
- Prefer **map/set shape** (`{ [budgetCategoryId]: true }`) to make Firebase Rules checks efficient and deterministic.
- Keep this document strictly about **Roles v2 / scoped permissions**. Do not introduce new domain concepts beyond category-scoped visibility and the existing canonical attribution model.

