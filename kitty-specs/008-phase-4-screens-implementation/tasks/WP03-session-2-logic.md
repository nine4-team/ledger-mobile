---
work_package_id: "WP03"
title: "Session 2 Logic – Transaction Display + Next Steps + Completeness + Receipt Parser"
phase: "Phase 2 - Session 2"
lane: "doing"
dependencies: ["WP00"]
subtasks:
  - "T014"
  - "T015"
  - "T016"
  - "T017"
  - "T018"
  - "T019"
assignee: ""
agent: "claude-opus"
shell_pid: ""
review_status: ""
reviewed_by: ""
history:
  - timestamp: "2026-02-26T22:30:00Z"
    lane: "planned"
    agent: "system"
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP03 – Session 2 Logic — Transaction Display + Next Steps + Completeness + Receipt Parser

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- 5 pure logic modules implemented, all in `Logic/`.
- `TransactionCompletenessCalculations`: exact thresholds match spec business rules (over>1.2, complete≤1%, near≤20%).
- `ReceiptListParser`: produces identical output to the RN `receiptListParser.ts` for all documented edge cases.
- All Swift Testing tests pass — mirror RN test cases verbatim where they exist.

**To start implementing:** `spec-kitty implement WP03 --base WP00`

---

## Context & Constraints

- **Refs**: `plan.md` (WP03), `spec.md` FR-4 (badges), FR-5 (completeness, next steps), `data-model.md` (Transaction model, completeness thresholds, badge color table, canonical values table).
- **RN source to port**: `src/utils/transactionCompleteness.ts`, `src/utils/receiptListParser.ts` — read these first.
- **Architecture**: Pure logic files in `Logic/`. No SwiftUI, no Firestore, no side effects.
- **Monetary amounts**: Always `Int` cents. Never `Double` for money arithmetic.
- **Completeness thresholds** (FR-5.7 — EXACT, check in this order):
  1. `over` if ratio > 1.2
  2. `complete` if |variance%| ≤ 1%
  3. `near` if |variance%| ≤ 20%
  4. `incomplete` otherwise
  5. Returns `nil` if no valid subtotal
- **Subtotal resolution priority** (FR-5.10):
  1. Explicit `transaction.subtotalCents` if present
  2. Inferred: `amountCents - (amountCents * taxRatePct / (100 + taxRatePct))` if both amount and taxRate present
  3. Fallback: `amountCents` (with `missingTaxData = true` flag)
- **Transaction type canonical labels**: `purchase`→"Purchase", `sale`→"Sale", `return`→"Return", `to-inventory`→"To Inventory".
- **Badge colors** (from `data-model.md`): Purchase=`StatusColors.budgetMet`(green), Sale=`.blue`, Return=`StatusColors.budgetMissed`(red), To Inventory=`BrandColors.primary`, Owed to Client/Business=amber, Receipt=`BrandColors.primary`, Needs Review=rust, Category=`BrandColors.primary`.

---

## Subtasks & Detailed Guidance

### Subtask T014 – Create `Logic/TransactionDisplayCalculations.swift`

**Purpose**: All logic for how a transaction is labeled, formatted, and badged in the UI.

**Steps**:
1. Create `Logic/TransactionDisplayCalculations.swift`.
2. Define output types:
   ```swift
   struct BadgeConfig {
       let text: String
       let color: Color
   }
   enum TransactionBadgeType { case type, reimbursement, receipt, needsReview, category }
   ```
3. Implement `func displayName(for transaction: Transaction) -> String`:
   - Priority: `transaction.source` (non-nil, non-empty) → canonical inventory sale label → `String(transaction.id.prefix(6))` → `"Untitled Transaction"`.
   - Canonical inventory sale: `isCanonicalInventorySale=true` → use `inventorySaleDirection` to build label (e.g., "To Inventory" / "From Inventory").
4. Implement `func badgeConfigs(for transaction: Transaction, category: BudgetCategory?) -> [BadgeConfig]`:
   - Type badge: always present. Color per type (see badge colors in Context).
   - Reimbursement badge: if `reimbursementType != nil && reimbursementType != "none"`.
   - Receipt badge: if transaction has `receiptImages` or `hasEmailReceipt=true`.
   - Needs Review badge: if `transaction.needsReview == true`.
   - Category badge: if `category != nil`.
5. Implement `func formattedAmount(for transaction: Transaction) -> String`:
   - Format `amountCents` as currency string (e.g., "$49.99"). Use existing `CurrencyFormatting.swift`.
6. Implement `func formattedDate(for transaction: Transaction) -> String`:
   - Format `transactionDate` timestamp as "MMM d, yyyy". Handle nil → empty string.

**Files**:
- `Logic/TransactionDisplayCalculations.swift` (create, ~90 lines)

**Parallel?**: Yes — independent of T015–T018.

---

### Subtask T015 – Create `Logic/TransactionNextStepsCalculations.swift`

**Purpose**: Compute the "Next Steps" card shown on `TransactionDetailView`.

**Steps**:
1. Create `Logic/TransactionNextStepsCalculations.swift`.
2. Define:
   ```swift
   struct NextStep {
       let id: String
       let title: String
       let isComplete: Bool
   }
   ```
3. Implement `func computeNextSteps(transaction: Transaction, category: BudgetCategory?, items: [Item]) -> [NextStep]`:
   - Step 1: "Add a budget category" — complete if `transaction.budgetCategoryId != nil`.
   - Step 2: "Enter the amount" — complete if `transaction.amountCents != nil && transaction.amountCents != 0`.
   - Step 3: "Add a receipt" — complete if `transaction.receiptImages?.isEmpty == false || transaction.hasEmailReceipt == true`.
   - Step 4: "Add items" — complete if `items.isEmpty == false`.
   - Step 5: "Set who purchased this" — complete if `transaction.purchasedBy != nil`.
   - Step 6 (conditional): "Set the tax rate" — only shown if `category?.type == "itemized"`. Complete if `transaction.taxRatePct != nil`.
4. Implement `func allStepsComplete(_ steps: [NextStep]) -> Bool`: returns `steps.allSatisfy { $0.isComplete }`.
5. Present incomplete steps first (sort: incomplete before complete) — or match RN order (check RN source).

**Files**:
- `Logic/TransactionNextStepsCalculations.swift` (create, ~70 lines)

**Parallel?**: Yes.

---

### Subtask T016 – Create `Logic/TransactionCompletenessCalculations.swift`

**Purpose**: Port `src/utils/transactionCompleteness.ts` — the transaction audit logic that compares item prices to the transaction subtotal.

**Steps**:
1. Read `src/utils/transactionCompleteness.ts` — understand every branch.
2. Create `Logic/TransactionCompletenessCalculations.swift`.
3. Define:
   ```swift
   enum CompletenessStatus { case over, complete, near, incomplete }
   struct CompletenessResult {
       let status: CompletenessStatus?   // nil if no valid subtotal
       let ratio: Double?
       let variancePct: Double?
       let itemsNetTotalCents: Int
       let subtotalCents: Int?
       let missingTaxData: Bool
   }
   ```
4. Implement `func resolveSubtotal(transaction: Transaction) -> (Int?, Bool)`:
   - Returns `(subtotalCents, missingTaxData)`.
   - Priority: explicit `transaction.subtotalCents` → inferred → fallback `amountCents`.
   - Inferred formula: `subtotal = amount / (1 + taxRate/100)` — in integer cents, round to nearest.
5. Implement `func computeItemsNetTotal(items: [Item]) -> Int`:
   - Sum of `item.projectPriceCents ?? item.purchasePriceCents ?? 0`.
   - Includes returned items and sold items.
6. Implement `func computeCompleteness(transaction: Transaction, items: [Item]) -> CompletenessResult`:
   - Resolve subtotal.
   - If no valid subtotal → return `CompletenessResult(status: nil, ...)`.
   - Compute ratio = `itemsNetTotal / subtotal` (as Double).
   - Compute variancePct = `(itemsNetTotal - subtotal) / subtotal * 100`.
   - Apply thresholds in exact order from spec.

**Files**:
- `Logic/TransactionCompletenessCalculations.swift` (create, ~100 lines)

**Parallel?**: Yes.

**Notes**:
- Integer division rounding for tax-rate inference: use `Double` intermediate, then round to `Int`.
- The RN source is authoritative — match every branch including edge cases (zero items, zero subtotal, nil tax rate).

---

### Subtask T017 – Create `Logic/TransactionListCalculations.swift`

**Purpose**: All filtering, sorting, and search logic for the transaction list.

**Steps**:
1. Create `Logic/TransactionListCalculations.swift`.
2. Define sort enum:
   ```swift
   enum TransactionSort {
       case dateDesc, dateAsc, createdDesc, createdAsc
       case sourceDesc, sourceAsc, amountDesc, amountAsc
   }
   ```
3. Define filter struct:
   ```swift
   struct TransactionFilter {
       var statusValues: Set<String>      // "pending", "completed", "canceled", "inventory-only"
       var reimbursementValues: Set<String> // "owed-to-company", "owed-to-client"
       var hasReceipt: Bool?
       var typeValues: Set<String>        // "purchase", "return"
       var completenessValues: Set<String> // "needs-review", "complete"
       var budgetCategoryId: String?
       var purchasedByValues: Set<String>  // "client-card", "design-business", "missing"
       var sourceValues: Set<String>       // dynamic from unique sources
   }
   ```
4. Implement `func filterAndSort(transactions: [Transaction], filter: TransactionFilter, sort: TransactionSort, query: String, items: [Item], categories: [BudgetCategory]) -> [Transaction]`:
   - Apply each active filter dimension.
   - Apply text search across source, notes, type label, formatted amount.
   - Apply sort.
   - Nil dates sort LAST for date-based sorts.
5. Implement `func uniqueSources(from transactions: [Transaction]) -> [String]` for the dynamic source filter.

**Files**:
- `Logic/TransactionListCalculations.swift` (create, ~120 lines)

**Parallel?**: Yes.

---

### Subtask T018 – Create `Logic/ReceiptListParser.swift`

**Purpose**: Port `src/utils/receiptListParser.ts` — parse free-form receipt text into structured `(name, priceCents)` pairs.

**Steps**:
1. Read `src/utils/receiptListParser.ts` carefully — understand the parsing rules.
2. Create `Logic/ReceiptListParser.swift`.
3. Define:
   ```swift
   struct ParsedReceiptItem {
       let name: String
       let priceCents: Int?
   }
   struct ReceiptParseResult {
       let items: [ParsedReceiptItem]
       let skippedLines: [String]
   }
   ```
4. Implement `func parseReceiptText(_ text: String) -> ReceiptParseResult`:
   - Split on newlines.
   - For each line: try to extract a price (look for `$` prefix or trailing decimal number).
   - Name = line with price portion removed and trimmed.
   - Lines with no parseable content → skippedLines.
   - Blank lines → skip silently (not in skippedLines).
   - Price extraction: strip `$`, parse as decimal, convert to cents.
5. Ensure: "Lamp $49.99" → name="Lamp", priceCents=4999. "Chair" → name="Chair", priceCents=nil.

**Files**:
- `Logic/ReceiptListParser.swift` (create, ~80 lines)

**Parallel?**: Yes.

**Notes**:
- Port the RN test cases verbatim into Swift Testing (T019) — this ensures identical behavior.
- Edge cases: "$" alone, price with commas ("$1,299.00"), negative prices (treat as nil), price in middle of text.

---

### Subtask T019 – Write Swift Testing suites for all 5 modules

**Purpose**: Comprehensive test coverage for all 5 logic modules.

**Steps**:
1. Create `LedgeriOSTests/Logic/TransactionDisplayCalculationsTests.swift`:
   - Display name priority: source → canonical label → ID prefix → "Untitled Transaction".
   - Badge config for each badge type.
   - Formatted amount for positive, zero, nil.
2. Create `LedgeriOSTests/Logic/TransactionNextStepsCalculationsTests.swift`:
   - 5-step: non-itemized category → no tax rate step.
   - 6-step: itemized category → tax rate step appears.
   - All-complete → `allStepsComplete` returns `true`.
3. Create `LedgeriOSTests/Logic/TransactionCompletenessCalculationsTests.swift`:
   - `over`: ratio = 1.3 → `.over`.
   - `complete`: |variance%| = 0.5% → `.complete`.
   - `near`: |variance%| = 15% → `.near`.
   - `incomplete`: |variance%| = 25% → `.incomplete`.
   - `nil`: no subtotal, no amount → `status == nil`.
   - Subtotal resolution: explicit > inferred > fallback.
4. Create `LedgeriOSTests/Logic/TransactionListCalculationsTests.swift`:
   - Each of the 8 filter dimensions independently.
   - Date-desc sort with nil dates last.
   - Source text search.
5. Create `LedgeriOSTests/Logic/ReceiptListParserTests.swift`:
   - Port test cases from `src/utils/receiptListParser.test.ts` verbatim.
   - Blank lines skipped silently.
   - Lines with no content → skippedLines.
   - Price with $ prefix parsed correctly.

**Files**:
- 5 test files in `LedgeriOSTests/Logic/` (create, ~40 lines each = ~200 total)

**Parallel?**: Partially — each test file can be written as soon as its corresponding implementation exists.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| JS→Swift floating point differences in completeness | Use integer cents throughout; only convert to Double for ratio/variance computation |
| `ReceiptListParser` edge cases not covered | Port ALL test cases from `receiptListParser.test.ts` — don't skip any |
| `transactionCompleteness.ts` branching not fully understood | Read entire file before coding; add comments referencing TS line numbers |
| Subtotal inference rounding | Document rounding strategy (round half up to nearest cent) in code comments |

---

## Review Guidance

- [ ] All 5 modules compile with no SwiftUI/Firestore imports.
- [ ] Completeness thresholds: `over`, `complete`, `near`, `incomplete`, `nil` each have a test case.
- [ ] Completeness thresholds checked in EXACT order from spec (over first, then complete, then near).
- [ ] ReceiptListParser: blank lines not in skippedLines; lines with no parseable content ARE in skippedLines.
- [ ] All tests pass ⌘U.
- [ ] No `Double` used for monetary storage — only for ratio/variance computation.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-02-27T21:55:05Z – claude-opus – lane=doing – Starting implementation - worktree created manually from main (WP00 merged)
