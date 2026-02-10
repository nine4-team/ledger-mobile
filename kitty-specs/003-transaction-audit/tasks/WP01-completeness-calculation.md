---
work_package_id: WP01
title: Completeness Calculation Utility
lane: "for_review"
dependencies: []
base_branch: main
base_commit: 57be6e4ca03ba84f11d251ae8e4a15cf33f91270
created_at: '2026-02-10T01:13:26.578262+00:00'
subtasks:
- T001
- T002
- T003
phase: Phase 1 - MVP
assignee: ''
agent: "claude-opus"
shell_pid: "75313"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-09T15:00:00Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP01 – Completeness Calculation Utility

## ⚠️ IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Objectives & Success Criteria

Create a pure TypeScript utility function that computes transaction completeness metrics by comparing linked item purchase prices against the transaction subtotal. This is the foundation layer — no React, no UI, fully testable in isolation.

**Success criteria**:
- `computeTransactionCompleteness()` returns correct completeness data for all status tiers
- Subtotal resolution follows the correct priority: explicit `subtotalCents` → inferred from `taxRatePct` → fallback to `amountCents`
- Completeness thresholds match legacy: ±1% (complete), 1-20% (near), >20% (incomplete), >120% (over)
- All edge cases handled: zero subtotal returns `null`, no items returns 0%/incomplete, missing prices counted correctly
- Unit tests pass covering all threshold boundaries and edge cases

## Context & Constraints

**Reference documents**:
- Spec: `kitty-specs/003-transaction-audit/spec.md` (FR-002, FR-003, FR-004, FR-007, FR-009, FR-010)
- Plan: `kitty-specs/003-transaction-audit/plan.md` (Key Implementation Details section)
- Research: `kitty-specs/002-transaction-audit/research.md` (D2, D5, D6, D11, D12)
- Data model: `kitty-specs/003-transaction-audit/data-model.md`

**Key constraints**:
- All monetary values are cents-based integers (`number | null`). No string parsing needed.
- Use `Math.round()` when computing inferred subtotal to avoid float drift.
- The function must be pure (no side effects, no React imports, no Firestore calls).
- Import the `Transaction` type from `src/data/transactionsService.ts` and `Item` type from `src/data/itemsService.ts`.

**Existing types for reference**:

Transaction (from `src/data/transactionsService.ts`):
```typescript
export type Transaction = {
  id: string;
  amountCents?: number | null;
  subtotalCents?: number | null;
  taxRatePct?: number | null;
  budgetCategoryId?: string | null;
  itemIds?: string[] | null;
  needsReview?: boolean | null;
  // ... other fields not relevant to audit
};
```

Item (from `src/data/itemsService.ts`):
```typescript
export type Item = {
  id: string;
  purchasePriceCents?: number | null;
  transactionId?: string | null;
  // ... other fields not relevant to audit
};
```

## Subtasks & Detailed Guidance

### Subtask T001 – Define types and interfaces

**Purpose**: Establish the TypeScript types that the calculation function returns and that the UI component will consume. Keeping types in the same file as the function keeps the module self-contained.

**Steps**:
1. Create file `src/utils/transactionCompleteness.ts`
2. Define the `CompletenessStatus` type:
   ```typescript
   export type CompletenessStatus = 'complete' | 'near' | 'incomplete' | 'over';
   ```
3. Define the `TransactionCompleteness` interface:
   ```typescript
   export interface TransactionCompleteness {
     /** Sum of purchasePriceCents for all linked items (cents) */
     itemsNetTotal: number;
     /** Total count of linked items */
     itemsCount: number;
     /** Count of items where purchasePriceCents is null/undefined/0 */
     itemsMissingPriceCount: number;
     /** Resolved pre-tax subtotal (cents) — via D5 priority */
     transactionSubtotal: number;
     /** itemsNetTotal / transactionSubtotal (0-N, where 1.0 = 100%) */
     completenessRatio: number;
     /** Classified status based on D6 thresholds */
     completenessStatus: CompletenessStatus;
     /** True if no explicit subtotal and no valid taxRatePct */
     missingTaxData: boolean;
     /** Tax amount inferred from taxRatePct (cents), undefined if not inferred */
     inferredTax?: number;
     /** itemsNetTotal - transactionSubtotal (positive = over, negative = under) */
     varianceCents: number;
     /** (varianceCents / transactionSubtotal) * 100 */
     variancePercent: number;
   }
   ```
4. Add import statements for `Transaction` and `Item` types at the top of the file.

**Files**: `src/utils/transactionCompleteness.ts` (new file)
**Parallel?**: Yes — types can be defined independently.

---

### Subtask T002 – Implement `computeTransactionCompleteness()` function

**Purpose**: The core calculation engine. Takes a transaction and its linked items, returns a `TransactionCompleteness` object or `null` (when subtotal is zero/invalid).

**Steps**:

1. **Function signature**:
   ```typescript
   export function computeTransactionCompleteness(
     transaction: Transaction,
     items: Pick<Item, 'purchasePriceCents'>[],
   ): TransactionCompleteness | null
   ```
   Use `Pick<Item, 'purchasePriceCents'>` so the function only depends on the field it needs. This makes it easier to test and more flexible for callers.

2. **Items total calculation** (FR-002):
   ```typescript
   const itemsNetTotal = items.reduce(
     (sum, item) => sum + (item.purchasePriceCents ?? 0),
     0,
   );
   ```
   Items with null/undefined/0 `purchasePriceCents` contribute 0.

3. **Missing price count** (FR-007, D12):
   ```typescript
   const itemsMissingPriceCount = items.filter(
     (item) => !item.purchasePriceCents,
   ).length;
   ```
   This catches `null`, `undefined`, and `0` — all considered "missing" per D12.

4. **Subtotal resolution** (FR-003, D5) — implement in priority order:
   - **Priority 1**: If `transaction.subtotalCents` exists and is > 0, use it directly. Set `missingTaxData = false`, `inferredTax = undefined`.
   - **Priority 2**: If `transaction.amountCents` exists and > 0 AND `transaction.taxRatePct` exists and > 0, compute:
     ```typescript
     const inferredSubtotal = Math.round(
       transaction.amountCents / (1 + transaction.taxRatePct / 100)
     );
     const inferredTax = transaction.amountCents - inferredSubtotal;
     ```
     Set `missingTaxData = false`.
   - **Priority 3 (fallback)**: If `transaction.amountCents` exists and > 0, use it as subtotal. Set `missingTaxData = true` (no tax info available), `inferredTax = undefined`.
   - **Bail out**: If none of the above yield a positive subtotal, return `null` (FR-009 — zero subtotal = N/A).

5. **Completeness ratio and variance**:
   ```typescript
   const completenessRatio = itemsNetTotal / transactionSubtotal;
   const varianceCents = itemsNetTotal - transactionSubtotal;
   const variancePercent = (varianceCents / transactionSubtotal) * 100;
   ```

6. **Status classification** (FR-004, D6) — evaluate in this order (order matters!):
   ```typescript
   let completenessStatus: CompletenessStatus;
   if (completenessRatio > 1.20) {
     completenessStatus = 'over';
   } else if (Math.abs(variancePercent) <= 1) {
     completenessStatus = 'complete';
   } else if (Math.abs(variancePercent) <= 20) {
     completenessStatus = 'near';
   } else {
     completenessStatus = 'incomplete';
   }
   ```
   **Critical**: Check `over` FIRST (ratio > 1.20), then `complete` (within ±1%), then `near` (within ±20%), then `incomplete` (everything else).

7. **Return the result object** with all computed fields.

**Files**: `src/utils/transactionCompleteness.ts`
**Parallel?**: No — depends on T001 types.

**Edge cases to handle**:
- `items` is empty array → `itemsNetTotal = 0`, `itemsCount = 0`, status will be `incomplete` (0% of subtotal)
- All items have null prices → same as above but `itemsMissingPriceCount` equals `itemsCount`
- `transaction.amountCents` is null/0 AND `subtotalCents` is null/0 → return `null`

---

### Subtask T003 – Write unit tests

**Purpose**: Verify all calculation logic, threshold boundaries, and edge cases. The pure function design makes this straightforward — no mocking needed.

**Steps**:

1. Create file `src/utils/__tests__/transactionCompleteness.test.ts`
2. Import `computeTransactionCompleteness` and types from `../transactionCompleteness`
3. Create a helper to build test transactions:
   ```typescript
   function makeTransaction(overrides: Partial<Transaction> = {}): Transaction {
     return { id: 'txn-1', amountCents: 10000, ...overrides };
   }
   function makeItems(prices: (number | null)[]): Pick<Item, 'purchasePriceCents'>[] {
     return prices.map(p => ({ purchasePriceCents: p }));
   }
   ```

4. **Test categories** (write at least one test per category):

   **a. Subtotal resolution priority**:
   - Explicit `subtotalCents` is used when present (ignoring amountCents and taxRatePct)
   - Inferred subtotal when `subtotalCents` is null but `amountCents` and `taxRatePct` are set
   - Fallback to `amountCents` when neither `subtotalCents` nor `taxRatePct` available
   - Verify `missingTaxData` is true only for fallback case
   - Verify `inferredTax` is set only for inferred case

   **b. Status classification at threshold boundaries**:
   - Exactly 1% variance → `complete` (boundary)
   - 1.01% variance → `near` (just past complete)
   - Exactly 20% variance → `near` (boundary)
   - 20.01% variance → `incomplete` (just past near)
   - Exactly 120% ratio → `near` (NOT over — over requires >1.20)
   - 121% ratio → `over`
   - 0% variance (exact match) → `complete`

   **c. Edge cases**:
   - Zero subtotal (all monetary fields null/0) → returns `null`
   - Empty items array → 0% completeness, `incomplete` status
   - All items have null `purchasePriceCents` → same as empty (0 total), `missingPriceCount` matches item count
   - Items with mix of prices and nulls → correct total and missing count
   - Single item matching subtotal exactly → `complete`

   **d. Inferred subtotal math**:
   - `amountCents: 10825, taxRatePct: 8.25` → `inferredSubtotal = Math.round(10825 / 1.0825) = 10000`
   - Verify `inferredTax = 825` (10825 - 10000)
   - Test with different tax rates to verify `Math.round()` prevents float issues

   **e. Items total calculation**:
   - Multiple items with varying prices → correct sum
   - Items with 0 price → counted in total as 0, counted in missing prices
   - Large number of items (100) → correct sum (performance confidence)

**Files**: `src/utils/__tests__/transactionCompleteness.test.ts` (new file)
**Parallel?**: No — depends on T002.

**Notes**:
- Ensure the `__tests__` directory exists (create if needed)
- Use descriptive test names that reference the FR/D number being tested
- No React testing library needed — pure function tests only

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Float precision in inferred subtotal | Incorrect cents values | Use `Math.round()` on inferred subtotal; test with known tax rates |
| Threshold boundary off-by-one | Wrong status classification | Test exact boundary values (1%, 20%, 120%) explicitly |
| `purchasePriceCents === 0` treated as valid vs missing | Incorrect missing count | D12 says 0 = missing — test explicitly |
| Import path issues with Transaction/Item types | Build failure | Verify exact export paths from service files |

## Review Guidance

**Key checkpoints for reviewers**:
1. **Subtotal resolution order**: Verify explicit > inferred > fallback (not swapped)
2. **Status classification order**: Verify `over` checked first (ratio > 1.20), then ±1%, then ±20%, then incomplete
3. **Missing price definition**: `null`, `undefined`, AND `0` all count as missing per D12
4. **Math.round()**: Applied to inferred subtotal calculation
5. **Return null**: Only when resolved subtotal is 0 or negative (FR-009)
6. **No React imports**: This file must be pure TypeScript — no React, no hooks

## Activity Log

- 2026-02-09T15:00:00Z – system – lane=planned – Prompt created.
- 2026-02-10T01:13:26Z – claude-opus – shell_pid=75313 – lane=doing – Assigned agent via workflow command
- 2026-02-10T01:15:14Z – claude-opus – shell_pid=75313 – lane=for_review – Ready for review: Pure calculation utility + 24 passing tests
