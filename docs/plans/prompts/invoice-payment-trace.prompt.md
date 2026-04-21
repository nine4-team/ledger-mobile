# Prompt — Trace Invoice, Payment, and Reimbursement-Settlement Data Model

## Context

The Reports sub-tab under Finances (file: [LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift](../../../LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift) — the filename is stale; users see "Reports") shows two summary cards today: "Payable to Business" and "Payable to Client." Those cards are pure sums of transactions tagged via `reimbursementType`. They do not account for anything that has already been paid or settled.

A planned change to the transaction flow is narrowing `reimbursementType` to mean only "this specific transaction is a reimbursement handoff" — see [docs/plans/transaction-flow-v2-unified.md](../transaction-flow-v2-unified.md). Under that narrowing, the current Reports cards will become meaningless (most transactions won't be tagged). The cards need to be reworked to show **net positions**: what the client actually owes the business right now, what the business actually owes the client right now — i.e., gross charges/credits minus what's been paid or settled.

Before writing the math, we need to know how "paid" and "settled" are represented in the data. That's what this task is about. See [docs/plans/reports-tab-rework.md](../reports-tab-rework.md) for the broader plan.

## Your Job

Investigate the codebase and report back (concise, under 600 words) with **exactly how invoices, invoice payments, and reimbursement settlements are modeled and tracked**. Research only — no code changes.

## Specific Questions to Answer

1. **Invoice model.** What file defines the `Invoice` struct? What fields does it have? Include `id`, `projectId`, `status` (and its possible values), any `totalCents`, `amountPaidCents`, `dateIssued`, `datePaid`, line-item structure, etc. File + line refs.

2. **Invoice lifecycle.** How does an invoice get from created → sent → paid? Who flips `status`? Is there a separate "payment" concept/model, or does paid status just mean "someone marked it paid"? Where is the flip performed (service / view / MCP tool)?

3. **Partial payments.** Is there any representation of a partial payment (e.g., client paid $500 of a $1000 invoice)? Or is it binary paid/unpaid?

4. **Invoice → transactions linkage.** How is it known which transactions a given invoice covers? Does the invoice carry a list of transaction IDs / item IDs? Does the transaction carry an invoice ID? Both? Neither? Reference fields and relevant service code.

5. **Reimbursement settlements.** If the business pays a client back for an `owed-to-client` reimbursement (or vice versa), how is that recorded? Options to check:
   - A separate settlement transaction that offsets the original.
   - A status field on the original transaction that flips (e.g., `reimbursementStatus: settled`).
   - Nothing — the feature doesn't exist yet.
   Report which it is, with file/line refs proving it.

6. **Existing Reports/accounting totals.** Re-read [AccountingTabView.swift](../../../LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift) and [Logic/ReportAggregationCalculations.swift](../../../LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift). Do any of the existing computations subtract paid-invoice amounts or settled reimbursements from the totals? (Expected answer: no. Confirm and cite.)

7. **MCP surface.** What invoice/payment-related MCP tools exist in [mcp-server/src/tools/](../../../mcp-server/src/tools/)? (Names and one-line descriptions only.)

8. **Specs.** Is there an invoicing spec at [docs/specs/billing-invoicing.md](../../specs/billing-invoicing.md) or elsewhere? If so, what does it say about payments and settlements? If it's out of date vs. the code, note the drift.

## Format for Your Report

Answer each numbered question directly, with file:line citations. Don't speculate — if the data isn't there (e.g., no settlement model exists), say so explicitly. End with a short "Gaps for the Reports rework" section: bullet list of concepts that would need to be *added* to the data model to make net-position cards possible (e.g., "no partial-payment model exists — would need an `invoicePayments` subcollection or `amountPaidCents` on Invoice"). No code changes, no design proposals — just what's there and what's missing.
