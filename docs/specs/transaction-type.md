# Transaction Type Taxonomy

## Target State

`Transaction.type` describes the event that happened. It does not describe
whether a row is itemized.

Canonical transaction event types:

| Type | Meaning | Writer |
| --- | --- | --- |
| `purchase` | Money spent to buy goods or services. | New Transaction, MCP create transaction |
| `return` | Vendor return/refund or item return movement. | New Transaction, inventory operations |
| `sale` | Business acquires project-originated items into inventory. | Inventory operations only |
| `paymentToBusiness` | Client pays the design business. | New Transaction Client Payment branch, invoice collection |

Legacy read-compatible values:

- `fee`
- `expense`
- `to inventory`

New writes must not create legacy values.

## Itemization

Itemization belongs to the budget category.

`purchase` is not an items-only type. A purchase can represent furnishings,
install supplies, installation services, fuel, receiving, storage, labor, or
other project costs. Whether the app asks for items, tax/subtotal audit, and
inventory routing depends on the selected budget category.

Inventory routing rule:

```text
selected budget category is itemized/items
AND purchasedBy == design-business
AND actual items exist / are being created
```

## Budget Categories

Every transaction must have `budgetCategoryId`.

Readers derive category behavior from `metadata.categoryType`.

- `metadata.categoryType = "itemized"`: item-backed purchases and returns.
- `metadata.categoryType = "general"`: non-itemized project cost purchases
  without item rows.
- `metadata.categoryType = "fee"`: company revenue/payment categories. Invoice
  collection and manual Client Payment entry create categorized
  `paymentToBusiness` transactions using fee/revenue categories.

Mixed budget category behavior is not an approved product concept and must not
be created by new UI or MCP writes.

## Invoice Collection

Invoices are demand. Transactions are money movement.

When an invoice is marked collected, the system groups settled invoice lines by
`budgetCategoryId` and creates one `paymentToBusiness` transaction per category.

Users may also record a Client Payment directly from New Transaction when money
has actually moved outside the invoice collection workflow. This writes
`type = paymentToBusiness`, requires a `categoryType = fee` budget
category, omits vendor/source, and must not include item, subtotal, tax,
discount, purchaser, or reimbursement fields.

Every settlement transaction stores:

- `type = paymentToBusiness`
- `projectId`
- `budgetCategoryId`
- `amountCents`
- `settlementInvoiceId`
- `settlementInvoiceLineIds`

Settlement transactions are not project spend and do not re-enter the billable
pool.

Returned paid item credits are not transactions. Returning a paid item to
inventory writes the legitimate inventory return movement, then creates invoice
credit demand as manual credit lines on an ordinary draft invoice. New writes
must not create `expense`, `purchase`, or any other synthetic transaction with a
source like `"Credit: returned ..."`.

## Migration Rules

Approved data migration rules:

- `expense -> purchase` for project-cost rows.
- historical 1584 Design `fee -> paymentToBusiness`.
- legacy `to inventory -> return` when it represents project-to-inventory return.
- normalize approved `purchasedBy` and `reimbursementType` display strings.
- remove `1584 Design Inventory` as the source on historical design-fee/payment
  rows; prefer no source unless validation requires `1584 Design`.

## Related Specs

- [transaction-creation.md](transaction-creation.md)
- [billing-invoicing.md](billing-invoicing.md)
- [sale-transactions.md](sale-transactions.md)
- [financial-access-controls.md](financial-access-controls.md)
