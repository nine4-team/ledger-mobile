---
work_package_id: WP01
title: Shared Types & Currency Formatting
lane: "done"
dependencies: []
base_branch: main
base_commit: 5058235f35ebbcd1fff842c102589b10266ba62e
created_at: '2026-02-26T07:57:47.624473+00:00'
subtasks:
- T001
- T002
- T003
- T004
- T005
- T006
- T007
- T008
phase: Phase 1 - Foundation
assignee: ''
agent: "claude-opus"
shell_pid: "65768"
review_status: "approved"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-26T07:45:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP01 – Shared Types & Currency Formatting

## IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.

---

## Review Feedback

*[This section is empty initially. Reviewers will populate it if the work is returned from review.]*

---

## Implementation Command

```bash
spec-kitty implement WP01
```

No dependencies — this is the starting package.

---

## Objectives & Success Criteria

- Define all new shared types needed by downstream components: ActionMenuItem, ControlAction, FormSheetAction, StatusBannerVariant, ItemFilterOption, ItemSortOption, ItemsListMode
- Create shared CurrencyFormatting utility with locale-aware formatting
- All new types compile cleanly as part of the LedgeriOS target
- CurrencyFormatting tests pass (Swift Testing framework)

**Success criteria:**
1. All 6 type files exist and compile
2. CurrencyFormatting logic file exists with `formatCents()` function
3. CurrencyFormattingTests pass with 100% coverage of edge cases
4. No duplication with existing `BudgetDisplayCalculations.formatCentsAsDollars()`

---

## Context & Constraints

- **Spec**: `kitty-specs/007-swiftui-component-library/spec.md`
- **Data model**: `kitty-specs/007-swiftui-component-library/data-model.md` — defines exact type interfaces
- **Plan**: `kitty-specs/007-swiftui-component-library/plan.md`
- **Existing patterns**: All models use `Codable`, `Identifiable`, `Hashable` conformances. See `LedgeriOS/LedgeriOS/Models/` for conventions.
- **Logic pattern**: Use `enum XxxCalculations` with static functions (see `Logic/BudgetDisplayCalculations.swift`).
- **Testing**: Swift Testing framework (`@Suite`, `@Test`, `#expect`) — see `LedgeriOSTests/BudgetDisplayCalculationTests.swift` for pattern.
- **File locations**:
  - Types: `LedgeriOS/LedgeriOS/Models/Shared/`
  - Logic: `LedgeriOS/LedgeriOS/Logic/`
  - Tests: `LedgeriOS/LedgeriOSTests/`

---

## Subtasks & Detailed Guidance

### Subtask T001 – Create ActionMenuItem and ActionMenuSubitem types

**Purpose**: Define the data structures for ActionMenuSheet menu items — used by ActionMenuSheet, FilterMenu, SortMenu, ItemCard, TransactionCard, MediaGallerySection, SharedItemsList, SharedTransactionsList.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Models/Shared/ActionMenuItem.swift`
2. Define `ActionMenuItem: Identifiable` with:
   - `id: String` — unique key
   - `label: String` — display text
   - `icon: String?` — SF Symbol name
   - `subactions: [ActionMenuSubitem]?` — child items
   - `selectedSubactionKey: String?` — currently selected child key
   - `isDestructive: Bool = false` — red styling
   - `isActionOnly: Bool = false` — execute immediately, no subactions
   - `onPress: (() -> Void)?` — action handler (optional because submenu items handle their own presses)
3. Define `ActionMenuSubitem: Identifiable` with:
   - `id: String` — unique key
   - `label: String`
   - `icon: String?` — SF Symbol name
   - `onPress: () -> Void`

**Files**: `LedgeriOS/LedgeriOS/Models/Shared/ActionMenuItem.swift` (new, ~30 lines)
**Parallel?**: Yes — independent file.

**Notes**:
- Cannot conform to `Codable` or `Hashable` because `onPress` closures aren't serializable. Only conform to `Identifiable`.
- `id` is `String` (not UUID) — matches the RN `key` convention for stable identification in menus.

### Subtask T002 – Create ControlAction type

**Purpose**: Define button configuration for ListControlBar and ItemsListControlBar.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Models/Shared/ControlAction.swift`
2. Define `ControlAction: Identifiable` with:
   - `id: String`
   - `title: String`
   - `variant: AppButtonVariant = .secondary` — reuse existing AppButtonVariant enum
   - `icon: String?` — SF Symbol name
   - `isDisabled: Bool = false`
   - `isActive: Bool = false`
   - `appearance: ControlActionAppearance = .standard`
   - `accessibilityLabel: String?`
   - `action: () -> Void`
3. Define `ControlActionAppearance` enum:
   - `.standard` — text + optional icon button
   - `.iconOnly` — fixed-size icon button
   - `.tile` — dashed-border icon square

**Files**: `LedgeriOS/LedgeriOS/Models/Shared/ControlAction.swift` (new, ~25 lines)
**Parallel?**: Yes — independent file.

**Notes**: Check that `AppButtonVariant` is accessible from AppButton.swift. If it's defined privately, it may need to be extracted.

### Subtask T003 – Create FormSheetAction type

**Purpose**: Define action button configuration for FormSheet and MultiStepFormSheet.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Models/Shared/FormSheetAction.swift`
2. Define `FormSheetAction` struct with:
   - `title: String`
   - `isLoading: Bool = false`
   - `isDisabled: Bool = false`
   - `action: () -> Void`

**Files**: `LedgeriOS/LedgeriOS/Models/Shared/FormSheetAction.swift` (new, ~10 lines)
**Parallel?**: Yes — independent file.

### Subtask T004 – Create StatusBannerVariant enum

**Purpose**: Define variant types for StatusBanner component.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Models/Shared/StatusBannerVariant.swift`
2. Define `StatusBannerVariant` enum: `.error`, `.warning`, `.info`

**Files**: `LedgeriOS/LedgeriOS/Models/Shared/StatusBannerVariant.swift` (new, ~8 lines)
**Parallel?**: Yes — independent file.

### Subtask T005 – Create ItemFilterOption and ItemSortOption enums

**Purpose**: Define filter and sort options for SharedItemsList and related components.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Models/Shared/ItemListEnums.swift`
2. Define `ItemFilterOption: String, CaseIterable`:
   - `.all`, `.bookmarked`, `.fromInventory = "from-inventory"`, `.toReturn = "to-return"`, `.returned`, `.noSku = "no-sku"`, `.noName = "no-name"`, `.noProjectPrice = "no-project-price"`, `.noImage = "no-image"`, `.noTransaction = "no-transaction"`
3. Define `ItemSortOption: String, CaseIterable`:
   - `.createdDesc = "created-desc"`, `.createdAsc = "created-asc"`, `.alphabeticalAsc = "alphabetical-asc"`, `.alphabeticalDesc = "alphabetical-desc"`

**Files**: `LedgeriOS/LedgeriOS/Models/Shared/ItemListEnums.swift` (new, ~25 lines)
**Parallel?**: Yes — independent file.

**Notes**: Raw values match the RN string constants for consistency across platforms.

### Subtask T006 – Create ItemsListMode enum

**Purpose**: Define the three operating modes for SharedItemsList.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Models/Shared/ItemsListMode.swift`
2. Define `ItemsListMode` enum:
   - `.standalone(scopeConfig: ScopeConfig)` — Note: `ScopeConfig` may need definition or alias to existing `ListScope`
   - `.embedded(items: [ScopedItem], onItemPress: (String) -> Void)`
   - `.picker(eligibilityCheck: ((ScopedItem) -> Bool)?, onAddSingle: ((ScopedItem) -> Void)?, addedIds: Set<String>, onAddSelected: (() -> Void)?)`

**Files**: `LedgeriOS/LedgeriOS/Models/Shared/ItemsListMode.swift` (new, ~20 lines)
**Parallel?**: Yes — independent file.

**Notes**:
- Check if `ScopedItem` exists in the codebase. The RN app uses it as Item enriched with project context. If it doesn't exist, check whether plain `Item` suffices or if a type alias / wrapper is needed.
- Check if `ScopeConfig` maps to the existing `ListScope` enum in `Logic/ScopeFilters.swift`. If so, use `ListScope` directly.

### Subtask T007 – Create CurrencyFormatting logic

**Purpose**: Shared cents-to-dollar formatting used by BudgetCategoryTracker, TransactionCard, BulkSelectionBar, and others.

**Steps**:
1. Read `LedgeriOS/LedgeriOS/Logic/BudgetDisplayCalculations.swift` — check existing `formatCentsAsDollars()` and `formatCentsWithDecimals()`.
2. Evaluate: If the existing functions are general-purpose enough, create `CurrencyFormatting` as a thin re-export/delegate. If they're budget-specific, create independent implementations.
3. Create `LedgeriOS/LedgeriOS/Logic/CurrencyFormatting.swift`
4. Define `enum CurrencyFormatting` with static functions:
   - `formatCents(_ cents: Int) -> String` — e.g., 15000 → "$150" (no decimals when whole)
   - `formatCentsWithDecimals(_ cents: Int) -> String` — e.g., 15099 → "$150.99"
   - `formatCentsCompact(_ cents: Int) -> String` — e.g., 150000 → "$1.5K" (for large amounts in compact spaces)
5. Use `NumberFormatter` for locale-aware formatting where possible.

**Files**: `LedgeriOS/LedgeriOS/Logic/CurrencyFormatting.swift` (new, ~40 lines)
**Parallel?**: No — must read existing code first.

**Notes**:
- Prefer delegating to existing BudgetDisplayCalculations if formats match. Avoid duplication.
- If BudgetDisplayCalculations is general enough, consider making CurrencyFormatting simply call through to it.

### Subtask T008 – Create CurrencyFormatting tests

**Purpose**: Validate formatting edge cases: zero, negative, large amounts, decimal precision.

**Steps**:
1. Create `LedgeriOS/LedgeriOSTests/CurrencyFormattingTests.swift`
2. Use Swift Testing framework pattern:
   ```swift
   import Testing
   @testable import LedgeriOS

   @Suite("CurrencyFormatting")
   struct CurrencyFormattingTests {
       @Test("formatCents with zero")
       func formatCentsZero() {
           #expect(CurrencyFormatting.formatCents(0) == "$0")
       }
       // ... more tests
   }
   ```
3. Test cases (~10 tests):
   - Zero cents → "$0"
   - Positive whole dollar (15000 → "$150")
   - Positive with cents (15099 → "$150.99" for decimals variant)
   - Negative amounts (-5000 → "-$50")
   - Large amounts (1000000 → "$10,000")
   - Single cent (1 → "$0.01" for decimals variant)

**Files**: `LedgeriOS/LedgeriOSTests/CurrencyFormattingTests.swift` (new, ~60 lines)
**Parallel?**: No — depends on T007.

---

## Test Strategy

- **Framework**: Swift Testing (`@Suite`, `@Test`, `#expect`)
- **Location**: `LedgeriOS/LedgeriOSTests/CurrencyFormattingTests.swift`
- **Run command**: `xcodebuild test -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:LedgeriOSTests/CurrencyFormattingTests`
- **Expected**: ~10 tests, all passing
- Types (T001–T006) don't need tests — they're pure data structures with no logic.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| CurrencyFormatting duplicates BudgetDisplayCalculations | Read existing code first; delegate or re-export |
| ScopedItem type may not exist | Check codebase; create type alias if needed |
| AppButtonVariant may be private | Extract to shared location if needed |

---

## Review Guidance

- Verify all types match the interfaces defined in `data-model.md`
- Confirm CurrencyFormatting doesn't duplicate existing functions
- Check that enums have correct raw values matching RN string constants
- Verify Swift Testing pattern matches existing test files

---

## Activity Log

- 2026-02-26T07:45:42Z – system – lane=planned – Prompt created.
- 2026-02-26T07:57:47Z – claude-opus – shell_pid=50971 – lane=doing – Assigned agent via workflow command
- 2026-02-26T08:08:26Z – claude-opus – shell_pid=50971 – lane=for_review – Ready for review: 6 shared type files, CurrencyFormatting logic with compact format, 16 tests passing. Uses Item directly (no ScopedItem wrapper needed), delegates to existing BudgetDisplayCalculations to avoid duplication.
- 2026-02-26T08:08:47Z – claude-opus – shell_pid=65768 – lane=doing – Started review via workflow command
- 2026-02-26T08:13:42Z – claude-opus – shell_pid=65768 – lane=done – Review passed: All 6 type files match data-model.md, CurrencyFormatting correctly delegates to BudgetDisplayCalculations, 16/16 tests pass, full build succeeds. Good adaptations: ScopeConfig→ListScope, ScopedItem→Item.
