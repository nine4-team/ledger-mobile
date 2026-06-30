# Transaction Taxonomy Audit Run - 2026-06-29

Status: 1584 production cleanup committed and validated; Assiist playground remains dry-run only

## Commands Run

Read-only audits:

```bash
GOOGLE_APPLICATION_CREDENTIALS=/Users/benjaminmackenzie/.config/gcloud/ledger-nine4-firebase-adminsdk.json node scripts/audit-transaction-taxonomy-impact.mjs
GOOGLE_APPLICATION_CREDENTIALS=/Users/benjaminmackenzie/.config/gcloud/ledger-nine4-firebase-adminsdk.json node scripts/audit-mixed-categories.mjs
GOOGLE_APPLICATION_CREDENTIALS=/Users/benjaminmackenzie/.config/gcloud/ledger-nine4-firebase-adminsdk.json node scripts/audit-invoice-line-categories.mjs
GOOGLE_APPLICATION_CREDENTIALS=/Users/benjaminmackenzie/.config/gcloud/ledger-nine4-firebase-adminsdk.json node scripts/audit-returned-paid-item-credit-transactions.mjs
```

Dry-runs:

```bash
GOOGLE_APPLICATION_CREDENTIALS=/Users/benjaminmackenzie/.config/gcloud/ledger-nine4-firebase-adminsdk.json node scripts/migrate-transaction-taxonomy.mjs
GOOGLE_APPLICATION_CREDENTIALS=/Users/benjaminmackenzie/.config/gcloud/ledger-nine4-firebase-adminsdk.json node scripts/migrate-transaction-taxonomy.mjs --account 1dd4fd75-8eea-4f7a-98e7-bf45b987ae94
```

Production writes completed after backup:

```bash
GOOGLE_APPLICATION_CREDENTIALS=/Users/benjaminmackenzie/.config/gcloud/ledger-nine4-firebase-adminsdk.json node scripts/repair-1584-install-category-blockers.mjs --commit
GOOGLE_APPLICATION_CREDENTIALS=/Users/benjaminmackenzie/.config/gcloud/ledger-nine4-firebase-adminsdk.json node scripts/migrate-transaction-taxonomy.mjs --account 1dd4fd75-8eea-4f7a-98e7-bf45b987ae94 --commit
```

Important: after this run, migration scripts were tightened so future `--commit`
runs require `--backup <existing-backup.json>`.

## Output Files

- `scripts/migration-logs/audit-transaction-taxonomy-impact-20260629T225011Z.json`
- `scripts/migration-logs/audit-mixed-categories-20260629T225011Z.json`
- `scripts/migration-logs/audit-invoice-line-categories-20260629T225011Z.json`
- `scripts/migration-logs/audit-returned-paid-item-credit-transactions-20260629T225011Z.json`
- `scripts/migration-logs/migrate-transaction-taxonomy-dryrun-20260629T225011Z.jsonl`
- `scripts/migration-logs/migrate-transaction-taxonomy-1584-dryrun-20260629T225011Z.jsonl`
- `scripts/migration-logs/backup-created-repair-docs-20260629T230920Z.json`
- `scripts/migration-logs/backup-transaction-taxonomy-1584-candidate-docs-20260629T230920Z.json`
- `scripts/migration-logs/backup-1584-mixed-category-docs-20260629T232300Z.json`
- `scripts/migration-logs/repair-1584-install-category-blockers-commit-20260629T230701Z.jsonl`
- `scripts/migration-logs/migrate-transaction-taxonomy-1584-commit-20260629T232124Z.jsonl`
- `scripts/migration-logs/cleanup-1584-mixed-category-docs-commit-20260629T232339Z.jsonl`
- `scripts/migration-logs/migrate-transaction-taxonomy-1584-postcommit-dryrun-20260629T232153Z.jsonl`
- `scripts/migration-logs/audit-mixed-categories-post-category-cleanup-20260629T232356Z.json`
- `scripts/migration-logs/migrate-transaction-taxonomy-allaccounts-dryrun-post-category-cleanup-20260629T232356Z.jsonl`

## Audit Snapshot

Current production counts:

| Area | Count |
| --- | ---: |
| Transactions scanned | 621 |
| `expense` transactions | 15 |
| `fee` transactions | 9 |
| legacy `to inventory` transactions | 1 |
| Mixed category docs | 3 |
| Mixed transactions | 19 |
| Returned-paid synthetic credit transactions | 0 |
| Invoices scanned | 2 |
| Invoice lines scanned | 1 |
| Invoice lines missing category | 1 |

The one missing invoice-line category is in Assiist Biz playground:

- `accounts/2d612868-852e-4a80-9d02-9d10383898d4/invoices/1FA36F78-02C3-4779-AC43-2D2370F0AB5B`
- line: `CODEx E2E Manual Fee`
- amount: 123 cents

Returned-paid synthetic credit audit found zero candidates. That means there
are no existing `"Credit: returned ..."` `purchase`/`expense` rows to migrate
right now.

## Dry-Run Findings

Unscoped dry-run:

- 106 candidate transaction updates.
- 69 in 1584 Design.
- 37 in Assiist Biz playground.

The unscoped output should not be committed as-is.

Scoped 1584 dry-run:

- 65 candidate transaction updates, all in 1584 Design.

Reasons in scoped 1584 dry-run:

| Reason | Count |
| --- | ---: |
| normalize reimbursementType `"Client Owes Design Business"` | 37 |
| `expense -> purchase` | 15 |
| `fee -> paymentToBusiness` | 8 |
| remove design-fee inventory source | 6 |
| mixed category recategorize -> Furnishings | 3 |
| normalize purchasedBy `""` | 2 |
| mixed category recategorize -> Fuel | 1 |
| mixed category target already current -> Kitchen | 1 |
| mixed category needs manual target | 3 |

The three mixed-category rows still needing manual/category-shape handling:

| Source | Current Category | Proposed Issue |
| --- | --- | --- |
| Lowe's | Install | target should be Install Supplies, but no safe target exists in current category set |
| Dean Berryessa- wallpaper install | Install | target should be Install Services, but no safe target exists in current category set |
| Dean Berryessa | Install | target should be Install Services, but no safe target exists in current category set |

## Script Fixes Made

`scripts/migrate-transaction-taxonomy.mjs` was tightened after the first dry-run:

- Added `--account <accountId>` filtering.
- Made FedEx receiving routing project-aware:
  - use `Storage & Receiving` only when the project has that category,
  - otherwise fall back to `Install Services`.
- Avoided useless category rewrites when the target category ID is already the
  current category.

## Commit Readiness

1584 cleanup has been committed and validated.

Committed changes:

- Added missing 1584 categories:
  - `Install Supplies` with `supportedTypes = ["purchase", "return"]`
  - `Install Services` with `supportedTypes = ["expense"]`
- Enabled those categories on affected projects.
- Migrated 73 1584 transaction updates:
  - 37 reimbursement normalizations
  - 15 `expense -> purchase`
  - 8 `fee -> paymentToBusiness`
  - 6 design-fee source removals
  - mixed category recategorizations into Furnishings, Install Services,
    Install Supplies, Fuel, and Storage & Receiving
  - 2 blank `purchasedBy` removals
- Cleaned remaining 1584 Mixed category docs:
  - `Additional Requests -> ["purchase", "return"]`
  - `Kitchen -> ["purchase", "return"]`
  - `Install -> ["expense"]`

Validation:

- Scoped 1584 post-commit dry-run returned 0 rows.
- Mixed category audit returned 0 mixed categories and 0 mixed transactions.
- All-account dry-run still returns 37 rows, all in Assiist Biz playground.

Remaining non-production scope:

- Assiist Biz is a playground account. The 37 remaining dry-run rows are
  intentionally skipped for this production cleanup pass.
