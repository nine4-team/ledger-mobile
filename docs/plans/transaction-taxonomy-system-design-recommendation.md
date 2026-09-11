# Transaction Taxonomy System Design Recommendation

Status: historical recommendation for the superseded June taxonomy
Created: 2026-06-26

> Do not implement this document's `sale`/`paymentToBusiness` target as the
> coming redesign. Preserve its analysis as historical evidence. Current
> authority: [Ledger Accounting Redesign](ledger-accounting-redesign/README.md).

Execution plan: `docs/plans/transaction-taxonomy-execution-plan.md`

## Recommendation

Keep `Transaction.type` focused on the real-world transaction event, and move
itemization, reimbursement, and invoicing semantics back to the fields that
already represent those concepts.

Recommended transaction event types:

| Type | Meaning |
|---|---|
| `purchase` | Someone paid an outside vendor/provider for project goods or services. The payer may be the design business or the client. |
| `return` | Value/money moved back because goods were returned, credited, or moved back through an approved return flow. |
| `sale` | Item/value moved out of a project, especially project-to-inventory sale/acquisition. |
| `paymentToBusiness` | The client paid the design business. Usually settlement evidence for an invoice. |

Long-term, remove these from `Transaction.type`:

| Type | Replacement |
|---|---|
| `expense` | `type = purchase` plus a non-itemized project-cost category. |
| `fee` | Planned fee: manual invoice line. Actual received fee/payment: `type = paymentToBusiness`. |

## Why `paymentToBusiness`

`collection` was too workflow/accounting-flavored and could be confused with
marking an invoice collected. `paymentToBusiness` is directional and explicit:
money came from the client to the design business.

It should be used only when money actually moved. A planned design fee,
retainer, or installment remains an invoice line until paid.

## Existing Fields To Keep

These concepts already exist and should not be duplicated:

| Existing field | Job |
|---|---|
| `Transaction.purchasedBy` | Who paid the vendor/provider on a `purchase`: design business or client. |
| `Transaction.reimbursementType` | Who ultimately owes whom: `owed-to-company`, `owed-to-client`, or none/missing. |
| `Transaction.itemIds` | Item records attached to this transaction. Empty can mean missing item docs; it is not proof that the transaction is non-itemized. |
| `Transaction.budgetCategoryId` | Category attribution for budget/reporting behavior. |
| `Transaction.settlementInvoiceId` | This transaction settled an invoice and must not re-enter the billable pool. |
| `Transaction.settlementInvoiceLineIds` | Optional line-level settlement targeting. |
| `BudgetCategory.metadata.categoryType` | Existing legacy itemization/category signal. Must not be cleared until a clean replacement is approved and migrated. |
| `BudgetCategory.supportedTypes` | Existing taxonomy field. Should not be used to support Mixed categories as a normal product path. |

## Itemization

Itemization belongs to the category, not to `Transaction.type`.

Current approved routing rule:

```text
routeThroughInventory =
  selected category is itemized/items
  AND purchasedBy == design-business
```

Do not use:

```text
routeThroughInventory =
  transaction.type == purchase
  AND purchasedBy == design-business
```

The category itemization signal can be the repaired legacy field:

```text
metadata.categoryType == itemized
```

or a future explicit field:

```text
itemizationMode = items | none
```

But the concept must remain category-owned.

## Billing And Invoicing

The active billing spec says:

- Transactions record money movement.
- Invoices demand money.
- Manual invoice lines cover planned charges before payment.
- Settlement is represented by linking a real money-movement transaction to an
  invoice.

Therefore:

- A design fee to be billed later is a manual invoice line, not a transaction.
- A client payment for that design fee is a `paymentToBusiness` transaction with
  `settlementInvoiceId`.
- Every transaction must carry a `budgetCategoryId`. For invoice settlement, the
  payment transaction's category comes from the invoice line category being
  settled.
- Manual invoice lines / New Charge lines must require an explicit budget
  category. Do not default this field silently.
- If a collected invoice contains multiple budget categories, create one
  `paymentToBusiness` transaction per budget category represented in the settled
  lines.
- A reimbursable installer payment is a `purchase` transaction with
  `reimbursementType = owed-to-company`.
- A client-paid project cost that should become a credit is a `purchase`
  transaction with `purchasedBy = client` and/or
  `reimbursementType = owed-to-client`.
- If an item was already collected from the client and later leaves the project,
  represent the client credit as negative invoice demand / a credit line, not as
  an `expense` transaction.

## Example Rows

| Scenario | type | purchasedBy | reimbursementType | itemized category? | invoice behavior |
|---|---|---|---|---|---|
| Business buys sofa from Wayfair | `purchase` | `design-business` | `owed-to-company` if billable | yes | Item lines are invoice charges. |
| Client buys faucet directly | `purchase` | `client` | `owed-to-client` if credited | yes or no | Credit if business owes client. |
| Business pays installer | `purchase` | `design-business` | `owed-to-company` if billable | no | Transaction line charge. |
| Client pays installer directly | `purchase` | `client` | `owed-to-client` if credited | no | Transaction line credit. |
| Draft design fee | no transaction | n/a | n/a | n/a | Manual invoice line. |
| Client pays invoice | `paymentToBusiness` | n/a | n/a | category of settled invoice line(s) | One settlement transaction per budget category; excluded from billable pool. |
| Project-originated item sold to inventory | `sale` | n/a | derived by inventory direction | item category attribution retained on tx | Project budget egress/credit behavior. |

## Data Repair Implications

Do not run blanket `purchase -> expense` repairs.

Instead:

1. Decide the canonical category shape for each Mixed category.
2. Decide item backfill needs per transaction.
3. Convert existing `expense` transaction rows back to `purchase` where they are
   project costs.
4. Convert existing `fee` rows according to what they actually represent:
   - planned fee demand: should be invoice line, not transaction;
   - actual client payment: should be `paymentToBusiness`.
5. Remove Mixed category support after production data no longer depends on it.

## Open Naming Decisions

- Confirm raw value spelling: `paymentToBusiness` vs `payment_to_business`.
- Decide whether UI label should be `Payment to Business`, `Client Payment`, or
  `Payment Received`.
- Decide whether `metadata.categoryType` should be retained as-is or migrated to
  an explicit `itemizationMode` field after the immediate repair.

## Settled Category Cleanup Decisions

- `Additional Requests` item-like rows such as BLVD Home and custom artwork move
  to Furnishings.
- `Kitchen` rows from Deni's Kitchens stay Kitchen.
- Split legacy `Install` into:
  - `Install Services` for install labor/service rows, Dean install rows,
    and bundled install service expenses.
  - `Install Supplies` for Home Depot, Lowe's, ACE, and similar install supply
    purchases.
- Speedway Gas goes to Fuel.
- FedEx receiving/tariff/freight-style rows go to Receiving when the project has
  a Receiving category; otherwise use Install Services.
- Historical design-fee/payment rows should not use an inventory source. Prefer
  no `source` for those rows; if a source is required by validation or display,
  use the business name, e.g. `1584 Design`.

## Non-Goals

- Do not resurrect old billing-status cascades.
- Do not make invoices automatic.
- Do not use `Transaction.type` as the itemization signal.
- Do not treat empty `itemIds` as proof that a transaction is non-itemized.
