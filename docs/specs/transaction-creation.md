# Transaction Creation Flow

> ⚠️ **Draft — to be revised.** This spec captures the current implementation of the multi-step "New Transaction" sheet so behavior can be reasoned about and refined. Expect changes as the flow evolves (e.g., explicit inventory-vs-project confirmation, simplification of step ordering).

## Purpose

Guide users through creating a new transaction in either a project or inventory context, collecting just enough information up front to classify and route it, then handing off to follow-up flows (item entry, sale-to-project) when appropriate.

## Entry Points

- **Project context** — opened from a project's transactions/finances tab. Transaction is scoped to that project (`projectId` set).
- **Inventory context** — opened from the inventory tab. No `projectId`; transaction lives at the account level.

The entry context is passed in as `TransactionCreationContext` (`.project(id)` or `.inventory`).

## Steps

The sheet is a `MultiStepFormSheet`. Number of steps depends on context:

- **Project context:** 4 steps (Type → Destination → Budget Category → Details)
- **Inventory context:** 3 steps (Type → Destination → Details — no category step)

### Step 1 — Transaction Type
User picks one of:
- **Purchase**
- **Sale**
- **Return**

The choice changes the wording of subsequent prompts (e.g., "Where was this purchased?" vs. "Who was this sold to?") but not the step structure.

### Step 2 — Destination / Vendor
Inline vendor picker. User selects a known vendor or enters a new one ("Other" mode). Required to advance.

### Step 3 — Budget Category *(project context only)*
Inline picker over the project's enabled, non-archived budget categories (sorted by `order`), plus a "No Category" option. Selection is optional but determines whether the Details step shows itemized fields and whether routing through inventory applies.

### Step 4 (or 3 in inventory) — Details
Three sections:

1. **Transaction Info** — source/vendor (pre-filled from Step 2), date, amount.
2. **Classification** — Purchased By (`client-card` | `design-business`), Reimbursement (`none` | `owed-to-client` | `owed-to-company`).
3. **Additional Details** — notes, email-receipt toggle. If the selected category is **itemized**, also shows Subtotal and Tax Rate fields.

Submit button: **Create Transaction**, gated by `TransactionFormValidation.isTransactionReadyToSubmit`.

## Routing After Creation

After the transaction is written via `TransactionsService.createTransaction`:

| Category type | Purchased By | Behavior |
|---|---|---|
| Itemized | `design-business` | `projectId` is cleared, transaction is created at the account level, then `ItemEntryFlowView` is presented for adding items and optionally selling to a project. See [item-entry-flow.md](item-entry-flow.md). |
| Itemized | `client-card` | Transaction stays on the project; sheet dismisses. |
| Non-itemized / no category | Any | Transaction stays on the project (or inventory); sheet dismisses. |

The "route through inventory" decision is computed as `isItemizedCategory && purchasedBy == "design-business"`.

## Field Mapping

| Form field | Transaction model field |
|---|---|
| Type | `transactionType` |
| Destination / Source | `source` |
| Date | `transactionDate` (ISO-8601 full date) |
| Amount | `amountCents` |
| Purchased By | `purchasedBy` |
| Reimbursement | `reimbursementType` (`none` → `nil`) |
| Notes | `notes` (trimmed; empty → `nil`) |
| Email Receipt | `hasEmailReceipt` |
| Budget Category | `budgetCategoryId` |
| Subtotal *(itemized)* | `subtotalCents` |
| Tax Rate *(itemized)* | `taxRatePct` |
| Project context | `projectId` (cleared if routing through inventory) |

## Open Questions / Planned Revisions

- **Explicit inventory confirmation.** User feedback envisioned a visible "is this inventory or going right into a project?" choice at the end of creation. The current flow routes silently based on `purchasedBy`. Worth surfacing as a confirmation message or step.
- **Step ordering.** Whether Budget Category should come before Destination, or move into the Details step as an inline field, is unresolved.
- **Inventory context + itemized.** Inventory transactions skip the category step entirely, so itemized routing is implicitly skipped. If inventory transactions ever need item entry, this needs revisiting.

## Related Specs

- [item-entry-flow.md](item-entry-flow.md) — post-creation item entry and sell-to-project flow
- [transaction-completeness.md](transaction-completeness.md) — required fields / completeness rules
- [transaction-audit.md](transaction-audit.md) — audit trail
