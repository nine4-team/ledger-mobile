# Billing & Invoicing v2 — Implementation Plan

Status: Phases 1–4 shipped (2026-04-21); Phase 5 pending
Last updated: 2026-04-21
Spec: [../specs/billing-invoicing-v2.md](../specs/billing-invoicing-v2.md) (supersedes the shipped [billing-invoicing.md](../specs/billing-invoicing.md))

## 1. Summary

This is the implementation plan for the v2 billing/invoicing redesign. We are collapsing "paid state" from three places (item `billingStatus`, transaction `billingStatus`, invoice `status`) down to one (invoice `status`), making invoices bidirectional (lines carry signs, `totalCents` is net), and collapsing `TransactionStatus` to effectively just `canceled`. A three-tab pipeline (To Invoice / Invoiced / Paid) is added below the existing Billing subtab content on the project detail view, driven entirely by derived queries from invoice membership. A returned item that sits on a paid invoice auto-generates a credit transaction on the project that lands in the To Invoice pool. The Reports-tab cards switch from the current raw-sum-of-reimbursement-tagged-transactions formula to a running-balance derivation that nets unpaid invoices against unbilled billable activity. Migration is non-trivial — existing data has `billingStatus` everywhere and existing `TransactionStatus` values of `pending` / `completed` — so a read-compatibility phase precedes the destructive backfill.

## 2. Reference Docs

- Spec: [docs/specs/billing-invoicing-v2.md](../specs/billing-invoicing-v2.md)
- Prior spec (shipped v1, being superseded): [docs/specs/billing-invoicing.md](../specs/billing-invoicing.md)
- Grounding — money story: [docs/plans/money-story.md](money-story.md)
- Grounding — the five coupled decisions: [docs/plans/invoicing-reconciliation-decisions.md](invoicing-reconciliation-decisions.md)
- Downstream: [docs/plans/reports-tab-rework.md](reports-tab-rework.md)
- Upstream / related data model: [docs/specs/data-model.md](../specs/data-model.md), [docs/specs/sale-transactions.md](../specs/sale-transactions.md), [docs/specs/reassign-vs-sell.md](../specs/reassign-vs-sell.md), [docs/specs/transaction-type.md](../specs/transaction-type.md)

## 3. Scope

**In scope.** Introducing signed invoice lines; removing `billingStatus` from items and non-itemized transactions and deleting the `BillingStatus` enum; collapsing `TransactionStatus`; adding the Billing-subtab pipeline; switching the Reports cards to a derived running balance; migration of existing v1 data; cleanup of all readers of the deleted fields; rewriting the `InvoiceService` create/update paths; deleting the mark-sent / mark-paid / void cascades while keeping the invoice-status transitions themselves; auto-credit on return of a previously-paid item.

**Out of scope.** Partial payments (explicitly deferred by the spec). Invoice-document PDF layout changes beyond what's forced by bidirectional lines. Cross-project invoices. Auto-payment detection (the v1 stretch goal, which never shipped). MCP tool surface for invoicing — there are no invoice tools in `mcp-server/src/tools/` today and we are not adding any in this plan. Firestore rules changes beyond the minimum required (the current rule for `accounts/{accountId}/invoices/{invoiceId}` is `allow read, create, update, delete: if isAccountMember(accountId)` — nothing to tighten or loosen for v2 unless we add invariant enforcement, which this plan treats as optional).

## 4. Current State (Grounded in Code)

The v1 model ships with these concrete surfaces, which the managing agent should skim before assigning tasks:

- **Enums:** `BillingStatus` (`unbilled`, `invoiced`, `paid`) and `TransactionStatus` (`pending`, `completed`, `canceled`) both live at [LedgeriOS/LedgeriOS/Models/Shared/Enums.swift:69-83](../../LedgeriOS/LedgeriOS/Models/Shared/Enums.swift). Both conform to `CaseInsensitiveStringEnum` with legacy-alias support — the migration path leans on this.
- **Models carrying the fields.** `Item.billingStatus` at [Models/Item.swift:58](../../LedgeriOS/LedgeriOS/Models/Item.swift). `Transaction.billingStatus` at [Models/Transaction.swift:59](../../LedgeriOS/LedgeriOS/Models/Transaction.swift). `Transaction.status: TransactionStatus?` at [Models/Transaction.swift:39](../../LedgeriOS/LedgeriOS/Models/Transaction.swift). `Transaction.isComplete` is a separate flag ([Models/Transaction.swift:51](../../LedgeriOS/LedgeriOS/Models/Transaction.swift)) and is **not** going away — "Needs Review" is driven by `isComplete != true`, not by `TransactionStatus`.
- **Invoice model.** [Models/Invoice.swift](../../LedgeriOS/LedgeriOS/Models/Invoice.swift). Already has `itemIds`, `transactionIds`, `totalCents`, `status`, date stamps. Does not yet carry signed lines.
- **InvoiceService.** [Services/InvoiceService.swift](../../LedgeriOS/LedgeriOS/Services/InvoiceService.swift). Five methods do the cascades we are deleting:
  - `createInvoice` (lines 62-125) writes the invoice and cascades `billingStatus = .invoiced` onto every referenced item and transaction.
  - `updateSelections` (lines 132-206) diffs and cascades both added (→ `.invoiced`) and removed (→ `.unbilled`) entries.
  - `markSent` (lines 210-223) is already status-only — no cascade. **Keep.** (Spec says the cascade is going away, but that cascade is on create, not on send — `markSent` is already correct.)
  - `markPaid` (lines 227-260) cascades `billingStatus = .paid`. **Delete cascade, keep status transition.**
  - `voidInvoice` (lines 264-315) reverts non-paid items/transactions to `.unbilled`. **Delete cascade, keep status transition.**
- **Create Invoice modal.** [Modals/CreateInvoiceModal.swift](../../LedgeriOS/LedgeriOS/Modals/CreateInvoiceModal.swift). The picker lists `billableItems` and `billableTransactions` filtered by `billingStatus ?? .unbilled == .unbilled` (or on-this-invoice in edit mode). Total is an unsigned sum. Needs a rewrite to switch the pool query to "not on any invoice" and to render signed totals.
- **Invoice Detail.** [Views/Projects/InvoiceDetailView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/InvoiceDetailView.swift). Wires up Mark Sent / Mark Paid / Void. Confirmation dialog copy currently says "All items and expenses on this invoice will be updated to Paid." and "Items and expenses will revert to Unbilled" — both strings need to change because the cascades are gone.
- **Finances tab.** [Views/Projects/FinancesTabView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/FinancesTabView.swift) has the three-way segmented control: Budget / Billing / Reports. `BillingSubTab` (private struct in the same file, lines 32-91) hosts `BillingSummaryCard` and the invoice list. This is where the new three-tab pipeline slots in — below `BillingSummaryCard` and above or instead of the existing flat invoice list.
- **Billing summary.** [Logic/BillingSummaryCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/BillingSummaryCalculations.swift) computes Total Spent / Invoiced / Collected / Outstanding from `billingStatus` on items and non-itemized transactions. This is fully replaced by a derivation off invoice membership.
- **Reports cards.** [Views/Projects/AccountingTabView.swift:13-23](../../LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift) computes `owedToCompanyCents` and `owedToClientCents` by summing transactions tagged with a `reimbursementDirection`. Under v2 these become net running-balance derivations off invoices + unbilled activity (see [reports-tab-rework.md](reports-tab-rework.md) for the conceptual model).
- **Invoice PDF builder.** [Logic/ReportAggregationCalculations.swift:106-240](../../LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift) already has `InvoiceReportData` with `chargeLines` and `creditLines` — the data *type* supports bidirectional, but the per-invoice `computeInvoiceReport(for:items:transactions:)` writes everything to `chargeLines` with no signing logic. We extend this to read signs from stored invoice lines.
- **Filter UI leaning on `billingStatus`.** [Components/SharedTransactionsList.swift:36-201](../../LedgeriOS/LedgeriOS/Components/SharedTransactionsList.swift) offers a billing-status filter facet; [Components/TransactionFilterMenu.swift:115](../../LedgeriOS/LedgeriOS/Components/TransactionFilterMenu.swift) wires it in. Both need to be removed or re-pointed.
- **Readers elsewhere.** Badges on cards via `ItemCardCalculations` / `TransactionCardCalculations`, the `Billing` row in `ItemDetailView` (line 375), and the `BillingStatus` uses in `LedgeriOSTests/Helpers/TestFactories.swift` and `BillingSummaryCalculationTests.swift`.
- **Transaction writers of `status: "completed"`.** `InventoryOperationsService` writes `"status": "completed"` on generated Sale / Return transactions at lines 151, 366, 507, 693, 716. `NewTransactionView.swift:54` defaults `@State private var status: TransactionStatus = .completed`. `ReturnTransactionPickerModal.swift:17` reads `tx.status != .completed`. `EditTransactionDetailsModal.swift:89` exposes `TransactionStatus.allCases` as a dropdown. `ImportInvoiceModal.swift:392` sets `tx.status = .pending`. These are the concrete writers and readers of the values we're collapsing.
- **State wiring.** `AccountContext.allInvoices` ([State/AccountContext.swift:24,176](../../LedgeriOS/LedgeriOS/State/AccountContext.swift)) is the live invoice stream subscribed via `InvoiceService.subscribeToInvoices`. The new derived queries (To Invoice / Invoiced / Paid) all lean on this plus `projectContext.items` and `projectContext.transactions`.
- **Firestore rules.** `accounts/{accountId}/invoices/{invoiceId}` has a permissive rule ([firebase/firestore.rules:184-186](../../firebase/firestore.rules)). No field-level guards on `billingStatus` or invoice fields. Nothing blocks us at the rules layer.
- **MCP server.** Grepped `mcp-server/src/tools/` for `billingStatus` / `invoice` / `reimbursement` — no matches. The research report's claim that no invoice tools exist is verified. No MCP changes required.

## 5. Phased Task Breakdown

The phases are sequenced so the app remains shippable at the end of every phase. Phase 1 adds the new writes alongside the old ones. Phase 2 flips readers to the new model. Phase 3 removes the now-unused v1 fields. Phase 4 layers on the pipeline UI and Reports rework. Phase 5 migrates production data and removes read-compat shims.

### Phase 1 — Data model additions (non-destructive) — **SHIPPED 2026-04-20 (commit 19e18cc4)**

All seven tasks landed in one commit. Build green; unit tests pass (47 integration failures were pre-existing emulator-offline errors, not related to these changes). Task 1.7 shipped with a safe default — `paidInvoiceItemIds: Set<String> = []` — so existing callers are no-ops until Phase 2 wires `accountContext.allInvoices` through `SellToBusinessModal` and `TransactionDetailView`.


**Task 1.1 — Add `InvoiceLine` and signed-lines to `Invoice`.** Introduce a new nested `InvoiceLine` type (`sourceType: "item" | "transaction"`, `sourceId: String`, `amountCents: Int`, `sign: +1 | -1`, `snapshotName: String?`). Add `lines: [InvoiceLine]?` to the `Invoice` struct at [Models/Invoice.swift](../../LedgeriOS/LedgeriOS/Models/Invoice.swift). Keep `itemIds`, `transactionIds`, `totalCents` alongside — `totalCents` becomes net (charges minus credits) rather than gross sum. Follow the Codable + `CodingKeys` + legacy-field pattern documented in the repo's root CLAUDE.md §"Firestore Models". Acceptance: new invoices round-trip through Firestore; reading a v1 invoice (no `lines` field) returns an `Invoice` with `lines == nil`. Dependencies: none.

**Task 1.2 — Add a sign-derivation helper.** New pure function in a new file `LedgeriOS/LedgeriOS/Logic/InvoiceLineCalculations.swift`: given an `Item` or a `Transaction` plus the project's `BudgetCategory` map, decide whether it is a **charge** or a **credit** using the rules in the spec §"Billable activity is derived, not stored" (sale into project → charge; owed-to-company expense → charge; owed-to-client expense → credit; return-of-previously-paid → credit). Reuse [ReportAggregationCalculations.reimbursementDirection(for:)](../../LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift:81) as the starting point — it already maps to `.owedToCompany` / `.owedToClient`. Acceptance: `#expect`-style Swift Testing coverage for each of the four rule branches. Dependencies: 1.1.

**Task 1.3 — Add a "billable membership" derivation.** New pure function on the same file: given `(projectId, items, transactions, invoices)`, return the three disjoint sets — `toInvoice` (billable and not on any invoice for that project), `invoiced` (on a sent-but-unpaid invoice, *and* also include draft-invoice members per the spec's "excluded from the picker" rule), `paid` (on a paid invoice). Voided invoices don't belong to any bucket — their ids return to the toInvoice pool. Acceptance: test coverage enumerating draft / sent / paid / voided × member / non-member. Dependencies: 1.2.

**Task 1.4 — Update `InvoiceService.createInvoice` to write signed lines.** Rewrite [Services/InvoiceService.swift:62-125](../../LedgeriOS/LedgeriOS/Services/InvoiceService.swift) to accept either (a) a pre-built `[InvoiceLine]` plus precomputed net `totalCents` (preferred — keeps sign decisions at the UI/logic layer) or (b) the legacy `(itemIds, transactionIds, totalCents)` tuple for backward compatibility during migration. **Delete the `billingStatus = .invoiced` cascades** inside this method (spec §"What Goes Away"). Do not remove the method's existing `itemIds` / `transactionIds` writes — those are still the membership index used by the "already on an invoice?" check in Task 1.3; redundant with `lines[].sourceId` but cheaper to query. Acceptance: creating an invoice persists signed lines; no `billingStatus` writes issued to items or transactions. Dependencies: 1.1.

**Task 1.5 — Update `InvoiceService.updateSelections` symmetrically.** Same treatment at [Services/InvoiceService.swift:132-206](../../LedgeriOS/LedgeriOS/Services/InvoiceService.swift). Remove the added→`.invoiced` and removed→`.unbilled` cascades. Replace the `totalCents` recompute with a net computation from signed lines. Acceptance: editing a draft invoice's line set commits only invoice-doc writes; no item/transaction writes. Dependencies: 1.4.

**Task 1.6 — Strip cascades from `markPaid` and `voidInvoice`.** At [Services/InvoiceService.swift:227-315](../../LedgeriOS/LedgeriOS/Services/InvoiceService.swift), remove the per-item and per-transaction `billingStatus` updates in `markPaid` and `voidInvoice`. Keep the invoice-doc status transitions (`status`, `datePaid`, `dateVoided`). Delete the `itemsService.getItem` / `transactionsService.getTransaction` pre-batch reads in `voidInvoice` — they exist only to skip already-paid items, which no longer applies when nothing cascades. Simplify `voidInvoice` to a single invoice-doc update. Update [Services/Protocols/InvoiceServiceProtocol.swift](../../LedgeriOS/LedgeriOS/Services/Protocols/InvoiceServiceProtocol.swift) comments accordingly. Acceptance: both methods commit exactly one Firestore write (the invoice doc). Dependencies: 1.4.

**Task 1.7 — Auto-credit on return of a previously-paid item.** In [Services/InventoryOperationsService.swift](../../LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift) `returnToInventory` and the mixed-batch return path around line 454 and 517-527, when an item being returned has an invoice ancestor whose `status == .paid` (query `AccountContext.allInvoices` before building the batch — same pattern as the `frozenSources` lookup at line 470), append a **credit transaction** to the project. Shape: `transactionType = .expense`, `reimbursementType = "owed-to-client"`, `amountCents = item.purchasePriceCents ?? 0` (or `projectPriceCents` — spec doesn't nail this; see open question Q2), `source = "Credit: returned \(item.displayName)"`, `isComplete = true`. No `status: "completed"` — see Task 3.2. The new credit transaction lands in the To Invoice pool automatically because billable-membership is derived. Acceptance: returning a paid-invoice item produces one new transaction on the project; returning a never-invoiced item produces none. Dependencies: 1.3.

### Phase 2 — Reader cutover — **SHIPPED 2026-04-21**

All seven tasks landed. Build green; the `BillingSummaryCalculationTests` suite was rewritten against invoice membership and passes. Notable choices:

- Card badges: replaced `billingStatus: BillingStatus?` with `invoiceStatus: InvoiceStatus?`; card views derive via `firstNonVoidedInvoiceStatus(forItemId:in:)` / `(forTransactionId:in:)` over `accountContext.allInvoices`. Paid wins over sent wins over draft when an id appears on multiple invoices.
- Picker pool in Create Invoice now uses `InvoiceLineCalculations.billableMembership(...).toInvoice`; transactions split into Charges / Credits sections; the selected total is signed net.
- `BillingSummaryCalculations.summarize` signature became `(projectId:, items:, transactions:, invoices:)`. Voided invoices are excluded from both Invoiced and Collected.
- `SharedTransactionsList.TransactionFilterState` dropped the `billingStatus` facet entirely; the corresponding Billing Status group was removed from `TransactionFilterMenu`.
- `ItemDetailView` Billing row now renders the first non-voided invoice's status (or "Unbilled").
- `InvoiceDetailView` mark-paid / void confirmation dialogs no longer claim a cascade.
- `computeInvoiceReport(for:items:transactions:)` reads stored `Invoice.lines` when present, splitting into charge/credit sections by sign. Falls back to legacy all-charges for v1 invoices with no `lines`.



**Task 2.1 — Reroute the Create Invoice picker.** Rewrite `billableItems` and `billableTransactions` in [Modals/CreateInvoiceModal.swift:43-65](../../LedgeriOS/LedgeriOS/Modals/CreateInvoiceModal.swift) to use `InvoiceLineCalculations.billableMembership(projectId:items:transactions:invoices:).toInvoice` from Task 1.3 rather than reading `billingStatus`. Render the selected total as a signed net — group rows into a Charges section and a Credits section based on Task 1.2's classifier. Acceptance: the picker shows the correct pool even for items/transactions whose `billingStatus` is nil, and correctly excludes items/transactions already on any draft/sent/paid invoice. Dependencies: 1.3.

**Task 2.2 — Rewrite `BillingSummaryCalculations`.** Replace the `billingStatus`-keyed switches in [Logic/BillingSummaryCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/BillingSummaryCalculations.swift) with a derivation from invoice membership: `invoiced = sum over items+non-itemized-tx on any non-voided invoice for this project`; `collected = sum over items+non-itemized-tx on paid invoices`; `outstanding = totalSpent - collected`. Update `BillingSummaryCalculationTests` to match. Acceptance: tests green; card on the Billing subtab visually unchanged for projects with no v2 data (and still correct). Dependencies: 1.3.

**Task 2.3 — Drop the `billingStatus` badge on item/transaction cards.** Remove the branches in [Logic/ItemCardCalculations.swift:21](../../LedgeriOS/LedgeriOS/Logic/ItemCardCalculations.swift) and [Logic/TransactionCardCalculations.swift:55](../../LedgeriOS/LedgeriOS/Logic/TransactionCardCalculations.swift) that render the "Invoiced" / "Paid" badge from stored `billingStatus`. Replace with an invoice-membership lookup (accepts an `invoices: [Invoice]` parameter, same shape as existing `forecast` parameters on those helpers). Update the call sites at [Components/ItemCard.swift:36](../../LedgeriOS/LedgeriOS/Components/ItemCard.swift) and [Components/TransactionCard.swift:26-35](../../LedgeriOS/LedgeriOS/Components/TransactionCard.swift) to pass `accountContext.allInvoices`. Acceptance: badge still renders on items on a paid invoice; no longer depends on stored `billingStatus`. Dependencies: 1.3.

**Task 2.4 — Remove the `billingStatus` filter facet from `SharedTransactionsList`.** Delete the `billingStatus` field and its handling at [Components/SharedTransactionsList.swift:36,46,59,94,199-202](../../LedgeriOS/LedgeriOS/Components/SharedTransactionsList.swift) and the matching menu wiring at [Components/TransactionFilterMenu.swift:115](../../LedgeriOS/LedgeriOS/Components/TransactionFilterMenu.swift). Optionally replace with an "invoice status" facet driven by membership — not strictly required for v2. Acceptance: build compiles; the filter menu no longer shows a Billing Status section. Dependencies: none.

**Task 2.5 — Update `ItemDetailView` Billing row.** At [Views/Projects/ItemDetailView.swift:375](../../LedgeriOS/LedgeriOS/Views/Projects/ItemDetailView.swift), replace `liveItem.billingStatus?.displayLabel ?? "—"` with a derivation: look up the first non-voided invoice that references this item id; render that invoice's `status.displayLabel` (or `"Unbilled"` if none). Acceptance: an item on a paid invoice shows "Paid"; an unreferenced item shows "Unbilled". Dependencies: 1.3.

**Task 2.6 — Rewrite the InvoiceDetail mark-paid / void dialogs.** At [Views/Projects/InvoiceDetailView.swift:83-101](../../LedgeriOS/LedgeriOS/Views/Projects/InvoiceDetailView.swift), remove the "All items and expenses on this invoice will be updated to Paid" and "Items and expenses will revert to Unbilled" copy (no cascade happens anymore). Replace with simple confirmations that describe the invoice-only effect. Acceptance: copy reflects the new behavior. Dependencies: 1.6.

**Task 2.7 — Switch per-invoice PDF builder to read stored signed lines.** At [Logic/ReportAggregationCalculations.swift:194-240](../../LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift), the `computeInvoiceReport(for:items:transactions:)` overload currently pushes every line into `chargeLines`. Rewrite to read the invoice's new `lines: [InvoiceLine]?` and sort them into `chargeLines` vs `creditLines` by sign. For v1 invoices (no `lines`), fall back to the existing all-charges logic so historical PDFs still render. Acceptance: a v2 invoice with one credit line renders a Credits section in the PDF and a correct net total. Dependencies: 1.1.

### Phase 3 — TransactionStatus collapse — **SHIPPED 2026-04-21**

Decision on Task 3.1: **keep all three cases** in `TransactionStatus` (`pending`, `completed`, `canceled`) for read-compat with legacy Firestore documents; document `pending` / `completed` as legacy-only. Writers stop producing either, readers stop branching on either. This is what the Migration Strategy already recommends — legacy values become "effectively nil" at every call site, and the enum cases can be dropped once Phase 5.3-equivalent data cleanup runs.

Rationale: reducing to a single case would force a custom `Transaction.init(from:)` to swallow `DecodingError`s on legacy values. Given that no reader checks the legacy values any more, that complexity is unjustified.

Changes:
- `InventoryOperationsService` — all eight `"status": "completed"` writes deleted (sale/return/sell/reassign paths).
- `NewTransactionView` — removed the default `@State status = .completed` and the `transaction.status = status` assignment in the save path.
- `ImportInvoiceModal` — removed `tx.status = .pending`.
- `ReturnTransactionPickerModal` — switched the "in-progress return" predicate from `tx.status != .completed` to `tx.isComplete != true`.
- `EditTransactionDetailsModal` — replaced the Status dropdown with a single "Canceled" toggle; save path writes `status: "canceled"` or `NSNull()` to clear.
- `Enums.swift` — doc comment on `TransactionStatus` flagging `pending` and `completed` as legacy; enum shape unchanged.



**Task 3.1 — Decide the collapsed shape.** Spec leaves the representation "TBD at implementation time" — either `isCanceled: Bool` or a single-case enum. Recommend: keep `TransactionStatus` as an enum with one case (`canceled`) to minimize call-site churn; callers that currently write `.completed` just stop writing that field. Treat nil as "active." This preserves Firestore back-compat for reads. Document the decision inline in `Enums.swift`. Acceptance: decision recorded. Dependencies: none.

**Task 3.2 — Stop writing `status: "completed"`.** Remove the five writes of `"status": "completed"` in [Services/InventoryOperationsService.swift:485,506,692,715, and the non-mixed writers at 151 and 366](../../LedgeriOS/LedgeriOS/Services/InventoryOperationsService.swift). Remove the `@State private var status: TransactionStatus = .completed` default and its write in [Views/Creation/NewTransactionView.swift:54](../../LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift) — new transactions simply don't set a status. Remove the `tx.status = .pending` write in [Modals/ImportInvoiceModal.swift:392](../../LedgeriOS/LedgeriOS/Modals/ImportInvoiceModal.swift). Acceptance: new transactions land with `status == nil`. Dependencies: 3.1.

**Task 3.3 — Rewrite readers of `.pending` / `.completed`.** At [Modals/ReturnTransactionPickerModal.swift:17](../../LedgeriOS/LedgeriOS/Modals/ReturnTransactionPickerModal.swift) the predicate `tx.status != .completed` needs to change — replace with `tx.isComplete != true` (the real "needs review" signal per CLAUDE.md's pattern and [Logic/ReviewCalculations.swift:6](../../LedgeriOS/LedgeriOS/Logic/ReviewCalculations.swift)). At [Modals/EditTransactionDetailsModal.swift:89](../../LedgeriOS/LedgeriOS/Modals/EditTransactionDetailsModal.swift), remove the dropdown that offers all `TransactionStatus.allCases` — the only user-facing transition is "cancel" (and maybe "uncancel"), so render it as a single toggle/button, not a picker. Grep `pendingTransactions` in [Views/Review/ReviewView.swift:15](../../LedgeriOS/LedgeriOS/Views/Review/ReviewView.swift) — that name is a red herring; it already delegates to `ReviewCalculations.pendingTransactions(...)` which reads `isComplete`, not `status`, so no change needed beyond renaming if desired. Acceptance: every reader of `.pending`/`.completed` removed; only `.canceled` comparisons remain. Dependencies: 3.2.

**Task 3.4 — Update `TransactionStatus` enum and legacy aliases.** At [Models/Shared/Enums.swift:69-73](../../LedgeriOS/LedgeriOS/Models/Shared/Enums.swift), reduce to `case canceled` (plus alias `"cancelled" → "canceled"`). Add `"pending" → "canceled"` and `"completed" → "canceled"` only if we want legacy reads to not throw — but a cleaner path is to make the enum tolerant by catching the decoding error and yielding nil. Decide per the axiom-codable skill. Acceptance: reads of existing production documents with `status: "completed"` succeed and land as `nil`. Dependencies: 3.3.

### Phase 4 — Billing subtab pipeline + Reports rework — **SHIPPED 2026-04-21**

- Task 4.1 shipped as a new private `BillingPipelineSection` inside `FinancesTabView`, appended below the existing summary card and Invoice list. Three segments — `To Invoice` / `Invoiced` / `Paid` — driven by `InvoiceLineCalculations.billableMembership`. Rows use the existing `ItemCard` / `TransactionCard` with `NavigationLink(value:)` into the already-registered `Item` / `Transaction` destinations on `ProjectDetailView`.
- Task 4.2 dropped (see note above): Create Invoice button stayed in its current spot.
- Task 4.3 shipped. New pure helper `InvoiceLineCalculations.payableBalance(projectId:items:transactions:invoices:)` returns `PayableBalance { toBusinessCents, toClientCents }`. `AccountingTabView` replaced its raw-sum `owedToCompanyCents` / `owedToClientCents` with this. Labels already read "Payable to Business" / "Payable to Client".
- Task 4.4 (cross-project aggregation) deferred — out of scope for v2; lives in [reports-tab-rework.md](reports-tab-rework.md).



**Task 4.1 — Build the three-tab pipeline UI.** In [Views/Projects/FinancesTabView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/FinancesTabView.swift), below the existing `BillingSummaryCard` and `Invoices` list inside `BillingSubTab` (lines 44-78), insert a new `SegmentedControl` with three segments — `to-invoice`, `invoiced`, `paid` — and three list views driven by `InvoiceLineCalculations.billableMembership(...)`. Each row renders an existing-pattern card: use `ItemCard` / `TransactionCard` as-is. Pattern to follow: the segmented control wiring already in `FinancesTabView` at line 8. Acceptance: the three tabs show correct contents for a seeded project. Dependencies: 1.3, 2.3.

**Task 4.2 — ~~Wire Create Invoice to the To Invoice tab's selection.~~ Dropped 2026-04-21.** The Create Invoice button stays where it is today (project-wide on the Billing subtab). Moving it onto the pipeline's To Invoice segment traded a stable affordance for a context-dependent one, and the picker already scopes to the same pool the segment would show. No action.

**Task 4.3 — Derive the Reports-tab running-balance cards.** Rewrite the `owedToCompanyCents` / `owedToClientCents` computed props in [Views/Projects/AccountingTabView.swift:13-23](../../LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift). Per spec §"Running balance is derived" and [reports-tab-rework.md](reports-tab-rework.md): `owedToBusiness = sum of +lines on sent-but-unpaid invoices for this project + sum of charge-signed unbilled billable activity`. `owedToClient = sum of −lines on sent-but-unpaid invoices + sum of credit-signed unbilled billable activity`. Sign conventions must line up with Task 1.2's classifier. Relabel the cards per [reports-tab-rework.md](reports-tab-rework.md): "Payable to Business" / "Payable to Client" (already correct in the AccountingTabView strings). Acceptance: cards on a project with one paid invoice, one sent invoice, and one unbilled sale show the correct net. Dependencies: 1.2, 1.3.

**Task 4.4 — (Optional) Aggregate running balance across projects for a Reports landing page.** Spec implies the cards are aggregated across projects; current AccountingTabView is project-scoped. If the Reports tab needs a cross-project view, defer to [reports-tab-rework.md](reports-tab-rework.md) — that is a separate in-progress plan and should not block this one. Flag as an open question (§8).

### Phase 5 — Migration + cleanup

Revised 2026-04-21 after senior-review pass. Key changes vs. the original draft:

- Dropped the `effectiveLines` read-compat shim. After the invoice backfill runs, no invoice lacks `lines`; the shim would be dead code the day it ships.
- Flipped the cleanup order: delete the Swift field decls **first** so the compiler surfaces any straggling reader, **then** strip the Firestore field. The compiler is a stronger check than trust in Phase 2 completeness.
- Added an explicit pre-flight Firestore export as a rollback anchor. The `FieldValue.delete()` step is the only irreversible action in this whole project.
- Called out `snapshotName` policy on backfilled lines (leave nil — don't lie about historical names).
- Dropped the "decide fate of `BillingSummaryCalculations`" task — it was decided in Phase 2 (kept, rewritten against invoice membership).
- Added explicit handling for legacy `TransactionStatus` values so they don't become permanent cruft.

**Task 5.1 — Backfill script: synthesize `lines` onto every v1 invoice.** New script at `scripts/migrate-invoices-v2.mjs` (follow the conventions in `migration/` and the pattern referenced by `docs/plans/transaction-type-migration.md`). For each document under `accounts/{id}/invoices/`:

- If `lines` is already present, skip.
- Otherwise, build one `InvoiceLine` per entry in `itemIds` and `transactionIds`, all with `sign: .charge` (v1 had no credits by construction).
- Use the current item/transaction `amountCents` for the line amount.
- **Leave `snapshotName` nil.** Filling it from the *current* item/tx name would misrepresent what the invoice said when it was issued.
- **Do not touch `totalCents`.** The stored net should already equal the sum of the synthesized charges for v1 invoices; if there's drift (rounding, manual edit), trust the stored value.

Must support `--dry-run` printing a per-doc diff without writing. Idempotent: re-running on an already-backfilled doc is a no-op. Acceptance: dry-run on production data reports sensible output; production run is safe to re-execute. Dependencies: 1.1.

**Task 5.2 — Delete `BillingStatus` enum and all Swift field declarations.** Code-only step, runs *before* the Firestore strip. Remove:

- `BillingStatus` enum at [Models/Shared/Enums.swift:75-78](../../LedgeriOS/LedgeriOS/Models/Shared/Enums.swift).
- `billingStatus` field on [Models/Item.swift:58,75](../../LedgeriOS/LedgeriOS/Models/Item.swift) and [Models/Transaction.swift:59,69](../../LedgeriOS/LedgeriOS/Models/Transaction.swift).
- All remaining mentions in `LedgeriOSTests/` (factories, fixtures, tests).

The Swift compiler will flag any reader that Phase 2 missed. If `xcodebuild` is clean, Phase 2 is provably complete. Acceptance: `grep -ri billingStatus LedgeriOS` returns zero hits; build green; tests green. Dependencies: 2.1, 2.2, 2.3, 2.4, 2.5.

**Task 5.3 — Pre-flight Firestore export.** Before running the destructive backfill in 5.4, take a full Firestore export to the existing backup bucket `gs://ledger-nine4-backups` (created 2026-04-20 for the transaction-type migration; 90-day auto-delete lifecycle in [firebase/backup-bucket-lifecycle.json](../../firebase/backup-bucket-lifecycle.json)):

```
gcloud firestore export gs://ledger-nine4-backups/pre-billing-v2-$(date +%Y%m%d-%H%M%S) --project=ledger-nine4
```

Restore path if needed: `gcloud firestore import gs://ledger-nine4-backups/<folder>/ --project=ledger-nine4`. Document the export folder in the migration PR description. Acceptance: export completes; folder name recorded. Dependencies: 5.2.

**Task 5.4 — Backfill script: strip `billingStatus` from items and transactions.** New script at `scripts/strip-billing-status.mjs`. For every `accounts/{id}/items/*` and `accounts/{id}/transactions/*`, issue `FieldValue.delete()` on `billingStatus`. Safe because 5.2 has already proven no Swift reader depends on it. Must support `--dry-run`. Idempotent. Acceptance: post-run Firestore export contains zero `billingStatus` fields. Dependencies: 5.2, 5.3.

**Task 5.5 — Clean up legacy `TransactionStatus` values.** Phase 3 stopped writing `"pending"` / `"completed"` but left legacy values in Firestore and the enum cases in Swift. To avoid indefinite cruft:

- New script `scripts/clear-legacy-transaction-status.mjs`: for every transaction where `status in ("pending", "completed")`, issue `FieldValue.delete()` on `status`. Dry-run flag, idempotent.
- After the script runs clean, delete `pending` and `completed` cases from `TransactionStatus` at [Models/Shared/Enums.swift](../../LedgeriOS/LedgeriOS/Models/Shared/Enums.swift), leaving only `canceled`. Remove the `"complete": "completed"` legacy alias; keep `"cancelled": "canceled"`.

Acceptance: grep for `.pending` / `.completed` across `LedgeriOS/` returns zero hits; test suite green against the reduced enum. Dependencies: 5.4 (share the export).

**Task 5.6 — Update feature docs and spec headers.** Touch `docs/features/` — if an invoicing feature doc exists, update per CLAUDE.md §"Feature Documentation"; if not, create one capturing the pipeline and derivations. Mark the v1 spec [billing-invoicing.md](../specs/billing-invoicing.md) as superseded in its header, pointing at [billing-invoicing-v2.md](../specs/billing-invoicing-v2.md). Update `docs/specs/_index.md`. Dependencies: everything else.

## 6. Migration Strategy

The destructive data changes land last. Between Phase 1 and Phase 5.3 the app dual-lives: new invoices have signed `lines`; old invoices still have `itemIds`/`transactionIds` only; items and transactions still carry `billingStatus` but nothing reads it. Every reader flips in Phase 2, so the stored `billingStatus` field becomes vestigial before it is deleted.

For `TransactionStatus.pending` / `.completed`, Phase 3 stops writing both values and rewires every reader. Phase 3.4 makes the enum tolerant of legacy reads. Phase 5.3 does not touch `transactions.status` — leaving the legacy `"completed"` values in place is safe because no reader checks them; we treat them as "effectively nil." If we want a clean store, a third backfill script can `FieldValue.delete()` non-`canceled` values, but it is not required for correctness.

No feature flag is required. The cutover is safe at every phase boundary because (a) signed lines are additive in Phase 1, (b) readers switch atomically in Phase 2 (PR-by-PR but the app compiles and behaves correctly at each step — the `BillingStatus` fields still exist and still round-trip, they simply go unread), (c) Phase 3 is an isolated enum collapse, (d) Phase 5 is the only destructive step and depends on everything else being green.

Phase 5 runs in this order: backfill invoice `lines` (5.1, additive) → delete Swift `BillingStatus` decls (5.2, compiler validates Phase 2) → Firestore export (5.3, rollback anchor) → strip `billingStatus` from docs (5.4, irreversible) → clean up legacy transaction statuses (5.5) → docs (5.6). The code-before-data ordering means any reader Phase 2 missed is a build failure, not silent data loss.

## 7. Open Questions — Status

**Q1 — Credit amount on auto-generated return credits.** **Decided 2026-04-20: use `projectPriceCents`** (what the client was charged). Matches existing PDF convention.

**Q2 — Non-itemized transactions with no `reimbursementType`.** **Resolved 2026-04-20: case-by-case, no policy rule needed.** Audit of the 1584 Design account ([q2-audit/](q2-audit/)) across all 72 non-itemized transactions in active projects found direction is nearly always inferrable from `purchasedBy`: `client-card` = client already paid (not billable), `design-business` = client owes (charge). Only **1** genuinely ambiguous record (`nvczC9GdYcroxocxoIs3` — Amazon, Witzenman's, $30.84, no `purchasedBy`, no `reimbursementType`). Resolution: tag that one by hand; v2 treats a non-itemized transaction as billable only when its direction is knowable from explicit tag or `purchasedBy`.

**Q2a — MCP filter bug.** During the audit, `list_transactions` with `reimbursementType: 'none'` returned zero hits for every project, but raw data showed many null/missing values. The filter only matches the literal string `"none"`, not null/missing. Worth logging as a separate bug against the MCP server.

**Q3 — Cross-check against [reports-tab-rework.md](reports-tab-rework.md).** **Decided 2026-04-20:** v2 wins on the math (invoice membership + unbilled pool drive the numbers); reports-tab-rework wins on card layout and labels.

**Q4 — Multiple open drafts per project.** **Confirmed 2026-04-20:** multiple drafts allowed; a transaction on one draft is excluded from the others' pickers.

**Q5 — `Transaction.isComplete`.** **Resolved 2026-04-20.** Verified in code: `isComplete` drives the "Needs Review" badge ([ReviewCalculations.swift:6](../../LedgeriOS/LedgeriOS/Logic/ReviewCalculations.swift:6), [TransactionDetailView.swift:717](../../LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift:717), [TransactionCardCalculations.swift:24](../../LedgeriOS/LedgeriOS/Logic/TransactionCardCalculations.swift:24)). MCP agrees — it's server-computed and exposed on every transaction query ([mcp-server/src/tools/transactions.ts:98](../../mcp-server/src/tools/transactions.ts:98)). v2 leaves `isComplete` alone.

A separate vestigial field `Transaction.needsReview: Bool?` exists on both iOS and MCP, but no reader branches on it. Cleanup is out of scope for v2; spun off as a separate task.

**Q6 — MCP tool surface for invoicing.** **Decided 2026-04-20:** on the roadmap at [../backlog/mcp-invoicing-tools.md](../backlog/mcp-invoicing-tools.md); not in scope for v2.
