# Invoice Import

## Purpose
Lets users select a vendor PDF invoice, extract and parse line items client-side, review/edit them, and create a transaction + items in one flow.

## Files

- `Logic/InvoiceMoneyParsing.swift` — Money string parsing (`normalizeMoneyToTwoDecimalString`, `parseMoneyToNumber`, `parseCentsFromDollarString`). Ported from `/Dev/ledger/src/utils/money.ts`.
- `Logic/InvoiceDateParsing.swift` — Shared date parsing (`parseDateToIso`). Supports MM/DD/YYYY, "Month DD, YYYY", abbreviated months.
- `Logic/PdfTextExtractor.swift` — PDFKit-based text extraction from PDF `Data`. Returns per-page text, full text, and `ExtractionStats` (for debug report).
- `Logic/PdfImageExtractor.swift` — Wayfair thumbnail extraction. Renders PDF pages at 2x, finds image regions via text gap analysis, crops thumbnails.
- `Logic/AmazonInvoiceParser.swift` — Amazon invoice parser (port of `amazonInvoiceParser.ts`). Also defines shared free functions: `extractFirstMatch`, `extractLastMatch`, `normalizeLines`, `extractMoneyTokens`.
- `Logic/WayfairInvoiceParser.swift` — Wayfair invoice parser (port of `wayfairInvoiceParser.ts`, ~1000 lines). SKU detection, attribute extraction, section tracking, multi-line description accumulation.
- `Logic/InvoiceImportCalculations.swift` — Vendor auto-detection, `DraftLineItem` model, draft item mapping from parse results, thumbnail attachment, validation.
- `Components/DocumentPicker.swift` — `UIDocumentPickerViewController` wrapper for PDF selection.
- `Modals/ImportInvoiceModal.swift` — Flow coordinator: select PDF -> auto-detect vendor -> parse -> review -> create transaction + items.
- `Modals/InvoiceImport/InvoiceParseSummary.swift` — Vendor-specific parsed header display (order/invoice #, date, totals, warnings).
- `Modals/InvoiceImport/DraftItemsList.swift` — Editable list of parsed line items with toggle inclusion.
- `Modals/InvoiceImport/DraftItemRow.swift` — Single draft item row with checkbox, inline-editable fields, optional SKU/attributes/thumbnail.
- `Modals/InvoiceImport/ParseDebugReport.swift` — Collapsible debug panel: extraction stats, raw text viewer, copy-to-clipboard JSON.

## State
All state is local to `ImportInvoiceModal` via `@State`. No `@Observable` store — this is a transient flow that creates data and dismisses. Key state:
- `selectedFileData` / `selectedFileName` — Raw PDF bytes and filename
- `detectedVendor` — Auto-detected `InvoiceVendor` (.amazon or .wayfair)
- `amazonParseResult` / `wayfairParseResult` — Vendor-specific parse output
- `draftItems: [DraftLineItem]` — Editable draft items with `isIncluded` toggle
- `extractedThumbnails` — Wayfair product images from PDF
- `extractionStats` / `rawPdfText` — For ParseDebugReport

## Data
**Creates:**
- `accounts/{accountId}/items/{itemId}` — One item per included draft line item. Fields: `name`, `purchasePriceCents`, `quantity`, `source`, `sku` (Wayfair), `status: "active"`, `budgetCategoryId`, `notes` (Wayfair attribute lines).
- `accounts/{accountId}/transactions/{txId}` — One transaction linking all created items. Fields: `projectId`, `transactionType: "purchase"`, `source` (e.g. "Amazon #ORDER123"), `transactionDate`, `amountCents`, `status: "pending"`, `itemIds`, `budgetCategoryId`.

**Uploads (background, fire-and-forget):**
- Receipt PDF to `accounts/{accountId}/transactions/{txId}/{uuid}.pdf` -> updates `receiptImages`
- Wayfair thumbnails (max 4) to `accounts/{accountId}/items/{itemId}/{uuid}.png` -> updates `images`

## Sheets & Navigation
- Entry: `TransactionsTabView` "+" button -> ActionMenuSheet with "New Transaction" and "Import Invoice"
- Import sheet: `.sheetStyle(.fullSheet)` for max content space
- Category picker: nested `.sheet(isPresented: $showCategoryPicker)` with `.sheetStyle(.picker)`
- Document picker: nested `.sheet(isPresented: $showDocumentPicker)` with `DocumentPicker`
- Dismisses immediately on transaction creation (optimistic UI); uploads run in background

## Gotchas
- **Vendor auto-detection order matters**: Amazon is checked first (`isAmazonInvoice`), then Wayfair. Both check for vendor-specific text markers in the PDF.
- **PDFKit text extraction vs pdf.js**: PDFKit gives simpler text output than pdf.js's x/y coordinate grouping. This works for the line-oriented parsing these invoices use, but table-heavy PDFs may need coordinate-based grouping later.
- **Shared free functions**: `extractFirstMatch`, `extractLastMatch`, `normalizeLines`, `extractMoneyTokens` are defined at file scope in `AmazonInvoiceParser.swift` and used by both parsers. They're free functions, not methods on the enum.
- **PdfImageExtractor is heuristic-based**: Unlike the web app which uses pdf.js operator lists to find exact image bounding boxes, the native version uses text gap analysis. May need refinement with real Wayfair PDFs.
- **Swift 6 concurrency**: `Regex<Substring>` isn't `Sendable`, so the `ignorePatterns` static array uses `nonisolated(unsafe)`. Background upload Tasks construct `[String: Any]` field dictionaries inline to avoid sending non-Sendable types across isolation boundaries.
