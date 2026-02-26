---
work_package_id: WP07
title: Tier 3 — TransactionCard & Transaction Logic
lane: "doing"
dependencies: [WP01, WP05]
base_branch: 007-swiftui-component-library-WP07-merge-base
base_commit: 8e07d86861297bbc331368eb84d6587257e651ff
created_at: '2026-02-26T08:44:49.341921+00:00'
subtasks:
- T040
- T041
- T042
- T043
phase: Phase 3 - Tier 3 Components
assignee: ''
agent: "claude-opus"
shell_pid: "26989"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T07:45:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP07 – Tier 3 — TransactionCard & Transaction Logic

## IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP07 --base WP05
```

---

## Objectives & Success Criteria

- Build TransactionCard with full badge system
- Create TransactionCardCalculations logic with tests
- Add transaction badge colors to StatusColors if missing
- TransactionCard supports all badge variants, selection, menu

**Success criteria:**
1. TransactionCard matches `05_project_detail_transactions.png` layout
2. All transaction type badges render with correct colors
3. TransactionCardCalculation tests pass
4. Selection and menu integration works (same pattern as ItemCard)

---

## Context & Constraints

- **Reference screenshot**: `reference/screenshots/dark/05_project_detail_transactions.png`
- **RN source**: `src/components/TransactionCard.tsx`
- **Research**: R7 (transaction badge colors — may need StatusColors additions)
- **Existing types**: Transaction model (`Models/Transaction.swift`), AttachmentRef
- **Existing StatusColors**: Has `badgeSuccess`, `badgeInfo`, `badgeWarning`, `badgeError`, `badgeNeedsReview`
- **Prerequisites**: ActionMenuSheet (WP05), SelectorCircle (existing), Badge (existing)

---

## Subtasks & Detailed Guidance

### Subtask T040 – Check and extend StatusColors for transaction badges

**Purpose**: Ensure all transaction badge colors exist in StatusColors.

**Steps**:
1. Read `LedgeriOS/LedgeriOS/Theme/StatusColors.swift`
2. Check for existing badge colors: `badgeSuccess`, `badgeInfo`, `badgeWarning`, `badgeError`, `badgeNeedsReview`
3. Map transaction types to colors:
   - Purchase → badgeSuccess (green) — likely exists
   - Sale → badgeInfo (blue) — likely exists
   - Return → badgeError (red) — likely exists
   - To-inventory → BrandColors.primary (taupe) — use directly
   - Reimbursement → badgeWarning (amber) — likely exists
   - Needs review → badgeNeedsReview (orange) — likely exists
   - Email receipt → badgeWarning (amber) — reuse
4. If any are missing, add them to StatusColors.swift with adaptive colorsets in `Assets.xcassets/Colors/`:
   - Create colorset JSON files for light/dark variants
   - Add static properties to StatusColors
5. If all exist already, document the mapping and move on (no changes needed).

**Files**: `LedgeriOS/LedgeriOS/Theme/StatusColors.swift` (edit, if needed), `Assets.xcassets/Colors/` (new colorsets, if needed)
**Parallel?**: Yes — independent of logic/component work.

**Notes**: Per R7 research, most badge colors likely already exist. Verify before adding.

### Subtask T041 – Create TransactionCardCalculations logic

**Purpose**: Pure functions for transaction type badge colors, amount formatting, and date formatting.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Logic/TransactionCardCalculations.swift`
2. Define `enum TransactionCardCalculations` with static functions:
   - `badgeItems(transactionType: String?, reimbursementType: String?, hasEmailReceipt: Bool, needsReview: Bool, budgetCategoryName: String?, status: String?) -> [(text: String, color: Color)]`
     - Returns array of (text, color) tuples for each applicable badge
     - Transaction type: "Purchase" (green), "Sale" (blue), "Return" (red), "To Inventory" (primary)
     - Reimbursement: "Owed to Client" or "Owed to Company" (amber)
     - Email receipt: "Receipt" (amber)
     - Needs review: "Needs Review" (orange)
     - Category: budget category name (secondary)
     - Status: "Pending"/"Completed"/"Canceled" with appropriate colors
   - `formattedAmount(amountCents: Int?, transactionType: String?) -> String`
     - Uses CurrencyFormatting.formatCents()
     - Adds sign: purchase/to-inventory → negative prefix, sale/return → positive prefix
     - Nil → "—"
   - `formattedDate(_ dateString: String?) -> String`
     - ISO date string → "MMM d, yyyy" format
     - Nil → "—"
   - `truncatedNotes(_ notes: String?, maxLength: Int = 100) -> String?`
     - Returns nil if notes is nil or empty
     - Truncates with "..." if over maxLength

**Files**: `LedgeriOS/LedgeriOS/Logic/TransactionCardCalculations.swift` (new, ~70 lines)
**Parallel?**: No — used by T043.

### Subtask T042 – Create TransactionCardCalculation tests

**Purpose**: Verify badge generation, amount formatting, and date formatting.

**Steps**:
1. Create `LedgeriOS/LedgeriOSTests/TransactionCardCalculationTests.swift`
2. Test cases (~15 tests):
   - `badgeItems`: purchase only → 1 badge, purchase + reimbursement + receipt + review → 4 badges, all nil → empty
   - `formattedAmount`: positive → "+$X", negative → "-$X", nil → "—", zero → "$0"
   - `formattedDate`: valid ISO → "Feb 25, 2026", nil → "—", invalid → "—"
   - `truncatedNotes`: short → full text, long → truncated, nil → nil, empty → nil

**Files**: `LedgeriOS/LedgeriOSTests/TransactionCardCalculationTests.swift` (new, ~80 lines)
**Parallel?**: No — depends on T041.

### Subtask T043 – Create TransactionCard component

**Purpose**: Transaction list item with source, amount, date, badge row, selection, and context menu.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/TransactionCard.swift`
2. Parameters:
   - `id: String`
   - `source: String`
   - `amountCents: Int?`
   - `transactionDate: String?`
   - `notes: String?`
   - `budgetCategoryName: String?`
   - `transactionType: String?`
   - `needsReview: Bool = false`
   - `reimbursementType: String?`
   - `hasEmailReceipt: Bool = false`
   - `status: String?`
   - Selection: `isSelected: Binding<Bool>? = nil`, `defaultSelected: Bool = false`
   - `bookmarked: Bool = false`
   - `onBookmarkPress: (() -> Void)?`
   - `menuItems: [ActionMenuItem] = []`
   - `onPress: (() -> Void)?`
3. State:
   - `@State private var internalSelected: Bool`
   - `@State private var showMenu = false`
   - `@State private var menuPendingAction: (() -> Void)?`
4. Layout (Card wrapper):
   - **Badge row**: HStack of Badge components from TransactionCardCalculations.badgeItems()
   - **Main content** (HStack):
     - SelectorCircle (if isSelected binding provided)
     - **Info** (VStack, flex):
       - Source (Typography.body, bold)
       - Date (Typography.small, secondary) — formatted via TransactionCardCalculations
       - Amount (Typography.h3) — formatted with sign
     - **Right** (VStack):
       - Bookmark toggle
       - Menu button → ActionMenuSheet
   - **Notes preview** (if notes): italic, lineLimit(2), Typography.small, secondary
5. Same selection and menu patterns as ItemCard (controlled/uncontrolled, deferred action).
6. Add `#Preview` block with:
   - Minimal (source + amount)
   - Full (all badges, notes, bookmarked)
   - Selected state

**Files**: `LedgeriOS/LedgeriOS/Components/TransactionCard.swift` (new, ~130 lines)
**Parallel?**: No — depends on T041, T040.

---

## Test Strategy

- **Framework**: Swift Testing
- **Test file**: `LedgeriOS/LedgeriOSTests/TransactionCardCalculationTests.swift`
- **Run command**: `xcodebuild test -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:LedgeriOSTests/TransactionCardCalculationTests`
- **Expected**: ~15 tests, all passing

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Missing StatusColors for badges | Check first; add only what's missing |
| Date formatting locale issues | Use DateFormatter with fixed en_US_POSIX for ISO parsing |
| Transaction type string matching | Use Transaction model's enum if available; fall back to string comparison |

---

## Review Guidance

- Compare TransactionCard with `05_project_detail_transactions.png`
- Verify all badge types render with correct colors
- Test amount formatting with positive, negative, zero, nil
- Confirm date formatting handles various ISO formats

---

## Activity Log

- 2026-02-26T07:45:42Z – system – lane=planned – Prompt created.
- 2026-02-26T08:44:49Z – claude-opus – shell_pid=26989 – lane=doing – Assigned agent via workflow command
