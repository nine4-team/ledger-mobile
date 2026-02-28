---
work_package_id: WP04
title: Session 2 Screens – Transactions Tab + Transaction Detail + Modals
lane: "doing"
dependencies:
- WP02
base_branch: 008-phase-4-screens-implementation-WP02
base_commit: c8543c031a946d9d8fd627756e2d37959de23803
created_at: '2026-02-27T23:10:07.332505+00:00'
subtasks:
- T020
- T021
- T022
- T023
- T024
- T025
phase: Phase 2 - Session 2
assignee: ''
agent: "claude-sonnet"
shell_pid: "56410"
review_status: "has_feedback"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-26T22:30:00Z'
  lane: planned
  agent: system
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP04 – Session 2 Screens — Transactions Tab + Transaction Detail + Modals

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

**Reviewed by**: nine4-team
**Status**: ❌ Changes Requested
**Date**: 2026-02-28

## Review Feedback — WP04

### Missing Tests for New Logic Files (Blocking)

Three pure logic files were introduced in this WP with **zero test coverage**:
- `Logic/TransactionNextStepsCalculations.swift`
- `Logic/TransactionCompletenessCalculations.swift`
- `Logic/ReceiptListParser.swift`

The plan explicitly calls this out (plan.md line 179): "Tests: completeness thresholds (all 4 states + null), subtotal resolution priority, next-steps (5-step and 6-step), filter dimensions, receiptListParser edge cases" and line 334: "port `transactionCompleteness.test.ts` and `receiptListParser.test.ts` verbatim."

CLAUDE.md mandates the test-first workflow for every new feature: logic must have tests before being marked complete.

**Required**: Add test files:
- `LedgeriOSTests/TransactionNextStepsCalculationTests.swift` — test 5-step and 6-step cases (with/without itemized category), allStepsComplete with all done and partial completion
- `LedgeriOSTests/TransactionCompletenessCalculationTests.swift` — test all 4 statuses (complete/near/incomplete/over), subtotal resolution priority (explicit > inferred from tax > fallback), nil/zero amount returns nil, varianceCents and variancePercent correctness
- `LedgeriOSTests/ReceiptListParserTests.swift` — standard line format, price with comma separators, lines without tax flag (no T), empty lines skipped, invalid lines go to skippedLines, empty input returns empty result

### Everything Else: ✅ Approved

- TransactionsTabView: real data, date-desc sort, filter/sort/search/add toolbar — correct
- TransactionDetailView: hero card, all 8 sections with correct default states (receipts expanded, rest collapsed), Next Steps hidden when all complete, delete via confirmationDialog — correct
- Modal field order (FR-5.6): Vendor → Amount → Date → Status → Purchased By → Transaction Type → Reimbursement Type → Budget Category → Email Receipt → (conditional) Subtotal → Tax Rate — matches spec exactly
- CreateItemsFromListModal: two-step flow, DisclosureGroup for skipped lines, Create All disabled when empty — correct
- Sheet-on-sheet sequencing via onDismiss pattern — correct per CLAUDE.md
- navigationDestination(for: Transaction.self) in ProjectDetailView — correct
- All modals use .sheet() with presentationDetents + presentationDragIndicator(.visible) — correct
- ProgressRing component — clean, well-animated, correct percentage display
- Category picker excludes archived categories — correct

### Minor Note (Non-blocking)

`CreateItemsFromListModal` callback signature in the spec says `onCreated: ([Item]) -> Void` but implementation uses `onCreated: ([ReceiptListParser.ParsedItem]) -> Void`. The implementation is actually cleaner (separation of concerns — modal doesn't touch ItemsService, parent handles creation). No change needed, just noting the intentional deviation.


## Objectives & Success Criteria

- `TransactionsTabView` replaces placeholder; shows real data sorted date-desc with toolbar (search/sort/filter/add).
- `TransactionDetailView` shows hero card, Next Steps (hidden when complete), 8 collapsible sections in correct default states.
- Badge colors match the spec color mapping exactly.
- 4 modals wired: `EditTransactionDetailsModal`, `EditNotesModal`, `CategoryPickerList`, `CreateItemsFromListModal`.
- `CreateItemsFromListModal` two-step flow works: paste text → preview parsed items + skipped lines → create items.
- Moved Items section visible (not collapsible) when lineage edges exist.

**To start implementing:** `spec-kitty implement WP04 --base WP02`

---

## Context & Constraints

- **Refs**: `plan.md` (WP04), `spec.md` FR-4 (transactions tab), FR-5 (transaction detail), FR-8.14 (CreateItemsFromListModal).
- **Architecture**: Views in `Views/Projects/`, Modals in `Modals/`. Bottom-sheet-first for all modals.
- **State**: `ProjectContext.transactions`, `ProjectContext.items`, `ProjectContext.budgetCategories` — already subscribed when ProjectDetailView is active.
- **Section default states** (FR-5.5): Receipts=expanded, all others (Other Images, Notes, Details, Items, Returned Items, Sold Items, Transaction Audit) collapsed.
- **Field order in EditTransactionDetailsModal** (FR-5.6): Vendor/Source → Amount → Date → Status → Purchased By → Transaction Type → Reimbursement Type → Budget Category → Email Receipt → (conditional) Subtotal → Tax Rate.
- **Moved Items section** (FR-5.13): non-collapsible, appears only when lineage edges exist, renders items at 50% opacity. `LineageEdgesService` may be a stub at this point — show empty section if no edges.
- **Transaction detail items subsection** (FR-5.15): has its own 6 sort modes + 6 filter modes (independent of the main transaction list sort/filter).
- **Navigation**: `NavigationLink(value: transaction)` with `.navigationDestination(for: Transaction.self)` — not deprecated form.

---

## Subtasks & Detailed Guidance

### Subtask T020 – Create `Views/Projects/TransactionsTabView.swift`

**Purpose**: Replace `TransactionsTabPlaceholder.swift` with a real, data-driven transaction list.

**Steps**:
1. Create `Views/Projects/TransactionsTabView.swift`.
2. Access `projectContext.transactions` filtered by date-desc (use `TransactionListCalculations.filterAndSort()`).
3. Build toolbar (matching RN design):
   - Search pill → toggle search bar.
   - Sort pill → `.sheet()` with sort picker (8 sort modes).
   - Filter pill → `.sheet()` with filter options (8 filter dimensions — status, reimbursement, receipt, type, completeness, budget category, purchased by, source).
   - Add pill → present `NewTransactionView` (stub for now — WP12 builds it).
4. Render each transaction with `TransactionCard` component. Pass: badge configs (from `TransactionDisplayCalculations`), display name, formatted amount, formatted date, item count, notes.
5. Add `NavigationLink(value: transaction)` wrapping each card.
6. Add `.navigationDestination(for: Transaction.self)` → `TransactionDetailView(transaction:)`.
7. Show empty state when no transactions match current filter/search.

**Files**:
- `Views/Projects/TransactionsTabView.swift` (create, ~100 lines)

**Parallel?**: No — sequential with T021.

---

### Subtask T021 – Create `Views/Projects/TransactionDetailView.swift`

**Purpose**: Full transaction detail screen with all sections, Next Steps, Moved Items, and delete action.

**Steps**:
1. Create `Views/Projects/TransactionDetailView.swift` with `init(transaction: Transaction)`.
2. Hero card at top: display name, formatted amount, formatted date.
3. Next Steps card:
   - Compute steps with `TransactionNextStepsCalculations.computeNextSteps()`.
   - Show progress ring (fraction = completed/total) using `ProgressRing` component.
   - List steps — incomplete first, with chevrons; completed with strikethrough + gold checkmark.
   - Hidden entirely when `allStepsComplete == true`.
4. 8 collapsible sections (use `CollapsibleSection` component):
   - Receipts (defaultExpanded: true): receipt image thumbnails; add/remove actions → `MediaService`.
   - Other Images (collapsed): other image thumbnails.
   - Notes (collapsed): formatted notes text; edit → `EditNotesModal`.
   - Details (collapsed): 11 fields in FR-5.6 order; edit → `EditTransactionDetailsModal`.
   - Items (collapsed): item list with 6-mode sort + 6-mode filter; add → two options: link existing OR "Create from List" → `CreateItemsFromListModal`.
   - Returned Items (collapsed, conditional): only if returned items exist.
   - Sold Items (collapsed, conditional): only if sold items exist.
   - Transaction Audit (collapsed, conditional): completeness badge + variance details.
5. Moved Items section (non-collapsible): fetch from `LineageEdgesService`; if edges exist, render `ItemCard` list at `.opacity(0.5)`. No header/title.
6. Delete action: toolbar button → `.confirmationDialog()` → hard delete via `TransactionsService.delete()` → `.dismiss()`.

**Files**:
- `Views/Projects/TransactionDetailView.swift` (create, ~200 lines)

**Parallel?**: No — T022–T025 depend on this skeleton existing.

**Notes**:
- Items section has its own local `@State var itemSort` and `@State var itemFilter` (not shared with main transaction list).
- Transaction Audit shows completeness result from `TransactionCompletenessCalculations.computeCompleteness()`.

---

### Subtask T022 – Create/wire `Modals/EditTransactionDetailsModal.swift`

**Purpose**: Bottom sheet for editing all transaction detail fields in the correct order.

**Steps**:
1. Create `Modals/EditTransactionDetailsModal.swift`.
2. Present as `.sheet()` with `.presentationDetents([.large])` + `.presentationDragIndicator(.visible)`.
3. Field order (FR-5.6): Vendor/Source (text field with vendor suggestion autocomplete from `VendorDefaultsService`), Amount (currency input), Date (date picker), Status (picker: pending/completed/canceled/inventory-only), Purchased By (picker: client-card/design-business/missing), Transaction Type (picker: purchase/sale/return/to-inventory), Reimbursement Type (picker: none/owed-to-client/owed-to-company), Budget Category (picker via `CategoryPickerList`), Email Receipt (toggle: true/false) → conditional: Subtotal (currency input), Tax Rate % (numeric input).
4. Show Subtotal and Tax Rate only if `budgetCategory?.type == "itemized"`.
5. Show computed Tax Amount (read-only field): Amount − Subtotal (nil if either is nil).
6. Save button: write changes to Firestore via `TransactionsService.update()` — optimistic (update local state immediately, don't await server).
7. Missing values display as "—" (read-only mode).
8. Vendor suggestions: dropdown or inline suggestions below the source field when typing.

**Files**:
- `Modals/EditTransactionDetailsModal.swift` (create, ~150 lines)

**Parallel?**: Yes — once T021 skeleton exists.

---

### Subtask T023 – Create/wire `Modals/EditNotesModal.swift`

**Purpose**: Shared bottom sheet for editing free-text notes — reused for transactions, items, spaces.

**Steps**:
1. Create `Modals/EditNotesModal.swift` with a generic design: `init(notes: String, onSave: (String) -> Void)`.
2. Present as `.sheet()` with `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)`.
3. Large `TextEditor` for multi-line notes input.
4. "Save" button calls `onSave(currentText)` then dismisses.
5. "Cancel" button discards changes and dismisses.
6. Make it reusable — it takes a closure for saving, not a Firestore service directly.

**Files**:
- `Modals/EditNotesModal.swift` (create, ~50 lines)

**Parallel?**: Yes.

---

### Subtask T024 – Create/wire `Modals/CategoryPickerList.swift`

**Purpose**: Single-select budget category picker presented as a bottom sheet list.

**Steps**:
1. Create `Modals/CategoryPickerList.swift` with `init(categories: [BudgetCategory], selectedId: String?, onSelect: (BudgetCategory) -> Void)`.
2. Present as `.sheet()` with `.presentationDetents([.medium, .large])`.
3. List of categories: name + checkmark if currently selected.
4. Tap → call `onSelect(category)` → dismiss.
5. Include "No Category" option at top that clears the selection (pass `nil` to `onSelect`).
6. Exclude archived categories from the list.

**Files**:
- `Modals/CategoryPickerList.swift` (create, ~60 lines)

**Parallel?**: Yes.

---

### Subtask T025 – Create `Modals/CreateItemsFromListModal.swift`

**Purpose**: Two-step modal for bulk item creation from pasted receipt text.

**Steps**:
1. Create `Modals/CreateItemsFromListModal.swift` with `init(transaction: Transaction, onCreated: ([Item]) -> Void)`.
2. Present as `.sheet()` with `.presentationDetents([.large])` + `.presentationDragIndicator(.visible)`.
3. **Step 1 (Paste)**: `TextEditor` for multi-line input. "Preview" button → call `ReceiptListParser.parseReceiptText(input)` → transition to Step 2.
4. **Step 2 (Preview)**:
   - List of parsed items: each row shows `name` + optional `price` (formatted as "$X.XX" or "—" if nil).
   - If `skippedLines.isEmpty == false`: show `DisclosureGroup("Skipped Lines")` with the list of skipped text.
   - "Create All" button → for each parsed item, call `ItemsService.create(name:, priceCents:, transactionId:)` → call `onCreated(newItems)` → dismiss.
   - "Back" button → return to Step 1.
5. "Create All" is disabled if parsed items list is empty.
6. Optimistic: dismiss as soon as create calls are fired — don't await all completions.

**Files**:
- `Modals/CreateItemsFromListModal.swift` (create, ~100 lines)

**Parallel?**: Yes.

**Notes**:
- `DisclosureGroup` for skipped lines: collapsed by default, expandable.
- Item creation: each item needs `name`, `transactionId`, optional `purchasePriceCents`. `budgetCategoryId` is inherited server-side from the transaction.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `LineageEdgesService` doesn't exist yet | Stub: `InventoryEdgesService.edges(forTransaction:)` returns `[]`. Show empty Moved Items section. |
| `TransactionCard` component shape unknown | Read Phase 5 component before building T020 |
| `CollapsibleSection` expand/collapse state storage | Use `@State var expandedSections: Set<String>` in `TransactionDetailView`; initialize with `"receipts"` expanded |
| EditTransactionDetailsModal is large | Split into header fields + conditional tax fields using `@ViewBuilder` |

---

## Review Guidance

- [ ] Transactions tab shows real data sorted date-desc (nil dates last).
- [ ] Badge colors match the FR-4.3 color mapping exactly.
- [ ] Transaction detail sections in correct default states (Receipts expanded, all others collapsed).
- [ ] Field order in EditTransactionDetailsModal matches FR-5.6 exactly.
- [ ] Next Steps: hidden when all steps complete; 6th step (tax rate) only shown for itemized categories.
- [ ] CreateItemsFromListModal: step 1 → step 2 with parsed items + skipped lines disclosure.
- [ ] Moved Items section: non-collapsible, 50% opacity, only when lineage edges exist.
- [ ] All modals present as bottom sheets with drag indicator.
- [ ] Light + dark mode correct.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-02-27T23:10:07Z – claude-opus – shell_pid=25734 – lane=doing – Assigned agent via workflow command
- 2026-02-27T23:27:03Z – claude-opus – shell_pid=25734 – lane=for_review – Ready for review: TransactionsTabView replaces placeholder with real data, TransactionDetailView with hero card + 8 collapsible sections + Next Steps + delete, 4 modals (EditDetails, EditNotes, CategoryPicker, CreateItemsFromList), 3 pure logic files ported from RN (NextSteps, Completeness, ReceiptListParser), ProgressRing component. Build passes clean.
- 2026-02-28T00:33:11Z – claude-sonnet – shell_pid=4628 – lane=doing – Started review via workflow command
- 2026-02-28T00:35:31Z – claude-sonnet – shell_pid=4628 – lane=planned – Moved to planned
- 2026-02-28T00:37:40Z – claude-sonnet – shell_pid=13964 – lane=doing – Started implementation via workflow command
- 2026-02-28T00:50:28Z – claude-sonnet – shell_pid=13964 – lane=for_review – Addresses review feedback: added missing test files for TransactionNextStepsCalculations (5-step + 6-step paths, allStepsComplete), TransactionCompletenessCalculations (all 4 statuses, subtotal resolution priority, nil/zero returns nil, variance), and ReceiptListParser (standard format, comma prices, no-T flag, empty lines skipped, invalid lines to skippedLines). All 52 tests pass.
- 2026-02-28T00:52:50Z – claude-sonnet – shell_pid=56410 – lane=doing – Started review via workflow command
