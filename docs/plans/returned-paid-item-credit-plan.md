# Returned Paid Item Credit Plan

Created: 2026-06-29
Last updated: 2026-06-29

Master tracker: [transaction-taxonomy-master-tracker.md](transaction-taxonomy-master-tracker.md)

## Decision

When an item that was already charged on a paid invoice is returned to business
inventory, Ledger must create client credit demand in invoicing. It must not
create a synthetic credit transaction.

The clean design is:

- Keep the inventory return money movement exactly as today.
- Create an ordinary draft invoice containing credit line(s).
- Use existing `InvoiceLine` fields only.
- Use deterministic credit line IDs for idempotency and auditability.
- Do not add a new invoice type, invoice purpose, credit reason enum, or extra
  top-level credit metadata fields.

## Problem

The current bad path is:

- `InventoryOperationsService.returnToInventory(...)` receives only
  `paidInvoiceItemIds: Set<String>`.
- It calls `appendPaidReturnCredits(...)`.
- `appendPaidReturnCredits(...)` writes a transaction with source
  `"Credit: returned ..."`.

That is wrong because returning a previously paid item does not mean money moved.
It means the client now has a credit demand that belongs in the invoice system.

## Code Facts

- `InventoryOperationsService.returnToInventory(...)` and
  `moveToInventory(...)` already build one Firestore batch for the movement.
- `MoveToInventoryModal` has `AccountContext`, including
  `accountContext.allInvoices`, before calling inventory operations.
- `TransactionDetailView.returnToInventory()` currently bypasses that modal path
  and calls `moveToInventory(...)` directly.
- `InvoiceLine` already has the fields needed for the credit line:
  - `id`
  - `sourceType`
  - `sourceId`
  - `amountCents`
  - `sign`
  - `budgetCategoryId`
  - `snapshotName`
  - `settlementTransactionIds`
- `InvoiceLineSourceType.manual` already exists and is not tied to invoice
  membership indexes.
- `InvoiceService.createInvoice(...)` can create draft invoices with `lines`.
- `InvoiceService.markCollected(...)` creates categorized
  `paymentToBusiness` transactions from positive settled demand. It must not be
  used to collect a net-negative credit invoice as money received.

## Target Behavior

Returning a paid item should:

1. Move the item back to inventory.
2. Write the legitimate return-to-inventory movement transaction.
3. Create a draft invoice with one credit line per returned paid invoice line.
4. Use the original paid invoice line's amount and category.
5. Avoid duplicate credits for the same paid invoice line and item.
6. Commit the movement and draft credit invoice in the same Firestore batch when
   the caller has invoice context.

Returning a paid item should not:

- Write an `expense`, `purchase`, or other credit transaction.
- Mutate the original paid invoice.
- Invent a new invoice lifecycle state.
- Add credit-only fields to the persisted invoice line model unless later
  evidence proves deterministic line IDs and notes are insufficient.

## Credit Line Shape

Use an ordinary `InvoiceLine`:

```swift
InvoiceLine(
    id: deterministicReturnedPaidItemCreditId(
        paidInvoiceId: paidInvoice.id,
        paidInvoiceLineId: paidLine.id,
        itemId: returnedItem.id
    ),
    sourceType: .manual,
    sourceId: nil,
    amountCents: paidLine.amountCents,
    sign: .credit,
    budgetCategoryId: paidLine.budgetCategoryId,
    snapshotName: "Credit: returned \(itemName)"
)
```

Why `sourceType = .manual`:

- The credit is not a new item charge.
- The returned item should not re-enter normal item invoice membership.
- Existing membership logic keys `itemIds` from `sourceType == .item`; this
  credit should leave `itemIds` empty.

Why no new persisted credit fields:

- The original paid invoice line already contains the frozen amount, category,
  and display context.
- The deterministic credit line ID can encode or hash the source invoice id,
  source invoice line id, and item id.
- Human explanation belongs in `snapshotName` and invoice `notes`.
- Four additional fields would duplicate lineage that can be recovered from the
  deterministic line ID without improving the current workflow.

## Idempotency

The machine-readable invariant is the deterministic credit line ID:

```text
returnCredit:{paidInvoiceId}:{paidInvoiceLineId}:{itemId}
```

Implementation may encode or hash the raw tuple to keep the persisted line ID
Firestore-safe and reasonably short.

There must be at most one non-voided returned-paid-item credit line for the same
source invoice line and returned item.

Context resolution should scan all non-voided invoices for an existing line with
the same deterministic ID and skip creating another credit when found. A voided
credit invoice does not dedupe future credit creation.

## Draft Invoice Container

Create a normal draft invoice:

- `status = draft`
- `projectId = source project id`
- `itemIds = []`
- `transactionIds = []`
- `lines = returned paid item credit lines`
- `notes` explains that the draft contains credits for paid items returned to
  inventory.

Do not append these lines to an arbitrary existing draft. Existing drafts may be
user-composed invoices in progress, and silent insertion would be surprising.

Do not add `Invoice.purpose` for this pass. The invoice lifecycle is already
draft, sent, paid, voided; a separate purpose enum is not justified by this rare
case.

## Runtime Context

Add a code-only context type. This is not persisted as a schema expansion:

```swift
struct ReturnedPaidItemCreditContext: Hashable {
    var itemId: String
    var itemName: String
    var projectId: String
    var amountCents: Int
    var budgetCategoryId: String
    var paidInvoiceId: String
    var paidInvoiceLineId: String
    var lineId: String
}
```

The `paidInvoiceId` and `paidInvoiceLineId` values are runtime inputs used to
build the deterministic line ID and audit logs. They do not require new
Firestore fields on `InvoiceLine`.

## Context Resolution

Add a pure helper near `InvoiceLineCalculations`:

```swift
static func returnedPaidItemCreditContexts(
    for items: [Item],
    invoices: [Invoice]
) -> [ReturnedPaidItemCreditContext]
```

Algorithm:

1. Build a lookup of selected returned item ids.
2. Scan paid invoices only for original charges:
   - `invoice.status == .paid`
   - `line.sourceType == .item`
   - `line.sourceId` is a selected returned item id
   - `line.sign == .charge`
3. Require `line.budgetCategoryId`.
4. Use `line.amountCents`, not the item's current price.
5. Use `line.budgetCategoryId`, not the item's current category.
6. Compute the deterministic returned-credit line ID from paid invoice id, paid
   line id, and item id.
7. Exclude contexts when any non-voided invoice already contains a line with
   that deterministic ID.
8. If multiple paid charge lines match one item, choose deterministically by the
   newest paid invoice date/id and log a diagnostic; this indicates historical
   data drift.

## Service Changes

Replace:

```swift
paidInvoiceItemIds: Set<String>
```

with:

```swift
returnedPaidItemCredits: [ReturnedPaidItemCreditContext] = []
```

on:

- `InventoryOperationsService.returnToInventory(...)`
- `InventoryOperationsService.moveToInventory(...)`

Remove:

- `appendPaidReturnCredits(...)`

Add an invoice batch helper, either on `InvoiceService` or a small shared writer:

```swift
appendReturnedPaidItemCreditDraft(
    accountId: String,
    projectId: String,
    credits: [ReturnedPaidItemCreditContext],
    batch: any BatchWriting,
    userId: String?
)
```

The helper should:

- no-op when `credits` is empty,
- create one new draft invoice for the credit batch,
- write `itemIds = []` and `transactionIds = []`,
- write manual credit lines with deterministic IDs,
- write a concise human-readable note,
- avoid writing `totalCents` unless draft invoice semantics require it
  elsewhere,
- never write a transaction.

## Atomicity

Preferred behavior is one Firestore batch containing:

- inventory return transaction writes,
- item scope/category/status updates,
- source transaction membership updates,
- lineage edge writes,
- draft credit invoice creation.

All reads needed to resolve credit contexts happen before the batch is built.

If a caller cannot resolve invoice context, it must not silently skip the credit.
It should route through a context-aware path or surface a blocking warning.

## UI Changes

`MoveToInventoryModal` should compute returned paid item credit contexts from:

- selected items,
- `accountContext.allInvoices`.

Then it should pass those contexts to `InventoryOperationsService`.

When credits will be created, show a concise confirmation line, for example:

```text
2 paid item credits will be added as a draft credit invoice.
```

Do not ask the user to pick a category for these credit lines. The category is
the original paid invoice line's category.

`TransactionDetailView.returnToInventory()` must either:

- use the same context resolver before calling `moveToInventory(...)`, or
- route through the same modal/context path.

It must not bypass returned-paid-item credit creation for paid items.

## Billing and Collection Behavior

Returned-paid-item credit drafts appear in the invoice list like normal drafts.
Their lines reduce the displayed invoice total.

A credit-only draft will have a negative net total. That represents value owed
to the client, not money the business is collecting.

`markCollected` / invoice collection must block net-negative selected lines from
creating `paymentToBusiness` transactions. `paymentToBusiness` means money came
in from the client to the business.

If money later moves from the business back to the client, that refund is a
separate money-movement transaction. It is not created by the item return.

## MCP Changes

MCP should mirror the same behavior:

- Inventory return tools must not create returned-paid-item credit transactions.
- If the tool has invoice context, it should write the ordinary draft credit
  invoice in the same logical operation.
- If the tool does not have invoice context, it should return a structured
  warning instead of silently skipping:

```json
{
  "requiresReturnedPaidItemCredits": true,
  "itemIds": ["..."]
}
```

No MCP schema expansion is needed for `InvoiceLine` beyond the fields that
already exist.

## Migration / Cleanup

Add an audit script:

```text
scripts/audit-returned-paid-item-credit-transactions.mjs
```

Find rows matching:

- `source` starts with `"Credit: returned "`
- `reimbursementType == "owed-to-client"`
- `type == "purchase"` or old `type == "expense"`

For each row, output:

- transaction path,
- project id,
- amount,
- source,
- budget category,
- possible matching returned item by name/id if inferable,
- candidate paid invoice line if inferable.

Do not auto-delete without reviewed mapping.

Reviewed migration should:

1. Create deterministic draft credit invoice lines.
2. Delete or void the bad synthetic credit transactions according to the
   approved data-cleanup policy.
3. Write a JSONL decision log.

## Tests

Add unit tests for context resolution:

- Paid invoice item returns one credit context.
- Sent/draft invoice item does not create returned-paid credit.
- Missing line category excludes the line with a diagnostic.
- Existing non-voided deterministic credit line dedupes.
- Voided credit invoice does not dedupe.
- Multiple paid line matches choose a deterministic newest match and report
  diagnostic data.

Add service tests:

- `returnToInventory` with credit context writes no synthetic credit
  transaction.
- It creates a draft invoice containing manual credit lines.
- It writes return movement and credit invoice in the same batch.
- It preserves original paid invoice lines.

Add UI/calculation tests:

- Credit-only draft invoice displays a negative/client-credit total.
- Billing summary treats sent credit invoices as payable-to-client.
- Credit line does not place the returned item back into normal item invoice
  membership.
- Net-negative invoice collection cannot create `paymentToBusiness`.

## Implementation Order

1. Remove `appendPaidReturnCredits(...)` transaction write.
2. Add deterministic returned-paid-item credit line ID helper.
3. Add returned paid item credit context resolver.
4. Add invoice batch helper for ordinary draft credit invoices.
5. Wire `MoveToInventoryModal` and `TransactionDetailView` to pass contexts.
6. Wire `returnToInventory(...)` and `moveToInventory(...)` to write the credit
   invoice in the movement batch.
7. Block net-negative invoice collection from creating `paymentToBusiness`.
8. Update MCP behavior without adding new invoice-line schema fields.
9. Add audit script for bad interim/legacy credit transactions.
10. Add tests and run build/test verification.

## Acceptance Criteria

- Returning a paid item creates zero synthetic credit transactions.
- Return movement and credit demand are committed atomically when invoice context
  is available.
- The client credit is represented as an invoice line with `sign = credit`.
- The credit line is categorized from the original paid invoice line.
- Duplicate credit lines are blocked by deterministic line ID.
- Paid invoice snapshots remain unchanged.
- Budget spend changes only through the legitimate Return inventory movement.
- The credit appears in billing/invoicing, not in transaction lists or billable
  transaction pools.
