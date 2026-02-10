---
work_package_id: WP01
title: Consolidate Space Detail Screens
lane: "doing"
dependencies: []
base_branch: main
base_commit: f7f8bf37cc020e9ee65899fd42429328da2b8e90
created_at: '2026-02-10T02:52:26.216718+00:00'
subtasks:
- T001
- T002
- T003
- T004
- T005
- T006
phase: Phase 1 - Space Consolidation + SectionList Migration
assignee: ''
agent: ''
shell_pid: "85660"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-10T02:25:42Z'
  lane: planned
  agent: system
  shell_pid: ''
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP01 – Consolidate Space Detail Screens

## Important: Review Feedback Status

**Read this first if you are implementing this task!**

- **Has review feedback?**: Check the `review_status` field above. If it says `has_feedback`, scroll to the **Review Feedback** section immediately.
- **You must address all feedback** before your work is complete.
- **Mark as acknowledged**: When you understand the feedback and begin addressing it, update `review_status: acknowledged` in the frontmatter.

---

## Review Feedback

> **Populated by `/spec-kitty.review`** – Reviewers add detailed feedback here when work needs changes.

*[This section is empty initially.]*

---

## Implementation Command

```bash
spec-kitty implement WP01
```

No dependencies — this is the starting work package.

---

## Objectives & Success Criteria

- **Objective**: Eliminate ~1,000 lines of duplication by consolidating the two near-identical space detail screens (`app/business-inventory/spaces/[spaceId].tsx` at 1,043 lines and `app/project/[projectId]/spaces/[spaceId].tsx` at 1,051 lines) into a single shared `SpaceDetailContent` component.
- **Secondary objective**: Normalize space media handling by replacing the manual `ThumbnailGrid` + `ImageGallery` + `ImagePickerButton` pattern with the existing `MediaGallerySection` component.

**Success Criteria**:
1. A single `src/components/SpaceDetailContent.tsx` renders all space detail content
2. Both route files are reduced to thin wrappers (~20 lines each)
3. Space images use `MediaGallerySection` instead of manual ThumbnailGrid/ImageGallery/ImagePickerButton
4. All existing functionality preserved: images, notes, items, checklists, bulk operations, picker modals
5. No visual regressions when navigating to spaces from either business inventory or project context
6. All offline-first patterns preserved: fire-and-forget Firestore writes, cache-first reads

## Context & Constraints

**Reference documents**:
- `kitty-specs/004-detail-screen-normalization/spec.md` — User Stories 2 (unified space) and 4 (normalized media)
- `kitty-specs/004-detail-screen-normalization/plan.md` — Phase 1, WP-01
- `kitty-specs/004-detail-screen-normalization/research.md` — Section 2 (consolidation analysis) and Section 4 (media analysis)
- `kitty-specs/004-detail-screen-normalization/data-model.md` — Section 2 (SpaceDetailContent props, route wrappers)

**Architectural constraints**:
- **Offline-first**: All Firestore writes remain fire-and-forget with `.catch()`. No `await` on Firestore writes in UI code.
- **Route preservation**: URL structure must be preserved. Both route files remain but become thin wrappers.
- **Import paths**: Components in `src/components/` use relative imports. Route wrappers in `app/` import from `../../src/` or deeper.

**Key insight from research**: The two space files differ ONLY in:
1. Route params (`spaceId` only vs `projectId + spaceId`)
2. Scope config (`createInventoryScopeConfig()` vs `createProjectScopeConfig(projectId)`)
3. `useOutsideItems` config (scope, includeInventory, currentProjectId)
4. Navigation routes (back, edit, delete, item detail)
5. Picker tab labels ("In Business Inventory" vs "Project")
6. `resolveItemMove` targetProjectId
7. Minor style differences (margins)

Everything else — state, hooks, handlers, JSX structure, modals — is identical.

---

## Subtasks & Detailed Guidance

### Subtask T001 – Create SpaceDetailContent component skeleton

**Purpose**: Establish the shared component file with proper types, imports, and the scope-based API.

**Steps**:
1. Create `src/components/SpaceDetailContent.tsx`
2. Define the scope type (from data-model.md):
   ```typescript
   type SpaceScope = {
     projectId: string | null;  // null = business inventory
     spaceId: string;
   };

   type SpaceDetailContentProps = {
     scope: SpaceScope;
     onSpaceNameChange: (name: string) => void;
     spaceMenuVisible: boolean;
     onCloseSpaceMenu: () => void;
   };
   ```
3. Copy all imports from `app/business-inventory/spaces/[spaceId].tsx` (the BI version is the reference copy), adjusting import paths from `../../../src/...` to `../...` (since the component is in `src/components/`)
4. Copy the helper functions (`randomId`, `getPrimaryImageUri`, `formatCents`, `getDisplayPrice`) — these are identical in both files
5. Copy the shared type aliases (`ItemPickerTab`, `SortMode`)
6. Export the component function with the new props signature

**Files**:
- `src/components/SpaceDetailContent.tsx` (new, initial skeleton ~50 lines)

**Notes**: Don't implement the full body yet — T002 fills in state/hooks/handlers. This step focuses on getting the file structure and types right.

---

### Subtask T002 – Extract shared state, hooks, and handlers

**Purpose**: Move the ~20 state variables, subscription hooks, and ~15 handler functions from the BI space detail into SpaceDetailContent.

**Steps**:
1. Copy all state declarations from `BISpaceDetailContent` (lines 119-157 in BI file) into SpaceDetailContent
2. **Parameterize scope config** — replace the static `createInventoryScopeConfig()` call:
   ```typescript
   const scopeConfig = useMemo(
     () => scope.projectId
       ? createProjectScopeConfig(scope.projectId)
       : createInventoryScopeConfig(),
     [scope.projectId]
   );
   ```
3. **Parameterize useOutsideItems** — replace static config:
   ```typescript
   const outsideItemsHook = useOutsideItems({
     accountId,
     currentProjectId: scope.projectId ?? null,
     scope: scope.projectId ? 'project' : 'inventory',
     includeInventory: scope.projectId ? true : false,
   });
   ```
4. Copy all subscription effects (`useEffect` for space data, items, etc.)
5. Copy all handler functions:
   - `handleSaveChecklists`
   - `handleAddImage`, `handleRemoveImage`, `handleSetPrimaryImage`
   - `handleAddSelectedItems`, `handleAddSingleItem`
   - `handleBulkRemove`, `handleBulkMove`
   - `handleDelete`
   - `handleSaveTemplate`
   - `handleCreateItemInSpace`
6. Copy all `useMemo` menu builders (`spaceMenuItems`, `sortMenuItems`, `filterMenuItems`, `addMenuItems`)
7. Copy the filtered items computation (`filteredSpaceItems` useMemo)

**Files**:
- `src/components/SpaceDetailContent.tsx` (modify, adding ~400 lines of state/hooks/handlers)

**Notes**:
- Don't parameterize navigation yet (T003 handles that)
- Leave hardcoded route strings temporarily — they'll be parameterized in T003
- Ensure all `useCallback` dependency arrays include `scope.projectId` where appropriate

---

### Subtask T003 – Parameterize navigation and scope-dependent logic

**Purpose**: Replace all hardcoded navigation routes and scope-specific values with parameterized versions that derive from `scope.projectId`.

**Steps**:
1. Create route builder helpers inside or above the component:
   ```typescript
   function getBackTarget(projectId: string | null): string {
     return projectId
       ? `/project/${projectId}?tab=spaces`
       : '/business-inventory/spaces';
   }

   function getEditRoute(projectId: string | null, spaceId: string): string {
     return projectId
       ? `/project/${projectId}/spaces/${spaceId}/edit`
       : `/business-inventory/spaces/${spaceId}/edit`;
   }

   function getDeleteTarget(projectId: string | null): string {
     return projectId
       ? `/project/${projectId}?tab=spaces`
       : '/business-inventory/spaces';
   }

   function getItemDetailRoute(
     projectId: string | null,
     spaceId: string,
     itemId: string
   ): { pathname: string; params: Record<string, string> } {
     return {
       pathname: '/items/[id]',
       params: {
         id: itemId,
         scope: projectId ? 'project' : 'inventory',
         ...(projectId ? { projectId } : {}),
         backTarget: projectId
           ? `/project/${projectId}/spaces/${spaceId}`
           : `/business-inventory/spaces/${spaceId}`,
       },
     };
   }
   ```
2. Replace all hardcoded navigation in handlers:
   - `handleDelete`: use `getDeleteTarget(scope.projectId)`
   - `handleCreateItemInSpace`: use scope-based params
   - `spaceMenuItems`: use `getEditRoute(scope.projectId, scope.spaceId)`
   - Item card `onPress`: use `getItemDetailRoute(...)`
   - Item card "Open" menu action: use `getItemDetailRoute(...)`
3. Parameterize `handleAddSelectedItems` and `handleAddSingleItem`:
   - `targetProjectId: scope.projectId ?? null`
   - Guard: `if (!accountId)` (remove projectId guard from project version — projectId can be null for BI)
4. Parameterize picker tab labels:
   ```typescript
   const pickerTabLabel = scope.projectId ? 'Project' : 'In Business Inventory';
   ```
5. Parameterize `SpaceSelector` in bulk panel: `projectId={scope.projectId}`

**Files**:
- `src/components/SpaceDetailContent.tsx` (modify)

**Notes**:
- Verify all dependency arrays in `useCallback`/`useMemo` include `scope.projectId` and `scope.spaceId`
- The route wrappers (T005) will pass these via the `scope` prop

---

### Subtask T004 – Replace space media with MediaGallerySection

**Purpose**: Replace the manual ThumbnailGrid + ImageGallery + ImagePickerButton pattern with the existing `MediaGallerySection` component for consistent media handling.

**Steps**:
1. Remove imports for `ThumbnailGrid`, `ImageGallery`, `ImagePickerButton` from SpaceDetailContent
2. Add import for `MediaGallerySection` (already in `src/components/`)
3. Remove the `galleryVisible` and `galleryIndex` state variables (MediaGallerySection manages its own lightbox state internally)
4. Replace the images section JSX:

   **Before** (inline ThumbnailGrid + ImagePickerButton + ImageGallery):
   ```tsx
   {/* Images */}
   <ThumbnailGrid images={space.images ?? []} onPress={...} onSetPrimary={...} onDelete={...} />
   {space.images && space.images.length < 50 && (
     <ImagePickerButton onImagePicked={handleAddImage} />
   )}
   {/* ... later ... */}
   <ImageGallery images={space.images} visible={galleryVisible} ... />
   ```

   **After**:
   ```tsx
   <MediaGallerySection
     title="Images"
     attachments={space.images ?? []}
     maxAttachments={100}
     allowedKinds={['image']}
     onAddAttachment={handleAddImage}
     onRemoveAttachment={handleRemoveImage}
     onSetPrimary={handleSetPrimaryImage}
     emptyStateMessage="No images yet."
     pickerLabel="Add image"
     size="md"
     tileScale={1.5}
   />
   ```

5. Adapt handler signatures to match MediaGallerySection expectations:
   - `handleAddImage(localUri: string, kind: AttachmentKind)` — current space handler takes `(localUri: string)`, needs to accept `kind` param (ignore it since spaces only allow images)
   - `handleRemoveImage(attachment: AttachmentRef)` — current handler takes `(imageUrl: string)`, needs to accept `AttachmentRef` and extract `.url`
   - `handleSetPrimaryImage(attachment: AttachmentRef)` — current handler takes `(imageUrl: string)`, needs to accept `AttachmentRef` and extract `.url`
6. Remove the ImageGallery modal JSX (no longer needed — MediaGallerySection handles this internally)

**Files**:
- `src/components/SpaceDetailContent.tsx` (modify)

**Edge Cases**:
- Spaces can have many images (50+ per the current cap). Setting `maxAttachments={100}` ensures no artificial limit
- `MediaGallerySection` already handles offline:// URIs via `resolveAttachmentUri`
- Handler signature change: ensure fire-and-forget pattern is preserved (no await on Firestore writes)

---

### Subtask T005 – Reduce both route files to thin wrappers

**Purpose**: Replace the 1,040+ line route files with ~20-line wrappers that render `SpaceDetailContent`.

**Steps**:
1. Rewrite `app/business-inventory/spaces/[spaceId].tsx`:
   ```typescript
   import { useState } from 'react';
   import { useLocalSearchParams, useRouter } from 'expo-router';
   import { Screen } from '../../../src/components/Screen';
   import { SpaceDetailContent } from '../../../src/components/SpaceDetailContent';
   // ... other minimal imports for Screen props

   type SpaceParams = { spaceId?: string };

   export default function BusinessInventorySpaceDetailScreen() {
     const { spaceId } = useLocalSearchParams<SpaceParams>();
     const router = useRouter();
     const [spaceName, setSpaceName] = useState('Space');
     const [menuVisible, setMenuVisible] = useState(false);

     if (!spaceId) {
       return <Screen title="Space" backTarget="/business-inventory/spaces"><AppText>Space not found.</AppText></Screen>;
     }

     return (
       <Screen
         title={spaceName}
         backTarget="/business-inventory/spaces"
         onPressMenu={() => setMenuVisible(true)}
       >
         <SpaceDetailContent
           scope={{ projectId: null, spaceId }}
           onSpaceNameChange={setSpaceName}
           spaceMenuVisible={menuVisible}
           onCloseSpaceMenu={() => setMenuVisible(false)}
         />
       </Screen>
     );
   }
   ```

2. Rewrite `app/project/[projectId]/spaces/[spaceId].tsx`:
   ```typescript
   // Same pattern but with projectId
   export default function ProjectSpaceDetailScreen() {
     const { projectId, spaceId } = useLocalSearchParams<{ projectId?: string; spaceId?: string }>();
     // ...
     return (
       <Screen
         title={spaceName}
         backTarget={`/project/${projectId}?tab=spaces`}
         onPressMenu={() => setMenuVisible(true)}
       >
         <SpaceDetailContent
           scope={{ projectId: projectId!, spaceId: spaceId! }}
           onSpaceNameChange={setSpaceName}
           spaceMenuVisible={menuVisible}
           onCloseSpaceMenu={() => setMenuVisible(false)}
         />
       </Screen>
     );
   }
   ```

3. Remove all unused imports, state, handlers, styles from both route files
4. Verify that the `Screen` component's `backTarget` is set correctly in each wrapper

**Files**:
- `app/business-inventory/spaces/[spaceId].tsx` (rewrite, ~1,040 lines → ~25 lines)
- `app/project/[projectId]/spaces/[spaceId].tsx` (rewrite, ~1,050 lines → ~25 lines)

**Notes**:
- The `Screen` component provides the header chrome (title, back button, menu button)
- `spaceName` state is lifted to the wrapper so `Screen` title updates when space loads
- `spaceMenuVisible` is lifted so the menu button in `Screen` can trigger it
- SpaceDetailContent calls `onSpaceNameChange` when the space loads to update the title

---

### Subtask T006 – Normalize styles and clean up accidental divergence

**Purpose**: Resolve minor accidental differences between the two original files and establish a clean baseline.

**Steps**:
1. Use the BI version's style as reference:
   - `sectionHeader`: include `marginTop: 8`
   - `bulkPanel`: include `marginBottom: 12`
   - `bulkModeToggle`: include `marginBottom: 8`
2. Remove the unused `checklists` style (present in project version but never used)
3. Normalize unicode: use consistent `'…'` (not `'\u2026'`) throughout
4. Clean up any dead code, unused imports, or commented-out sections
5. Verify the SpaceDetailContent styles are consistent with the BI reference

**Files**:
- `src/components/SpaceDetailContent.tsx` (modify styles)

**Notes**: This is a cleanup pass. No functional changes.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Navigation breaks after consolidation | Low | High | Both route files remain; only content component changes. URL structure preserved. |
| Media handler signature mismatch | Low | Low | MediaGallerySection handlers accept `void \| Promise<void>`. Adapt space handlers to accept AttachmentRef. |
| Screen title not updating | Low | Medium | Lift spaceName state to wrapper, pass onSpaceNameChange callback. |
| Missing scope-specific behavior | Medium | Medium | Research doc lists ALL differences. Check each one during parameterization. |

## Review Guidance

**Key checkpoints for reviewers**:
1. Open a space from business inventory — all sections render, images load, items list works, checklists work
2. Open a space from a project — identical experience with project-specific context
3. Add/remove images — uses MediaGallerySection (no ThumbnailGrid/ImageGallery)
4. Bulk operations — move items between spaces, remove from space
5. Item picker — tab labels show correct context ("In Business Inventory" vs "Project")
6. Verify both route files are ~20 lines (thin wrappers only)
7. No offline-first violations: all Firestore writes are fire-and-forget

---

## Activity Log

- 2026-02-10T02:25:42Z – system – lane=planned – Prompt created.
