# Invoice Transaction Redesign Draft

> Status: working draft from design discussion on 2026-07-13. This is not final implementation guidance. It records the candidate redesign and the first code/spec reality check.

Implementation and UX changes are tracked separately in [invoice-redesign-change-plan.md](invoice-redesign-change-plan.md).

## Current Reality Check

The current canonical spec is [billing-invoicing.md](billing-invoicing.md). The current Swift model is `LedgeriOS/LedgeriOS/Models/Invoice.swift`.

Current Ledger already does **not** have a persisted `Receivable` object. Existing billable sources are:

- `Item`
- `Transaction`
- `InvoiceLine` with `sourceType == manual` for New Charges such as design fees

Current invoice lines already store:

```swift
struct InvoiceLine {
    var id: String
    var sourceType: InvoiceLineSourceType // item, transaction, manual
    var sourceId: String?
    var amountCents: Int
    var sign: InvoiceLineSign
    var budgetCategoryId: String?
    var snapshotName: String?
    var settlementTransactionIds: [String]?
}
```

Current invoice lifecycle is:

```swift
draft -> sent -> paid
draft/sent -> voided
```

Current behavior treats drafts as live previews and sent/paid invoices as frozen demand snapshots. This draft redesign rejects the sent/freeze boundary and chooses "live until paid" as the target.

## Purpose

The invoicing system exists to track and collect receivables: money that a client owes the design business for a project.

Transactions exist to track project financial activity and money movement. Invoices should not become a parallel transaction ledger.

## Definitions

These definitions are part of the spec. Future implementation work should use these meanings rather than inferring new ones from field names.

### Core Concepts

**Transaction**

A financial event or project activity record. Transactions track money movement, project spending, inventory movement, reimbursement direction, and client payments. A transaction is not an unpaid invoice demand.

**Invoice**

A project-scoped demand for money from the client. An invoice groups existing billable source records so the business can collect against them. An invoice is not proof that money moved.

**Receivable**

Money the client owes the design business. In this redesign, `receivable` is a product/UI concept, not a generic persisted object.

**Candidate receivable**

An existing source record that can appear in the top section of the Invoices page because it is potentially invoiceable. Candidate receivables are fee installments, reimbursable expense transactions, and eligible items.

**Source record**

The underlying domain record referenced by an invoice line. Target source records are:

- `FeeInstallment`
- `Transaction`
- `Item`

The source record owns the financial amount while the invoice is `created` or `sent`.

**Invoice line**

The link between an invoice and a source record. A sourced invoice line should not own a separate editable live amount. It may own invoice-specific presentation fields such as custom client-facing description and sort order.

**Client-facing description**

Optional invoice-line wording shown to the client. This may differ from the internal source record name. Description drift is acceptable because it is presentation, not financial truth. The final description is locked in the paid-boundary snapshot.

**Active invoice line**

An invoice line on an invoice whose status is `created`, `sent`, or `paid`. Active invoice lines block their source records from appearing as available candidates for another invoice.

**Available candidate**

A candidate receivable that is invoiceable and is not linked to an active invoice line.

### Invoice Status Terms

**Created**

The invoice exists and counts as a receivable grouping, but has not been marked sent to the client. `created` replaces the old vague `draft` concept.

**Sent**

The invoice has been sent to the client. `sent` is a pipeline state only. It does not freeze invoice line amounts.

**Paid**

The invoice has been paid. Marking an invoice paid creates/links settlement or payment transactions, writes paid-boundary snapshots, locks amount-changing edits to source records, and records the paid state.

**Canceled**

The invoice should no longer be collected. Canceled invoice lines release their source records back to the candidate pool. A paid invoice must have its payment corrected before it can be canceled.

**Unpaid**

A derived UI/filter concept, not a stored status:

```text
isUnpaid = status == created || status == sent
```

### Candidate Source Types

**Fee**

Money payable to the design business for services or business revenue, configured through fee budget categories.

**Fee category**

An account budget category where `BudgetCategory.metadata.categoryType == fee`. A project enables/configures that fee through `ProjectBudgetCategory`, including `budgetCents` when a configured fee amount exists.

**Fee installment**

A source record representing one billable portion of a project fee. The invoiceable row is the `FeeInstallment`; the fee category is its grouping/configuration context. A fee installment is not a payment and is not a generic receivable.

Fee installments are company-revenue records. They must respect financial access controls anywhere invoices or candidate receivables are shown.

**Fee group metrics**

Summary values shown for a fee category group in the candidate receivables UI:

- `Total`: full fee amount for this project fee category.
- `Invoiced`: fee installment amount attached to non-canceled invoices.
- `Received`: fee installment amount collected on paid invoices / settlement transactions.
- `To Invoice`: fee amount not yet attached to a non-canceled invoice; calculated as `Total - Invoiced`.

**Expense transaction**

A non-itemized project transaction for money the business already spent and expects the client to reimburse. It is invoiceable only when reimbursement direction indicates money is owed to the company. Its invoice amount comes from `transaction.amountCents`.

**Item sold to project**

An item that entered the project through a business-inventory sale or project-to-project sale path. It is invoiceable at `item.projectPriceCents`.

**Reimbursable vendor item**

An item attached to a vendor transaction marked `reimbursementType == "owed-to-company"`. It is invoiceable at `item.purchasePriceCents`.

**Client-paid item**

An item paid for by the client or otherwise not owed to the company. It should not appear as an invoice candidate.

### Amount And Snapshot Terms

**Live until paid**

Invoice line amounts derive from the underlying source record while the invoice is `created` or `sent`. Sending the invoice does not freeze amounts.

**Paid-boundary snapshot**

Historical invoice evidence written when the invoice becomes `paid`. It freezes final line amount, final client-facing description, final source display name, source ID/type, and payment timestamp/status. It is not editable live invoice state.

**Amount drift**

A mismatch between duplicated financial amount fields that both appear to be authoritative. The redesign avoids amount drift by deriving invoice amounts from source records until paid.

**Presentation drift**

A difference between internal source naming and client-facing invoice wording. This is allowed through invoice-line descriptions.

### Payment And Correction Terms

**Settlement/payment transaction**

A `paymentToBusiness` transaction generated or linked when an invoice is marked paid. It records actual collected money and links back to the invoice through `settlementInvoiceId` and optionally `settlementInvoiceLineIds`.

**Payment correction**

The operation used when an invoice was marked paid by mistake. It cancels generated settlement/payment transactions, restores the invoice to its pre-paid pipeline state, and writes a `paymentCanceled` invoice event. It is not a refund.

**Canceled transaction**

A transaction with `status == "canceled"`. Its accounting fields remain intact for history, but it contributes $0 to calculations. Generated settlement/payment transactions should be canceled this way during payment correction.

**Refund**

A real money-out event after money was actually received and later returned to the client. Refunds are distinct from payment correction and are not fully designed in this draft.

**Invoice event**

An append-only history record for invoice lifecycle operations such as `created`, `sent`, `paid`, `paymentCanceled`, and `canceled`.

## Page Model

The Invoices page has two main sections:

1. Things that can be invoiced
2. Things that have been invoiced

The top section is a candidate pool of invoiceable records. The bottom section is the list of invoices.

## Invoice Status

Decision: use a true pipeline status:

```swift
enum InvoiceStatus {
    case created
    case sent
    case paid
    case canceled
}
```

Meanings:

- `created`: invoice exists but has not been marked sent.
- `sent`: invoice has been sent to the client.
- `paid`: invoice has been paid.
- `canceled`: invoice should no longer be collected.

In this model, "unpaid" is derived:

```text
isUnpaid = status == created || status == sent
```

The key requirement is that `sent` must not freeze invoice line amounts. Invoices remain live until paid.

There is no proposed partial-payment, balance, overpayment, or underpayment model in this draft.

`draft` is not part of the target model unless we identify a real user workflow where an invoice-like object is being prepared but should not yet count as a receivable.

## Live Until Paid

Invoices are live while not paid.

While an invoice is created or sent, designers can edit the underlying billable records and the invoice should reflect those changes. Once an invoice is paid, the linked billable records should be locked from edits that would change the paid invoice amount.

Canceled invoices release their lines back into the candidate pool.

This conflicts with current canonical behavior, where `sent` freezes line amounts and names before payment. Target redesign: do not freeze at send time. Freeze/lock only at paid time.

## Receivables

Decision: do not create a generic persisted `Receivable` object for this redesign. Treat "receivable" as a concept or UI role.

Candidate receivables are existing domain records that can be invoiced:

- project fees
- non-itemized reimbursable expense transactions
- project items that are billable under existing item rules

Current Ledger already models receivables as a role played by existing records and invoice lines.

A separate receivable object risks creating duplicate amount/description truth that can drift from the underlying fee, item, transaction, or manual charge.

## Invoice Lines

Invoice lines attach source records to an invoice.

Candidate shape:

```swift
struct InvoiceLine {
    var id: String?
    var invoiceId: String
    var sourceType: InvoiceLineSourceType
    var sourceId: String
    var description: String?
    var sortOrder: Int?
}
```

Field meanings:

- `id`: stable invoice-line identifier.
- `invoiceId`: invoice that owns this line.
- `sourceType`: source record kind; target values are `feeInstallment`, `transaction`, and `item`.
- `sourceId`: document ID of the source record named by `sourceType`. It is required for sourced lines.
- `description`: optional client-facing wording for this invoice line.
- `sortOrder`: optional display ordering within the invoice.

Decision: invoice lines may have custom client-facing descriptions.

Rationale:

- client-facing wording may reasonably differ from internal item, fee, or transaction naming
- description drift is presentation drift, not amount drift
- paid locking rules should lock the final client-facing description along with the paid invoice

Decision: sourced invoice lines should not store an editable live `amountCents` while the invoice is `created` or `sent`.

Current code does store `amountCents` on every invoice line. That supports manual New Charges, returned paid item credits, and frozen sent/paid invoices.

Target redesign:

- sourced fee/item/transaction lines should derive amount live until paid
- paid invoices need a reliable locked amount; the source records are locked from amount-changing edits once paid
- new manual financial lines are removed from the target model

Implementation note: if a paid-invoice snapshot field is added for reporting/audit, it must be written only at the paid boundary. It must not be editable live invoice state.

## Candidate Pool Rules

A source record appears in the top candidate pool when it is invoiceable and is not linked to an active invoice line.

Active invoice means:

```text
invoice.status == created || invoice.status == sent || invoice.status == paid
```

Canceled invoice lines do not block the source record from becoming a candidate again.

## Candidate Source Types

### Fees

Fees are money payable to the business and known from project setup / project budget configuration.

Important complication: design fees are often not billed all at once. A project may have one total design fee but collect it in multiple installments.

Current understanding:

- the app already tracks project fees through budget categories / project budget configuration
- the redesigned invoice top section should auto-populate fee groups from the project
- we do not want the invoice redesign blocked on a large new design-fee installment engine

Reality check from code: `ProjectBudgetCategory` currently has `budgetCents` but no installment shape. `BudgetCategory` identifies fee categories through `metadata.categoryType == fee`.

Decision: create a lightweight `FeeInstallment` source object on demand.

Candidate shape:

```swift
struct FeeInstallment {
    var id: String
    var accountId: String
    var projectId: String
    var budgetCategoryId: String
    var label: String
    var amountCents: Int
    var sortOrder: Int?
    var createdAt: Date?
    var updatedAt: Date?
}
```

Field meanings:

- `id`: stable fee-installment document identifier.
- `accountId`: account scope.
- `projectId`: project that owns this installment.
- `budgetCategoryId`: fee category this installment belongs to. This points to an account `BudgetCategory` that is enabled for the project through `ProjectBudgetCategory`.
- `label`: internal/default display label for this installment, such as "Design Fee 1 of 3."
- `amountCents`: amount to bill for this installment.
- `sortOrder`: optional ordering within the fee group.
- `createdAt` / `updatedAt`: audit timestamps.

Why this is different from a generic receivable:

- it is specific to one real source type: project fees
- it gives design fee installments a source record without bringing back manual invoice lines
- it can be created just in time from the invoice page
- later, project creation can optionally pre-create default fee installments without changing invoice-line semantics

Candidate UX:

- The top fee section groups rows by enabled fee budget category.
- Each fee group shows existing unpaid/available fee installments.
- The group has an add/installment action for creating a new installment with label and amount.
- The group may show the configured total fee, already invoiced/paid installment total, and remaining amount if `ProjectBudgetCategory.budgetCents` is present.

Decision: fee installment totals should be enforced against `ProjectBudgetCategory.budgetCents` when a configured fee budget exists. The app should block creating or editing fee installments that push the total over the configured fee amount. If the business needs to bill more, the configured fee amount should be updated first so the source of truth stays clean.

Naming decision: use `FeeInstallment` because it is the thing being billed; payment happens later when the invoice is paid.

Access decision: users who do not have access to a fee category must not see that fee category's fee group, fee installments, invoice lines, invoice rows, totals, or summaries in ways that reveal hidden fee revenue.

### Expense Transactions

Expenses are costs the business has already paid and needs to be reimbursed for.

Expected behavior:

- source is a project transaction
- transaction is non-itemized/atomic
- transaction is marked or classifiable as reimbursable by existing rules
- amount comes from `transaction.amountCents`
- `transaction.amountCents` is the full transaction amount; `subtotalCents` is the separate pre-tax subtotal field
- when the invoice is marked paid, create/link the appropriate reimbursement/payment transaction

### Items

Items need to be reconciled with the current item model before finalizing amount rules.

Current implementation:

- `Item.purchasePriceCents`: what was paid for the item
- `Item.projectPriceCents`: what the project/client is charged for the item
- item writes maintain `projectPriceCents >= purchasePriceCents`; invoice candidate readers defensively resolve `max(projectPriceCents ?? 0, purchasePriceCents ?? 0)` for legacy data
- inventory-to-project movement requires `projectPriceCents`
- project-to-inventory exits are origin-aware: inventory Returns reverse normalized `projectPriceCents`, while project-originated Sale-to-Inventory acquisitions use `purchasePriceCents`

Current conceptual direction to preserve:

- some items are billed as design-business sales to the project
- some items are reimbursed at purchase cost with no markup
- the amount basis should come from existing item fields and current inventory/sale transaction rules, not new guessed fields

Target item amount rule:

```text
if the item entered the project through a business-inventory sale:
  invoice at item.projectPriceCents
if the item belongs to a reimbursable vendor transaction:
  invoice at item.purchasePriceCents
```

Interpretation:

- `projectPriceCents` is the price charged to the project/client.
- `purchasePriceCents` is the cost basis.
- Items sold to the project use `projectPriceCents`.
- Reimbursable vendor-purchase items use `purchasePriceCents`.
- Items outside those two eligibility paths should not appear as invoice candidates.

Item candidate eligibility is separate from item pricing:

1. Business sold item to project.
   - The item entered the project from business inventory / project-to-project sale.
   - Candidate amount basis: `projectPriceCents`.

2. Reimbursable vendor item.
   - The item is attached to a project transaction whose source is a vendor other than the business/inventory.
   - The transaction is marked as owed to the company / business should be reimbursed.
   - Candidate amount basis: `purchasePriceCents`.

Excluded:

- client-paid items
- non-reimbursable vendor purchases
- returned items
- items already linked to an active invoice line

Research result: current code uses `InventoryOperationsService.cameFromInventory(item)`, which compares `item.currentSource` to `item.source`. That is the current operation heuristic, but it should not be the final invoice-pricing source of truth because those are mutable item fields and can drift.

Better target detection:

1. Prefer the item's current transaction and reimbursement direction.
   - If `item.transactionId` points to a `Purchase` transaction whose `source` is an inventory label and whose `projectId` is the current project, the item entered the project through the sell-to-project path. Invoice at `projectPriceCents`.
   - If `item.transactionId` points to a normal vendor transaction and `transaction.reimbursementType == "owed-to-company"`, the item is reimbursable. Invoice at `purchasePriceCents`.
   - If the current transaction is client-paid or has no owed-to-company reimbursement direction, the item is not a candidate.

2. Use lineage as the durable audit fallback / cross-check.
   - A `lineageEdges` record with `movementKind == "sold"` and `toProjectId == invoice.projectId` means the item entered this project via inventory/project-to-project sale. Invoice at `projectPriceCents`.
   - A same-project `association` or normal transaction link without a matching sold-to-project edge points toward project-originated purchase. Invoice at `purchasePriceCents`.

3. Use `currentSource != source` only as a legacy fallback when transaction shape and lineage are unavailable.

Implementation requirement: define a shared item invoiceability/pricing resolver. The invoice code should not re-implement a string heuristic inline.

## Payment And Correction

Marking an invoice paid should be an operation, not just a raw boolean update.

Expected behavior:

```text
markInvoicePaid(invoiceId)
  -> require invoice.status == created || invoice.status == sent
  -> create/link required payment or reimbursement transaction records
  -> set invoice.status = paid
  -> set invoice.paidAt
```

If a paid invoice was marked paid by mistake, the correction should not silently delete financial history.

Expected correction:

```text
voidInvoicePayment(invoiceId)
  -> require invoice.status == paid
  -> cancel generated settlement/payment transaction records
  -> restore invoice.status to its pre-paid pipeline state, normally sent
  -> write paymentCanceled InvoiceEvent
```

Refund means money was actually received and later returned. It is distinct from voiding a mistaken payment. This draft does not yet define a complete refund workflow.

Decision: mistaken payment correction cancels generated settlement/payment transactions; it does not create reversal transactions. Reversal transactions belong to refund or other real money-out workflows.

Implementation detail: the existing transaction cancellation convention is sufficient for generated settlement/payment transactions. Set generated settlement/payment transactions to `status == "canceled"` and keep their `settlementInvoiceId` / `settlementInvoiceLineIds` intact. The invoice should record the correction with an `InvoiceEvent`. Do not silently delete settlement transactions.

## Cancellation

Expected behavior:

```text
cancelInvoice(invoiceId)
  -> allowed for created or sent invoices
  -> set invoice.status = canceled
  -> set invoice.canceledAt
  -> release source records back to the candidate pool
```

For paid invoices, require payment correction first:

```text
paid -> void payment -> restored pre-paid status -> canceled
```

The restored pre-paid status is normally `sent`.

## Implementation Guidance

The product model is coherent enough to implement without adding more domain concepts. Remaining decisions should be treated as implementation policy, not reasons to expand the core model.

### Central Resolver

Implement a single shared resolver for invoice candidate eligibility and amount basis. Views, invoice services, reports, and migration code should call this resolver rather than re-implementing source-specific rules.

Example shape:

```swift
resolveInvoiceCandidate(source, context) -> eligible / ineligible + amountCents + reason
```

The resolver owns:

- fee installment eligibility and remaining-budget enforcement
- expense transaction eligibility and amount basis
- item eligibility and price basis
- exclusion reasons for client-paid, non-reimbursable, returned, canceled, or already-invoiced records

### Paid Snapshot

Even though invoices stay live until paid and source records are locked after payment, paid invoices should write a paid-boundary snapshot for audit/reporting.

This snapshot is not live invoice state and should not be editable. It is historical evidence of what was collected:

- final line amount
- final client-facing description
- final source display name
- source ID and source type
- paid timestamp / invoice status at payment

Before payment, sourced invoice lines derive amounts from their source records. At payment, the final values are frozen.

### Invoice Events

Use an invoice event log for operations with audit meaning:

- created
- sent
- paid
- paymentCanceled
- canceled

The invoice document can still store current status and convenience timestamps. Events preserve the history of how the invoice reached that state, especially payment correction.

Store invoice events as append-only history, similar to `lineageEdges`, not as mutable invoice fields. Candidate path:

```text
accounts/{accountId}/invoiceEvents/{eventId}
```

Payment correction should:

- cancel generated settlement/payment transactions
- restore the invoice to its pre-paid pipeline state, normally `sent`
- write a `paymentCanceled` invoice event

### Migration

Treat migration from the current model as its own design pass after the target model is finalized.

Do not distort the target model to preserve legacy concepts such as manual invoice lines or the old `draft/sent/voided` semantics. Instead, map existing data into the clean model deliberately:

- old `draft` / `sent` / `paid` / `voided`
- existing `InvoiceLine.amountCents`
- manual lines
- settlement transactions
- sent/frozen snapshots

## Design Principle

An invoice is a grouping of existing billable project records. It starts `created`, can become `sent`, can become `paid`, and can be canceled before payment. Amount truth should live on the source records and source-specific billing rules, not duplicated across invoice-specific financial fields.
