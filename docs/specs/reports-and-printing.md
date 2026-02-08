# Reports & Printing Specification

**Version**: 1.0
**Date**: 2026-02-07
**Status**: Draft

---

## Table of Contents

1. [Overview](#overview)
2. [Goals & Principles](#goals--principles)
3. [Data Model](#data-model)
4. [Report Types](#report-types)
5. [Rendering Pipeline](#rendering-pipeline)
6. [Offline Behavior](#offline-behavior)
7. [Intentional Deltas from Web](#intentional-deltas-from-web)
8. [Business Profile Integration](#business-profile-integration)
9. [Acceptance Criteria](#acceptance-criteria)
10. [Implementation Targets](#implementation-targets)

---

## Overview

Reports & Printing provides three project-scoped reports that summarize financial and asset data for client presentation. Each report can be previewed on-screen in the mobile app and shared or printed via the native OS share sheet.

The three reports are:

| Report | Purpose | Primary Data |
|--------|---------|-------------|
| **Invoice** | Itemized billing statement for clients | Invoiceable transactions + linked items |
| **Client Summary** | Spending overview with savings analysis | Items with project prices and market values |
| **Property Management Summary** | Asset inventory for property management | Items with market values and space assignments |

All reports operate offline-first, rendering entirely from Firestore's local cache with no network dependency. Reports are generated as PDF documents via `expo-print` and distributed through `expo-sharing` or printed directly.

---

## Goals & Principles

### Primary Goals

1. **Client-Ready Output**: Reports must produce polished, branded documents suitable for direct client delivery
2. **Accurate Financials**: All calculations must match the source data exactly, using cents-based arithmetic to avoid floating-point errors
3. **Offline-First**: Reports must render from local cache without network access
4. **Native Distribution**: Use platform-native share sheets and print dialogs rather than browser-based workarounds

### Design Principles

- **Cents-Based Arithmetic**: All monetary calculations operate on integer cents. Conversion to dollars happens only at the formatting layer
- **Deterministic Output**: Same data always produces the same report (no random ordering, no time-of-day variance beyond the date header)
- **Zero-Network Rendering**: Report data assembly and PDF generation use no network calls. Only media (logo) may require prior upload
- **Graceful Degradation**: Missing data (no items, no logo, no market value) produces clear fallback messaging rather than errors
- **Consistent Branding**: Business logo and name appear on all reports when available

---

## Data Model

### Transaction (Report-Relevant Fields)

**Firestore Path**: `accounts/{accountId}/transactions/{transactionId}`

```typescript
type Transaction = {
  id: string;
  projectId?: string | null;
  transactionDate?: string | null;           // ISO date string, e.g. "2025-03-15"
  amountCents?: number | null;               // Transaction amount in cents
  source?: string | null;                    // Vendor/source name
  reimbursementType?: string | null;         // 'owed-to-company' | 'owed-to-client' | null
  isCanceled?: boolean | null;               // Soft-cancel flag
  isCanonicalInventorySale?: boolean | null;  // True if system-generated canonical sale
  inventorySaleDirection?: 'business_to_project' | 'project_to_business' | null;
  itemIds?: string[] | null;                 // Linked item IDs
  budgetCategoryId?: string | null;          // FK to BudgetCategory
  notes?: string | null;                     // Free-text notes
  receiptImages?: AttachmentRef[] | null;    // Receipt image attachments
};
```

**Reimbursement Type Constants** (from `src/constants/reimbursement.ts`):

| Constant | Value | Meaning |
|----------|-------|---------|
| `OWED_TO_COMPANY` | `'owed-to-company'` | Client owes the design business |
| `OWED_TO_CLIENT` | `'owed-to-client'` | Design business owes the client |

---

### Item (Report-Relevant Fields)

**Firestore Path**: `accounts/{accountId}/items/{itemId}`

```typescript
type Item = {
  id: string;
  name: string;                              // Display label (normalized from legacy `description`)
  projectId?: string | null;
  spaceId?: string | null;                   // FK to Space document
  source?: string | null;                    // Vendor/source name
  sku?: string | null;                       // Stock keeping unit
  transactionId?: string | null;             // FK to linked transaction
  projectPriceCents?: number | null;         // What the client paid, in cents
  marketValueCents?: number | null;          // Retail/market value, in cents
  budgetCategoryId?: string | null;          // FK to BudgetCategory (item-level)
};
```

---

### Space (Report-Relevant Fields)

**Firestore Path**: `accounts/{accountId}/spaces/{spaceId}`

```typescript
type Space = {
  id: string;
  projectId: string | null;
  name: string;                              // Display name (e.g. "Living Room")
  isArchived: boolean;
};
```

Items reference spaces via `item.spaceId`. Reports must resolve the space name by looking up the Space document.

---

### BudgetCategory (Report-Relevant Fields)

**Firestore Path**: `accounts/{accountId}/presets/default/budgetCategories/{budgetCategoryId}`

```typescript
type BudgetCategory = {
  id: string;
  name: string;                              // Display name (e.g. "Furnishings")
  isArchived: boolean;
};
```

Used by the Client Summary report to group items by spending category.

---

### BusinessProfile

**Firestore Path**: `accounts/{accountId}/profile/default`

```typescript
type BusinessProfile = {
  id: 'default';
  accountId: string;
  businessName: string;
  logo?: {
    url?: string | null;                     // Remote URL or 'offline://...' placeholder
    kind?: 'image';
    storagePath?: string | null;
  } | null;
};
```

---

### Project (Report-Relevant Fields)

**Firestore Path**: `accounts/{accountId}/projects/{projectId}`

```typescript
type Project = {
  id: string;
  name: string;
  clientName: string;
};
```

---

### AttachmentRef

```typescript
type AttachmentRef = {
  url: string;                               // Remote URL or 'offline://<mediaId>'
  kind: 'image' | 'pdf';
  fileName?: string;
  contentType?: string;
  isPrimary?: boolean;
};
```

An `AttachmentRef` with a URL starting with `offline://` indicates the file exists only on-device and has not been uploaded to cloud storage.

---

## Report Types

### Invoice Report

#### Purpose

Generate an itemized billing statement showing what the client owes (charges) and what the design business owes back (credits), producing a net amount due.

#### Data Selection

**Filter**: From all project transactions, include only those where:

1. `isCanceled` is falsy (`false`, `null`, or `undefined`)
2. `reimbursementType` is `'owed-to-company'` OR `'owed-to-client'`

```typescript
const invoiceableTransactions = transactions
  .filter(t => !t.isCanceled)
  .filter(t =>
    t.reimbursementType === 'owed-to-company' ||
    t.reimbursementType === 'owed-to-client'
  );
```

#### Grouping

Invoiceable transactions are split into two sections:

| Section | Filter | Label |
|---------|--------|-------|
| **Project Charges** | `reimbursementType === 'owed-to-company'` | Amounts the client owes |
| **Project Credits** | `reimbursementType === 'owed-to-client'` | Amounts owed back to the client |

Within each section, transactions are sorted by `transactionDate` ascending (earliest first). Null dates sort to the beginning.

#### Line Total Calculation

For each invoiceable transaction, determine whether it has linked items:

```typescript
// Resolve linked items for the transaction
const linkedItems = items.filter(item => item.transactionId === transaction.id);
const hasItems = linkedItems.length > 0;
```

**If the transaction has linked items** (`hasItems === true`):

```typescript
lineTotal = linkedItems.reduce((sum, item) => {
  const priceCents = item.projectPriceCents ?? 0;
  return sum + priceCents;
}, 0);
```

Each linked item contributes its `projectPriceCents`. If `projectPriceCents` is `null` or `0`, the item is flagged as "Missing project price" and contributes `0` to the line total.

**If the transaction has no linked items** (`hasItems === false`):

```typescript
lineTotal = transaction.amountCents ?? 0;
```

The transaction's own `amountCents` is used directly.

#### Missing Price Detection

An item has a missing price when:

```typescript
const missingPrice = !item.projectPriceCents || item.projectPriceCents === 0;
```

Missing-price items are visually flagged in the report with a warning badge: "Missing project price". They contribute `$0.00` to the line total.

#### Transaction Title

Canonical inventory transactions display a canonical title instead of the raw `source` field:

```typescript
function getTransactionTitle(transaction: Transaction): string {
  if (transaction.isCanonicalInventorySale) {
    if (transaction.inventorySaleDirection === 'business_to_project') {
      return 'Design Business Inventory Sale';
    }
    if (transaction.inventorySaleDirection === 'project_to_business') {
      return 'Design Business Inventory Purchase';
    }
  }
  return transaction.source ?? 'Transaction';
}
```

#### Summary Totals

```typescript
const chargesTotalCents = chargeLines.reduce((sum, line) => sum + line.lineTotalCents, 0);
const creditsTotalCents = creditLines.reduce((sum, line) => sum + line.lineTotalCents, 0);
const netAmountDueCents = chargesTotalCents - creditsTotalCents;
```

| Label | Calculation |
|-------|-------------|
| **Charges Total** | Sum of all charge line totals |
| **Credits Total** | Sum of all credit line totals |
| **Net Amount Due** | Charges Total - Credits Total |

A negative net amount due means the design business owes the client overall.

#### Display Structure

```
┌─────────────────────────────────────────┐
│  [Business Logo]                        │
│  Invoice                                │
│  Project Name                           │
│  Client: Client Name                    │
│  Date: Feb 7, 2026                      │
│─────────────────────────────────────────│
│                                         │
│  Project Charges                        │
│  ┌─────────────────────────────────┐   │
│  │ Source Name         Feb 15      │   │
│  │   Notes text                    │   │
│  │   ├ Item A          $1,200.00   │   │
│  │   ├ Item B ⚠Missing  $0.00     │   │
│  │   └ Item C            $800.00   │   │
│  │                     $2,000.00   │   │
│  │─────────────────────────────────│   │
│  │ Source Name 2       Mar 1       │   │
│  │                       $500.00   │   │
│  │─────────────────────────────────│   │
│  │ Charges Total       $2,500.00   │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Project Credits                        │
│  ┌─────────────────────────────────┐   │
│  │ Return              Mar 10      │   │
│  │                       $200.00   │   │
│  │─────────────────────────────────│   │
│  │ Credits Total         $200.00   │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Net Amount Due          $2,300.00      │
└─────────────────────────────────────────┘
```

#### Edge Cases

| Scenario | Behavior |
|----------|----------|
| No invoiceable transactions | Show empty state: "No invoiceable items. There are no qualifying transactions for this project." |
| All invoiceable transactions are credits | Charges section is empty (show header, no lines, $0.00 total). Net Amount Due is negative. |
| Transaction with items but all missing prices | Line total is $0.00. Each item shows warning badge. |
| Null `transactionDate` | Omit date display for that line. Sort to beginning. |
| Null `source` on non-canonical transaction | Display "Transaction" as fallback title. |

---

### Client Summary Report

#### Purpose

Present a client-facing overview of project spending, market value of acquired furnishings, and savings achieved. Includes a line-item list of all project items with receipt links.

#### Summary Calculations

All calculations operate on the full set of project items (no filtering by canceled status -- items are never canceled, only their transactions are).

**Total Spent**:

```typescript
const totalSpentCents = items.reduce((sum, item) => {
  return sum + (item.projectPriceCents ?? 0);
}, 0);
```

**Total Market Value**:

```typescript
const totalMarketValueCents = items.reduce((sum, item) => {
  return sum + (item.marketValueCents ?? 0);
}, 0);
```

**Total Saved**:

The savings calculation sums the per-item difference between market value and project price, but only for items where market value is greater than zero:

```typescript
const totalSavedCents = items.reduce((sum, item) => {
  const marketValue = item.marketValueCents ?? 0;
  const projectPrice = item.projectPriceCents ?? 0;
  if (marketValue > 0) {
    return sum + (marketValue - projectPrice);
  }
  return sum;
}, 0);
```

Items with no market value (null or 0) are excluded from the savings calculation entirely. The savings value can be negative if an item's project price exceeds its market value.

#### Category Breakdown

The Client Summary includes a breakdown of total spending by budget category.

**Category Resolution**: For each item, determine its budget category:

```typescript
function resolveItemCategoryId(item: Item, transactions: Transaction[]): string | null {
  // Prefer item-level budgetCategoryId
  if (item.budgetCategoryId) {
    return item.budgetCategoryId;
  }
  // Fallback: use the linked transaction's budgetCategoryId
  if (item.transactionId) {
    const tx = transactions.find(t => t.id === item.transactionId);
    if (tx?.budgetCategoryId) {
      return tx.budgetCategoryId;
    }
  }
  return null;
}
```

**Aggregation**:

```typescript
const categoryBreakdown: Record<string, number> = {};

items.forEach(item => {
  const categoryId = resolveItemCategoryId(item, transactions);
  if (categoryId) {
    const categoryName = budgetCategoryMap.get(categoryId) ?? 'Unknown Category';
    categoryBreakdown[categoryName] =
      (categoryBreakdown[categoryName] ?? 0) + (item.projectPriceCents ?? 0);
  }
});
```

Categories are displayed sorted alphabetically by name. Items with no resolved category are excluded from the breakdown (their amounts are still included in the overall total).

#### Receipt Link Behavior

Each item in the Furnishings list may include a receipt link. The link resolution follows this priority chain:

```typescript
function getReceiptLink(
  item: Item,
  transactions: Transaction[],
  projectId: string
): ReceiptLink | null {
  if (!item.transactionId) {
    return null; // No linked transaction -> no receipt
  }

  const tx = transactions.find(t => t.id === item.transactionId);
  if (!tx) {
    return null; // Transaction not found
  }

  // 1. Canonical inventory sale or invoiceable transaction -> link to invoice
  const isCanonical = tx.isCanonicalInventorySale === true;
  const isInvoiceable =
    tx.reimbursementType === 'owed-to-company' ||
    tx.reimbursementType === 'owed-to-client';

  if (isCanonical || isInvoiceable) {
    return { type: 'invoice', projectId };
  }

  // 2. Has receipt image with remote URL -> link to receipt
  const receiptUrl = tx.receiptImages?.[0]?.url;
  if (receiptUrl && !receiptUrl.startsWith('offline://')) {
    return { type: 'receipt-url', url: receiptUrl };
  }

  // 3. Has receipt image but local-only -> pending upload notice
  if (receiptUrl && receiptUrl.startsWith('offline://')) {
    return { type: 'pending-upload' };
  }

  // 4. No receipt image -> no link
  return null;
}
```

| Resolution | On-Screen Behavior | PDF Behavior |
|------------|-------------------|-------------|
| `invoice` | Navigates to Invoice report screen | Prints "See Project Invoice" |
| `receipt-url` | Opens URL in browser/viewer | Prints "Receipt available" |
| `pending-upload` | Shows "Receipt pending upload" label | Prints "Receipt pending upload" |
| `null` | No link shown | No receipt text |

#### Display Structure

```
┌─────────────────────────────────────────┐
│  [Business Logo]                        │
│  Client Summary                         │
│  Project Name                           │
│  Client: Client Name                    │
│  Date: Feb 7, 2026                      │
│─────────────────────────────────────────│
│                                         │
│  ┌─────────────────┬─────────────────┐ │
│  │ Project Overview │ Furnishing      │ │
│  │                  │ Savings         │ │
│  │ Total Spent      │                 │ │
│  │ $45,000.00       │ Market Value    │ │
│  │                  │ $68,000.00      │ │
│  │ ── by category ──│                 │ │
│  │ Furnishings      │ What You Spent  │ │
│  │   $35,000.00     │ $45,000.00      │ │
│  │ Install          │                 │ │
│  │   $10,000.00     │ What You Saved  │ │
│  │                  │ $23,000.00      │ │
│  └─────────────────┴─────────────────┘ │
│                                         │
│  Furnishings                            │
│  ┌─────────────────────────────────┐   │
│  │ Sofa - West Elm                 │   │
│  │   Source: West Elm  View Receipt│   │
│  │   Space: Living Room            │   │
│  │                     $2,400.00   │   │
│  │─────────────────────────────────│   │
│  │ Dining Table                    │   │
│  │   Source: Restoration Hardware  │   │
│  │                     $3,200.00   │   │
│  │─────────────────────────────────│   │
│  │ Furnishings Total  $45,000.00   │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

#### Edge Cases

| Scenario | Behavior |
|----------|----------|
| No items in project | Show empty state: "No items found. There are no items associated with this project." |
| All items have zero market value | Savings section shows $0.00 saved. Market Value shows $0.00. |
| Item with no `source` | Omit "Source:" line for that item. |
| Item with no `spaceId` | Omit "Space:" line for that item. |
| `spaceId` references a deleted/archived space | Display space name from cached Space document. If Space document not found, omit space line. |
| Item with no `transactionId` | No receipt link shown. |
| Negative savings (project price > market value) | Display the negative number. Label remains "What You Saved". |

---

### Property Management Summary

#### Purpose

Produce an asset inventory document listing all items in a project with their space assignments and market values. Used for property management, insurance documentation, and asset tracking.

#### Summary Calculations

**Total Item Count**:

```typescript
const totalItemCount = items.length;
```

**Total Market Value**:

```typescript
const totalMarketValueCents = items.reduce((sum, item) => {
  return sum + (item.marketValueCents ?? 0);
}, 0);
```

#### Item List

Each item displays:

| Field | Source | Fallback |
|-------|--------|----------|
| Description | `item.name` | `'Item'` |
| Source | `item.source` | Omitted if null |
| SKU | `item.sku` | Omitted if null |
| Space | Resolved from `item.spaceId` via Space lookup | Omitted if null or unresolvable |
| Market Value | `item.marketValueCents` formatted as USD | `$0.00` with "No market value set" note |

#### Space Resolution

Items reference spaces by ID. The report must resolve space names:

```typescript
function resolveSpaceName(
  spaceId: string | null | undefined,
  spaces: Space[]
): string | null {
  if (!spaceId) return null;
  const space = spaces.find(s => s.id === spaceId);
  return space?.name ?? null;
}
```

#### Display Structure

```
┌─────────────────────────────────────────┐
│  [Business Logo]                        │
│  Property Management Summary            │
│  Project Name                           │
│  Client: Client Name                    │
│  Date: Feb 7, 2026                      │
│─────────────────────────────────────────│
│                                         │
│  Summary                                │
│  ┌─────────────────────────────────┐   │
│  │ Total Items: 24                 │   │
│  │ Total Market Value: $68,000.00  │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Items                                  │
│  ┌─────────────────────────────────┐   │
│  │ Sofa - West Elm                 │   │
│  │   Source: West Elm  SKU: WE-123 │   │
│  │   Space: Living Room            │   │
│  │                     $4,500.00   │   │
│  │─────────────────────────────────│   │
│  │ Side Table                      │   │
│  │   Source: CB2                   │   │
│  │   Space: Bedroom               │   │
│  │          $0.00 No market value  │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

#### Edge Cases

| Scenario | Behavior |
|----------|----------|
| No items in project | Show empty state: "No items found. There are no items associated with this project." |
| `marketValueCents` is `null` or `0` | Display `$0.00` with subtext "No market value set" |
| `spaceId` is null | Omit "Space:" line |
| `spaceId` references a non-existent Space | Omit "Space:" line (fail silently) |
| Item with no `source` and no `sku` | Omit the source/SKU metadata line entirely |

---

## Rendering Pipeline

### Overview

Reports follow a two-stage pipeline: on-screen preview and shareable PDF generation.

```
┌──────────────┐     ┌───────────────┐     ┌──────────────┐     ┌──────────────┐
│  Firestore   │────>│  Data Service  │────>│  React Native│────>│  On-Screen   │
│  Local Cache │     │  (aggregate)   │     │  ScrollView  │     │  Preview     │
└──────────────┘     └───────────────┘     └──────────────┘     └──────────────┘
                            │
                            v
                     ┌───────────────┐     ┌──────────────┐     ┌──────────────┐
                     │  HTML Template │────>│  expo-print  │────>│  Share Sheet  │
                     │  Generator    │     │  (PDF)       │     │  or Print    │
                     └───────────────┘     └──────────────┘     └──────────────┘
```

### Stage 1: On-Screen Preview

The report screen renders a native React Native `ScrollView` displaying the report content using standard React Native components (`View`, `Text`, `Image`). This provides immediate visual feedback while the user decides whether to share or print.

**Key behaviors**:
- Renders instantly from cached data
- Uses the app's theme system for colors and typography
- Includes action buttons (Back, Share, Print) in the screen header
- Scrollable for long reports

### Stage 2: PDF Generation and Distribution

When the user taps Share or Print:

1. **HTML Generation**: `reportHtml.ts` generates a self-contained HTML string with inline CSS for the report. The HTML template mirrors the on-screen layout but is optimized for print (A4/Letter sizing, page breaks, no interactive elements).

2. **PDF Creation**: `expo-print`'s `printToFileAsync` converts the HTML to a PDF file stored in the app's temporary directory.

3. **Distribution**:
   - **Share**: `expo-sharing`'s `shareAsync` opens the native share sheet with the PDF file, allowing the user to email, AirDrop, save to Files, or send via messaging apps.
   - **Print**: `expo-print`'s `printAsync` opens the native print dialog for direct printing to AirPrint (iOS) or cloud print (Android) printers.

```typescript
import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';

async function shareReport(html: string, fileName: string): Promise<void> {
  const { uri } = await Print.printToFileAsync({ html });
  await Sharing.shareAsync(uri, {
    mimeType: 'application/pdf',
    dialogTitle: fileName,
    UTI: 'com.adobe.pdf',
  });
}

async function printReport(html: string): Promise<void> {
  await Print.printAsync({ html });
}
```

### HTML Template Requirements

HTML templates in `reportHtml.ts` must be:

- **Self-Contained**: All CSS inline (no external stylesheets). No external JavaScript.
- **Print-Optimized**: Appropriate margins, page-break rules, font sizing for print.
- **Brand-Styled**: Use the app brand color (`#987e55`) for headers and accent elements.
- **Logo-Embedded**: Business logo embedded as a base64 data URI or remote URL (see [Business Profile Integration](#business-profile-integration)).

**Template structure**:

```typescript
function generateInvoiceHtml(params: {
  businessName: string;
  logoUrl: string | null;
  projectName: string;
  clientName: string;
  date: string;
  chargeLines: InvoiceLine[];
  creditLines: InvoiceLine[];
  chargesTotalCents: number;
  creditsTotalCents: number;
  netAmountDueCents: number;
}): string {
  return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        /* Inline print-optimized styles */
        body { font-family: -apple-system, 'Helvetica Neue', sans-serif; ... }
        @media print { ... }
      </style>
    </head>
    <body>
      <!-- Report content -->
    </body>
    </html>
  `;
}
```

### Currency Formatting

All monetary values use the same formatter:

```typescript
function formatCents(cents: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(cents / 100);
}
```

This converts cents to dollars at the formatting boundary only, preserving integer arithmetic for all calculations.

---

## Offline Behavior

### Data Source

All report data is read from Firestore's local cache. The mobile app uses `@react-native-firebase/firestore` with persistent local cache enabled. Report screens subscribe to the same Firestore collections used elsewhere in the app:

- `accounts/{accountId}/transactions` (scoped by `projectId`)
- `accounts/{accountId}/items` (scoped by `projectId`)
- `accounts/{accountId}/spaces` (scoped by `projectId`)
- `accounts/{accountId}/presets/default/budgetCategories`
- `accounts/{accountId}/profile/default`

Because these collections are already subscribed to by list screens, their data is present in the local cache before the user opens a report.

### No Network Required

Report rendering, PDF generation, and distribution via share sheet all operate without network access:

| Operation | Network Required | Notes |
|-----------|-----------------|-------|
| Data assembly | No | Reads from Firestore cache |
| On-screen preview | No | Native React Native views |
| HTML generation | No | String concatenation |
| PDF creation (`printToFileAsync`) | No | Local WebKit rendering |
| Share sheet (`shareAsync`) | No | Opens native OS dialog |
| Print dialog (`printAsync`) | No | Opens native print picker |
| Actual printing | Yes (usually) | Requires printer connectivity |
| Actual sharing (email, etc.) | Yes | Requires network for delivery |

### Business Logo Offline Handling

The business logo is stored as an `AttachmentRef`. Its `url` field may be:

| URL Pattern | Meaning | Report Behavior |
|-------------|---------|-----------------|
| `https://...` | Uploaded to Firebase Storage | Embed in HTML via `<img src="...">`. In PDF, the renderer fetches the image at generation time. If offline, logo may not render in PDF. |
| `offline://...` | Local-only, pending upload | On-screen preview: resolve to local file path via `resolveAttachmentUri`. HTML/PDF: omit logo and show business name text only. |
| `null` / missing | No logo configured | Omit logo. Show business name text only. |

When the logo URL is `offline://`, the report should display a subtle notice in the on-screen preview: "Business logo pending upload. Share when online for logo to appear in PDF."

---

## Intentional Deltas from Web

The mobile app's reports intentionally differ from the legacy web app in the following ways:

### 1. Native Distribution vs Browser Print

| Aspect | Web App | Mobile App |
|--------|---------|------------|
| Print mechanism | `window.print()` + CSS `@media print` | `expo-print` PDF generation |
| Share mechanism | Not available (print only) | Native share sheet (email, AirDrop, Files, etc.) |
| Print styling | CSS `print:hidden` classes | Separate HTML template (no on-screen/print duality) |

### 2. Cents-Based Amounts

| Aspect | Web App | Mobile App |
|--------|---------|------------|
| Storage | Dollar strings (e.g., `"1200.50"`) | Integer cents (e.g., `120050`) |
| Field names | `item.projectPrice`, `item.marketValue` | `item.projectPriceCents`, `item.marketValueCents` |
| Transaction amount | `transaction.amount` (dollar string) | `transaction.amountCents` (integer) |
| Arithmetic | `parseFloat()` with `toNumber()` helper | Direct integer addition |
| Formatting | `Intl.NumberFormat` on dollar values | `Intl.NumberFormat` on `cents / 100` |

### 3. Space References

| Aspect | Web App | Mobile App |
|--------|---------|------------|
| Storage | `item.space` (free-text string) | `item.spaceId` (FK to Space document) |
| Resolution | Direct display of string value | Look up `Space` document by `spaceId`, display `space.name` |
| Archived spaces | N/A | Must handle gracefully (Space may be archived but still referenced) |

### 4. Item-Level Budget Category

| Aspect | Web App | Mobile App |
|--------|---------|------------|
| Category source | Transaction's `categoryId` only | Prefer `item.budgetCategoryId`, fallback to `transaction.budgetCategoryId` |
| Accuracy | Items from same transaction always share category | Items can have individual categories, more accurate per-item attribution |
| Resolution | `transaction.categoryId` -> category name lookup | `item.budgetCategoryId ?? transaction.budgetCategoryId` -> category name lookup |

### 5. Canonical Inventory Sale Detection

| Aspect | Web App | Mobile App |
|--------|---------|------------|
| Detection | `transactionId.startsWith('INV_SALE_')` or `startsWith('INV_PURCHASE_')` | `isCanonicalInventorySale === true` + `inventorySaleDirection` field |
| Title derivation | Prefix-based string matching | Structured boolean + enum fields |
| Canonical titles | Same display text | Same display text ("Design Business Inventory Sale" / "Design Business Inventory Purchase") |

### 6. Item Linking

| Aspect | Web App | Mobile App |
|--------|---------|------------|
| How items link to transactions | `item.transactionId` matches `transaction.transactionId` | `item.transactionId` matches `transaction.id` (Firestore document ID) |
| Reverse link | Not used in reports | `transaction.itemIds` array available but not used for report generation (forward link preferred) |

---

## Business Profile Integration

### Report Header

All three reports share a common header layout:

```
┌─────────────────────────────────────────┐
│  [Logo Image]  Report Title             │
│                Project Name             │
│                Client: Client Name      │
│                Date: Feb 7, 2026        │
└─────────────────────────────────────────┘
```

**Logo display rules**:

| Condition | On-Screen Preview | HTML/PDF |
|-----------|-------------------|----------|
| Logo URL is `https://...` | `<Image source={{ uri }}` | `<img src="url">` |
| Logo URL is `offline://...` | Resolve to local file path | Omit logo, show business name only |
| Logo is `null` / missing | Omit logo | Omit logo |

**Logo sizing**:
- Maximum height: 96px (on-screen), 72pt (PDF)
- Width: auto (maintain aspect ratio)
- Object fit: contain

**Business name**: Always displayed as text regardless of logo presence. Used as the `alt` text for the logo image.

### Date Display

Reports display today's date (the date the report is generated/viewed), not a stored date:

```typescript
const today = new Date().toLocaleDateString('en-US', {
  year: 'numeric',
  month: 'short',
  day: 'numeric',
}); // e.g., "Feb 7, 2026"
```

---

## Acceptance Criteria

### Invoice Report

- [ ] Only non-canceled transactions with `reimbursementType` of `'owed-to-company'` or `'owed-to-client'` appear
- [ ] "Project Charges" section contains only `'owed-to-company'` transactions
- [ ] "Project Credits" section contains only `'owed-to-client'` transactions
- [ ] Transactions within each section are sorted by `transactionDate` ascending
- [ ] Transactions with linked items show item-level detail with per-item `projectPriceCents`
- [ ] Line total for item-bearing transactions equals sum of `item.projectPriceCents` (not `transaction.amountCents`)
- [ ] Line total for transactions without items equals `transaction.amountCents`
- [ ] Items with null/zero `projectPriceCents` are flagged "Missing project price" and contribute $0
- [ ] Canonical inventory transactions display "Design Business Inventory Sale" or "Design Business Inventory Purchase" title
- [ ] Non-canonical transactions display `source` field as title, falling back to "Transaction"
- [ ] Charges Total equals sum of all charge line totals
- [ ] Credits Total equals sum of all credit line totals
- [ ] Net Amount Due equals Charges Total minus Credits Total
- [ ] Empty state shown when no invoiceable transactions exist
- [ ] Transaction notes displayed when present

### Client Summary Report

- [ ] Total Spent equals sum of `item.projectPriceCents` across all project items
- [ ] Market Value equals sum of `item.marketValueCents` across all project items
- [ ] Saved equals sum of per-item `(marketValueCents - projectPriceCents)` only where `marketValueCents > 0`
- [ ] Category breakdown uses `item.budgetCategoryId` with fallback to `transaction.budgetCategoryId`
- [ ] Category breakdown amounts are sorted alphabetically by category name
- [ ] Items with no resolvable category are excluded from the breakdown but included in overall totals
- [ ] Furnishings list shows all items with `name`, `source`, `space` (resolved from `spaceId`), and `projectPriceCents`
- [ ] Receipt link for canonical/invoiceable transactions navigates to invoice report
- [ ] Receipt link for transactions with remote receipt URL links to the receipt
- [ ] Transactions with local-only receipt (`offline://`) show "Receipt pending upload"
- [ ] Items with no linked transaction show no receipt link
- [ ] Furnishings Total equals Total Spent
- [ ] Empty state shown when no items exist

### Property Management Summary

- [ ] Summary shows total item count and total market value
- [ ] Total market value equals sum of `item.marketValueCents` across all project items
- [ ] Each item shows description, source (if present), SKU (if present), space name (if resolvable), and market value
- [ ] Items with null/zero `marketValueCents` show `$0.00` with "No market value set" note
- [ ] Space names are resolved from `item.spaceId` via Space document lookup
- [ ] Items with no `spaceId` or unresolvable `spaceId` omit the space line
- [ ] Empty state shown when no items exist

### Rendering & Distribution

- [ ] On-screen preview renders in a native ScrollView from Firestore cache
- [ ] Share button generates a PDF via `expo-print` and opens native share sheet via `expo-sharing`
- [ ] Print button opens native print dialog via `expo-print`
- [ ] PDF uses inline CSS with no external dependencies
- [ ] PDF includes business logo when available as remote URL
- [ ] PDF omits logo gracefully when logo is `offline://` or null
- [ ] PDF uses brand color (`#987e55`) for headings and accent elements
- [ ] Currency values formatted as USD with `Intl.NumberFormat`
- [ ] All arithmetic uses integer cents (no floating-point dollar math)

### Business Profile

- [ ] Report header shows business logo (when available and uploaded)
- [ ] Report header shows business name
- [ ] Report header shows project name and client name
- [ ] Report header shows today's date in "Mon D, YYYY" format
- [ ] Offline logo (`offline://`) triggers informational message in on-screen preview

### Offline

- [ ] All three reports render fully offline from Firestore local cache
- [ ] PDF generation works offline (no network calls)
- [ ] Share sheet opens offline (delivery requires network)
- [ ] Print dialog opens offline (printing requires printer connectivity)
- [ ] No error states triggered by lack of network connectivity

### Navigation

- [ ] Invoice report is accessible from project context
- [ ] Client Summary report is accessible from project context
- [ ] Property Management Summary is accessible from project context
- [ ] Back button navigates to the originating screen

---

## Implementation Targets

### Data Layer

| File | Purpose |
|------|---------|
| `src/data/reportDataService.ts` | Aggregate report data from Firestore subscriptions. Provides functions like `buildInvoiceData()`, `buildClientSummaryData()`, `buildPropertyManagementData()` that accept raw transactions, items, spaces, and budget categories and return structured report data. |

### HTML Generation

| File | Purpose |
|------|---------|
| `src/utils/reportHtml.ts` | HTML template generators for each report type. Exports `generateInvoiceHtml()`, `generateClientSummaryHtml()`, `generatePropertyManagementHtml()`. Each returns a self-contained HTML string for PDF rendering. Includes shared helper for currency formatting, header template, and inline CSS. |

### Screen Components

| File | Purpose |
|------|---------|
| `src/screens/ProjectInvoiceReport.tsx` | Invoice report screen. Subscribes to project data, calls `buildInvoiceData()`, renders on-screen preview, handles Share/Print actions. |
| `src/screens/ProjectClientSummaryReport.tsx` | Client Summary report screen. Subscribes to project data + budget categories, calls `buildClientSummaryData()`, renders on-screen preview with receipt links, handles Share/Print actions. |
| `src/screens/ProjectPropertyManagementReport.tsx` | Property Management Summary screen. Subscribes to project data + spaces, calls `buildPropertyManagementData()`, renders on-screen preview, handles Share/Print actions. |

### Expo Router Pages

| File | Purpose |
|------|---------|
| `app/project/[projectId]/invoice.tsx` | Route entry for Invoice report. Extracts `projectId` param, renders `ProjectInvoiceReport`. |
| `app/project/[projectId]/client-summary.tsx` | Route entry for Client Summary report. Extracts `projectId` param, renders `ProjectClientSummaryReport`. |
| `app/project/[projectId]/property-management-summary.tsx` | Route entry for Property Management Summary. Extracts `projectId` param, renders `ProjectPropertyManagementReport`. |

### Dependencies

| Package | Purpose | Already Installed |
|---------|---------|-------------------|
| `expo-print` | HTML-to-PDF conversion and native print dialog | Check `package.json` |
| `expo-sharing` | Native share sheet for PDF files | Check `package.json` |

---

**End of Specification**
