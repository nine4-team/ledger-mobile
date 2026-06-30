# Agent Transaction Taxonomy Guide

## Purpose

This is the short version for AI agents and MCP clients. Use this before
creating, editing, classifying, or explaining Ledger transactions.

## Transaction Types

`Transaction.type` records the event that happened. It does not record whether a
transaction is itemized.

Canonical event types:

| Type | Who writes it | Meaning |
| --- | --- | --- |
| `purchase` | User transaction creation / MCP `create_transaction` | Money spent to buy goods or services. |
| `return` | User transaction creation / inventory return flows | Vendor refund or item return event. |
| `sale` | Inventory tools only | Business acquires project-originated items into inventory. |
| `paymentToBusiness` | User Client Payment entry / invoice collection | Client payment actually received by the business. |

Normal user/tool transaction creation accepts `purchase`, `return`, and
`paymentToBusiness`. Do not create `sale` directly; use inventory movement
tools.

Legacy read/filter values may exist in old data:

- `fee`
- `expense`
- `to inventory`

Do not write those values.

## Budget Category Behavior

Itemization belongs to the budget category, not `Transaction.type`.

Use app/MCP `categoryKind` for behavior:

| categoryKind | Storage compatibility shape | Meaning |
| --- | --- | --- |
| `items` | `supportedTypes = ["purchase", "return"]` | Item-backed categories. Can have item rows, subtotal/tax audit, and inventory routing. |
| `projectCost` | `supportedTypes = ["expense"]` | Non-itemized project costs such as install services, install supplies, fuel, delivery, receiving, storage, or labor. Transactions are still `type = purchase`. |
| `feeCategory` | `supportedTypes = ["fee"]` | Company revenue/payment categories used by invoices and payment visibility. |
| `unknown` | Anything else | Migration/debug state. Do not create new categories in this state. |

The raw storage values `expense` and `fee` in `supportedTypes` are compatibility
markers for category behavior. They are not approved new transaction types.

## Creation Rules

For a non-itemized service/cost purchase, create:

- `type = purchase`
- `budgetCategoryId` pointing to a `categoryKind = projectCost` category
- no item rows

For an itemized purchase, create:

- `type = purchase`
- `budgetCategoryId` pointing to a `categoryKind = items` category
- item rows when actual items exist

The sell-from-inventory path is valid only when all are true:

```text
categoryKind == items
AND purchasedBy == design-business
AND actual item rows exist / are being created
```

For design fees, retainers, service charges, and other money the client owes
the business but has not paid yet, create invoice New Charge lines. Do not create
a transaction until money actually moves. Once money moves, either mark the
invoice collected or create a Client Payment transaction:

- `type = paymentToBusiness`
- `budgetCategoryId` pointing to a `categoryKind = feeCategory` category
- no source/vendor
- no item rows, subtotal, tax, discount, purchaser, or reimbursement fields

Returned paid item credits are invoice credit lines on draft invoices, not
synthetic credit transactions.

## MCP Guidance

- Call `server_info` and `describe_schema` once per session.
- Use `transactionTypeForCreate` for normal creation choices.
- Use `categoryKind` for itemization/routing choices.
- Treat `supportedTypes` and `categoryType` as storage/debug fields.
- `create_transaction_with_items` is for itemized categories only.
- `create_transaction` is for non-itemized purchases/returns or itemized vendor
  return shells when the inventory tool expects an existing return transaction.
