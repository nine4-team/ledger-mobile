# Transaction Creation Flow

> ⚠️ **Draft — v2 unified flow.** This spec describes the redesigned "New Transaction" sheet for Purchase in a project context, with conditional steps driven by the picked budget category's type (Fee / Expense / Itemized). Sale and Return flows are unchanged. Inventory-context Purchase uses a simpler fallback flow.

## Purpose

Guide users through creating a new transaction, showing only fields relevant to the kind of transaction being made. Fees and Expenses hide fields that exist only to support Itemized purchases (tax rate, item routing). Fees additionally hide the vendor step and the "Who paid?" question because the counterparty and payer are implicitly the design business.

Reimbursement is treated as a narrow concept — asked about only in the Expense flow and only via a single toggle (see §Payable Semantics).

For photo-first physical item capture, use [proto-item-capture.md](proto-item-capture.md). Transaction creation remains the financial evidence flow; proto items are physical evidence that can be linked or merged later.

## Entry Points

- **Project context** — opened from a project's transactions/finances tab. Transaction is pre-scoped to that project (`projectId` set as the default).
- **Inventory context** — opened from the inventory tab. No `projectId`; transaction defaults to the account-level Business Inventory.

The entry context is passed in as `TransactionCreationContext` (`.project(id)` or `.inventory`).

## Budget Category Type

Every budget category has a `metadata.categoryType` of `.fee`, `.expense`, `.itemized`, or legacy `.general`. The type is defined once on the category and drives conditional behavior in the Purchase flow. It is **not** persisted on the transaction — the chosen `budgetCategoryId` carries all downstream classification.

| Type | Semantics |
|---|---|
| `fee` | Money owed to the design business itself (design fee, deposit, management fee). Counterparty is implicitly the business. |
| `expense` | Non-itemized project expense paid to a third party (delivery, storage, fuel). No line items, no tax breakdown. |
| `itemized` | Purchase of physical items that flow through the inventory/item model. Supports tax-rate entry and item routing. |
| `general` | Legacy. Treated like `expense` for flow purposes. |

## Steps — Purchase

Unified flow, same shape regardless of entry point. Entry context only sets defaults. Sheet uses `MultiStepFormSheet`; step count varies by branch.

1. **Type** — Purchase / Sale / Return.
2. **Category Type** — Fee / Expense / Itemized. UI filter; not persisted on the transaction.
3. **Who paid?** *(skipped for Fee — implicitly the business)*. Design Business or Client.
4. **Destination** *(skipped for Itemized + business-paid, which auto-routes to Inventory)*. Project picker, pre-filled with the entry project. Currently shows only active projects; Business Inventory is not a user-visible option in this picker.
5. **Budget Category** — filtered to categories whose `metadata.categoryType` matches the Step-2 pick. Legacy `.general` categories surface under the Expense filter. A "No Category" option is not offered — a category is required.
6. **Vendor** *(skipped for Fee)*. The counterparty / source-of-purchase. For Fee, `source` is set automatically to `InventoryOperationsService.inventoryLabel(for: account.name)`.
7. **Details** — see §Details.

### Implicit values for Fee

When the user picks Fee on Step 2:

- `purchasedBy = "design-business"`
- `source = inventoryLabel(for: account.name)`
- The vendor state is cleared and the Vendor step is skipped.

### Entry-context defaults

| Entered from | `selectedDestination` default | User impact |
|---|---|---|
| A project's Transactions tab | `.project(currentProjectId)` | Destination step pre-filled to that project — usually a one-tap confirm. |
| Inventory tab or floating "+" | `.inventory` | Destination step starts without a project selected. User must pick one unless the flow is Itemized+business (auto-skips Destination, routes to Inventory). |

## Steps — Sale, Return

Unchanged from the pre-v2 behavior (no redesign in scope):

- **Sale / Return (project):** Type → Vendor → Budget Category → Details.
- **Sale / Return (inventory):** Type → Vendor → Details.

The Budget Category step is shown when a project is associated with the transaction (from the entry context for Sale/Return — there is no Destination picker on those flows).

## Details

Field visibility at the Details step is driven by **the picked transaction type**, not the category. Categories can mix types (see [transaction-type.md](transaction-type.md)), so category-shape is not a reliable gate.

| Section / Field | Fee | Expense | Purchase | Return |
|---|---|---|---|---|
| Source/Vendor (pre-filled from Step 6) | hidden (auto-set) | shown | shown | shown |
| Date | shown | shown | shown | shown |
| Amount | shown | shown | shown | shown |
| Purchased By | hidden (asked at Step 3) | hidden (asked at Step 3) | hidden (asked at Step 3) | n/a (implicit business) |
| "Does this need to be reimbursed?" toggle | hidden | shown (default No) | hidden | hidden |
| Subtotal + Tax Rate | hidden | hidden | shown | shown |
| Notes | shown | shown | shown | shown |
| Email Receipt | shown | shown | shown | shown |

**Purchase + business buying straight to inventory** (entered from inventory tab or floating "+", destination auto-routes to Inventory, no category picked): follow the **Purchase** column. Purchased By was set on the Who-Paid step; no reimbursement toggle.

Submit button: **Create Transaction**, gated by `TransactionFormValidation.isTransactionReadyToSubmit`.

## Payable Semantics

`Transaction.reimbursementType` (UI concept "Payable") is treated as a **narrow reimbursement flag** — "does this transaction require a reimbursement handoff between the business and the client?" Most transactions leave it as `nil` / `"none"`.

| Transaction type | Who paid | Reimbursement toggle | Resulting `reimbursementType` |
|---|---|---|---|
| Fee | business (implicit) | — | `nil` |
| Expense | business | off | `nil` |
| Expense | business | on | `"owed-to-company"` |
| Expense | client | off | `nil` |
| Expense | client | on | `"owed-to-client"` |
| Purchase / Return / Sale | business or client | — | `nil` |

The toggle appears only on the Expense Details section; direction is inferred from Who paid.

**The 3-value Payable dropdown has been removed from the create flow.** The Edit flow ([EditTransactionDetailsModal.swift](../../LedgeriOS/LedgeriOS/Modals/EditTransactionDetailsModal.swift)) still exposes it for backward compatibility with existing data; that modal's UX is a separate rework.

**Downstream consumers of `reimbursementType`** — invoice report ([ReportAggregationCalculations.swift](../../LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift)) and the Finances → Reports sub-tab totals ([AccountingTabView.swift](../../LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift)) continue to read this field. Under the narrow semantic, the Reports cards become reimbursement-specific rather than full ledger positions. Reworking that display is tracked separately in [../plans/reports-tab-rework.md](../plans/reports-tab-rework.md).

## Routing After Creation

After the transaction is written via `TransactionsService.createTransaction`:

| Category type | Purchased By | Behavior |
|---|---|---|
| Itemized | `design-business` | `projectId` is cleared, transaction is created at the account level, then `ItemEntryFlowView` is presented for adding items and optionally selling to a project. See [item-entry-flow.md](item-entry-flow.md). |
| Itemized | `client-card` | Transaction stays on the destination project; sheet dismisses. |
| Fee / Expense / General | Any | Transaction stays on the destination project; sheet dismisses. No item-entry handoff. |

The "route through inventory" decision is computed as `isItemizedCategory && purchasedBy == "design-business"`.

## Field Mapping

| Form field | Transaction model field |
|---|---|
| Type | `transactionType` |
| Vendor (or Fee auto-set) | `source` |
| Date | `transactionDate` (ISO-8601 full date) |
| Amount | `amountCents` |
| Who paid | `purchasedBy` |
| Reimbursement toggle + Who paid | `reimbursementType` (see §Payable Semantics) |
| Notes | `notes` (trimmed; empty → `nil`) |
| Email Receipt | `hasEmailReceipt` |
| Budget Category | `budgetCategoryId` |
| Subtotal *(itemized)* | `subtotalCents` |
| Tax Rate *(itemized)* | `taxRatePct` |
| Destination → project | `projectId` (cleared if routing through inventory) |

## Open Questions / Planned Revisions

- **`.general` migration.** Existing categories default to `.general`. Keep the case indefinitely, or migrate all `.general` → `.expense`? Decision deferred until post-launch data review.
- **Vendor scoping by category type.** The design notes envision vendor lists scoped per type (Fee vendors vs. Expense vendors). `VendorDefaults` is currently a flat `[String]` per account with no type field — scoping requires a model + UI change. Deferred.
- **"Exclude from overall budget" toggle.** Per-category toggle to exclude a category from the project's overall budget rollup. Separate spec.
- **Edit modal.** [EditTransactionDetailsModal.swift](../../LedgeriOS/LedgeriOS/Modals/EditTransactionDetailsModal.swift) still uses the 3-value Payable dropdown. Should be reworked to match the toggle pattern or left as a power-user escape hatch — undecided.

## Related Specs

- [item-entry-flow.md](item-entry-flow.md) — post-creation item entry and sell-to-project flow
- [proto-item-capture.md](proto-item-capture.md) — persistent photo-first item intake and later resolution
- [transaction-completeness.md](transaction-completeness.md) — required fields / completeness rules
- [transaction-audit.md](transaction-audit.md) — audit trail
