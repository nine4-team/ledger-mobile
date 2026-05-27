# Billing & Invoicing
Status: active redesign
Last updated: 2026-05-26
Implementation plan: [../plans/billing-invoicing-canonical-implementation.md](../plans/billing-invoicing-canonical-implementation.md)

## Summary

Billing is the boundary between money the business requests and money that has
actually moved.

- **Transaction** — a record that money moved.
- **Invoice** — a demand for money.
- **Invoice line** — one component of an invoice's demand.

Ledger supports two invoice workflows:

1. **Ad-hoc invoices** built from existing project records: items, reimbursable
   expenses, credits, and other transactions where money already moved.
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
    var amountCents: Int
    var sign: InvoiceLineSign
    var snapshotName: String?
    var settlementTransactionIds: [String]?
}
```

`id` is needed so settlement transactions can optionally target specific lines.
`sourceId` is nil for manual lines.

Line ID policy:

- New invoice lines use UUID strings created when the draft line is added.
- Backfilled historical lines use deterministic IDs derived from invoice id,
  source type, source id, and line index so migration is idempotent.
- Line IDs survive draft edits and are frozen into sent invoices.

Source meanings:

- `item` — demand is based on a project item.
- `transaction` — demand or credit is based on money that already moved, such as
  a reimbursable expense or client-paid credit.
- `manual` — demand is entered directly on the invoice, not backed by an item or
  prior transaction.

The UI should label the action for adding a manual line as **New Charge**.
Examples: "Design Fee 1 of 3", "Retainer", "Project Management Fee", "Storage
Fee", "Adjustment".

## Billable Pool

The To Invoice pool includes existing billable sources that are not already
claimed by a non-voided invoice:

- Project items that are not returned.
- Eligible non-itemized project transactions where money already moved and the
  transaction is not canceled.

Existing transactions are billable only when their shape represents money that
should be demanded or credited on an invoice. Settlement transactions are never
billable.

Fee transactions are treated as money movement. A fee transaction created when
the client pays the business is settlement evidence, not a planned receivable.

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

When the client pays, Ledger creates or links a fee transaction for the payment
event and links that transaction to the invoice or specific invoice lines.

### Mixed Invoice

One invoice can combine existing records and manual charges.

Example:

```text
Invoice:
- Existing expense transaction: delivery reimbursement       $300
- New Charge: Design Fee 1 of 3                            $2,500

Client pays $2,800:
- Create one transaction for the $2,800 payment event.
- Link it to the invoice.
```

The existing expense transaction records money out. The settlement transaction
records money in. Both are transactions because money moved in both cases, but
only the expense transaction is an invoice-line source.

## Collection Behavior

Ledger should support collecting at invoice or line granularity:

- **Whole invoice collected** — create or link one transaction for the amount
  collected and set `settlementInvoiceId`.
- **Selected lines collected** — create or link one transaction for the payment
  event and set `settlementInvoiceLineIds` to the settled lines.

Collection should follow real payment events. If one check/ACH/card payment
settles multiple lines, create one transaction, not one transaction per line.

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

If an item on a paid invoice is returned, Ledger may create a credit source
transaction or a manual credit line depending on the operation. The resulting
credit appears on a later invoice as a credit line. The credit source must be
clearly separated from settlement transactions so it does not get excluded from
the billable pool by mistake.

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

Contract ingestion should create or update project fields and draft invoice
manual lines for fee schedules. It should not create fee transactions until
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
