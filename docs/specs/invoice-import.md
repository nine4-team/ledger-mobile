# Invoice Import

> **Target/source boundary:** Preserve the shipped local PDF import capability,
> not the Firebase writer. The source UI locally extracts Amazon/Wayfair PDFs,
> reviews included rows and quantities/prices, shows vendor summaries/debug
> information, and captures receipt/thumbnail evidence. It does not call a
> Cloud Function to parse those supported text PDFs. The broader camera/OCR/
> editor features described below were not all implemented; O-061 owns their
> target scope and quantity/duplicate-import rules. Canonical Item/Invoice and
> receipt-line specs replace the old unconditional Purchase writer and amount
> model. No target Firebase implementation is authorized.

## Target Import Contract

- Preserve local PDF selection/cancel, Amazon/Wayfair detection and local
  parsing without requiring a new network dependency. Distinguish extracting,
  unsupported vendor, corrupt/image-only PDF, no rows and successful review.
  Remote OCR or unsupported formats may require connectivity under the approved
  import scope; they cannot disable the already-supported offline parser.
- Preserve vendor-specific summary, warnings, included count, description/
  quantity/unit-price editing, inclusion toggles, category selection, changing
  PDF and cancel. Preserve SKU/attributes/thumbnail display and safe debug
  statistics/raw-text/Copy JSON controls. Scope all drafts and diagnostics to
  their source document and Account; don't lose review edits on a failed save.
  Diagnostic disclosure is an explicit local user action on authorized source
  evidence only; omit credentials, tokens, private storage URLs and hidden
  financial metadata. Never upload raw text or clipboard diagnostics as telemetry.
- Source rows retain stable provenance through review and accepted import.
  Keep receipt adjustments under the shared non-Item receipt-line contract;
  tax/shipping/credits cannot become fake physical Items. Bind thumbnails to
  the exact included source row, never by zipping a filtered Item list against
  unfiltered images. Missing thumbnail bytes are not import success evidence.
- Confirmation uses the canonical payer/ownership routing and shared Item,
  Expense, receipt and payment commands with their approved validations. A
  vendor document alone is not proof of a Client payment. Never unconditionally
  create a project Purchase or infer a tax basis from subtotal/total. O-016,
  O-027, O-029, O-031 and O-032 still govern their respective accounting inputs.
- Persist accepted intent, source bytes and relationships before success-shaped
  dismissal; show pending, applied or rejected outcomes and preserve evidence
  through restart/retry. Repeating one accepted request must not duplicate
  Items, accounting records or media. O-061 separately decides recognizing a
  newly submitted copy of the same document and physical quantity semantics.
- Vendor recognition is an Account-scoped suggestion, not permission to rewrite
  source evidence or mutate shared presets. O-047 governs reading/selection;
  O-026 governs adding/changing shared defaults. Unknown sources remain honest.
  Adding a vendor suggestion does not install a parser for that vendor or make
  an unsupported document importable. Local parse/review of already-supported
  PDFs does not wait for O-061's expanded scope or final quantity/commit policy.

## Historical and Proposed Import Description

The remaining sections combine the old generic proposal with source-era data
shapes. They identify capabilities to reconcile, not a second target algorithm;
the Target Import Contract and canonical accounting specs take precedence.

## Overview

Invoice import allows users to extract transaction and item data from vendor invoices (PDFs or images). The system sends the document to a server-side parser that returns structured line items, which the user can review and import as a draft transaction with linked items.

## Flow

### Step 1: Document Capture

User provides an invoice via:

- Camera capture (photo of physical invoice)
- Photo library selection
- File picker (PDF)

### Step 2: Upload and Parse

The document is sent to a Cloud Function (Tier 3 -- callable) for processing. This step requires connectivity.

The parser extracts:

- **Vendor name** (from invoice header/letterhead)
- **Invoice date**
- **Line items**, each with:
  - Item name/description
  - Quantity
  - Unit price (in cents)
  - Line total (in cents)
- **Subtotal** (pre-tax total)
- **Tax amount** (if present)
- **Total amount** (including tax)

### Step 3: Review and Edit

User reviews the parsed results. They can:

- Edit vendor name
- Edit invoice date
- Edit or remove individual line items
- Add missing line items manually
- Adjust prices
- Select a budget category for the transaction

### Step 4: Import

On confirmation, the system creates:

1. An active transaction with:
   - `source` = vendor name
   - `transactionDate` = parsed date
   - `amountCents` = parsed total
   - `subtotalCents` = parsed subtotal (if available)
   - `taxRatePct` = calculated from subtotal and total (if both available)
   - `budgetCategoryId` = user-selected category
   - `transactionType` = "Purchase"
   - `isComplete` = `false` until the linked items/audit reconcile cleanly
2. **Items** for each line item:
   - `name` = parsed item description
   - `purchasePriceCents` = parsed unit price
   - `projectPriceCents` = at least the parsed unit price, unless an explicitly higher project price is supplied
   - `quantity` = parsed quantity (if the item model supports it)
   - `source` = vendor name

Items are linked to the transaction via `transaction.itemIds`.

## Vendor Recognition

The system maintains a list of known vendors per account at `accounts/{accountId}/presets/default/vendors/default` (or similar). When parsing identifies a vendor:

- Check against known vendors for name normalization
- Suggest the recognized vendor name to the user
- Unknown vendors can be added to the list for future recognition

Pre-populated vendor defaults include common vendors like Home Depot, Wayfair, West Elm, Pottery Barn, etc.

## Parser Limitations

The parser is best-effort:

- Handwritten invoices may not parse reliably
- Multi-page invoices should be supported
- Non-English invoices may have reduced accuracy
- Complex table layouts may miss items
- The user review step (Step 3) exists precisely because parsing is imperfect

## Offline Behavior

Supported local PDF extraction and review work offline. Capture and accepted
import must be durable locally; authorized byte upload, remote OCR if selected,
and authoritative command application wait for connectivity. The target never
uses fire-and-forget Firestore writes or requires remote parsing for a supported
local document merely because this old proposal described a server parser.

## Edge Cases

1. **No line items extracted**: Show empty review screen with option to add items manually
2. **Duplicate import**: No automatic detection -- user is responsible for not importing the same invoice twice
3. **Very large invoices (100+ items)**: Parser should handle; review screen should be scrollable/searchable
4. **Missing prices**: Line items without prices are imported with `purchasePriceCents` set to null. If both price fields are absent, both remain zero/null-equivalent; otherwise the canonical item price floor still applies.
5. **Tax already included in line prices**: User can toggle whether extracted prices include tax

## Design Decision: Why Server-Side Parsing?

PDF/image parsing requires OCR and structured extraction capabilities that are too heavy for client-side execution. Server-side processing provides:

- Access to ML-based extraction models
- Consistent parsing quality across platforms
- Ability to improve parsing without app updates
