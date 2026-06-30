# Billing & Invoicing v2

Status: historical; superseded by [billing-invoicing.md](billing-invoicing.md) as the active product spec
Last updated: 2026-05-26
Implemented: 2026-04-21
Supersedes: [billing-invoicing.md](billing-invoicing.md) (shipped 2026-04-07)
Grounding: [../plans/money-story.md](../plans/money-story.md), [../plans/invoicing-reconciliation-decisions.md](../plans/invoicing-reconciliation-decisions.md)

> **Historical implementation spec.** This document describes the shipped
> 2026-04-21 billing redesign. New product work should use
> [billing-invoicing.md](billing-invoicing.md), which keeps signed invoice lines
> but clarifies that transactions record money movement, invoices demand money,
> and manual New Charge lines cover fees before collection.
>
> Important supersession: this historical document's "credit transaction" rule
> for returns after paid invoices is no longer valid. Active behavior is defined
> in [billing-invoicing.md](billing-invoicing.md): returned paid items create
> invoice credit demand, not synthetic transactions.

## Summary

A redesign of how invoicing and "who owes what" are tracked. The shipped v1 stores paid-state in three places (on items, on transactions, on invoices) and cascades between them. Invoices can only carry charges, so when money flows both ways on a project they can't tell the whole story. Nothing tracks a running balance. This spec collapses paid-state onto the invoice, lets invoices carry both charges and credits, and makes the running balance derivable.

The manual, pick-what-to-bill flow from v1 is preserved. What changes is the data model underneath.

## Core Model

### Billable activity is derived, not stored

A transaction is billable if its shape says so:

- A sale into a project — billable as a charge.
- An owed-to-company expense (business fronted money for the client) — billable as a charge.
- An owed-to-client expense (client fronted money for something the business covers) — billable as a credit.
- A return of an item that was previously on a paid invoice — billable as a credit.

Reassignments, inventory-internal moves, and canceled transactions are not billable.

A billable transaction is either on an invoice or not. "To invoice" is not a stored field — it's the set of billable transactions for a project whose id does not appear on any invoice (draft, sent, or paid) for that project.

A given transaction can be on at most one invoice at a time. When the user creates a new draft, the picker excludes anything already on another draft, sent, or paid invoice.

### Invoices are bidirectional

An invoice is a collection of lines. Each line carries a sign:

- Charge lines add to the total.
- Credit lines subtract from the total.

`totalCents` is the net. It can be positive (client owes the business) or negative (business owes the client).

When the user opens Create Invoice, the picker shows unbilled billable activity for the project. The sign of each line is determined by the transaction's shape (see above), not chosen by the user.

### Paid lives only on the invoice

The invoice's `status` (draft / sent / paid / voided) is the single source of truth for "has this been settled."

Items and non-itemized transactions no longer carry a `billingStatus` field. To know whether a given item or transaction has been paid for, follow its invoice membership: find the invoice it's on, read that invoice's status.

### Running balance is derived

"What does this client currently owe" is:

> sum of `totalCents` across all sent-but-unpaid invoices for the project
> \+ sum of net value of all unbilled billable activity

The Reports-tab cards ("Payable to Business" / "Payable to Client") are this number aggregated across projects and split by sign.

No stored balance field. Computed on read, same as the budget.

### TransactionStatus collapses

The `pending` and `completed` values go away. The only remaining value is `canceled`. In practice the field becomes an `isCanceled: Bool` or an enum with a single non-default case; shape TBD at implementation time.

## Billing Subtab (Project Detail)

Each project's detail view has a Billing subtab. Below the existing Billing content, this spec adds a three-tab pipeline, all computed from the same set of billable transactions filtered by invoice membership:

- **To Invoice** — billable transactions not on any invoice for this project. This is the pool. Create Invoice is a button on this tab and opens a picker against this list.
- **Invoiced** — transactions on a sent-but-unpaid invoice.
- **Paid** — transactions on a paid invoice.

The Reports-tab running-balance cards derive from the same underlying query, aggregated across projects.

## Invoice Lifecycle

Unchanged from v1 in transitions, changed in what the transitions do.

- `draft`: invoice exists, lines can be added or removed, not yet sent to the client. **Drafts are live previews** — the document stores only the membership index (`itemIds`, `transactionIds`). Every reader recomputes amounts and signs from the current item / transaction state, so editing an item's price outside the invoice flow is reflected immediately in the draft.
- `sent`: invoice has been issued. The signed `lines` array and net `totalCents` are materialized at this moment from the then-current state and written atomically with the status transition and `dateSent`. From this point on the invoice is a frozen snapshot — later edits to the underlying items or transactions do not change what the client sees.
- `paid`: client has paid. `datePaid` set. No cascade — nothing else to update.
- `voided`: invoice withdrawn. Its lines return to the unbilled pool. `dateVoided` set.

## What Goes Away

- `BillingStatus` enum and the `billingStatus` field on items and transactions.
- The `markPaid` cascade in `InvoiceService` (items/transactions no longer need flipping).
- The `markSent` cascade — same reason.
- The `voidInvoice` unbilled-revert logic — derived now, not stored.
- `TransactionStatus.pending` and `TransactionStatus.completed`.

## What Stays

- Manual invoice creation. User picks lines, saves, sends when ready.
- One transaction per budget category per project.
- Ledger generates invoice documents; money collection happens in external tools.
- Transaction cancellation.

## Migration Notes

Non-trivial. Existing data has:

- `billingStatus` fields on items and transactions — need read-compatible treatment, then a backfill that places legacy "invoiced" and "paid" items onto their correct invoice and drops the field.
- `TransactionStatus.pending` / `completed` values — rewritten to the new single-value shape. "canceled" stays. Everything else collapses.
- Existing invoices with `totalCents` as a pure sum — still correct under the new model (they have no credit lines), but new invoices computed differently.

Migration plan is out of scope for this spec. Implementation doc will cover it.

## Resolved Decisions

- **Returns after a paid invoice.** Superseded by the active billing spec. The shipped v2 idea was to generate a credit transaction on the project automatically. That is now rejected because no money moved. The active model creates ordinary draft invoice credit lines for returned paid items and does not create a synthetic transaction.
- **Partial payments.** Not doing it. An invoice is fully paid or not.
- **Multiple open drafts per project.** Allowed. A transaction can only be on one invoice at a time (see Core Model) — the picker enforces this.
- **One project per invoice.** An invoice covers lines from one project. Cross-project moves (project A → inventory → project B) produce the source project's exit transaction (Return or Sale-to-Inventory) plus the destination project's Purchase-from-inventory transaction; each project only invoices its own eligible lines.

## Related

- [../plans/money-story.md](../plans/money-story.md) — plain-English description of how money flows today.
- [../plans/invoicing-reconciliation-decisions.md](../plans/invoicing-reconciliation-decisions.md) — the five coupled decisions this spec resolves.
- [../plans/reports-tab-rework.md](../plans/reports-tab-rework.md) — the Reports-tab work that depends on this spec.
- [sale-transactions.md](sale-transactions.md) — the per-batch inventory movement model, upstream.
- [reassign-vs-sell.md](reassign-vs-sell.md) — why reassignments are not billable.
- [billing-invoicing.md](billing-invoicing.md) — the shipped v1 spec this supersedes.
