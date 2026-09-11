# Transaction Creation Flow

> **Target-state notice (2026-08-30):**
> [Invoice-Centered Project Accounting](invoice-centered-project-accounting.md)
> is authoritative where it conflicts with this current flow. Target project
> Transactions record client-paid money movement: direct client-to-vendor
> purchases and whole-Invoice Client → 1584 payments. A direct client-paid
> physical-goods Transaction may have Items in Furnishings. 1584-paid project
> Expenses and inventory Item charges remain in Invoicing until collection.
> Target project types are exactly Purchase, Return, and same-Client Transfer;
> collection creates Purchase rather than Payment to Business. See
> [Client Identity and Project Transfers](client-identity-and-project-transfers.md).

## Purpose

The New Transaction flow records actual financial events. It does not create
invoice demand. Planned design fees, retainers, and other New Charges belong on
invoices until money actually moves. When money has moved, users can record it
as a Client Payment.

## Transaction Types

Normal user-created transactions use:

- `purchase` — money spent to buy goods or services.
- `return` — money credited/refunded back from a vendor, or item return flows.
- `paymentToBusiness` — money actually received from the client by the design
  business. Shown in the UI as **Client Payment**.

Other transaction types are system-created:

- `sale` — inventory operation when the business acquires project-originated
  items into inventory.

Legacy read-compatible values:

- `fee`
- `expense`
- `to inventory`

New normal write paths must not create those legacy values.

## Category And Itemization

Every transaction needs a `budgetCategoryId`.

Itemization is a property of the selected budget category, not the transaction
type. A `purchase` can be either:

- an itemized purchase, when the category is itemized/items, or
- a non-itemized purchase, when the category represents a service, labor, fuel,
  receiving, delivery, storage, install work, or similar project cost.

The transaction type alone must never trigger item entry or inventory routing.

## Steps

1. **Type** — Purchase, Return, or Client Payment.
2. **Who paid?** — shown for Purchase. Return skips this.
3. **Destination** — project selection.
4. **Budget Category** — required.
5. **Vendor / Source** — required for purchases and returns. Skipped for Client
   Payment.
6. **Details** — date, amount, notes, receipt fields, and itemized-only tax /
   subtotal fields when the selected category is itemized.

For Client Payment, budget categories are limited to fee/revenue categories such
as Design Fee. Client Payment never asks for items, tax/subtotal audit, source,
vendor, purchaser, or reimbursement fields.

## Inventory Routing

The post-create item-entry / sell-from-inventory path is offered only when all
of these are true:

```text
type == purchase
AND
selected budget category is itemized/items
AND purchasedBy == design-business
AND actual item rows exist / are being created
```

Business-paid service purchases must stay on the selected project and must not
show the sell-from-inventory path.

Examples that must not trigger inventory routing unless the category is
itemized and items exist:

- install labor
- installation services
- fuel
- delivery
- receiving
- storage
- bundled service work

## Reimbursement Fields

`purchasedBy` records who paid:

- `client-card`
- `design-business`

`reimbursementType` records a reimbursement handoff:

- `owed-to-company`
- `owed-to-client`
- `none` or missing

Approved legacy display values are normalized during migration:

- `Client` -> `client-card`
- `Design Business` -> `design-business`
- `Client Owes Design Business` -> `owed-to-company`
- `Design Business Owes Client` -> `owed-to-client`
- empty string -> missing

## Field Mapping

| Form field | Transaction field |
| --- | --- |
| Type | `type` |
| Destination project | `projectId` |
| Budget Category | `budgetCategoryId` |
| Vendor / Source | `source` |
| Date | `transactionDate` |
| Amount | `amountCents` |
| Who paid | `purchasedBy` |
| Reimbursement | `reimbursementType` |
| Notes | `notes` |
| Email Receipt | `receiptEmailed` |
| Subtotal, tax | itemized-category purchases/returns only |

## Related Specs

- [transaction-type.md](transaction-type.md)
- [item-entry-flow.md](item-entry-flow.md)
- [billing-invoicing.md](billing-invoicing.md)
- [transaction-completeness.md](transaction-completeness.md)
