# Invoice-Centered Project Accounting
Status: target-state redesign — approved direction, not implemented
Last updated: 2026-08-31
Program tracker: [../plans/ledger-accounting-redesign/README.md](../plans/ledger-accounting-redesign/README.md)
Companion Item lifecycle: [inventory-item-invoicing-lifecycle.md](inventory-item-invoicing-lifecycle.md)
Item intake and Link: [proto-item-capture.md](proto-item-capture.md)
Client and Transfer model: [client-identity-and-project-transfers.md](client-identity-and-project-transfers.md)
Impact analysis: [../plans/invoice-centered-project-accounting/impact-analysis.md](../plans/invoice-centered-project-accounting/impact-analysis.md)

## Purpose

Ledger must separate three facts that the current model sometimes conflates:

1. who actually paid money;
2. what 1584 plans to charge the client; and
3. which project budget category the underlying work belongs to.

The target design makes project Transactions a ledger of money the client has
actually paid or received, plus one explicit non-cash exception for direct
Transfers between projects owned by that same Client. Charges that 1584 expects
the client to pay live in Invoicing until the client pays an Invoice. Inventory
sales into and out of a project are represented to the user as Item charges or
credits, not as project Transactions.

This is a target-state specification. Existing specs continue to describe
shipped behavior until a migration phase explicitly replaces it. New work in
this area must use this document as the product direction and must not extend
the old project-side inventory-movement Transaction model.

## Accounting Boundary

Transaction meaning is relative to the owner of its scope:

- A client owns a project. A project-scoped Purchase records money paid by that
  client; a Return records money received back by that client. A paired Transfer
  is the sole non-cash exception for reallocating Items between that Client's
  projects.
- 1584 owns Business Inventory. An inventory-scoped Transaction records money
  paid or received by 1584 for inventory.
- An Invoice is a project-scoped demand from 1584 to the client. It is not proof
  that money moved.
- An Invoice line states what the client is being charged or credited for.

The rule is not that every Transaction has the same payer. Globally, target
types are `purchase`, `return`, and `transfer`. Purchase means the scope owner
paid; Return means the scope owner received money back. Transfer is valid only
as the paired same-Client project exception described below.

## Canonical Entry Routing

| Real-world event | Record created now | Where it lives | Needs invoicing? |
|---|---|---|---|
| Client pays a vendor directly for physical goods | Project Transaction with attached Items | Project | No |
| Client pays a vendor directly for a non-itemized cost | Project Transaction | Project | No |
| Client pays 1584 for a whole Invoice | One project Purchase with the Invoice's collected contents attached | Project | This is collection |
| 1584 buys physical goods | Inventory acquisition Transaction with attached Items | Business Inventory | Items become invoiceable only when sold into a project |
| 1584 pays a non-itemized project cost | Expense | Project Invoicing | Yes |
| 1584 refunds the client or the client pays an additional amount | Transaction when money actually moves | Project | Depends on the demand being settled |
| Client or 1584 receives a vendor refund | Return/refund Transaction in the scope whose owner receives the money | Project or Business Inventory | No new demand by itself |
| Same Client moves Items directly between two of its projects | Two linked Transfer Transactions, one in each project | Both projects | No; no money changed hands |

### Project Transaction types

Target project writes use exactly three values:

- `purchase` — the client paid money for goods and/or services, including a
  direct vendor purchase or payment of a 1584 Invoice;
- `return` — the client actually received money back; and
- `transfer` — the non-cash, same-Client project-to-project Item reallocation
  defined in
  [client-identity-and-project-transfers.md](client-identity-and-project-transfers.md).

`sale`, `paymentToBusiness`, `fee`, `expense`, and `to inventory` are not target
project write values. Legacy reads remain compatible during migration.

### Direct client-paid purchases

The project entry flow still asks who paid.

- If the client paid a vendor directly, create a project Transaction immediately.
- If the purchase contains physical goods, attach the Items to that Transaction
  and attribute them to Furnishings.
- If the purchase is non-itemized, use the selected project budget category.
- These records never enter Invoicing because the client has already paid.

### 1584-paid physical goods

Physical goods paid for by 1584 have one supported path:

1. create an inventory-scoped acquisition Transaction;
2. attach the purchased Items and receipt details to that Transaction;
3. keep the Items in Business Inventory, or sell them into a project; and
4. when sold into a project, expose an Item charge in that project's Invoicing
   area at the project-price basis.

Do not create a second business-paid project Purchase Transaction. The old
`project_reimbursement` path for physical goods is retired by this target model.

Quick Added project Items use the same boundary. **Business paid** Link may
optionally associate the inventory acquisition Purchase and creates the open
Item charge; it never creates a project movement Transaction. **Client paid**
Link instead requires the actual project Purchase and creates no Invoicing
demand. See [Quick Item Capture and Linking](proto-item-capture.md#link-routes).

### 1584-paid non-itemized costs

A non-itemized project cost paid by 1584 becomes an Expense in Invoicing. The
Expense owns its vendor, date, final amount, receipt image, notes, category, and
any embedded non-item receipt details. It is available to place on an Invoice.
It does not create a project Transaction until the client pays the Invoice.

### Worked West Elm example

- If the client uses the client's card at West Elm, Ledger creates a project
  Transaction for the West Elm payment and attaches the purchased Items in
  Furnishings. Nothing is owed to 1584, so those Items never enter Invoicing.
- If 1584 uses the business card at West Elm, Ledger creates an inventory-scoped
  acquisition Transaction and attaches the Items there. Selling an Item into a
  project creates an Item charge in that project's Invoicing area. When the
  client later pays an Invoice containing it, Ledger creates one project
  Transaction for the client's actual payment to 1584 and attaches the frozen
  Item occurrence as paid history.

The two paths can describe similar physical goods, but they cannot share the
same accounting record because different parties paid at different times.

## Project Invoicing Workspace

The user-facing project Invoicing area has these sections:

- **Items** — positive charges and negative credits caused by sales between
  Business Inventory and the project;
- **Expenses** — non-itemized project costs paid by 1584;
- **Fees** — planned charges such as design fees and retainers;
- **Invoices** — curated groups of the preceding records sent to or paid by the
  client.

“Item Movement” is not a user-facing record type. Ledger may retain hidden
sale/return occurrence records and lineage so repeated sales, returns, and price
bases remain auditable.

Manual Invoice adjustments are not finalized by this spec. They must not be
used as a quiet substitute for a typed Item, Expense, Fee, or credit record.

## Invoice Lifecycle

### Build and edit

Building an Invoice means curating which Items, Expenses, Fees, and supported
credits should be charged together.

- `created` and `sent` Invoices remain live until collection.
- Eligible edits to their source records update the live Invoice and its total.
- A source can belong to at most one non-canceled, uncollected Invoice.
- Invoice lines preserve stable source and occurrence identities; label matching
  is never sufficient.
- Whole-Invoice collection is the only supported collection mode for now.
  Partial payments and line-level collection are out of scope.

### Collect

Collection is one atomic, idempotent operation:

1. verify that the whole Invoice is collectible;
2. freeze the Invoice and every line at the collection boundary;
3. create one project Purchase for the actual Client → 1584 payment;
4. attach all collected Items, Expenses, Fees, and supported adjustment records
   to that Transaction as historical paid contents;
5. remove those records from the active Invoicing queues; and
6. mark the Invoice paid without deleting it or its lines.

The Purchase amount is the actual lump-sum payment. It is not split into one
Transaction per budget category. Category allocation comes from the frozen
Invoice contents attached to it.

“Attached to the Transaction” is historical accounting membership. It must not
overwrite an Item's current physical location or erase the source Expense/Fee
record needed for audit.

### Paid boundary

After collection:

- the paid Invoice, its lines, payment Transaction, total, and category
  allocations are immutable;
- later corrections use explicit credits, refunds, or accounting corrections;
- returning an Item does not remove it from the paid Transaction's historical
  contents; and
- source edits cannot silently rewrite the paid snapshot.

## Budget Progress

Each project category shows one progress line composed of two semantic segments:

1. **client paid** — qualifying direct client-paid project Transactions plus
   the frozen category allocations attached to collected Invoice payments;
2. **invoicing / unpaid** — open Item charges and credits, Expenses, and Fees,
   whether still available or already placed on a created/sent Invoice.

For category `c`:

```text
project progress(c) = client-paid(c) + invoicing-unpaid(c)
```

Collecting an Invoice transfers the same source amounts from the unpaid segment
to the paid segment. The category total must not change merely because the
Invoice was collected.

The lump-sum settlement Transaction is evidence of payment, not an additional
budget contribution. Budget allocation for that Transaction comes from its
frozen collected contents. Readers must never count both those contents and the
Transaction amount as project spend.

### Furnishings and Additional Requests

- Project Item charges and credits contribute to Furnishings.
- An Additional Requests tag is a non-exclusive reporting overlay on an Item.
- A tagged Item remains part of Furnishings.
- Additional Requests may show the subtotal of tagged Item activity, but that
  subtotal is not added to overall project spend a second time.

The visual colors for paid versus unpaid are presentation choices. Their
semantic meaning and arithmetic are fixed by this spec.

## Receipt Details

“Receipt details” means the information owned by the record of the actual
purchase: vendor, date, final amount, receipt image, Items, tax, shipping,
warranty, discounts, credits, and notes as applicable.

Do not introduce separate `PurchaseReceipt` or `VendorReceipt` entities merely
to implement this redesign. Receipt details remain on:

- a direct client-paid project Transaction;
- an inventory acquisition Transaction; or
- a 1584-paid Expense.

Moving an Item into a project does not automatically copy transaction-wide tax,
shipping, warranty, discounts, or credits into the project charge. Their
treatment must be explicit: absorbed into project price, included as a separate
Expense/charge, or otherwise governed by a later approved rule.

## Corrections and Refunds

- A mistaken association is a correction, not a sale, return, or payment.
- Before collection, correct the live source and Invoice atomically and retain
  an audit trail.
- After collection, preserve the paid records and use an explicit accounting
  correction, credit, or refund workflow.
- A vendor refund creates a Return/refund Transaction in the scope whose owner
  actually receives the money.
- A client credit does not create a Transaction merely because it exists. If it
  offsets a later Invoice, the resulting Purchase records the client's net cash
  payment and the credit settlement remains linked evidence. A cash refund to
  the client creates a Return.
- A direct same-Client project Transfer creates the paired non-cash records
  defined in the Client/Transfer spec. It bypasses Business Inventory and does
  not create a charge, credit, payment, or refund.

## Required Data Relationships

The target schema must distinguish these relationships instead of overloading
one mutable `item.transactionId`:

- Item acquisition Transaction;
- Item current physical placement;
- current open Item charge or credit occurrence;
- live Invoice membership;
- paid Invoice and frozen line membership;
- paid Transaction historical membership; and
- sale, return, and correction provenance.

Exact field names are an implementation decision. Every cross-record write at
collection, return, correction, or sale boundaries must be atomic, idempotent,
and safe to retry.

## Product Decisions Still Open

1. Whether paid Item credits may be applied to a future positive Invoice, paid
   back in cash, or both.
2. How a credit-only Invoice is closed and what Transaction proves a cash refund.
3. How pending negative credits render in the two-segment budget line.
4. Which Expense edits remain legal while available, on a created/sent Invoice,
   and after collection.
5. Whether hidden accounting occurrences extend the existing lineage model or
   use a dedicated internal entity.
6. How mixed receipt-level tax, shipping, warranty, discounts, and credits are
   allocated.
7. Whether manual Invoice adjustments remain and, if so, how they are typed and
   categorized.
8. Whether a live Invoice whose last line is removed auto-cancels or remains a
   noncollectible zero-dollar Invoice.
9. How a Business-paid Quick Added Item records unresolved acquisition evidence
   when the user Links it without selecting a Business Inventory Purchase.
10. Whether the actual positive Client payment recorded at whole-Invoice
    collection must exactly equal the Invoice's authoritative positive total.
    The initial recommendation is to require exact equality and reject a
    mismatch until Ledger has an approved model for payment fees, discounts,
    underpayments, or overpayments.
11. Which membership changes are permitted after an Invoice is sent and how a
    revised sent Invoice is versioned, rendered, and delivered. Source financial
    values remain live until collection under D-011; that does not by itself
    decide whether adding/removing sources requires an explicit revise-and-resend
    action and a preserved delivery audit.
12. What the Client Summary report's “Total Spent” and category totals mean:
    actual paid value, paid plus open recognized demand, or current physical Item
    project prices. The initial recommendation is to label paid and open/
    committed values separately and never call current Item prices paid spend.
13. Whether client-shared reports may include receipt evidence and, if so,
    whether it is embedded, attached, or exposed through a durable authorized
    delivery link. Expiring Storage tokens and raw private object paths must not
    be written into a shared PDF.
14. What happens to Items currently assigned to a Space when that Space is
    archived. The initial recommendation is to preserve the resolvable archived
    Space reference as historical/current location evidence, remove the Space
    from new-assignment pickers, and require an explicit Item move/clear action
    rather than silently erasing placement.

These questions do not reopen the accounting boundary, whole-Invoice
collection rule, or no-double-count budget invariant.

## Acceptance Invariants

- Project Purchases and Returns contain only real client money movement;
  Transfer is the sole non-cash project Transaction.
- Inventory Transactions contain only real 1584 inventory money movement.
- 1584-paid project demand is visible before collection without inventing a
  project Transaction.
- Every collected Invoice creates exactly one payment Transaction.
- Collection changes budget segment composition, not total progress.
- Paid records never change because an Item later moves or its mutable price
  changes.
- A single source or settlement is never counted twice in Invoicing, Invoices,
  Transactions, budgets, reports, or exports.
- Direct client-paid physical goods remain valid project Transactions with
  attached Items in Furnishings.
- 1584-paid physical goods always enter through Business Inventory.
- Quick Added Business-paid Items may enter project Invoicing without a selected
  acquisition link, but Ledger never fabricates an inventory Purchase; the
  missing evidence remains explicit and reconcilable.
