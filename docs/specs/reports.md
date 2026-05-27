# Reports

## Overview

The reporting system generates formatted documents from project data. Reports are computed client-side from already-loaded data and rendered for display, printing, or sharing.

## Report Types

### 1. Invoice Report

**Purpose:** Render a project invoice demand for a client. The report uses the invoice's stored lines once sent/collected so historical invoices do not drift when source items or transactions change.

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

**Display price:** `projectPriceCents` (always set at item creation — defaults to `purchasePriceCents` when not explicitly provided).
For manual New Charge lines, use the line's stored `snapshotName` and `amountCents`.

### 2. Client Summary Report

**Purpose:** High-level spending summary for client review. Shows total spent, total market value, total saved, and per-category spending breakdowns.

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

Reports are generated entirely client-side. No server-side rendering is needed. All data is already loaded through existing Firestore subscriptions.

## Output Formats

- **On-screen display:** Rendered in the app for review
- **Print:** System print dialog for physical copies
- **Share:** Export as PDF or share via system share sheet

## Edge Cases

1. **No items/transactions:** Show empty report with message "No data for this report"
2. **Items without prices:** Include in report with "No Price" or $0.00
3. **Offline generation:** Works fully offline from cached data
4. **Collected fee transactions:** Settlement transactions linked by `settlementInvoiceId` are excluded from the active invoiceable pool. They record money received; they are not a new demand for money.
5. **Canceled transactions:** Excluded from all reports
