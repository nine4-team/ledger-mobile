# Category Type Legacy Code Removal Audit

Created: 2026-07-14

## Goal

Remove legacy budget-category taxonomy code after production data is migrated to
the canonical shape:

```ts
metadata.categoryType: "general" | "itemized" | "fee"
```

The desired end state is not long-lived compatibility with `supportedTypes`.
The desired end state is clean code and clean data.

## Removal Principle

Keep `supportedTypes` fallback only long enough to bridge the production data
migration. Once every active category has valid `metadata.categoryType` and
deployed clients no longer write `supportedTypes`, remove fallback readers,
legacy labels, compatibility denormalization, and schema prompts that mention
`supportedTypes` as behavior.

## Swift Targets

### `LedgeriOS/LedgeriOS/Models/BudgetCategory.swift`

Current legacy seams:

- `supportedTypes` stored property and `CodingKeys` entry.
- `resolvedSupportedTypes`.
- `BudgetCategoryKind.init(supportedTypes:)`.
- `BudgetCategoryDisplay.pillLabel(for supportedTypes:)`.
- `BudgetCategoryDisplay.pillColor(for supportedTypes:)`.
- Legacy display labels using `Items`, `Fee Category`, or generic fallback
  naming instead of only `General`, `Itemized`, `Fee`.

Target cleanup:

- Remove `supportedTypes` from the behavior model.
- Resolve behavior directly from `metadata.categoryType`.
- Keep only canonical labels: `General`, `Itemized`, `Fee`.
- Delete fallback tests once migration guarantees canonical data.

### `LedgeriOS/LedgeriOS/Models/Project.swift`

Current legacy seams:

- Project budget category copies still carry `supportedTypes`.
- `ProjectBudgetCategory.resolvedSupportedTypes` derives old transaction-type
  shapes.

Target cleanup:

- Decide whether project-level copies store `metadata.categoryType`, a direct
  `categoryType`, or always resolve through account-level category presets.
- Remove `supportedTypes` from project-budget display and budget summary logic
  once that decision is implemented.

### Swift Callers

Known call sites to audit/remove after model cleanup:

- `LedgeriOS/LedgeriOS/Views/Projects/ProjectsListView.swift`
- Any remaining `resolvedSupportedTypes`, `categoryKind`, `isItemsCategory`,
  `isFeeCategory`, or `isProjectCostCategory` usages.

Target cleanup:

- Callers should ask for `resolvedCategoryType` or direct
  `metadata.categoryType`, not transaction-type arrays.

## Firebase Functions Targets

### `firebase/functions/src/index.ts`

Current legacy seams:

- `BudgetCategoryType` still accepts legacy `standard`.
- `deriveCategoryTypeFromSupportedTypes`.
- `resolveSupportedTypesFromCategoryData`.
- `isItemsCategorySupportedTypes`.
- `transactionUsesItemsCategory` still reaches through supported-type helpers.
- Budget-summary category metadata includes `supportedTypes`.
- Category-change trigger still compares `supportedTypes` as a relevant field.

Target cleanup:

- Stop accepting `standard` except possibly in a one-time migration script.
- Resolve category behavior from `metadata.categoryType` directly.
- Remove all supported-type helpers from live Functions code.
- Stop writing `supportedTypes` into budget summary documents.
- Stop treating supported-type changes as behavior-changing events.

### `firebase/functions/scripts/backfill-budget-summaries.mjs`

Current legacy seams:

- Derives category type from `supportedTypes`.
- Writes summary metadata with `supportedTypes`.

Target cleanup:

- Read `metadata.categoryType` only after production category migration.
- Write summary metadata with `categoryType` only.

### Generated Files

After TypeScript cleanup, regenerate:

- `firebase/functions/lib/index.js`
- `firebase/functions/lib/index.js.map`

## MCP Targets

### `mcp-server/src/util/budget.ts`

Current legacy seams:

- `deriveCategoryTypeFromSupportedTypes`.
- `resolveSupportedTypes`.
- `categoryPillLabel` still maps through `Fee Category` / `Items` style labels.

Target cleanup:

- Resolve directly from `metadata.categoryType`.
- Remove supported-type fallback/export helpers.
- Align labels with `General`, `Itemized`, `Fee`.

### `mcp-server/src/types.ts`

Current legacy seams:

- `supportedTypes` appears on budget category shapes.

Target cleanup:

- Make `categoryType` canonical in exposed types.
- Remove `supportedTypes` from normal tool/resource outputs unless explicitly
  retained in a debug-only field.

### `mcp-server/src/resources/index.ts`

Current legacy seams:

- Resource output includes `categoryKind`.
- Resource output includes `supportedTypes`.
- Imports `resolveSupportedTypes`.

Target cleanup:

- Resource output should surface `categoryType`.
- Remove `supportedTypes` from non-debug resource output.

### `mcp-server/src/util/enums.ts`

Current legacy seams:

- `categoryKinds = ["items", "projectCost", "feeCategory", "unknown"]`.

Target cleanup:

- Use canonical category type enum: `general`, `itemized`, `fee`.
- Remove `projectCost` / `items` / `feeCategory` as category behavior names from
  agent-facing docs.

## Docs Targets

Docs may keep historical notes, but current specs should not present
`supportedTypes` as a valid product model.

Audit targets:

- `docs/specs/data-model.md`
- `docs/specs/transaction-type.md`
- `docs/specs/transaction-completeness.md`
- `docs/specs/agent-transaction-taxonomy-guide.md`
- Older taxonomy plans that predate the restoration plan.

Target cleanup:

- Current specs say `metadata.categoryType` is canonical.
- Historical docs are clearly marked superseded.

## Deletion Gate

Do not delete fallback code until:

- Production categories have valid `metadata.categoryType`.
- Production categories no longer need `supportedTypes` to resolve behavior.
- Current deployed app and MCP versions no longer write `supportedTypes`.
- Functions and summaries have been deployed/backfilled with canonical reads.
- Spot checks pass for Deni's Kitchens, Maverick gas, FedEx tariffs, ACE
  Hardware, Furnishings, Additional Requests, and Games and Entertainment.

## Completion Status

Completed: 2026-07-14

Production data migration is complete:

- All account-level budget categories have canonical
  `metadata.categoryType` values.
- No scanned category documents retain `supportedTypes`.
- No scanned category documents retain `metadata.itemizationEnabled`.
- No scanned category documents retain legacy `metadata.categoryType =
  "standard"`.
- Project-level category copies do not carry behavior fields.
- The affected Install Supplies transactions were repaired and the final audit
  found 0 affected transactions.

Runtime cleanup is complete:

- Swift category models, callers, and tests no longer read or write
  `supportedTypes`.
- Firebase Functions and the budget-summary backfill script read/write
  `metadata.categoryType` only.
- MCP tools/resources expose `categoryType` and no longer expose the old
  `categoryKind` alias layer.
- Current specs describe only `metadata.categoryType` for category behavior.

Verification completed:

- `npm run build` passed in `firebase/functions`.
- `npm run build` passed in `mcp-server`.
- `xcodebuild build -project LedgeriOS/LedgeriOS.xcodeproj -scheme LedgeriOS
  -destination "generic/platform=iOS Simulator" -derivedDataPath
  LedgeriOS/DerivedData-Codex CODE_SIGNING_ALLOWED=NO` passed.
