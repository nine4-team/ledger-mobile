# Task Breakdown: Transaction Audit Section

**Feature**: 003-transaction-audit
**Spec**: [spec.md](spec.md)
**Plan**: [plan.md](plan.md)
**Date**: 2026-02-09

## Subtask Register

| ID | Description | WP | Parallel | Dependencies |
|----|-------------|-----|----------|-------------|
| T001 | Define `CompletenessStatus` type and `TransactionCompleteness` interface | WP01 | [P] | — |
| T002 | Implement `computeTransactionCompleteness()` pure function | WP01 | — | T001 |
| T003 | Write unit tests for completeness calculation | WP01 | — | T002 |
| T004 | Replace AuditSection placeholder with real UI component | WP02 | — | WP01 |
| T005 | Gate audit section behind `itemizationEnabled` in sections memo | WP02 | [P] | — |
| T006 | Pass `linkedItems` as props from parent page to AuditSection | WP02 | [P] | T004 |

## Work Packages

### WP01 — Completeness Calculation Utility

**Priority**: P1 (foundation — all UI depends on this)
**Subtasks**: T001, T002, T003
**Estimated prompt size**: ~350 lines
**Dependencies**: None
**Parallel opportunities**: T001 is independent type definitions

**Goal**: Create a pure TypeScript utility that computes transaction completeness metrics from Transaction + Item data. This is the core logic layer — no React, no UI, fully testable in isolation.

**Included subtasks**:
- [ ] T001: Define `CompletenessStatus` type and `TransactionCompleteness` interface in `src/utils/transactionCompleteness.ts`
- [ ] T002: Implement `computeTransactionCompleteness(transaction, items)` pure function with subtotal resolution (D5), threshold classification (D6), variance calculation, missing price detection (D12)
- [ ] T003: Unit tests covering all threshold boundaries, edge cases (zero subtotal, no items, missing prices, over-itemization), and subtotal resolution priority

**Implementation sequence**:
1. Types first (T001)
2. Function implementation (T002)
3. Test suite (T003)

**Risks**:
- Float precision in inferred subtotal calculation — mitigate with `Math.round()`
- Threshold boundary conditions (exactly 1%, exactly 20%, exactly 120%) — tests must cover these precisely

**Implementation command**: `spec-kitty implement WP01`

---

### WP02 — Audit Section UI Component

**Priority**: P1 (completes Phase 1 MVP)
**Subtasks**: T004, T005, T006
**Estimated prompt size**: ~400 lines
**Dependencies**: WP01 (needs `computeTransactionCompleteness` and types)
**Parallel opportunities**: T005 and T006 modify different sections of `index.tsx`

**Goal**: Replace the AuditSection placeholder with a real component that displays completeness progress, status, totals comparison, and missing price count. Gate visibility behind itemized categories.

**Included subtasks**:
- [ ] T004: Replace AuditSection.tsx placeholder — add `items` prop, call `computeTransactionCompleteness` via `useMemo`, render Card with ProgressBar, totals row, status message, missing price count, N/A state for zero subtotal
- [ ] T005: Gate audit section in parent page `sections` memo — wrap with `if (itemizationEnabled)` like the taxes section
- [ ] T006: Pass `linkedItems` to AuditSection in parent page render switch — update the `case 'audit'` branch

**Implementation sequence**:
1. T005 + T006 can start in parallel (both modify `index.tsx` but different sections)
2. T004 is the main component work

**Risks**:
- Color mapping inversion: `getBudgetProgressColor` uses `isFeeCategory` parameter to invert semantics. For audit, high completeness = good (green), so pass `isFeeCategory=true` for inverted mapping.
- ProgressBar overflow: when ratio > 1.0, set `percentage=100` and `overflowPercentage = (ratio - 1) * 100`

**Implementation command**: `spec-kitty implement WP02 --base WP01`
