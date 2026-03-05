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

**Display price priority:** Use `projectPriceCents` if set, otherwise `purchasePriceCents`.

### 2. Client Summary Report

**Purpose:** High-level budget summary for client review. Shows spending by category without item-level detail.

**Data Sources:**
- Project details
- Budget progress data (per-category spent vs budgeted)

**Structure:**
- Header: Business name, project name, client name, date
- Body: Budget categories with spent vs allocated amounts
  - Each category: name, budgeted amount, spent amount, remaining
  - Fee categories shown separately with "received" language
- Footer: Overall budget total, overall spent, overall remaining

### 3. Property Management Report

**Purpose:** Inventory of items by space/room for property management handoff.

**Data Sources:**
- Project details
- Spaces in the project
- Items assigned to each space

**Structure:**
- Header: Project name, property address, date
- Body: Items grouped by space
  - Each space: name, list of items with name, SKU, and price
  - Items with no space grouped under "Unassigned"
- Footer: Total item count, total value

## Generation

Reports are generated entirely client-side. No server-side rendering is needed. All data is already loaded through existing Firestore subscriptions.

## Output Formats

- **On-screen display:** Rendered in the app for review
- **Print:** System print dialog for physical copies
- **Share:** Export as PDF or share via system share sheet

## Edge Cases

1. **No items/transactions:** Show empty report with message "No data for this report"
2. **Items without prices:** Include in report with "Price not set" or $0.00
3. **Offline generation:** Works fully offline from cached data
4. **Fee categories in invoice:** Typically excluded from item invoices (they represent income, not client charges)
5. **Canceled transactions:** Excluded from all reports
