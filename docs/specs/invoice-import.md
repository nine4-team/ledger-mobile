# Invoice Import

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

1. A **draft transaction** with:
   - `source` = vendor name
   - `transactionDate` = parsed date
   - `amountCents` = parsed total
   - `subtotalCents` = parsed subtotal (if available)
   - `taxRatePct` = calculated from subtotal and total (if both available)
   - `budgetCategoryId` = user-selected category
   - `status` = "pending" (draft)
   - `transactionType` = "Purchase"
2. **Items** for each line item:
   - `name` = parsed item description
   - `purchasePriceCents` = parsed unit price
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

Invoice import does NOT work offline because:

1. Document upload requires connectivity (actual bytes)
2. Server-side parsing requires the Cloud Function
3. The review step can happen offline (data is local after parsing)
4. The final import (creating transaction + items) works offline (fire-and-forget Firestore writes)

## Edge Cases

1. **No line items extracted**: Show empty review screen with option to add items manually
2. **Duplicate import**: No automatic detection -- user is responsible for not importing the same invoice twice
3. **Very large invoices (100+ items)**: Parser should handle; review screen should be scrollable/searchable
4. **Missing prices**: Line items without prices are imported with `purchasePriceCents` set to null
5. **Tax already included in line prices**: User can toggle whether extracted prices include tax

## Design Decision: Why Server-Side Parsing?

PDF/image parsing requires OCR and structured extraction capabilities that are too heavy for client-side execution. Server-side processing provides:

- Access to ML-based extraction models
- Consistent parsing quality across platforms
- Ability to improve parsing without app updates
