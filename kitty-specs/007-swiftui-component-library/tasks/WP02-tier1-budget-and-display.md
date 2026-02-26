---
work_package_id: WP02
title: Tier 1 — Budget & Data Display Components
lane: "doing"
dependencies: [WP01]
base_branch: 007-swiftui-component-library-WP01
base_commit: 125de502fd2f1682240a1147bc6176e85c037cba
created_at: '2026-02-26T08:14:19.166397+00:00'
subtasks:
- T009
- T010
- T011
- T012
- T013
- T014
- T015
- T016
- T017
phase: Phase 2 - Tier 1 Components
assignee: ''
agent: ''
shell_pid: "72276"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T07:45:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP02 – Tier 1 — Budget & Data Display Components

## IMPORTANT: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP02 --base WP01
```

---

## Objectives & Success Criteria

- Build 7 Tier 1 components: BudgetCategoryTracker, BudgetProgressPreview, CategoryRow, ImageCard, SpaceCard, InfoCard, DraggableCard
- Create BudgetTrackerCalculations logic with tests
- All components render correctly in SwiftUI previews (light + dark mode)
- All components use design tokens exclusively (no hardcoded values)

**Success criteria:**
1. 7 component files exist in `Components/`
2. BudgetTrackerCalculations logic file + tests pass
3. Each component has `#Preview` blocks showing key states
4. Visual output matches RN reference screenshots where applicable

---

## Context & Constraints

- **Reference screenshots**: `reference/screenshots/dark/01_projects_list_.png` (BudgetProgressPreview in ProjectCard), `03_project_detail_budget.png` (BudgetCategoryTracker rows), `06_project_detail_spaces.png` (SpaceCard)
- **RN source reference**: `src/components/budget/BudgetCategoryTracker.tsx`, `src/components/budget/BudgetProgressPreview.tsx`, `src/components/budget/CategoryRow.tsx`, `src/components/ImageCard.tsx`, `src/components/SpaceCard.tsx`
- **Existing Tier 0 components**: Card, ProgressBar, SelectorCircle, AppButton (all available)
- **Design tokens**: BrandColors, StatusColors, Spacing, Typography, Dimensions — use these exclusively
- **Pattern**: Follow existing component structure in `Components/Card.swift`, `Components/ProgressBar.swift`
- **Models available**: `BudgetCategory`, `Space`, `AttachmentRef`, `BudgetProgress.CategoryProgress`

---

## Subtasks & Detailed Guidance

### Subtask T009 – Create BudgetTrackerCalculations logic

**Purpose**: Pure formatting functions for BudgetCategoryTracker and BudgetProgressPreview — display names, spent/remaining labels, percentage, overflow detection, fee-type category support.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Logic/BudgetTrackerCalculations.swift`
2. Define `enum BudgetTrackerCalculations` with static functions:
   - `spentLabel(spentCents: Int, categoryType: BudgetCategoryType) -> String`
     - General/itemized: "$X spent"
     - Fee: "$X received"
     - Uses CurrencyFormatting.formatCents() from WP01
   - `remainingLabel(spentCents: Int, budgetCents: Int, categoryType: BudgetCategoryType) -> String`
     - Under budget: "$X remaining"
     - Over budget: "$X over"
     - Fee over: "$X over received"
     - Zero budget: "No budget set"
   - `progressPercentage(spentCents: Int, budgetCents: Int) -> Double`
     - Returns 0–100 range for normal, >100 for overflow
   - `isOverBudget(spentCents: Int, budgetCents: Int) -> Bool`
   - `overflowPercentage(spentCents: Int, budgetCents: Int) -> Double`
     - For ProgressBar overflow fill — percentage of overflow relative to budget

**Files**: `LedgeriOS/LedgeriOS/Logic/BudgetTrackerCalculations.swift` (new, ~50 lines)
**Parallel?**: No — used by T011, T012.

**Notes**: Check existing `BudgetTabCalculations.swift` — it already has `remainingLabel()` and `spentLabel()`. If those are identical, consider reusing them or consolidating. Avoid duplication.

### Subtask T010 – Create BudgetTrackerCalculation tests

**Purpose**: Verify formatting and calculation correctness.

**Steps**:
1. Create `LedgeriOS/LedgeriOSTests/BudgetTrackerCalculationTests.swift`
2. Test cases (~15 tests):
   - `spentLabel`: general "$X spent", fee "$X received", zero
   - `remainingLabel`: under budget, over budget, zero budget, fee variants
   - `progressPercentage`: 0%, 50%, 100%, 150% overflow
   - `isOverBudget`: boundary (equal = not over), just over, zero budget
   - `overflowPercentage`: no overflow → 0, 50% over budget → 50

**Files**: `LedgeriOS/LedgeriOSTests/BudgetTrackerCalculationTests.swift` (new, ~80 lines)
**Parallel?**: No — depends on T009.

### Subtask T011 – Create BudgetCategoryTracker component

**Purpose**: Category-level budget row showing name, spent/remaining amounts, and progress bar with overflow. Used in BudgetProgressDisplay and Budget tab.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/BudgetCategoryTracker.swift`
2. Parameters:
   - `name: String` — category display name
   - `spentCents: Int`
   - `budgetCents: Int`
   - `categoryType: BudgetCategoryType = .general`
3. Layout (VStack, spacing: Spacing.sm):
   - Row 1: category name (Typography.h3) | spent label (Typography.small, secondary text)
   - Row 2: ProgressBar with:
     - `percentage`: from BudgetTrackerCalculations.progressPercentage()
     - `fillColor`: StatusColors based on budget status
     - `overflowPercentage`: from BudgetTrackerCalculations.overflowPercentage()
     - `overflowColor`: StatusColors.overflowBar
   - Row 3: remaining label (Typography.caption, secondary text)
4. Add `#Preview` block with:
   - Under budget (50%)
   - At budget (100%)
   - Over budget (150%)
   - Fee category
   - Zero budget

**Files**: `LedgeriOS/LedgeriOS/Components/BudgetCategoryTracker.swift` (new, ~60 lines)
**Parallel?**: Yes — after T009 logic is ready.

### Subtask T012 – Create BudgetProgressPreview component

**Purpose**: Compact budget preview for ProjectCard — shows pinned category name, spent/remaining, and progress bar.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/BudgetProgressPreview.swift`
2. Parameters:
   - `categoryName: String`
   - `spentCents: Int`
   - `budgetCents: Int`
   - `categoryType: BudgetCategoryType = .general`
3. Layout (HStack + VStack, compact):
   - Category name (Typography.caption, truncated)
   - Spent label (Typography.caption, secondary)
   - Compact ProgressBar (height: 4)
4. Add `#Preview` block showing normal and over-budget states.

**Files**: `LedgeriOS/LedgeriOS/Components/BudgetProgressPreview.swift` (new, ~40 lines)
**Parallel?**: Yes.

**Notes**: This is used inside ProjectCard. Check existing ProjectCard.swift to see if it already has a budget preview section — if so, wire this component in.

### Subtask T013 – Create CategoryRow component

**Purpose**: Single budget category row for settings/management screens.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/CategoryRow.swift`
2. Parameters:
   - `name: String`
   - `categoryType: BudgetCategoryType`
   - `onTap: (() -> Void)?`
3. Layout:
   - HStack: category name (Typography.body) | type badge (Badge with category type label) | chevron if tappable
   - Full-width tap target
4. Add `#Preview` block with general, itemized, and fee types.

**Files**: `LedgeriOS/LedgeriOS/Components/CategoryRow.swift` (new, ~35 lines)
**Parallel?**: Yes.

### Subtask T014 – Create ImageCard component

**Purpose**: Card with async image area and content below. Used by ProjectCard and SpaceCard.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/ImageCard.swift`
2. Parameters:
   - `imageUrl: String?` — URL string for the image
   - `aspectRatio: CGFloat = 16/9` — image area aspect ratio
   - `onPress: (() -> Void)?`
   - `content: @ViewBuilder` — content area below image
3. Layout (VStack, spacing: 0):
   - Image area: `AsyncImage(url:)` with:
     - Placeholder: rounded rect with icon (system image "photo") in BrandColors.textTertiary
     - Loading: same placeholder with ProgressView overlay
     - Error: placeholder with exclamation icon
     - Success: resizable, aspect fill, clipped to aspect ratio
   - Content area: padding Spacing.cardPadding
4. Wrap in Card component for consistent styling.
5. Add `#Preview` block with: no image (placeholder), loading, valid image, error.

**Files**: `LedgeriOS/LedgeriOS/Components/ImageCard.swift` (new, ~70 lines)
**Parallel?**: Yes.

**Notes**: Use `URL(string:)` to convert string to URL. Handle nil gracefully (show placeholder).

### Subtask T015 – Create SpaceCard component

**Purpose**: Space display card with hero image, name, item count, checklist progress, and optional notes.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/SpaceCard.swift`
2. Parameters:
   - `space: Space` — Space model from existing Models/
   - `itemCount: Int`
   - `showNotes: Bool = false`
   - `onPress: () -> Void`
   - `onMenuPress: (() -> Void)?`
3. Layout:
   - ImageCard with primary image URL from `space.images.first(where: { $0.isPrimary == true })?.url`
   - Content area (VStack):
     - HStack: space name (Typography.h3) | menu button (if onMenuPress provided)
     - Item count label (Typography.small, secondary)
     - If checklists exist: ProgressBar showing completion percentage
     - If showNotes && notes exist: notes text (Typography.small, secondary, lineLimit 2)
4. Tap entire card → onPress
5. Add `#Preview` block with: basic space, space with image, space with checklists, space with notes.

**Files**: `LedgeriOS/LedgeriOS/Components/SpaceCard.swift` (new, ~80 lines)
**Parallel?**: Yes.

**Notes**: Checklist progress = total checked items / total items across all checklists. Calculate inline or extract to a simple helper.

### Subtask T016 – Create InfoCard component

**Purpose**: Information display card for contextual help or tips.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/InfoCard.swift`
2. Parameters:
   - `message: String`
   - `icon: String = "info.circle"` — SF Symbol
3. Layout:
   - Card wrapper with HStack:
     - Icon (Image(systemName:), BrandColors.primary, Typography.body)
     - Message text (Typography.small, BrandColors.textSecondary)
4. Background: subtle brand primary tint (BrandColors.primary.opacity(0.08))
5. Add `#Preview` block.

**Files**: `LedgeriOS/LedgeriOS/Components/InfoCard.swift` (new, ~25 lines)
**Parallel?**: Yes.

### Subtask T017 – Create DraggableCard component

**Purpose**: Card with drag handle for reorder operations in settings screens.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/DraggableCard.swift`
2. Parameters:
   - `title: String`
   - `isDisabled: Bool = false`
   - `isActive: Bool = false` — dragging state
   - `rightContent: @ViewBuilder` — optional right-side content
3. Layout:
   - HStack:
     - Drag handle icon ("line.3.horizontal", BrandColors.textTertiary)
     - Title (Typography.body)
     - Spacer
     - Right content
   - Card wrapper
   - Opacity reduced when disabled, elevated when active
4. Add `#Preview` block with: normal, disabled, active states.

**Files**: `LedgeriOS/LedgeriOS/Components/DraggableCard.swift` (new, ~40 lines)
**Parallel?**: Yes.

---

## Test Strategy

- **Framework**: Swift Testing
- **Test file**: `LedgeriOS/LedgeriOSTests/BudgetTrackerCalculationTests.swift`
- **Run command**: `xcodebuild test -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:LedgeriOSTests/BudgetTrackerCalculationTests`
- **Expected**: ~15 tests, all passing
- Components tested via SwiftUI previews (not unit tests) — verify visually

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Duplication with BudgetTabCalculations | Read existing code; reuse or consolidate |
| AsyncImage caching behavior | Rely on URLSession defaults; no custom cache |
| Space checklist progress calculation | Keep inline; extract only if reused elsewhere |

---

## Review Guidance

- Verify all components use design tokens only (no magic numbers)
- Check light/dark mode rendering in previews
- Confirm BudgetCategoryTracker matches `03_project_detail_budget.png` layout
- Verify SpaceCard matches `06_project_detail_spaces.png` layout
- Check that ImageCard handles nil URL gracefully with placeholder

---

## Activity Log

- 2026-02-26T07:45:42Z – system – lane=planned – Prompt created.
