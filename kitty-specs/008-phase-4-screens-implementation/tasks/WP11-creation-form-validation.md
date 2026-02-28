---
work_package_id: WP11
title: Session 6 Logic – Creation Form Validation
lane: "doing"
dependencies: [WP08]
base_branch: 008-phase-4-screens-implementation-WP08
base_commit: 8dd0f94c525a7425ca5e49f0647c6dc69b979705
created_at: '2026-02-28T23:08:52.013294+00:00'
subtasks:
- T050
- T051
- T052
- T053
- T054
phase: Phase 6 - Session 6
assignee: ''
agent: "claude-opus"
shell_pid: "86623"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T22:30:00Z'
  lane: planned
  agent: system
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP11 – Session 6 Logic — Creation Form Validation

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- 4 pure validation modules covering project, transaction, item, and space creation forms.
- All validation functions return `[ValidationError]` with exact error messages from spec.
- All Swift Testing tests pass: required fields, boundary values, valid inputs, transaction type-specific rules.

**To start implementing:** `spec-kitty implement WP11 --base WP08`

---

## Context & Constraints

- **Refs**: `plan.md` (WP11), `spec.md` FR-11, `data-model.md` (Validation Error Messages table).
- **Exact error messages** (from data-model.md — use these strings verbatim):
  - Project name empty: `"Name is required"`
  - Project clientName empty: `"Client name is required"`
  - Item name empty: `"Name is required"`
  - Space name empty: `"Name is required"`
  - Budget category name >100 chars: `"Category name must be 100 characters or less"`
  - Category isItemized AND isFee: `"A category cannot be both Itemized and Fee"`
- **Architecture**: Pure functions in `Logic/`. No SwiftUI, no Firestore, no async.
- **Output type**: consistent `ValidationError` struct across all 4 modules:
  ```swift
  struct ValidationError: Equatable {
      let field: String   // field name, e.g., "name", "clientName"
      let message: String // exact error message text
  }
  ```
- **Transaction form**: progressive disclosure — only validate fields that are visible (based on selected type + destination).

---

## Subtasks & Detailed Guidance

### Subtask T050 – Create `Logic/ProjectFormValidation.swift`

**Purpose**: Validation logic for the New Project creation form.

**Steps**:
1. Create `Logic/ProjectFormValidation.swift`.
2. Implement `func validateProject(name: String, clientName: String, budgetAllocations: [String: Int]) -> [ValidationError]`:
   - If `name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` → add `ValidationError(field: "name", message: "Name is required")`.
   - If `clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` → add `ValidationError(field: "clientName", message: "Client name is required")`.
   - Budget allocations: validate that no allocation is negative (non-negative integer cents). If any allocation `< 0` → add `ValidationError(field: "budgetAllocations", message: "Budget allocations must be zero or greater")`.
3. Implement `func isValidProject(name: String, clientName: String) -> Bool`:
   - Returns `!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`.

**Files**:
- `Logic/ProjectFormValidation.swift` (create, ~50 lines)

**Parallel?**: Yes.

---

### Subtask T051 – Create `Logic/TransactionFormValidation.swift`

**Purpose**: Progressive disclosure validation for the New Transaction multi-step form.

**Steps**:
1. Create `Logic/TransactionFormValidation.swift`.
2. Transaction types: `"purchase"`, `"sale"`, `"return"`, `"to-inventory"`.
3. Implement `func validateTransactionStep1(type: String?) -> [ValidationError]`:
   - Type required: if `type == nil || type!.isEmpty` → `ValidationError(field: "transactionType", message: "Transaction type is required")`.
4. Implement `func validateTransactionStep2(type: String, destination: String?) -> [ValidationError]`:
   - For types that require a destination (purchase/sale/return — need a project or channel): if `destination == nil` → `ValidationError(field: "destination", message: "Destination is required")`.
5. Implement `func validateTransactionDetail(type: String, source: String?, amountCents: Int?, date: Date?) -> [ValidationError]`:
   - Source: optional (no required validation).
   - Amount: optional for creation.
   - Return empty array if all optional — no required detail fields for transaction creation.
6. Implement `func isTransactionReadyToSubmit(type: String?) -> Bool`:
   - Returns `type != nil`.

**Files**:
- `Logic/TransactionFormValidation.swift` (create, ~60 lines)

**Parallel?**: Yes.

**Notes**:
- Transaction creation is relatively permissive — only type is required in the RN app. Check RN `src/screens/NewTransactionScreen.tsx` for exact required field rules.

---

### Subtask T052 – Create `Logic/ItemFormValidation.swift`

**Purpose**: Validation for the New Item creation form.

**Steps**:
1. Create `Logic/ItemFormValidation.swift`.
2. Implement `func validateItem(name: String, purchasePriceCents: Int?, projectPriceCents: Int?, marketValueCents: Int?) -> [ValidationError]`:
   - Name required: if `name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` → `ValidationError(field: "name", message: "Name is required")`.
   - Prices: if any provided price `< 0` → `ValidationError(field: "purchasePrice", message: "Price must be zero or greater")` (same for project price, market value).
3. Implement `func isValidItem(name: String) -> Bool`.

**Files**:
- `Logic/ItemFormValidation.swift` (create, ~40 lines)

**Parallel?**: Yes.

---

### Subtask T053 – Create `Logic/SpaceFormValidation.swift`

**Purpose**: Validation for the New Space creation form.

**Steps**:
1. Create `Logic/SpaceFormValidation.swift`.
2. Implement `func validateSpace(name: String) -> [ValidationError]`:
   - Name required: if `name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` → `ValidationError(field: "name", message: "Name is required")`.
3. Implement `func isValidSpace(name: String) -> Bool`.

**Files**:
- `Logic/SpaceFormValidation.swift` (create, ~30 lines)

**Parallel?**: Yes.

---

### Subtask T054 – Write Swift Testing suites for all 4 validators

**Purpose**: Verify all validation rules with exact error messages.

**Steps**:
1. Create `LedgeriOSTests/Logic/ProjectFormValidationTests.swift`:
   - `@Test func emptyNameFails()`: `name=""` → errors contains `ValidationError(field: "name", message: "Name is required")`.
   - `@Test func emptyClientNameFails()`.
   - `@Test func whitespaceOnlyNameFails()`: `name="   "` → fails.
   - `@Test func validProjectPasses()`: name + clientName provided → empty errors.
   - `@Test func negativeBudgetFails()`.
2. Create `LedgeriOSTests/Logic/TransactionFormValidationTests.swift`:
   - `@Test func nilTypeFails()`.
   - `@Test func validTypePasses()`: `type="purchase"` → empty errors.
3. Create `LedgeriOSTests/Logic/ItemFormValidationTests.swift`:
   - `@Test func emptyNameFails()`.
   - `@Test func negativePriceFails()`.
   - `@Test func validItemPasses()`.
4. Create `LedgeriOSTests/Logic/SpaceFormValidationTests.swift`:
   - `@Test func emptyNameFails()`.
   - `@Test func validSpacePasses()`.
   - `@Test func trimmedWhitespaceFails()`.

**Files**:
- 4 test files in `LedgeriOSTests/Logic/` (create, ~40 lines each)

**Parallel?**: Partial — each test file starts once its implementation is done.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Transaction required fields unclear | Check RN `NewTransactionScreen.tsx` for exact submit gate conditions |
| `ValidationError` naming conflicts with other types | Use module prefix if needed: `FormValidationError` |

---

## Review Guidance

- [ ] Exact error message strings match data-model.md verbatim.
- [ ] Whitespace-only names fail (use `trimmingCharacters(in: .whitespacesAndNewlines)`).
- [ ] All 4 validators compile with no SwiftUI/Firestore imports.
- [ ] All tests pass ⌘U.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-02-28T23:08:52Z – claude-opus – shell_pid=44632 – lane=doing – Assigned agent via workflow command
- 2026-02-28T23:20:57Z – claude-opus – shell_pid=44632 – lane=for_review – Ready for review: 4 pure validation modules (Project, Transaction, Item, Space) with shared ValidationError type. 47 Swift Testing tests all passing. No SwiftUI/Firestore imports.
- 2026-02-28T23:21:48Z – claude-opus – shell_pid=86623 – lane=doing – Started review via workflow command
