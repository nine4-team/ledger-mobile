# Feature Spec: Transaction Audit Section

| Field | Value |
|-------|-------|
| **Feature** | Transaction Audit Section |
| **Spec ID** | 003-transaction-audit |
| **Branch** | feat/transaction-audit |
| **Date** | 2026-02-09 |
| **Status** | Draft |
| **Research** | `kitty-specs/002-transaction-audit/research.md` |
| **Data Model** | `kitty-specs/002-transaction-audit/data-model.md` |

## Overview

When a transaction is categorized under an itemized budget category, users need visibility into how well the linked items account for the transaction total. The audit section surfaces a completeness analysis: comparing the sum of individual item prices against the transaction's pre-tax subtotal. This helps project managers identify transactions with missing item data, unaccounted-for costs, or over-reported item totals before finalizing project finances.

---

## User Scenarios & Testing

### P1 -- Core Audit Visibility

**US-01: View audit completeness for an itemized transaction**
As a project manager reviewing a transaction,
I want to see how much of the transaction total is accounted for by linked item prices,
so that I can identify gaps in my inventory records before closing out a project.

Given: A transaction categorized under an itemized budget category with linked items that have prices recorded.
When: I view the transaction detail page.
Then: I see an audit section showing the items total, the transaction subtotal, a visual completeness indicator, and a status message.

**US-02: Identify transactions needing attention**
As a project manager scanning my transaction list,
I want transactions with incomplete itemization to be visually distinct,
so that I can prioritize which records need follow-up.

Given: A transaction where linked item prices sum to significantly less than the transaction subtotal.
When: I view the audit section on the transaction detail page.
Then: I see a clear visual indicator (color-coded status) that the transaction is incomplete, with a percentage showing how much is accounted for.

**US-03: Understand missing item prices**
As a project manager reviewing an itemized transaction,
I want to know how many linked items are missing price data,
so that I can determine whether the completeness gap is due to missing data entry versus genuinely unaccounted costs.

Given: A transaction with some linked items that have no purchase price recorded.
When: I view the audit section.
Then: I see a count of items missing prices, helping me distinguish between "data not entered" and "costs don't add up."

### P2 -- Status Tiers & Over-Itemization

**US-04: See near-complete transactions**
As a project manager reviewing an itemized transaction,
I want to distinguish between transactions that are nearly complete and those that are far off,
so that I can focus effort on the most problematic records first.

Given: A transaction where item prices account for most (but not all) of the subtotal, within a small variance.
When: I view the audit section.
Then: I see a "near complete" status with appropriate color coding, distinguishing it from transactions that are severely incomplete.

**US-05: Identify over-itemized transactions**
As a project manager reviewing an itemized transaction,
I want to be alerted when linked item prices exceed the transaction subtotal by a significant margin,
so that I can investigate whether items were incorrectly linked or prices were entered wrong.

Given: A transaction where the sum of item prices is more than 120% of the transaction subtotal.
When: I view the audit section.
Then: I see an "over" status with distinct visual treatment, and the progress indicator reflects the overage.

### P3 -- Edge Cases

**US-06: View audit for transactions with no linked items**
As a project manager viewing an itemized transaction that has no items linked yet,
I want to see that 0% of the transaction is accounted for,
so that I know I need to link items to this transaction.

Given: An itemized transaction with no linked items.
When: I view the transaction detail page.
Then: The audit section shows 0% completeness and an "incomplete" status.

**US-07: Handle transactions with zero subtotal**
As a user viewing a transaction where the subtotal resolves to zero,
I want the audit section to handle this gracefully rather than showing errors,
so that I am not confused by broken calculations.

Given: A transaction where all monetary fields resolve to zero or null.
When: I view the audit section.
Then: The audit section displays a neutral "N/A" state rather than errors or nonsensical percentages.

**US-08: Audit section only appears for itemized categories**
As a user viewing a transaction under a non-itemized budget category (general or fee),
I want the audit section to be hidden,
so that I only see audit information when it is relevant.

Given: A transaction categorized under a "general" or "fee" budget category.
When: I view the transaction detail page.
Then: No audit section is visible.

**US-09: Offline audit calculation**
As a user working without internet connectivity,
I want the audit section to calculate and display correctly from locally available data,
so that I can review audit status regardless of connectivity.

Given: The device is offline, and transaction and item data have been previously loaded.
When: I view the transaction detail page.
Then: The audit section calculates and displays completeness from cached data without blocking on network requests.

---

## Requirements

### Functional Requirements

**FR-001: Conditional display based on budget category type**
The audit section shall only be displayed on the transaction detail page when the transaction's associated budget category has a category type of "itemized." Transactions under "general" or "fee" categories shall not show the audit section.

**FR-002: Items total calculation**
The system shall calculate the items total as the sum of all purchase prices for items linked to the transaction. Items with no purchase price (null or zero) shall be counted as contributing zero to the total.

**FR-003: Subtotal resolution with fallback priority**
The transaction subtotal used for audit comparison shall be resolved in the following priority order:
1. Explicit pre-tax subtotal, if available
2. Inferred subtotal derived from the total amount and the tax rate percentage, if both are available
3. Total transaction amount as a final fallback

**FR-004: Completeness ratio and status classification**
The system shall calculate a completeness ratio (items total divided by transaction subtotal) and classify the result into one of four statuses:
- **Complete**: Variance is within 1% of the subtotal (ratio approximately 1.0)
- **Near complete**: Variance is between 1% and 20% of the subtotal
- **Incomplete**: Variance exceeds 20% of the subtotal
- **Over**: Items total exceeds 120% of the subtotal

**FR-005: Visual completeness indicator**
The audit section shall display a visual progress indicator showing the completeness ratio. The indicator shall:
- Fill proportionally to the completeness percentage
- Support overflow display when the ratio exceeds 100%
- Use color coding consistent with the app's existing budget status colors (theme-aware for light and dark modes)

**FR-006: Status message display**
The audit section shall display a human-readable status message reflecting the completeness status. The message shall include the completeness percentage.

**FR-007: Missing price count**
When one or more linked items have no purchase price recorded (null or zero), the audit section shall display a count of items with missing prices.

**FR-008: Totals comparison display**
The audit section shall display the items total and the transaction subtotal side by side so the user can see the raw values being compared.

**FR-009: Division by zero handling**
When the resolved transaction subtotal is zero, the audit section shall display a neutral "N/A" state and shall not attempt to calculate a completeness ratio.

**FR-010: No linked items handling**
When the transaction has no linked items, the audit section shall show 0% completeness with an "incomplete" status.

**FR-011: Offline calculation support**
All audit calculations shall be performed using data already available on the transaction detail page. The audit section shall not initiate any additional data fetching or network requests.

**FR-012: Theme-aware color coding**
All status colors in the audit section shall adapt to the current display theme (light or dark mode), using the app's existing color system.

### Key Entities

| Entity | Role in Audit | Key Fields |
|--------|---------------|------------|
| **Transaction** | Subject of the audit | Total amount, pre-tax subtotal, tax rate, linked item IDs, budget category reference, review flag |
| **Item** | Contributes to items total | Purchase price |
| **Budget Category** | Gates audit visibility | Category type (general / itemized / fee) |
| **Transaction Completeness** | Computed audit result (not persisted) | Items total, items count, missing price count, subtotal, completeness ratio, status, variance |

### Phase Plan

| Phase | Scope |
|-------|-------|
| **Phase 1 (MVP)** | Completeness calculation, progress bar with color coding, status message, items total vs transaction subtotal, missing-price item count |
| **Phase 2** | Tax data warnings, variance detail breakdown, collapsible sub-sections, navigation from audit to individual items |
| **Phase 3** | Historical item resolution (items moved away from transaction), per-item contribution view, automated review flag updates |

### Out of Scope (All Phases)

- Editing item prices from within the audit section
- Audit calculations for non-itemized budget categories
- Server-side audit computation or persistence of computed audit metrics
- Bulk transaction audit views or aggregate audit dashboards
- Audit history or change tracking over time

---

## Success Criteria

**SC-001: Audit section visibility accuracy**
The audit section appears on 100% of transaction detail pages where the budget category type is "itemized" and is hidden on 100% of pages where the category type is "general" or "fee."

**SC-002: Calculation correctness**
For any transaction with linked items, the displayed items total equals the sum of all linked item purchase prices (treating null/zero as zero). The displayed subtotal matches the resolution priority (explicit subtotal, then inferred from tax rate, then total amount).

**SC-003: Status classification accuracy**
The completeness status displayed matches the defined thresholds: "complete" within 1% variance, "near" for 1-20% variance, "incomplete" for >20% variance, and "over" when items total exceeds 120% of subtotal.

**SC-004: Zero subtotal resilience**
When the transaction subtotal resolves to zero, the audit section displays "N/A" without errors, crashes, or nonsensical percentages.

**SC-005: Empty items resilience**
When an itemized transaction has no linked items, the audit section displays 0% completeness and an "incomplete" status without errors.

**SC-006: Missing price transparency**
When linked items have missing prices, the missing price count is displayed and matches the actual count of items with null or zero purchase prices.

**SC-007: Offline functionality**
The audit section renders and calculates correctly when the device has no network connectivity, using previously loaded data.

**SC-008: Theme consistency**
All audit section colors (progress indicator, status text) are appropriate and legible in both light and dark display themes.

**SC-009: No additional network requests**
Loading the audit section does not trigger any data fetches beyond what the transaction detail page already performs. Verified by confirming no new loading states or network delays when scrolling to the audit section.

**SC-010: Performance**
The audit section renders without perceptible delay (under 100ms) for transactions with up to 100 linked items.
