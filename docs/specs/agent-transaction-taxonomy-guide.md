# Agent Transaction Taxonomy Guide

> **Migration warning (2026-08-30):** This is the current write guide for
> shipped clients. The approved target in
> [Invoice-Centered Project Accounting](invoice-centered-project-accounting.md)
> removes project-side inventory movement Transactions and category-grouped
> Invoice settlements. The target project enum becomes Purchase, Return, and
> same-Client Transfer under
> [Client Identity and Project Transfers](client-identity-and-project-transfers.md).
> Agents must not simulate the target schema before its trusted writers and
> migration are shipped, but must not extend the legacy model as new architecture
> either.

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

Use `metadata.categoryType` for behavior:

| categoryType | Meaning |
| --- | --- |
| `itemized` | Item-backed categories. Can have item rows, subtotal/tax audit, and inventory routing. |
| `general` | Non-itemized project costs such as install services, install supplies, fuel, delivery, receiving, storage, or labor. Transactions are still `type = purchase`. |
| `fee` | Company revenue/payment categories used by invoices and payment visibility. |
| missing/unknown | Migration/debug state. Do not create new categories in this state. |

Category behavior is `metadata.categoryType`.

## Creation Rules

For a non-itemized service/cost purchase, create:

- `type = purchase`
- `budgetCategoryId` pointing to a `categoryType = general` category
- no item rows

For an itemized purchase, create:

- `type = purchase`
- `budgetCategoryId` pointing to a `categoryType = itemized` category
- item rows when actual items exist

The sell-from-inventory path is valid only when all are true:

```text
categoryType == itemized
AND purchasedBy == design-business
AND actual item rows exist / are being created
```

For design fees, retainers, service charges, and other money the client owes
the business but has not paid yet, create invoice New Charge lines. Do not create
a transaction until money actually moves. Once money moves, either mark the
invoice collected or create a Client Payment transaction:

- `type = paymentToBusiness`
- `budgetCategoryId` pointing to a `categoryType = fee` category
- no source/vendor
- no item rows, subtotal, tax, discount, purchaser, or reimbursement fields

Returned paid item credits are invoice credit lines on draft invoices, not
synthetic credit transactions.

## MCP Guidance

- Call `server_info` and `describe_schema` once per session.
- Use `transactionTypeForCreate` for normal creation choices.
- Use `metadata.categoryType` for itemization/routing choices.
- `create_transaction_with_items` is for itemized categories only.
- `create_transaction` is for non-itemized purchases/returns or itemized vendor
  return shells when the inventory tool expects an existing return transaction.
