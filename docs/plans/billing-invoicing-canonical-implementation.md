# Billing & Invoicing Canonical Model — Implementation Plan

**Status:** Implementation pass complete; sandbox/data backfills still require operator-run validation
**Created:** 2026-05-26
**Spec:** [../specs/billing-invoicing.md](../specs/billing-invoicing.md)

## Summary

Bring the app, MCP server, tests, reports, and docs into alignment with the
canonical billing model:

- **Transaction** = money moved.
- **Invoice** = demand for money.
- **Invoice line** = component of that demand.
- **Manual New Charge line** = invoice demand not backed by an existing item or
  transaction.
- **Settlement transaction** = ordinary transaction linked to an invoice or
  invoice lines as evidence that money moved.

This is a semantic migration from "paid is inferred from invoice membership" to
"collection is auditable through real transactions linked to invoice demand."
Implementation should be additive first, then convert readers, then clean up old
compatibility assumptions.

## Goals

- Preserve ad-hoc invoices built from existing items and transactions.
- Add manual New Charge invoice lines for design fees, retainers, storage fees,
  project management fees, and similar demands where no money has moved yet.
- Create or link one transaction per real payment event, not one transaction per
  invoice line.
- Exclude settlement-linked transactions from billable pools and invoice-source
  calculations.
- Keep existing invoices readable during migration.
- Make stale specs point at the canonical billing model.

## Non-Goals

- Payment processing. Ledger records settlement; it does not move money through
  Stripe, Square, QuickBooks, a bank, or card processor.
- A standalone `ProjectCharge` table. Manual New Charge lines live on invoices
  unless a future workflow proves project-level charges are needed.
- Partial-payment automation beyond line/invoice settlement linkage. The model
  should support partial settlement, but this plan does not require bank-feed
  matching or external reconciliation.

## Status

| Phase | Status |
|---|---|
| Phase 0 — inventory and decisions | Complete |
| Phase 1 — additive data model | Complete |
| Phase 2 — invoice writers and manual lines | Complete |
| Phase 3 — collection and settlement writes | Complete for create-new settlement flow |
| Phase 4 — reader/math conversion | Complete for app billing/report paths touched by settlement |
| Phase 5 — MCP support | Complete locally; needs sandbox smoke test |
| Phase 6 — migration/backfill | Script updated and syntax-checked; production run pending |
| Phase 7 — docs cleanup | Complete for known active references |

## Phase 0 — Inventory and Decisions

**Scope:** confirm the exact field names, UI labels, and migration constraints
before code changes.

**Decisions recorded 2026-05-26:**

1. Final transaction settlement field names:
   - `settlementInvoiceId: String?`
   - `settlementInvoiceLineIds: [String]?`
   - A transaction with `settlementInvoiceId` is a settlement transaction for
     billing purposes and must be excluded from billable membership and
     invoice-source calculations.
2. Final invoice-line ID strategy:
   - Every invoice line has `id: String`.
   - New lines use UUID strings created when the draft line is added.
   - Existing item/transaction draft selections receive line IDs when the draft
     is converted to line-backed storage in Phase 2.
   - Backfilled historical lines get deterministic IDs from
     `invoiceId + sourceType + sourceId + lineIndex` so the script is idempotent.
   - Line IDs survive draft edits and are frozen into sent invoices.
3. Membership indexes:
   - Keep `Invoice.itemIds` and `Invoice.transactionIds` as flat membership
     indexes for item and transaction lines.
   - Manual lines are represented only in `Invoice.lines`.
   - `itemIds` / `transactionIds` are derived from `lines`, not separately
     authoritative.
4. UI wording:
   - Data model source type: `manual`.
   - User action label: **New Charge**.
   - Invoice lifecycle may keep raw `status == paid` for compatibility.
   - Collection UX should say **Mark Collected** when it creates or links a
     settlement transaction.
5. Historical paid-invoice policy:
   - Do not synthesize settlement transactions for historical paid invoices in
     the first implementation.
   - Readers keep `Invoice.status == paid` as a compatibility-only collected
     signal until the team chooses a reviewed settlement backfill.
   - Any future historical settlement backfill must be explicit and auditable.
6. Production invoice audit:
   - Required before Phase 6 migration/backfill, not before Phase 1 additive
     model work.
   - Audit counts: invoices with `lines == nil`, status distribution, lines
     lacking IDs, and stored `totalCents` drift from line sums.

**Ship gate:** complete. Phase 1 can start.

## Phase 1 — Additive Data Model

**Scope:** add fields and Codable support without changing behavior.

**Completed 2026-05-26.**

Notes:

- iOS model additions landed for manual invoice lines, stable line IDs, optional
  line `sourceId`, line settlement reverse lookup, and transaction settlement
  linkage.
- MCP TypeScript mirror types landed.
- Firestore rules do not need a change for Phase 1: transaction immutability
  freezes movement shape fields only, and settlement fields are non-shape;
  invoice rules already allow the new line shape.
- Cloud Functions do not read these fields today, so no Phase 1 function change
  is required.
- Focused iOS model/service/report tests and MCP TypeScript build passed.

### iOS Models

1. Update [Invoice.swift](../../LedgeriOS/LedgeriOS/Models/Invoice.swift):
   - Add `manual` to `InvoiceLineSourceType`.
   - Add stable `id` to `InvoiceLine`.
   - Make `sourceId` optional for manual lines.
   - Add optional `settlementTransactionIds` to `InvoiceLine` as a convenience
     reverse lookup. The transaction's `settlementInvoiceLineIds` remains the
     settlement source of truth.
   - Preserve decoding compatibility for existing lines that lack `id`.
2. Update [Transaction.swift](../../LedgeriOS/LedgeriOS/Models/Transaction.swift):
   - Add `settlementInvoiceId`.
   - Add `settlementInvoiceLineIds`.
   - Ensure these fields round-trip through Firestore.
3. Update model tests:
   - [ModelCodableTests.swift](../../LedgeriOS/LedgeriOSTests/ModelCodableTests.swift)
   - Any invoice-specific Codable fixtures.

### MCP / TypeScript Types

4. Update [mcp-server/src/types.ts](../../mcp-server/src/types.ts) with settlement
   fields and invoice-line shape if invoice tools/types are added there.
5. Update enum utilities if invoice line source types are centralized.

### Firebase Rules and Functions

6. Check [firebase/firestore.rules](../../firebase/firestore.rules) and
   [firebase/firestore.test.rules](../../firebase/firestore.test.rules):
   - Invoice rules are currently broad, but transaction create/update rules may
     need to allow settlement fields.
   - Add rule tests for settlement fields if rules constrain transaction shape.
7. Verify Cloud Functions that compute transaction completeness ignore settlement
   fields and do not treat settlement transactions as itemized audit candidates.

**Ship gate:** app builds; existing invoices and transactions decode unchanged;
no UI behavior changes.

## Phase 2 — Invoice Writers and Manual New Charge Lines

**Scope:** allow draft invoices to include manual New Charge lines while keeping
existing item/transaction invoice behavior.

**Completed 2026-05-26.**

Notes:

- Draft invoices can now persist full line selections, including manual New
  Charge lines.
- Create/edit invoice UI supports adding/removing manual charge lines and
  includes them in draft totals.
- Invoice preview/report aggregation handles manual lines and uses frozen sent
  line snapshots.

1. Update [InvoiceService.swift](../../LedgeriOS/LedgeriOS/Services/InvoiceService.swift):
   - Allow create/update APIs to accept full draft line selections, including
     manual lines.
   - Continue writing `itemIds` and `transactionIds` membership indexes derived
     from item/transaction lines only.
   - Store manual line label, amount, sign, and stable ID on the invoice line.
   - Materialize/freeze manual lines at `markSent` alongside item/transaction
     lines.
2. Update [InvoiceServiceProtocol.swift](../../LedgeriOS/LedgeriOS/Services/Protocols/InvoiceServiceProtocol.swift)
   to match the new API.
3. Update [CreateInvoiceModal.swift](../../LedgeriOS/LedgeriOS/Modals/CreateInvoiceModal.swift):
   - Add an **Add New Charge** action.
   - Let users create, edit, and delete manual lines on draft invoices.
   - Include manual lines in selected total.
   - Keep existing item and transaction picker behavior.
4. Update [InvoiceDetailView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/InvoiceDetailView.swift):
   - Show manual lines in the preview.
   - Permit editing manual lines only while invoice is draft.
5. Update invoice report aggregation:
   - [ReportAggregationCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift)
     must render `manual` lines.
   - Sent invoices should use frozen line names/amounts, not live lookups.
6. Update tests:
   - [InvoiceServiceTests.swift](../../LedgeriOS/LedgeriOSTests/InvoiceServiceTests.swift)
   - [InvoiceReportAggregationTests.swift](../../LedgeriOS/LedgeriOSTests/InvoiceReportAggregationTests.swift)
   - Add cases for manual charge, manual credit/adjustment if allowed, draft
     edit, sent freeze, and legacy invoice compatibility.

**Ship gate:** users can create a draft invoice containing existing items,
existing transactions, and manual New Charge lines; PDFs/previews show correct
signed totals.

## Phase 3 — Collection and Settlement Writes

**Scope:** marking collected creates or links a real transaction and links it to
the invoice or selected lines.

**Completed 2026-05-26 for the primary create-new-settlement path.**

Notes:

- The app's Mark Collected action creates one Fee transaction linked with
  `settlementInvoiceId`, optionally linked to invoice line IDs, then marks the
  invoice paid.
- MCP supports whole-invoice and selected-line collection.
- Existing-transaction settlement linking is left as an explicit follow-up
  because no current UI flow selects a pre-existing payment transaction.

1. Add a settlement service/helper.
   - Create one transaction for the real payment event.
   - Link it with `settlementInvoiceId`.
   - Optionally link selected `settlementInvoiceLineIds`.
   - If an existing transaction already records the payment, support linking it
     instead of creating a duplicate.
2. Decide transaction shape for client payments.
   - Likely `type: fee` for money received by the design business.
   - Require `amountCents`, `projectId`, `transactionDate`, and source/notes.
   - Use a fee category if required by budget/report display.
3. Update [InvoiceDetailView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/InvoiceDetailView.swift):
   - Replace the primary "Mark Paid" action with a Mark Collected flow.
   - Whole-invoice collection creates/links one transaction.
   - Line-level collection creates/links one transaction for the selected lines.
   - Do not create one transaction per invoice line unless there were distinct
     real payment events.
4. Update transaction create/edit flows if needed:
   - [NewTransactionView.swift](../../LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift)
   - [EditTransactionDetailsModal.swift](../../LedgeriOS/LedgeriOS/Modals/EditTransactionDetailsModal.swift)
   - Support setting/clearing settlement linkage for authorized workflows.
5. Update display copy:
   - Use "collected" for money received.
   - Reserve "sent/paid/voided" for invoice lifecycle where the status remains.

**Ship gate:** collecting an invoice can create exactly one settlement-linked
transaction; that transaction is visible as money movement and does not appear
as billable activity.

## Phase 4 — Reader and Math Conversion

**Scope:** convert all UI summaries, badges, reports, and billable pools to the
canonical settlement-aware model.

**Completed 2026-05-26 for current billing/report calculations.**

Notes:

- Settlement-linked transactions are excluded from billable membership and
  invoice-source report aggregation.
- Billing summary collected/outstanding math prefers settlement transactions and
  retains `Invoice.status == paid` compatibility for historical invoices.
- Draft invoice row totals include manual New Charge lines.

1. Update [InvoiceLineCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/InvoiceLineCalculations.swift):
   - Exclude settlement-linked transactions from `billableMembership`.
   - Include/manual-line helpers for invoice totals.
   - Revisit `sign(for tx:)`: fee transactions used as settlement should not be
     invoice-source charges.
2. Update [BillingSummaryCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/BillingSummaryCalculations.swift):
   - `Demanded/Invoiced` = sent/paid invoice demand.
   - `Collected` = settlement-linked transactions.
   - `Outstanding` = sent invoice demand minus settlement transactions.
   - Keep compatibility fallback to invoice `paid` status until all historical
     paid invoices have settlement records or a migration policy exists.
3. Update Billing subtab:
   - [FinancesTabView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/FinancesTabView.swift)
   - Pipeline labels may need to shift from `To Invoice / Invoiced / Paid` to a
     demand/collection framing.
   - Manual draft lines should appear where the user expects to track pending
     charge demand.
4. Update cards and detail views:
   - [ItemCardCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/ItemCardCalculations.swift)
   - [TransactionCardCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/TransactionCardCalculations.swift)
   - [ItemDetailView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift)
   - [TransactionDetailView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift)
   - Distinguish invoice demand status from collected settlement state.
5. Update reports/payable cards:
   - [AccountingTabView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift)
   - [ReportAggregationCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift)
   - [ReportHTMLBuilder.swift](../../LedgeriOS/LedgeriOS/Views/Reports/ReportHTMLBuilder.swift)
   - [ClientSummaryReportView.swift](../../LedgeriOS/LedgeriOS/Views/Reports/ClientSummaryReportView.swift)
   - [PropertyManagementReportView.swift](../../LedgeriOS/LedgeriOS/Views/Reports/PropertyManagementReportView.swift)
   - [InvoiceReportView.swift](../../LedgeriOS/LedgeriOS/Views/Reports/InvoiceReportView.swift)
6. Update exports/search if settlement transactions should be grouped or hidden:
   - [TransactionExportCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/TransactionExportCalculations.swift)
   - [SearchCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/SearchCalculations.swift)
   - [SharedTransactionsList.swift](../../LedgeriOS/LedgeriOS/Components/SharedTransactionsList.swift)
7. Update tests:
   - [BillingSummaryCalculationTests.swift](../../LedgeriOS/LedgeriOSTests/BillingSummaryCalculationTests.swift)
   - [BudgetTrackerCalculationTests.swift](../../LedgeriOS/LedgeriOSTests/BudgetTrackerCalculationTests.swift)
   - [TransactionCardCalculationTests.swift](../../LedgeriOS/LedgeriOSTests/TransactionCardCalculationTests.swift)
   - [ItemCardCalculationTests.swift](../../LedgeriOS/LedgeriOSTests/ItemCardCalculationTests.swift)
   - [ReportAggregationCalculationTests.swift](../../LedgeriOS/LedgeriOSTests/ReportAggregationCalculationTests.swift)

**Ship gate:** all user-facing billing totals have explicit demand vs collection
semantics; settlement transactions never double-count as invoiceable demand.

## Phase 5 — MCP Support

**Scope:** expose the canonical billing model to MCP and contract ingestion.

**Completed locally 2026-05-26.**

Notes:

- Added invoice tools: `apply_contract_setup`, `list_invoices`, `get_invoice`,
  `billable_pool`, `create_invoice`, `add_invoice_line`,
  `update_invoice_line`, `mark_invoice_sent`, `void_invoice`,
  `mark_invoice_collected`, and `mark_invoice_lines_collected`.
- Updated MCP schema/server instructions and TypeScript types for invoice demand
  vs transaction settlement semantics.
- `npm run build` passes. Sandbox smoke tests still need real credentials/data.

1. Add invoice tools in `mcp-server/src/tools/`:
   - `list_invoices`
   - `get_invoice`
   - `create_invoice`
   - `add_invoice_line`
   - `update_invoice_line`
   - `mark_invoice_sent`
   - `void_invoice`
   - `mark_invoice_collected`
   - `mark_invoice_lines_collected`
   - `billable_pool`
2. Add contract ingestion workflow:
   - Parse contract into project fields and draft invoice manual New Charge
     lines.
   - Do not create fee transactions until collection.
3. Update MCP transaction tools:
   - [transactions.ts](../../mcp-server/src/tools/transactions.ts) should accept
     settlement linkage only for valid settlement workflows.
   - Settlement-linked transactions should be searchable/filterable but clearly
     labeled.
4. Update MCP server prompt/context:
   - [index.ts](../../mcp-server/src/index.ts)
   - [http.ts](../../mcp-server/src/http.ts)
   - Mention invoices as demands and settlement-linked transactions as money
     movement.
5. Add MCP tests for invoice creation, manual lines, settlement creation, and
   billable-pool exclusion.

**Ship gate:** MCP can create a draft invoice with manual charges, mark it
collected by creating/linking a transaction, and prove the settlement transaction
does not return in `billable_pool`.

## Phase 6 — Migration and Backfill

**Scope:** make historical data compatible with stable line IDs and settlement
semantics.

**Completed locally 2026-05-26; production execution pending.**

Notes:

- [scripts/backfill-invoice-lines.mjs](../../scripts/backfill-invoice-lines.mjs)
  now writes deterministic line IDs for historical/generated lines and adds IDs
  to existing line arrays that lack them.
- `node --check scripts/backfill-invoice-lines.mjs` passes.
- No historical settlement transactions are generated by default.

1. Update [scripts/backfill-invoice-lines.mjs](../../scripts/backfill-invoice-lines.mjs):
   - Generate stable line IDs for existing lines.
   - Preserve item/transaction source types.
   - Do not invent manual lines.
   - Keep idempotency and dry-run output.
2. Decide historical paid-invoice settlement policy:
   - Phase 0 decision: keep `Invoice.status == paid` as compatibility-only
     collected signal for historical invoices.
   - Do not create historical settlement transactions unless a later reviewed
     migration explicitly chooses to.
3. Run a Firestore export before destructive migration.
4. Backfill invoice-line IDs.
5. If a settlement backfill is chosen, create/link settlement transactions with
   clear migration metadata so they are auditable.
6. Update scripts that mention billing v2 or legacy status:
   - [clear-legacy-transaction-status.mjs](../../scripts/clear-legacy-transaction-status.mjs)
   - [strip-billing-status.mjs](../../scripts/strip-billing-status.mjs)
   - migration changelog docs.

**Ship gate:** all invoices have stable line IDs; historical invoices still
render and summarize correctly; rollback anchor recorded.

## Phase 7 — Docs Cleanup and Spec Alignment

**Scope:** remove stale conceptual docs that still describe transactions as
pending demands or billing status as item/transaction state.

**Completed 2026-05-26 for known active specs/plans.**

Notes:

- Active specs now point to the canonical invoice-demand/transaction-settlement
  model.
- Historical v2 specs/plans remain in place as historical records and point to
  the canonical spec/plan.

1. Update stale specs:
   - [item-detail-view.md](../specs/item-detail-view.md): remove old
     `billingStatus` field references and describe invoice demand/settlement
     display instead.
   - [_app-map.md](../specs/_app-map.md): replace "no item-level billing status"
     and "separate billing status track" language with canonical model.
   - [reports.md](../specs/reports.md): update fee/invoice guidance for manual
     New Charge lines and settlement-linked fee transactions.
   - [project-closeout-report.md](../specs/project-closeout-report.md): already
     partially updated; verify formulas after Phase 4.
2. Update stale plans:
   - [money-story.md](money-story.md): mark historical or rewrite to canonical
     demand/money-movement model.
   - [reports-tab-rework.md](reports-tab-rework.md): replace open questions that
     are now answered by settlement linkage.
   - [billing-invoicing-v2-implementation.md](billing-invoicing-v2-implementation.md):
     mark historical and point to this plan.
3. Update feature docs:
   - [docs/features/invoice-import.md](../features/invoice-import.md) still
     mentions `status: "pending"` for imported transactions. Remove pending
     transaction language.
4. Update references/backlog:
   - [mcp-invoicing-tools.md](../backlog/mcp-invoicing-tools.md) should remain
     aligned with the tools implemented in Phase 5.
   - Any references to standalone project charges should point to manual New
     Charge invoice lines unless a future standalone entity is approved.
5. Update [../specs/_index.md](../specs/_index.md) and
   [../specs/_changelog.md](../specs/_changelog.md) after implementation.

**Ship gate:** `rg "billingStatus|pending transaction|ProjectCharge|service charges|billing-invoicing-v2"` in active specs/plans has only historical-context hits.

## Cross-Cutting Risks

- **Double-counting.** Settlement-linked fee transactions must not appear as
  invoice-source charge transactions.
- **Historical paid invoices.** Existing paid invoices may not have transaction
  evidence. Readers need compatibility or migration.
- **Line identity.** Line-level collection requires stable line IDs. Without
  them, partial settlement cannot be safely linked.
- **Draft behavior.** Existing draft invoices are live previews for item and
  transaction lines. Manual lines are different: their label/amount live directly
  on the draft.
- **Fee categories.** Existing budget/report code treats fee transactions as
  income. That may remain correct for settlement transactions, but invoice
  demand for fees now lives as manual invoice lines.
- **MCP write safety.** MCP must not create fake fee transactions from contracts.
  Contract ingestion creates draft invoice manual lines only.

## Verification Matrix

Minimum scenarios before release:

1. Draft invoice with only existing items.
2. Draft invoice with only existing transactions.
3. Draft invoice with only manual New Charge lines.
4. Mixed invoice with item + transaction + manual line.
5. Sent invoice freezes manual line label and amount.
6. Whole invoice collected with one settlement transaction.
7. Selected lines collected with one settlement transaction.
8. Existing transaction linked as settlement instead of creating a new one.
9. Settlement transaction excluded from To Invoice pool.
10. Paid historical invoice still renders and summarizes correctly.
11. Returned paid item creates/produces a credit path that remains billable and
    is not mistaken for settlement.
12. MCP contract ingestion creates draft manual lines and no fee transactions.
13. Closeout report includes manual charges and subtracts settlement
    transactions from outstanding.

## Suggested Implementation Order

1. Phase 0 decisions.
2. Phase 1 model additions.
3. Phase 2 manual invoice lines.
4. Phase 6 line-ID backfill, if needed before line-level settlement.
5. Phase 3 collection writes.
6. Phase 4 reader/math conversion.
7. Phase 5 MCP tools.
8. Phase 7 docs cleanup.

Phases 5 and 7 can start earlier in limited form, but reader/math conversion
should not be considered done until settlement-linked transactions are excluded
from every billable and payable calculation.
