# Transaction Taxonomy — Migration Plan

**Spec:** [../specs/transaction-type.md](../specs/transaction-type.md)

Phased migration from the two-enum model (`Transaction.transactionType` + `BudgetCategory.metadata.categoryType`) to a single-enum model where categories reference `TransactionType` values directly via `supportedTypes: [TransactionType]`.

## Goals

- Zero data loss at every phase.
- Each phase independently shippable and revertible.
- No long-running dual-write period. A resolver normalizes both legacy transaction types AND legacy category types at read time so the app works correctly throughout.

## Status (last updated 2026-04-20)

| Phase | Status | Notes |
|---|---|---|
| Phase 1 — enum + resolver + new field (code only) | ✅ Done | Shipped; iOS + MCP + Functions all build clean. |
| Phase 2 — swap readers | ✅ Done | All display/logic sites migrated. Audit gate moved to tx-type-based (see spec §"Transaction audit gate"). `CategoryFormModal` offers 4 options (Fees / Expenses / Items / Mixed). Cloud Function `computeIsComplete` rewritten. Dual-write on category create turned off. |
| Phase 3 — backfill historical data | 🟢 Done on 1584 | **Committed 2026-04-20.** Pre-backup export at `gs://ledger-nine4-backups/pre-taxonomy-20260420-135945/` (5.25 MiB, 26 shards, SUCCESSFUL). Cloud Functions deployed ahead of backfill. Categories: 8 written with per-category overrides. Transactions: 286 updated (2 → fee, 8 → expense, 276 case-normalized to lowercase). Both scripts re-run clean (0 candidates) — idempotent. Changelog at [scripts/migration-logs/tx-1dd4fd75-8eea-4f7a-98e7-bf45b987ae94-commit-2026-04-21T00-20-11-153Z.jsonl](../../scripts/migration-logs/). Other production accounts (Ben's Biz, Assiist Biz, Ben's Bonks) not yet run — do when you're ready by re-pointing `--account` or using `--all`. |
| Phase 4 — retire legacy enum | ⚪ Not started | Cloud Functions change already shipped in Phase 3 deploy. Still to do: Script 3 (clear `metadata.categoryType`), delete `BudgetCategoryType` from Swift, remove fallback derivation, add write-path guard for `.purchase`, update seed data. |

### Verification in progress on 1584

**Where to find the migrated transactions** (confirmed via Firestore query 2026-04-20):

- **Fee badge (2 txns total):** both on project **"Hyer's Martinique Rental"**, source `1584 Design`, amounts $8,163 and $16,325.
- **Expense badge (8 txns total):**
  - Bradshaws Desert Color Rental (1) — Maverick, $85.13
  - Hyer's Martinique Rental (4) — Terrible's, Maverick, Maverick-Littlefield, Corner Mart
  - Jessop's Main Level Design (2) — Maverick, Sunset Chevron
  - Inventory (1) — Wayfair, $10.75

Any project that doesn't appear above has zero Fee or Expense transactions — seeing only "Purchase" / "Return" badges there is correct, not a bug.

Checklist:

- [ ] Hyer's Martinique Rental — two txns badge as "Fee"
- [ ] Hyer's Martinique Rental / Bradshaws / Jessop's — Fuel txns badge as "Expense"
- [ ] Inventory tab — Wayfair $10.75 txn badges as "Expense"
- [ ] Edit modal on an Expense txn — tax/subtotal fields hidden
- [ ] Category management — Install / Additional Requests / Kitchen pill shows "Mixed"
- [ ] Wizard — Mixed categories surface for both Purchase/Return AND Expense type picks
- [ ] Reports tab on Hyer's Martinique — Payable cards unchanged from pre-migration
- [ ] Budget tab — category totals + fee-received labels unchanged

### Known outstanding issues

- **Legacy `TransactionFilterOption` enum** in [SharedTransactionsList.swift:5](../../LedgeriOS/LedgeriOS/Components/SharedTransactionsList.swift) only has `purchase / sale / return` cases — missing `fee` and `expense`. **Not user-visible today**: the live filter UI uses `TransactionFilterMenu` + `TransactionFilterState` (grouped, string-based) which was updated correctly in Phase 2, and the only external caller of `applyFilter(filter:)` ([ReviewView.swift:52](../../LedgeriOS/LedgeriOS/Views/Review/ReviewView.swift)) hardcodes `.all`. Cleanup: either delete the dead enum + picker path or add `.fee` / `.expense` cases for completeness. Low priority but flagged for hygiene.

### Immediate next actions

1. **Eyeball 1584** in the app against the verification checklist above. Any regression → `node scripts/revert-transactions-to-fee-expense.mjs --account 1dd4fd75-8eea-4f7a-98e7-bf45b987ae94 --commit` (rollback window lasts until Phase 4 — once `_migrationPreviousType` is stripped, the export is the only restore path).
2. **Run Phase 3 on the other production accounts** (Ben's Biz `10fef89a…`, Assiist Biz `2d612868…`, Ben's Bonks `bb0bf594…`) when you're ready. Re-use the same scripts; if those accounts have missing-categoryType categories, write an override file per account the way 1584's was done.
3. **Phase 4 prep** — see §Phase 4 for the full list. Safe to start once you're confident in 1584.

## Phase 1 — Expand the enum, add the resolver, add the new category field (code only, no data changes)

**Scope:** add the new `TransactionType` cases, add `supportedTypes` to `BudgetCategory`, add the resolver, update the create flows to write new values going forward. No modifications to existing Firestore documents.

1. **Expand `TransactionType`** in [LedgeriOS/LedgeriOS/Models/Shared/Enums.swift](../../LedgeriOS/LedgeriOS/Models/Shared/Enums.swift). Add cases `.fee` and `.expense`. Existing cases `.purchase`, `.sale`, `.return` stay unchanged. Add a doc comment that `.purchase` now means itemized purchase only.

2. **Add `supportedTypes` to `BudgetCategory`.** Decodable — if the field is missing on a document (all legacy docs), derive it from `metadata.categoryType`:

   ```swift
   extension BudgetCategory {
       var resolvedSupportedTypes: [TransactionType] {
           if let explicit = supportedTypes, !explicit.isEmpty { return explicit }
           switch metadata?.categoryType {
           case .fee:      return [.fee]
           case .expense:  return [.expense]
           case .general:  return [.expense]
           case .itemized: return [.purchase, .return]
           case nil:       return [.purchase, .return]  // best guess for corrupted docs
           }
       }
   }
   ```

3. **Add `TransactionTaxonomy` resolver** — single named place that normalizes a stored transaction type to its intended value, given the linked category:

   ```swift
   enum TransactionTaxonomy {
       static func resolve(storedType: TransactionType, category: BudgetCategory?) -> TransactionType {
           guard storedType == .purchase else { return storedType }
           let supported = category?.resolvedSupportedTypes ?? [.purchase, .return]
           if supported == [.fee] { return .fee }
           if supported == [.expense] { return .expense }
           return .purchase  // purchases-and-returns category or unknown
       }
   }
   ```

4. **Keep `BudgetCategoryType` in the codebase for now.** Still needed to decode legacy docs. Phase 2 swaps its readers; Phase 3 backfills; Phase 4 removes it.

5. **Update `NewTransactionView.createTransaction`** to write the new `.fee` / `.expense` values directly for those flows. Purchases and Returns continue to write `.purchase` / `.return` unchanged.

6. **Update the Category-creation UI** to show the 3-option plural picker (Fees / Expenses / Purchases/Returns (items)) and write `supportedTypes` on new categories. Also continue writing `metadata.categoryType` for now so legacy readers in phase-1 code still work. (Dual-write on the category create path only. Removed in Phase 2.)

7. **MCP server** — update the `transactionType` zod enum in [mcp-server/src/util/enums.ts](../../mcp-server/src/util/enums.ts) to accept all 5 values. Add `supportedTypes` as an accepted field on category create/update tools.

**Verification:** build + existing tests pass. Manually:
- Create a Fee transaction from the wizard — stored `type == "fee"`.
- Create a new category via settings with "Fees" — stored `supportedTypes = ["fee"]` (and legacy `metadata.categoryType = "fee"`).
- Open an existing project — legacy categories still work; wizard filters categories correctly via `resolvedSupportedTypes`.
- Open an existing transaction — displays / reports correctly via the resolver.

**No existing documents change.**

## Phase 2 — Swap readers to the new model

**Audit-gate swap (tx-type based):** under the multi-type category model, a category no longer tells you whether a transaction needs tax/subtotal. Swap these reader sites to check the transaction's own type instead of the linked category:

- [ ] [EditTransactionDetailsModal.swift](../../LedgeriOS/LedgeriOS/Modals/EditTransactionDetailsModal.swift) — `isItemizedCategory` → check `transaction.transactionType == .purchase || .return`.
- [ ] [TransactionDetailView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift) — the subtotal/tax display rows.
- [ ] [TransactionNextStepsCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/TransactionNextStepsCalculations.swift) — the "Set tax rate" next-step.
- [ ] `NewTransactionView` — already tx-type-based after Phase 2 restructure. No change.

Cloud Functions' `computeIsComplete` is the server-side half of the same swap; it moves in Phase 4.


**Scope:** every site that reads `metadata.categoryType` or uses `transactionType` in a legacy-three-value way is audited and swapped. Each consumer is a separate commit.

**Transaction-type consumers:**

- [ ] `ReportAggregationCalculations.reimbursementDirection` — Sale fallback condition.
- [ ] `ReportAggregationCalculations.computeInvoiceReport` — Fee exclusion switches from `categoryType == .fee` to `transactionType == .fee` (simpler).
- [ ] `TransactionFilterMenu` filter options — add Fee / Expense filters.
- [ ] `TransactionCard` / `TransactionCardCalculations` — badge and display logic.
- [ ] `TransactionDisplayCalculations.displayName` — "Purchase from X" / "Sale to X" phrasing; add Fee / Expense display names.
- [ ] `AccountingTabView` — if it branches on type anywhere.
- [ ] Inventory operations — sale/return routing (no change expected — those read `.sale` / `.return` directly).
- [ ] `ExportFieldConfig` — CSV type column.
- [ ] MCP `list_transactions` filter, `create_transaction`, `update_transaction`.
- [ ] Unit + integration tests.

**Category-type consumers:**

- [ ] `BudgetTabCalculations.spentLabel` — currently branches on `categoryType`. Switch to deriving from the category's primary supported type.
- [ ] `NewTransactionView` — already uses `categoryTypeFilter`. Remove that step entirely (the top picker now is the transaction-type pick directly) and filter categories by `supportedTypes.contains(pickedType)`.
- [ ] `CategoryRow` display pill — reads `categoryType` for label + color. Drive from `supportedTypes` instead.
- [ ] `BudgetCategoryManagementView` — same display pill logic.
- [ ] `BudgetCategory.metadata.categoryType` writes — the category-create flow stops dual-writing after this phase.
- [ ] Unit tests on category display.

For each site: swap the read, run that site's tests, commit separately. During Phase 2, both legacy and new-model documents coexist — the resolver handles both transparently.

## Phase 3 — Backfill historical data

**Scope:** rewrite legacy fields on existing documents so they match the new model.

### Data-safety protocol (run before any `--commit`)

The 1584 Design account is the production-critical dataset. Protect it in this order:

1. **Firestore export.** Full managed export to a GCS bucket — gives a point-in-time snapshot for worst-case restore.
   ```bash
   gcloud firestore export gs://ledger-nine4-backups/pre-taxonomy-$(date +%Y%m%d-%H%M%S) \
     --project=ledger-nine4 --async
   ```
   **Backup bucket:** `gs://ledger-nine4-backups` — created 2026-04-20, US multi-region, uniform bucket-level access, **90-day auto-delete lifecycle** (edit [firebase/backup-bucket-lifecycle.json](../../firebase/backup-bucket-lifecycle.json) + `gsutil lifecycle set` to change). Each export lands in a timestamped folder like `pre-taxonomy-20260420-215700/`.

   **Permissions note:** `gcloud firestore export` requires `roles/datastore.importExportAdmin`. The `firebase-adminsdk-fbsvc@` service account does NOT have it by default and cannot grant it to itself. Either (a) run this command yourself while authenticated as a project owner, or (b) grant the role once: `gcloud projects add-iam-policy-binding ledger-nine4 --member="serviceAccount:firebase-adminsdk-fbsvc@ledger-nine4.iam.gserviceaccount.com" --role="roles/datastore.importExportAdmin" --condition=None`.

   **Restore:** `gcloud firestore import gs://ledger-nine4-backups/<folder>/ --project=ledger-nine4`.
2. **Run dry-runs first** (scripts default to dry-run). Review the distribution output and the per-doc changelog written to [scripts/migration-logs/](../../scripts/migration-logs/).
3. **Run 1584 alone before `--all`.** Use `--account <1584-id>` so at most one account is affected if something's wrong.
4. **Verify after commit** (see verification checklist below) before moving to the next account.

### Built-in safeguards

- **`_migrationPreviousType` marker.** Script 1 stashes the previous `type` value on every transaction it rewrites. Trivial rollback via [scripts/revert-transactions-to-fee-expense.mjs](../../scripts/revert-transactions-to-fee-expense.mjs) — no export needed for an in-window revert.
- **Changelog per run.** Each account's run writes a JSONL changelog to `scripts/migration-logs/` recording every doc path, old value, new value. Reviewable and machine-readable.
- **Script 2 is additive-only.** No field is cleared or overwritten; categories already carrying `supportedTypes` are skipped. There is no "undo" needed because nothing is lost.
- **Idempotent by construction.** Script 1 queries `type == "purchase"` so migrated docs drop out of subsequent runs. Script 2 skips categories that already have `supportedTypes`.
- **No `.sale` / `.return` docs touched.** Script 1 filters on `type == "purchase"` only. The 8 legacy canonical sales on 1584 (`isCanonicalInventorySale: true`, `type: "sale"`) are untouched.

### Post-commit verification checklist (run per-account)

- Open the 1584 project in the app — every transaction still renders with the expected badge.
- Invoice report totals unchanged (the resolver was already treating these docs as fee/expense at read time, so totals should match pre-migration).
- Budget Tab totals unchanged.
- Re-run both dry-runs — both should report zero candidates.
- Spot-check three categories in [BudgetCategoryManagementView](../../LedgeriOS/LedgeriOS/Views/Settings/BudgetCategoryManagementView.swift) — labels match expectations (Fee / Expense / Items).

**Script 1 — Transactions:** rewrite legacy `purchase` transactions whose linked category is a fee or expense type.

1. Write a one-off Node script in [scripts/](../../scripts/) using firebase-admin, matching the style of `scripts/dev-native.mjs`.
2. For each account, iterate transactions where `type == "purchase"`. Load the linked category. Apply the resolver. If the result differs from the stored value, write the update.
3. Dry-run first — log every candidate and count the distribution (`purchase → fee`, `purchase → expense`, `purchase → purchase`).
4. Commit the real run with 500-doc batches, per-account (`--account <id>` flag).
5. Idempotent — re-running should report zero updates on a migrated account.

**Script 2 — Categories:** populate `supportedTypes` on every category document. **Additive only** — `metadata.categoryType` is preserved. It's cleared in Phase 4 alongside the Cloud Functions migration (see below).

1. For each account, iterate budget categories.
2. Derive `supportedTypes`:
   - If the script is passed `--overrides <path-to-json>` and the category ID is in that file, use the explicit mapping from the file.
   - Else derive from `metadata.categoryType` via the mapping in the spec (including `(missing) → [purchase, return, expense]`).
3. Write `supportedTypes`. Do NOT touch `metadata.categoryType` — Cloud Functions still read it (see Phase 4).
4. Dry-run + real run + idempotent, same pattern as Script 1.

**Overrides file format** (JSON, keyed by category document ID):

```json
{
  "1aa4b56b-2ff2-4377-b5fa-f7b8650ca9c0": ["purchase", "return", "expense"],
  "b0df89f8-7610-4f10-8651-0358330e95e2": ["fee"]
}
```

Unknown IDs fall through to derivation. The 1584 overrides live at [scripts/overrides/1584-categories.json](../../scripts/overrides/1584-categories.json) and are the source of truth for that account's shapes — the metadata-derived defaults are NOT safe for categories whose legacy `categoryType` is missing or ambiguous.

**Why we don't clear `metadata.categoryType` in Phase 3:** three Cloud Functions in [firebase/functions/src/index.ts](../../firebase/functions/src/index.ts) still read the field:

- `recalculateProjectBudgetSummary` (:1002) writes it into `budgetSummary.categories[id].categoryType`, which the projects list reads for fee-vs-non-fee display.
- `computeIsComplete` (:1161) uses `categoryType == 'itemized'` to decide whether a transaction needs tax/subtotal. Clearing the field would flip every itemized transaction's `isComplete` to `true`, hiding real Needs-Review state.
- `onAccountBudgetCategoryWritten` (:1446, :1465) short-circuits on `categoryType` diff and recomputes transaction completeness.

Migrating these (plus deploying) before clearing is load-bearing.

**Verification:** after the run — no `purchase`-typed transaction links to a category with derived `supportedTypes == [fee]` or `== [expense]`. Every category has a non-empty `supportedTypes`. Resolver is a no-op in practice (the fallback derivation still matters for docs that existed before Phase 3 if the script was incomplete, and for the `.general` → `[.expense]` mapping until Phase 4).

## Phase 4 — Retire the legacy enum and lock in invariants

**Scope:** migrate Cloud Functions off `metadata.categoryType`, move the audit gate to tx-type-based, clear the legacy field, then remove `BudgetCategoryType` from the codebase.

1. **Migrate Cloud Functions** in [firebase/functions/src/index.ts](../../firebase/functions/src/index.ts). Update:
   - `recalculateProjectBudgetSummary` (:1002) — write `supportedTypes` into `BudgetSummaryCategory` instead of `categoryType`. Fallback to derivation from `metadata.categoryType` for safety.
   - `computeIsComplete` (:1161) — **retire the category-based gate entirely**. The needs-audit gate becomes `txData.type === 'purchase' || txData.type === 'return'` (case-insensitive). No category lookup. A fee or expense transaction is always auto-complete.
   - `onAccountBudgetCategoryWritten` (:1446, :1465) — trigger budget-summary recompute on `supportedTypes` change. Do NOT retrigger transaction-isComplete recompute on category-type changes (since audit no longer depends on category shape).
   - Deploy functions BEFORE running the clear script.

   **Rationale for the audit-gate change:** under the multi-type category model (see spec §"Transaction audit gate"), a single category can hold both purchase and expense transactions. Whether a specific transaction needs tax/subtotal is a property of THAT transaction, not its category. The old gate produced false negatives (expense in an items category auto-incomplete) and false positives (purchase in a mixed category skipping audit).

2. **Update `BudgetSummaryCategory` shape** on the Swift side ([ProjectsListView:161](../../LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift) reads `catData.categoryType`). Switch to reading the new `supportedTypes` field from the summary.

3. **Script 3 — Clear `metadata.categoryType`.** One-off node script (same style as Phase 3 scripts) that walks every account's budget categories and unsets `metadata.categoryType`. Runs only after functions are deployed. Dry-run + idempotent.

4. **Delete `BudgetCategoryType`** from [Enums.swift](../../LedgeriOS/LedgeriOS/Models/Shared/Enums.swift). Remove `metadata.categoryType` from the `BudgetCategory` model. Remove the legacy `categoryType` field from `BudgetProgress.CategoryProgress`. Remove any remaining references.

5. **Remove `resolvedSupportedTypes` fallback derivation.** At this point every category has `supportedTypes` explicitly set. Reads become direct field access.

6. **Write-path guard for `.purchase`.** `NewTransactionView.createTransaction` and MCP `create_transaction` / `update_transaction` reject a `.purchase` transaction whose linked category doesn't include `.purchase` in `supportedTypes`. Catches drift instead of relying on the resolver forever.

7. **Keep the `TransactionTaxonomy.resolve` function** as a safety net with a single `return storedType` body — deprecated but present in case of stragglers. Add a log line if it ever returns a non-identity result (indicates unmigrated data).

8. **Seed data** — [firebase/seed-data/bundle.json](../../firebase/seed-data/bundle.json) uses `fee` / `expense` values for fee/expense fixtures and `supportedTypes` on categories.

9. **Test factories / fixtures** — update any that still construct the old category-type field.

**Verification:** build + tests pass. Grep confirms `BudgetCategoryType` and `categoryType` are gone from the Swift codebase and Cloud Functions. New transactions cannot write into the old ambiguous state.

## Risks / Watch-outs

- **No Firestore rules change needed** for the transaction side — raw values unchanged. If we decide to enforce `supportedTypes` non-empty in rules, that's a rules change.
- **MCP backwards compat.** External callers may pass the old `categoryType` field on category creates until Phase 4. Accept both during Phases 1–3; drop the legacy name in Phase 4 or document as breaking.
- **Canonical-sales legacy model.** Sales aren't affected by this migration (raw value unchanged). Confirm no downstream code assumes `categoryType` on sale-related categories.
- **`.general` categoryType.** Derives to `supportedTypes = [.expense]`. After Phase 3 the original value is wiped. New-category UI never produces a general equivalent — it only writes `[.fee]`, `[.expense]`, or `[.purchase, .return]`.
- **Category-editing edge cases.** If a user changes a category from Expenses to Purchases/Returns mid-project after existing `.expense` transactions link to it, there's drift. Phase 4 write-path guard should refuse the change if it would orphan transactions. Phase 2 should at least warn.
- **Dual-write window.** Phase 1 writes both `supportedTypes` and `metadata.categoryType` on new categories. Phase 2 turns off the legacy write. Don't ship Phase 2 until all readers are migrated or they'll start missing data on new categories.
- **Cloud Functions still read `metadata.categoryType` through Phase 3.** They're migrated in Phase 4. Do NOT clear the field during Phase 3 — see Script 2 notes.

## Deferred

- Dropping the `.general` value in any migration-visible way beyond backfilling it as `[.expense]`.
- Changing Firestore security rules for category writes (would require server-side knowledge of `supportedTypes` structure).
- Surfacing `supportedTypes` as user-editable post-creation. For now, category type is set once at creation.
