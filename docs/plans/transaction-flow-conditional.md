# Implementation Plan — Conditional New-Transaction Flow

**Spec:** [docs/specs/transaction-creation.md](../specs/transaction-creation.md)
**Scope:** Redesign the Purchase branch of the New Transaction sheet so visible fields are driven by the picked budget category's type. Sale and Return flows untouched.

## Goal

Cut the number of fields a user sees when creating a purchase by picking a category-type filter (Fee / Expense / Itemized) before the category list, then hiding fields that don't apply:

- **Fee** — skip vendor step; hide Purchased By, Payable, Subtotal, Tax Rate.
- **Expense / General** — hide Subtotal, Tax Rate.
- **Itemized** — unchanged from today.

## Out of Scope

- Sale / Return flows.
- Vendor scoping by category type (tracked as Open Question in spec).
- "Exclude from overall budget" per-category toggle.
- Migrating legacy `.general` categories to `.expense`.

## Task Breakdown

### Task 0 — Refactor step management to an enum *(do first)*

**Why:** The current code stores the step as `@State private var currentStep = 1` and branches on `switch currentStep { case 1… case 2… case 3… }` ([NewTransactionView.swift:20, 88](../../LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift)). Inserting a new step in the middle shifts every downstream number. Numeric comparisons like `if currentStep == 2 || !destination.isEmpty` (line 100) also silently change meaning. Fix the representation before adding the new step — not at the same time.

**File:** [LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift](../../LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift)

**Introduce a step enum** covering every logical screen the sheet can show. Keep the naming logical, not ordinal:

```swift
enum TransactionCreationStep: Hashable {
    case typeSelection        // Purchase / Sale / Return
    case categoryTypeFilter   // Fee / Expense / Itemized  (added in Task 2, declared here so the enum is stable)
    case budgetCategory       // pick a BudgetCategory
    case destination          // vendor picker
    case details              // full detail form
}
```

**State:**
- Replace `@State private var currentStep = 1` with `@State private var currentStep: TransactionCreationStep = .typeSelection`.

**Step ordering:**

Add a single helper that returns the ordered list of steps for the current branch. This is the one place that encodes the flow:

```swift
private var orderedSteps: [TransactionCreationStep] {
    switch (transactionType, hasCategories) {
    case (.purchase, true):
        // Task 2 will insert .categoryTypeFilter and conditionally drop .destination for Fee.
        // Pre-Task-2 form matches today's flow:
        return [.typeSelection, .destination, .budgetCategory, .details]
    case (.purchase, false),
         (.sale, false),
         (.return, false):
        return [.typeSelection, .destination, .details]
    case (.sale, true), (.return, true):
        return [.typeSelection, .destination, .budgetCategory, .details]
    case (nil, _):
        return [.typeSelection]
    }
}

private var currentStepIndex: Int {
    (orderedSteps.firstIndex(of: currentStep) ?? 0) + 1  // 1-based for display
}

private var totalSteps: Int { orderedSteps.count }

private func advance() {
    guard let i = orderedSteps.firstIndex(of: currentStep),
          i + 1 < orderedSteps.count else { return }
    currentStep = orderedSteps[i + 1]
}

private func goBack() {
    guard let i = orderedSteps.firstIndex(of: currentStep),
          i > 0 else { return }
    currentStep = orderedSteps[i - 1]
}
```

**Call-site changes:**
- `switch currentStep` in `body` (line 88) → switch on the enum, not integers.
- `MultiStepFormSheet(currentStep: …)` calls (lines 117, 167, 204, 229) → pass `currentStepIndex`.
- All `currentStep = N` assignments (lines 132, 173, 176, 207, 210, 235) → call `advance()` / `goBack()`, or assign the enum case directly when jumping.
- Vendor-picker condition at line 100 (`if currentStep == 2 || !destination.isEmpty`) → replace with `if currentStep == .destination || !destination.isEmpty`. This is the case where the ordinal comparison would silently break: preserve the *intent* (this is the destination step), not the number.
- Delete the `detailsStep` helper — replaced by `.details` case.

**Verification:**
- Build succeeds.
- Manual test: full Purchase, Sale, Return flows in both project and inventory contexts. Back/next navigation lands on the expected screen every time. Step counter in the header reads "1 of N … N of N".
- No behavioral change vs. `main` at this point — pure refactor.

**Commit this task separately** before starting Task 2. Keeps the diff reviewable and lets us revert independently if the refactor regresses anything.

### Task 1 — Add `.expense` to `BudgetCategoryType`

**File:** [LedgeriOS/LedgeriOS/Models/Shared/Enums.swift:32](../../LedgeriOS/LedgeriOS/Models/Shared/Enums.swift)

- Add `case expense` to the `BudgetCategoryType` enum.
- Raw value: `"expense"`.
- Preserve the existing legacy decoder path (`"standard"` → `.general`).
- Add a display label for UI (matches existing pattern for `.fee` / `.general` / `.itemized`).

**Verification:** build succeeds. Existing category documents with `categoryType: "general" | "itemized" | "fee"` still decode. New value `"expense"` round-trips via `Codable`.

### Task 2 — Add a "category type filter" step to `NewTransactionView`

**File:** [LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift](../../LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift)

**State:**
- Add `@State private var categoryTypeFilter: BudgetCategoryType?` — the user's pick at the new step. Not persisted on the transaction.

**Step ordering:** update `orderedSteps` (from Task 0) to insert the new `.categoryTypeFilter` step and conditionally drop `.destination` for Fee:

```swift
case (.purchase, true):
    var steps: [TransactionCreationStep] = [.typeSelection, .categoryTypeFilter, .budgetCategory]
    if categoryTypeFilter != .fee {
        steps.append(.destination)
    }
    steps.append(.details)
    return steps
```

Sale / Return / inventory-context branches are untouched.

**Helpers:**
```swift
private var isPurchase: Bool { transactionType == .purchase }
private var isFee: Bool { categoryTypeFilter == .fee }
```

**Filtered category list:**
- In Step 3, filter `projectContext?.enabledBudgetCategories` to those whose `metadata?.categoryType == categoryTypeFilter`.
- Treat `.general` categories as matching the `.expense` filter.

**Auto-set source for Fee:**
- When `categoryTypeFilter == .fee` is confirmed, set `source = InventoryOperationsService.inventoryLabel(for: accountContext.currentAccount?.name)` before entering the Details step. Do not show the vendor picker.

### Task 3 — Conditional field visibility on the Details step

**File:** same as Task 2, `stepDetails` (around line 225).

Drive visibility off the picked category's `metadata?.categoryType` (not off `categoryTypeFilter` — use the saved category's type so we're always reading from the canonical source).

Add:
```swift
private var detailsCategoryType: BudgetCategoryType? {
    selectedCategory?.metadata?.categoryType
}
```

Then in the Details view:
- **Source/Vendor row**: hide if `.fee`.
- **Purchased By picker** (line ~262): hide if `.fee`.
- **Payable (Reimbursement) picker** (line ~272): hide if `.fee`.
- **Subtotal + Tax Rate** (line ~285): already conditional on `.itemized`; no change.
- **All other fields**: unchanged.

Implicit values when Fee fields are hidden (set once when entering the Details step for a Fee flow):
- `purchasedBy = "design-business"`
- `reimbursementType = "owed-to-company"`
- `source = inventoryLabel(for: account.name)` (already set in Task 2)

### Task 4 — Validation

**File:** `TransactionFormValidation` (find via Grep — used at [NewTransactionView.swift:56](../../LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift)).

`isTransactionReadyToSubmit` currently only checks `type`. Audit whether it needs to:
- Require a category when `transactionType == .purchase` and `hasCategories`.
- Skip vendor requirement when Fee.

If changes are needed, add a new overload that takes the category type and vendor state. Keep the old signature for Sale/Return callers.

### Task 5 — Spec cross-check

Re-read [docs/specs/transaction-creation.md](../specs/transaction-creation.md) after implementation. Confirm the table of field visibility in §Step 5 matches what ships. If anything drifted, update the spec in the same PR.

## Acceptance Criteria

- [ ] `BudgetCategoryType.expense` exists and round-trips through Firestore.
- [ ] Purchase + project context shows the Category Type Filter step between Type and Category.
- [ ] Picking **Fee** skips the vendor step and lands on Details with `source` pre-populated to the inventory label.
- [ ] Details step hides Purchased By + Payable when the selected category is `.fee`.
- [ ] Details step hides Subtotal + Tax Rate when the selected category is `.fee`, `.expense`, or `.general`.
- [ ] Details step shows Subtotal + Tax Rate when the selected category is `.itemized` (regression check — this behavior is pre-existing).
- [ ] Sale and Return flows are bit-for-bit identical to before.
- [ ] Inventory context is unchanged (no filter step, no category step).
- [ ] Routing after creation: Fee / Expense / General stay on the project; Itemized + `design-business` still routes to `ItemEntryFlowView` (spec §Routing After Creation).
- [ ] Legacy `.general` categories appear under the **Expense** filter, not silently dropped.
- [ ] Step counters (`currentStep` / `totalSteps`) display correctly for every branch.

## Risks / Watch-outs

- **Hidden fields still needing values.** Whenever a field is hidden for Fee, its backing state must be set to the implicit value *before* `createTransaction` is called. Missing this will silently create transactions with wrong `purchasedBy` / empty `source`.
- **`status` stays implicit.** `@State private var status: TransactionStatus = .completed` ([NewTransactionView.swift:34](../../LedgeriOS/LedgeriOS/Views/Creation/NewTransactionView.swift)) is never shown in the UI but is written on create. Preserve the default through all refactors — don't accidentally drop it or expose it as a form field.
- **`inventoryLabel(for:)` needs an account name.** Pull from `accountContext.currentAccount?.name`. If nil, the helper already falls back to `"Business Inventory"`.
- **Test fixtures.** Any unit test that constructs a `BudgetCategory` and assumes a specific `categoryType` behavior needs to be reviewed when Fee field-hiding lands.
