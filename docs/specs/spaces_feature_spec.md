# Spaces Feature Specification

## Document Status
**Version:** 1.3
**Last Updated:** 2026-02-06
**Status:** Draft - Ready for Implementation

## Intent

Provide an offline-ready Spaces experience for organizing items within projects and business inventory. Users can browse/search spaces, create/edit/delete spaces, manage space items, upload images, and work with checklists—all with predictable offline behavior.

This is a **mobile-first** application with a planned desktop version. Features like drag-and-drop image upload are specifically designed for desktop use.

## Architecture Baseline

- **Firestore-native offline persistence** as the default (Firestore is canonical)
- **Scoped listeners** on bounded queries while foregrounded (never unbounded "listen to everything")
- **Request-doc workflows** (Cloud Functions) for multi-doc/invariant operations
- See: `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`

---

## Definitions

### Core Concepts

- **Space**: A location/grouping entity used to organize items (similar to a room, storage area, or zone)
- **Space template**: An account-wide preset used to prefill new spaces with default name, notes, and checklists
- **Workspace scope**: Where the space "lives" and which items may reference it:
  - **Project scope**: Spaces within a specific project
  - **Business Inventory scope**: Spaces within the Business Inventory workspace (`projectId = null`)

### Scope Rules (Required)

**NEW FEATURE:** Business Inventory spaces are a **greenfield capability** for this mobile app, not a migration from the legacy web app. The legacy app uses free-text `businessInventoryLocation` fields instead of structured spaces. There are no existing account-wide spaces to migrate.

**Spaces are workspace-scoped:**
- Project spaces always have a concrete `projectId`
- Business Inventory spaces have `projectId = null` (explicit scope)

---

## Data Model & Storage

### Firestore Collections

#### Spaces Collection
**Path:** `accounts/{accountId}/spaces/{spaceId}`

```typescript
interface Space {
  id: string
  accountId: string
  projectId: string | null  // null = Business Inventory scope
  templateId?: string | null  // provenance tracking
  name: string  // required
  notes?: string | null
  images?: AttachmentRef[]  // kind: "image", with isPrimary flag
  checklists?: SpaceChecklist[]
  isArchived: boolean  // soft delete flag
  metadata?: Record<string, any> | null
  createdAt: Timestamp
  updatedAt: Timestamp
  createdBy?: string | null
  updatedBy?: string | null
}

interface SpaceChecklist {
  id: string  // UUID
  name: string
  items: SpaceChecklistItem[]
}

interface SpaceChecklistItem {
  id: string  // UUID
  text: string
  isChecked: boolean
}
```

**Notes:**
- `version` field from legacy is **omitted** (not critical for mobile)
- `isArchived` field is used for **soft delete** (set to `true` when user deletes space)
- User-facing terminology is "Delete", not "Archive"
- `AttachmentRef` follows `20_data/data_contracts.md` contract
- Upload state (`local_only | uploading | failed | uploaded`) is **derived locally**, not stored on the Space doc

#### Space Templates Collection
**Path:** `accounts/{accountId}/spaceTemplates/{templateId}`

```typescript
interface SpaceTemplate {
  id: string
  accountId: string
  name: string
  notes?: string | null
  checklists?: SpaceChecklist[]  // all items default to isChecked=false
  isArchived: boolean
  sortOrder?: number | null  // for drag-to-reorder in settings
  metadata?: Record<string, any> | null
  createdAt: Timestamp
  updatedAt: Timestamp
  createdBy?: string | null
  updatedBy?: string | null
}
```

### Item ↔ Space Reference Rules

Items reference spaces via `item.spaceId` (foreign key).

**Scope consistency is mandatory:**
- If `item.projectId = <projectId>`, then `item.spaceId` must reference a Space with `space.projectId = <projectId>`
- If `item.projectId = null` (Business Inventory), then `item.spaceId` must reference a Space with `space.projectId = null`
- When an item changes scope (e.g., BI → Project allocation), `spaceId` must be updated/cleared atomically

**Legacy field migration:**
- Legacy items have `item.space` (deprecated free-text field) in addition to `item.spaceId`
- **Mobile app will NOT use `item.space`** - only `item.spaceId`
- Data migrator (separate tool) will handle conversion

---

## Owned Screens & Routes

### Project Spaces

| Screen | Route | Description |
|--------|-------|-------------|
| **Spaces List** | `/project/:projectId/spaces` | Grid view of project spaces |
| **Create Space** | `/project/:projectId/spaces/new` | Create new space form |
| **Space Detail** | `/project/:projectId/spaces/:spaceId` | Space detail with tabs (Items/Images/Checklists) |
| **Edit Space** | `/project/:projectId/spaces/:spaceId/edit` | Edit space name/notes |

### Business Inventory Spaces (NEW)

| Screen | Route | Description |
|--------|-------|-------------|
| **Inventory Spaces List** | `/business-inventory/spaces` | Grid view of inventory spaces |
| **Create Inventory Space** | `/business-inventory/spaces/new` | Create new inventory space |
| **Inventory Space Detail** | `/business-inventory/spaces/:spaceId` | Space detail with tabs |
| **Edit Inventory Space** | `/business-inventory/spaces/:spaceId/edit` | Edit space name/notes |

**Mobile route structure may differ** but scope separation must be explicit.

### Screen Contracts
- `ui/screens/ProjectSpacesList.md`
- `ui/screens/SpaceDetail.md`
- `ui/screens/SpaceForm.md`

---

## Primary Flows

### 1. Browse/Search Spaces

**Summary:**
- Spaces render in a grid of cards showing:
  - Primary image (or placeholder icon)
  - Space name
  - Item count (derived from items with matching `spaceId`)
- Search filters spaces by `name` and `notes` substring matches (case-insensitive)
- Empty state with "Add Space" call-to-action

**Item Count Calculation:**
- **Project spaces**: Count items where `item.projectId = <projectId>` AND `item.spaceId = <spaceId>`
- **Inventory spaces**: Count items where `item.projectId = null` AND `item.spaceId = <spaceId>`
- **Implementation**: Use scoped Firestore query with count aggregation (no denormalized counter field)

**Deleted Spaces:**
- By default, deleted spaces (`isArchived = true`) are **hidden** from the list
- No UI for viewing/restoring deleted spaces in v1 (gap noted for future enhancement)

**Offline behavior:**
- Render from Firestore local cache on cold start (avoid empty flash)
- Use scoped listener on `accounts/{accountId}/spaces` with filter:
  - `projectId == <projectId>` for project context
  - `projectId == null` for Business Inventory context
  - `isArchived == false`

**Legacy parity source:**
- `src/pages/ProjectSpacesPage.tsx`
- `src/components/spaces/SpacePreviewCard.tsx`

---

### 2. Create Space (Optionally from Template)

**Summary:**
- Triggered from Spaces list "Add" button
- Form fields:
  - **Template picker** (optional dropdown)
  - **Name** (required text input)
  - **Notes** (optional textarea)
- Template selection prefills name, notes, and checklists
- On submit: validate, create space, show success toast, navigate back

**Template Picker:**
- Shows all active (non-archived) templates
- Sorted by `sortOrder` field (ascending)
- When selected: auto-fills form with template data
- Checklist normalization: all items forced to `isChecked = false` at creation time

**Validation:**
- `name` is required (non-empty after trim)

**Success flow:**
- Create space in Firestore
- Show success toast
- Navigate back to Spaces list (or to Space detail if "Save & View")
- Refresh collections via Firestore listener

**Scope handling:**
- Project spaces: set `projectId = <projectId>`
- Business Inventory spaces: set `projectId = null`

**Legacy parity source:**
- `src/pages/SpaceNew.tsx`
- `normalizeChecklistsFromTemplate` logic (line 99)

---

### 3. Inline Space Creation (SpaceSelector Component)

**CRITICAL FEATURE:** This is how users create most spaces in practice.

**Summary:**
- Reusable combobox/dropdown component used throughout the app
- Shows existing spaces for the current workspace
- **Allows inline creation**: user types new space name → "Create '[name]'" option appears
- Immediately creates space via `spaceService.createSpace()`
- Returns new `spaceId` to parent form

**Component Props:**
```typescript
interface SpaceSelectorProps {
  projectId: string | null  // null = Business Inventory context
  value: string | null  // current spaceId
  onChange: (spaceId: string | null) => void
  allowCreate?: boolean  // default: true
  disabled?: boolean
  placeholder?: string
}
```

**Behavior:**
- Loads spaces for current workspace (scoped by `projectId`)
- User types in search box:
  - Shows matching existing spaces
  - If no exact match: shows "Create '[typed name]'" option
- On "Create" selection:
  1. Call `spaceService.createSpace({ accountId, projectId, name })`
  2. Optimistically add to dropdown
  3. Auto-select the new space
  4. Return `spaceId` to parent via `onChange`

**Used in these contexts:**
- Add/Edit Item forms (assign item to space)
- Item Detail (change space assignment)
- Bulk item operations (assign multiple items to space)
- Transaction itemization (set space for items)

**Desktop vs Mobile:**
- Desktop: Dropdown with keyboard search
- Mobile: Bottom sheet picker with search input

**Legacy parity source:**
- `src/components/spaces/SpaceSelector.tsx`
- Used in: `AddItem.tsx`, `EditItem.tsx`, `ItemDetail.tsx`, `BulkItemControls.tsx`, `TransactionItemsList.tsx`

---

### 4. View Space Detail (Tabs: Items / Images / Checklists)

**Summary:**
- Header with back button, space name, and actions menu
- Notes section (collapsible if long)
- Three tabs:
  1. **Items**: Manage items assigned to this space
  2. **Images**: Upload/view/manage space images
  3. **Checklists**: Create/edit checklists and checklist items

**Actions Menu:**
- Edit space (name/notes)
- Save as Template (admin-only)
- Delete space

**Offline behavior:**
- Render from Firestore local cache
- Use scoped listeners:
  - Space doc: `accounts/{accountId}/spaces/{spaceId}`
  - Items: `accounts/{accountId}/items` where `spaceId == <spaceId>` (bounded query)

**Legacy parity source:**
- `src/pages/SpaceDetail.tsx` (1127 lines)

---

### 5. Manage Items in Space (Items Tab)

**Summary:**
- Shows all items assigned to this space
- Two primary actions:
  1. **Create New Item** (in this space)
  2. **Add Existing Items** (from anywhere)
- Item list with inline editing, duplication, bulk operations

**Create New Item:**
- Opens standard item creation flow
- Pre-fills `spaceId` with current space
- On save: item appears in list immediately

**Add Existing Items (CRITICAL FEATURE):**

Opens a full-screen modal/bottom sheet with advanced item picker:

**Tabs:**
- **In This Workspace**: Items in current project/BI that aren't in this space yet
- **Outside**: Items from other projects + other workspace (requires pull-in)

**Features:**
- **Search**: Real-time search by description, SKU, source, price
  - Auto-switches to first tab with results
  - Debounced input (300ms)
- **Multi-select**: Checkboxes on each item
- **Select All**: Per-tab, respects disabled items
- **Duplicate Grouping**: Items with identical SKU/description/metadata group together
  - Collapsible group with count badge (e.g., "×3")
  - Tri-state checkbox (checked/unchecked/indeterminate)
  - "Add All" button on group (convenience pattern)
- **Sticky "Add Selected" button**: Stays visible at bottom while scrolling
  - Shows count: "Add Selected (5)"
  - Disabled while processing
- **Empty states**: "No items match this search"
- **Loading states**: "Loading items..."

**Outside Items Handling (NEW REQUIREMENT):**

Items from outside the current workspace can be added, but they must be **pulled into the workspace first** before assignment.

**Pull-in flows:**
1. **Business Inventory → Project Space**
   - Run allocation flow (request-doc workflow)
   - Set `item.projectId = <projectId>`
   - Set `item.spaceId = <spaceId>`
   - See: `40_features/inventory-operations-and-lineage/flows/business_inventory_to_project_allocation.md`

2. **Project A → Project B Space**
   - Run deallocate + allocate flow (move/sell)
   - Update `item.projectId = <projectIdB>`
   - Set `item.spaceId = <spaceId>`
   - See: `40_features/inventory-operations-and-lineage/...`

3. **Project → Business Inventory Space**
   - Run deallocation flow
   - Set `item.projectId = null`
   - Set `item.spaceId = <spaceId>`

4. **Within Same Workspace**
   - Direct update: `item.spaceId = <spaceId>`

**Disabled Items:**
- Items tied to transactions from outside workspaces are **disabled** with reason text:
  - _"This item is tied to a transaction; move the transaction instead."_

**Bulk Operations:**
- **Move Items to Another Space**: Select items → choose target space → update `spaceId`
- **Remove Items from Space**: Select items → clear `spaceId` to `null`

**Search Implementation (v1 - Client-Side Filtering):**

**In This Workspace Tab:**
- Scoped Firestore query: `accounts/{accountId}/items` where `projectId == <scope>` AND `spaceId != <currentSpaceId>`
- Firestore listener provides real-time dataset
- Client-side filtering on search query (debounced 350ms)
- Searchable fields: name, SKU, source, notes

**Outside Tab:**
- One-time Firestore query when tab opens: `accounts/{accountId}/items` (all items)
- Reads from Firestore local cache (fast after first load)
- Results stored in component state
- Client-side filtering on search query (in-memory, instant)
- Query disposed when picker closes

**Performance Characteristics (v1):**
- First load (cold cache): ~1-2 seconds for 2000 items
- Subsequent loads (warm cache): <100ms
- Search/filter: Instant (JavaScript array operations)
- Memory footprint: ~2-4MB for 2000 items
- Acceptable for accounts with <5000 items

**Offline Behavior:**
- Search works 100% offline (Firestore cached data)
- No network request needed for search
- Same pattern as existing SharedItemsList/SharedTransactionsList components

**Search Upgrade Path (Phase 2 - Future Enhancement):**

When accounts exceed 5000 items or users request better search:
- Integrate existing SQLite FTS5 search-index module (`/src/search-index/`)
- Extend for account-wide scope (cross-project search)
- Benefits: Fuzzy matching, BM25 ranking, better performance at scale
- Still offline-first (SQLite is local database)
- Infrastructure already built, just needs integration

See: `src/search-index/README.md` for complete documentation of existing search infrastructure.

**UI Patterns Reference:**
- Reusable `ExistingItemsPicker` component (same as used for transactions)
- See `ExistingItemsPicker.tsx`, `AddExistingItemsModal.tsx` in legacy web app

**Legacy parity sources:**
- `src/components/items/ExistingItemsPicker.tsx` (792 lines)
- `src/pages/SpaceDetail.tsx` (lines 301-326, 721, 1017-1036)
- `src/services/itemPullInService.ts` (pull-in logic)
- `src/utils/itemGrouping.ts` (duplicate grouping)
- `src/components/ui/CollapsedDuplicateGroup.tsx`

---

### 6. Manage Space Images (Images Tab)

**Summary:**
- Upload multiple images to space gallery
- Set primary image for space preview card
- Remove images
- View in full-screen gallery/lightbox
- Offline support with placeholder URLs

**Upload Methods:**

**Desktop:**
- **Drag-and-drop** zone (full drag-over visual feedback)
- File browser dialog (multi-select)

**Mobile:**
- **Camera capture** (take photo)
- **Photo library** (device gallery)
- **File picker** (browse files)

**Shared Image Upload Component:**

Reuse the same image upload patterns from Item Detail screen:

**Components to use:**
- `ImageUpload` - Drag-drop/multi-select with validation
- `ImagePreview` - Thumbnail grid with controls
- `ImageGallery` - Full-screen viewer with zoom/pan

**Features (inherited from shared components):**
- Multi-file selection (up to **50 images per space**)
- File validation (type, size, quota)
- Automatic compression on mobile (1200px width, 0.7 quality)
- HEIC/HEIF auto-conversion to JPEG
- Upload progress indicator (aggregate percentage)
- Offline placeholder support (`offline://<mediaId>`)
- Error handling with user-friendly messages

**Implementation reference:**
See Item Detail screen implementation in legacy web app:
- `src/pages/ItemDetail.tsx` (lines 889-1067, 1221-1256)
- `src/components/ui/ImageUpload.tsx` (496 lines)
- `src/components/ui/ImagePreview.tsx` (589 lines)
- `src/components/ui/ImageGallery.tsx` (706 lines)
- `src/services/imageService.ts` (868 lines)

**Attachment Contract (Required):**
- Space images are stored as `AttachmentRef[]` with `kind: "image"`
- Upload state is **derived locally**, not persisted on Space doc
- See: `20_data/data_contracts.md`, `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`

**Set Primary Image:**
- User taps menu on image → "Set Primary"
- Updates `images` array to mark selected image with `isPrimary: true`
- All other images: `isPrimary: false`
- Primary image shown on space preview card

**Remove Image:**
- User taps menu on image → "Delete"
- Confirmation dialog
- Remove from `images` array
- If removing primary: auto-select first remaining image as primary (or none if last image)

**Gallery/Lightbox:**
- Tap thumbnail → full-screen gallery
- Swipe navigation, zoom/pan gestures
- Keyboard support (desktop): arrows, escape, +/-, 0
- See: `40_features/_cross_cutting/ui/components/image_gallery_lightbox.md`

**Offline Behavior:**
- Uploads may create `offline://` placeholder URLs (renderable immediately via IndexedDB blob resolution)
- When online: background sync uploads to Storage, replaces URLs
- Offline image resolution pattern from `src/components/spaces/SpacePreviewCard.tsx`

**File Storage:**
- Supabase Storage bucket: `space-images`
- Path structure: `{projectName}/space-images/{dateTime}/{timestamp}_{fileName}`
- Max file size: 10MB per image
- **Max images per space: 50** (higher than items due to larger documentation needs)

**Legacy parity sources:**
- `src/pages/SpaceDetail.tsx` (lines 205-258, handleAddImage, handleRemoveImage, handleSetPrimaryImage)
- Item Detail image upload patterns (preferred reference)

---

### 7. Manage Checklists (Checklists Tab)

**Summary:**
- Multiple named checklists per space
- Each checklist has ordered list of items with checkboxes
- Inline editing with immediate persistence

**Checklist Operations:**

| Action | Trigger | Behavior | Persistence |
|--------|---------|----------|-------------|
| **Add Checklist** | "Add Checklist" button | Creates checklist with default name "New Checklist" | Immediate |
| **Rename Checklist** | Click name to edit | Inline input; commit on blur or Enter; empty → "Checklist" | On blur/Enter |
| **Delete Checklist** | Delete icon | Confirmation dialog → removes from array | Immediate |
| **Add Checklist Item** | "Add Item" button or Enter | Creates item with default text "Item", unchecked | Immediate |
| **Edit Checklist Item** | Click text to edit | Inline input; commit on blur or Enter; Escape cancels; empty → "Item" | On blur/Enter |
| **Toggle Checkbox** | Click checkbox | Toggle `isChecked` boolean | Immediate |
| **Delete Checklist Item** | Delete icon | Removes from array | Immediate |

**UX Details:**
- **Auto-focus**: New checklist/item inputs receive focus automatically
- **Keyboard shortcuts**:
  - Enter: Add new item (when focused in last item)
  - Escape: Cancel edit without saving
  - Tab: Move to next field
- **Empty name handling**:
  - Checklist: empty name becomes "Checklist"
  - Checklist item: empty text becomes "Item"
- **Drag-to-reorder**: NOT implemented in v1 (gap noted)

**Data Structure:**
```typescript
checklists: [
  {
    id: "uuid-1",
    name: "Move-in Checklist",
    items: [
      { id: "uuid-a", text: "Check for damages", isChecked: true },
      { id: "uuid-b", text: "Take photos", isChecked: false }
    ]
  },
  {
    id: "uuid-2",
    name: "Inventory Check",
    items: [...]
  }
]
```

**Offline Behavior:**
- Checklist edits are deterministic Firestore updates
- Queued offline by Firestore-native persistence
- Conflict strategy: **last-write-wins** with `serverTimestamp` ordering (acceptable for checklists)

**Legacy parity source:**
- `src/pages/SpaceDetail.tsx` (lines 259-297, checklist handlers)

---

### 8. Save Space as Template (Admin-Only)

**Summary:**
- From Space Detail actions menu → "Save as Template"
- Creates a new template based on current space
- Checklists are copied but normalized (all items → `isChecked: false`)

**Flow:**
1. User selects "Save as Template" from menu
2. Modal opens with form:
   - **Name**: Pre-filled with space name (editable)
   - **Notes**: Pre-filled with space notes (editable)
   - **Checklists**: Copied from space (read-only preview)
3. On submit:
   - Create template via `spaceTemplatesService.createTemplate()`
   - Normalize checklists: force all `isChecked = false`
   - Auto-assign next `sortOrder` value
   - Show success toast
   - Close modal

**Permissions:**
- **Admin-only** (client gating for UX; server enforcement required)
- Non-admins don't see this action in menu

**Checklist Normalization:**
- Template checklists store **default state only** (unchecked)
- When user creates space from template: items start unchecked
- When user works in space: checkbox state is space-specific

**Legacy parity source:**
- `src/pages/SpaceDetail.tsx` (lines 327-345, isAdmin gate, normalizeChecklistsForTemplate)

---

### 9. Edit Space (Name/Notes Only)

**Summary:**
- Edit screen for updating space name and notes
- Does NOT edit checklists or images (use Space Detail tabs)

**Form Fields:**
- **Name** (required text input)
- **Notes** (optional textarea)

**Validation:**
- `name` is required (non-empty after trim)

**Navigation:**
- Respects `returnTo` query parameter
- Fallback: Navigate to Space Detail

**Legacy parity source:**
- `src/pages/SpaceEdit.tsx`

---

### 10. Delete Space (Soft Delete)

**Summary:**
- Delete action from Space Detail actions menu
- **Soft delete only**: Sets `isArchived = true` (does NOT hard delete from database)
- User-facing terminology: "Delete Space" (not "Archive")
- Items assigned to space: NOT deleted, but `spaceId` is cleared

**Flow:**
1. User selects "Delete Space" from actions menu
2. Confirmation dialog:
   - **Title**: "Delete Space?"
   - **Message**:
     - If space has items: _"This space has N items assigned. Items will not be deleted, but their space assignment will be cleared."_
     - If no items: _"Are you sure you want to delete this space?"_
   - **Actions**: "Cancel" (default) / "Delete Space" (destructive)
3. On confirm:
   - Update space: `{ isArchived: true }`
   - **Server-side cleanup** (Cloud Function trigger): Clear `item.spaceId = null` for all items where `spaceId == <deletedSpaceId>`
   - Show success toast
   - Navigate back to Spaces list

**Server-Side Cleanup Implementation:**

Cloud Function trigger on space document update:

```typescript
exports.onSpaceDeleted = functions.firestore
  .document('accounts/{accountId}/spaces/{spaceId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Trigger when space is soft-deleted
    if (!before.isArchived && after.isArchived) {
      const { accountId, spaceId } = context.params;
      const projectId = after.projectId; // null for BI spaces

      // Clear spaceId for all items in this space (scoped to correct workspace)
      const itemsQuery = admin.firestore()
        .collection(`accounts/${accountId}/items`)
        .where('spaceId', '==', spaceId)
        .where('projectId', '==', projectId);

      const batch = admin.firestore().batch();
      const snapshot = await itemsQuery.get();

      snapshot.docs.forEach(doc => {
        batch.update(doc.ref, { spaceId: null });
      });

      await batch.commit();
    }
  });
```

**Scope Handling:**
- Cleanup must apply to **correct workspace items only**:
  - Project space: Clear `spaceId` for items where `projectId == <projectId>`
  - Inventory space: Clear `spaceId` for items where `projectId == null`

**Timing:**
- Cleanup is **asynchronous** (Cloud Function trigger executes within 1-2 seconds)
- Client shows success immediately after updating space doc
- Items cleared in background

**No Restore in v1:**
- Deleted spaces are hidden from listings
- No UI for viewing/restoring deleted spaces (gap noted for future enhancement)

**Hard Delete:**
- NOT exposed in UI
- Service method may exist for admin/maintenance purposes only

**Legacy parity source:**
- `src/pages/SpaceDetail.tsx` (lines 346-360, showDeleteConfirm)
- `src/services/spaceService.ts` (archiveSpace vs deleteSpace methods)

---

## Space Templates Management (Settings Feature)

### Overview

Space Templates is an **account-scoped** preset management system that allows administrators to create reusable space definitions. Templates are managed in **Settings > Presets > Spaces** (admin-only) and are used to quickly create project spaces with predefined names, notes, and checklists.

**Key Principle**: Templates are definitions, not instances. Creating a space from a template clones the template data into a new space record. Templates do not auto-update existing spaces.

**File Reference**: `src/components/spaces/SpaceTemplatesManager.tsx` (legacy web app)

---

### Complete Feature Set

| Feature | UI Location | Permissions | Key Behaviors |
|---------|-------------|-------------|---------------|
| **Create Template** | Settings > Presets > Spaces | Admin only | Modal form, name required, auto-assigns sortOrder |
| **Edit Template** | Three-dot menu > Edit | Admin only | Same modal as create, preserves sortOrder, increments version |
| **Archive Template** | Three-dot menu > Archive | Admin only | Soft delete, hides from picker, frees name for reuse |
| **Unarchive Template** | Show Archived > Unarchive button | Admin only | Restores to active, may fail if name conflict |
| **Delete Template** | NOT IN UI (service only) | N/A | Hard delete, sets spaces.templateId to null, NOT recommended |
| **Reorder Templates** | Drag GripVertical icon | Admin only | Drag-to-reorder active only, saves sortOrder batch update |
| **Checklist Management** | Template modal | Admin only | Full CRUD on checklists and items, all isChecked=false |

---

### 1. Template CRUD Operations

#### Create New Template

**UI Access**:
- Settings > Presets > Spaces tab
- "Click to create new template" row in table

**Creation Flow**:
- Opens modal titled "Create space template"
- Fields:
  - **Name** (required, text input with validation)
  - **Notes** (optional, textarea, 4 rows)
  - **Checklists** (optional, full CRUD interface)

**Business Logic**:
- Name is trimmed and required
- Notes are trimmed; empty strings converted to `null`
- Checklists default to empty array `[]`
- On create:
  - `isArchived = false`
  - `sortOrder` auto-calculated as `max(existing) + 1`
  - Success message: "Template created successfully"

#### Edit Template

**UI Access**: Three-dot menu > "Edit"

**Edit Flow**:
- Same modal as create, pre-filled with existing values
- User can modify name, notes, and checklists
- Save button: "Save changes"

**Business Logic**:
- Same validation as create
- Version incremented for conflict detection
- Success message: "Template updated successfully"

#### Archive Template (Soft Delete)

**UI Access**: Three-dot menu > "Archive"

**Archive Behavior**:
- Sets `isArchived = true`
- Template disappears from active list
- Hidden from space creation picker
- Frees template name for reuse
- Success message: "Template archived successfully"

#### Unarchive Template (Restore)

**UI Access**:
- Toggle "Show Archived" button (top-right)
- Click "Unarchive" button on archived template row

**Unarchive Behavior**:
- Sets `isArchived = false`
- Template returns to active list
- Becomes visible in space creation picker
- May fail if name conflict exists with active template
- Success message: "Template unarchived successfully"

#### Delete Template (Hard Delete)

**Implementation Status**: Service method exists but NOT exposed in UI

**Business Rule**: Hard delete is NOT recommended. Use archive instead to preserve provenance and prevent accidental data loss.

**If hard deleted**: `spaces.templateId` automatically set to `null` (foreign key: ON DELETE SET NULL)

---

### 2. Template Checklists Management

Templates support multiple checklists with items, managed within the create/edit modal.

#### Add Checklist
- Button: "Add Checklist" (top-right of Checklists section)
- Creates checklist with default name "New Checklist", empty items array
- Client-generated UUID

#### Edit Checklist Name
- Click name to enter edit mode
- Commit on blur or Enter
- Trimmed; empty defaults to "Checklist"

#### Delete Checklist
- Trash icon on checklist header
- Immediate delete, no confirmation

#### Add Checklist Item
- Input field at bottom of each checklist: "Add item..."
- Press Enter or click "Add" button
- **Critical**: All items created with `isChecked: false`

#### Edit Checklist Item
- Click item text to enter edit mode
- Commit on blur or Enter
- Escape key cancels edit
- Trimmed; empty defaults to "Item"

#### Delete Checklist Item
- X icon on each item
- Immediate delete, no confirmation

**Default State Rule**: All checklist items in templates MUST have `isChecked: false`. When a space is created from a template, items remain unchecked by default.

---

### 3. Template Organization

#### Drag-to-Reorder

**UI**:
- GripVertical icon in leftmost column
- Drag handle appears on active templates only

**Behavior**:
- Drag start: row opacity 50%
- Drag over: target row highlighted with blue border
- Drop: reorders templates, saves new order to database
- Updates `sortOrder` field with sequential integers

**Reordering Logic**:
- Only affects active templates (archived excluded)
- Optimistic update (immediate UI feedback)
- Calls `spaceTemplatesService.updateTemplateOrder()` for batch update
- On error: reverts by reloading templates

#### Sort Order Persistence

**Database Field**: `sortOrder` (integer, nullable)

**Sort Order**:
- Primary: `sortOrder ASC NULLS LAST`
- Secondary: `name ASC`

**Auto-Assignment**:
- New templates: `sortOrder = max(existing) + 1`
- Drag-to-reorder: sequential integers (1, 2, 3, ...)

---

### 4. UI/UX Details

#### Location in Settings

**Navigation Path**: Settings > Presets > Spaces

**Tab Structure**:
- Settings has Presets tab
- Presets has 4 sub-tabs: Budget Categories, Vendor Defaults, Tax Presets, **Spaces**

#### Layout: Table View

**Table Columns**:
1. Drag handle (GripVertical icon, 40px)
2. Template name (truncated)
3. Actions menu (three-dot icon, 40px)

**Active Template Row**:
- Drag handle (left)
- Template name (bold, gray-900)
- Three-dot menu (right)

**Archived Template Row**:
- No drag handle
- Template name (gray-500, indicates inactive)
- Unarchive button (replaces three-dot menu)

**Empty States**:
- No templates: "No templates found. Create your first template to get started."
- No archived: "No archived templates."

#### Actions Menu (Three-Dot Dropdown)

**Menu Items**:
1. **Edit** (Edit2 icon): Opens edit modal
2. **Archive** (Archive icon): Archives template

**Menu Behavior**:
- Portal-based dropdown (document.body)
- Smart positioning (stays within viewport)
- Closes on: click outside, Escape, selecting item

#### Create/Edit Modal

**Modal Layout**:
- Header: Title + subtitle + close button
- Body (scrollable): Name input (required, auto-focus), Notes textarea, Checklists section
- Footer: Cancel button, Save button (disabled if name empty)

**Modal Behavior**:
- Click outside: closes modal
- Escape key: closes modal
- Max-height: `calc(100dvh - 2rem)`

#### Show/Hide Archived Toggle

**UI**: Button in top-right (above table)

**Behavior**:
- Text: "Show Archived" / "Hide Archived" (toggles)
- Only visible when NOT creating/editing
- Triggers template reload with `includeArchived` parameter

---

### 5. Permissions

#### Admin-Only Access

**Enforcement**: UI-level (RLS policies permissive for all account members)

**Visibility Gate**:
- Presets tab only visible if `isAdmin === true`
- Based on `account_memberships.role` field

**Who Can Manage Templates**:
- **Admins**: Full access (create, edit, archive, unarchive, reorder)
- **Users**: Cannot access Presets tab
- **Owners**: Full access (same as admins)

---

### 6. Integration with Space Creation

#### Template Picker in SpaceNew

**Picker Structure**:
- Label: "Start from Template (optional)"
- Select dropdown:
  - Default: "Start blank" (value = "")
  - Template options: `{template.name}` (value = template.id)
- Help text: "Select a template to prefill name and notes, or start blank."

#### Template Selection Behavior

**When Template Selected**:
1. Prefill name: `template.name`
2. Prefill notes: `template.notes || ''`
3. Checklists included in submission (not shown in UI)

**When "Start Blank" Selected**:
- Name and notes reset to empty
- Checklists default to empty array

#### Checklist Normalization

**Critical Function**: `normalizeChecklistsFromTemplate()`

**Purpose**: Ensures all checklist items start UNCHECKED when creating space from template

**Logic**:
```typescript
const normalizeChecklistsFromTemplate = (checklists: SpaceChecklist[]): SpaceChecklist[] => {
  return checklists.map(checklist => ({
    ...checklist,
    items: checklist.items.map(item => ({
      ...item,
      isChecked: false // Always start unchecked
    }))
  }))
}
```

**Why This Matters**: Templates store structure, not completion state. New spaces must start with all items unchecked.

#### Template List Filtering

**Templates Shown in Picker**:
- Only templates where `isArchived = false`
- Sorted by `sortOrder ASC, name ASC`

---

### 7. Data Model

#### SpaceTemplate Interface

```typescript
interface SpaceTemplate {
  id: string
  accountId: string
  name: string  // required, trimmed
  notes?: string | null
  checklists?: SpaceChecklist[]  // all items have isChecked=false
  isArchived: boolean
  sortOrder?: number | null
  metadata?: Record<string, any> | null
  createdAt: Timestamp
  updatedAt: Timestamp
  createdBy?: string | null
  updatedBy?: string | null
  version: number  // for optimistic locking
}
```

#### Validation Rules

**Name**:
- Required (non-empty after trim)
- Unique per account for active templates (case-insensitive)

**Notes**:
- Optional, trimmed
- Empty strings → `null`

**Checklists**:
- Optional (defaults to `[]`)
- Each checklist must have: `id` (UUID), `name` (non-empty), `items` (array)
- Each item must have: `id` (UUID), `text` (non-empty), `isChecked` (boolean, MUST be `false` in templates)

---

### 8. Business Rules

#### Template Deletion and Space References

**Soft Delete (Archive)**:
- Does NOT affect referencing spaces
- Spaces retain `templateId`
- Archived templates hidden from pickers only

**Hard Delete** (not recommended):
- Foreign key: `ON DELETE SET NULL`
- Spaces NOT deleted, but `templateId` → `null`
- Space data preserved, only provenance link lost

**Recommendation**: Use archive instead of hard delete.

#### Template Name Reuse

**Rule**: Active template names must be unique per account (case-insensitive)

**Behavior**:
- Archiving frees name for reuse
- Can create new active template with archived template's name
- Unarchiving may fail if name conflict exists

#### Template Modifications and Existing Spaces

**Rule**: Templates and spaces are decoupled after creation.

**Behavior**:
- Editing template does NOT update existing spaces
- Template is blueprint; spaces are instances
- `templateId` preserves provenance only (not a live link)

---

### Legacy Parity Sources

**Core Implementation**:
- `src/components/spaces/SpaceTemplatesManager.tsx` (890 lines)

**Services**:
- `src/services/spaceTemplatesService.ts` (256 lines)

**Space Creation Integration**:
- `src/pages/SpaceNew.tsx` (253 lines)

**Database**:
- `supabase/migrations/20260124_create_space_templates_and_space_template_id.sql`

---

## Offline-First Behavior (Mobile Target)

### Local Source of Truth
- UI reads from **Firestore's local cache** (cache-first reads)
- User writes are **direct Firestore writes** (queued offline)
- Media attachments represented locally via `offline://<mediaId>` placeholders
  - When upload completes: Space doc patched with remote URL
  - Upload state: derived locally, NOT persisted on Space doc

### Cold Start Behavior
- Spaces list renders from local cache (avoid empty flash)
- Space detail renders from local cache (space + images + checklists + items)

### Reconnect Behavior
- Foregrounded screens converge via Firestore listeners
- Queued writes acknowledged and synced
- Clear any "hydrated from cache" stale indicator

### Scoped Listeners (Required)
- **Never unbounded listeners** (no "listen to everything")
- Spaces: Bounded query on `accounts/{accountId}/spaces` with `projectId == <scope>` and `isArchived == false`
- Items in space: Bounded query on `accounts/{accountId}/items` with `spaceId == <spaceId>`
- Detach listeners on background; reattach on foreground

**Canonical architecture source:**
- `OFFLINE_FIRST_V2_SPEC.md`
- `src/data/LISTENER_SCOPING.md`

---

## Permissions & Gating

### Authentication
- User must be authenticated with active `accountId`
- All space operations require account context

### Role-Based Features
- **"Save as Template"**: Admin-only (client gating for UX; server enforcement required)
- **Settings > Space Templates**: Admin-only
- **Space CRUD**: All authenticated users

### Business Inventory Spaces
- If Business Inventory creation/edit is role-gated (per `40_features/business-inventory/feature_spec.md`), inventory spaces should follow same policy

---

## Cross-Cutting Dependencies

| Dependency | Reference | Scope |
|------------|-----------|-------|
| **Offline Data v2** | `OFFLINE_FIRST_V2_SPEC.md` | Firestore-native persistence, scoped listeners, request-docs |
| **Image Gallery/Lightbox** | `40_features/_cross_cutting/ui/components/image_gallery_lightbox.md` | Shared gallery behavior |
| **Offline Media Lifecycle** | `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md` | Media upload, sync, placeholders |
| **Inventory Operations** | `40_features/inventory-operations-and-lineage/...` | Allocation/deallocation flows for pull-in |
| **Space Templates (Settings)** | `40_features/settings-and-admin/...` | Template management UI |
| **Shared Items/Transactions** | `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md` | Item CRUD, ExistingItemsPicker |

---

## Known Gaps & Open Questions

### Gaps Noted in Spec

1. **Drag-to-reorder checklists/items**: NOT implemented in v1
   - Templates have drag-reorder; checklists don't
   - Priority: Low (can add later)

2. **Restore deleted spaces**: NOT implemented in v1
   - No UI for viewing/restoring deleted spaces
   - Templates have archive/unarchive toggle; spaces don't
   - Priority: Medium (future enhancement)

3. **Item field migration (`space` → `spaceId`)**: Deferred to separate migrator
   - Legacy items have both fields
   - Mobile will ignore `item.space` entirely
   - Priority: High (data consistency)

4. **Bulk space operations**: NOT implemented in v1
   - No multi-select/delete for multiple spaces
   - Priority: Low (nice-to-have)

5. **Space search on detail page**: NOT implemented
   - Item tab has search in picker, but space detail items list has no search
   - Priority: Medium (UX improvement)

### Resolved Decisions

✅ **Item Count Performance**: Use scoped query with count aggregation
✅ **Delete Space Cleanup**: Cloud Function trigger on `isArchived` change (async, 1-2 sec delay)
✅ **Business Inventory Spaces**: Greenfield feature (no migration from legacy account-wide spaces)
✅ **Soft Delete Terminology**: UI says "Delete Space", backend uses `isArchived = true`
✅ **No Restore in v1**: Deleted spaces hidden permanently (can add restore later)
✅ **Outside Items Search**: Client-side filtering for v1, SQLite FTS5 upgrade path for Phase 2
✅ **Checklist Conflicts**: Last-write-wins (no conflict UI in v1)
✅ **Space Image Quota**: 50 images max per space (vs 5 for items)
✅ **Inline Space Creation Error**: Queue for offline sync, optimistic update
✅ **Space Templates Management**: Complete feature documentation added to spec (admin-only, full CRUD)

### Open Questions

**Q1: Outside Items Search Strategy** ✅ RESOLVED

**Decision:** Use client-side filtering for v1, upgrade to SQLite FTS5 in Phase 2 when needed.

**v1 Implementation:**
- One-time Firestore query loads all account items when picker opens
- Client-side filtering over cached results (proven pattern from SharedItemsList)
- Fast via Firestore local cache (<100ms after first load)
- Acceptable performance for <5000 items
- Fully offline-capable

**Phase 2 Upgrade Path:**
- Integrate existing SQLite FTS5 search-index module (already built in `/src/search-index/`)
- Extend for account-wide scope (cross-project search)
- Provides fuzzy matching, BM25 ranking, better performance at scale
- Triggers: Users complain search is slow, accounts exceed 5000 items, need fuzzy matching

**Infrastructure Status:**
- Current app uses 100% client-side filtering for all search (items, transactions)
- Works well for current scale (~100-200 items per scope)
- SQLite FTS5 module exists but not yet integrated
- Clear upgrade path when needed

---

**Q2: Conflict Resolution for Checklist Edits** ✅ RESOLVED

**Decision:** Last-write-wins (simple, acceptable for checklists)

If two users edit the same checklist item simultaneously offline:
- Firestore applies last-write-wins with `serverTimestamp` ordering
- No conflict resolution UI in v1
- Can add conflict detection UI later if users report issues

---

**Q3: Space Image Upload Quota** ✅ RESOLVED

**Decision:** Spaces can have up to **50 images** (significantly more than items)

**Rationale:**
- Spaces represent larger areas (rooms, storage zones) vs individual items
- Users may want comprehensive photo documentation of spaces
- Items: 5 images max (small objects)
- Spaces: 50 images max (larger areas with more documentation needs)

---

**Q4: Space Templates Management** ✅ RESOLVED

**Decision:** Complete feature documentation added to spec.

**Coverage:**
- Full CRUD operations (create, edit, archive, unarchive, delete)
- Checklist management within templates
- Drag-to-reorder with sortOrder persistence
- Admin-only permissions
- Integration with space creation
- Business rules and data model

See: [Space Templates Management (Settings Feature)](#space-templates-management-settings-feature) section for complete details.

---

**Q5: Inline Space Creation - Error Handling** ✅ RESOLVED

**Decision:** Queue creation for offline sync, optimistically show in dropdown (Option B)

When user creates space via `SpaceSelector` inline:
- Optimistically add space to dropdown immediately
- Queue Firestore write (handled by offline persistence)
- If write fails on reconnect: Show error toast with retry option
- Consistent with offline-first principles

---

## Acceptance Criteria

See `acceptance_criteria.md` in feature folder for detailed test scenarios.

**Summary criteria:**
- ✅ Create project space and inventory space
- ✅ Create space from template (prefills name/notes/checklists)
- ✅ Inline create space via SpaceSelector
- ✅ Edit space name/notes
- ✅ Delete space (soft delete, clears item assignments)
- ✅ Upload multiple images (drag-drop on desktop, camera/gallery on mobile)
- ✅ Set primary image
- ✅ Remove image
- ✅ View images in full-screen gallery
- ✅ Add/edit/delete checklists and items
- ✅ Toggle checklist item checkboxes
- ✅ Add new item to space
- ✅ Add existing items from current workspace
- ✅ Add existing items from outside workspace (with pull-in)
- ✅ Search existing items (description, SKU, price)
- ✅ Multi-select items with select-all
- ✅ View duplicate-grouped items
- ✅ Bulk move items to another space
- ✅ Bulk remove items from space
- ✅ Save space as template (admin-only)
- ✅ Search spaces by name/notes
- ✅ Offline: Create/edit/view spaces without network
- ✅ Offline: Upload images with placeholders
- ✅ Reconnect: Sync queued changes

---

## Implementation Phases

**Phase 1: Core CRUD (Highest Priority)**
- Spaces list (project + BI)
- Create/edit/delete space
- Inline space creation (SpaceSelector)
- Basic image upload (using shared components)
- Checklists CRUD

**Phase 2: Items Management**
- Items tab with list
- Create new item in space
- Add existing items picker (current workspace only)
- Bulk operations (move/remove)

**Phase 3: Advanced Picker (Requires Search Index)**
- Outside items tab in picker
- Cross-workspace pull-in flows
- Duplicate grouping
- Search with auto-tab-switch

**Phase 4: Templates & Polish**
- Template picker in create flow
- Save as template (admin)
- Settings: Template management (if not covered by settings spec)
- Image gallery enhancements (zoom/pan)

---

## Legacy Parity Sources

**Key files in `/Users/benjaminmackenzie/Dev/ledger`:**

| File | Lines | Purpose |
|------|-------|---------|
| `src/pages/ProjectSpacesPage.tsx` | ~300 | Spaces list, search, grid |
| `src/pages/SpaceDetail.tsx` | 1,127 | Space detail with tabs (main reference) |
| `src/pages/SpaceNew.tsx` | ~200 | Create space, template picker |
| `src/pages/SpaceEdit.tsx` | ~150 | Edit name/notes |
| `src/components/spaces/SpaceSelector.tsx` | ~250 | Inline creation |
| `src/components/spaces/SpacePreviewCard.tsx` | ~100 | Grid card with offline images |
| `src/components/spaces/SpaceTemplatesManager.tsx` | ~400 | Settings: Template management |
| `src/components/items/ExistingItemsPicker.tsx` | 792 | Add existing items picker |
| `src/components/items/AddExistingItemsModal.tsx` | 85 | Modal wrapper |
| `src/services/spaceService.ts` | ~400 | Space CRUD operations |
| `src/services/spaceTemplatesService.ts` | ~300 | Template CRUD operations |
| `src/services/itemPullInService.ts` | 44 | Pull-in logic for outside items |
| `src/utils/itemGrouping.ts` | 113 | Duplicate grouping logic |
| `src/pages/ItemDetail.tsx` | 1,816 | Image upload reference (lines 889-1256) |
| `src/components/ui/ImageUpload.tsx` | 496 | Shared drag-drop upload |
| `src/components/ui/ImagePreview.tsx` | 589 | Shared thumbnail grid |
| `src/components/ui/ImageGallery.tsx` | 706 | Shared full-screen viewer |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-06 | Initial draft with comprehensive feature documentation |
| 1.1 | 2026-02-06 | Updated with final decisions: soft delete strategy, BI greenfield, item count approach. Outside items search strategy under investigation. |
| 1.2 | 2026-02-06 | Finalized search strategy: client-side filtering for v1 with SQLite FTS5 upgrade path. Spec ready for review. |
| 1.3 | 2026-02-06 | Added complete Space Templates Management documentation. All open questions resolved. Spec ready for implementation. |

---

## Notes

- This spec is **draft status** and requires review before implementation
- Business Inventory spaces are **NEW functionality** (not legacy parity)
- Account-wide spaces migration strategy TBD
- Search index requirement for "outside items" picker deferred to Phase 3
- Image upload patterns reference Item Detail implementation (preferred over Space-specific legacy code)
