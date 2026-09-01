# Billing & Invoicing
Status: current implementation model — target replacement approved
Last updated: 2026-08-30
Implementation plan: [../plans/billing-invoicing-canonical-implementation.md](../plans/billing-invoicing-canonical-implementation.md)

> **Target-state notice (2026-08-30):**
> [Invoice-Centered Project Accounting](invoice-centered-project-accounting.md)
> replaces this document as the approved redesign direction where the two
> conflict. In particular, the target uses Items/Expenses/Fees as invoiceable
> sources, whole-Invoice collection, one actual lump-sum payment Transaction,
> typed `purchase` because the client paid 1584, and frozen source-based category
> allocations. This document remains the
> reference for current behavior until the staged migration is implemented.

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
2. **Fee invoices** built from `FeeInstallment` source records for future or
   planned fees, such as design fees, retainers, storage fees, kitchen fees, or
   project management fees.
3. **Manual adjustments** entered directly on an invoice when no item,
   transaction, or planned-fee source exists.

The app must not create a transaction for money that has not moved. If the team
needs to request money before collection, create a source record and invoice it.
For fees, that source record is `FeeInstallment`. When collection happens,
create or link a transaction and connect it to the invoice as settlement
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
existing source records and invoice-only manual adjustment lines.

Lifecycle:

- `created` — editable planned demand. The invoice can stage fee installments,
  items, and reimbursable costs before sending.
- `sent` — issued demand. Created and sent invoices stay live until collection;
  paid invoices use the paid-boundary snapshot.
- `paid` — settled demand. This status should be supported by linked settlement
  transactions, either created through the Mark Collected flow or linked after
  the fact.
- `canceled` — withdrawn demand. Its existing sources return to the billable
  pool unless they are claimed by another non-canceled invoice.

Legacy reads may contain `draft` or `voided`; read them as `created` and
`canceled` respectively.

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
    case feeInstallment
    case manual
}

struct InvoiceLine {
    var id: String
    var sourceType: InvoiceLineSourceType
    var sourceId: String?
    var sourceTransactionId: String?
    var budgetCategoryId: String?
    var amountCents: Int
    var sign: InvoiceLineSign
    var snapshotName: String?
    var settlementTransactionIds: [String]?
}
```

`id` is needed so settlement transactions can optionally target specific lines.
`sourceId` is nil for manual lines.
For item-backed lines, `sourceTransactionId` records which transaction association supplied the item's billing basis/category when the line was materialized. This additive reference prevents a later category correction from guessing after the same item has moved through another transaction. Legacy lines may omit it; ambiguous legacy lines must block an automatic correction rather than be rewritten speculatively.
`budgetCategoryId` is required for every line. It should be resolved from the
source record for item, transaction, and fee-installment lines. Manual lines use
the reserved system category `Other Client Charges & Credits`; users never pick
this category. Invoice settlement uses the resolved category to create
categorized payment transactions.

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
- `feeInstallment` — demand is based on a planned/future fee source record such
  as a design fee, kitchen fee, retainer, storage fee, or project management
  fee.
- `manual` — invoice-only charge or credit not backed by a normal source record.
  Manual adjustments have a description, positive magnitude, and sign; normal
  manual adjustments use the reserved `Other Client Charges & Credits` category.
- `manual` with `sign == credit` may also represent a system-generated credit
  demand that should not claim a source item or transaction as normal invoice
  membership, such as a paid item returned to inventory.

The UI should let users create fee installments inline from invoicing so a
single kitchen fee or design-fee installment does not feel like a separate chore.
The app writes the `FeeInstallment` first, then adds a `feeInstallment` invoice
line that references it.

The manual-adjustment form asks for only description and amount. It routes the
line to `Other Client Charges & Credits` automatically; that system category is
not selectable in normal category, budget, item, or transaction workflows.

## Billable Pool

The To Invoice pool includes existing billable sources that are not already
claimed by a non-canceled invoice:

- Project items that are not returned.
- Eligible non-itemized project transactions where money already moved and the
  transaction is not canceled.
- Fee installments for planned/future fees.

Existing transactions are billable only when their shape represents money that
should be demanded or credited on an invoice. Settlement transactions are never
billable.

`paymentToBusiness` transactions are treated as money-in movement. A
`paymentToBusiness` transaction created when the client pays the business is
settlement evidence, not a planned receivable.

Manual lines are not discovered from the pool because they do not represent the
normal source-record model. Fee installments are discovered from the pool because
they are the project-level source records for planned fees.

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

### Fee Invoice

Used when no money has moved yet and the team needs to demand a design fee,
retainer, service fee, or other planned amount.

Example:

```text
FeeInstallments:
- Design Fee 1 of 3       $2,500
- Design Fee 2 of 3       $2,500
- Design Fee 3 of 3       $2,500

Created invoice:
- Design Fee 1 of 3       sourceType: feeInstallment
- Design Fee 2 of 3       sourceType: feeInstallment
- Design Fee 3 of 3       sourceType: feeInstallment
```

Those installments may exist before they are invoiced. They are not
transactions. The invoice lines link to them.

When the client pays, Ledger creates or links categorized `paymentToBusiness`
transaction(s) for the payment event and links those transaction(s) to the
invoice or specific invoice lines.

### Manual Adjustment

Used for an invoice-only amount that is not an item, an existing project cost,
or part of a planned fee schedule. The user enters a description and amount;
the line is stored as `sourceType: manual` and creates no transaction until the
invoice is collected.

Manual charges and credits settle through the reserved system category **Other
Client Charges & Credits**. This preserves the invariant that every settlement
transaction has a category without misclassifying the adjustment as a normal
fee or project-budget category.

### Mixed Invoice

One invoice can combine existing records and fee installments.

Example:

```text
Invoice:
- Existing expense transaction: delivery reimbursement       $300
- Fee installment: Design Fee 1 of 3                       $2,500

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
  transaction(s), set `settlementInvoiceLineIds` to the settled lines, and keep
  the invoice `sent` until every line has been settled.

Collection should follow real payment events and budget-category attribution. If
one check/ACH/card payment settles multiple lines in one budget category, create
one transaction for that category. If it settles multiple budget categories,
create one `paymentToBusiness` transaction per budget category represented by the
settled lines.

Every settlement transaction must have a `budgetCategoryId`. If a selected line
cannot resolve a budget category, the app should block collection until the line
or source record is categorized.

### Purchase-from-Inventory Category Corrections

An eligible Purchase from Business Inventory may be reclassified before collection. Because item- and transaction-backed invoice lines derive `budgetCategoryId` from their source, the correction keeps affected created/sent, uncollected line category snapshots aligned with the new project-enabled itemized category.

The ordinary correction is blocked when an affected line has an active settlement/payment transaction or its invoice is paid. Canceled invoices and canceled settlement transactions do not create a lock. Once collection has categorized real money received, changing that accounting requires a separate explicit collected-accounting correction; the normal Purchase editor must not silently rewrite invoice or payment history.

This rule does not change invoice amounts and does not itself choose between whole-invoice and selected-line collection. It defines the safe category boundary for either stored-data shape.

For a normal manual adjustment, the category is always the reserved system
category **Other Client Charges & Credits**. A returned paid-item credit is an
exception: it retains the original paid line's category because it reverses that
known prior demand.

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

Collection must not settle the same invoice line twice. If a selected line
already has an active settlement transaction, the app/tool should block
collection until the mistaken payment is canceled or the user selects only
unsettled lines.

## Derived States and Reporting

Invoices track demand lifecycle:

- Created: planned but not issued.
- Sent: demanded and outstanding unless fully settled.
- Paid: settled.
- Canceled: withdrawn.

Transactions track money movement.

Reports and billing summaries should distinguish:

- **Demanded / invoiced** — invoice lines on sent or paid invoices.
- **Outstanding** — sent invoice demand minus linked settlement transactions.
- **Collected** — transactions linked to invoices as settlement.
- **Unbilled** — eligible items, transactions, and fee installments not on a
  non-canceled invoice.

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

Returned paid item credits are created as ordinary created invoices containing
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
is a frozen historical demand. The created credit invoice is a new demand artifact
that the user can review, send, void, or otherwise handle through the existing
invoice workflow.

The credit line's deterministic ID encodes or hashes:

```text
returnCredit:{paidInvoiceId}:{paidInvoiceLineId}:{itemId}
```

That ID prevents duplicate returned-paid-item credits across all non-canceled
invoices. Human-readable explanation belongs in the credit line label and invoice
notes; the data model does not add separate returned-item credit metadata fields
unless a future workflow needs them.

## MCP and Contract Ingestion

MCP tools should operate on invoices and settlement linkage, not fake
transactions for future money.

Needed capabilities:

- Create fee installments for planned/future fee demand.
- Create created invoices.
- Add existing item and transaction lines.
- Add fee-installment lines.
- Add manual adjustment lines without asking the user to choose a budget
  category.
- Build fee installments and created invoice lines from a contract.
- Mark an invoice or selected lines collected.
- Create or link settlement transactions.
- List invoice settlement state and outstanding balances.

Contract ingestion should create or update project fields and categorized
`FeeInstallment` records for fee schedules, optionally adding those installments
to a created invoice. It should not create transactions until payment is
actually collected.

## Implementation Notes

- Existing `InvoiceLineSourceType` should support
  `item | transaction | feeInstallment | manual`.
- Invoice lines need stable IDs for line-level settlement.
- Created invoices can continue to render live previews for item, transaction,
  and fee-installment lines. Manual lines store their amount and label on the
  line itself.
- The system provisions **Other Client Charges & Credits** on first use as a
  hidden, excluded-from-budget category. Its stable ID is
  `system-other-client-charges-and-credits`.
- Paid invoices freeze line names, signs, and amounts.
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
  transactions are money movement records and invoices are demands.
  FeeInstallment source records cover design fees and other planned fee demand
  that exists before money moves.
