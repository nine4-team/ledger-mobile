# Billing & Invoicing
Status: active redesign
Last updated: 2026-06-29
Implementation plan: [../plans/billing-invoicing-canonical-implementation.md](../plans/billing-invoicing-canonical-implementation.md)

## Summary

Billing is the boundary between money the business requests and money that has
actually moved.

- **Transaction** — a record that money moved.
- **Invoice** — a demand for money.
- **Invoice line** — one component of an invoice's demand.

Ledger supports two invoice workflows:

1. **Ad-hoc invoices** built from existing project records: items,
   non-itemized project costs, credits, and other transactions where money
   already moved.
2. **Manual charge invoices** built from new invoice lines that are not backed by
   prior transactions, such as design fees, retainers, storage fees, or project
   management fees.

The app must not create a transaction for money that has not moved. If the team
needs to request money before collection, use an invoice line. When collection
happens, create or link a transaction and connect it to the invoice as settlement
evidence.

## Core Model

### Transactions

A transaction records a real-world money movement. Examples:

- The business buys an item.
- The business pays an installer.
- The client pays the business.
- The business refunds or credits the client.

Transactions are never pending demands. A planned fee, future installment, or
expected client payment is not a transaction until money moves.

Some transactions settle invoice demands. Settlement is represented by optional
invoice linkage on the transaction, not by a separate payment entity.

Settlement fields:

```swift
struct Transaction {
    var settlementInvoiceId: String?
    var settlementInvoiceLineIds: [String]?
}
```

- `settlementInvoiceId` points to the invoice this transaction settled.
- `settlementInvoiceLineIds` optionally points to specific invoice lines when a
  payment settles only part of an invoice.

A transaction with `settlementInvoiceId` is not billable activity. It is
collection or settlement evidence and must not re-enter the To Invoice pool.

### Invoices

An invoice is a project-scoped demand for money. It may include lines based on
existing records and lines typed directly into the invoice.

Lifecycle:

- `draft` — editable planned demand. The invoice can be used to stage design-fee
  breakdowns before sending.
- `sent` — issued demand. Lines and totals are frozen as the demand the client
  received.
- `paid` — settled demand. This status should be supported by linked settlement
  transactions, either created through the Mark Collected flow or linked after
  the fact.
- `voided` — withdrawn demand. Its existing item/transaction sources return to
  the billable pool unless they are claimed by another non-voided invoice.

Invoices do not mutate the source records they reference. Paid/collected state is
derived from invoice status and settlement linkage, not stored on items or source
transactions.

### Invoice Lines

Invoice lines represent the components of a demand. They carry a sign so one
invoice can include charges and credits.

```swift
enum InvoiceLineSourceType {
    case item
    case transaction
    case manual
}

struct InvoiceLine {
    var id: String
    var sourceType: InvoiceLineSourceType
    var sourceId: String?
    var budgetCategoryId: String?
    var amountCents: Int
    var sign: InvoiceLineSign
    var snapshotName: String?
    var settlementTransactionIds: [String]?
}
```

`id` is needed so settlement transactions can optionally target specific lines.
`sourceId` is nil for manual lines.
`budgetCategoryId` is required for manual New Charge lines and should be
resolved for item/transaction-sourced lines from the source record. Invoice
settlement uses this category to create categorized payment transactions.

Line ID policy:

- New invoice lines use UUID strings created when the draft line is added.
- Backfilled historical lines use deterministic IDs derived from invoice id,
  source type, source id, and line index so migration is idempotent.
- System-generated returned-paid-item credit lines use deterministic IDs derived
  from the original paid invoice id, original paid invoice line id, and returned
  item id. The line ID is the machine-readable dedupe key.
- Line IDs survive draft edits and are frozen into sent invoices.

Source meanings:

- `item` — demand is based on a project item.
- `transaction` — demand or credit is based on money that already moved, such as
  a non-itemized project cost or client-paid credit.
- `manual` — demand is entered directly on the invoice, not backed by an item or
  prior transaction.
- `manual` with `sign == credit` may also represent a system-generated credit
  demand that should not claim a source item or transaction as normal invoice
  membership, such as a paid item returned to inventory.

The UI should label the action for adding a manual line as **New Charge**.
Examples: "Design Fee 1 of 3", "Retainer", "Project Management Fee", "Storage
Fee", "Adjustment".

Manual New Charge lines must require the user to pick a budget category. Do not
silently default the category.

## Billable Pool

The To Invoice pool includes existing billable sources that are not already
claimed by a non-voided invoice:

- Project items that are not returned.
- Eligible non-itemized project transactions where money already moved and the
  transaction is not canceled.

Existing transactions are billable only when their shape represents money that
should be demanded or credited on an invoice. Settlement transactions are never
billable.

`paymentToBusiness` transactions are treated as money-in movement. A
`paymentToBusiness` transaction created when the client pays the business is
settlement evidence, not a planned receivable.

Manual New Charge lines are not discovered from the pool because they do not
exist until the user adds them to a draft invoice. They are invoice demand lines,
not project-level source records.

## Invoice Workflows

### Ad-Hoc Invoice

Used when the project already has records that justify the demand.

Example:

```text
Existing records:
- Item: Sofa
- Transaction: business paid installer $300

Invoice:
- Sofa                         sourceType: item
- Installer reimbursement      sourceType: transaction
```

When the client pays, Ledger creates or links a transaction for the actual money
received and sets `settlementInvoiceId` to the invoice.

### Manual Charge Invoice

Used when no money has moved yet and the team needs to demand a design fee,
retainer, service fee, or other planned amount.

Example:

```text
Draft invoice:
- New Charge: Design Fee 1 of 3       $2,500
- New Charge: Design Fee 2 of 3       $2,500
- New Charge: Design Fee 3 of 3       $2,500
```

Those lines may live on a draft invoice before it is sent. They are invoice
lines, not transactions.

When the client pays, Ledger creates or links categorized `paymentToBusiness`
transaction(s) for the payment event and links those transaction(s) to the
invoice or specific invoice lines.

### Mixed Invoice

One invoice can combine existing records and manual charges.

Example:

```text
Invoice:
- Existing expense transaction: delivery reimbursement       $300
- New Charge: Design Fee 1 of 3                            $2,500

Client pays $2,800:
- Create categorized `paymentToBusiness` settlement transaction(s).
- If all settled lines share one budget category, one transaction is enough.
- If settled lines span multiple budget categories, create one transaction per
  budget category.
- Link the settlement transaction(s) to the invoice.
```

The existing expense transaction records money out. The settlement transaction
records money in. Both are transactions because money moved in both cases, but
only the expense transaction is an invoice-line source.

## Collection Behavior

Ledger should support collecting at invoice or line granularity:

- **Whole invoice collected** — create or link categorized `paymentToBusiness`
  transaction(s) for the collected amount and set `settlementInvoiceId`.
- **Selected lines collected** — create or link categorized `paymentToBusiness`
  transaction(s) and set `settlementInvoiceLineIds` to the settled lines.

Collection should follow real payment events and budget-category attribution. If
one check/ACH/card payment settles multiple lines in one budget category, create
one transaction for that category. If it settles multiple budget categories,
create one `paymentToBusiness` transaction per budget category represented by the
settled lines.

Every settlement transaction must have a `budgetCategoryId`. If a selected line
cannot resolve a budget category, the app should block collection until the line
or source record is categorized.

Collection must not create `paymentToBusiness` transactions for a net-negative
selection or invoice. `paymentToBusiness` means money came in from the client to
the business. A credit-only invoice represents value owed to the client; if money
later moves back to the client, that refund/payment is a separate
money-movement transaction.

Marking an invoice paid may create a settlement transaction as part of the
workflow. If a transaction already exists, the user should be able to link it
instead.

The UI should use **Mark Collected** for actions that create or link settlement
transactions. The raw invoice status value `paid` may remain for lifecycle
compatibility.

## Derived States and Reporting

Invoices track demand lifecycle:

- Draft: planned but not issued.
- Sent: demanded and outstanding unless fully settled.
- Paid: settled.
- Voided: withdrawn.

Transactions track money movement.

Reports and billing summaries should distinguish:

- **Demanded / invoiced** — invoice lines on sent or paid invoices.
- **Outstanding** — sent invoice demand minus linked settlement transactions.
- **Collected** — transactions linked to invoices as settlement.
- **Unbilled** — eligible items and transactions not on a non-voided invoice,
  plus manual charges not yet sent if represented in draft invoices.

Until settlement linkage is implemented, paid invoice status may remain a
compatibility signal for collected state. The target model is auditable
collection through linked transactions.

Historical paid invoices should not get synthetic settlement transactions by
default. Readers should treat `Invoice.status == paid` as a compatibility-only
collected signal until a reviewed settlement backfill is intentionally run.

## Returns and Credits

Credits remain invoice lines with negative sign.

If an item on a collected invoice is returned or otherwise removed from the
project after the client paid, represent the client credit as negative invoice
demand / a credit line. Do not create an `expense`, `purchase`, or other
synthetic transaction for that credit. If money later moves back to the client,
that refund/payment is a separate money-movement transaction.

Returned paid item credits are created as ordinary draft invoices containing
only manual credit lines:

- `itemIds = []`
- `transactionIds = []`
- `sourceType = manual`
- `sourceId = nil`
- `sign = credit`
- `amountCents` copied from the original paid invoice line
- `budgetCategoryId` copied from the original paid invoice line
- `snapshotName` set to a human-readable returned-item credit label

The system must not mutate the original paid invoice. The original paid invoice
is a frozen historical demand. The draft credit invoice is a new demand artifact
that the user can review, send, void, or otherwise handle through the existing
invoice workflow.

The credit line's deterministic ID encodes or hashes:

```text
returnCredit:{paidInvoiceId}:{paidInvoiceLineId}:{itemId}
```

That ID prevents duplicate returned-paid-item credits across all non-voided
invoices. Human-readable explanation belongs in the credit line label and invoice
notes; the data model does not add separate returned-item credit metadata fields
unless a future workflow needs them.

## MCP and Contract Ingestion

MCP tools should operate on invoices and settlement linkage, not fake
transactions for future money.

Needed capabilities:

- Create draft invoices.
- Add existing item and transaction lines.
- Add manual New Charge lines.
- Build draft invoice lines from a contract.
- Mark an invoice or selected lines collected.
- Create or link settlement transactions.
- List invoice settlement state and outstanding balances.

Contract ingestion should create or update project fields and categorized draft
invoice manual lines for fee schedules. It should not create transactions until
payment is actually collected.

## Implementation Notes

- Existing `InvoiceLineSourceType` should expand from `item | transaction` to
  `item | transaction | manual`.
- Invoice lines need stable IDs for line-level settlement.
- Draft invoices can continue to render live previews for item and transaction
  lines. Manual lines store their amount and label on the draft line itself.
- Sent invoices freeze line names, signs, and amounts.
- Transactions with settlement linkage must be excluded from billable membership,
  budget demand calculations, and invoice pickers.
- The previous `billingStatus` model on items/transactions remains retired.
- Legacy `pending` and `completed` transaction statuses are not part of the
  conceptual model. Nil means active; `canceled` means canceled.

## Historical Context

This spec replaces the earlier v1/v2 split:

- v1 stored billing state on items and transactions and cascaded invoice status
  changes onto those records.
- The shipped v2 redesign moved paid-state onto invoices and introduced signed
  lines.
- The current target model keeps signed invoice lines but clarifies that
  transactions are money movement records and invoices are demands. Manual New
  Charge lines cover design fees and other demands that exist before money moves.
