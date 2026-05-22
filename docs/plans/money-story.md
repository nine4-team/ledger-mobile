# The Money Story — As It Works Today

This is a plain-English description of how money moves through Ledger right now. It's the grounding for any conversation about invoicing, settlements, and net-position reporting. Read it. Mark what doesn't match how you want it to work. Design conversations can resume from there.

## Items, projects, and inventory

An item lives in one of two places: business inventory, or inside a project. An item in inventory has no budget category. An item in a project has both a budget category and a transaction it was attached to. Nothing else. The category is wiped on the way back to inventory, so the two states stay clean.

## Two ways items change location

There are two different operations. They look similar but mean different things.

A **reassignment** is a fix. The user put an item somewhere by mistake and is correcting it. No money changes hands, no Sale or Return transaction is written, no project budget shifts. The item just gets re-pointed to the right transaction. This is a data-correction tool.

A **movement** is the real financial event. When an item enters a project from business inventory, a Purchase-from-inventory transaction is written and the project's spend in the chosen category goes up. When an item goes the other way, leaving a project back to inventory, a Return transaction is written (or, in the narrow case where the item was born in the project, a Sale-to-inventory). Either way, money has moved and the project's budget reflects it. Inventory movement transactions and Returns are the operations that change what the client might owe.

That's all an inventory movement transaction is. It's a record with a money impact on one project's budget. It does not know anything about the client being billed.

## Direct project expenses

Some things aren't items: install crew, fuel, a permit fee. These become transactions with no items attached. They affect the project's budget directly. A flag on the transaction, `reimbursementType`, says which direction the money was going at the moment of the expense — the business paid out for the client (client owes us) or the client paid out for something the business covers (we owe the client).

## What an invoice is

An invoice is a separate document the user builds by hand. The user opens the Create Invoice flow, picks some items and some non-itemized transactions, and saves. Each thing picked gets its billing status flipped from unbilled to invoiced. When the invoice is later marked paid, every picked thing flips from invoiced to paid. The invoice itself has its own lifecycle: draft, sent, paid, voided. The total on an invoice is a pure sum — every line adds up, no signs, no credits.

Invoices are never created automatically. Inventory movement transactions don't produce invoices. Nothing in the system connects the two layers.

## What the system doesn't track

There is no "the client currently owes us $X" number anywhere. The Reports cards try to estimate it by summing reimbursement-tagged transactions, but that's a gross total, not a balance — it ignores anything already invoiced or paid.

Invoices can't carry credits. If the business has charged the client $500 in furnishings and the client also paid $100 out of pocket for fuel the business should cover, the invoice can only show $500. The $100 either gets reconciled outside Ledger or the user edits the invoice total manually.

Returns don't issue refunds. If an item was invoiced and paid, then later returned to inventory, nothing records that the client is now owed money back. The item simply leaves the project and the paid-invoice history stays untouched.

Partial payments don't exist. An invoice is either paid in full or not paid. The user can't say "client paid half."

Settlements aren't recorded. When the business pays the client back for money the client advanced, no field or entity captures that the debt was cleared. The original `owed-to-client` transaction sits there forever tagged the same way.

## The summary in one line

Inventory movements move items and change project budgets. Invoices are one-way bills the user assembles manually. Nothing in between tracks running balances, credits, refunds, partial payments, or settlements. Every design conversation about the Reports cards keeps hitting the same wall because that in-between layer doesn't exist yet.
