# Billing & Invoicing
Status: shipped (auto-payment detection deferred)
Last updated: 2026-04-07
Implemented: 2026-04-07

## Summary
Progressive billing for projects — the ability to bill clients mid-project for approved items rather than waiting until the end. Items within a project transaction have individual billing statuses, invoices can be generated from selected items, and marking an invoice as paid automatically updates all items on it. Stretch goal: auto-detect payment via email integration.

## Current Behavior (What Exists Today)

- Ledger can generate invoices (downloadable documents), but does not handle money collection or payment tracking in-app
- The user downloads the invoice and attaches it to external payment software (e.g., Stripe, Square, QuickBooks — exact tool TBD) to collect payment
- There is no item-level billing status — once items are in a project, there's no way to distinguish "billed" from "unbilled" items within a transaction
- There is no way to bill for a subset of items mid-project; billing happens outside the app at the end of a project
- All items within a project's category transaction are treated the same regardless of whether the client has approved, been invoiced for, or paid for them

## What's Changing

### Staying the Same
- One transaction per budget category per project (e.g., one Furnishings transaction that accumulates items over time)
- Ledger generates invoices as downloadable documents
- Actual money collection happens in external payment software (Ledger does not process payments)

### Changing
- **Items get individual billing statuses.** Each item within a project transaction now has a status: unbilled, invoiced, or paid. This replaces the current flat/untracked state.
- **Invoice generation becomes item-aware.** Instead of generating a generic invoice, the user selects specific items from a transaction to include on an invoice. Only selected items move to "invoiced" status.

### Adding
- **Item-level billing status** (unbilled → invoiced → paid) — visible on each item within a project transaction
- **Selective invoicing from transactions** — user can check/select approved items from a transaction and generate an invoice for just those items
- **Invoice-level payment confirmation** — when the user marks an invoice as "paid," all items on that invoice automatically update from "invoiced" → "paid" (no manual per-item updates)
- **Project billing summary** — a view showing total project cost, total invoiced, total collected (paid), and total still outstanding
- **Stretch goal: auto-payment detection** — Ledger monitors incoming email for payment confirmation notifications from the external payment software and automatically marks the corresponding invoice (and its items) as paid via MCP integration

### Removing
- Nothing explicitly removed — this builds on what exists

## How It Works

### Item Billing Status
Every item within a project transaction has one of three billing statuses:

- **Unbilled** — item is in the project, client has not been invoiced for it yet. This is the default status when an item enters a project (whether sold from inventory or logged as a direct expense).
- **Invoiced** — item has been included on an invoice that was sent to the client. Payment has not been received yet.
- **Paid** — client has paid for this item (confirmed either manually or via auto-detection).

Status transitions are one-directional under normal flow: unbilled → invoiced → paid.

For non-itemized expenses (install, fuel, etc.), the billing status applies to the expense entry itself rather than individual items, since these aren't itemized.

### Generating an Invoice (Mid-Project or End-of-Project)
1. User opens the project's Finances → Billing tab
2. User taps "Create Invoice"
3. The Create Invoice picker presents every billable item and non-itemized expense in the project (see "Billable Membership" below). A search field at the top filters both lists in real time by name, source, or SKU using the same matchers as the rest of the app.
4. User selects/checks the items and expenses they want to bill for — typically those the client has already approved. Selections persist across search queries (selecting an item, changing the search, then returning to a different filter still keeps it counted in the running total).
5. User reviews step 2: optional **Invoice Name** (free-form, e.g. "Phase 1 — Furnishings"), optional notes, total. Tapping Create makes the invoice in `draft` status and cascades every selected item + transaction to `billingStatus = invoiced` in one atomic batch.
6. User downloads (or otherwise exports) the invoice and sends it through their external payment software, then can mark it Sent in Ledger.

### Billable Membership

The Create Invoice picker includes:

- **Items** that satisfy: persisted, `billingStatus ∈ {nil, unbilled}`, AND `status != returned` (returned items are terminal and never billable).
- **Transactions** that satisfy: persisted, **non-itemized** (no `itemIds` — itemized transactions are excluded so their value isn't double-counted alongside their child items), `billingStatus ∈ {nil, unbilled}`, AND `status != canceled`.

Transactions where `isComplete != true` ("needs review") **are** included in the picker but each row is flagged with a "Needs Review" badge so the user can decide whether to bill them as-is.

The user can generate multiple invoices over the life of a project — one for the big items confirmed early on, another for accessories confirmed later, a final one for remaining items at project end. Each invoice is a separate billing event.

### Invoice Across Categories
A single invoice should be able to pull items from multiple transactions/categories within the same project. For example, one invoice to the client might include:
- 3 items from the Furnishings transaction
- The install crew expense from the Install transaction
- 2 items from the Additional Requests transaction

This means the invoice is its own entity — it references items across transactions, not tied to a single transaction.

### Marking an Invoice as Paid
1. User receives confirmation that the client has paid (via their payment software, email, etc.)
2. User opens the invoice in Ledger and marks it as "Paid"
3. **All items on that invoice automatically update** from "invoiced" → "paid" — no per-item manual changes required
4. The project billing summary updates to reflect the new totals

### Project Billing Summary
The project view includes a billing summary showing:
- **Total project cost** — the sum of all items and expenses in the project across all categories
- **Total invoiced** — the sum of all items/expenses that have been included on invoices (status: invoiced + paid)
- **Total collected** — the sum of all items/expenses where payment has been received (status: paid)
- **Total outstanding** — the sum of all items/expenses not yet paid (status: unbilled + invoiced)

This summary gives an at-a-glance picture of where the project stands financially — how much has been spent, how much has been billed, how much has been collected, and how much is still owed.

### Stretch Goal: Auto-Payment Detection via Email/MCP
Rather than manually marking invoices as paid, Ledger could monitor the team's email for payment confirmation notifications from their payment software. When a matching email arrives (e.g., "Invoice #1234 has been paid"), an MCP integration could:
1. Parse the email to identify the invoice
2. Match it to the corresponding invoice in Ledger
3. Automatically mark the invoice as paid
4. Cascade the status update to all items on that invoice

This would eliminate the manual confirmation step entirely. Requires: email MCP access, reliable invoice ID matching between Ledger and the payment software, and a way to handle edge cases (partial payments, failed payments, refunds).

## Open Questions
- What does the invoice document look like today? What fields/layout does the current invoice generator produce? [needs discovery]
- Should invoices be browsable as a list within the project (e.g., "Invoice History" section), or just downloadable one-time documents?
- Can a single invoice span multiple projects, or is it always one invoice per project? (Likely one per project, but worth confirming.)
- What payment software does the team use? This matters for the auto-detection stretch goal — different platforms send different email formats.
- Should there be a "void" or "cancel" action for invoices? (e.g., client disputes items after invoicing, items need to go back to "unbilled")
- For partial payments — if a client pays half an invoice, how should that be handled? Mark individual items as paid? Or is it all-or-nothing per invoice?
- How should the billing status be visually represented on items? Color coding? Badge/tag? Status column?

---
## Implementation Notes
- Items have a `billingStatus` field (enum: unbilled, invoiced, paid). nil is treated as unbilled. Default for new items: unbilled.
- Transactions also have a `billingStatus` field — used for non-itemized expenses (install, fuel) that have no child items.
- The `Invoice` entity (`accounts/{accountId}/invoices/{id}`, with `projectId` field) references a list of `itemIds` AND `transactionIds`, has its own status (draft / sent / paid / voided), `totalCents` snapshot, and date stamps for issued / sent / paid / voided.
- The `invoiceNumber` Firestore field stores the user's free-form **Invoice Name** (the UI label is "Invoice Name", but the underlying field name is preserved for backward compatibility).
- All cascading operations (create → invoiced, markPaid → paid, void → unbilled) commit through one Firestore batch so they're atomic.
- Voiding an invoice reverts referenced items + transactions to `unbilled`, but **skips** any that have already moved to `paid` — paid is terminal.
- Auto-payment detection would use an email MCP to monitor inbox, parse payment notifications, and call Ledger's MCP to update invoice status — this is a significant integration effort and should be treated as a separate phase
- Consider whether billing status should also be reflected on the transaction level (e.g., "partially billed," "fully billed," "fully paid") for quick scanning
