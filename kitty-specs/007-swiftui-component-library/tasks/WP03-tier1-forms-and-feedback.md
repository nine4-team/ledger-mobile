---
work_package_id: WP03
title: Tier 1 — Form Sheets & Feedback Components
lane: "doing"
dependencies: [WP01]
base_branch: 007-swiftui-component-library-WP01
base_commit: 125de502fd2f1682240a1147bc6176e85c037cba
created_at: '2026-02-26T08:15:20.994214+00:00'
subtasks:
- T018
- T019
- T020
- T021
- T022
phase: Phase 2 - Tier 1 Components
assignee: ''
agent: "claude-opus"
shell_pid: "75175"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T07:45:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP03 – Tier 1 — Form Sheets & Feedback Components

## IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.
- **You must address all feedback** before your work is complete.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP03 --base WP01
```

---

## Objectives & Success Criteria

- Build 5 Tier 1 components: FormSheet, MultiStepFormSheet, StatusBanner, ErrorRetryView, LoadingScreen
- All components follow bottom-sheet-first convention (CLAUDE.md)
- All components render in SwiftUI previews with all state variants

**Success criteria:**
1. FormSheet presents via `.sheet()` with `.presentationDetents` and `.presentationDragIndicator(.visible)`
2. FormSheet primary button shows loading indicator and disables during async ops
3. StatusBanner supports 3 variants (error, warning, info) with distinct styling
4. ErrorRetryView shows retry button and offline state
5. LoadingScreen centers ProgressView with optional message

---

## Context & Constraints

- **CLAUDE.md convention**: All forms present as bottom sheets. `.sheet()` + `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)`.
- **RN reference**: `src/components/FormBottomSheet.tsx`, `src/components/StatusBanner.tsx`, `src/components/ErrorRetryView.tsx`, `src/components/LoadingScreen.tsx`
- **Existing components**: AppButton (used for FormSheet buttons), Card
- **Type dependency**: FormSheetAction (from WP01)

---

## Subtasks & Detailed Guidance

### Subtask T018 – Create FormSheet component

**Purpose**: Reusable sheet scaffold used by all feature modals (EditItemDetailsModal, SetSpaceModal, etc.). This is the SwiftUI equivalent of RN's FormBottomSheet.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/FormSheet.swift`
2. Parameters:
   - `title: String`
   - `description: String?`
   - `primaryAction: FormSheetAction`
   - `secondaryAction: FormSheetAction?`
   - `error: String?`
   - `content: @ViewBuilder`
3. Layout (VStack):
   - **Header**: Title (Typography.h2) + optional description (Typography.small, secondary)
   - **Content**: ScrollView wrapping the @ViewBuilder content
   - **Error area**: If error is non-nil, red text (StatusColors.missedText) below content
   - **Action buttons**:
     - Primary: AppButton(.primary) with `isLoading` and `isDisabled` from FormSheetAction
     - Secondary (optional): AppButton(.secondary)
   - Padding: Spacing.screenPadding all around
4. **Presentation convention**: This component is the *content* of a `.sheet()`. The presenting view wraps it:
   ```swift
   .sheet(isPresented: $showForm) {
       FormSheet(title: "Edit Item", primaryAction: ...) {
           // form fields
       }
       .presentationDetents([.medium, .large])
       .presentationDragIndicator(.visible)
   }
   ```
5. **Keyboard avoidance**: SwiftUI handles this automatically for TextField inside ScrollView. No custom handling needed.
6. Add `#Preview` block with:
   - Basic form with title + content + primary action
   - Form with error message
   - Form with loading primary button
   - Form with primary + secondary actions

**Files**: `LedgeriOS/LedgeriOS/Components/FormSheet.swift` (new, ~80 lines)
**Parallel?**: Yes.

**Notes**:
- The `.presentationDetents` and `.presentationDragIndicator` go on the *presenting* side, not inside FormSheet itself. FormSheet is just the content view.
- Consider adding a `dismiss` environment action so the secondary button can close the sheet:
  ```swift
  @Environment(\.dismiss) private var dismiss
  ```

### Subtask T019 – Create MultiStepFormSheet component

**Purpose**: Form scaffold with step indicator for multi-step flows (e.g., "Step 2 of 3").

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/MultiStepFormSheet.swift`
2. Parameters:
   - Same as FormSheet plus:
   - `currentStep: Int`
   - `totalSteps: Int`
3. Layout: Same as FormSheet but adds step indicator between title and content:
   - "Step \(currentStep) of \(totalSteps)" (Typography.caption, secondary text)
4. Implementation options:
   - Option A: Compose FormSheet internally, adding the step indicator as part of content
   - Option B: Copy FormSheet layout with step indicator added
   - **Prefer Option A** — compose, don't duplicate
5. Add `#Preview` block with: Step 1 of 3, Step 2 of 3.

**Files**: `LedgeriOS/LedgeriOS/Components/MultiStepFormSheet.swift` (new, ~35 lines)
**Parallel?**: Yes.

### Subtask T020 – Create StatusBanner component

**Purpose**: Sticky notification banner for errors, warnings, and info messages.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/StatusBanner.swift`
2. Parameters:
   - `message: String`
   - `variant: StatusBannerVariant = .error`
   - `autoDismissAfter: TimeInterval?` — optional auto-dismiss duration in seconds
   - `onDismiss: (() -> Void)?`
   - `actions: @ViewBuilder` — optional action buttons
3. Color mapping per variant:
   - `.error`: background `StatusColors.missedBackground`, text `StatusColors.missedText`
   - `.warning`: background `StatusColors.inProgressBackground`, text `StatusColors.inProgressText`
   - `.info`: background `BrandColors.surface`, text `BrandColors.textPrimary`
4. Layout (HStack, inside Card):
   - Icon (SF Symbol: exclamationmark.triangle for error/warning, info.circle for info)
   - Message text (Typography.small, flex)
   - Optional dismiss button (X icon)
   - Optional actions below message
5. Auto-dismiss: If `autoDismissAfter` is set, use `.task { try? await Task.sleep(for: .seconds(duration)); onDismiss?() }`
6. Add `#Preview` block with: error, warning, info, with dismiss button, with actions.

**Files**: `LedgeriOS/LedgeriOS/Components/StatusBanner.swift` (new, ~70 lines)
**Parallel?**: Yes.

**Notes**: The banner should be placed at the top of a screen via `.safeAreaInset(edge: .top)` or `VStack` — the consuming view decides placement.

### Subtask T021 – Create ErrorRetryView component

**Purpose**: Error state display with retry capability and offline indication.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/ErrorRetryView.swift`
2. Parameters:
   - `message: String = "Something went wrong"`
   - `onRetry: (() -> Void)?`
   - `isOffline: Bool = false`
3. Layout (VStack, centered, spacing: Spacing.lg):
   - Icon: SF Symbol "exclamationmark.triangle" (large, secondary color)
   - Message text (Typography.body, secondary, multiline centered)
   - If isOffline: "You appear to be offline" text (Typography.small, tertiary)
   - If onRetry provided: AppButton(.secondary, title: "Try Again", action: onRetry)
4. Center in available space with padding.
5. Add `#Preview` block with: basic error, with retry, offline state.

**Files**: `LedgeriOS/LedgeriOS/Components/ErrorRetryView.swift` (new, ~45 lines)
**Parallel?**: Yes.

### Subtask T022 – Create LoadingScreen component

**Purpose**: Full-screen loading state during initial data fetches.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/LoadingScreen.swift`
2. Parameters:
   - `message: String?`
3. Layout (VStack, centered, spacing: Spacing.md):
   - `ProgressView()` — system activity indicator
   - If message: Text (Typography.small, secondary)
4. Center in available space.
5. Add `#Preview` block with: no message, with message.

**Files**: `LedgeriOS/LedgeriOS/Components/LoadingScreen.swift` (new, ~20 lines)
**Parallel?**: Yes.

---

## Test Strategy

- No pure logic functions in this WP — all UI components.
- Test via SwiftUI previews only.
- Verify FormSheet keyboard avoidance works with real keyboard in preview/simulator.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Keyboard avoidance in FormSheet | SwiftUI handles automatically; verify in simulator |
| StatusBanner auto-dismiss timing | Use Task.sleep; test with short duration in preview |
| FormSheet presentation not looking right | Match `.presentationDetents([.medium, .large])` convention exactly |

---

## Review Guidance

- Verify FormSheet matches CLAUDE.md bottom-sheet convention
- Check StatusBanner variants have distinct visual treatment
- Confirm LoadingScreen centers correctly in various container sizes
- Verify ErrorRetryView offline state renders correctly

---

## Activity Log

- 2026-02-26T07:45:42Z – system – lane=planned – Prompt created.
- 2026-02-26T08:15:21Z – claude-opus – shell_pid=75175 – lane=doing – Assigned agent via workflow command
