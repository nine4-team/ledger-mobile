# Local SQLite schema (required search index; derived only)

This doc defines a local SQLite schema used **only** as a **derived, rebuildable search index**.

Because **search is a mandatory feature**, the *presence of a local search index* should be treated as **required** for Items/Transactions UX.

Important distinction:
- **Required**: having a local search index.
- **Optional**: the exact implementation details (FTS flavor, tokenization) so long as behavior matches feature specs.

## Non-negotiables

- **Firestore is canonical**. SQLite is **non-authoritative**.
- No bespoke sync-engine primitives in SQLite (no outbox, no delta cursors, no conflicts table as a baseline).
- The index must be **rebuildable** from Firestore snapshots at any time.

---

## What this index is for

Feature specs require **multi-field search** for:

- **Transactions**: “Search matches title/source/type/notes and amount-ish queries.”
  - Source: `40_features/project-transactions/feature_spec.md` and `ui/screens/TransactionsList.md`
- **Items (inventory scope)**: “Search matches description, sku, source, paymentMethod, businessInventoryLocation.”
  - Source: `40_features/business-inventory/ui/screens/BusinessInventoryItemsScopeConfig.md`

Items are a shared module across **project** and **inventory** scopes (`40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`). However, feature specs do not currently enumerate the project-scope items search fields.

TBD / needs confirmation:
- Project-scope items list search matching rules and explicit field list for search indexing.
- Whether project search requires a local index at all (feature specs do not define a project search contract yet).

---

## Schema (recommended)

Use SQLite FTS (FTS5 if available) for fast multi-field search. Exact DDL is implementation-defined; this doc specifies the logical columns.

### `items_search` (FTS)

One row per item visible in the current account.

Required identity/scoping columns (stored, not full-text indexed):

- `account_id` (TEXT)
- `project_id` (TEXT NULL) — `NULL` means Business Inventory scope
- `item_id` (TEXT) — Firestore doc id

Indexed text columns (from feature specs):

- `description` (TEXT)
- `sku` (TEXT)
- `source` (TEXT)
- `payment_method` (TEXT)
- `business_inventory_location` (TEXT)
  - Only meaningful when `project_id IS NULL` (inventory scope).

TBD (spec gap; do not invent):
- Project-scope items list search fields (feature specs do not enumerate them). If project items search should include fields beyond the inventory list set, update this schema based on an explicit spec update.

### `transactions_search` (FTS)

One row per transaction visible in the current account.

Required identity/scoping columns (stored, not full-text indexed):

- `account_id` (TEXT)
- `project_id` (TEXT NULL) — `NULL` means Business Inventory scope
- `transaction_id` (TEXT) — Firestore doc id

Indexed text columns (from feature specs):

- `title` (TEXT)
  - Derived display title (e.g., canonical title mapping for `INV_*` ids, otherwise vendor/source). The precise derivation should match the Transactions UI module logic.
- `source` (TEXT)
- `transaction_type` (TEXT)
- `notes` (TEXT)
- `amount_text` (TEXT)
  - For “amount-ish queries”: index a normalized amount string derived from `amountCents` (e.g., `"123.45"` and `"12345"`).
  - TBD: exact tokenization/formatting strategy (locale, negatives, decimals) should match UI expectations.

---

## Update strategy (from Firestore snapshots)

### Incremental updates

While the app is active, it receives Firestore snapshots via scoped listeners. On each snapshot change:

- **Added/modified doc**: upsert the corresponding FTS row for that entity
- **Removed/deleted doc**: delete the corresponding FTS row

Notes:

- Soft deletes (`deletedAt != null`) should remove rows from the search index (or mark them non-searchable).
- Derived columns like `transactions_search.title` must be recomputed whenever the source fields change.

### Rebuild strategy (required)

Rebuild must be safe and cheap enough to run when needed:

- Clear all FTS tables for the active account.
- Reindex from the current in-memory Firestore snapshot cache (or by reattaching listeners and waiting for initial snapshots).

The rebuild path must not require special server support.

