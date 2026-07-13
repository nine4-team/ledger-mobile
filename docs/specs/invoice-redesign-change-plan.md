# Invoice Redesign Change Plan

> Status: working implementation and UX companion to `invoice-transaction-redesign-draft.md`.
> This document records app changes, research tasks, and UI decisions needed to implement the target model. It is not the domain spec.

## Purpose

The redesign spec defines the target invoice model. This change plan tracks how the current app has to move toward that model without mixing implementation chores into the model itself.

Definitions for invoice, receivable, candidate receivable, fee installment, expense transaction, settlement transaction, payment correction, and related fields live in [invoice-transaction-redesign-draft.md](invoice-transaction-redesign-draft.md#definitions). This change plan should use those meanings.

Core product direction:

- One project invoicing page with two primary sections:
  - candidate receivables: things that can be invoiced
  - invoices: things that have been invoiced
- Candidate receivables are a UI role, not a persisted generic `Receivable` object.
- Invoice lines attach existing source records to invoices and stay live until paid.
- Paid invoices create/link financial transaction records.
- Transaction records remain about financial activity and money movement.

## Transaction Research

The redesign should not require a wholesale transaction model redesign. It does require research around transaction cancellation/correction support.

Findings from current code/specs:

- `Transaction.status` already exists.
- `TransactionStatus` has one canonical stored value: `canceled`; `nil` means active.
- `docs/specs/data-model.md` says canceled transactions preserve accounting fields and contribute $0 to budget calculations.
- Firestore rules allow transaction `status` updates, including on inventory movement transactions whose accounting fields are otherwise immutable.
- Invoice settlement/payment transactions already link back to invoices with `settlementInvoiceId` and `settlementInvoiceLineIds`.
- `InvoiceService.markCollected` already creates `paymentToBusiness` transactions grouped by invoice line budget category.

Decision: invoice payment correction should reuse the existing transaction cancellation convention. No new transaction status enum is needed.

Implementation requirement:

- Add an invoice payment-correction operation that finds generated settlement/payment transactions for the invoice and sets `status = "canceled"` without deleting them.
- Keep `settlementInvoiceId` and `settlementInvoiceLineIds` intact on canceled settlement transactions so the correction remains traceable.
- Write a `paymentCanceled` invoice event listing the canceled transaction IDs.

Known code paths that must be audited/fixed:

- `BillingSummaryCalculations` currently groups settlement transactions without excluding `status == .canceled`; canceled invoice payments could still count as collected until this is fixed.
- `InvoiceLineCalculations.payableBalance` subtracts settlement transactions by `settlementInvoiceId` and should exclude canceled settlement transactions.
- Transaction list/card surfaces already display canceled transactions, but invoice-generated payment rows may need clearer language.

Expected target behavior:

- `markInvoicePaid` creates/link settlement/payment transactions and marks invoice `paid`.
- `voidInvoicePayment` cancels generated settlement/payment transactions, restores invoice to its pre-paid status, and writes a `paymentCanceled` invoice event.
- Reversal transactions are reserved for real money-out workflows such as refunds.

## Current UI Reality

Current primary surfaces:

- `FinancesTabView`
  - shows `BillingSummaryCard`
  - shows an `Invoices` list
  - shows a `Candidate Receivables` section above the invoice list
  - groups fee installments by fee category with Total / Invoiced / Received / To Invoice tracking
- `CreateInvoiceModal`
  - selects fee installments, items, and transactions in a modal
  - no longer exposes manual New Charge lines
  - splits transactions into charges and credits
- `InvoiceDetailView`
  - shows invoice report preview
  - exposes lifecycle actions in a menu
  - keeps created/sent invoice amounts live and locks the paid snapshot at collection
- `InvoiceReportView` / `ReportHTMLBuilder`
  - render invoice presentation and PDF output

This means the redesign is larger than renaming statuses. The Billing page now has the target two-section shape, but the create/edit flow still uses a modal picker rather than direct multi-select from the candidate section.

Current implementation constraints:

- Fee installment creation is available from fee groups, but fee installment defaulting/scheduling is not designed yet.
- Current membership logic treats `created` invoices as a claimed bucket and sent invoices as sent/receivable.
- Current candidate item logic uses the source-aware billable resolver; future work should keep Create Invoice and Candidate Receivables on the same resolver path.
- Current transaction candidate logic already excludes canceled/payment/settlement transactions and requires a reimbursement direction.
- Current `CreateInvoiceModal` no longer creates manual New Charge invoice lines. Manual `InvoiceLine` remains as an internal representation for returned paid item credits.
- Current invoice rows and detail/report paths use live totals for `created` and `sent`; paid invoices use the paid-boundary snapshot.

## Target Invoicing Page UX

The page should be organized around two stacked sections.

UX direction:

- Keep the page clean, dense, and list-like, consistent with Ledger's existing project screens.
- Use existing visual patterns: section labels, `SearchField`, icon-only filter/sort controls, `ActionMenuSheet` filter menus, `GroupedItemCard`-style expandable group cards, single-column stacked rows, and budget-style progress bars.
- Avoid card-heavy nesting. Use cards only for individual rows or empty states when the existing app pattern calls for them.
- Favor rows and sections over a large wizard/modal as the primary invoicing experience.
- Keep labels concrete and financial: do not use vague labels like "configured" or ambiguous labels like "remaining" without specifying what remains.

### Candidate Receivables

Top section: records that can be added to an invoice or are already attached to an active invoice.

Candidate source groups:

- fee installments
- reimbursable expense transactions
- eligible items

Primary filters:

- availability:
  - available
  - on created invoice
  - on sent invoice
  - paid
  - all
- source type:
  - all
  - fees
  - expenses
  - items
- search:
  - source name / display name
  - client-facing description if present
  - category/vendor where available

The availability filter is important because designers need to see both what has not been added to an invoice and what already has been added.

Candidate rows should clearly show:

- source type
- source display name
- client-facing invoice description when customized
- derived invoice amount
- invoice membership state
- linked invoice name/number when already attached
- reason when a record is visible but not selectable

### Fee UX

Fees should appear as fee groups based on enabled project fee budget categories.

Within each fee group:

- show existing fee installments
- allow adding a fee installment with label and amount
- show `Total`, `Invoiced`, `Received`, and `To Invoice`
- reuse budget-tracking visual language with a dual-tone progress bar, labeled as invoicing progress rather than spend
- block creating/editing installments beyond the configured fee amount

The row being invoiced is the `FeeInstallment`, not the whole fee category. The group is the fee category context.

Fee group metric definitions:

- `Total`: full fee amount for this project fee category.
- `Invoiced`: fee installment amount attached to non-canceled invoices.
- `Received`: fee installment amount collected on paid invoices / settlement transactions.
- `To Invoice`: fee amount not yet attached to a non-canceled invoice; calculated as `Total - Invoiced`.

Fee groups should be collapsible/expandable. Default expanded when there are available installments, money left to invoice, a Fees-only filter is active, or the group needs attention. Default collapsed or visually compact when the group is fully invoiced/paid and the user is viewing a broader candidate list.

Fee group visual reference:

- Use `GroupedItemCard` as the main interaction/container precedent: grouped card, collapsed summary, count/total badge area, chevron, and expanded child rows.
- Adapt the collapsed summary for fees: fee name, `Total` / `Invoiced` / `Received` / `To Invoice`, and a dual-tone invoicing progress bar.
- Use the Budget tab only as the progress-bar/money-summary precedent, not as the grouped-object container precedent.
- Expanded content should be stacked fee installment rows, not nested cards.

Fee progress bar:

- Base semantic color should be in the brand-gold family.
- Show `Invoiced` and `Received` as two tones.
- `Received` must be visually distinct from, and contained within, `Invoiced` because received amount cannot exceed invoiced amount under the target model.
- `To Invoice` is the unfilled remainder of `Total`.
- Avoid spend/budget language in labels or accessibility copy.

Add/edit fee installment interaction:

- Use a small `FormSheet` for adding or editing a fee installment.
- Trigger it from the fee group add button.
- Fields: label, amount.
- The sheet title should name the fee group, for example `Add Design Fee Installment`.
- Keep validation immediate and plain: block amounts that push the fee group over its `Total`.
- Do not use a large invoice-creation wizard for this. Adding a fee installment is a small source-record edit, not invoice creation.

Rationale: inline editing would be fast on desktop but can make the fee group visually busy and cramped on mobile. A small sheet matches existing app create/edit patterns and keeps the main invoicing page uncluttered.

Recommended storage:

```text
accounts/{accountId}/projects/{projectId}/feeInstallments/{feeInstallmentId}
```

Rationale:

- fee installments are project-scoped
- the configured fee amount already lives in `accounts/{accountId}/projects/{projectId}/budgetCategories/{categoryId}`
- the invoice page already operates inside a project context
- keeping installments under the project avoids making them look like account-wide financial events

Implementation requirements:

- Add `InvoiceLineSourceType.feeInstallment`.
- Add a project-scoped `FeeInstallmentsService`.
- Project context or the invoice page must subscribe to fee installments for the current project.
- Fee installments must feed invoice visibility metadata: fee lines should set/derive `containsCompanyRevenue = true` and include their `budgetCategoryId` in `feeCategoryIds`.
- Create/edit must enforce total installments for a fee category <= `ProjectBudgetCategory.budgetCents` when `budgetCents` is configured.

### Invoice List

Bottom section: invoices that exist for the project.

Invoice rows should show:

- invoice name/number
- status: `created`, `sent`, `paid`, `canceled`
- derived/live total for `created` and `sent`
- paid-boundary snapshot total for `paid`
- created/sent/paid/canceled date as relevant
- visible paid/unpaid affordance

Toggling paid/unpaid cannot be a raw boolean flip. The UI can feel simple, but the action must call the correct operation:

- mark paid: creates/link settlement/payment transactions
- correct mistaken payment: cancels generated settlement/payment transactions and restores pre-paid status

Canceled invoices should visually recede and release their source records back to the available pool.

## Create/Edit Flow Changes

Current `CreateInvoiceModal` should not remain the main invoice creation experience in its current form.

Needed changes:

- Directly connect candidate-row selection to invoice creation/editing so the top section becomes the primary workflow.
- Replace item/transaction picker logic with the shared candidate resolver.
- Support custom client-facing descriptions per invoice line.
- Keep line amounts live for `created` and `sent`.
- Move the user experience toward selecting candidates from the top section and creating/updating the invoice from that selection.

Possible interaction model:

1. User filters/scans candidate receivables.
2. User selects available candidate rows.
3. User creates invoice from selection.
4. Invoice appears in bottom section as `created`.
5. Candidate rows now show they are on that created invoice.
6. User can mark sent, mark paid, cancel, or edit the created/sent invoice.

## Code Surfaces Likely To Change

Model/services:

- `Invoice`
- `InvoiceLine`
- `InvoiceStatus`
- `InvoiceService`
- `InvoiceServiceProtocol`
- new `FeeInstallment` model/service/repository path
- new `InvoiceEvent` model/service or event-writing support
- `Transaction` may not need new core status fields; invoice payment correction should use existing `status == .canceled`

Calculations:

- replace or heavily revise `InvoiceLineCalculations.billableMembership`
- add shared candidate resolver for fees, expenses, and items
- update `BillingSummaryCalculations`
- update `ReportAggregationCalculations.computeInvoiceReport`
- update invoice membership helpers used by item/transaction cards
- apply financial-access policy before building invoice candidate rows and invoice rows

UI:

- redesign `FinancesTabView` billing section around candidate pool + invoice list
- `BillingPipelineSection` has been removed in favor of candidate receivables
- revise `CreateInvoiceModal` until candidate section selection can fully replace the modal picker
- update `InvoiceDetailView` lifecycle actions and edit rules
- update `InvoiceRow`
- update `BillingSummaryCard` labels/definitions
- update `ItemCard`, `TransactionCard`, item detail, and transaction detail billing badges as needed

Access control:

- Employees who cannot see a fee category must not see that fee category in the invoice page.
- Hidden fee categories must be excluded from:
  - fee groups
  - fee installments
  - candidate receivables
  - invoice rows containing hidden fee lines
  - invoice totals/summaries where showing the invoice would reveal hidden fee revenue
- Fee installments must feed invoice visibility metadata: `containsCompanyRevenue` and `feeCategoryIds`.
- Access filtering should happen before rows/totals are rendered, not only by hiding labels inside visible rows.

Reports/export:

- update `InvoiceReportView`
- update `ReportHTMLBuilder.invoice`
- ensure paid invoices render from paid-boundary snapshot
- ensure created/sent invoices render from live source values

## Implementation Order Candidate

1. Fix/read-audit settlement calculations so canceled settlement transactions do not count as collected.
2. Add invoice event storage and payment-correction operation using `Transaction.status == "canceled"`.
3. Add `FeeInstallment` model/service/repository path and fee-budget enforcement.
4. Build shared invoice candidate resolver.
5. Update invoice model/status/events/paid snapshot.
6. Rework billing page candidate pool and invoice list.
7. Replace modal picker behavior with candidate-driven create/edit flow.
8. Update invoice detail, report rendering, billing summary, access metadata, and badges.
9. Design migration from current invoice/manual-line data.

## Things Not Yet Fully Designed

- Exact invoice event storage fields.
- Exact top-section row layout details.
- Exact filter menu option grouping and default selections.
- Migration from existing manual New Charge invoice lines.
- Refund workflow after real money is returned to the client.

## Invoice Page Layout Recommendation

Use the current `FinancesTabView` billing tab as the placement, but replace the old `Invoices` + `BillingPipelineSection` split with a single invoicing workspace:

1. Billing summary, if retained, stays compact at the top.
2. Candidate receivables section comes next.
3. Invoice list section comes below it.

Candidate receivables controls:

- Search field for source/client-facing text.
- Icon filter button using an `ActionMenuSheet`.
- A compact source-type segmented control only if it remains visually calm; otherwise source type should live in the filter menu.
- Avoid stacking multiple segmented controls as the primary design. The current Billing Pipeline does this, and it will get noisy with availability + source type + search.

Recommended filter menu groups:

- Availability: available, on created invoice, sent, paid, all.
- Source type: fees, expenses, items, all.
- Fee category: visible fee categories only.

Candidate row rhythm:

- One row per invoiceable source.
- Left: selection control when available.
- Main: source display name and optional client-facing description.
- Secondary: type/category/vendor and invoice membership state.
- Right: derived amount and linked invoice status/name when applicable.

Fee group rhythm:

- Use a `GroupedItemCard`-style expandable group card.
- Header shows fee name plus compact metrics: `Total`, `Invoiced`, `Received`, `To Invoice`.
- Use a dual-tone budget-style progress bar for invoicing progress, not spend.
- Rows inside the group are fee installments.

Invoice list rhythm:

- One row per invoice.
- Show invoice name/number, status, important date, total, and a paid/unpaid affordance.
- Canceled invoices should visually recede but remain findable.

## Invoice Event Storage Recommendation

Use an append-only account-level collection, mirroring `lineageEdges`:

```text
accounts/{accountId}/invoiceEvents/{eventId}
```

Candidate shape:

```swift
struct InvoiceEvent {
    var id: String?
    var accountId: String
    var projectId: String
    var invoiceId: String
    var kind: InvoiceEventKind
    var fromStatus: InvoiceStatus?
    var toStatus: InvoiceStatus?
    var settlementTransactionIds: [String]?
    var source: String? // app | migration | server
    var note: String?
    var createdBy: String?
    var createdAt: Date?
}
```

Candidate event kinds:

- `created`
- `sent`
- `paid`
- `paymentCanceled`
- `canceled`

Rules recommendation:

- account members can read events
- app/server can create events
- events cannot be updated or deleted

The invoice document should still store current status and convenience timestamps. Events are for history, correction audit, and debugging.
