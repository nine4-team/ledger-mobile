# Reports Tab — Rework

> ⚠️ **In-progress design.** Spun out from the Payable-semantics conversation in [transaction-flow-v2-unified.md](transaction-flow-v2-unified.md). The goal here is separate: figure out what the Reports sub-tab (under Finances) should actually show, and reword / restructure it accordingly.

## Current State

**Location:** Finances tab → Reports sub-tab. [FinancesTabView.swift:8-20](../../LedgeriOS/LedgeriOS/Views/Projects/FinancesTabView.swift:8) wires it up. The implementing view file is still named [AccountingTabView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift) — that filename is stale, it's "Reports" to the user.

**What it currently shows:**

1. Two summary cards, stacked as two rows:
   - **"Payable to Business"** = sum of transactions where `reimbursementDirection == .owedToCompany`.
   - **"Payable to Client"** = sum where `.owedToClient`.
2. A list of report types below (Invoice, Client Summary, Property Management) that link to PDF-exportable reports.

**Known problems:**

- Cards are two separate rows; should be a single row (user note).
- Card labels map to the narrow `reimbursementType` interpretation, but the totals don't tell the full "what does the client owe / what does the business owe" story.
- Once the transaction flow migrates to the narrow-semantic-with-toggle model (see [transaction-flow-v2-unified.md](transaction-flow-v2-unified.md)), most transactions will have `reimbursementType = none` — so these cards will become very small numbers that no longer represent the full picture.

## Concept

The user's framing:

> "For the statistics under reports, the concept is to understand what is owed to the business and what is owed to the client."

So the cards should answer two questions about a project at a point in time:

- **What does the client owe the business?** (net, accounting for payments already received)
- **What does the business owe the client?** (reimbursements outstanding, accounting for any already settled)

These are **net positions**, not raw sums of reimbursement-flagged transactions. That's the gap.

## What Feeds Each Side

**Owed to business** should include, conceptually:

- Fees charged to the client (not reimbursements — fees are direct charges).
- Chargeable project expenses the business paid for on the client's behalf.
- Items sold to the client (per per-batch sale transactions; see [sale-transactions.md](../specs/sale-transactions.md)).
- Minus: invoice payments already received from the client.

**Owed to client** should include:

- Reimbursements where the client advanced money for something the business covers — `reimbursementType = "owed-to-client"` under the narrow-semantic model.
- Minus: reimbursements already paid back.

## The Sticky Part — "Already Paid"

Neither side is meaningful without accounting for what's already been settled:

- **Invoice payments.** The app has invoices (Billing sub-tab, [Invoice model](../../LedgeriOS/LedgeriOS/Models/Invoice.swift) — verify), with `InvoiceStatus.paid`. A paid invoice should reduce "owed to business" by its total. But today the Reports totals don't look at invoice status at all — they're pure transaction sums.
- **Reimbursement settlements.** If the business pays the client back for a `owed-to-client` expense, how is that recorded? Is there a settlement transaction, or a status flip on the original transaction? **Unknown — needs investigation before proposing the math.**

Until we know how settlements are represented in data, we can't write the formula for net outstanding.

## Open Questions

1. **Is "Reports" even the right home?** These are live net-position cards, not generated reports. They may belong on a Dashboard / project summary screen. The Reports tab could be just the exportable report list.
2. **How are invoice payments recorded?** Need to read the Invoice / payment model. Does `InvoiceStatus.paid` alone track receipt, or is there a payment transaction?
3. **How are reimbursement settlements recorded?** Offsetting transaction? Status on the original? Nothing at all today (i.e., the feature doesn't exist yet)?
4. **Layout — single-row cards.** User note: the two cards should fit on one row, not stack. Easy change once the content is right.
5. **Do we want a third card?** E.g., "Unbilled work" — approved items not yet on an invoice. Or "Net project P&L." Out of scope unless requested.
6. **Retention.** User said "I don't know if we're even going to keep them." So an option on the table: drop the cards entirely, make Reports purely the exportable-report list.

## Next Steps

1. Trace the invoice / payment / settlement data model — we cannot design the math without it. No code changes until this is understood.
2. Decide layout intent (single-row cards vs. something else) after content intent is settled.
3. Draft a spec for the reworked tab once decisions are made.

## Related

- [transaction-flow-v2-unified.md](transaction-flow-v2-unified.md) — why `reimbursementType` is going narrow.
- [../specs/billing-invoicing.md](../specs/billing-invoicing.md) — existing invoice spec (check).
- [../specs/canonical-sales.md](../specs/canonical-sales.md), [../specs/sale-transactions.md](../specs/sale-transactions.md) — how sales feed into what the client has been charged.
