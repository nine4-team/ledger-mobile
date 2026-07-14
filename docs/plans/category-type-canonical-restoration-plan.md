# Category Type Canonical Restoration Plan

Created: 2026-07-02

## Purpose

Restore the budget-category taxonomy to the spec-aligned model:

- One canonical budget category behavior field.
- Itemization is a category property.
- Transaction type does not determine itemization.
- `supportedTypes` is not the user-facing or product-facing category model.

This plan exists because the app is currently half-migrated: some code reads
`metadata.categoryType`, some code reads/writes `supportedTypes`, and category
create/edit paths can clear the canonical field. That drift caused categories
such as Kitchen to behave like item categories and caused non-itemized
transactions to be flagged incomplete.

Primary bug to fix:

```text
Current code often lets supportedTypes override metadata.categoryType.
Spec-aligned behavior must let metadata.categoryType win.
```

Concrete examples in current code:

- Swift `BudgetCategory.resolvedSupportedTypes` returns explicit
  `supportedTypes` before `metadata.categoryType`.
- Firebase Functions `resolveSupportedTypesFromCategoryData` does the same, so
  a dirty `supportedTypes = ["purchase", "return"]` can override
  `metadata.categoryType = "general"`.
- MCP `resolveSupportedTypes` also prefers `supportedTypes`.

The corrective implementation should focus on resolving category behavior first
from `metadata.categoryType`, then deriving any compatibility/debug shape from
that behavior.

## Supersedes

This plan intentionally supersedes the parts of earlier taxonomy migration docs
that made `supportedTypes` the target product model, especially the paused Phase
4 direction in `docs/plans/transaction-type-migration.md`.

The old plan correctly identified that clearing `metadata.categoryType` was not
safe while routing/completeness still depended on category itemization. This
restoration plan takes the stronger position: `metadata.categoryType` remains
the canonical product model unless a new explicit scalar is separately approved.

## Canonical Model

Budget category documents live at:

```text
accounts/{accountId}/presets/default/budgetCategories/{budgetCategoryId}
```

Canonical field:

```ts
metadata.categoryType: "general" | "itemized" | "fee"
```

Meanings:

| Value | Product meaning | Behavior |
| --- | --- | --- |
| `general` | Normal project cost category | Purchases/services/labor/fuel/storage/etc. No item rows required. |
| `itemized` | Item-tracked category | Item rows allowed/expected. Drives item entry, subtotal/tax audit, and inventory routing eligibility. |
| `fee` | Business revenue/payment category | Used for client payments/design fees. Not itemized project spend. |

Rules:

- A category has exactly one category type.
- A category cannot be both `fee` and `itemized`.
- A category cannot be both `general` and `itemized`.
- `purchase` can be itemized or non-itemized based on the selected category.
- Completeness checks must only enforce item rows/subtotal-tax audit for
  `metadata.categoryType == "itemized"`.
- `metadata.itemizationEnabled` is legacy import data only.
- `supportedTypes` is temporary compatibility/migration data only. The product
  direction is to update production data into the canonical shape, then remove
  compatibility code instead of keeping patchwork legacy paths indefinitely.

## Superseded Model

Do not use this as the product model:

```ts
supportedTypes: ["expense"]
supportedTypes: ["purchase", "return"]
supportedTypes: ["fee"]
```

Those values can be used temporarily as read fallback for dirty data, but they
must not be exposed to users as category type semantics and must not be the
primary write target. They should be deleted or ignored after the production
data migration verifies every active category has `metadata.categoryType`.

Mixed shapes are invalid as a normal product path:

```ts
supportedTypes: ["purchase", "return", "expense"]
```

## Field Precedence During Cleanup

Temporary read precedence during migration:

1. If `metadata.categoryType` is present and valid, use it.
2. Else derive from `supportedTypes` for compatibility:
   - `["purchase", "return"]` -> `itemized`
   - `["expense"]` -> `general`
   - `["fee"]` -> `fee`
3. Else derive from explicit account/category migration overrides.
4. Else default to `general`, except historical Furnishings-style item
   categories must be handled by override, not guessed from transaction shape.

Legacy value handling:

- Decode legacy `standard` as `general`.
- Do not write new `standard` values.
- Remove server seeding behavior that normalizes `general` to `standard`.

After data cleanup, read paths should rely on `metadata.categoryType` directly.

## Known 1584 Category Targets

From the Q2 audit and current product intent:

| Category | Target `metadata.categoryType` |
| --- | --- |
| Furnishings | `itemized` |
| Additional Requests | `itemized` unless explicitly split/reviewed |
| Kitchen | `general` |
| Install Services | `general` |
| Install Supplies | `general` |
| Fuel | `general` |
| Storage & Receiving | `general` |
| Games and Entertainment | `itemized` unless explicitly reviewed otherwise |
| Design Fee | `fee` |

Important: Do not infer itemized status from whether historical transactions have
`itemIds`. Missing `itemIds` is not proof of non-itemized status, and present
`itemIds` may indicate a transaction that needs category repair.

This table intentionally contradicts older `scripts/overrides/1584-categories.json`
mixed-category overrides. Those overrides came from the `supportedTypes` migration
era and must be re-reviewed under the canonical category-type model.

For Kitchen, Install, Additional Requests, Games and Entertainment, and Install
Supplies, migration uses the reviewed target table above unless the dry run
finds category-specific evidence that needs human review. If review is needed,
choose one action per category:

- Set the whole category to `general`.
- Set the whole category to `itemized`.
- Split historical transactions into new category IDs before applying canonical
  category types.

Do not carry forward mixed `purchase + return + expense` behavior as the answer.

## Implementation Phases

### Phase 0 - Freeze Taxonomy Writes

Goal: stop creating worse data while cleanup is in progress.

Tasks:

- Identify every code path that creates or updates budget categories.
- Confirm whether production app versions can still write `supportedTypes`.
- Decide whether to hotfix category edit/create first or complete all phases in
  one release.
- Confirm whether MCP has any category create/update mutation tools. Current
  code appears to expose category readers/project allocation edits, not account
  category mutation tools.

Acceptance:

- We have a complete write-path list.
- No migration script runs until this list is understood.

Known write/seed/migration surfaces to inventory:

| Surface | Current risk |
| --- | --- |
| `LedgeriOS/LedgeriOS/Components/Modals/CategoryFormModal.swift` | UI currently returns/edits supported types. |
| `LedgeriOS/LedgeriOS/Views/Settings/BudgetCategoryManagementView.swift` | Creates categories with `metadata.categoryType = nil` and writes `supportedTypes`. |
| `LedgeriOS/LedgeriOS/Views/Creation/NewProjectView.swift` | On-the-fly category creation writes non-canonical state. |
| `LedgeriOS/LedgeriOS/Modals/EditProjectModal.swift` | On-the-fly category creation writes non-canonical state. |
| `firebase/functions/src/index.ts` account seeding | Normalizes/writes legacy `standard`; must write canonical `general`. |
| Migration scripts and overrides | May still encode mixed supportedTypes-era decisions. |
| MCP tools | Confirm no account category create/update tool exists; fix readers/validators regardless. |

### Phase 1 - Restore Swift Canonical Reads

Goal: every Swift behavior check asks for category type, not raw
`supportedTypes`.

Tasks:

- Add a single resolver, for example:

```swift
var resolvedCategoryType: BudgetCategoryType
```

- Resolver uses temporary migration precedence:
  `metadata.categoryType` first, `supportedTypes` fallback second.
- Derive compatibility `resolvedSupportedTypes` from `resolvedCategoryType`
  only where old callers still need it during transition.
- Replace direct `categoryKind`, `resolvedSupportedTypes`, and
  `supportedTypes` behavior checks with `resolvedCategoryType` where the logic
  means fee/general/itemized.
- Keep display labels simple and spec-aligned:
  - General
  - Itemized
  - Fee

Acceptance:

- Item entry, inventory routing, tax/subtotal visibility, budget display, invoice
  eligibility, and transaction cards all use the same category behavior source.
- No user-facing UI explains or exposes `["expense"]`.

Likely files:

- `LedgeriOS/LedgeriOS/Models/BudgetCategory.swift`
- `LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift`
- `LedgeriOS/LedgeriOS/Modals/EditTransactionDetailsModal.swift`
- `LedgeriOS/LedgeriOS/Logic/TransactionNextStepsCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/BillingSummaryCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/InvoiceLineCalculations.swift`
- `LedgeriOS/LedgeriOS/Logic/BudgetTabCalculations.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift`
- `LedgeriOS/LedgeriOS/Components/CategoryRow.swift`

### Phase 2 - Restore Swift Canonical Writes

Goal: category create/edit writes the canonical scalar.

Tasks:

- Change category forms to return `BudgetCategoryType`, not `[TransactionType]`.
- Create category:
  - write `metadata.categoryType`
  - write `metadata.excludeFromOverallBudget`
  - do not clear `metadata.categoryType`
- Update category:
  - write `metadata.categoryType`
  - write `metadata.excludeFromOverallBudget`
  - do not write `supportedTypes`; delete it when the migration/deployed-reader
    sequence allows, and never use it as the primary write.
- If editing category type is allowed for categories with existing transactions,
  show a warning because it changes itemization/revenue semantics.

Acceptance:

- New categories persist exactly one canonical category type.
- Editing a category cannot create a mixed or missing taxonomy state.
- Existing categories with `metadata.categoryType` keep it unless the user
  deliberately changes it.

### Phase 3 - Restore Firebase Function Canonical Reads

Goal: server-side recomputation matches app behavior.

Tasks:

- Keep the category-driven completeness behavior, but fix resolver precedence:
  `metadata.categoryType` must win over dirty `supportedTypes`.
- Keep temporary `supportedTypes` fallback only for dirty data during migration.
- Ensure category writes trigger recomputation when `metadata.categoryType`
  changes.
- Ensure non-itemized categories are complete when required transaction-level
  fields are present; they must not require item rows or subtotal/tax audit.
- Remove seeding normalization that writes `standard`; write `general`.
- Remove `supportedTypes` from denormalized summary shapes once deployed readers
  no longer need it.
- Define the final budget-summary category shape, then update both the live
  trigger and backfill script consistently. Summaries currently have mixed
  `categoryType`/`supportedTypes` behavior across trigger, backfill, and Swift
  readers.

Acceptance:

- General categories do not produce incomplete flags for missing item rows.
- Itemized categories still produce incomplete flags when item audit data is
  genuinely incomplete.
- Category type changes recompute affected transactions.
- A conflict shaped like `metadata.categoryType = "general"` plus
  `supportedTypes = ["purchase", "return"]` resolves as general.
- Account seeding writes `metadata.categoryType = "general"`, not `standard`.

Likely files:

- `firebase/functions/src/index.ts`
- `firebase/functions/scripts/backfill-budget-summaries.mjs`
- generated `firebase/functions/lib/*` after build.

### Phase 4 - Restore MCP / Agent Canonical Reads And Writes

Goal: agent tools speak the same product language as the app.

Tasks:

- Budget category resources and tools should surface `categoryType` as the
  primary behavior.
- If `categoryKind` remains as an app-facing convenience, it must be derived
  from `metadata.categoryType`, not from `supportedTypes`.
- If category create/update tools are added or found, they should accept/write
  `categoryType`.
- Raw `supportedTypes` can be exposed only as debug/compatibility metadata.
- Tool docs should tell agents:
  - use `purchase` for money spent
  - use category type to determine itemization
  - never create mixed category shapes
- Update MCP schema/help surfaces so agents stop treating `supportedTypes` or
  supportedTypes-derived `categoryKind` as canonical. Include server info,
  schema descriptions, enum descriptions, and transaction-tool guidance.

Acceptance:

- MCP cannot create `supportedTypes = ["purchase", "return", "expense"]`.
- MCP cannot make Kitchen/Fuel/Install Services itemized unless explicitly told
  to set `categoryType = "itemized"`.
- MCP validators resolve `metadata.categoryType = "general"` plus dirty
  item-looking `supportedTypes` as general.

Likely files:

- `mcp-server/src/types.ts`
- `mcp-server/src/util/budget.ts`
- `mcp-server/src/util/enums.ts`
- `mcp-server/src/tools/budget.ts`
- `mcp-server/src/tools/transactions.ts`
- `mcp-server/src/resources/index.ts`
- `mcp-server/src/tools/server-info.ts`
- schema/enum description surfaces returned to agents.

### Phase 5 - Data Audit Dry Run

Goal: produce a reviewed migration plan before touching production data.

Dry-run output per account/category:

```json
{
  "accountId": "...",
  "categoryId": "...",
  "name": "Kitchen",
  "currentMetadataCategoryType": null,
  "currentSupportedTypes": ["purchase", "return"],
  "proposedCategoryType": "general",
  "reason": "1584 override / Q2 audit",
  "linkedTransactionCount": 4,
  "itemizedLinkedTransactionCount": 0,
  "risk": "low"
}
```

Dry-run output per affected transaction:

```json
{
  "transactionId": "...",
  "source": "Deni's Kitchens",
  "project": "Sandra- BAHAMA Unit",
  "categoryName": "Kitchen",
  "oldCategoryType": "itemized/fallback",
  "newCategoryType": "general",
  "oldIsComplete": false,
  "proposedIsComplete": true
}
```

Acceptance:

- Dry run includes before/after counts by account:
  - categories missing `metadata.categoryType`
  - categories with invalid/mixed `supportedTypes`
  - incomplete transactions by category type
  - transactions whose completeness would change
- 1584 category overrides are explicit and reviewed.
- No production writes occur in dry run.

### Phase 6 - Production Data Migration

Goal: backfill canonical category data and repair affected transaction
completeness.

Tasks:

- Back up category documents targeted by the migration.
- Write `metadata.categoryType` to every account-level category.
- Delete `supportedTypes` from active category documents after all deployed
  readers ignore it. If deletion must be delayed for release sequencing, record
  the exact delayed-removal reason and treat the field as inert legacy data.
- Recompute `isComplete` for transactions linked to changed categories.
- Recompute budget summaries where category metadata is denormalized.

Acceptance:

- Every active account-level category has valid `metadata.categoryType`.
- No active category has mixed behavior.
- Kitchen in Sandra Bahama is `general`.
- Remaining incomplete transactions are only genuine itemized/audit issues or
  genuinely missing required transaction-level fields.

### Phase 7 - Remove Compatibility Fallback

Goal: make the system simple again after production is clean.

Prerequisites:

- Current App Store/TestFlight version no longer writes `supportedTypes`.
- Firebase Functions deployed with canonical reads.
- MCP deployed with canonical reads/writes.
- Production categories have valid `metadata.categoryType`.
- Production migration has removed or explicitly quarantined `supportedTypes`.

Tasks:

- Remove fallback from `supportedTypes` in app behavior code.
- Remove `supportedTypes` from the app/server/MCP data model unless a specific
  debug/export use is explicitly approved.
- Remove stale docs that present `supportedTypes` as the product model.
- Keep migration notes documenting the historical field.

Acceptance:

- `rg "supportedTypes"` only finds compatibility docs, migration scripts, or
  intentionally retained debug fields.
- New category creation cannot persist ambiguous or mixed taxonomy data.

## Test Plan

Swift tests:

- Category resolver:
  - `metadata.categoryType = general` -> general
  - `metadata.categoryType = itemized` -> itemized
  - `metadata.categoryType = fee` -> fee
  - missing metadata with `supportedTypes = ["expense"]` -> general fallback
  - missing metadata with `supportedTypes = ["purchase", "return"]` -> itemized
    fallback
  - mixed `supportedTypes` -> invalid/unknown requiring migration, not normal UI
  - `metadata.categoryType = general` with
    `supportedTypes = ["purchase", "return"]` -> general
- New transaction flow:
  - purchase + general category skips item entry and tax/subtotal audit
  - purchase + itemized category enables item entry and audit
  - payment/client payment uses fee category only
- Category editor:
  - create writes `metadata.categoryType`
  - update writes `metadata.categoryType`
  - update does not clear existing category type

Firebase Functions tests:

- `computeIsComplete` returns complete for general category purchases that have
  required transaction-level fields.
- `computeIsComplete` still catches incomplete itemized transactions.
- Category type change recomputes linked transactions.
- Conflict precedence: `metadata.categoryType = "general"` plus
  `supportedTypes = ["purchase", "return"]` resolves as general.
- Seeded default categories write `general`, `itemized`, and `fee`, never new
  `standard`.

MCP tests:

- If category mutation tools exist, create category writes
  `metadata.categoryType` and create/update rejects mixed category behavior.
- Transaction creation routes itemization from category type, not transaction
  type.
- Conflict precedence matches Swift and Functions.

Production verification:

- Before/after category taxonomy counts.
- Before/after incomplete transaction counts.
- Spot checks:
  - Deni's Kitchens / Sandra Bahama / Kitchen
  - Maverick gas / Fuel
  - FedEx tariffs / Storage & Receiving
  - ACE Hardware / Install Supplies
  - Furnishings itemized transactions that should still be audited

## Rollback Plan

Code rollback:

- Revert app/functions/MCP commits if the deployed behavior is wrong.
- Keep migration scripts idempotent and dry-run capable.

Data rollback:

- Store pre-migration snapshots for every changed category:
  - full category document
  - affected transaction `isComplete` values
  - affected budget summary snippets
- If rollback is needed, restore snapshots in reverse order:
  1. category docs
  2. transaction completeness
  3. budget summaries

Do not rollback unrelated user data or unrelated transaction edits.

## Open Decisions

1. Should `metadata.categoryType` use `general` only, or keep accepting legacy
   `standard` as decode-only alias?
2. Should Additional Requests be split into separate general/itemized categories
   before the canonical migration?
3. Do project-level category copies need `metadata.categoryType`, or should all
   itemization reads resolve through account-level category presets?

## Linked Cleanup Audits

- `docs/plans/category-type-legacy-code-removal-audit.md` tracks the code paths
  that still mention or depend on legacy taxonomy fields and should be removed
  after the data migration.
- `docs/plans/category-type-data-migration-audit.md` tracks the database fields,
  category decisions, dry-run outputs, and production data updates needed before
  compatibility code can be deleted.
