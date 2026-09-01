# Reports

> **Target-state notice (2026-08-30):** Report readers must migrate with
> [Invoice-Centered Project Accounting](invoice-centered-project-accounting.md).
> Paid category allocation comes from frozen Invoice contents attached to the
> lump-sum Transaction; open allocation comes from Items, Expenses, and Fees.
> Reports must not double-count the settlement Transaction or treat hidden
> movement provenance as a client-facing record.

## Overview

The reporting system generates formatted documents from project data. Reports are computed client-side from already-loaded data and rendered for display, printing, or sharing.

## Report Types

### 1. Invoice Report

**Purpose:** Render a project invoice demand for a client. Created and sent
Invoices render the current authoritative live source values under D-011. A
collected Invoice renders only its immutable frozen paid lines and allocations.
O-034 controls whether sent membership changes require revise-and-resend and
which delivered render revisions are retained.

**Data Sources:**
- Project details (name, client name, address)
- Invoice lines (`sourceType: item | transaction | manual`)
- Items and transactions referenced by source-backed lines when rendering draft/live previews
- Budget categories for grouping

**Structure:**
- Header: Business name/logo, project name, client name, date
- Body: Invoice lines grouped by budget category where available
  - Each group shows: category name, list of line labels and signed amounts
  - Group subtotal
- Footer: Overall total, optional notes

**Calculations:**
```
for each invoice line:
  signedAmount = amountCents * sign

overallTotal = sum of signedAmount
```

**Display price:** the normalized `projectPriceCents`. Every item write maintains `projectPriceCents >= purchasePriceCents`; report readers defensively use `max(projectPriceCents ?? 0, purchasePriceCents ?? 0)` for legacy records.
For manual New Charge lines, use the line's stored `snapshotName` and `amountCents`.

### 2. Client Summary Report

**Purpose:** High-level financial and physical-value summary for Client review.
O-035 must close the meaning and labels for paid, open/committed, recognized,
market-value, savings, credits, and category totals. Current active-Item price
aggregation is source behavior, not approved target “paid spend.”

**Data Sources:**
- Project details
- Items (for spending totals and category breakdowns)

**Structure:**
- Header: Business name, project name, date
- Summary cards: Total Spent, Total Market Value, Total Saved
- Body: Category breakdown showing spending per category
- Items list with space assignments and receipt links
- No internal budget data is exposed to the client

### 3. Property Management Report

**Purpose:** Inventory of items by space/room for property management handoff.

**Data Sources:**
- Project details
- Spaces in the project
- Items assigned to each space

**Structure:**
- Header: Project name, property address, date
- Body: Items grouped by space
  - Each space: name, list of items with name, SKU, and market value
  - Items with no space grouped under "No Space"
- Footer: Total item count, total value

## Generation

Reports may be rendered entirely on-device from an authorization-safe,
readiness-complete local `ReportSnapshot`. Rendering code does not receive raw
mutable domain arrays and does not reimplement accounting. A generated snapshot
records account/project, report kind, local data version, accounting authority
version, as-of time, visibility scope, currency, and source/frozen revision
evidence. Server rendering is optional infrastructure, not report authority.

## Output Formats

- **On-screen display:** Rendered in the app for review
- **Print:** System print dialog for physical copies
- **Share:** Export as PDF or share via system share sheet

## Edge Cases

1. **No items/transactions:** Show empty report with message "No data for this report"
2. **Items without prices:** Include in report with "No Price" or $0.00
3. **Offline generation:** Works fully offline only when the required report
   snapshot reports complete readiness. A partial synchronized working set must
   not render a deceptively complete report.
4. **Collection evidence:** The one collected Project Purchase proves payment
   but is not counted again on top of frozen source allocations.
5. **Canceled transactions:** Excluded from all reports
6. **Shared receipt evidence:** O-036 controls eligibility and delivery. A PDF
   must never contain a private object path or expiring bearer download URL.

## Target Export and Delivery Rules

- Screen, PDF, print, CSV, and MCP render from the same typed snapshot fields.
- Every row has stable identity and deterministic ordering; exports record an
  as-of/version manifest so reruns can explain changes.
- Financial permissions are applied before source rows or safe aggregate
  projections reach the local database or MCP result. Hidden rows, counts,
  totals, names, categories, and search hits do not leak.
- A report renderer is pure presentation. It cannot fetch logo/receipt bytes,
  decide payment state, infer missing relationships, or fall back to legacy
  accounting on its own.
- Local temporary files use collision-safe names and protected storage, report
  failures visibly, and are removed under an explicit retention policy after
  share/download handoff.
