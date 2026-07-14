# Category Type Data Migration Audit

Created: 2026-07-14

## Goal

Create a reviewed list of database records that must be updated so the app can
remove `supportedTypes` compatibility code instead of carrying legacy behavior.

Canonical target:

```ts
metadata.categoryType: "general" | "itemized" | "fee"
```

Legacy fields to remove or quarantine after migration:

- `supportedTypes`
- `metadata.itemizationEnabled`
- legacy `metadata.categoryType = "standard"`

## Scope

Primary collection:

```text
accounts/{accountId}/presets/default/budgetCategories/{budgetCategoryId}
```

Related data to recompute or verify:

- Transactions using changed `budgetCategoryId`.
- Transaction `isComplete` and audit fields.
- Budget summary/category denormalization documents.
- Project-level budget category copies if they store category behavior.

## 1584 Category Decisions

Initial reviewed targets:

| Category | Target `metadata.categoryType` | Notes |
| --- | --- | --- |
| Furnishings | `itemized` | Item rows expected. |
| Additional Requests | `itemized` | Usually furnishings/add-ons; split later only if needed. |
| Kitchen | `general` | Non-itemized project cost unless explicitly split. |
| Install Services | `general` | Labor/service cost. |
| Install Supplies | `general` | User decision: keep general. |
| Fuel | `general` | Non-itemized project cost. |
| Storage & Receiving | `general` | Non-itemized project cost. |
| Games and Entertainment | `itemized` | User correction: probably itemized. |
| Design Fee | `fee` | Business revenue/payment category. |

Do not infer category type from historical presence or absence of `itemIds`.
Use reviewed product intent.

## Dry-Run Output Required

The dry run must save machine-readable output before any production writes.

Category-level output:

```json
{
  "accountId": "...",
  "categoryId": "...",
  "name": "Kitchen",
  "currentMetadataCategoryType": null,
  "currentSupportedTypes": ["purchase", "return"],
  "hasItemizationEnabled": false,
  "proposedCategoryType": "general",
  "proposedRemoveSupportedTypes": true,
  "linkedTransactionCount": 4,
  "incompleteLinkedTransactionCount": 1,
  "reason": "reviewed category target",
  "risk": "low"
}
```

Transaction-level output for affected rows:

```json
{
  "transactionId": "...",
  "projectId": "...",
  "source": "Deni's Kitchens",
  "categoryId": "...",
  "categoryName": "Kitchen",
  "oldResolvedCategoryType": "itemized",
  "newCategoryType": "general",
  "oldIsComplete": false,
  "proposedIsComplete": true,
  "reason": "general category no longer requires item rows"
}
```

## Data Items To Identify

The audit must list every active category where any of the following is true:

- Missing `metadata.categoryType`.
- Invalid `metadata.categoryType`.
- Legacy `metadata.categoryType = "standard"`.
- Has `supportedTypes`.
- Has mixed `supportedTypes`, especially `["purchase", "return", "expense"]`.
- Has `metadata.itemizationEnabled`.
- Category name matches a reviewed override target.
- Project-level category copy has behavior fields that disagree with the
  account-level category.

The audit must also list every transaction whose completeness would change after
category migration.

## Production Write Plan

Script:

```bash
node scripts/audit-category-type-migration.mjs --account <accountId>
node scripts/audit-category-type-migration.mjs --all
```

The script is dry-run by default and writes review artifacts under:

```text
docs/plans/category-type-migration-runs/YYYY-MM-DD/
```

Production writes require an explicit commit:

```bash
node scripts/audit-category-type-migration.mjs --account <accountId> --commit
```

Deleting legacy fields requires an additional explicit flag:

```bash
node scripts/audit-category-type-migration.mjs --account <accountId> --commit --remove-legacy-fields
```

Do not run commit mode until the dry-run artifacts have been reviewed.

For each approved category:

1. Back up the full current category document.
2. Write `metadata.categoryType` to the reviewed target.
3. Remove `supportedTypes` if all deployed readers are ready.
4. Remove or ignore `metadata.itemizationEnabled`.
5. Recompute affected transaction completeness.
6. Recompute affected budget summaries.
7. Save before/after counts and spot-check notes.

## Spot Checks

Required checks after dry run and after production write:

- Deni's Kitchens / Sandra Bahama / Kitchen.
- Maverick gas / Fuel.
- FedEx tariffs / Storage & Receiving.
- ACE Hardware / Install Supplies.
- Furnishings itemized transactions that should remain audited.
- Additional Requests itemized transactions.
- Games and Entertainment itemized transactions.
- Design Fee fee/revenue transactions.

## Output Files

Dry-run artifacts should be saved under:

```text
docs/plans/category-type-migration-runs/YYYY-MM-DD/
```

Required files:

- `category-audit.json`
- `project-category-audit.json`
- `affected-transactions.json`
- `summary.md`
- `backups-manifest.json` before production writes

Production write artifacts should add:

- `write-results.json`
- `post-write-verification.md`

## Dry-Run Results

### 2026-07-14 all-account dry run

Command:

```bash
node scripts/audit-category-type-migration.mjs --all --output-dir docs/plans/category-type-migration-runs/2026-07-14-all
```

Result:

- Accounts scanned: 5.
- Categories scanned: 27.
- Categories needing canonical writes: 20.
- Categories with `supportedTypes`: 13.
- Categories with mixed `supportedTypes`: 0.
- Categories missing `metadata.categoryType`: 15.
- Categories with legacy `metadata.categoryType = "standard"`: 2.
- Categories with `metadata.itemizationEnabled`: 0.
- Project-level category copies with behavior fields: 0.
- Affected transaction rows for review: 3.

Affected transactions:

| Account | Transaction | Source | Category change | Proposed completeness |
| --- | --- | --- | --- | --- |
| 1584 Design | `12f20735-a18d-43f4-bc55-54f3fd9765be` | Lowe's | Install Supplies `itemized -> general` | `true` |
| 1584 Design | `DKJjy44hKyJnVdBOHUBw` | ACE Hardware | Install Supplies `itemized -> general` | `true` |
| 1584 Design | `z0Ie6FwUuF7Q4AHHuyqA` | Home Depot | Install Supplies `itemized -> general` | `true` |

Artifacts:

- `docs/plans/category-type-migration-runs/2026-07-14-all/category-audit.json`
- `docs/plans/category-type-migration-runs/2026-07-14-all/project-category-audit.json`
- `docs/plans/category-type-migration-runs/2026-07-14-all/affected-transactions.json`
- `docs/plans/category-type-migration-runs/2026-07-14-all/backups-manifest.json`
- `docs/plans/category-type-migration-runs/2026-07-14-all/summary.md`

### 2026-07-14 metadata commit

Command:

```bash
node scripts/audit-category-type-migration.mjs --all --commit --output-dir docs/plans/category-type-migration-runs/2026-07-14-all-commit-metadata
```

Result:

- Wrote canonical `metadata.categoryType` to 20 category documents.
- Did not remove legacy fields in this pass (`removedLegacyFields: false`).
- Left `supportedTypes` in place as a temporary release-safety field.

The three Install Supplies transactions identified by the dry run were then
repaired to match the canonical general-category behavior:

| Account | Transaction | Source | Repair |
| --- | --- | --- | --- |
| 1584 Design | `12f20735-a18d-43f4-bc55-54f3fd9765be` | Lowe's | `isComplete: true`, `audit: null` |
| 1584 Design | `DKJjy44hKyJnVdBOHUBw` | ACE Hardware | `isComplete: true`, `audit: null` |
| 1584 Design | `z0Ie6FwUuF7Q4AHHuyqA` | Home Depot | `isComplete: true`, `audit: null` |

Post-repair verification:

```bash
node scripts/audit-category-type-migration.mjs --all --output-dir docs/plans/category-type-migration-runs/2026-07-14-all-post-transaction-repair
```

Result:

- Categories scanned: 27.
- Categories missing `metadata.categoryType`: 0.
- Categories with legacy `metadata.categoryType = "standard"`: 0.
- Categories with `metadata.itemizationEnabled`: 0.
- Project-level category copies with behavior fields: 0.
- Affected transaction rows for review: 0.
- Remaining categories needing write: 13, all due to retained `supportedTypes`.

Next production step, after deployed readers are confirmed safe:

```bash
node scripts/audit-category-type-migration.mjs --all --commit --remove-legacy-fields --output-dir docs/plans/category-type-migration-runs/2026-07-14-all-remove-legacy-fields
```

### 2026-07-14 legacy field removal

Command:

```bash
node scripts/audit-category-type-migration.mjs --all --commit --remove-legacy-fields --output-dir docs/plans/category-type-migration-runs/2026-07-14-all-remove-legacy-fields
```

Result:

- Removed legacy taxonomy fields from 13 category documents.
- `removedLegacyFields: true`.
- No affected transaction rows.

Final verification command:

```bash
node scripts/audit-category-type-migration.mjs --all --output-dir docs/plans/category-type-migration-runs/2026-07-14-all-post-legacy-removal
```

Final verification result:

- Categories scanned: 27.
- Categories needing write: 0.
- Categories with `supportedTypes`: 0.
- Categories with mixed `supportedTypes`: 0.
- Categories missing `metadata.categoryType`: 0.
- Categories with legacy `metadata.categoryType = "standard"`: 0.
- Categories with `metadata.itemizationEnabled`: 0.
- Project-level category copies with behavior fields: 0.
- Affected transaction rows: 0.

## Resolved Data Decisions

- `Additional Requests`: migrated as one `itemized` category.
- `Install Supplies`: migrated as `general`.
- `Games and Entertainment`: migrated as `itemized`.
- Project-level category copies: final audit found 0 project-level category
  copies with behavior fields, so no project-copy backfill was needed.
