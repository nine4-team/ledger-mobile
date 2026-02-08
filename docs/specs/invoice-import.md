# Invoice Import Specification

**Version**: 1.0
**Date**: 2026-02-07
**Status**: Draft

---

## Table of Contents

1. [Overview](#overview)
2. [Goals & Principles](#goals--principles)
3. [Data Model](#data-model)
4. [Import Flow](#import-flow)
5. [Vendor-Specific Behavior](#vendor-specific-behavior)
6. [PDF Extraction Architecture](#pdf-extraction-architecture)
7. [Draft Editing](#draft-editing)
8. [Creation Workflow (Offline-First)](#creation-workflow-offline-first)
9. [Media Handling](#media-handling)
10. [Debug Tooling](#debug-tooling)
11. [Intentional Deltas from Web](#intentional-deltas-from-web)
12. [Edge Cases & Validation](#edge-cases--validation)
13. [Acceptance Criteria](#acceptance-criteria)
14. [Implementation Targets](#implementation-targets)

---

## Overview

Invoice Import enables users to import Amazon and Wayfair PDF invoices into draft transactions with line items, eliminating manual data entry for vendor purchases. The feature:

- Extracts text (and optionally embedded images) from vendor invoice PDFs entirely on-device
- Parses extracted text using vendor-specific parsers to produce structured line item data
- Presents a draft transaction with pre-populated fields for user review and editing
- Creates the transaction and items via the request-doc workflow for offline-first reliability

**Legacy Reference**: The web app implements this feature in `src/pages/ImportAmazonInvoice.tsx` and `src/pages/ImportWayfairInvoice.tsx`, with parsers in `src/utils/amazonInvoiceParser.ts` and `src/utils/wayfairInvoiceParser.ts`. The mobile implementation ports the same parsing logic but adapts file selection, PDF extraction, and creation to mobile constraints.

---

## Goals & Principles

### Primary Goals

1. **Offline-First**: PDF parsing and draft preparation require zero network access. Creation queues via request-doc when offline.
2. **Local Parsing**: All text extraction and vendor-specific parsing runs on-device. No PDF data is sent to any server for extraction.
3. **No Server Dependency for Extraction**: The pdf.js library runs inside a hidden WebView bridge; there is no cloud function involved in parsing.
4. **Request-Doc for Creation**: Transaction + items creation uses the idempotent request-doc workflow, matching the mobile app's established pattern for offline-safe writes.
5. **Parser Parity**: The Amazon and Wayfair parsers must produce identical results to the legacy web parsers for the same input text, ensuring consistent import quality.

### Design Principles

- **Deterministic Parsing**: Same PDF text input always produces the same parse result. No AI/ML involved.
- **Non-Destructive Drafts**: Nothing is persisted until the user explicitly taps "Create". Drafts are ephemeral screen state.
- **Graceful Degradation**: Parsing warnings are non-blocking (except Amazon wrong-vendor detection). Users can always review and edit before creating.
- **Transparency**: Debug tooling (parse report, raw text preview) is always available for troubleshooting parse issues.

---

## Data Model

### Amazon Line Item

```typescript
type AmazonInvoiceLineItem = {
  description: string;
  qty: number;
  unitPrice?: string;       // Dollar string, e.g. "12.99"
  total: string;            // Dollar string, e.g. "25.98"
  shippedOn?: string;       // YYYY-MM-DD
};
```

### Amazon Parse Result

```typescript
type AmazonInvoiceParseResult = {
  orderNumber?: string;
  orderPlacedDate?: string;   // YYYY-MM-DD
  grandTotal?: string;        // Dollar string, e.g. "125.47"
  projectCode?: string;       // Rarely present; extracted if available
  paymentMethod?: string;     // e.g. "Visa | Last digits: 1234"
  tax?: string;               // Dollar string
  shipping?: string;          // Dollar string
  lineItems: AmazonInvoiceLineItem[];
  warnings: string[];
};
```

**Legacy Reference**: `src/utils/amazonInvoiceParser.ts` lines 3-21.

---

### Wayfair Line Item

```typescript
type WayfairInvoiceLineItem = {
  description: string;
  sku?: string;              // Wayfair item code, e.g. "W004170933"
  qty: number;
  unitPrice?: string;        // Dollar string
  subtotal?: string;         // Dollar string
  shipping?: string;         // Dollar string (per-line shipping)
  adjustment?: string;       // Dollar string (absolute value; original may be negative)
  tax?: string;              // Dollar string (per-line tax)
  total: string;             // Dollar string
  attributeLines?: string[]; // Raw attribute lines, e.g. ["Fabric: Linen", "Color: Taupe"]
  attributes?: {
    color?: string;
    size?: string;
  };
  shippedOn?: string;        // YYYY-MM-DD
  section?: 'shipped' | 'to_be_shipped' | 'unknown';
};
```

### Wayfair Parse Result

```typescript
type WayfairInvoiceParseResult = {
  invoiceNumber?: string;
  orderDate?: string;              // YYYY-MM-DD
  invoiceLastUpdated?: string;
  orderTotal?: string;             // Dollar string
  subtotal?: string;               // Dollar string
  shippingDeliveryTotal?: string;  // Dollar string
  taxTotal?: string;               // Dollar string
  adjustmentsTotal?: string;       // Dollar string (may be negative)
  calculatedSubtotal?: string;     // orderTotal - taxTotal
  lineItems: WayfairInvoiceLineItem[];
  warnings: string[];
};
```

**Legacy Reference**: `src/utils/wayfairInvoiceParser.ts` lines 1-38.

---

### Money Utilities

Both parsers depend on two shared money functions:

```typescript
/**
 * Normalizes a money string to a two-decimal string.
 * Handles: "$12.34", "-$12.34", "(12.34)", "($12.34)", "1,234.56"
 * Returns undefined if the input cannot be parsed.
 */
function normalizeMoneyToTwoDecimalString(input: string): string | undefined;

/**
 * Parses a money string to a number.
 * Returns undefined if the input cannot be parsed.
 */
function parseMoneyToNumber(input: string | undefined): number | undefined;
```

**Legacy Reference**: `src/utils/money.ts`.

---

### PDF Text Extraction Result

```typescript
type PdfTextExtractionResult = {
  pages: string[];    // Per-page reconstructed text
  fullText: string;   // All pages joined with double-newline
};
```

---

### PDF Embedded Image Placement (Wayfair Only)

```typescript
type PdfEmbeddedImagePlacement = {
  pageNumber: number;
  bbox: { xMin: number; yMin: number; xMax: number; yMax: number };
  pixelWidth: number;
  pixelHeight: number;
  pageHeight: number;
  /** Base64-encoded PNG data URI (on mobile, replaces the web File object) */
  dataUri: string;
};
```

**Legacy Reference**: `src/utils/pdfEmbeddedImageExtraction.ts` lines 1-10. The mobile type replaces `file: File` with `dataUri: string` since React Native does not use the browser `File` API.

---

### Draft Item (Screen State, Not Persisted)

```typescript
type ImportItemDraft = {
  id: string;                          // Local UUID for list key
  description: string;
  purchasePrice: string;               // Dollar string
  price: string;                       // Dollar string (same as purchasePrice for import)
  sku?: string;
  notes?: string;
  taxAmountPurchasePrice?: string;     // Dollar string (Wayfair only)
  thumbnailDataUri?: string;           // Base64 PNG (Wayfair only)
};
```

---

### Request-Doc Payload for Import

```typescript
type ImportTransactionRequestPayload = {
  transaction: {
    projectId: string;
    transactionDate: string;            // YYYY-MM-DD
    source: 'Amazon' | 'Wayfair';
    transactionType: 'Purchase';
    purchasedBy?: string;
    amountCents: number;
    budgetCategoryId?: string;
    notes?: string;
    taxRatePct?: number;
    subtotalCents?: number;
  };
  items: Array<{
    name: string;
    purchasePriceCents: number;
    projectPriceCents: number;
    sku?: string;
    notes?: string;
    source: 'Amazon' | 'Wayfair';
  }>;
};
```

---

## Import Flow

### Step-by-Step

1. **Entry Point**: From a project's transactions list, the user taps the "Add" button in the control bar. This opens a bottom sheet with two top-level options: "Create New" (to manually create a transaction) and "Import from Invoice". Tapping "Import from Invoice" expands to reveal vendor-specific options: "Amazon" and "Wayfair". Selecting a vendor navigates to the corresponding import screen, passing `projectId` as a route parameter. The import options only appear in project scope (not in business inventory).

2. **File Selection**: The import screen presents a "Select PDF" button. Tapping it opens `expo-document-picker` configured with:
   ```typescript
   DocumentPicker.getDocumentAsync({
     type: 'application/pdf',
     copyToCacheDirectory: true,
   });
   ```
   The returned URI points to a cached copy of the selected file.

3. **PDF Text Extraction**: The selected file's content is read as base64 and sent to the hidden WebView bridge (see [PDF Extraction Architecture](#pdf-extraction-architecture)). The bridge returns:
   - Text extraction result (`PdfTextExtractionResult`)
   - For Wayfair: embedded image placements (`PdfEmbeddedImagePlacement[]`)

4. **Vendor-Specific Parsing**: The extracted `fullText` is passed to the appropriate parser:
   - `parseAmazonInvoiceText(fullText)` -> `AmazonInvoiceParseResult`
   - `parseWayfairInvoiceText(fullText)` -> `WayfairInvoiceParseResult`

5. **Parse Summary + Warnings Display**: The screen displays a summary header showing the invoice/order identifier, parsed totals, and line item count. Any parser warnings are shown in an amber alert box. For Amazon, a "Not an Amazon invoice" warning blocks creation.

6. **Draft Review/Edit Screen**: Parsed data populates editable draft fields for the transaction and its items. The user can modify any field before creating.

7. **Create via Request-Doc**: When the user taps "Create Transaction", the app writes a request-doc to Firestore and enqueues media uploads via the offline media lifecycle.

---

### Screen Navigation

**Expo Router Paths**:
- Amazon: `app/project/[projectId]/import-amazon.tsx`
- Wayfair: `app/project/[projectId]/import-wayfair.tsx`

**Screen Components**:
- Amazon: `src/screens/ImportAmazonInvoice.tsx`
- Wayfair: `src/screens/ImportWayfairInvoice.tsx`

---

## Vendor-Specific Behavior

### Amazon

**Vendor Detection**:
The parser checks for Amazon invoice signatures before parsing:
```typescript
function isAmazonInvoice(fullText: string): boolean {
  const hasOrderNumber = /Amazon\.com order number:/i.test(fullText);
  const hasFinalDetails = /Final Details for Order #/i.test(fullText);
  const hasOrderPlacedAndAmazon =
    /Order Placed:/i.test(fullText) && /Amazon\.com/i.test(fullText);
  return hasOrderNumber || hasFinalDetails || hasOrderPlacedAndAmazon;
}
```
If detection fails, the parser returns `warnings: ['Not an Amazon invoice']` with zero line items. This warning **blocks creation** -- the "Create Transaction" button is disabled and an error message is displayed.

**Legacy Reference**: `src/utils/amazonInvoiceParser.ts` lines 102-108.

**Line Item Parsing**:
- Items are detected by the pattern `<qty> of: <description>` (e.g., `3 of: USB Cable 6ft`)
- The price may appear at the end of the description line or on a subsequent line
- Lines matching `IGNORE_LINES` patterns (e.g., `Sold by:`, `Condition:`, `Business Price`) are skipped
- Address blocks (between `Shipping Address:` and the next item/section boundary) are skipped entirely
- Shipment boundaries are detected by `Shipped on <date>` lines

**Quantity Expansion**:
Amazon items with `qty > 1` are expanded into individual item drafts. For example, `qty=3` produces 3 separate items, each with the per-unit price. Items are **not** grouped (each gets a unique `uiGroupKey`).

**Per-Unit Price Calculation**:
```typescript
const perUnitPurchasePrice = unitPriceNum !== undefined
  ? unitPriceNum
  : (totalNum !== undefined ? totalNum / qty : 0);
```

**Item Notes**:
Notes include the shipped date (if available) and an "Amazon import" label:
```
"Amazon shipped on 2026-01-15 * Amazon import"
```

**Transaction Notes**:
```
"Amazon import * Order # 123-4567890-1234567 * Order date: 2026-01-15"
```

**Total Validation**:
After parsing, the parser computes `sum(lineItem.total) + tax + shipping` and compares to `grandTotal`. If the difference exceeds $0.05, a warning is emitted.

**Legacy Reference**: `src/utils/amazonInvoiceParser.ts` (full file, ~344 lines), `src/pages/ImportAmazonInvoice.tsx` lines 48-111.

---

### Wayfair

**Line Item Parsing (State Machine)**:
The Wayfair parser is significantly more complex than Amazon due to:
- Multi-line item descriptions (buffered across up to 8 lines)
- SKU lines that can appear before or after the money row
- Attribute lines (e.g., `Color: Taupe`, `Size: King`) that attach to the nearest item
- Table header detection and stripping (merged headers at page breaks)
- Shipped vs. to-be-shipped section detection
- Multiple money columns per row (unit price, qty, subtotal, shipping, adjustment, tax, total)

The parser operates as a line-by-line state machine with the following state:
- `bufferedDescriptionParts: string[]` -- accumulated description fragments
- `pendingSku: string | undefined` -- SKU detected but not yet attached to a money row
- `pendingAttributes: { color?: string; size?: string }` -- structured attributes awaiting attachment
- `pendingAttributeLines: string[]` -- raw attribute lines awaiting attachment
- `allowLooseContinuationForPreviousItem: boolean` -- whether continuation lines can append to the previous item
- `awaitingPostMoneyContinuation: boolean` -- whether we just parsed a money row and are in the trailing block
- `lastItemAwaitingSku: WayfairInvoiceLineItem | undefined` -- pointer to item that still needs a SKU

**Legacy Reference**: `src/utils/wayfairInvoiceParser.ts` lines 755-1301.

**SKU Capture**:
SKUs are detected in multiple positions:
1. Standalone SKU line: matches `/^(?=.*[A-Za-z])(?=.*\d)[A-Za-z0-9-]{6,20}$/` (e.g., `W004170933`)
2. Leading SKU on a money row: SKU token followed by multiple money columns
3. SKU prefix on a description line: first token matches SKU pattern
4. Trailing SKU on a description line: last token matches SKU pattern

**Attribute Lines**:
Lines matching `Key: Value` pattern (e.g., `Fabric: Linen`, `Color: Taupe`, `Size: 30" x 30"`) are captured in `attributeLines[]` and, for `color` and `size`, in the structured `attributes` object. Order-level attributes (e.g., `Payment Type`, `Billing Address`) are filtered out via prefix/exact-match lists.

**Smart Grouping by SKU + Normalized Price**:
Items with the same non-empty SKU and the same normalized price share a `uiGroupKey`, causing them to be visually grouped in the draft items list. Items with no SKU get unique keys (no grouping).

```typescript
if (normalizedSku) {
  const normalizedPrice = (template.purchasePrice || template.price || '')
    .trim().toLowerCase().replace(/[^0-9.-]/g, '');
  uiGroupKey = [normalizedSku, normalizedPrice].join('|');
} else {
  uiGroupKey = `unique-${Math.random()}`;
}
```

**Embedded Thumbnail Extraction**:
The Wayfair parser extracts product thumbnail images embedded in the PDF. This uses the WebView Canvas approach (see [PDF Extraction Architecture](#pdf-extraction-architecture)).

Thumbnail processing pipeline:
1. **Candidate identification**: Walk the PDF operator list and find `paintImageXObject` operations whose bounding box matches Wayfair thumbnail heuristics:
   - Width: 15-180 PDF points
   - Height: 15-180 PDF points
   - Left edge (`xMin`) <= 220 PDF points
   - Aspect ratio <= 2.3 (filters out logos/wordmarks)
2. **Page rendering**: Render each page containing candidates to a Canvas at 2x scale
3. **Cropping**: Crop each candidate's bounding box from the rendered page
4. **Header filtering**: Drop images near the top of page 1 that are extremely wide or very short (likely logos)
5. **Score-based normalization**: If more images than line items, score each by area, aspect ratio, position, and drop lowest-scoring extras
6. **Matching**: Remaining thumbnails are matched to line items by reading order (page ascending, y descending, x ascending)

**Scoring function** (per placement):

| Criterion | Score |
|-----------|-------|
| Area >= 4000 sq pts | +2 |
| Area >= 9000 sq pts | +1 |
| Both width and height >= 40 pts | +1 |
| xMin <= 240 pts | +1 |
| Aspect ratio 0.7-1.5 (square-ish) | +2 |
| Aspect ratio >= 2.2 or <= 0.5 (elongated) | -3 |
| Page 1 and yMax >= 650 (header band) | -4 |
| Width or height < 35 pts | -2 |

**Legacy Reference**: `src/utils/pdfEmbeddedImageExtraction.ts` (full file, ~418 lines), `src/pages/ImportWayfairInvoice.tsx` lines 224-368.

**Tax Per-Unit Handling**:
Each line item's `tax` field is captured as per-unit tax and stored in `taxAmountPurchasePrice` on the item draft:
```typescript
const taxPerUnit = taxNum / qty;
const perUnitTaxMoney = normalizeMoneyToTwoDecimalString(String(taxPerUnit)) || undefined;
```

**Per-Unit Price Calculation (Wayfair)**:
Wayfair price calculation accounts for adjustments and shipping:
```typescript
const perUnitPurchasePrice = unitPriceNum !== undefined
  ? (unitPriceNum - adjustmentPerUnit + shippingPerUnit)
  : (perUnitFromTotal ?? totalNum ?? 0);
```

**Shipped vs. To-Be-Shipped Sections**:
The parser tracks section transitions:
- `Shipped On <date>` -> section = `'shipped'`, captures shipped date
- `Items to be Shipped` / `To be Shipped` -> section = `'to_be_shipped'`, clears shipped date

Section is stored on each line item and included in item notes:
- Shipped: `"Wayfair shipped on 2026-01-15"`
- To-be-shipped: `"Wayfair: items to be shipped"`

**Inline Tax/Subtotal Handling**:
When both `orderTotal` and `taxTotal` are parsed, the parser computes `calculatedSubtotal = orderTotal - taxTotal`. This is used to auto-fill the transaction's `subtotal` field and set `taxRatePreset = 'Other'`.

**Item Notes (Wayfair)**:
Notes are constructed from shipped date, section, and attribute lines:
```
"Wayfair shipped on 2026-01-15 * Fabric: Linen * Color: Taupe * Size: King"
```
If no specific note parts exist, defaults to `"Wayfair import"`.

**Transaction Notes (Wayfair)**:
```
"Wayfair import * Invoice # 123456789 * Order date: 2026-01-15"
```

---

## PDF Extraction Architecture

### Why a WebView Bridge

pdf.js (`pdfjs-dist`) is a browser-only library that requires DOM APIs (`document`, `canvas`, Web Workers). React Native does not provide a browser DOM or Web Worker environment. Rather than using a native PDF parsing library (which would require rewriting the text reconstruction and image extraction logic), the mobile app uses a hidden `<WebView>` that runs a bundled HTML page containing `pdfjs-dist`. This ensures:

1. **Parser compatibility**: The `buildTextLinesFromPdfTextItems` function produces identical output to the web app, so the same vendor-specific parsers work without modification.
2. **Image extraction**: Canvas-based page rendering and cropping for Wayfair thumbnails uses the same logic as the web app.
3. **Single codebase**: The pdf.js extraction code is maintained in one place (the bundled HTML), not forked across platforms.

### Architecture

```
┌──────────────────────┐         ┌──────────────────────────────┐
│  React Native Screen │         │  Hidden WebView              │
│                      │         │  (pdfExtractionWebView.html) │
│  1. Read PDF as      │         │                              │
│     base64           │  ────>  │  2. Receive base64 via       │
│                      │ postMsg │     postMessage               │
│                      │         │                              │
│                      │         │  3. Decode to ArrayBuffer    │
│                      │         │                              │
│                      │         │  4. pdf.js getDocument()     │
│                      │         │                              │
│                      │         │  5. Extract text items per   │
│                      │         │     page, reconstruct lines  │
│                      │         │     via buildTextLinesFrom   │
│                      │         │     PdfTextItems()           │
│                      │         │                              │
│                      │         │  6. (Wayfair) Walk operator  │
│                      │         │     list, render pages to    │
│                      │         │     canvas, crop thumbnails, │
│                      │         │     encode as data URIs      │
│                      │  <────  │                              │
│  7. Receive result   │ postMsg │  7. Post result back         │
│     via onMessage    │         │                              │
│                      │         │                              │
│  8. Parse text with  │         │                              │
│     vendor parser    │         │                              │
└──────────────────────┘         └──────────────────────────────┘
```

### Communication Protocol

**Request (React Native -> WebView)**:
```typescript
type PdfExtractionRequest = {
  id: string;                    // Correlation ID for matching response
  action: 'extractText' | 'extractTextAndImages';
  pdfBase64: string;             // Base64-encoded PDF content
  imageOptions?: {               // Only for 'extractTextAndImages'
    pdfBoxSizeFilter?: { min: number; max: number };
    xMinMax?: number;
    maxAspectRatio?: number;
    renderScale?: number;
  };
};
```

**Response (WebView -> React Native)**:
```typescript
type PdfExtractionResponse = {
  id: string;                    // Matches request correlation ID
  success: boolean;
  error?: string;
  text?: PdfTextExtractionResult;
  images?: PdfEmbeddedImagePlacement[];   // Only for 'extractTextAndImages'
  stats?: {
    pageCount: number;
    charCount: number;
    durationMs: number;
  };
};
```

### Text Line Reconstruction

The `buildTextLinesFromPdfTextItems` function is critical for parser compatibility. It:

1. Extracts `(x, y)` coordinates from each `TextItem.transform` matrix (`e=x`, `f=y` in PDF space)
2. Filters out empty tokens
3. Sorts top-to-bottom (higher y first), then left-to-right
4. Groups tokens into lines using a `yTolerance` of 2 PDF points (tokens within 2 points vertically are on the same line)
5. Within each line, sorts tokens by x coordinate
6. Joins tokens with spaces, normalizes whitespace

This reconstruction ensures tabular data (quantities, prices) stays on the same line as the item description, which is required for the parsers to detect line items.

**Legacy Reference**: `src/utils/pdfTextExtraction.ts` lines 51-81.

### Bridge Component

```
src/invoice-import/PdfExtractionBridge.tsx
```

The bridge component renders a hidden `<WebView>` (zero-size, off-screen) and exposes an imperative API:

```typescript
type PdfExtractionBridgeRef = {
  extractText(pdfBase64: string): Promise<PdfTextExtractionResult>;
  extractTextAndImages(
    pdfBase64: string,
    imageOptions?: PdfExtractionRequest['imageOptions']
  ): Promise<{
    text: PdfTextExtractionResult;
    images: PdfEmbeddedImagePlacement[];
  }>;
};
```

The bridge manages:
- Loading state (waits for WebView to signal ready)
- Request/response correlation via unique IDs
- Timeout handling (30-second timeout per extraction)
- Error propagation from WebView to React Native

### Bundled HTML

```
src/invoice-import/pdfExtractionWebView.html
```

This file is a self-contained HTML page that includes:
- `pdfjs-dist` (bundled inline or loaded from a local asset)
- The `buildTextLinesFromPdfTextItems` function (identical to the web utility)
- Image extraction logic (operator list walking, canvas rendering, cropping)
- Message handler that receives requests and posts responses

The HTML file is loaded into the WebView via `require()` as a static asset (configured in Metro bundler).

---

## Draft Editing

After parsing, the import screen displays editable draft fields. All draft state is ephemeral (React state only). Nothing is persisted until the user taps "Create Transaction".

### Transaction Fields

| Field | Source | Editable | Notes |
|-------|--------|----------|-------|
| Transaction Date | `orderPlacedDate` / `orderDate` | Yes | Falls back to today if not parsed |
| Amount | `grandTotal` / `orderTotal` or sum of line totals | Yes | Dollar string |
| Budget Category | User selection | Yes | Required for creation |
| Purchased By | User selection | Yes | Defaults to current user |
| Payment Method | `paymentMethod` or default | Yes | Radio: "Client Card" / company name |
| Notes | Auto-generated from parse result | Yes | Editable textarea |
| Calculated Subtotal | `calculatedSubtotal` (Wayfair only) | Yes | Shown only when `taxRatePreset = 'Other'` |

### Item Fields

| Field | Source | Editable | Notes |
|-------|--------|----------|-------|
| Description | `lineItem.description` | Yes | Required; must be non-empty |
| Purchase Price | Computed per-unit price | Yes | Must be >= 0 |
| SKU | `lineItem.sku` (Wayfair only) | Yes | Optional |
| Notes | Auto-generated from attributes/dates | Yes | Editable |
| Tax (Purchase) | Per-unit tax (Wayfair only) | Yes | Optional |
| Thumbnail | Extracted image (Wayfair only) | No | Display only; removable |

### Amazon Item Expansion

Amazon items with `qty > 1` are expanded into individual items before populating the draft list:

```typescript
// qty=3 for "USB Cable" produces:
[
  { description: "USB Cable", purchasePrice: "4.99", ... },
  { description: "USB Cable", purchasePrice: "4.99", ... },
  { description: "USB Cable", purchasePrice: "4.99", ... },
]
```

Each expanded item gets its own unique ID but shares the same description and price.

---

## Creation Workflow (Offline-First)

### Request-Doc Pattern

When the user taps "Create Transaction", the app writes a request-doc to Firestore:

```typescript
const opId = generateRequestOpId();

await createRequestDoc(
  'import-transaction',
  {
    transaction: {
      projectId,
      transactionDate,
      source: 'Amazon',  // or 'Wayfair'
      transactionType: 'Purchase',
      purchasedBy,
      amountCents: Math.round(parseFloat(amount) * 100),
      budgetCategoryId: categoryId || undefined,
      notes: notes || undefined,
      taxRatePct: taxRatePct || undefined,
      subtotalCents: subtotalCents || undefined,
    },
    items: items.map(item => ({
      name: item.description,
      purchasePriceCents: Math.round(parseFloat(item.purchasePrice) * 100),
      projectPriceCents: Math.round(parseFloat(item.price) * 100),
      sku: item.sku || undefined,
      notes: item.notes || undefined,
      source: 'Amazon',  // or 'Wayfair'
    })),
  },
  { accountId, projectId },
  opId
);
```

**Firestore Path**: `accounts/{accountId}/projects/{projectId}/requests/{requestId}`

**Legacy Reference**: `src/data/requestDocs.ts` for the request-doc infrastructure.

### Cloud Function Processing

A Cloud Function (`onRequestDocCreated`) listens for new request-docs of type `import-transaction` and:

1. Creates the transaction document at `accounts/{accountId}/transactions/{transactionId}`
2. Creates item documents at `accounts/{accountId}/items/{itemId}` for each item in the payload
3. Links items to the transaction via `itemIds` array on the transaction
4. Sets `status: 'applied'` on the request-doc
5. On error, sets `status: 'failed'` with `errorCode` and `errorMessage`

### Idempotency

The `opId` field on the request-doc prevents double-creation if the user retries while offline:
- If a request-doc with the same `opId` already exists and has `status: 'applied'`, the Cloud Function skips processing
- If `status: 'pending'`, the Cloud Function processes normally
- The client generates `opId` via `generateRequestOpId()` (UUID) before writing

### Offline Behavior

When the device is offline:
1. The Firestore SDK queues the request-doc write locally
2. The UI shows "Created (pending sync)" feedback
3. When connectivity resumes, Firestore syncs the write to the server
4. The Cloud Function fires and processes the request
5. The request-doc's `status` updates to `'applied'` (or `'failed'`), which the client can observe via `subscribeToRequest()`

---

## Media Handling

### Receipt PDF

The selected invoice PDF is saved as a receipt attachment on the transaction:

1. **Save locally**: `saveLocalMedia({ localUri: pdfUri, mimeType: 'application/pdf', ownerScope: transactionScope })`
   - Returns `{ mediaId, attachmentRef }` with `attachmentRef.url = "offline://<mediaId>"`
   - Status: `local_only`
2. **Enqueue upload**: `enqueueUpload({ mediaId, destinationPath: receipts/<transactionId>/invoice.pdf })`
   - Creates an `UploadJob` with status `queued`
3. **Include in request-doc**: The `attachmentRef` is included in the transaction payload so the receipt is linked immediately (even before upload completes)
4. **Background upload**: `processUploadQueue()` runs the upload handler, updating status: `local_only` -> `uploading` -> `uploaded` (or `failed`)

**Legacy Reference**: `src/offline/media/mediaStore.ts` for the full lifecycle.

### Wayfair Thumbnails

Each extracted thumbnail follows the same lifecycle as the receipt PDF:

1. The WebView bridge returns thumbnail data as base64 data URIs
2. Each data URI is written to the local filesystem via `FileSystem.writeAsStringAsync()`
3. `saveLocalMedia()` + `enqueueUpload()` for each thumbnail
4. Upload concurrency is limited to **4 concurrent uploads** (matching the web app's `WAYFAIR_ASSET_UPLOAD_CONCURRENCY`)
5. After upload, the item's `images` field is updated with the remote URL

### Upload Concurrency

The media lifecycle processes uploads sequentially by default via `processUploadQueue()`. For Wayfair imports with multiple thumbnails, the import screen may batch-enqueue uploads and trigger processing. The upload handler respects the queue ordering.

### Failure Handling

- If a thumbnail upload fails, the error is stored on the `UploadJob` and `MediaRecord`
- The UI shows: "Wayfair uploads finished with N issue(s). Open the transaction to retry."
- Users can retry from the transaction detail screen, which calls `retryPendingUploads()`
- Receipt upload failures are handled independently of thumbnail failures

### Attachment States

```
local_only ──> uploading ──> uploaded
                   │
                   └──> failed ──> (retry) ──> uploading ──> ...
```

| Status | Meaning |
|--------|---------|
| `local_only` | File saved to local cache, not yet uploaded |
| `uploading` | Upload in progress |
| `uploaded` | Successfully uploaded; `remoteUrl` available |
| `failed` | Upload failed; `lastError` contains reason |

---

## Debug Tooling

### Parse Summary Header

Displayed immediately after parsing, before the draft edit form:

**Amazon**:
```
Order Number: #123-4567890-1234567
Order total (parsed): $125.47
Detected line items: 3
```

**Wayfair**:
```
Invoice: #987654321
Order total (parsed): $2,345.67
  Tax Total: $187.65
Detected line items: 8 (shipped 6, to-be-shipped 2)
  SKU: 7/8 * Attributes: 5/8
```

### Warnings Display

Parser warnings are shown in an amber alert box below the summary. Warnings are non-blocking except for Amazon's "Not an Amazon invoice" which blocks creation.

Common warnings:
- `"Could not confidently find an order number."`
- `"Could not confidently find an order date; defaulting to today is recommended."`
- `"Missing order total"`
- `"No line items were detected. The PDF may be image-based or the template changed."`
- `"Line totals ($X.XX) do not match order total ($Y.YY). Difference: $Z.ZZ."`
- `"Could not find unit price for item: <description>"`
- `"Detected N embedded thumbnail(s) but parsed M line item(s). Matching will be partial; please review."`

### Debug Disclosure

A collapsible "Parse report (debug)" section contains:

1. **Copy JSON**: Copies the full parse report to the clipboard (via `Clipboard.setStringAsync()` on mobile)
2. **Share JSON**: Opens the system share sheet with the parse report as a JSON file (via `Sharing.shareAsync()`)
3. **Parsed line items (compact)**: Scrollable list of all parsed line items showing description, SKU, qty, total, and attributes
4. **Raw extracted text preview**: Numbered lines of the raw extracted PDF text with configurable line limits:
   - Options: 200 / 400 / 800 / 1600 / All
   - Default: 400
5. **Extraction stats**: Page count, character count, non-empty line count, parse duration

**Parse Report JSON Structure**:
```typescript
{
  generatedAt: string;           // ISO 8601
  file: {
    name: string;
    size: number;
    type: string;
  };
  extraction: {
    pageCount: number;
    charCount: number;
    nonEmptyLineCount: number;
    firstLines: string[];        // First 600 non-empty lines
  };
  images?: {                     // Wayfair only
    embeddedPlacementsCount: number;
    thumbnailDebug: {
      extractedCount: number;
      headerDropCount: number;
      extraDropCount: number;
      finalMatchCount: number;
      placements: Array<{
        pageNumber: number;
        bbox: { xMin; yMin; xMax; yMax };
        pageHeight: number;
        width: number;
        height: number;
        score: number;
      }>;
    };
  };
  parse: AmazonInvoiceParseResult | WayfairInvoiceParseResult;
  debug: {
    totalItems?: number;         // Amazon
    skuCount?: number;           // Wayfair
    missingSkuCount?: number;    // Wayfair
    attrCount?: number;          // Wayfair
    missingAttrCount?: number;   // Wayfair
  };
}
```

**Legacy Reference**: `src/pages/ImportAmazonInvoice.tsx` lines 317-333, `src/pages/ImportWayfairInvoice.tsx` lines 667-687.

---

## Intentional Deltas from Web

| Aspect | Web App | Mobile App | Reason |
|--------|---------|------------|--------|
| PDF text extraction | Direct pdf.js via Vite-bundled worker | WebView bridge with bundled pdfjs-dist | React Native lacks DOM/Web Workers |
| Image extraction | Direct Canvas API in browser | WebView Canvas, results as base64 data URIs | React Native lacks Canvas API |
| File selection | `<input type="file">` + drag-and-drop | `expo-document-picker` with `application/pdf` filter | Native file picker required |
| Transaction creation | Direct Firestore `addDoc` / `createTransaction` | Request-doc workflow via `createRequestDoc` | Offline-first with idempotent server processing |
| Receipt upload | Immediate `ImageUploadService.uploadReceiptAttachment()` | `saveLocalMedia()` + `enqueueUpload()` via offline media lifecycle | Offline-first media handling |
| Thumbnail upload | Immediate upload with 4-concurrent limiter | `saveLocalMedia()` + `enqueueUpload()` per thumbnail | Offline-first media handling |
| Navigation | React Router `useNavigate()` | Expo Router `router.push()` / `router.back()` | Expo Router for mobile navigation |
| Toast notifications | `useToast()` from custom ToastContext | React Native toast/alert system | Platform-specific notification |

---

## Edge Cases & Validation

### File Selection

| Scenario | Behavior |
|----------|----------|
| Non-PDF file selected | Show error: "Please select a PDF file." Do not proceed to extraction. |
| File selection canceled | No action; screen remains in initial state. |
| Very large PDF (>50MB) | Allow selection; extraction may be slow. No hard limit enforced. |

### PDF Extraction

| Scenario | Behavior |
|----------|----------|
| Empty PDF (no pages) | Extraction returns empty `fullText`. Parser produces zero line items + warning. |
| No text extracted (image-based PDF) | `fullText` is empty or contains only whitespace. Warning: "No line items were detected. The PDF may be image-based or the template changed." |
| WebView extraction timeout (>30s) | Bridge rejects with timeout error. Screen shows: "Failed to parse PDF. Please try again." |
| WebView crashes | Bridge detects crash via `onError` callback. Screen shows error state. User can retry by selecting the file again. |
| PDF with password protection | pdf.js will fail to open. Bridge returns error. Screen shows: "Failed to parse PDF." |

### Parsing

| Scenario | Behavior |
|----------|----------|
| Amazon: wrong vendor | Warning "Not an Amazon invoice" blocks creation. Error message shown. |
| Parser finds no line items | Warning emitted. User can still create a transaction-only (no items) if they edit the amount manually. |
| Parser line totals do not match order total | Warning emitted with the difference amount. Non-blocking. |
| Parser cannot find order number | Warning emitted. Order number field shows "Unknown". Non-blocking. |
| Parser cannot find order date | Warning emitted. Transaction date defaults to today. Non-blocking. |
| Amazon: missing unit price for an item | Warning emitted with item description. Item is skipped (not included in line items). |
| Wayfair: thumbnail count != line item count | Warning emitted: "Detected N embedded thumbnail(s) but parsed M line item(s)." Thumbnails are matched by order; extra thumbnails are dropped (lowest-scoring); extra items have no thumbnail. |

### Draft Validation (Before Creation)

| Validation | Rule |
|------------|------|
| Project ID | Must be non-null (from route params) |
| Account ID | Must be non-null (from auth context) |
| User signed in | `user.id` must be non-null |
| Parse result exists | Must have parsed at least once |
| Amazon: not wrong vendor | `warnings` must not contain "Not an Amazon invoice" |
| Amount | Must be a positive finite number |
| Item descriptions | Each item must have a non-empty description |
| Item prices | Each item's `purchasePrice` must be a finite number >= 0 |
| Wayfair subtotal (if tax preset = "Other") | `subtotal` must be positive and <= `amount` |

### Creation

| Scenario | Behavior |
|----------|----------|
| Offline during creation | Request-doc queued locally. UI shows "Created (pending sync)". |
| Request-doc write fails (e.g., permissions) | Error shown. User can retry. |
| Cloud Function fails to process | Request-doc `status` set to `'failed'`. Client can show error via subscription. |
| Duplicate creation (same `opId`) | Cloud Function skips if already applied. No duplicate transaction. |

### Media Upload

| Scenario | Behavior |
|----------|----------|
| Offline during upload | Upload queued. Retried automatically when online. |
| Upload fails after retries | Job status = `'failed'`. User prompted: "Open the transaction to retry." |
| Receipt PDF upload fails | Handled independently of thumbnail uploads. Warning shown. |
| Thumbnail upload partially fails | Successfully uploaded thumbnails are attached. Failed ones show error. |

---

## Acceptance Criteria

### File Selection & Parsing

- [ ] Tapping "Add" in the project transactions control bar opens a bottom sheet with "Create New" and "Import from Invoice" options
- [ ] "Import from Invoice" expands to show "Amazon" and "Wayfair" vendor sub-options
- [ ] Import options are only visible in project scope (not in business inventory)
- [ ] Tapping either option navigates to the corresponding import screen with `projectId` in route params
- [ ] File picker opens with `application/pdf` filter via `expo-document-picker`
- [ ] Non-PDF file selection shows error message and does not proceed
- [ ] Selected PDF name is displayed on the screen
- [ ] PDF text extraction runs locally via WebView bridge (no network required)
- [ ] Extraction timeout (30s) shows error with retry option
- [ ] Parse result populates the summary header with order/invoice ID, totals, and line item count

### Amazon-Specific

- [ ] Wrong-vendor detection ("Not an Amazon invoice") blocks creation
- [ ] Wrong-vendor detection shows error message to user
- [ ] `orderNumber` parsed from "Amazon.com order number:" or "Final Details for Order #" lines
- [ ] `orderPlacedDate` parsed and converted to YYYY-MM-DD format
- [ ] `grandTotal` parsed from "Grand Total:" or "Order Total:" lines
- [ ] `tax` parsed from "Estimated Tax:" line
- [ ] `shipping` parsed from last "Shipping & Handling:" match
- [ ] `paymentMethod` parsed from "Visa|Mastercard|... | Last digits: NNNN" pattern
- [ ] Line items detected by `<qty> of: <description>` pattern
- [ ] Item price extracted from end of description line or subsequent line
- [ ] Address blocks and ignored lines skipped during parsing
- [ ] Shipment boundaries detected by "Shipped on <date>" lines
- [ ] Items with `qty > 1` expanded into individual item drafts
- [ ] Per-unit price calculated correctly: `unitPrice` if available, else `total / qty`
- [ ] Item notes include shipped date and "Amazon import" label
- [ ] Transaction notes include "Amazon import", order number, and order date
- [ ] Total validation warning emitted when calculated total differs from grand total by > $0.05

### Wayfair-Specific

- [ ] `invoiceNumber` parsed from "Invoice Number/# :" pattern
- [ ] `orderDate` parsed from "Order Date:" or "Order Placed:" pattern
- [ ] `orderTotal`, `subtotal`, `shippingDeliveryTotal`, `taxTotal`, `adjustmentsTotal` parsed
- [ ] `calculatedSubtotal` computed as `orderTotal - taxTotal`
- [ ] Line items detected by money rows with >= 2 money tokens and a valid quantity
- [ ] Multi-line descriptions accumulated (up to 8 lines) and joined
- [ ] SKU captured from standalone lines, leading position on money rows, or prefix/suffix on description lines
- [ ] Attribute lines (e.g., "Color: Taupe") captured and attached to correct items
- [ ] Order-level attributes (e.g., "Payment Type") filtered out
- [ ] Table header lines detected and skipped (or stripped if merged with item data)
- [ ] Shipped vs. to-be-shipped sections tracked correctly
- [ ] Items with same SKU + normalized price share `uiGroupKey` (grouped in UI)
- [ ] Items without SKU get unique `uiGroupKey` (not grouped)
- [ ] Per-unit price accounts for adjustments and shipping
- [ ] Per-unit tax captured as `taxAmountPurchasePrice`
- [ ] Embedded thumbnails extracted from PDF via WebView Canvas
- [ ] Header/decorative images filtered out (page 1 top band, extreme aspect ratios)
- [ ] Thumbnail count mismatch produces warning
- [ ] Thumbnails matched to items by reading order
- [ ] Total validation warning emitted when line totals differ from order total by > $0.05

### Draft Editing

- [ ] Transaction date, amount, budget category, payment method, and notes are editable
- [ ] Item description, purchase price, SKU, and notes are editable
- [ ] Amazon items expanded by quantity are individually editable
- [ ] Budget category is required for creation
- [ ] Amount must be a positive number
- [ ] Each item must have a non-empty description and price >= 0
- [ ] All draft state is ephemeral (not persisted until "Create" is tapped)

### Creation & Offline

- [ ] "Create Transaction" writes a request-doc with `type: 'import-transaction'`
- [ ] Request-doc includes `opId` for idempotent processing
- [ ] Request-doc payload includes transaction fields and items array
- [ ] Offline creation queues the request-doc locally and shows "Created (pending sync)"
- [ ] Cloud Function processes request-doc: creates transaction + items atomically
- [ ] Duplicate `opId` is ignored by Cloud Function (no double-creation)
- [ ] Failed request-doc sets `status: 'failed'` with error details
- [ ] UI navigates to transaction detail after successful creation

### Media

- [ ] Receipt PDF saved via `saveLocalMedia()` and enqueued via `enqueueUpload()`
- [ ] Receipt linked to transaction via `attachmentRef` in request-doc payload
- [ ] Wayfair thumbnails saved and enqueued individually
- [ ] Upload concurrency limited to 4 for Wayfair thumbnails
- [ ] Upload failures show warning with retry guidance
- [ ] Attachment status transitions: `local_only` -> `uploading` -> `uploaded` (or `failed`)
- [ ] Failed uploads can be retried from transaction detail screen

### Debug Tooling

- [ ] Parse summary header shows invoice/order ID, totals, and line item count
- [ ] Warnings displayed in amber alert box
- [ ] Debug disclosure section is collapsible
- [ ] "Copy JSON" copies parse report to clipboard
- [ ] "Share JSON" opens system share sheet
- [ ] Parsed line items list shows description, SKU (Wayfair), qty, total
- [ ] Raw text preview shows numbered lines with configurable limit (200/400/800/1600/All)
- [ ] Extraction stats shown (page count, char count, line count)

### Mobile UX

- [ ] Touch targets minimum 44pt height on all interactive elements
- [ ] Loading indicator shown during PDF extraction
- [ ] Loading indicator shown during thumbnail extraction (Wayfair)
- [ ] "Create" button disabled during parsing and creation
- [ ] Reset button clears all state and returns to initial file selection view
- [ ] Back navigation returns to project transactions list
- [ ] Input fields use 16px font to prevent iOS zoom

---

## Implementation Targets

### Utility Files (Ported from Web)

| File | Description |
|------|-------------|
| `src/utils/money.ts` | `normalizeMoneyToTwoDecimalString`, `parseMoneyToNumber` |
| `src/utils/amazonInvoiceParser.ts` | Amazon invoice text parser (port from web) |
| `src/utils/wayfairInvoiceParser.ts` | Wayfair invoice text parser (port from web) |
| `src/utils/pdfTextExtraction.ts` | `buildTextLinesFromPdfTextItems` type definitions (used in WebView bridge) |
| `src/utils/pdfEmbeddedImageExtraction.ts` | Type definitions and scoring functions for embedded image extraction |

### WebView Bridge

| File | Description |
|------|-------------|
| `src/invoice-import/pdfExtractionWebView.html` | Self-contained HTML with pdfjs-dist, text extraction, and image extraction |
| `src/invoice-import/PdfExtractionBridge.tsx` | React Native component exposing imperative extraction API via hidden WebView |

### Screen Components

| File | Description |
|------|-------------|
| `src/screens/ImportAmazonInvoice.tsx` | Amazon import screen with file picker, parsing, draft editing, and creation |
| `src/screens/ImportWayfairInvoice.tsx` | Wayfair import screen with file picker, parsing, thumbnails, draft editing, and creation |

### Shared UI Components

| File | Description |
|------|-------------|
| `src/components/import/ParsedInvoiceSummary.tsx` | Summary header showing parsed invoice metadata and totals |
| `src/components/import/DraftItemsList.tsx` | Editable list of draft items with grouping support |
| `src/components/import/ParseDebugReport.tsx` | Collapsible debug section with JSON export, line items, and raw text preview |

### Route Files (Expo Router)

| File | Description |
|------|-------------|
| `app/project/[projectId]/import-amazon.tsx` | Route entry point for Amazon import |
| `app/project/[projectId]/import-wayfair.tsx` | Route entry point for Wayfair import |

---

## Future Enhancements (Out of Scope for MVP)

- Additional vendor parsers (e.g., Restoration Hardware, CB2)
- OCR fallback for image-based PDFs (no text layer)
- Camera-based invoice scanning (capture photo, process as PDF)
- Batch import (multiple PDFs in one session)
- Parse result caching (resume draft after app restart)
- Server-side PDF parsing fallback (when WebView bridge fails)
- AI-assisted parsing for unknown invoice formats
- Import history/audit log

---

## Related Specifications

- [Budget Management](./budget-management.md) -- Budget category selection during import
- [Offline Capability](./offline_capability.md) -- Offline media lifecycle and sync status
- [Transaction Audit](./transaction_audit_spec.md) -- Transaction data model

---

**End of Specification**
