# Transaction Flow v2 — Unified Flow

> ⚠️ **In-progress design.** Preserves state across sessions. The already-shipped conditional-flow work is tracked in [transaction-flow-conditional.md](transaction-flow-conditional.md) and reflected in [../specs/transaction-creation.md](../specs/transaction-creation.md). The Reports-tab accounting question is split out to [reports-tab-rework.md](reports-tab-rework.md).

## Current Status

**Shipped (build succeeds, not user-tested):**
- `BudgetCategoryType.expense` case added.
- `NewTransactionView` refactored to a step enum.
- Purchase in project context has a Fee/Expense/Itemized filter step before the category picker.
- Fee branch skips vendor step, auto-sets `source = inventoryLabel(for: account.name)`, `purchasedBy = "design-business"`, `reimbursementType = "owed-to-company"`.
- Details step hides Source/Vendor + Classification (Purchased By, Payable) for Fee; Subtotal/Tax Rate stays Itemized-only.

**Needs revision:** the shipped code auto-sets Fee's `reimbursementType` to `"owed-to-company"`. Under the narrow semantic we're adopting (see §Payable below), a Fee is not a reimbursement and should default to `none` like everything else. Revert that one line in `applyFeeImplicitValues()`.

**User feedback after first impl:**
- Flow should be **unified** across project and inventory contexts, not split.
- "Destination" in the current code is actually the vendor field — confusing. Rename to **Vendor**. Reserve "Destination" for project-or-inventory.
- Stay true to the user's handwritten notes: Fee / Expense / Itemized branching, "who paid" gating Itemized destination.

## Proposed v2 Flow (unified, note-faithful)

```
1. Purchase / Sale / Return
2. Fee / Expense / Itemized                                  (category type filter)
3. Who paid?                                                 (skipped for Fee — always business)
4. Destination:
     - Fee:                  Project          (pre-filled from entry context)
     - Expense:              Project          (pre-filled)
     - Itemized + business:  Inventory        (automatic, skip step)
     - Itemized + client:    Project          (pre-filled)
5. Budget Category (filtered by type)
6. Vendor                                                     (skipped for Fee)
7. Details — date, amount, notes, email
              + Tax Rate + Subtotal (Itemized only)
              + "Does this need to be reimbursed?" toggle (Expense only — see §Payable)
```

**Naming fix:** rename the current "Destination" step in the code to **Vendor**. Reserve "Destination" for the project-or-inventory picker in step 4.

**Entry context effect:** just sets the default for step 4. Inventory tab → Destination defaults to Business Inventory. Project tab → Destination defaults to that project. Either is editable.

**Sale and Return flows:** unchanged from today (Type → Vendor → Category → Details).

## Payable — Narrow Semantic with Toggle

**Decision:** `reimbursementType` keeps its historical narrow meaning — "this transaction requires a reimbursement handoff between the business and the client." It is not a ledger-side marker. Most transactions should have it set to `none` / nil.

**Why:** one field cannot cleanly express both "needs reimbursement" and "which side of the ledger" without forcing every transaction to classify itself. The narrow meaning matches the user's mental model and the original field intent. The ledger-side question is the Reports tab's problem, solved separately.

**Derivation vs. user input:**

| Category type | Who paid | Reimbursement | How it's set |
|---|---|---|---|
| Fee | business (implicit) | `none` | Auto. A fee is not a reimbursement. |
| Expense | business or client | `none` OR `owed-to-{client,company}` | **Toggle** — see below. Direction inferred from who paid. |
| Itemized | business | `none` | Auto. Items go to inventory. |
| Itemized | client | `none` | Auto. Client paid for their own items. |

**The toggle** appears only on the Expense flow's Details step, under a question like **"Does this need to be reimbursed?"** Default off.

- Toggle off → `reimbursementType = "none"`.
- Toggle on + client paid → `"owed-to-client"` (business owes client).
- Toggle on + business paid → `"owed-to-company"` (client owes business).

No three-way Payable dropdown. No classifying every transaction. Fees and Itemized transactions never ask the question.

**Consequences for existing downstream code:**

- [AccountingTabView.swift:14-24](../../LedgeriOS/LedgeriOS/Views/Projects/AccountingTabView.swift:14) — the Reports-tab "Payable to Business / Client" totals will only count explicit reimbursements going forward. They will not be a complete client-balance view. That's acknowledged and addressed in [reports-tab-rework.md](reports-tab-rework.md).
- [ReportAggregationCalculations.swift:82-102](../../LedgeriOS/LedgeriOS/Logic/ReportAggregationCalculations.swift:82) — invoice charge/credit lines still work. Fees are separately excluded via category type (line 111-122), so the narrow-semantic Fee=`none` doesn't change invoicing.
- [Transaction filter menu, CSV export, MCP filters] — still functional. Users filtering by "owed-to-client" etc. just get the reimbursement set.

## Open Items Before Implementing v2

1. **Exact toggle copy.** "Does this need to be reimbursed?" is a working label. Better wording welcome.
2. **Edit flow.** [EditTransactionDetailsModal.swift:104-108](../../LedgeriOS/LedgeriOS/Modals/EditTransactionDetailsModal.swift:104) still exposes the 3-value Payable dropdown. Under the new model, edit should match the toggle pattern (or remain a dropdown for power users / legacy data — decide).
3. **Historical data.** Existing transactions may have `reimbursementType` values written under either the narrow or the broad interpretation. No migration proposed — accept that historical data is what it is, forward behavior is consistent.
4. **Destination step UX.** When is the Destination step *shown* vs. auto-skipped? Spec says skipped for Itemized+business (auto → Inventory). Is it shown or skipped for Fee and Expense when the user entered from a project (already pre-filled)? Proposal: always shown so the user can change it, pre-filled so the default path is one tap.

## Implementation Sketch (once approved)

1. Revert the `reimbursementType = "owed-to-company"` line in `applyFeeImplicitValues()`. Let Fee default to `none`.
2. Add `destination: ProjectOrInventory` state (separate from the current `destination` vendor variable — rename that to `vendor` for clarity).
3. Insert "Who paid?" step between Category Type filter and Destination.
4. Insert Destination step (project picker with Business Inventory as an option). Skip for Itemized+business.
5. Adjust Details step: remove 3-value Payable dropdown, replace with the toggle shown only on Expense.
6. Update [transaction-creation.md](../specs/transaction-creation.md) to match.
