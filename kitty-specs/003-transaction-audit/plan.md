# Implementation Plan: Transaction Audit Section

**Branch**: `feat/transaction-audit` | **Date**: 2026-02-09 | **Spec**: [`kitty-specs/003-transaction-audit/spec.md`](spec.md)
**Input**: Feature specification from `kitty-specs/003-transaction-audit/spec.md`
**Research**: [`kitty-specs/002-transaction-audit/research.md`](../002-transaction-audit/research.md), [`data-model.md`](../002-transaction-audit/data-model.md)

## Summary

Implement the Transaction Audit Section (Phase 1 MVP) for the transaction detail page. The feature adds a pure calculation utility (`computeTransactionCompleteness`) that compares the sum of linked item purchase prices against the transaction's pre-tax subtotal, producing a completeness ratio and status classification. The existing `AuditSection.tsx` placeholder (already wired into the SectionList) will be replaced with a thin UI component that renders a ProgressBar with theme-aware status colors, a totals comparison, a status message, and a missing-price item count. All data is passed as props from the parent page -- no additional fetching. The calculation handles edge cases (zero subtotal, no items, missing prices, over-itemization) and works fully offline.

## Technical Context

**Language/Version**: TypeScript 5.x, React Native (Expo SDK)
**Primary Dependencies**: React Native, Expo Router, `@react-native-firebase/firestore` (data layer only -- no direct use in this feature)
**Storage**: N/A (all data computed client-side from props; Firestore data already loaded by parent page)
**Testing**: Jest (unit tests for pure calculation function, component rendering tests via React Native Testing Library)
**Target Platform**: iOS and Android via Expo
**Project Type**: Mobile (React Native / Expo)
**Performance Goals**: Audit section renders under 100ms for transactions with up to 100 linked items (SC-010)
**Constraints**: Offline-capable (FR-011, SC-007) -- no network requests; all Firestore writes fire-and-forget per offline-first rules (N/A for this read-only feature)
**Scale/Scope**: Single section on the transaction detail page; ~2 new files, ~2 modified files

## Constitution Check

Skipped (no constitution file).

## Project Structure

### Documentation (this feature)

```
kitty-specs/003-transaction-audit/
├── plan.md              # This file
├── spec.md              # Feature specification (FR-001 through FR-012)
└── tasks.md             # Phase 2 output (created by /spec-kitty.tasks)

kitty-specs/002-transaction-audit/
├── research.md          # Research decision log (D1-D12)
└── data-model.md        # Entity definitions (Transaction, Item, BudgetCategory, TransactionCompleteness)
```

### Source Code (repository root)

```
# New files
src/utils/transactionCompleteness.ts              # Pure calculation function + TypeScript types
src/utils/__tests__/transactionCompleteness.test.ts  # Unit tests for calculation logic

# Modified files
app/transactions/[id]/sections/AuditSection.tsx    # Replace placeholder with real audit UI component
app/transactions/[id]/index.tsx                    # Pass linkedItems as props to AuditSection

# Reused (read-only, no modifications)
src/components/ProgressBar.tsx                     # Visual progress indicator (supports overflow)
src/utils/budgetColors.ts                          # getBudgetProgressColor(), getOverflowColor()
src/theme/ThemeProvider.tsx                         # useTheme(), useThemeContext(), useUIKitTheme()
src/components/Card.tsx                            # Card wrapper for audit section
src/components/AppText.tsx                         # Themed text component
src/data/transactionsService.ts                    # Transaction type definition (line 16-43)
src/data/itemsService.ts                           # Item type definition (line 20-41)
src/data/budgetCategoriesService.ts                # BudgetCategory, BudgetCategoryType types (line 15-35)
```

**Structure Decision**: This feature follows the existing mobile app convention. New utility logic lives in `src/utils/` with co-located tests in `src/utils/__tests__/`. The UI component is built in-place in the existing `AuditSection.tsx` placeholder at `app/transactions/[id]/sections/`, which is already exported from `sections/index.ts` and wired into the SectionList on the detail page. No new directories are needed.

### Key Implementation Details

**New file: `src/utils/transactionCompleteness.ts`**

Types to define:
- `CompletenessStatus = 'complete' | 'near' | 'incomplete' | 'over'`
- `TransactionCompleteness` -- computed result interface with fields: `itemsNetTotal`, `itemsCount`, `itemsMissingPriceCount`, `transactionSubtotal`, `completenessRatio`, `completenessStatus`, `missingTaxData`, `inferredTax`, `varianceCents`, `variancePercent`

Pure function: `computeTransactionCompleteness(transaction, items) => TransactionCompleteness | null`
- Returns `null` when subtotal resolves to zero (FR-009) or when called with invalid inputs
- **Items total** (FR-002): `items.reduce((sum, item) => sum + (item.purchasePriceCents ?? 0), 0)` -- null/undefined/0 all contribute 0
- **Missing price count** (FR-007, D12): count of items where `purchasePriceCents` is null, undefined, or 0
- **Subtotal resolution** (FR-003, D5): `transaction.subtotalCents` (if > 0) > inferred `amountCents / (1 + taxRatePct/100)` (if both present and taxRatePct > 0) > `transaction.amountCents` (fallback)
- **Inferred tax**: when using inferred subtotal, `inferredTax = amountCents - inferredSubtotal` (rounded)
- **Missing tax data**: true when no explicit subtotal and no valid taxRatePct
- **Completeness ratio**: `itemsNetTotal / transactionSubtotal`
- **Status classification** (FR-004, D6): ratio > 1.20 = `'over'`; `|variancePercent|` <= 1 = `'complete'`; `|variancePercent|` <= 20 = `'near'`; else `'incomplete'`
- **Variance**: `varianceCents = itemsNetTotal - transactionSubtotal`; `variancePercent = (varianceCents / transactionSubtotal) * 100`
- All arithmetic in integer cents (D2) -- `Math.round()` inferred subtotal to avoid float drift

**Modified file: `app/transactions/[id]/sections/AuditSection.tsx`**

Replace the placeholder with a real component:
- Props: `{ transaction: Transaction; items: Array<{ purchasePriceCents?: number | null }> }` (items passed from parent)
- Call `computeTransactionCompleteness(transaction, items)` (memoized via `useMemo`)
- When result is `null`: render N/A state (FR-009)
- When result exists: render Card containing:
  - **Totals row** (FR-008): items total and transaction subtotal formatted as dollars, side by side
  - **ProgressBar** (FR-005, D7): `percentage = Math.min(ratio * 100, 100)`, `overflowPercentage` when ratio > 1.0, colors from `getBudgetProgressColor()` / `getOverflowColor()` (FR-012, D8)
  - **Status message** (FR-006): human-readable text with percentage (e.g., "98% complete", "Items exceed subtotal by 35%")
  - **Missing price count** (FR-007): shown when > 0 (e.g., "3 items missing prices")
- Use `useThemeContext()` for dark mode detection (`resolvedColorScheme === 'dark'`)
- Use `useTheme()` for simplified theme colors (text, textSecondary, background)

**Modified file: `app/transactions/[id]/index.tsx`**

- Update the `AuditSection` render call (line 1257) to pass `linkedItems` as a new `items` prop: `<AuditSection transaction={item} items={linkedItems} />`
- The `linkedItems` memo (line 191) already derives the correct item list from scoped items. No additional fetching needed (D9, FR-011).
- The `AuditSectionProps` type change is self-contained in `AuditSection.tsx`

**Audit section visibility (FR-001, D3)**:
- The audit section is already in the SectionList for all transactions (line 264-276 of `index.tsx`). FR-001 requires it only for itemized categories.
- Two options: (a) conditionally omit the section from the sections array, or (b) have `AuditSection` return `null` for non-itemized. The parent page already computes `itemizationEnabled` (line 239). The simplest approach: gate the section in the `sections` memo, same pattern as the `taxes` section (line 256). Wrap the audit section push with `if (itemizationEnabled)`.

**Color mapping for audit statuses**:
- `getBudgetProgressColor(percentage, isFeeCategory=false, isDark)` maps percentage to green/yellow/red. For audit: `complete` = green (low budget usage = green), `near` = yellow, `incomplete`/`over` = red.
- However, the budget color function inverts semantics (high % = red for standard categories, because high budget usage is bad). For audit, high completeness is good. We need an inverted mapping: use `isFeeCategory=true` which gives green at high %, yellow at mid, red at low. This matches audit semantics where high completeness = good.
- For overflow (ratio > 1.2): use `getOverflowColor(isDark)` for the overflow bar segment.

**Test file: `src/utils/__tests__/transactionCompleteness.test.ts`**

Unit tests covering:
- Basic completeness calculation (items sum vs subtotal)
- Subtotal resolution priority (explicit > inferred > fallback)
- Inferred subtotal math with taxRatePct
- Status classification at each threshold boundary (1%, 20%, 120%)
- Zero subtotal returns null (FR-009)
- No items returns 0% incomplete (FR-010)
- Missing price count accuracy (FR-007, D12)
- Items with null/undefined/0 purchasePriceCents handled correctly
- Over-itemization (ratio > 1.2)
- Large item counts (100 items) for performance confidence

## Complexity Tracking

*No violations to track.*
