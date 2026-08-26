# Purchase Handling and Inventory Intent

## Status

Active shipped specification. Implementation and runtime QA were completed by
2026-08-19. This document records the agreed transaction-creation,
inventory-intent, follow-up, pricing, correction, and MCP behavior discussed on
2026-08-17.

Quick-draft transaction association is included below and uses one authoritative
`transactionId`; transaction scope determines the conversion route.

## Purpose

`purchasedBy` answers who paid. It does not answer why the design business paid or
whether the purchase represents inventory for resale versus a project cost the
business temporarily covered.

For purchases paid by the design business, the New Transaction flow must ask for
the business intent explicitly instead of inferring it from purchaser or budget
category.

## Business-Paid Purchase Handling

After the user selects **Design Business**, show two primary choices and retain both
the title and explanatory copy:

- **Buy for resale** — Add it to business inventory. Items can be sold to a project
  now or later.
- **Cover a project purchase** — Keep it in this project and mark it payable to the
  business.

Persist the choice on the transaction using a field such as `purchaseHandling` with
the following canonical values:

- `inventory_resale`
- `project_reimbursement`

Do not continue deriving this intent from `purchasedBy`, itemized category metadata,
or `reimbursementType`.

### Buy For Resale From A Project

When the flow starts inside a project:

- Create the vendor purchase in business inventory.
- Set the current project as the intended project automatically.
- Preserve the budget category the user selected as the intended budget category.
- Do not offer an "I don't know yet" destination branch.
- Permit the user to add and sell the items immediately, but do not require the
  immediate flow to finish before the transaction can be saved.

The acquisition transaction remains an inventory transaction and therefore keeps
the inventory invariants:

```text
projectId = null
budgetCategoryId = null
```

Destination intent is stored separately:

```text
intendedProjectId = <current project ID>
intendedBudgetCategoryId = <selected project budget category ID>
```

The intended category is a destination hint, not the acquisition transaction's
actual `budgetCategoryId`. The category must be revalidated before the eventual
inventory-to-project sale.

### Buy For Resale From An Unscoped Entry Point

When the flow starts from business inventory or another account-level entry point:

- Allow the user to choose an intended project.
- Allow **I don't know yet**.
- If an intended project is selected, collect and persist its intended budget
  category.
- If the project is unknown, leave both intent fields empty and treat the purchase
  as general business inventory.

General inventory with no intended project is not overdue project-sale work and
must not appear in the intended-project follow-up queue merely because it remains
in inventory.

### Cover A Project Purchase

This path represents the design business temporarily paying a cost that belongs
directly to the project, such as when the client's payment method is unavailable.

- A project is required. When the flow starts inside a project, use the current
  project without another destination question.
- Create the purchase directly in that project.
- Keep the selected project `budgetCategoryId` on the transaction.
- Set `purchasedBy = design-business`.
- Set `reimbursementType = owed-to-company`.
- Do not show a second reimbursement question that could contradict the handling
  choice.
- Do not create an inventory acquisition or an inventory-to-project sale.

For items on this path—and every other item write path—persist:

```text
projectPriceCents = max(projectPriceCents ?? 0, purchasePriceCents ?? 0)
```

This makes purchase cost the minimum client-facing project price while preserving
any explicitly higher markup. Inventory resale uses the same invariant. A sale flow
asks for a price only when neither field is positive; it never permits a project
price below purchase cost.

### Cover A Project Purchase From An Unscoped Entry Point

When this choice is available outside a project, require the user to select the
project being covered. The transaction then follows the same direct-project rules
above.

## Intended Project And Category

An inventory acquisition and its eventual project sale may be separated by hours or
days. View-local state is not sufficient to preserve the destination.

Add the following optional transaction fields for `inventory_resale` purchases:

| Field | Meaning |
| --- | --- |
| `intendedProjectId` | Project expected to receive the items. Null for general inventory. |
| `intendedBudgetCategoryId` | Expected category for the future project purchase. Null when no intended project is known. |

The app should display the current project name by resolving `intendedProjectId`
against the account's project collection. Do not persist a duplicated project-name
snapshot that becomes stale after a rename. If the ID no longer resolves, show an
explicit unavailable or archived-project state.

## Transaction Grouping Invariant

One resale acquisition transaction has at most one intended project and one intended
budget category.

Items may be added and sold over time, but all items on that transaction share the
same intended destination. First-class item-level project or category overrides are
not part of this design. Purchases that mistakenly combine different destinations
must be corrected by separating the records rather than normalizing mixed grouping
as a supported workflow.

Partial completion is allowed only as a timing state: some items from the transaction
may have been sold to its one intended project/category while other items from the
same transaction still await entry or sale.

## Inventory Follow-Up

Business Inventory must surface intended-project purchases that still require work
in a distinct action area, such as **Planned for Projects**.

Useful derived states include:

- **Waiting for items** — the transaction has an intended destination but no item
  records have been added yet.
- **Ready to sell** — inventory items remain and have enough information to move.
- **Partially completed** — some items have moved to the intended destination and
  others remain.
- **Missing sale prices** — one or more items cannot be sold because neither a
  project price nor a purchase price can produce a positive normalized price.
- **Missing or invalid category** — the intended category is absent, archived, or no
  longer enabled for the intended project.
- **Project unavailable** — the intended project cannot be resolved.

An empty `itemIds` array is not sufficient to mean the intent is complete: the user
may have created the transaction before adding any items. Intent is resolved only
after all expected items have been handled or the user deliberately returns the
purchase to general inventory/cancels the intent.

Do not reuse transaction `isComplete` for this workflow. `isComplete` remains the
accounting and itemization-audit signal. Inventory disposition is a separate state.
The implementation may use an explicit resolution state or timestamp, provided it
can distinguish an empty-but-waiting transaction from a genuinely resolved one.

## Corrections Versus Business Events

A real inventory-to-project sale must continue through the canonical inventory
operation so that it creates the destination Purchase, updates item scope and price,
and writes lineage.

A purchase that was mistakenly routed to inventory but was actually a covered
project purchase is a correction, not a sale. The correction must atomically:

- move the original purchase into the selected project,
- restore its actual project budget category,
- set `purchaseHandling = project_reimbursement`,
- set `reimbursementType = owed-to-company`,
- update linked item data consistently, including the no-markup project-price rule,
- avoid creating fabricated sale transactions or movement lineage.

Legacy and ambiguous records must not be automatically classified from
`purchasedBy` alone.

## Ledger MCP Requirements

The Ledger MCP must support the complete transaction and inventory-intent cleanup
workflow without inventing accounting events.

It must be able to:

- list inventory resale transactions with unresolved intended-project work,
  enriched with intended project and category names;
- identify waiting-for-items, ready-to-sell, partially completed, missing-price,
  invalid-category, and unavailable-project conditions;
- set, change, clear, or resolve intended project/category metadata;
- validate that an intended category is active, non-system, canonically itemized,
  and already enabled for the intended project;
- perform canonical inventory-to-project sales for real movements;
- atomically correct purchases that were routed to inventory but should be direct
  project reimbursements;
- identify purchases that violate the one-project/one-category grouping invariant
  so a human can separate them;
- produce dry-run plans before material cleanup; and
- leave ambiguous historical records for human confirmation rather than guessing.

For quick drafts, the MCP must also:

- read, set, change, or clear the one authoritative `transactionId`;
- validate the referenced transaction's account and scope before conversion;
- report project drafts marked From Inventory that still lack an inventory
  `transactionId` or conflict with a selected project transaction;
- atomically promote a project draft linked to an inventory transaction through the
  inventory-create-and-sell sequence defined in `proto-item-capture.md`;
- leave the draft unconverted when required project, category, price, or transaction
  data is missing; and
- audit legacy `candidateTransactionId` values for human review without silently
  treating them as confirmed associations.

MCP transaction-intent tools must clearly distinguish real-event operations from
correction operations in their names, descriptions, validation, and output.

## Quick-Draft Transaction Association

Quick drafts use one authoritative `transactionId` for the transaction the eventual
item should initially join. `candidateTransactionId` is deprecated and must not act
as a promotion fallback. Suggested matches remain transient until a human confirms
one and writes `transactionId`.

For a project-scoped draft, the referenced transaction's scope determines conversion:

- a transaction in the same project produces a direct project item association;
- a business-inventory transaction triggers one atomic operation that creates the
  item under the acquisition transaction and immediately performs the canonical sale
  into the draft's project; and
- a transaction in another project is invalid until corrected.

The final project item points to the newly created Purchase-from-inventory
transaction, while lineage preserves the original acquisition. See
[Proto Item Capture](proto-item-capture.md) for the complete validation and write
sequence.

## Related Specifications

- [Transaction Creation Flow](transaction-creation.md)
- [Inventory Movement Transactions](sale-transactions.md)
- [Inventory as a Store](inventory-as-store.md)
- [Transaction Completeness](transaction-completeness.md)
- [Billing & Invoicing](billing-invoicing.md)
