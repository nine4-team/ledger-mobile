# Inventory Item Invoicing and Return Lifecycle
Status: target-state redesign — approved direction, not implemented
Last updated: 2026-08-31
Program tracker: [../plans/ledger-accounting-redesign/README.md](../plans/ledger-accounting-redesign/README.md)
Parent model: [invoice-centered-project-accounting.md](invoice-centered-project-accounting.md)
Item intake and Link: [proto-item-capture.md](proto-item-capture.md)

## Purpose

This spec describes what the user sees and what Ledger must preserve when an
Item is sold between Business Inventory and a project, invoiced, paid, returned,
corrected, or sold again.

The user works with **Items**, **charges**, and **credits**. The system retains a
hidden occurrence and lineage history so it can distinguish the same Item being
sold, returned, and sold again without rewriting prior accounting.

This document replaces the project-side Transaction behavior in
[sale-transactions.md](sale-transactions.md) as a target direction. The existing
per-batch Transaction model remains shipped behavior until the migration is
implemented.

## Core Rules

1. Selling an inventory Item into a project creates a positive Item charge in
   project Invoicing, not a project Transaction.
2. Removing an uncollected Item removes its current positive demand. It does not
   create a fake refund Transaction.
3. Removing a paid Item preserves the paid Invoice and Transaction and creates a
   new client credit in Invoicing.
4. The same Item may have multiple sale/return cycles. Every cycle has a stable,
   unique occurrence identity.
5. Created and sent Invoices remain live. Eligible Item price or membership
   changes update their lines and totals until collection.
6. Collection freezes the Item amount, category, occurrence, Invoice line, and
   paid Transaction membership.
7. Current Item location and historical paid membership are separate facts.
8. Corrections never masquerade as real sales, returns, payments, or refunds.
9. Linking a Quick Added Business-paid Item enters this lifecycle by creating
   the same open charge and occurrence; it does not create a second Item or a
   project movement Transaction.

## User-Facing Model

In a project's Invoicing area:

- a positive Item row means the project will charge the client for that Item;
- a negative Item row means the project owes the client a credit for that Item;
- a row may be available to invoice, on a created/sent Invoice, or paid; and
- Item detail may show useful history, but users do not manage an entity called
  an “Item Movement.”

Under the hood, every financial sale or return records enough provenance to
answer:

- which exact sale/return cycle this is;
- source and destination scope;
- source and destination category snapshots;
- amount and price basis;
- prior occurrence being reversed, when applicable;
- Invoice and Invoice-line membership; and
- whether the occurrence is open, paid, reversed, or corrected.

An Invoice Item line references both the Item and the exact occurrence. An Item
ID alone is insufficient because the Item may be sold more than once.

## Price and Category Basis

| Story | Amount basis | Category basis |
|---|---|---|
| Business Inventory → project | Item project price for that sale cycle | Furnishings |
| Unpaid Item price edit | Latest approved project price | Furnishings; live charge and Invoice update |
| Paid Item later returned | Original paid Invoice-line amount | Original paid category snapshot |
| Inventory-originated Item returns to inventory before payment | Remove the open positive charge | Original open charge category |
| Inventory-originated Item returns after payment | Credit the original paid amount | Original paid category snapshot |
| Project-originated Item sold to inventory | Purchase cost, never an inflated project price | Source project category snapshot |
| Project-originated Item returns to its source project | Immutable amount recorded when it entered inventory | Immutable source category snapshot |
| Item later resold from inventory | New destination project price | Furnishings in the new destination project |

For the target design, all project Item charges and credits contribute through
Furnishings. Additional Requests is a tag/overlay and does not replace
Furnishings or duplicate overall spend.

## Story 1: Sell an Inventory Item to a Project

When 1584 sells an Item from Business Inventory into a project:

1. move the Item's current physical placement into the destination project;
2. create a new positive Item charge in that project's Invoicing area at the
   current project price;
3. attribute the charge to Furnishings;
4. record a new hidden sale occurrence with source, destination, amount, price
   basis, and lineage; and
5. increase the project's invoicing/unpaid Furnishings progress.

No project Transaction exists yet because the client has not paid.

If the project price changes while the charge remains uncollected, update the
open Item charge and any created/sent Invoice that contains it. Recalculate the
Invoice total atomically. Once collected, the frozen amount does not change.

## Story 2: Decide Not to Use It Before It Is on an Invoice

If the Item has an open charge but is not on an Invoice:

1. move the Item back to Business Inventory;
2. remove the positive Item charge from active Invoicing;
3. reduce invoicing/unpaid Furnishings progress by that charge;
4. mark the hidden sale occurrence reversed by the return occurrence; and
5. create no Invoice, credit row, or project Transaction.

The user sees that the Item is no longer waiting to be invoiced. Ledger retains
the hidden history so the action remains auditable.

## Story 3: Remove It from a Created or Sent Invoice

Created and sent Invoices are live until collection. If the Item is returned to
Business Inventory while its positive line is on one:

1. move the Item back to Business Inventory;
2. remove its exact occurrence line from the live Invoice;
3. recalculate and persist the Invoice subtotal, total, and affected category
   allocation;
4. remove the positive charge from active Invoicing;
5. reduce invoicing/unpaid Furnishings progress; and
6. retain Invoice edit history plus linked sale/return provenance.

Create no project Transaction because no client payment or refund occurred.

If the removal leaves the Invoice at zero dollars, the Invoice becomes
noncollectible until the open zero-Invoice policy is resolved. The
implementation must not collect it as an ordinary payment.

## Story 4: Remove It after the Invoice Was Paid

If the client already paid for the Item:

1. keep the original paid Invoice, frozen line, payment Transaction, and the
   Item's historical paid-Transaction membership unchanged;
2. move the Item's current physical placement to Business Inventory;
3. create a new negative Item credit in active Invoicing;
4. calculate the credit from the original paid line's amount and category
   snapshot, not from the Item's current mutable price;
5. link the credit deterministically to the original paid line and return
   occurrence so retries cannot duplicate it; and
6. reduce Furnishings budget progress immediately.

The Item no longer appears in the project's current contents, but remains in
the historical contents of the paid Transaction. No refund Transaction is
created until money actually leaves 1584 or an approved offset is settled.

How the credit is applied to a future positive Invoice or paid back in cash is
an open workflow decision.

## Story 5: Sell the Same Item Again

If the returned Item is later sold from Business Inventory:

1. create a brand-new positive Item charge and sale occurrence;
2. use the destination project's current approved project price;
3. place it in the destination project's Furnishings Invoicing activity; and
4. leave every earlier charge, credit, Invoice, and paid Transaction frozen.

Never reopen or reuse an earlier occurrence merely because the Item ID is the
same.

## Story 6: Sell a Project-Originated Item to Business Inventory

This is 1584 acquiring an Item that originated in and was owned by the project.

1. move the Item into Business Inventory;
2. record the acquisition at purchase-cost basis; a higher project price cannot
   increase the project credit;
3. preserve the source project, category, amount, and origin in an immutable
   inventory-entry snapshot; and
4. apply the source project's billing-state rule:
   - if its positive demand is uncollected, remove that open demand; or
   - if the client already paid, create a linked negative Item credit.

The project budget decreases immediately by the origin-aware basis. A client
refund Transaction does not exist until cash moves or a credit is settled.

## Story 7: Return a Project-Originated Item to Its Source Project

If an Item acquired into Business Inventory is returned to its proven source
project:

1. restore the source project, category, and amount from the immutable
   inventory-entry snapshot;
2. create a new positive Item charge and hidden return-to-project occurrence;
3. make the charge available in Invoicing; and
4. increase that project's invoicing/unpaid progress.

The user does not choose a different project, category, or recalculated amount
inside this Return action. If provenance cannot prove a single source, Ledger
must fall back to an ordinary Sell flow or block rather than guess.

## Story 8: Transfer between Projects Owned by the Same Client

When Project A and Project B have the same authoritative `clientId`, use the
direct Transfer flow in
[client-identity-and-project-transfers.md](client-identity-and-project-transfers.md):

1. keep the Item out of Business Inventory;
2. create one linked Transfer record in each project;
3. move the Item and its current project accounting attribution directly;
4. preserve any frozen paid history in Project A;
5. move an uncollected charge to Project B without creating a new purchase or
   source credit; and
6. keep the Client's aggregate spend unchanged.

This is the only project-to-project path that bypasses Business Inventory.
Matching `clientName` text is insufficient; both projects need the same
non-null Client ID.

## Story 9: Sell from Project A to a Different Client's Project through Inventory

This is one user action with two project-specific accounting effects:

1. apply Project A's origin-aware removal rule:
   - remove uncollected positive demand, or
   - create a paid Item credit using its frozen original basis;
2. move the Item through Business Inventory and retain correlated provenance;
3. create a new positive Item charge for Project B at Project B's destination
   project-price basis; and
4. update both projects' Furnishings progress atomically.

Project A and Project B never share an Invoice, Invoice line, project
Transaction, or budget allocation. Correlated hidden provenance is the bridge.
This ownership-changing path is not a Transfer and must not be offered by the
same-Client Transfer picker.

## Story 10: Correct a Mistake

If the Item did not truly change economic scope, use an explicit correction:

- repair current placement and the open charge/Invoice atomically;
- void or reverse the erroneous occurrence with audit metadata;
- produce no sale, return, payment, refund, or budget effect that did not happen;
- after collection, preserve paid records and require an explicit accounting
  correction or credit instead of silently editing history.

## Story 11: Return an Item to an Outside Vendor

A vendor return follows the scope-owner rule because an actual refund occurs:

- If the client paid the vendor directly, create a project Return/refund
  Transaction and negative project spend.
- If 1584 bought it into Business Inventory, create an inventory Return/refund
  Transaction.
- If the Item was also charged from inventory to a project, apply the applicable
  uncollected removal or paid-credit story in addition to the vendor refund.

The vendor refund and the project client credit are distinct economic events
and must not be collapsed into one record.

## Collection Behavior for Items

When the whole Invoice is collected:

1. freeze every Item line's Item ID, occurrence ID, signed amount, category,
   label, and relevant price snapshot;
2. create the one lump-sum Client → 1584 project Transaction;
3. attach each collected Item occurrence to that Transaction as historical paid
   membership;
4. remove the Items from active Invoicing; and
5. leave current physical placement unchanged.

The operation is atomic and idempotent. A retry cannot create a second payment
Transaction or duplicate an Item attachment.

## Data and Integrity Requirements

- `item.transactionId` cannot remain the sole authority for acquisition,
  current placement, open billing, and paid history.
- An occurrence has a stable ID and a signed, immutable paid snapshot.
- Open charge amounts may change only through the approved price workflow and
  only before collection.
- Paid Invoice lines and historical Transaction contents are append-only/frozen.
- Every return or correction points to the exact occurrence it reverses.
- Origin resolution fails closed when provenance is ambiguous.
- Source changes, live Invoice recalculation, physical placement, provenance,
  and budget-source state change in one trusted atomic operation.
- Background triggers may verify or repair derived totals, but there must be one
  authoritative mutation path to avoid recursive or competing recalculation.

## Required Test Stories

At minimum, automated tests must cover:

- sell → price edit → live Invoice total update;
- sell → return before Invoice;
- sell → add to created Invoice → return;
- sell → send Invoice → return;
- sell → collect → return → one credit only under retries;
- sell → collect → return → resell to the same project;
- sell → collect → return → resell to a different project;
- project-originated sale to inventory at purchase cost;
- return to source project from immutable inventory-entry snapshot;
- Project A → Project B with uncollected source demand;
- Project A → Project B with paid source demand;
- same-Client direct Transfer with open demand, live Invoice demand, and paid
  history;
- same-Client mixed paid/unpaid bulk Transfer without duplicate budget effects;
- return after one or more same-Client Transfers, using the approved destination
  credit rule and original frozen basis;
- cross-Client project sale proving the Transfer path is unavailable;
- direct client-paid vendor purchase and vendor return;
- inventory acquisition and vendor return;
- correction before collection and explicit correction after collection;
- collection retry, concurrent Item return, and concurrent project-price edit;
- budget total unchanged by collection, with paid/unpaid segments exchanged; and
- Additional Requests subtotal reported without double-counting Furnishings.

## Open Decisions

The parent spec owns the unresolved paid-credit settlement, negative budget-bar
display, zero-dollar Invoice, hidden-history storage, and receipt-allocation
decisions. None of them permits mutation of paid accounting history.
