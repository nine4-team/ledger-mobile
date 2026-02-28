---
work_package_id: WP08
title: Session 4 Screens – Spaces Tab + Space Detail + Modals
lane: "doing"
dependencies:
- WP06
base_branch: 008-phase-4-screens-implementation-WP06
base_commit: 85c5f7a38ca0c3971640237a96a16797619ecd80
created_at: '2026-02-28T22:37:46.865153+00:00'
subtasks:
- T039
- T040
- T041
- T042
phase: Phase 4 - Session 4
assignee: ''
agent: "claude-opus"
shell_pid: "38079"
review_status: "has_feedback"
reviewed_by: "nine4-team"
history:
- timestamp: '2026-02-26T22:30:00Z'
  lane: planned
  agent: system
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP08 – Session 4 Screens — Spaces Tab + Space Detail + Modals

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

**Reviewed by**: nine4-team
**Status**: ❌ Changes Requested
**Date**: 2026-02-28

## Review Feedback — WP08

**Reviewer:** claude-opus

### Issue 1 (MUST FIX): EditChecklistModal missing `.onMove` reorder support

The spec explicitly requires drag-to-reorder for checklist items:

> "Drag handle for reordering: `.onMove { indices, destination in ... }` in edit mode."
> "Use `List` with `.onMove` for reorder drag handles — requires `EditButton` or toggling `.environment(\.editMode, .constant(.active))`."

The current `EditChecklistModal.swift` uses `ForEach` within a `VStack` but has no `.onMove` modifier — neither for reordering checklists relative to each other, nor for reordering items within a checklist.

**How to fix:**
1. Wrap the checklist items `ForEach` in a `List` (or use `ForEach` with `.onMove`) 
2. Add `.onMove { indices, destination in ... }` that mutates `checklist.wrappedValue.items.move(fromOffsets:toOffset:)`
3. Set `.environment(\.editMode, .constant(.active))` on the list section to show drag handles, or use an `EditButton`
4. Optionally also support reordering the top-level checklists themselves

### Issue 2 (MINOR — Optional): SpaceCard checklist progress text

The spec mentions "checklist progress (as text 'X of Y' or fraction for a progress bar)". The SpaceCard renders a `ProgressBar` (good) but no textual label. Consider adding a small "X/Y" text label next to or below the progress bar for accessibility/clarity. This is a nice-to-have, not a blocker.

### Everything else: PASS

- SpacesTabView: All 6 requirements pass — correct data sourcing, archive filtering, search, SpaceCard rendering, NavigationLink pattern, LazyVStack
- SpaceDetailView: All 13 requirements pass — 4 collapsible sections with correct defaults, Media/Notes/Items/Checklists all wired correctly, role-gated template stub, action menu, delete confirmation, optimistic checklist toggling
- EditSpaceDetailsModal: All 4 requirements pass — correct sheet presentation, name/notes fields, validation, save/dismiss
- EditChecklistModal: 7 of 8 pass — add/remove/check items all work, add checklist works, save/dismiss works. Only reorder is missing.
- All types and dependencies confirmed to exist with correct signatures
- Architecture follows CLAUDE.md patterns (bottom sheets, @Observable, NavigationLink(value:), theme tokens)
- Sheet-on-sheet sequencing correctly uses onDismiss pattern


## Objectives & Success Criteria

- `SpacesTabView` replaces placeholder; shows real space cards with name, item count, and checklist progress.
- `SpaceDetailView` has 4 collapsible sections (Media expanded, others collapsed); full items list with `ItemsListControlBar` + 10 filter modes; "Save as Template" role-gated.
- Checklist editing via `EditChecklistModal` works (add/remove/reorder/check) with optimistic Firestore updates.
- Navigation from spaces tab → space detail → back works.

**To start implementing:** `spec-kitty implement WP08 --base WP06`

---

## Context & Constraints

- **Refs**: `plan.md` (WP08), `spec.md` FR-9.
- **Section defaults** (FR-9.3): Media=expanded, Notes=collapsed, Items=collapsed, Checklists=collapsed.
- **Space Detail Items section** (FR-9.10): full 10 project-scope filter modes from `ItemListCalculations`.
- **"Save as Template"** (FR-9.8): owner/admin only; creates a `SpaceTemplate` via `SpaceTemplatesService`. Since `SpaceTemplatesService` is built in WP13, stub it here: call `SpaceTemplatesService.create()` if it exists, otherwise show a "Coming soon" toast.
- **`EditNotesModal`**: reuse from WP04. Just wire it in.
- **Checklist reorder**: SwiftUI `.onMove` modifier in edit mode. Persist new order to Firestore optimistically after drop.
- **`SharedItemsList` embedded mode**: already fixed in WP06 — reuse here for the Items section.

---

## Subtasks & Detailed Guidance

### Subtask T039 – Create `Views/Projects/SpacesTabView.swift`

**Purpose**: Replace `SpacesTabPlaceholder.swift` with a real space card list.

**Steps**:
1. Create `Views/Projects/SpacesTabView.swift`.
2. Source spaces from `projectContext.spaces` and items from `projectContext.items`.
3. Call `SpaceListCalculations.buildSpaceCards(spaces:items:)` → sort → optionally search.
4. Render each `SpaceCardData` using a `SpaceCard` component (Phase 5). Pass: space name, item count, checklist progress (as text "X of Y" or fraction for a progress bar).
5. Add button in toolbar → present `NewSpaceView` (stub for WP12).
6. Search: optional search bar using `SpaceListCalculations.applySearch()`.
7. `NavigationLink(value: space)` + `.navigationDestination(for: Space.self)` → `SpaceDetailView`.

**Files**:
- `Views/Projects/SpacesTabView.swift` (create, ~80 lines)

---

### Subtask T040 – Create `Views/Projects/SpaceDetailView.swift`

**Purpose**: Full space detail screen with 4 collapsible sections and role-gated "Save as Template".

**Steps**:
1. Create `Views/Projects/SpaceDetailView.swift` with `init(space: Space)`.
2. `@State var expandedSections: Set<String> = ["media"]` — Media expanded by default.
3. Build 4 collapsible sections using `CollapsibleSection` component:

   **Media** (expanded):
   - `MediaGallerySection` wired to `MediaService`.
   - Upload path: `"accounts/{accountId}/spaces/{spaceId}/{filename}"`.

   **Notes** (collapsed):
   - Display `space.notes` text.
   - Edit pencil → present `EditNotesModal(notes: space.notes, onSave: { newNotes in SpacesService.update(notes: newNotes) })`.

   **Items** (collapsed):
   - `ItemsListControlBar` (sort + filter — all 10 project-scope modes).
   - `SharedItemsList` in embedded mode: source `SpaceDetailCalculations.itemsInSpace(spaceId: space.id, allItems: projectContext.items)`.
   - Navigation to `ItemDetailView` per item.

   **Checklists** (collapsed):
   - List of checklists with their items + checkboxes.
   - Tapping a checkbox → immediate optimistic Firestore update via `SpacesService.update(space:)`.
   - Edit button → present `EditChecklistModal`.

4. "Save as Template" action in toolbar (role-gated by `SpaceDetailCalculations.canSaveAsTemplate()`):
   - If eligible: call `SpaceTemplatesService.create(from: space)` (stub if WP13 not landed).
   - Show success toast/alert on completion.

**Files**:
- `Views/Projects/SpaceDetailView.swift` (create, ~180 lines)

---

### Subtask T041 – Create/wire `Modals/EditSpaceDetailsModal.swift`

**Purpose**: Bottom sheet for editing space name and notes.

**Steps**:
1. Create `Modals/EditSpaceDetailsModal.swift` with `init(space: Space, onSave: (String, String?) -> Void)`.
2. Present as `.sheet()` `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)`.
3. Two fields: Name (required `TextField`), Notes (optional `TextEditor`).
4. "Save" button: validate name non-empty → call `onSave(name, notes)` → dismiss.
5. Caller (SpaceDetailView) handles the Firestore write via `SpacesService.update()`.

**Files**:
- `Modals/EditSpaceDetailsModal.swift` (create, ~60 lines)

**Parallel?**: Yes — once T040 skeleton exists.

---

### Subtask T042 – Create/wire `Modals/EditChecklistModal.swift`

**Purpose**: Bottom sheet for full checklist management (add/remove/reorder/check items).

**Steps**:
1. Create `Modals/EditChecklistModal.swift` with `init(space: Space, onSave: ([Checklist]) -> Void)`.
2. Present as `.sheet()` `.presentationDetents([.large])` + `.presentationDragIndicator(.visible)`.
3. `@State var localChecklists: [Checklist]` — initialized from `space.checklists ?? []`.
4. For each checklist:
   - Checklist title (editable inline or via separate text field).
   - List of items: checkbox toggle (`isChecked`) + item text (editable `TextField`) + swipe-to-delete.
   - Drag handle for reordering: `.onMove { indices, destination in ... }` in edit mode.
   - "Add Item" button at bottom of each checklist.
5. "Add Checklist" button at bottom of modal: appends a new empty `Checklist`.
6. "Save" button: call `onSave(localChecklists)` → dismiss.
7. Caller (SpaceDetailView) writes updated checklists to Firestore via `SpacesService.update(checklists:)`.
8. Optimistic: caller updates local state immediately (no waiting for server).

**Files**:
- `Modals/EditChecklistModal.swift` (create, ~120 lines)

**Parallel?**: Yes — once T040 skeleton exists.

**Notes**:
- Use `List` with `.onMove` for reorder drag handles — requires `EditButton` or toggling `.environment(\.editMode, .constant(.active))`.
- Each `ChecklistItem` needs a stable `id` for identity-based animations.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `SpaceTemplatesService` not yet built (WP13) | Stub: `func create(from space: Space) async throws {}`. Show placeholder alert "Template saved" |
| Checklist reorder: SwiftUI List edit mode interferes with other UI | Toggle `.environment(\.editMode)` only for the checklist list section |
| Items section in SpaceDetail using embedded SharedItemsList | SharedItemsList embedded mode was fixed in WP06 — verify fix is merged |

---

## Review Guidance

- [ ] Spaces tab shows real data with item counts and checklist progress.
- [ ] Space detail: Media expanded by default, others collapsed.
- [ ] Items section has full `ItemsListControlBar` with 10 filter modes.
- [ ] "Save as Template" visible only for owner/admin roles.
- [ ] `EditChecklistModal`: add/remove/reorder/check all work; changes persist after save.
- [ ] All modals present as bottom sheets with drag indicator.
- [ ] Light + dark mode correct.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
- 2026-02-28T22:37:47Z – claude-opus – shell_pid=45115 – lane=doing – Assigned agent via workflow command
- 2026-02-28T22:47:01Z – claude-opus – shell_pid=45115 – lane=for_review – Ready for review: SpacesTabView, SpaceDetailView with 4 collapsible sections, EditSpaceDetailsModal, EditChecklistModal. Build succeeds.
- 2026-02-28T22:47:16Z – claude-opus – shell_pid=97784 – lane=doing – Started review via workflow command
- 2026-02-28T22:53:44Z – claude-opus – shell_pid=97784 – lane=planned – Moved to planned
- 2026-02-28T22:55:04Z – claude-opus – shell_pid=15132 – lane=doing – Started implementation via workflow command
- 2026-02-28T22:59:45Z – claude-opus – shell_pid=15132 – lane=for_review – Review feedback addressed: EditChecklistModal now uses List with .onMove/.onDelete for drag-to-reorder, SpaceCard has X/Y progress text. Build succeeds.
- 2026-02-28T23:05:57Z – claude-opus – shell_pid=38079 – lane=doing – Started review via workflow command
