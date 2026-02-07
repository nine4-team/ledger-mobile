# Spaces Feature Implementation Plan

## Context

The Spaces feature allows users to organize items within projects and business inventory using location-based grouping (e.g., rooms, storage areas, zones). This plan addresses implementing the complete Spaces feature as specified in `/docs/specs/spaces_feature_spec.md`.

### Why This Change

The Spaces feature is a core organizational tool for managing project items and business inventory. Users need to:
- Group items by physical location for better tracking
- Upload images to document spaces visually
- Use checklists for move-in/move-out inspections
- Quickly create spaces inline while working with items
- Reuse space templates for common configurations

### Current State Analysis

**Already Implemented:**
- ✅ `spacesService.ts` - Complete CRUD operations (create, update, delete, subscribe)
- ✅ `ProjectSpacesList.tsx` - List view with search, item counts, image previews
- ✅ Space detail screen (`/app/project/[projectId]/spaces/[spaceId].tsx`) - Full implementation with:
  - Three tabs: Items, Images, Checklists
  - Add existing items picker with "current" and "outside" tabs
  - Cross-workspace item pull-in using `resolveItemMove`
  - Bulk operations (move to space, remove from space)
  - Image upload/management (set primary, remove)
  - Checklist CRUD with inline editing
  - Save as template (admin-only)
  - Delete space functionality
- ✅ `SharedItemPicker` component - Tab-based picker with multi-select
- ✅ `useOutsideItems` hook - Loads items from other projects
- ✅ `spaceTemplatesService.ts` - Template CRUD operations
- ✅ Integration into `ProjectShell` with tab navigation

**Missing/Incomplete:**
- ❌ Soft delete support (`isArchived` field not in Space type - currently uses hard delete)
- ❌ Business Inventory spaces routes and screens
- ❌ Space creation screen (`/spaces/new`)
- ❌ Space edit screen (`/spaces/[spaceId]/edit`)
- ❌ `SpaceSelector` component for inline creation (CRITICAL - used everywhere)
- ❌ Template picker integration in space creation
- ❌ Cloud Function for space deletion cleanup (clearing `item.spaceId`)
- ❌ Template management UI in Settings
- ❌ Proper image upload UI (camera, photo library, drag-drop) - currently just text inputs
- ❌ `ThumbnailGrid` and `ImageGallery` component integration
- ❌ Polish and refinements (loading states, error handling, accessibility)
- ❌ Grid layout for spaces list (currently vertical list)

---

## Implementation Phases

### Phase 1: Complete Core CRUD & Soft Delete

**Goal:** Finish the basic space management screens and add soft delete support.

#### What Gets Built

**Services:**
- Update Space type to include `isArchived` field
- Update `deleteSpace()` to set `isArchived = true` instead of hard delete
- Add `accountId` field to Space type (required by spec)

**Screens:**
- Create `/app/project/[projectId]/spaces/new.tsx` - Space creation form
- Create `/app/project/[projectId]/spaces/[spaceId]/edit.tsx` - Space edit form
- Update space detail to use soft delete

**Components:**
- `SpaceForm.tsx` - Reusable form component for create/edit
  - Name field (required)
  - Notes field (optional, multiline)
  - Template picker (placeholder for Phase 4)
  - Validation and error handling

#### Dependencies
- None (foundational phase)

#### Risks
- Low - Straightforward CRUD implementation

#### Tickets

**1.1: Add Soft Delete Support to Space Type and Service**
- Update `Space` type in `spacesService.ts`:
  - Add `isArchived: boolean` field
  - Add `accountId: string` field
- Update `deleteSpace()` to use soft delete:
  - Set `{ isArchived: true, updatedAt: serverTimestamp() }`
  - Keep function name as `deleteSpace()` for backward compatibility
- Update `subscribeToSpaces()` to filter out archived spaces:
  - Add `.where('isArchived', '==', false)` clause
- Update space detail delete handler to use soft delete
- **Acceptance:** Deleting a space sets `isArchived = true`, space disappears from list

**1.2: Create SpaceForm Component**
- Reusable form component at `/src/components/SpaceForm.tsx`
- Props: `mode: 'create' | 'edit'`, `initialValues`, `onSubmit`, `onCancel`
- Fields:
  - Name (required, TextInput with validation)
  - Notes (optional, multiline TextInput, 4 rows)
  - Template picker (Select dropdown, placeholder for Phase 4)
- Validation: Name required (trimmed, non-empty)
- Success/error toast feedback
- Keyboard dismissal on submit
- **Acceptance:** Form validates input, shows errors, submits correctly

**1.3: Space Creation Screen**
- Create `/app/project/[projectId]/spaces/new.tsx`
- Uses `SpaceForm` with `mode="create"`
- Sets `projectId` from route params
- On submit:
  - Calls `createSpace(accountId, { name, notes, projectId })`
  - Shows success toast
  - Navigates back to spaces list
- Works offline (queued write)
- **Acceptance:** User can create space, see it in list immediately

**1.4: Space Edit Screen**
- Create `/app/project/[projectId]/spaces/[spaceId]/edit.tsx`
- Uses `SpaceForm` with `mode="edit"`
- Pre-fills form with current space data
- On submit:
  - Calls `updateSpace(accountId, spaceId, { name, notes })`
  - Shows success toast
  - Navigates back to space detail
- **Acceptance:** User can edit name/notes, changes reflected immediately

**1.5: Update Space Detail Actions**
- Add "Edit" button in header actions that navigates to edit screen
- Update "Delete" to show improved confirmation dialog:
  - If space has items: "This space has N items. Items will not be deleted, but their space assignment will be cleared."
  - If no items: "Are you sure you want to delete this space?"
- **Acceptance:** Edit and delete work as expected

---

### Phase 2: SpaceSelector Component (CRITICAL)

**Goal:** Build the inline space creation component used throughout the app.

#### What Gets Built

**Components:**
- `SpaceSelector.tsx` - Dropdown/combobox with inline creation capability
- Desktop: Dropdown with keyboard search
- Mobile: Bottom sheet picker with search input

**Features:**
- Shows existing spaces for current workspace (scoped by `projectId`)
- Search filters spaces by name
- "Create '[typed name]'" option when no exact match
- On create:
  1. Calls `spacesService.createSpace()`
  2. Optimistically adds to dropdown
  3. Auto-selects new space
  4. Returns `spaceId` via `onChange`
- Works offline with optimistic UI

#### Dependencies
- Phase 1 complete (space CRUD works)

#### Risks
- Medium - Inline creation with optimistic UI requires careful state management

#### Tickets

**2.1: SpaceSelector Component**
- Create `/src/components/SpaceSelector.tsx`
- Props:
  ```typescript
  interface SpaceSelectorProps {
    projectId: string | null;  // null = BI context
    value: string | null;       // current spaceId
    onChange: (spaceId: string | null) => void;
    allowCreate?: boolean;      // default: true
    disabled?: boolean;
    placeholder?: string;
  }
  ```
- Loads spaces via `subscribeToSpaces(accountId, projectId)`
- Search input filters by name (debounced 300ms)
- Shows "Create '[name]'" option if search doesn't match existing
- On create:
  - Show loading indicator
  - Call `createSpace()` with typed name
  - Add to local state optimistically
  - Auto-select via `onChange(newSpaceId)`
  - Handle errors with toast
- Mobile: Use `BottomSheet` component
- Desktop: Use dropdown with keyboard navigation
- **Acceptance:** User can select existing space or create new inline, works offline

**2.2: Integrate SpaceSelector in Item Forms**
- Update item create screen (`/app/items/new.tsx`):
  - Add Space field using `SpaceSelector`
  - Pass item's `projectId` as scope
  - Set `item.spaceId` on creation
- Update item detail screen (`/app/items/[id].tsx`):
  - Add Space field using `SpaceSelector`
  - Allow changing space assignment
  - Update `item.spaceId` on change
- **Acceptance:** Users can assign items to spaces (existing or new) from item forms

**2.3: SpaceSelector Error Handling**
- Handle offline creation:
  - Queue write via Firestore
  - Show "Creating..." then "Created" state
  - If sync fails later, show error toast with retry option
- Handle validation errors (empty name)
- Handle network errors
- **Acceptance:** Errors handled gracefully with clear user feedback

---

### Phase 3: Business Inventory Spaces

**Goal:** Extend spaces to Business Inventory workspace.

#### What Gets Built

**Screens:**
- `/app/business-inventory/spaces.tsx` - BI spaces list
- `/app/business-inventory/spaces/new.tsx` - Create BI space
- `/app/business-inventory/spaces/[spaceId].tsx` - BI space detail
- `/app/business-inventory/spaces/[spaceId]/edit.tsx` - Edit BI space

**Features:**
- Same UI as project spaces but scoped to `projectId = null`
- Reuses all existing components (`SpaceForm`, `ProjectSpacesList` pattern, space detail)
- Item counts filtered to BI items only

#### Dependencies
- Phase 1 complete (CRUD screens exist)
- Phase 2 complete (SpaceSelector works)

#### Risks
- Low - Mostly code reuse with different scope

#### Tickets

**3.1: Business Inventory Spaces List**
- Create `/app/business-inventory/spaces.tsx`
- Copy pattern from project spaces list
- Use `subscribeToSpaces(accountId, null)` for BI spaces
- Filter items where `projectId === null`
- "Add space" navigates to `/business-inventory/spaces/new`
- **Acceptance:** Users see BI spaces list, can navigate to create/detail

**3.2: Business Inventory Space CRUD Screens**
- Create `/app/business-inventory/spaces/new.tsx` - Uses `SpaceForm`, sets `projectId = null`
- Create `/app/business-inventory/spaces/[spaceId].tsx` - Copy space detail, scope to BI
- Create `/app/business-inventory/spaces/[spaceId]/edit.tsx` - Uses `SpaceForm`
- All screens use same components as project spaces
- **Acceptance:** Full CRUD for BI spaces works identically to project spaces

**3.3: Update SpaceSelector for BI Context**
- Ensure `SpaceSelector` works when `projectId = null`
- Filter spaces correctly for BI context
- Test inline creation in BI item forms
- **Acceptance:** SpaceSelector works in both project and BI contexts

---

### Phase 4: Templates & Advanced Features

**Goal:** Enable space templates and improve space creation workflow.

#### What Gets Built

**Components:**
- Template picker in `SpaceForm`
- Template selection logic with prefill

**Features:**
- Template dropdown in space creation form
- On template select: prefills name, notes, checklists
- Checklist normalization (all items `isChecked = false`)
- "Start blank" option clears template

#### Dependencies
- Phase 1 complete (space creation form exists)
- `spaceTemplatesService` already exists

#### Risks
- Low - Service already exists, just need UI integration

#### Tickets

**4.1: Template Picker in Space Form**
- Update `SpaceForm` to include template picker:
  - Load templates via `subscribeToSpaceTemplates(accountId)`
  - Filter to active templates only (`isArchived = false`)
  - Sort by `sortOrder` field
  - Dropdown options: "Start blank" (default) + template names
- On template select:
  - Pre-fill name, notes from template
  - Include checklists in form state (hidden from user)
  - Normalize checklists: force all items to `isChecked = false`
- On "Start blank": clear prefilled values
- Help text: "Select a template to prefill, or start blank"
- **Acceptance:** Users can create spaces from templates, checklists normalized correctly

**4.2: Save Space as Template (Polish)**
- Verify existing "Save as template" button in space detail
- Ensure checklist normalization works correctly
- Add success feedback toast
- **Acceptance:** Admins can save spaces as templates successfully

---

### Phase 5: Image Upload & Gallery Enhancement

**Goal:** Replace text input image upload with proper mobile/desktop UI.

#### What Gets Built

**Components:**
- Integrate `ThumbnailGrid` component
- Integrate `ImageGallery` component
- Camera/photo library picker
- Drag-and-drop upload (desktop)

**Features:**
- Mobile: Camera, photo library, file picker
- Desktop: Drag-and-drop zone with visual feedback
- Thumbnail grid with menu actions (set primary, delete)
- Full-screen gallery with zoom/pan
- Max 50 images per space
- Offline placeholder support

#### Dependencies
- Media infrastructure already exists (reuse from items)
- Phase 1 complete (space detail exists)

#### Risks
- Low - Reusing existing battle-tested components

#### Tickets

**5.1: Replace Image Upload UI with ThumbnailGrid**
- Update Images tab in space detail screen
- Replace TextInput fields with `ThumbnailGrid` component
- Add button to trigger image picker
- Mobile: Present action sheet (Camera / Photo Library / File)
- Desktop: Show drag-and-drop zone
- Use `expo-image-picker` for camera/gallery
- Call `saveLocalMedia()` → `enqueueUpload()` pattern
- **Acceptance:** Users can upload images via proper UI, see thumbnails

**5.2: Integrate ImageGallery**
- Add tap handler on thumbnails to open `ImageGallery`
- Pass space images array
- Support pinch-to-zoom, pan, navigation
- Close button returns to detail
- **Acceptance:** Users can view images in full-screen gallery with gestures

**5.3: Image Menu Actions**
- Each thumbnail shows context menu:
  - "Set Primary" - marks as primary for space card
  - "Delete" - removes from space
- Primary image has visual indicator (star badge)
- If deleting primary, next image becomes primary
- **Acceptance:** Users can set primary and delete images via menu

---

### Phase 6: Cloud Function for Space Deletion Cleanup

**Goal:** Automatically clear `item.spaceId` when space is soft-deleted.

#### What Gets Built

**Cloud Functions:**
- Firestore trigger on space update
- Detects `isArchived` change from `false` to `true`
- Batch updates items to clear `spaceId`

**Features:**
- Runs asynchronously (1-2 seconds after delete)
- Scoped to correct workspace
- Handles large item counts with batching

#### Dependencies
- Phase 1 complete (soft delete implemented)

#### Risks
- Medium - Requires Cloud Function deployment and testing

#### Tickets

**6.1: Space Deletion Cleanup Cloud Function**
- Create Cloud Function in `/firebase/functions/src/`
- Trigger: `onSpaceUpdate`
- Logic:
  ```typescript
  if (!before.isArchived && after.isArchived) {
    const itemsQuery = db
      .collection(`accounts/${accountId}/items`)
      .where('spaceId', '==', spaceId)
      .where('projectId', '==', after.projectId);

    const batch = db.batch();
    const snapshot = await itemsQuery.get();
    snapshot.docs.forEach(doc => {
      batch.update(doc.ref, { spaceId: null });
    });
    await batch.commit();
  }
  ```
- Handle large batches (Firestore batch limit = 500)
- Log success/failure
- **Acceptance:** Deleting space clears all item assignments within 2 seconds

**6.2: Test Cleanup Function**
- Integration test: Create space, assign items, delete space, verify items updated
- Test with 0, 1, 10, 100 items
- Test cross-workspace isolation (project items don't affect BI items)
- **Acceptance:** Cleanup works correctly for all item counts and scopes

---

### Phase 7: Template Management UI (Settings)

**Goal:** Admin-only template management in Settings.

#### What Gets Built

**Screens:**
- Settings → Presets → Spaces tab
- Template list with table view
- Create/edit template modal
- Archive/unarchive functionality
- Drag-to-reorder

**Features:**
- CRUD operations on templates
- Checklist management within templates
- Show/hide archived toggle
- Drag-to-reorder with `sortOrder` persistence

#### Dependencies
- Phase 4 complete (templates used in space creation)
- Settings screen structure already exists

#### Risks
- Low - Standard CRUD UI

#### Tickets

**7.1: Template List in Settings**
- Add Spaces sub-tab to Settings → Presets
- Table layout:
  - Drag handle (GripVertical icon)
  - Template name
  - Actions menu (Edit, Archive)
- Show active templates by default
- "Show Archived" toggle button (top-right)
- Empty states: "No templates yet" / "No archived templates"
- **Acceptance:** Admins can view templates in Settings, toggle archived view

**7.2: Create/Edit Template Modal**
- Modal triggered by "Create template" button or "Edit" action
- Fields:
  - Name (required, auto-focus)
  - Notes (optional, textarea)
  - Checklists section (full CRUD)
- Checklist management:
  - Add checklist, rename, delete
  - Add items, edit text, delete items
  - All items forced to `isChecked = false`
- Save button disabled if name empty
- On save: create/update template, close modal, refresh list
- **Acceptance:** Admins can create/edit templates with checklists

**7.3: Archive/Unarchive Templates**
- Archive action sets `isArchived = true`
- Unarchive action sets `isArchived = false`
- Archived templates show in separate list (toggle view)
- Unarchive may fail if name conflict exists (show error)
- **Acceptance:** Admins can archive/unarchive templates

**7.4: Drag-to-Reorder Templates**
- Drag handle on active templates only
- Drag-and-drop updates order
- On drop: batch update `sortOrder` field with sequential integers
- Optimistic UI update
- On error: revert order, show error toast
- **Acceptance:** Admins can reorder templates, order persists and reflects in pickers

---

### Phase 8: Polish & Refinements

**Goal:** Improve UX, handle edge cases, optimize performance.

#### What Gets Built

**Enhancements:**
- Grid layout for spaces list (2 columns on mobile)
- Loading states and skeletons
- Error handling and retry logic
- Offline indicators
- Accessibility improvements
- Performance optimizations

#### Dependencies
- All previous phases complete

#### Risks
- Low - Incremental improvements

#### Tickets

**8.1: Grid Layout for Spaces List**
- Update `ProjectSpacesList` to use grid layout
- 2 columns on mobile, 3-4 on tablet, responsive
- Space cards with proper aspect ratio
- Primary image fills card top
- Name and item count below image
- **Acceptance:** Spaces display in attractive grid layout

**8.2: Loading States & Skeletons**
- Add skeleton placeholders for loading spaces
- Shimmer effect for image loading
- Loading indicators for async operations
- Disable buttons during loading
- **Acceptance:** Loading states provide clear feedback

**8.3: Error Handling & Offline Indicators**
- Network error handling with retry buttons
- Offline banner when network unavailable
- "Syncing..." indicator for pending writes
- Validation error messages inline
- **Acceptance:** Errors handled gracefully with actionable feedback

**8.4: Accessibility Improvements**
- Add `accessibilityLabel` to all interactive elements
- Proper `accessibilityRole` attributes
- Keyboard navigation on desktop
- Focus management in modals
- Screen reader testing
- Color contrast verification (WCAG AA)
- **Acceptance:** App navigable with screen readers and keyboard

**8.5: Performance Optimization**
- Memoize expensive computations (item counts, filtered lists)
- Virtualize long lists if needed (>100 items)
- Lazy-load images with progressive loading
- Debounce search inputs (350ms)
- Profile and optimize re-renders
- **Acceptance:** App remains performant with large datasets (tested with 1000+ items)

---

## Critical Files

Based on current implementation and this plan, the most critical files are:

1. **`/src/components/SpaceSelector.tsx`** (NEW) - Inline space creation component used everywhere (item forms, transaction forms, bulk operations). Highest-impact component for user workflow.

2. **`/src/data/spacesService.ts`** (MODIFY) - Core service requiring soft delete and `isArchived` field addition.

3. **`/app/project/[projectId]/spaces/new.tsx`** (NEW) - Space creation screen with template picker.

4. **`/app/project/[projectId]/spaces/[spaceId].tsx`** (EXISTS) - Already comprehensive, needs image UI polish and soft delete integration.

5. **`/src/components/SpaceForm.tsx`** (NEW) - Reusable form component for create/edit flows.

---

## Risk Summary

| Risk | Severity | Mitigation | Phase |
|------|----------|------------|-------|
| SpaceSelector complexity | Medium | Break into small PRs, extensive testing | 2 |
| Cloud Function deployment | Medium | Thorough testing, gradual rollout | 6 |
| Image upload UX on mobile | Low | Reuse battle-tested item detail patterns | 5 |
| Template management complexity | Low | Standard CRUD UI, existing service | 7 |
| Performance with large datasets | Low | Memoization, virtualization if needed | 8 |

---

## Verification & Testing

**Per Phase:**
- Unit tests for new services and utilities
- Component tests for UI interactions
- Integration tests for complete flows
- Manual testing on iOS and Android
- Offline scenario testing (airplane mode)

**Key Test Scenarios:**
1. Create space offline → reconnect → verify sync
2. Delete space with items → verify Cloud Function cleanup
3. Inline space creation from item form → verify optimistic update
4. Create space from template → verify checklist normalization
5. Upload images offline → verify placeholders → verify upload on reconnect
6. Cross-workspace item pull-in → verify allocation
7. Drag-reorder templates → verify persistence
8. Screen reader navigation through all screens

**Performance Benchmarks:**
- Spaces list loads in <500ms with 100 spaces
- Item count calculation completes in <200ms with 1000 items
- Search filters respond in <300ms (debounced)
- Image upload queues in <100ms (sync happens in background)

---

## Output Location

Upon plan approval and implementation, create the final detailed implementation plan document at:
**`/Users/benjaminmackenzie/Dev/ledger_mobile/.plans/spaces_implementation_plan.md`**

This document will serve as the authoritative guide for executing the Spaces feature implementation across all 8 phases.
