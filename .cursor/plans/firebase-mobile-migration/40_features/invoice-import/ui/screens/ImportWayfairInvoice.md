# Import Wayfair Invoice — Screen contract

## Intent
Let a user select a Wayfair invoice PDF, parse it locally into a draft transaction + draft items, optionally extract embedded item thumbnails, allow review/edit, then create the transaction/items and attach media with robust background/queued upload behavior.

## Inputs
- Route params:
  - `projectId`
- Query params:
  - `returnTo` (optional; parity pattern)
  - `backTarget` (optional; deep link fallback)
- Entry points (where navigated from):
  - Project transactions list “Add” menu → Import → Wayfair (parity: `src/pages/TransactionsList.tsx`)

## Reads (local-first)
- Project display info (name) for header context.
  - Web parity evidence: `src/pages/ImportWayfairInvoice.tsx` (`projectService.getProject` → `projectName`)
- Cached metadata dependencies:
  - Budget categories for `CategorySelect`

## Writes (local-first)
For each user action:

- Select PDF
  - Local state only (draft); no DB writes.
- Parse PDF
  - Local state only (draft); no DB writes.
- Extract thumbnails
  - Local state only (draft), but produces local image files that may need staging space.
- Edit draft fields (date, amount, category, payment method, notes, tax fields, item drafts, item images)
  - Local state only (draft); no DB writes.
- Create transaction
  - **Request-doc write (Firestore local cache)**:
    - create a request doc that includes transaction + item payloads and a stable idempotency key
    - stage local attachment placeholders for receipt PDF + item images (offline media state)
  - **Server apply (Cloud Function transaction)**:
    - create transaction + items atomically
    - attach receipt/item image metadata and enqueue uploads per offline media lifecycle

## UI structure (high level)
- Header:
  - Back CTA
  - Reset CTA
  - Title “Import Wayfair Invoice” + project name subtitle
- Upload section:
  - PDF picker (mobile: file picker)
  - Parsing spinner
  - Thumbnail extraction spinner (distinct state)
- Parse summary card:
  - Invoice number, parsed total, tax total (when present), detected item counts (shipped/to-be-shipped)
  - Warnings list (if any)
  - Thumbnail warning block (if any)
- Debug disclosure:
  - Parse report copy/share actions
  - Raw extracted text preview with configurable line limit
  - Thumbnail debug info (counts) in the parse report payload (mobile-friendly)
- Draft form:
  - Transaction date
  - Amount
  - Tax (inline fields; no presets)
  - Budget category select
  - Payment method radio
  - Notes textarea
  - Draft itemization editor with image-file editing hooks (draft mode)
- Sticky create CTA:
  - “Create Transaction” disabled while parsing/creating

## User actions → behavior (the contract)
- **Back**
  - Uses native back stack; if entered via deep link/cold start, fall back to `backTarget` or project transactions list.
  - See: `40_features/navigation-stack-and-context-links/README.md`
- **Reset**
  - Clears selected file, parse result, extracted text, extracted thumbnails, draft items, and restores defaults.
  - Parity evidence: `handleReset` in `src/pages/ImportWayfairInvoice.tsx`
- **Select PDF**
  - Reject non-PDF and show an error.
  - Parity evidence: `onFileSelected` in `src/pages/ImportWayfairInvoice.tsx`
- **Parse**
  - Extract text from PDF, parse Wayfair invoice, and attempt embedded thumbnail extraction.
  - If thumbnail extraction fails, proceed without thumbnails and show a warning.
  - Parity evidence: `parsePdf` in `src/pages/ImportWayfairInvoice.tsx`
- **Review thumbnails**
  - Thumbnails are matched to items by row order; show a warning when counts mismatch.
  - Allow user to remove/replace item images in the draft editor before create.
  - Parity evidence: `applyThumbnailsToDrafts` + `handleImageFilesChange` in `src/pages/ImportWayfairInvoice.tsx`
- **Tax (simplified; no presets)**
  - When the parser provides `calculatedSubtotal`, default to **Calculate from subtotal** mode and populate subtotal.
  - When the parser provides tax total, populate **tax amount** and back-calculate the rate.
  - Validation: `subtotal > 0` and `subtotal <= total amount`; `taxAmount >= 0` and `taxAmount < total amount`.
  - Parity evidence: `applyParsedInvoiceToDraft` + `validateBeforeCreate` in `src/pages/ImportWayfairInvoice.tsx` (intentional delta: replaces preset “Other” with inline tax fields).
- **Create**
  - On success: show success feedback and navigate to transaction detail.
  - Then: enqueue background/queued uploads for receipt + thumbnails and show progress messaging.
  - On failure: show an error and keep the draft for retry.
  - Parity evidence: `handleCreate` + `finalizeWayfairImportAssets` in `src/pages/ImportWayfairInvoice.tsx`

## States
- Loading:
  - Project name fetch may be loading; importer still usable.
- Error:
  - Parse failures show “Failed to parse PDF” + keep screen usable.
  - Thumbnail extraction failure shows a non-blocking warning and proceeds.
- Offline:
  - Parsing is allowed offline (local).
  - Create is allowed offline by writing the request doc to Firestore local cache; show “created (pending sync)” messaging on create.
- Pending sync:
  - Transaction and items are immediately visible via Firestore local cache; media shows placeholder states until uploaded.
- Permissions denied:
  - Show access denied UI with a back CTA.
  - Parity evidence: guard `!currentAccountId && !isOwner()` in `src/pages/ImportWayfairInvoice.tsx`
- Quota/media blocked:
  - If storage quota prevents staging thumbnails or the PDF, block create and explain.
  - Source of truth: `40_features/_cross_cutting/ui/components/storage_quota_warning.md`

## Media
- Add/select:
  - Single PDF selected becomes a receipt attachment.
  - Extracted thumbnails become staged item image files.
- Placeholder rendering (offline):
  - Receipt + item images show `local_only` / `uploading` / `failed` states with retry.
  - Source of truth: `40_features/_cross_cutting/offline-media-lifecycle/offline_media_lifecycle.md`
- Cleanup/orphan rules:
  - If user resets or leaves without creating, staged local files should be cleaned up (best-effort).

## Collaboration / realtime expectations
- None required while screen is open.
- Created entities converge via Firestore offline persistence + scoped project listeners (no large listeners).

## Performance notes
- Use explicit progress states for parse + thumbnail extraction.
- Limit concurrent uploads (parity uses 4); mobile can keep similar to avoid saturating bandwidth/storage.

## Parity evidence
- Screen: `src/pages/ImportWayfairInvoice.tsx`
- Parser: `src/utils/wayfairInvoiceParser.ts`
- PDF text extraction: `src/utils/pdfTextExtraction.ts`
- Embedded image extraction: `src/utils/pdfEmbeddedImageExtraction.ts`

