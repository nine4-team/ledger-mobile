# Research Decision Log

## Summary

- **Feature**: 002-transaction-audit
- **Date**: 2026-02-09
- **Researchers**: Claude (automated analysis of legacy web app + mobile codebase)
- **Open Questions**: See [Next Actions](#next-actions)

## Decisions & Rationale

| # | Decision | Rationale | Evidence | Status |
|---|----------|-----------|----------|--------|
| D1 | Reuse existing `AuditSection.tsx` placeholder — do not create new files | Placeholder already exists at `app/transactions/[id]/sections/AuditSection.tsx`, is wired into the SectionList, exported from `index.ts`, and has collapsible state configured. Building in-place avoids integration overhead. | E1, E6 | final |
| D2 | Use `cents`-based arithmetic (no string parsing) | Mobile codebase stores monetary values as `number \| null` (e.g., `amountCents`, `subtotalCents`, `purchasePriceCents`). Legacy web app stores as strings and parses with `parseFloat()`. The mobile convention avoids float-parsing bugs. | E2, E3 | final |
| D3 | Determine itemization via `categoryType === 'itemized'` on `BudgetCategory.metadata` | Mobile codebase already uses this pattern on the transaction detail page (line 239 of `index.tsx`). Legacy uses `getItemizationEnabled()` which checks `metadata.itemizationEnabled` — the mobile schema replaced this with a typed `categoryType` enum (`'general' \| 'itemized' \| 'fee'`). | E4, E5 | final |
| D4 | Resolve linked items from `transaction.itemIds` + `itemsService` queries | Legacy web app uses `inventoryService.getItemsForTransaction()` plus lineage edge resolution. Mobile has `transaction.itemIds` array and `listItemsByProject()`. For MVP, resolve items by IDs from the items already loaded on the detail page. Lineage edge resolution is deferred to Phase 3. | E2, E7 | final |
| D5 | Subtotal resolution: explicit subtotalCents > inferred from taxRatePct > fallback to amountCents | Matches legacy precedence order exactly. Mobile has `subtotalCents` and `taxRatePct` directly on the Transaction type. No need for tax preset lookup — mobile stores resolved `taxRatePct` directly. | E3, E8 | final |
| D6 | Completeness status tiers: 1% / 20% / 120% thresholds (from legacy) | Legacy uses: complete (within ±1%), near (1-20% variance), incomplete (>20% variance), over (ratio >1.2). These are battle-tested thresholds. The existing spec incorrectly lists 95%/80% tiers which differ from the actual legacy implementation. | E8 | final |
| D7 | Reuse existing `ProgressBar` component (supports overflow) | Mobile codebase already has `src/components/ProgressBar.tsx` with `overflowPercentage` and `overflowColor` props — perfect for over-budget visualization. No need to build a new one. | E9 | final |
| D8 | Use `getBudgetProgressColor()` for status colors (not hardcoded hex) | Existing budget color system supports light/dark mode and has green/yellow/red tiers. Reuse this rather than introducing audit-specific color constants. | E10 | final |
| D9 | Items on the detail page are already loaded — pass them as props, don't re-fetch | Transaction detail page already loads items via `subscribeToProjectItems` and has `transactionItems` derived state. Pass this data to `AuditSection` as props rather than fetching again inside the component. | E6 | final |
| D10 | Exclude tax warnings from Phase 1; defer to Phase 2 | Legacy tax logic involves preset lookups and multi-step resolution. Mobile already shows tax info in a separate `TaxesSection`. Adding tax warnings to audit creates UX redundancy. Defer to Phase 2. | E8 | follow-up |
| D11 | Use `sumItemPurchasePrices` denormalized field when available | Legacy Transaction type has `sumItemPurchasePrices` (denormalized string). Mobile Transaction type does NOT have this field. We must compute from item data. However, if this field is added later, prefer it for performance. | E3 | follow-up |
| D12 | Missing price detection: `purchasePriceCents` is null/undefined or === 0 | Matches legacy logic. Mobile stores as `number \| null` so check is simpler (no string parsing). | E2, E8 | final |

## Evidence Highlights

### Key Insights

- **E1 — Placeholder exists and is wired in**: `app/transactions/[id]/sections/AuditSection.tsx` is a placeholder component already integrated into the SectionList, exported from `sections/index.ts`, and has `audit: true` in `collapsedSections` state (line 122 of `index.tsx`).

- **E2 — Mobile Item type uses cents integers**: `Item.purchasePriceCents` is `number | null` (not string like legacy). This simplifies arithmetic but means we can't reuse legacy `parseFloat()` patterns directly.

- **E3 — Mobile Transaction type has all needed fields**: `amountCents`, `subtotalCents`, `taxRatePct`, `budgetCategoryId`, `itemIds`, `needsReview` — all present on the Transaction type.

- **E4 — Itemization check already implemented**: Transaction detail page (line 239) already computes `itemizationEnabled = selectedCategory?.metadata?.categoryType === 'itemized'` and uses it to gate sections.

- **E5 — Legacy vs mobile schema drift on itemization**: Legacy uses `metadata.itemizationEnabled: boolean`. Mobile uses `metadata.categoryType: BudgetCategoryType` where `'itemized'` is the equivalent. The existing spec references the legacy approach — needs updating.

- **E6 — Detail page already loads items**: The transaction detail page subscribes to project items and derives `transactionItems` from them. These are available to pass as props without additional fetching.

- **E7 — Lineage edges not yet in mobile**: Legacy's `getTransactionCompleteness()` fetches lineage edges to include moved-out items. Mobile codebase has no lineage service. For MVP, use only currently-linked items.

- **E8 — Legacy completeness thresholds differ from spec**: The actual legacy code uses `ratio > 1.2` (over), `|variancePercent| > 20` (incomplete), `|variancePercent| > 1` (near), else complete. The existing spec lists 95%/80%/<80%/>100% tiers which don't match.

- **E9 — ProgressBar supports overflow**: `src/components/ProgressBar.tsx` has `overflowPercentage` and `overflowColor` props — designed for exactly this use case.

- **E10 — Budget color system is reusable**: `getBudgetProgressColor(percentage, isFeeCategory, isDark)` in `src/utils/budgetColors.ts` provides theme-aware green/yellow/red colors.

### Risks / Concerns

- **No lineage service in mobile**: Items that were moved out of a transaction won't appear in the completeness calculation. This means completeness can appear lower than it should for transactions with item movements. Acceptable for MVP but needs Phase 3 resolution.

- **`sumItemPurchasePrices` not on mobile Transaction**: We must compute items total client-side from the item array. This is fine for <100 items but could be a concern for very large item sets (unlikely in practice).

- **Spec accuracy**: The existing spec at `docs/specs/transaction_audit_spec.md` has several inaccuracies vs the actual legacy implementation (thresholds, data model fields, component structure). A new/updated spec is needed before planning.

## Next Actions

1. **Update spec** with accurate thresholds, mobile data model fields, and correct component hierarchy based on this research.
2. **Confirm items loading pattern** — verify that `transactionItems` on the detail page includes all linked items or just project-scoped ones.
3. **Decide on Phase 2 scope** — lineage edges, tax warnings, and per-item variance details.
4. **Check if `needsReview` update logic exists** in mobile or needs to be built (legacy has `_recomputeNeedsReview`).

> Keep this document living. As more evidence arrives, update decisions and rationale so downstream implementers can trust the history.
