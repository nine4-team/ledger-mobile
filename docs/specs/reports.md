# Reports

## Overview

The reporting system generates formatted documents from project data. Reports are computed client-side from already-loaded data and rendered for display, printing, or sharing.

## Report Types

### 1. Invoice Report

**Purpose:** Generate an itemized invoice for a client showing all purchased items, grouped by budget category, with totals.

**Data Sources:**
- Project details (name, client name, address)
- Transactions (filtered to project, non-canceled)
- Items linked to those transactions
- Budget categories for grouping

**Structure:**
- Header: Business name/logo, project name, client name, date
- Body: Items grouped by budget category
  - Each group shows: category name, list of items with name/description and price
  - Group subtotal
- Footer: Overall total, optional notes

**Calculations:**
```
for each budget category with items:
  categoryItems = items where budgetCategoryId matches
  categoryTotal = sum of item display prices

overallTotal = sum of all category totals
```

**Display price:** `projectPriceCents` (always set at item creation — defaults to `purchasePriceCents` when not explicitly provided).

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
4. **Fee categories in invoice:** Transactions in fee categories (`categoryType == "fee"`) are excluded from the invoice. Fee categories represent income received from the client (e.g., design fees), not pass-through charges. Including them would double-count money already collected.
5. **Canceled transactions:** Excluded from all reports
