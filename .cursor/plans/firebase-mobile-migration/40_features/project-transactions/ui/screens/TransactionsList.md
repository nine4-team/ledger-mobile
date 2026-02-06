# Screen contract: `TransactionsList` (shared module: project + business inventory scopes)

## Intent
Let a user browse transactions in the current workspace scope (project or business inventory) with fast local search/filter/sort, and reliably navigate into transaction detail and back without losing state.

Shared-module requirement:

- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`

## Inputs
- Route params:
  - `scope`: `'project' | 'inventory'`
  - `projectId` (required when `scope === 'project'`; absent when `scope === 'inventory'`)
- Persisted list state (web parity uses query params; Expo Router mobile uses a list state store):
  - `listStateKey` (required; stable per scope)
  - list controls: search/filter/sort/menu state
  - restore hint: anchor id (preferred) + optional scroll offset fallback
- Entry points:
  - Project shell → Transactions tab (`ProjectTransactionsPage` renders this) OR Business inventory shell → Transactions tab (wrapper TBD)
  - Return from `TransactionDetail` / `EditTransaction` via native back stack (Expo Router)

## Reads (local-first)
- Firestore queries (cache-first via native Firestore offline persistence):
  - `transactions` scoped by the active workspace context (project vs inventory), with additional predicates based on selected filters
  - Budget categories (to display category name for **non-canonical** transactions)
  - Optional derived: transaction completeness (needs-review vs missing items)
- Derived view models:
  - Canonical title mapping for canonical inventory sale transactions (direction-aware)
  - Optional: canonical amount display helpers (prefer `transaction.amountCents` as authoritative; canonical rows are system-owned)
- Cached metadata dependencies:
  - Budget categories (for category display and budget-category filter options)

## Writes (local-first)
- User actions generally do not mutate transaction data from the list.

System-owned canonical rows note:
- Canonical inventory sale transactions are system-owned; the list must not “self-heal” canonical amounts via client writes.
  Canonical `amountCents` is maintained by server-owned inventory invariants (request-doc workflows / Cloud Functions).

## UI structure (high level)
- Sticky controls bar:
  - Add menu: Create manually, Import invoice submenu (Wayfair/Amazon routes)
  - Sort menu
  - Filter menu (multi-view submenu)
  - Export button
  - Search field
- Transactions list:
- Preview cards with title, amount, purchased by, date, optional notes, badges (category/type + needs-review/missing-items)

## Budget category semantics (new model; required)

Source of truth:

- `00_working_docs/BUDGET_CATEGORIES_CANONICAL_TRANSACTIONS_REVISIONS.md`

Rules:

- **Non-canonical transactions**: category badge/name (if shown) comes from `transaction.budgetCategoryId`.
- **Canonical inventory sale transactions (system)** (recommended id prefix `INV_SALE__`):
  - Are category-coded (`transaction.budgetCategoryId` is populated) and direction-coded (`inventorySaleDirection` is populated).
  - Are system-owned/read-only in UI, but can be filtered/exported like any other transaction.
  - If the list displays special badges for canonical rows, it should use direction (e.g., “System: project→business”).

Implementation note:
- Canonical rows are already category-coded, so budget-category filtering does not require joining items to canonical transactions.

## User actions → behavior (the contract)
- **Open Add menu** → show actions; selecting an action closes menus.
- **Create manually** → navigate to `AddTransaction` in the current scope context.
- **Import invoice** → navigate to import screen in the current scope context (if enabled for that scope).
- **Change sort** → list reorders and state persists.
- **Change filters** → list re-filters and state persists.
- **Search** → list filters by text/amount-like match and state persists.
- **Export** → generate CSV from locally available transactions and share/save it (mobile).
  - Recommended: include a column like `inventorySaleDirection` so canonical rows are explainable in exports.
- **Open transaction**:
  - Navigating into a transaction detail records a restore hint for the current list:
    - preferred: `anchorId = <opened transactionId>`
    - optional fallback: `scrollOffset`
  - Returning restores previous list controls and performs best-effort scroll restoration (anchor-first).
- **Close menus**:
  - Clicking outside closes open menus.
  - Pressing Escape closes open menus.

## States
- Loading:
  - Show loading state while local cache is hydrating and/or initial snapshot is loading.
- Empty:
  - If no transactions match filters/search, show “No transactions found” and hint to adjust filters/search.
- Error:
  - If local DB query fails, show recoverable error state (retry).
- Offline:
  - List should remain usable offline (local-only) and clearly indicate any global “offline” status via global sync UI.
- Pending sync (local writes queued):
  - If a transaction is pending sync, the list should optionally surface a pending marker (depends on global pending UX).
- Permissions denied:
  - If user lacks access to the project, block with a permissions error.
- Quota/media blocked:
  - Not applicable on list screen (handled on form/detail).

## Media (if applicable)
- Not applicable directly; list does not manage media.

## Collaboration / realtime expectations
- While foregrounded in an active scope, list should reflect other users’ changes via **scoped listeners** on bounded queries.
- No unbounded listeners on `transactions`.

## Performance notes
- Expected dataset sizes:
  - Transactions can be large enough that list operations must be indexed and virtualized as needed.
- Required indexes (Firestore + optional derived index):
  - Firestore composite indexes to support bounded queries (projectId + sort mode + key filters).
  - Optional: if robust offline full-text search over `source`/`notes` is required, add a **derived local search index** module (index-only; Firestore remains canonical), per `OFFLINE_FIRST_V2_SPEC.md`.

## Parity evidence
- State persistence (URL params; web): Observed in `src/pages/TransactionsList.tsx` (`useSearchParams` + sync effects).
- Scroll restoration (web): Observed in `src/pages/TransactionsList.tsx` (restore via `location.state.restoreScrollY`).
- Mobile target (Expo Router): list state + scroll restoration is owned by the shared Transactions list module via `listStateKey` (see `40_features/navigation-stack-and-context-links/feature_spec.md`).
- Filters/sorts/search logic: Observed in `src/pages/TransactionsList.tsx` (`filteredTransactions` useMemo + menu UI).
- Export CSV: Observed in `src/pages/TransactionsList.tsx` (`buildTransactionsCsv`, `handleExportCsv`).
- Canonical title + totals + self-heal: Observed in `src/pages/TransactionsList.tsx` (`getCanonicalTransactionTitle`, `computeCanonicalTransactionTotal`, `updateTransaction`).
