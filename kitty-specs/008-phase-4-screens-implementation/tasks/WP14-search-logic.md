---
work_package_id: "WP14"
title: "Session 7b Logic – Search Calculations"
phase: "Phase 7 - Session 7b"
lane: "planned"
dependencies: ["WP06"]
subtasks:
  - "T066"
  - "T067"
assignee: ""
agent: ""
shell_pid: ""
review_status: ""
reviewed_by: ""
history:
  - timestamp: "2026-02-26T22:30:00Z"
    lane: "planned"
    agent: "system"
    action: "Prompt generated via /spec-kitty.tasks"
---

# Work Package Prompt: WP14 – Session 7b Logic — Search Calculations

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- `SearchCalculations` implements all 3 matching strategies with per-entity field mapping.
- Amount prefix-range: "40" → [$40.00–$40.99], "40.0" → [$40.00–$40.09], "40.00" → [$40.00 exact].
- SKU normalization: "ABC-123" matches "abc123" (strip all non-alphanumeric, case-insensitive).
- Empty query returns all results (not empty results).
- All Swift Testing tests pass — all edge cases from data-model.md.

**To start implementing:** `spec-kitty implement WP14 --base WP06`

---

## Context & Constraints

- **Refs**: `plan.md` (WP14), `spec.md` FR-13, `data-model.md` (Search Amount Prefix-Range Algorithm section, per-entity field mappings FR-13.4–13.6).
- **Amount prefix-range algorithm** (from data-model.md — EXACT):
  1. Strip leading `$` and commas.
  2. Split on `"."` → integer part + decimal part.
  3. Integer only → `range = [int*100, int*100+99]`.
  4. One decimal digit → `range = [int*1000+decimal*10, int*1000+decimal*10+9]`.
     - Wait: re-read. "40.0" → range: 4000...4009. So: int=40, decimal="0" (1 digit) → `40*100+0*10=4000` to `4000+9=4009`. ✓
  5. Two decimal digits → `range = [int*100+decimal, int*100+decimal]` (exact).
     - "40.00" → 4000 exactly.
  6. Invalid (non-numeric after stripping) → no amount matching (skip silently).
- **Per-entity field mappings** (FR-13.4–13.6):
  - Items (text): name, source, SKU (raw + normalized), notes, budget category name.
  - Items (amount): purchasePriceCents, projectPriceCents, marketValueCents.
  - Transactions (text): displayName (resolved per TransactionDisplayCalculations), transactionType, notes, purchasedBy, budget category name.
  - Transactions (amount): amountCents.
  - Spaces (text): name, notes. No amount matching.
- **Architecture**: Pure function. `func search(query: String, items: [Item], transactions: [Transaction], spaces: [Space], categories: [BudgetCategory]) -> SearchResults`.

---

## Subtasks & Detailed Guidance

### Subtask T066 – Create `Logic/SearchCalculations.swift`

**Purpose**: Three matching strategies + per-entity field mapping for universal search.

**Steps**:
1. Create `Logic/SearchCalculations.swift`.
2. Define output type:
   ```swift
   struct SearchResults {
       let items: [Item]
       let transactions: [Transaction]
       let spaces: [Space]
   }
   ```
3. Implement amount prefix-range parser: `func parseAmountQuery(_ query: String) -> ClosedRange<Int>?`:
   - Strip `$` and `,` from query.
   - Return `nil` if result is non-numeric (non-parseable as decimal).
   - Split on `"."`:
     - No decimal: `let cents = int * 100; return cents...(cents+99)`.
     - 1 decimal digit: `let d = decimalPart.first! - "0"; return (int*100 + Int(d)*10)...(int*100 + Int(d)*10 + 9)`.
     - 2 decimal digits: `let cents = int*100 + decimalCents; return cents...cents`.
4. Implement SKU normalizer: `func normalizedSKU(_ sku: String) -> String`:
   - Strip all non-alphanumeric characters: `sku.filter { $0.isLetter || $0.isNumber }.lowercased()`.
5. Implement text substring match: `func textMatch(query: String, in text: String?) -> Bool`:
   - `text?.lowercased().contains(query.lowercased()) ?? false`.
6. Implement item match:
   ```swift
   func itemMatches(item: Item, query: String, categories: [BudgetCategory]) -> Bool {
       if query.isEmpty { return true }
       let amountRange = parseAmountQuery(query)
       // Text fields
       let textFields = [item.name, item.source, item.sku, item.notes,
                        categories.first(where: { $0.id == item.budgetCategoryId })?.name]
       let textMatch = textFields.contains { textMatch(query: query, in: $0) }
       // SKU normalized
       let skuNorm = item.sku.map { normalizedSKU($0) }
       let skuMatch = skuNorm?.contains(normalizedSKU(query)) ?? false
       // Amount fields
       let amountMatch = amountRange.map { range in
           [item.purchasePriceCents, item.projectPriceCents, item.marketValueCents]
               .compactMap { $0 }.contains { range.contains($0) }
       } ?? false
       return textMatch || skuMatch || amountMatch
   }
   ```
7. Implement transaction match: text fields (displayName, transactionType, notes, purchasedBy, category name), amount field (amountCents).
8. Implement space match: text fields (name, notes). No amount matching.
9. Implement main function:
   ```swift
   func search(query: String, items: [Item], transactions: [Transaction], spaces: [Space], categories: [BudgetCategory]) -> SearchResults {
       if query.isEmpty { return SearchResults(items: items, transactions: transactions, spaces: spaces) }
       return SearchResults(
           items: items.filter { itemMatches(item: $0, query: query, categories: categories) },
           transactions: transactions.filter { transactionMatches(transaction: $0, query: query, categories: categories) },
           spaces: spaces.filter { spaceMatches(space: $0, query: query) }
       )
   }
   ```

**Files**:
- `Logic/SearchCalculations.swift` (create, ~120 lines)

---

### Subtask T067 – Write Swift Testing suite for SearchCalculations

**Purpose**: Exhaustive edge case coverage for all 3 matching strategies.

**Steps**:
1. Create `LedgeriOSTests/Logic/SearchCalculationsTests.swift`.
2. Amount prefix-range tests:
   - `@Test func integerQuery()`: "40" → range 4000...4099. Item with purchasePriceCents=4050 → matches.
   - `@Test func oneDecimalQuery()`: "40.0" → range 4000...4009. Item with 4005 → matches, item with 4050 → no match.
   - `@Test func twoDecimalQuery()`: "40.00" → range 4000...4000. Item with 4000 → matches, 4001 → no match.
   - `@Test func dollarSignStripped()`: "$40" → same as "40".
   - `@Test func commaStripped()`: "1,200" → range 120000...120099.
   - `@Test func invalidQueryNoAmountMatch()`: "abc" → `parseAmountQuery` returns `nil`.
   - `@Test func emptyQueryReturnsAll()`: empty string → all items/transactions/spaces returned.
3. SKU normalization tests:
   - `@Test func hyphenStripped()`: "ABC-123" query matches item.sku="abc123".
   - `@Test func slashStripped()`: "ABC/123" matches "abc123".
   - `@Test func spaceStripped()`: "ABC 123" matches "abc123".
   - `@Test func caseInsensitive()`: "ABC123" matches "abc123".
4. Text substring tests:
   - `@Test func nameMatch()`: query "lamp" matches item.name="Table Lamp".
   - `@Test func caseInsensitiveText()`: query "LAMP" matches "table lamp".
   - `@Test func nilFieldNoMatch()`: query "lamp" with item.name=nil → no text match from name.
   - `@Test func categoryNameMatch()`: query "furnish" matches category.name="Furnishings" linked to item.

**Files**:
- `LedgeriOSTests/Logic/SearchCalculationsTests.swift` (create, ~120 lines)

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Amount prefix-range for 1-decimal: off-by-one | Test "40.0" → expect 4000...4009 specifically; "40.1" → 4010...4019 |
| Transaction displayName requires `TransactionDisplayCalculations` as dependency | Import and call `TransactionDisplayCalculations.displayName(for:)` in the match function |
| Empty string query behavior | Explicitly check `query.isEmpty` first → return all results |

---

## Review Guidance

- [ ] `parseAmountQuery("40")` returns `4000...4099`.
- [ ] `parseAmountQuery("40.0")` returns `4000...4009`.
- [ ] `parseAmountQuery("40.00")` returns `4000...4000`.
- [ ] `parseAmountQuery("$1,200")` returns `120000...120099`.
- [ ] `normalizedSKU("ABC-123")` returns `"abc123"`.
- [ ] Empty query returns all results.
- [ ] All tests pass ⌘U.
- [ ] No SwiftUI/Firestore imports.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
