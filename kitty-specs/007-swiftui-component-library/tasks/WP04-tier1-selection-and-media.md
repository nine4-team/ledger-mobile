---
work_package_id: WP04
title: Tier 1 — Selection, Controls & Media Components
lane: "doing"
dependencies: [WP01]
base_branch: 007-swiftui-component-library-WP01
base_commit: 125de502fd2f1682240a1147bc6176e85c037cba
created_at: '2026-02-26T08:14:59.207221+00:00'
subtasks:
- T023
- T024
- T025
- T026
- T027
- T028
phase: Phase 2 - Tier 1 Components
assignee: ''
agent: "claude-opus"
shell_pid: "73972"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T07:45:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP04 – Tier 1 — Selection, Controls & Media Components

## IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check the `review_status` field above.

---

## Review Feedback

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP04 --base WP01
```

---

## Objectives & Success Criteria

- Build 4 Tier 1 components: BulkSelectionBar, ListStateControls, ThumbnailGrid, ImageGallery
- Create MediaGalleryCalculations logic with tests
- ImageGallery supports pinch-to-zoom and swipe navigation
- BulkSelectionBar uses `.safeAreaInset(edge: .bottom)` placement pattern

**Success criteria:**
1. BulkSelectionBar appears/disappears with smooth animation
2. ThumbnailGrid renders configurable column layout
3. ImageGallery supports pinch-to-zoom and swipe between images
4. MediaGalleryCalculation tests pass

---

## Context & Constraints

- **Research decisions**: R3 (ImageGallery gestures), R4 (BulkSelectionBar placement)
- **RN reference**: `src/components/BulkSelectionBar.tsx`, `src/components/ListStateControls.tsx`, `src/components/ThumbnailGrid.tsx`, `src/components/ImageGallery.tsx`
- **Screenshots**: `09_item_detail.png` (ThumbnailGrid in Images section)
- **Existing types**: AttachmentRef (from `Models/Shared/AttachmentRef.swift`)
- **Convention exception**: ImageGallery uses `.fullScreenCover()` — justified exception per spec and CLAUDE.md

---

## Subtasks & Detailed Guidance

### Subtask T023 – Create MediaGalleryCalculations logic

**Purpose**: Pure functions for attachment validation and grid layout calculation.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Logic/MediaGalleryCalculations.swift`
2. Define `enum MediaGalleryCalculations` with static functions:
   - `canAddAttachment(current: [AttachmentRef], maxAttachments: Int) -> Bool`
   - `isAllowedKind(_ kind: AttachmentKind, allowedKinds: [AttachmentKind]) -> Bool`
   - `primaryImage(_ attachments: [AttachmentRef]) -> AttachmentRef?` — finds first with `isPrimary == true`, falls back to first image
   - `gridColumns(for count: Int, preferredColumns: Int = 3) -> Int` — returns actual column count (min 1, max preferredColumns)
   - `thumbnailCount(_ attachments: [AttachmentRef]) -> Int` — count of image-type attachments

**Files**: `LedgeriOS/LedgeriOS/Logic/MediaGalleryCalculations.swift` (new, ~35 lines)
**Parallel?**: No — used by T027.

### Subtask T024 – Create MediaGalleryCalculation tests

**Purpose**: Validate attachment validation and grid layout logic.

**Steps**:
1. Create `LedgeriOS/LedgeriOSTests/MediaGalleryCalculationTests.swift`
2. Test cases (~10 tests):
   - `canAddAttachment`: under limit → true, at limit → false, empty → true
   - `isAllowedKind`: image in [image, pdf] → true, pdf in [image] → false
   - `primaryImage`: with primary → returns it, no primary → returns first, empty → nil
   - `gridColumns`: 0 items → 1, 1 item → 1, 3 items → 3, 10 items → 3 (capped)
   - `thumbnailCount`: mixed types → only counts images

**Files**: `LedgeriOS/LedgeriOSTests/MediaGalleryCalculationTests.swift` (new, ~60 lines)
**Parallel?**: No — depends on T023.

### Subtask T025 – Create BulkSelectionBar component

**Purpose**: Fixed bottom bar for bulk operations — shows selected count, optional total amount, action button, clear button.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/BulkSelectionBar.swift`
2. Parameters:
   - `selectedCount: Int`
   - `totalCents: Int?` — optional total amount of selected items
   - `actionLabel: String = "Actions"`
   - `onBulkActions: () -> Void`
   - `onClear: () -> Void`
3. Layout (HStack, padded):
   - Left: "\(selectedCount) selected" (Typography.body, bold) + optional "(\(CurrencyFormatting.formatCents(totalCents)))" (Typography.small)
   - Right: Clear button ("xmark.circle", secondary) | Action button (AppButton, primary, compact)
4. Background: BrandColors.surface with top border (BrandColors.border)
5. **Placement pattern** (used by consuming views, not this component):
   ```swift
   List { ... }
       .safeAreaInset(edge: .bottom) {
           if selectedCount > 0 {
               BulkSelectionBar(...)
                   .transition(.move(edge: .bottom))
           }
       }
       .animation(.default, value: selectedCount > 0)
   ```
6. Add `#Preview` block with: 1 selected, 5 selected with total, 20 selected.

**Files**: `LedgeriOS/LedgeriOS/Components/BulkSelectionBar.swift` (new, ~55 lines)
**Parallel?**: Yes.

### Subtask T026 – Create ListStateControls component

**Purpose**: Search input field that toggles visibility with animation.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/ListStateControls.swift`
2. Parameters:
   - `searchText: Binding<String>`
   - `isSearchVisible: Bool`
   - `placeholder: String = "Search..."`
3. Layout:
   - When `isSearchVisible`:
     - HStack: magnifyingglass icon | TextField | clear button (X) when text non-empty
     - Background: BrandColors.inputBackground, corner radius: Dimensions.inputRadius
     - Padding: Spacing.sm
   - Animate show/hide with `.transition(.move(edge: .top).combined(with: .opacity))`
4. Add `#Preview` block with: visible empty, visible with text, hidden.

**Files**: `LedgeriOS/LedgeriOS/Components/ListStateControls.swift` (new, ~50 lines)
**Parallel?**: Yes.

### Subtask T027 – Create ThumbnailGrid component

**Purpose**: Grid of image thumbnails with overlay badges and tap interaction.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/ThumbnailGrid.swift`
2. Parameters:
   - `attachments: [AttachmentRef]`
   - `columns: Int = 3`
   - `showPrimaryBadge: Bool = true`
   - `onThumbnailTap: ((Int) -> Void)?` — index of tapped thumbnail
3. Layout:
   - `LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: columns))`
   - Each cell:
     - `AsyncImage(url:)` with aspect fill, clipped to square
     - Corner radius: Dimensions.cardRadius / 2
     - If primary and showPrimaryBadge: star badge overlay (top-left)
     - Tappable → onThumbnailTap(index)
4. Add `#Preview` block with: 1 image, 3 images with primary, 6+ images, empty.

**Files**: `LedgeriOS/LedgeriOS/Components/ThumbnailGrid.swift` (new, ~65 lines)
**Parallel?**: Yes.

### Subtask T028 – Create ImageGallery component

**Purpose**: Full-screen image viewer with swipe navigation and pinch-to-zoom. Justified `.fullScreenCover()` exception.

**Steps**:
1. Create `LedgeriOS/LedgeriOS/Components/ImageGallery.swift`
2. Parameters:
   - `images: [AttachmentRef]`
   - `initialIndex: Int = 0`
   - `isPresented: Binding<Bool>`
3. Layout:
   - `TabView(selection: $currentIndex)` with `.tabViewStyle(.page(indexDisplayMode: .automatic))`
   - Each page: `ZoomableImage` (internal view)
   - Close button (top-right): X icon, taps set `isPresented = false`
   - Page indicator dots at bottom
4. Internal `ZoomableImage` view:
   - `AsyncImage(url:)` filling available space
   - `@GestureState private var magnification: CGFloat = 1.0`
   - `@State private var steadyStateMagnification: CGFloat = 1.0`
   - `@GestureState private var dragOffset: CGSize = .zero`
   - `MagnificationGesture` for pinch-to-zoom (min 1, max 4)
   - `DragGesture` for panning when zoomed
   - Double-tap: toggle between 1x and 2x zoom
5. **Presentation** (used by consuming views):
   ```swift
   .fullScreenCover(isPresented: $showGallery) {
       ImageGallery(images: attachments, initialIndex: tappedIndex, isPresented: $showGallery)
   }
   ```
6. Add `#Preview` block with: single image, multiple images.

**Files**: `LedgeriOS/LedgeriOS/Components/ImageGallery.swift` (new, ~120 lines)
**Parallel?**: Yes (but most complex in this WP).

**Notes**:
- Keep gesture implementation simple initially. MagnificationGesture + DragGesture compose with `.simultaneously()`.
- Double-tap: use `.onTapGesture(count: 2)` to toggle between 1x and 2x.
- Reset zoom when swiping to a different image: use `.onChange(of: currentIndex)` to reset scale.

---

## Test Strategy

- **Framework**: Swift Testing
- **Test file**: `LedgeriOS/LedgeriOSTests/MediaGalleryCalculationTests.swift`
- **Run command**: `xcodebuild test -scheme LedgeriOS -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:LedgeriOSTests/MediaGalleryCalculationTests`
- **Expected**: ~10 tests, all passing
- Components tested via SwiftUI previews — ImageGallery gestures verified in simulator

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| ImageGallery gesture conflicts | Use `.simultaneously()` for compose; test in simulator |
| TabView swipe conflicts with drag gesture | Only enable drag when zoomed (scale > 1) |
| AsyncImage performance in grid | LazyVGrid handles lazy loading; keep cell count reasonable |

---

## Review Guidance

- Test ImageGallery pinch-to-zoom in simulator (not just preview)
- Verify BulkSelectionBar animation is smooth (`.transition(.move(edge: .bottom))`)
- Check ThumbnailGrid with varying image counts (1, 3, 6, 9+)
- Confirm ListStateControls search toggle animation

---

## Activity Log

- 2026-02-26T07:45:42Z – system – lane=planned – Prompt created.
- 2026-02-26T08:14:59Z – claude-opus – shell_pid=73972 – lane=doing – Assigned agent via workflow command
