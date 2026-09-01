# Invoice-Centered Project Accounting: Corrected Architecture and Impact Analysis

**Status:** Working design record; agreed boundaries plus unresolved decisions; not yet implementation-ready

**Created:** 2026-08-30
**Last updated:** 2026-08-31

**Central program tracker:** [Ledger Accounting Redesign](../ledger-accounting-redesign/README.md)

**Replaces:** the superseded one-Transaction-per-project Inventory Activity proposal in [the historical net-ledger research](../inventory-project-net-ledger/report-source.md).

## What is settled

The current direction is:

1. **Transaction meaning is relative to the owner of its scope.** A Transaction records real money movement by or to the entity that owns the project or inventory scope.
2. **Project-scoped Transactions show payments made by the client, because the client owns the project.**
3. **Business-inventory-scoped Transactions show purchases made by 1584, because 1584 owns business inventory.**
4. **A direct Client → Vendor purchase remains a project Transaction.** It keeps its vendor, amount, budget category, receipt details, and physical Items when itemized. It contributes to project budget spend.
5. **A Client → 1584 invoice payment is also a project Transaction.** It links to the Invoice and records the actual lump-sum payment. It does not contribute to budget spend because the underlying invoiced activity already did.
6. **A direct 1584 → Vendor business-inventory purchase remains an inventory-scoped Transaction.** It owns the acquired Items and purchase details; it does not affect a project budget until an Item is sold into a project.
7. **1584-paid project Expenses live in the invoicing workspace.** They contribute to their project budget categories immediately and can be selected onto an Invoice.
8. **When an Item is sold between business inventory and a project, the Item appears in the invoicing workspace as a Furnishings charge or credit—not as a project Transaction.** The implementation keeps movement history underneath, but “Item Movement” is not a required user-facing object.
9. **An Invoice groups amounts the client owes.** Paying it creates or links a client-payment Transaction; the Invoice remains as historical demand and is not deleted or converted destructively.
10. **There is no longer one aggregate user-facing Inventory Activity Transaction per project.**
11. **Additional Requests is a tag/overlay on Furnishings activity.** It does not remove the Item from Furnishings and does not add the same spend to Overall Spend twice.
12. **Invoices are collected only as a whole for now.** Building an Invoice is the act of curating which Items, Expense lines, Fees, and adjustments should be charged together. Collection creates one Client → 1584 project Transaction for the whole Invoice; line-level collection and partial payments are out of scope.
13. **Created and sent Invoices remain live until collection.** Eligible source amount/category changes flow through to the uncollected Invoice. Collection freezes the paid Invoice snapshot.
14. **Budget collection changes state, not total spend.** Unpaid 1584-funded activity occupies the invoicing/unpaid segment of each budget line. When its Invoice is collected, that amount moves to the client-paid segment; the combined budget progress does not increase.
15. **Collection attaches the Invoice contents to the new Transaction.** The collected Items and Expense lines leave the active invoicing area and become members of the Client → 1584 Transaction. The paid Invoice and its line snapshots remain as historical evidence of what was grouped and collected.
16. **Target Transaction types are globally limited to Purchase, Return, and Transfer.** Purchase means the scope owner paid; Return means the scope owner received money back. In project scope that owner is the Client; in Business Inventory it is 1584. Transfer is project-only and is the sole non-cash Transaction.
17. **Projects gain authoritative Client identity.** `project.clientId`, not free-text `clientName`, determines whether two projects belong to the same Client.
18. **Same-Client project Transfers bypass Business Inventory.** One bulk action atomically changes the Item directly from the source project to the destination and writes linked source/destination Transfer records. It does not temporarily place the Item in inventory or manufacture a new purchase, sale, charge, credit, Invoice line, payment, or refund solely because of the Transfer.
19. **Transfer budget reallocation is confirmed.** The same recognized amount moves out of the source project's attribution and into the destination's, so a $100 Item remains $100 across the Client's projects rather than becoming $0 or $200.

## The corrected model in plain language

### Transaction and scope ownership

A Transaction records real money movement from the perspective of the entity that owns its scope:

- the client owns a project, so a project Transaction records money the client paid or received;
- 1584 owns business inventory, so a business-inventory Transaction records money 1584 paid or received for inventory.

Project `transfer` is the explicit exception: it is a paired, non-cash
reallocation between two projects owned by the same Client. It exists in both
projects for audit and budget attribution but does not claim that money moved.

An inventory sale/placement that merely establishes an amount the project owes is not yet a Transaction in either scope. The Item appears in the project’s invoicing area at its charge amount. The later client payment is the project Transaction.

There are at least two materially different project Transaction kinds:

| Client payment | Example | Contains Items/vendor details? | Affects budget? | Invoiceable? |
|---|---|---:|---:|---:|
| Direct vendor purchase | Client buys a sofa from West Elm | Yes, when applicable | Yes | No; client already paid |
| Invoice settlement Purchase | Client pays 1584 one lump sum | Yes; collected Items and Expense lines attach from the Invoice | No new spend | No; it settles existing demand |

This distinction must be persisted or otherwise structurally reliable. It cannot be inferred only from a label. A field such as `paymentKind` or an equivalent invariant may be appropriate, but the canonical schema is not yet approved.

A Transaction has an `amount`, not a price. Item purchase prices and project prices remain Item-level values where applicable.

### Expense

An Expense is a non-itemized project cost paid by 1584 for the project—for example installation labor, fuel, delivery, or another reimbursable project cost.

It lives in the invoicing workspace, has a project budget category, contributes to spend immediately, and is eligible to be placed on an Invoice.

A client-paid non-itemized vendor purchase is not a second Expense plus a Transaction. The direct client-paid Transaction is already the project record and budget contribution.

### Inventory Items in invoicing

From the user’s perspective:

- business inventory → project: the Item appears in Invoicing as a positive Furnishings charge;
- project → business inventory before payment: the Item’s unpaid charge disappears from Invoicing;
- project → business inventory after payment: the Item appears in Invoicing as a Furnishings credit;
- same-Client project → project: a direct paired Transfer reallocates the Item
  and its project accounting without Business Inventory, a new charge, or a
  credit;
- cross-Client project → project through inventory: the source project loses or
  receives credit for the Item, while the destination project receives a new
  Item charge.

Under the hood, Ledger must retain a separate history entry each time the Item crosses scopes so repeated sale/return cycles remain auditable. That implementation history is what earlier drafts called an “Item Movement.” It should not be presented to users as another financial object they must understand.

### Invoice

An Invoice is a demand sent to the client. Its lines identify the exact Items, Expense lines, Fee Installments, or approved adjustments being billed or credited.

When the client pays, Ledger records a Client → 1584 Transaction linked to the Invoice. The Transaction proves that money moved; the Invoice preserves what that payment covered.

### “Invoice source”

In this document, a source is simply an existing record selected onto an Invoice:

- an Expense;
- an Item charge or credit, identified to the exact sale/return occurrence under the hood;
- a Fee Installment;
- or another explicitly approved billable record.

It is not a proposed universal base class and does not require a new user-visible “source” object.

### Receipt details

“Receipt details” means the information Ledger already needs to describe and verify a purchase:

- vendor;
- date;
- final amount;
- receipt image or document;
- physical Items;
- tax, shipping, warranty, discount, credit, or other non-item receipt lines.

This design does **not** currently require a new `PurchaseReceipt` or `VendorReceipt` model. Those names were an unapproved abstraction and have been removed from the plan.

For the least disruptive design, the record representing the actual vendor purchase continues to own these details:

- a direct client-paid purchase Transaction;
- a business-inventory acquisition Transaction;
- or a 1584-paid project Expense when the purchase is non-itemized.

## Explicit retractions from earlier drafts

The following are not part of the current plan:

- one project-scoped Transaction accumulating all inventory activity;
- a separate `DirectItemAcquisition` or generic `ItemActivity` record for client-paid Goods;
- a universal new `PurchaseReceipt`/`VendorReceipt` document;
- a universal rule that every Payment contributes zero to budget;
- a new user-facing “source claim” concept;
- moving direct client-paid Items out of their Transaction.

## End-to-end behavior

### Quick Added Item before payer/accounting is known

1. Capture photos and lightweight Item details through Quick Add.
2. Show the object under Unlinked Items; users do not manage a draft/proto
   conversion.
3. Permit optional Space placement without budget or accounting effects.
4. Link through Client paid or Business paid only.
5. Client paid requires the current project's actual Purchase.
6. Business paid optionally associates a Business Inventory Purchase and creates
   one open Item charge in Invoicing, never a project movement Transaction.
7. Preserve one physical Item identity; Invoicing references it through a
   separate occurrence.
8. When no inventory Purchase is selected, keep missing acquisition evidence
   explicit and reconcilable rather than fabricating a vendor Purchase.

### Client pays a vendor directly for physical Goods

1. Create a project Transaction for the actual Client → Vendor payment.
2. Set its category to Furnishings.
3. Attach the physical Items to that Transaction and project.
4. Store vendor, date, amount, and receipt details on the Transaction.
5. Include the Transaction once in Furnishings budget spend.
6. Mark it already client-paid/noninvoiceable.
7. Do not create an Expense, inventory-invoicing charge, or second Payment record for the same purchase.

If an Item is tagged Additional Requests, its contribution remains in Furnishings and also appears in the non-additive Additional Requests subtotal.

### Client pays a vendor directly for a non-itemized cost

1. Create a project Transaction for the actual Client → Vendor payment.
2. Use the selected project budget category.
3. Store the vendor, amount, date, and receipt details.
4. Include it once in that category’s budget spend.
5. Do not place it in To Invoice.

### 1584 buys physical Goods for a project

1. Create an inventory-scoped Transaction for the 1584 → Vendor purchase and attach the acquired Items in business inventory.
2. Store the acquisition’s purchase amount and receipt details there.
3. When Items are sold/placed into the project, show each Item in the project’s invoicing area at its charge amount and record the sale in hidden movement history.
4. Use the Item project-price basis for the project charge.
5. Categorize the project movement as Furnishings.
6. Include it immediately in project budget spend.
7. Make the Item available in the Invoicing Items section.
8. When selected, an Invoice line references the Item and the exact underlying sale occurrence so a later return/re-sale cannot confuse the accounting.
9. When the client pays the Invoice, create one Client → 1584 settlement Transaction for the real payment event, attach the collected Items and exact movement/line references to it, and remove those sources from the active invoicing area.

The inventory Transaction records what 1584 paid the vendor. The Item’s invoicing charge records what the project/client is charged. They are different amounts for different purposes.

### 1584 pays a non-itemized project cost

1. Create an Expense in the project’s invoicing workspace.
2. Store its category, amount, vendor, date, and receipt details.
3. Include it immediately in project budget spend.
4. Make it available in To Invoice.
5. An Invoice line references the Expense.
6. Collection creates or links the Client → 1584 settlement Transaction, attaches the collected Expense line to it, and removes the Expense from the active invoicing area.

### Project returns an Item to business inventory

1. Record the Item’s return at the approved origin-aware price basis and create the corresponding project credit/history entry.
2. Reduce Furnishings spend immediately.
3. If the original positive movement is not yet invoiced, update the available demand consistently.
4. If it is on a created or sent Invoice, follow the approved pre-collection edit rule.
5. If it was already paid, create new credit demand; do not rewrite the paid Invoice.
6. If 1584 later sends actual money to the client, record that separate cash movement under the future refund rule.

### Project-to-project sale through inventory

One trusted operation creates:

- the source project’s Item credit/removal;
- the destination project’s new Item charge;
- correlated lineage;
- the Item location change;
- both projects’ budget effects.

Each project sees and invoices only its own movement.

## Item stories by billing state

Every real sale/return is retained in hidden movement history even when a later opposite action makes the net financial effect zero. What the user sees depends on whether the Item’s project charge is still available to invoice, on a live Invoice, or already collected.

### Inventory Item sold to a project

- Move the Item into the project.
- Show the Item in the invoicing area as a positive Furnishings charge at normalized project price.
- Increase project budget progress immediately in the invoicing/unpaid segment.
- Make the movement available to add to an Invoice.
- Do not create a project Transaction until the client actually pays.

### Project decides not to use it before it is on an Invoice

- Move the Item back to business inventory.
- Record the return against the original project charge using its stored price basis.
- Remove/resolve the positive movement from the active To Invoice pool; do not ask the user to bill a charge and matching credit.
- Reduce project Furnishings progress immediately, normally back to its prior net amount.
- Create no Invoice and no project Transaction.
- Preserve the original sale, return, and lineage in hidden history for audit.

### Project removes it from a created or sent, uncollected Invoice

- Move the Item back to business inventory and record the reversal in hidden history.
- Because created and sent Invoices remain live, automatically remove the Item’s positive line—do not add a credit line for an uncollected charge—and recalculate the Invoice total.
- Remove the Item from active invoiceable project contents.
- Reduce Furnishings progress immediately.
- Create no project Transaction because the client has not paid.
- Preserve the Invoice edit/audit history. If removing the Item leaves a zero or negative Invoice, apply the still-unresolved zero/credit-Invoice rule rather than allowing ordinary collection.

### Project removes it after the Invoice was collected

- Keep the original paid Invoice, settlement Transaction, frozen line, and historical Transaction membership unchanged.
- Move the Item’s current location back to business inventory.
- Create a new Item credit in Invoicing using the original paid line amount and category snapshot—not today’s mutable Item price—and record the return in hidden history.
- Reduce Furnishings budget progress immediately.
- Link the new client-credit demand deterministically to the original paid Invoice line and the return history entry.
- Do not create a credit Transaction merely because the Item moved; no new cash has moved yet.
- When the credit is later applied to a positive Invoice or paid back in cash, record that settlement without rewriting the original paid Transaction.

The Item therefore leaves the project’s current contents but remains listed historically on the paid Transaction that originally bought it. Current Item placement and historical paid-Transaction membership must be separate relationships.

### Same Item later sold from inventory again

- Show it as a new positive Item charge in the destination project’s invoicing area and record a new sale occurrence in hidden history.
- Use the then-approved destination project and price rules.
- Add new invoicing/unpaid Furnishings activity.
- Never reopen or reuse the earlier positive, negative, Invoice, or paid Transaction records.

### Project-originated Item sold to business inventory

- Create a source-project Item credit at purchase-cost basis because 1584 is acquiring an Item the project/client owned; a higher project price must not inflate the acquisition credit.
- Move the Item into business inventory and record immutable source project/category/amount provenance.
- Reduce the source project’s budget immediately.
- If the Item’s prior project cost was already client-paid, create linked client-credit demand; if it was still uncollected, remove the live positive demand instead of creating a credit.

### Project-originated Item returned from inventory to its source project

- Show a new positive Item charge using the immutable inventory-entry snapshot and record the return-to-project occurrence in hidden history.
- Restore the recorded source project, category, and amount; do not ask the user to choose or recalculate them from mutable Item fields.
- Make the restored charge invoiceable/unpaid again unless a different explicit correction workflow applies.

### Project A sells an Item to Project B through inventory

- In one atomic operation, create Project A’s origin-aware Item removal/credit, Project B’s new Item charge, correlated hidden movement history, and the location change.
- Project A follows the same billing-state rules above: remove uncollected positive demand or create a new credit if the source charge was paid.
- Project B receives new invoicing/unpaid Furnishings activity at destination project-price basis.
- The two projects never share one Transaction or one Invoice line.

### Correction versus real movement

A mistaken association is a correction, not a sale or return. If the Item never truly changed economic scope, void/reverse the erroneous movement with an audit record and repair any live Invoice. After collection, use an explicit accounting correction/credit; never silently rewrite the paid Invoice or Transaction.

### Vendor return

A return to an outside vendor follows the scope-owner Transaction rule because real money is refunded:

- client-paid project purchase returned to vendor: project-scoped Return/refund Transaction and negative project spend;
- 1584-paid inventory purchase returned to vendor: inventory-scoped Return/refund Transaction;
- an Item already charged from inventory to a project may additionally require the project Item removal/credit behavior above.

## Budget rules

Budget behavior is determined by what the record represents—not merely by whether it is called a Transaction.

| Record | Budget contribution |
|---|---:|
| Direct Client → Vendor purchase Transaction | Signed amount in its project category |
| Direct client-paid itemized Transaction | Furnishings contribution |
| 1584-paid Expense | Signed amount in its category |
| Inventory Item sold into project | Positive Furnishings contribution |
| Project Item returned/sold into inventory | Negative Furnishings contribution |
| Client → 1584 invoice-settlement Transaction | Zero |
| Invoice or InvoiceLine | Zero; it groups demand |
| 1584-paid business-inventory Transaction | Zero to a project until an Item is sold into it |
| Canceled/reversed record | Zero, with preserved audit history |

The v2 calculation is conceptually:

    project category spend
      = direct client-paid purchase Transactions for that category
      + 1584-paid Expenses for that category
      + signed inventory Item charges/credits for that category
      + any other explicitly approved budget-bearing record

    invoice-settlement Transactions
      = excluded from project spend

### Budget-line visual composition

Each budget-category progress line is one stacked line with two accounting-state segments:

1. **Client-paid segment** — direct client-paid purchase Transactions in that category, plus the category amounts of source lines on collected Invoices.
2. **Invoicing/unpaid segment** — 1584-paid Expense lines and inventory Item charges/credits that contribute to that category but have not yet been collected, whether still available to invoice or already on a created/sent Invoice.

The color names are not settled because the recording referred to the paid segment first as green and later as red. The semantic states—not the palette—are the design decision.

For each category:

    total budget progress = client-paid segment + invoicing/unpaid segment

Collection changes only the composition:

    before collection: amount is in invoicing/unpaid segment
    after collection:  same amount is in client-paid segment
    total progress:     unchanged

The paid category allocation is derived from the preserved Invoice lines and the collected contents attached to the new Transaction. The one lump-sum settlement Transaction does not need to be split into category-specific Transactions and does not add spend again. Canceling an uncollected Invoice returns its underlying Expenses/Movements to the available invoicing pool but leaves them in the invoicing/unpaid budget segment.

### Existing budget defect and migration baseline

Current app and Cloud Function logic broadly counts categorized, non-canceled Transactions. Generated `paymentToBusiness` settlement Transactions can therefore increase project spend after the underlying purchase was already counted.

Before migration:

1. define and implement one shared “does this record affect project budget?” rule;
2. exclude settlement-linked Transactions;
3. rebuild cached summaries;
4. use the corrected calculation—not the current stored `budgetSummary`—as the migration baseline.

During migration, only one accounting version may be authoritative for each project. Legacy movement Transactions and new hidden movement-history entries must never both contribute.

## How Ledger prevents billing the same Expense or Movement twice

When a user adds an Expense line or inventory Item to an Invoice, the Invoice line stores the exact Expense ID or Item-plus-sale-occurrence identity it includes.

Ledger must then prevent that same amount from being added to a second active Invoice. This can be enforced atomically by the server and indexed for fast lookup. It does not require a user-visible “claim” object.

The rules are:

- uninvoiced Expense/Movement: selectable;
- included on a created or sent Invoice: not selectable elsewhere;
- Invoice canceled: selectable again;
- Invoice paid: the Items and Expense lines leave the active invoicing area, attach to the new settlement Transaction, and remain preserved on the paid Invoice snapshot;
- correction after payment: new credit, adjustment, or reversal—not mutation of the paid line.

Before collection, an Invoice references the Expense or Movement without owning it. That allows the project cost to exist and affect budget before invoicing and to survive Invoice cancellation. At collection, the resulting Transaction becomes the active paid container, while the Invoice remains immutable historical evidence.

## Implementation-only movement history and lineage

Although the user works with Items, every financial sale/return needs stable occurrence identity underneath. An Item ID alone is insufficient because one Item can enter, leave, and re-enter the same project.

At minimum, each movement occurrence needs:

- movement ID and idempotent operation ID;
- Item ID;
- project ID;
- direction and sign;
- amount and project-price basis snapshot;
- Furnishings category identity;
- Additional Requests tag state for that project occurrence;
- source and destination context;
- effective date, actor, and audit timestamps;
- correlated counterpart for project-to-project operations;
- reversal/correction linkage;
- enough display snapshot data to preserve history if the Item later changes.

The existing lineage graph is a strong candidate for this history, but one financial authority must be selected:

- enrich designated financial lineage occurrences with the accounting fields; or
- create a separate hidden movement-accounting entry that references lineage.

Do not maintain two independently editable amount-bearing versions of the same movement.

An Item-backed Invoice line references the Item plus the exact underlying sale/return occurrence. The history entry itself does not need a mutable `invoiceId` field merely to establish membership.

## Non-item receipt lines and completeness

The NonItemReceiptLine work still solves a real problem: not everything printed on a purchase receipt is a physical Item.

Examples include:

- sales tax;
- shipping;
- warranty or protection;
- discounts;
- credits;
- other service or adjustment lines.

These lines remain embedded in the record representing the vendor purchase. They do not become physical Items.

Receipt reconstruction remains:

    physical Item purchase-price total
      + increasing non-item receipt lines
      - decreasing non-item receipt lines
      = final purchase amount

For a direct client-paid purchase, that parent is the Transaction. For a business-inventory acquisition, it remains the inventory purchase record. For a non-itemized 1584-paid project cost, the Expense can carry its finite receipt lines.

Moving an inventory Item into a project does not automatically copy the acquisition’s shipping, tax, warranty, or discount into the Item’s project charge. The project treatment must be explicit:

- absorbed by 1584;
- included in the Item’s project price;
- entered as a separate project Expense;
- entered as a separate approved charge/credit.

Receipt completeness and movement accounting remain separate checks. Receipt completeness proves the vendor purchase amount. Movement reconciliation proves the project’s Furnishings charges and credits.

Open receipt details include legitimate rounding treatment and how legacy transaction-wide tax-rate behavior migrates without changing established Item project-price calculations accidentally.

## Invoice collection

The target behavior is one Transaction per actual client payment event—not one artificial Transaction per budget category.

For a full payment:

1. keep the Invoice and its lines;
2. create one Client → 1584 Transaction for the amount actually received;
3. attach every collected Item and Expense line to that Transaction;
4. retain exact Invoice-line, Item sale/return occurrence, amount, sign, and category references/snapshots so the Transaction can explain its total;
5. update the Items/Expenses/Movements so they no longer appear in the active invoicing area and point to the settlement Transaction;
6. link the Transaction back to the Invoice;
7. mark the Invoice paid and freeze its snapshot;
8. exclude the settlement Transaction amount from creating new budget spend; collection only moves the attached line amounts to the client-paid visual segment.

This must be one atomic, idempotent operation. A failure cannot leave a paid Invoice without its Transaction, or attach only some of the Invoice contents.

“Attach” does not mean delete the source history. The new Transaction needs user-facing membership references such as Item IDs and Expense IDs, plus exact collected-line references. The paid Invoice retains its frozen lines. Later Item returns or corrections create new movement/credit activity and must not remove the Item from, or recalculate, the historical paid Transaction.

Current code supports collecting selected Invoice lines and creates category-grouped settlement Transactions. The approved redesign removes that behavior for now: collection is whole-Invoice only and creates one Transaction for the actual payment. Created and sent Invoices stay live until collection; source changes update them, and collection freezes the paid snapshot.

## Application impact

### Models

- Replace target project Transaction writes with exactly `purchase`, `return`,
  and `transfer`; collection writes `purchase`, not `paymentToBusiness`.
- Add an account-scoped Client entity and authoritative `project.clientId`, with
  `clientName` retained temporarily as a compatibility/display snapshot.
- Add paired source/destination Transfer shape, stable correlation ID,
  counterpart links, roles, Client/project IDs, and immutable Item-line amount
  snapshots.
- Keep Transaction capable of representing direct client-paid purchases, including Items, category, vendor, receipt fields, and budget impact.
- Add a durable distinction between direct vendor purchase Transactions and invoice-settlement Transactions.
- Invoice-settlement Transactions must not require a project budget category for spend attribution; their per-category coverage is derived from the linked Invoice lines. A compatibility category, if temporarily required by storage, is explicitly non-budget-bearing.
- Invoice-settlement Transactions need collected membership: Item IDs, Expense IDs, exact source/movement references, and frozen line amount/sign/category snapshots or an equally durable link to the frozen Invoice lines.
- Add a first-class project Expense record for 1584-paid non-itemized costs.
- Add or enrich implementation-only sale/return occurrence records.
- Keep Item-backed Invoice lines user-facing while adding exact occurrence identity; add Expense-line source identity.
- Add collected/settlement linkage on Expenses and Item sale/return occurrences so active invoicing queries exclude them without deleting history.
- Separate an Item's current paid-Transaction attachment from acquisition and movement provenance; the existing single `item.transactionId` meaning cannot safely represent all three relationships after migration.
- Preserve legacy Transaction decoding throughout migration.
- Add an accounting-authority/version marker so one budget model is active per project.
- Preserve or replace the internal `ProtoItem` capture boundary without exposing
  it as a second product entity; define a durable Link-state projection and
  idempotent resolution to one Item identity.

### iOS services and state

- Project creation/editing must select or create a Client instead of accepting
  authoritative free-text client identity.
- Add a trusted bulk same-Client Transfer operation and direct Item-history path;
  it must not call the inventory sale pipeline.
- Transaction creation must support direct client-paid itemized and non-itemized vendor purchases.
- Project Transaction lists must show client-funded purchases and invoice payments, not 1584-paid Expenses or inventory movement pseudo-transactions.
- InventoryOperationsService must stop creating project Purchase/Sale/Return Transactions for new v2 writes; it updates Item location, hidden movement history, project budget effects, and the Item’s invoicing charge/credit instead.
- InvoiceService must select Expenses/Movements, remove selected-line collection, and atomically create one settlement Transaction with all Invoice Items and Expense lines for whole-Invoice collection.
- BudgetTabCalculations and BudgetProgressService must use the corrected record table above.
- ProjectContext must subscribe to client-paid Transactions, Expenses, invoicing Item charges/credits backed by movement history, Invoices, and Fees.
- Account/inventory state must retain inventory-scoped Transactions representing 1584 purchases.
- Quick Add/Link must use one trusted operation for Client-paid association or
  Business-paid charge creation, preserve media/Space, and never call the legacy
  project movement-Transaction writer.

### UI

- Add Client selection/creation to project setup and a Client-management surface
  sufficient to rename/archive Clients without independently drifting projects.
- Add a bulk Transfer-to-Another-Project action whose destination picker includes
  only active projects with the exact same `clientId`.
- Project entry begins with who paid: Client or 1584.
- Client-paid entry remains Transaction entry, then branches Goods versus non-itemized purchase.
- 1584-paid entry routes into the invoicing workspace:
  - Goods use an inventory Transaction, then appear as Items in project Invoicing when sold;
  - non-itemized costs create Expenses.
- Remove the current business-paid itemized “Cover a project purchase” / `projectReimbursement` branch; 1584-paid physical Goods use the inventory path.
- Invoicing shows distinct sections for Items, Expenses, Fees, and Invoices. Users do not manage a separate “Item Movement” object.
- The project Transactions surface should be explained as Client Payments while still distinguishing direct vendor purchases from payments to 1584. The Business Inventory Transactions surface represents 1584's inventory purchases.
- Budget UI must not make an Invoice payment look like additional project spend.
- Each budget line shows client-paid and invoicing/unpaid segments whose sum is total progress; collection transfers the amount between segments without extending the line.
- Paid Invoice detail shows the lump-sum Transaction and the lines it covered.
- Collected Items and Expenses disappear from active To Invoice/Invoice-building sections and appear on the new Transaction detail; the paid Invoice remains accessible as history.
- Project Items shows Unlinked Items above Linked Items. Link asks Client paid or
  Business paid; Space remains optional and independent. Do not expose Needs
  Assignment, Assign Item, proto/draft conversion, or Sell from Business
  Inventory as target labels.

### MCP

- Add Client create/list/get/update/archive tools and replace authoritative
  project `clientName` mutation with Client selection/identity.
- Add one idempotent trusted same-Client bulk Transfer tool; never expose two
  independent create-Transfer calls.
- Transaction creation must retain direct client-paid vendor purchases with category, Items, and purchase details.
- Settlement creation must atomically link the Invoice, attach every collected Item and Expense line, mark those records collected, and be excluded from new budget calculations.
- Add Expense create/update/list/get operations.
- Inventory tools must write Item/location/history changes rather than project movement Transactions.
- Invoice tools must accept exact Expense lines and Item-plus-occurrence sources.
- Budget, project, analytics, resource, search, and export tools must share the same budget-authority resolver.
- Quick Add and MCP composite operations must use the same two-route Link command
  and target occurrence writer. Existing quick-draft names/fields remain
  tolerant-read compatibility only.

### Cloud Functions

- Replace broad Transaction-based project spend aggregation with kind-aware aggregation.
- Exclude invoice-settlement Transactions from spend.
- Trigger summaries from direct client-paid purchase Transactions, Expenses, and signed Item sale/return history.
- Move project repricing/deletion reconciliation from movement-Transaction totals to exact Item sale/return occurrences.
- Preserve receipt completeness on the purchase-owning Transaction or Expense.
- Add reconciliation for budget totals, movement integrity, duplicate Invoice-line inclusion, settlement totals, and exact agreement between a paid Invoice and its Transaction attachments.

### Firestore rules and indexes

- Add Client collection access and indexes; validate that project `clientId`
  resolves inside the account.
- Make paired Transfers trusted-only and require same-account, same-Client,
  two-sided, immutable correlation.
- Enforce valid direct-purchase versus settlement Transaction shapes.
- Prevent settlement Transactions from masquerading as budget-bearing purchases.
- Validate Expense project/category/payer and paid-Invoice locks.
- Make movement writes trusted/idempotent.
- Prevent the same Expense or Movement from joining two active Invoices.
- Require whole-Invoice collection to attach the complete frozen Invoice membership to exactly one active settlement Transaction.
- Reject stale clients that create legacy project movement Transactions after authority cutover.
- Add indexes for Expenses, Item sale/return occurrences, active Invoice-line lookup by source identity, and Invoice settlement linkage.

### Search, reporting, exports, and review

- Search must include Expenses and relevant Item sale/return history while retaining client-paid Transactions.
- Reports must distinguish total project spend, client-paid spend, invoicing/unpaid spend, amount assembled onto Invoices, outstanding Invoice demand, and client payments.
- Exports must preserve direct client purchases, Expenses, Movements, Invoices, and settlement Transactions without double counting.
- Receipt-completeness review remains on the purchase-owning Transaction/Expense.
- Movement-integrity failures become a separate review category.

## Current specifications that conflict with this direction

The active specs cannot be treated as an implementation plan without revision:

- [item-entry-flow.md](../../specs/item-entry-flow.md) still says each category has one accumulating project Transaction.
- [transaction-creation.md](../../specs/transaction-creation.md) defines Client Payment as fee/revenue-only and prohibits Items, vendor, source, and receipt fields. That conflicts with direct Client → Vendor Transactions.
- [transaction-type.md](../../specs/transaction-type.md) similarly treats `paymentToBusiness` as the only client-payment path and assumes settlement category splitting.
- [billing-invoicing.md](../../specs/billing-invoicing.md) still treats business purchases and installer payments as Transactions and creates one settlement Transaction per category.
- [budget-management.md](../../specs/budget-management.md) derives project spend from legacy Transactions and legacy movement signs.
- [data-model.md](../../specs/data-model.md) makes `item.transactionId`, Invoice item/transaction sources, and movement Transactions central.
- [returned-paid-item-credit-plan.md](../returned-paid-item-credit-plan.md) correctly preserves the paid Invoice and creates new credit demand, but its movement-Transaction and manual-credit-line containers must be adapted to Item-backed credits, collected Transaction attachments, and explicit sale/return provenance in this redesign.
- sale, return, reassignment, lineage, audit, completeness, reports, search, access-control, and MCP guidance specs all depend on those assumptions.

The superseded [net-ledger report](../inventory-project-net-ledger/report-source.md) is historical research only. Its one-Transaction proposal must not be copied into canonical specs.

## Migration hazards

1. **Do not split existing direct client-paid project purchases into multiple new records.** They remain budget-bearing Transactions with their Items.
2. **Do not count invoice-settlement Transactions as spend.** Correct and rebuild the legacy baseline first.
3. **Do not count legacy project movement Transactions and new Item sale/return history simultaneously.**
4. **Do not lose acquisition history when replacing `item.transactionId`.** Separate current placement from acquisition and movement occurrence identity.
5. **Do not rewrite paid Invoice snapshots.**
6. **Do not merge legacy category-split settlement Transactions into one historical payment without evidence.** Correlate or preserve them.
7. **Do not infer tax as `amount - subtotal` during receipt migration.**
8. **Do not allow old/offline clients to recreate legacy movement Transactions after cutover.**
9. **Do not hard-delete movement history.** Use explicit reversals/corrections.
10. **Do not assume existing cached budget summaries are correct enough to validate migration.**
11. **Do not overload or overwrite the only Item-to-Transaction relationship without preserving acquisition and movement provenance.** Paid-Transaction membership, acquisition history, and current movement state are distinct.
12. **Do not mark an Invoice paid before all Items and Expense lines are attached to its Transaction.** Collection must be atomic and reconcilable.
13. **Do not infer Client identity from `clientName`.** Text normalization may
    produce migration suggestions, never Transfer authorization.
14. **Do not create the two Transfer sides independently.** Both records, Item
    placement, live-Invoice changes, provenance, and budget effects commit or
    fail together.

## Safe transition plan

### Phase 0 — Canonical decisions and production audit

- Resolve the open decisions below.
- Define the exact Transaction discriminator and budget-contribution rule.
- Audit direct client-paid purchases, 1584-paid project Transactions, movement Transactions, which Invoice lines include which records, settlements, Items, lineage, and receipt completeness.
- Produce a corrected payment-excluding legacy budget baseline.

### Phase 1 — Fix current double counting

- Exclude settlement-linked Transactions in every iOS, MCP, Function, report, and cached-summary path.
- Recalculate affected project summaries.
- Add regression tests before the larger redesign.

### Phase 2 — Add new records and tolerant readers

- Add Expense and hidden Item sale/return accounting schemas.
- Add new InvoiceLine source identities.
- Add settlement Transaction membership and reverse-link fields for collected Items, Expenses, and Movements.
- Add accounting authority/version fields.
- Keep all legacy records readable.
- Add tolerant reads for open `protoItems`, provisional `assignmentHint` and
  `spaceId`, and old Quick Draft MCP shapes.

### Phase 3 — Centralize writers and shadow calculations

- Route inventory operations through one idempotent writer.
- Shadow-write Item sale/return history while retaining rollback compatibility.
- Write Expenses through one canonical service.
- Shadow the target Item Link result without changing authoritative legacy
  accounting; compare physical Item identity, charge, category, and media/Space
  preservation.
- Shadow-compute v2 budgets and compare them with the corrected legacy baseline.

### Phase 4 — Backfill and reconcile

- Preserve direct client-paid Transactions as Transactions.
- Convert provable 1584-paid non-itemized project costs to Expenses.
- Convert provable legacy project movement batches to occurrence-level Item sale/return history.
- Map active Invoice sources only when provenance is exact, and backfill paid Transaction attachments only when the historical Invoice/settlement relationship proves them.
- Preserve ambiguous and paid history rather than guessing.
- Reconcile every open internal capture to Unlinked, Linked, duplicate, removed,
  or ambiguous status; never infer a missing inventory Purchase.

### Phase 5 — Authority switch and UI cutover

- Verify category totals, Furnishings, Additional Requests, unique Invoice-line inclusion, and settlement totals per project.
- Flip one project/account authority flag.
- Launch the corrected Transactions and Invoicing surfaces.
- Launch Quick Add with Unlinked Items / Linked Items / Link terminology and
  switch Business-paid Link to the open-charge writer.
- Reject legacy writes from stale clients.

### Phase 6 — Retire compatibility writes

- Stop legacy movement shadow writes after a rollback window.
- Retain historical Transactions and exports.
- Keep reconciliation permanently.

## Product decisions still required

1. **Paid-item credits and refunds:** may a returned-item credit be applied only to a future positive Invoice, can a credit-only Invoice be closed by a 1584 → Client refund Transaction, and how should a pending negative credit render in the two-segment budget line?
2. **Expense edits:** which edits remain legal while available to invoice, on created/sent Invoices, and after payment?
3. **Movement-history authority:** enrich financial lineage or create a separate hidden accounting record?
4. **Mixed receipt charges:** how are shipping, tax, warranty, discounts, and credits absorbed, included in project price, or passed through?
5. **Manual Invoice lines:** remain budget-neutral Invoice-only adjustments, or require typed Fee/Adjustment records?
6. **Item history presentation:** how much sale/return history should appear on Item detail versus only in accounting audit views?
7. **Missing acquisition evidence:** what target record remains when Business
   paid is Linked without choosing an inventory Purchase?
8. **Quick Add hint:** retain a reversible payer hint at capture time or defer the
   choice entirely to Link?
9. **Capture persistence and duplicates:** when can `protoItems` be retired, and
   what audited operation reconciles duplicate physical Item evidence?

## Resolved decisions

Business inventory is owned by 1584. A vendor purchase into business inventory is therefore an inventory-scoped Transaction representing 1584's real payment. Projects are owned by clients, so project-scoped Transactions represent the client's real payments. This is a scope rule, not a global rule that every Transaction in the account has the same payer.

Invoices are collected as a whole for now. Building the Invoice curates the activity charged together; collection creates one project Transaction for the full Client → 1584 payment and attaches all collected Items and Expense lines to it. Those records leave the active invoicing area. Created and sent Invoices remain live until collection, and collection freezes the Invoice snapshot rather than deleting it.

Budget progress is one total split into client-paid and invoicing/unpaid visual segments. Collection moves the Invoice-line amounts between those segments without changing total progress. Category allocation comes from Invoice lines, so the lump-sum settlement Transaction is not split by category and does not create another budget contribution.

Additional Requests is a non-exclusive tag/reporting overlay on Furnishings. Its tagged-Item subtotal may be displayed separately, but it does not remove those Items from Furnishings or add their spend to overall progress a second time.

## Next step

The canonical target-state specs now exist at
[`invoice-centered-project-accounting.md`](../../specs/invoice-centered-project-accounting.md)
and
[`inventory-item-invoicing-lifecycle.md`](../../specs/inventory-item-invoicing-lifecycle.md).
Resolve decisions 1–5 because they determine schemas and write authority, then
produce the symbol-level implementation/test tracker. Do not start the broad
migration from this impact analysis or the superseded net-ledger report alone.
