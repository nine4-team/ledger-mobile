# Invoicing & Settlement — Decisions on the Table

Working doc for the Reports-tab rework and the invoice/settlement reconciliation conversation. Grounding lives in [money-story.md](money-story.md). These are the five coupled decisions that need to be made to reconcile the overlapping state systems (TransactionStatus, BillingStatus, InvoiceStatus) and make net-position Reports cards possible.

## The Five Decisions

### 1. Where does "paid" live?

Today it's in three places — on each item, on the transaction (for non-itemized), and on the invoice — and they cascade. Messy.

Two coherent options:
- **(a)** Paid only lives on the invoice. Items/transactions just know which invoice they're on.
- **(b)** Paid only lives on items/transactions. Invoices are pure groupings with no status of their own.

Today's "all three + cascade" is the sloppy middle.

### 2. Are invoices one-way or bidirectional?

- **One-way.** Every line adds up. `totalCents` is a sum. (This is today.)
- **Bidirectional.** Lines have signs (charge vs credit). `totalCents` is net.

User has stated preference for netting → points to bidirectional.

### 3. Is there a settlement concept outside invoices?

- **No.** Every debt and credit flows through an invoice, including we-owe-client. Netting clears debts.
- **Yes.** Some debts settle informally outside any invoice — needs its own entity or field.

User workflow (single netted invoice per project or phase) → points to "no separate settlement concept."

### 4. What happens to TransactionStatus (pending / completed / canceled)?

Downstream of #3.

- If settlement lives in invoices: pending/completed has no job. Field collapses to `canceled` only (or an `isCanceled: Bool`).
- If settlement stays partly on transactions: pending/completed survives as a lightweight settlement flag.

### 5. Running balance — stored or derived?

- **Derived.** Compute on read from invoices (+ any settlement records, if they exist).
- **Stored.** Denormalize onto the project.

Derivation is simpler and matches how the budget already works.

## The Coherent Path (Following User's Stated Preferences)

If the five decisions go the way the user has leaned in conversation:

1. Invoices become **bidirectional** — charges and credits, net total.
2. "Paid" lives **only on the invoice**. Items and transactions just reference their invoice (and know whether they're on one).
3. **No separate settlement concept.** Everything clears through an invoice. We-owe-client becomes a credit line on the next invoice.
4. **TransactionStatus collapses to `canceled` only** (or `isCanceled: Bool`). Pending/completed go away.
5. **Balance is derived** at read time from invoices.

This is the path that follows from what the user has said — not the only path. If any one decision flips, the plan reshapes.

## Known Downstream Implications of the Coherent Path

- **BillingStatus on items becomes redundant** (invoice membership + invoice status covers it). Likely deletable.
- **Item-level billing UI** (showing unbilled/invoiced/paid badges on items) would need to resolve status indirectly via the item's invoice.
- **Reports cards** ("Payable to Business" / "Payable to Client") become derived from summing unpaid invoice net positions per direction.
- **Migration work** is non-trivial: existing billingStatus fields on items and transactions, existing pending/completed TransactionStatus values all need read-compatible treatment.
- **`reimbursementType` narrowing** (see [transaction-flow-v2-unified.md](transaction-flow-v2-unified.md)) still happens. Under the coherent path, `reimbursementType` is just a signal to the invoice picker that a transaction should be suggested as a credit line, not a charge.

## Open Follow-ups (Not Yet Decided)

- Returns after an invoice is already paid — do they auto-generate a credit on the next invoice, or is it manual?
- Partial payments — still deferred, but worth revisiting once the paid-state question (#1) is settled.
- Can one project have multiple open invoices at once, or is it one-at-a-time? Spec currently allows multiple.
- Cross-project invoicing — spec says probably single-project; confirm.

## Current Status

Decisions are on the table. User has leaned toward the coherent path above but has not formally committed. Next step: user picks which of the five decisions to lock in (or flip), then a spec can be drafted against those choices. No code changes before spec.

## Related

- [money-story.md](money-story.md) — plain-English description of how money flows today, the grounding doc for this conversation.
- [reports-tab-rework.md](reports-tab-rework.md) — the downstream work waiting on these decisions.
- [transaction-flow-v2-unified.md](transaction-flow-v2-unified.md) — the `reimbursementType` narrowing, upstream of all this.
- [../specs/billing-invoicing.md](../specs/billing-invoicing.md) — current shipped invoice spec.
- [../specs/sale-transactions.md](../specs/sale-transactions.md) — per-batch inventory movement model.
- [../specs/reassign-vs-sell.md](../specs/reassign-vs-sell.md) — reassignment (data fix) vs sale (financial event) distinction.
- [../specs/_feedback-log.md](../specs/_feedback-log.md) (dated 2026-04-03) — original user feedback driving progressive invoicing.
