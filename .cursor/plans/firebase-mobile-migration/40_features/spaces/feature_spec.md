# Spaces — Feature spec (Firebase mobile migration)

## Intent
Provide an offline-ready Spaces experience inside a project: users can browse/search spaces, create/edit/delete spaces, and manage a space’s items, images, and checklists with predictable offline behavior.

Architecture baseline (mobile):
- **Firestore-native offline persistence** is the default (Firestore is canonical).
- “Freshness” while foregrounded is achieved via **scoped listeners** on bounded queries (never unbounded “listen to everything”).
- Any multi-doc/invariant operations use **request-doc workflows** (Cloud Function applies changes in a transaction).

## Definitions
- **Space**: a location/grouping entity used to organize items.
- **Space template**: an account-wide preset used to prefill a new space (name/notes/checklists).
- **Workspace scope** (required): where the Space “lives” and which Items may reference it:
  - **Project scope**: spaces within a specific project.
  - **Business Inventory scope**: spaces within the Business Inventory workspace (no `projectId`).

Migration stance (intentional model choice):
- **Spaces are workspace-scoped** (Project or Business Inventory). We do not model generic “account-wide spaces” that float across contexts; the reusable/account-wide concept is **templates**.
- **Business Inventory spaces are explicit**:
  - Legacy web traces used `space.projectId === null` as “Account-wide space”.
  - Migration requirement: `space.projectId === null` now **explicitly means Business Inventory scope**, not a generic catch‑all. Project spaces always have a concrete `projectId`.

## Scope + datastore locations (Firebase target; required)

### Space locations
- **All spaces** live under a single account-level collection:
  - Firestore: `accounts/{accountId}/spaces/{spaceId}`
  - Scope is defined by `space.projectId`:
    - Project space: `projectId = <projectId>`
    - Business Inventory space: `projectId = null`

### Item ↔ space reference rules (required)
- Items reference spaces via `item.spaceId`.
- **Scope consistency is mandatory**:
  - If `item.projectId = <projectId>`, then `item.spaceId` (when non-null) must refer to a Space with `space.projectId = <projectId>`.
  - If `item.projectId = null` (Business Inventory), then `item.spaceId` (when non-null) must refer to a Space with `space.projectId = null`.
- When an item changes scope (e.g. Business Inventory → Project allocation), `spaceId` must be updated/cleared as part of the same invariant operation so it never points at a space from the wrong scope.

## Owned screens / routes
- **Spaces list**: `ProjectSpacesPage`
  - Route: `/project/:projectId/spaces`
  - Web parity source: `src/pages/ProjectSpacesPage.tsx`
- **Create space**: `SpaceNew`
  - Route: `/project/:projectId/spaces/new`
  - Web parity source: `src/pages/SpaceNew.tsx`
- **Space detail**: `SpaceDetail`
  - Route: `/project/:projectId/spaces/:spaceId`
  - Web parity source: `src/pages/SpaceDetail.tsx`
- **Edit space**: `SpaceEdit`
  - Route: `/project/:projectId/spaces/:spaceId/edit`
  - Web parity source: `src/pages/SpaceEdit.tsx`

Business Inventory equivalents (conceptual; mobile routes may differ, but the scope must be explicit):
- **Inventory spaces list**: `BusinessInventorySpacesList`
  - Route concept: `/business-inventory/spaces`
- **Create inventory space**: `BusinessInventorySpaceNew`
  - Route concept: `/business-inventory/spaces/new`
- **Inventory space detail**: `BusinessInventorySpaceDetail`
  - Route concept: `/business-inventory/spaces/:spaceId`
- **Edit inventory space**: `BusinessInventorySpaceEdit`
  - Route concept: `/business-inventory/spaces/:spaceId/edit`

Screen contracts:
- `ui/screens/ProjectSpacesList.md`
- `ui/screens/SpaceDetail.md`
- `ui/screens/SpaceForm.md`

## Primary flows

### 1) Browse/search spaces
Summary:
- Spaces render in a grid of cards with:
  - primary image (or placeholder)
  - space name
  - item count (derived from items with `item.spaceId`)
- Search filters spaces by `name` and `notes` substring matches (case-insensitive).

Parity evidence:
- List/search + empty states: `src/pages/ProjectSpacesPage.tsx`
- Offline image resolution: `src/components/spaces/SpacePreviewCard.tsx`

Business Inventory scope (required):
- Business Inventory must support the same “browse/search spaces” UX within the inventory workspace, backed by `accounts/{accountId}/spaces` where `space.projectId = null`.
- Item counts must be computed from **inventory-scoped items only** (`projectId = null`) that reference the space via `spaceId`.

### 2) Create a space (optionally from template)
Summary:
- Create is launched from the Spaces list “Add”.
- A template picker can prefill `name` and `notes` (and supply checklists).
- Validation: `name` required.
- On success: show success toast, refresh collections, and close (returnTo / fallback).

Template checklist normalization (required):
- When creating from a template, template checklist items are copied but forced to `isChecked=false` at creation time.

Parity evidence:
- Template picker and prefill: `src/pages/SpaceNew.tsx`
- Checklist normalization: `normalizeChecklistsFromTemplate` in `src/pages/SpaceNew.tsx`
- Success + refresh: `refreshCollections({ includeProject: false })` in `src/pages/SpaceNew.tsx`

Business Inventory scope (required):
- Business Inventory supports creating spaces within the inventory workspace, backed by `accounts/{accountId}/spaces` where `space.projectId = null`.
- Templates remain account-wide; they can be used to create both project spaces and inventory spaces.

### 3) View space detail (tabs: Items / Images / Checklists)
Summary:
- Space detail shows:
  - header/back + actions menu
  - name
  - notes section
  - tabs:
    - Items: manage items assigned to the space
    - Images: manage space images (add/remove/set primary)
    - Checklists: manage checklists and checklist items

Parity evidence:
- Tab UI and action menu: `src/pages/SpaceDetail.tsx`

### 4) Assign/manage items in a space (Space detail → Items tab)
Summary:
- Items tab uses the shared itemization UI (`TransactionItemsList`) in “space context”:
  - Create a new item “in space”
  - Update existing item fields
  - Duplicate items
  - Bulk move selected items to another space
  - Bulk remove selected items from the current space
- “Add Existing Items” opens a modal picker that supports:
  - search + multi-select
  - select all (for the current tab / current result set)
  - duplicate-group aware selection
  - bulk “Add Selected”

Correct behavior (web parity; required):
- The picker must support pulling items from **any context**, not just the current workspace:
  - **Current workspace items** (same scope as the space)
  - **Outside items** (account-wide), including:
    - items from **other projects**
    - items from **Business Inventory** (items with `projectId = null`)
- When adding an outside item, the system must **pull the item into the target workspace** first (canonical behavior), then assign it to the space:
  - **Business Inventory → Project space**: allocate into the project via the canonical allocation flow, then set `spaceId`.
  - **Other project → Project space**: move with accounting via the canonical sell/move flow (deallocate+allocate), then set `spaceId`.
  - **Project → Business Inventory space**: deallocate to Business Inventory via the canonical deallocation flow, then set `spaceId`.
  - **Business Inventory → Business Inventory space**: set `spaceId` directly.
- Items that are already assigned to this space are excluded/disabled in the picker.
- Items that are currently tied to a transaction should be **blocked** in the Space picker (recommended parity + safety):
  - Reason shown: the item is tied to a transaction; use the transaction flow instead.

Parity evidence:
- Items tab wiring + bulk handlers: `src/pages/SpaceDetail.tsx` (TransactionItemsList props and `bulkSetSpaceId` / `bulkUnassignSpace`)
- Add existing items modal: `src/pages/SpaceDetail.tsx` + `src/components/spaces/SpaceItemPicker.tsx`
  - Outside-items UX pattern (tabs/search/select-all/duplicates/sticky add): `src/components/transactions/TransactionItemPicker.tsx`
  - Outside-items query semantics (other projects + optional business inventory): `unifiedItemsService.searchItemsOutsideProject(...)`
  - Canonical pull-in semantics for Spaces: `SPACES_ADD_EXISTING_ITEMS_PARITY_PLAN.md` (web repo), plus inventory ops flows in this migration plan (see below).

Migration notes:
- In Firebase/RN, these are local-first item mutations:
  - set/clear `item.spaceId`
  - and (optional, parity): set human-readable `item.space` name for display if retained in the data contract
- Do not implement an unbounded listener on all items just to compute “live item counts”. Use scoped/bounded queries and/or a denormalized counter strategy (if needed).

Business Inventory scope (required):
- The Items tab must work for inventory spaces as well:
  - “Add Existing Items” can pull from **any context** (projects + business inventory), but items must be pulled into the **inventory workspace** before assignment:
    - Project → inventory space: deallocate to inventory, then set `spaceId`.
    - Inventory → inventory space: set `spaceId`.
  - Bulk add/remove sets/clears `item.spaceId` on inventory items.
- Direct cross-scope linking is disallowed, but **cross-scope pull-in is allowed**:
  - after a pull-in operation completes, the item’s `projectId` must match the space’s scope, so `spaceId` remains scope-consistent.

Allocation touchpoint (required; Business Inventory → Project):
- Allocation flows may include an optional “destination space” choice for the target project.
- When allocating an inventory item to a project via the server-owned invariant (request-doc workflow):
  - set `item.projectId = <projectId>`
  - set/clear `item.spaceId` to a **project space id** selected by the user (or `null` if not selected)
  - ensure the resulting `spaceId` conforms to the “scope consistency” rules above
- Source of truth for allocation invariants: `40_features/inventory-operations-and-lineage/flows/business_inventory_to_project_allocation.md`.

### Implementation changes needed (to align mobile with correct behavior)
Mobile currently must implement more than “set `spaceId`”:
- **Picker UI parity**:
  - Provide a real “Add Existing Items” picker with tabs (at least “In this workspace” + “Outside”), search, duplicate grouping, select-all, and sticky “Add selected”.
- **Outside search**:
  - Support searching items outside the current workspace (other projects + business inventory) without unbounded listeners.
  - Recommended approach: use the derived search index module (Phase 2) + scoped queries per `OFFLINE_FIRST_V2_SPEC.md`.
- **Canonical pull-in operations**:
  - Adding outside items must run inventory operations invariants (request-doc / server-owned) before setting `spaceId`:
    - Business Inventory → Project allocation
    - Project → Business Inventory deallocation
    - Project → Project move/sell (deallocate+allocate)
  - Source of truth: `40_features/inventory-operations-and-lineage/…` flows (especially allocation and sell/move flows).
- **Guardrails**:
  - Block transaction-linked items in Space picker (recommended parity + safety), or explicitly define a confirmation + invariant flow if you want to allow it.

### 5) Manage space images (Space detail → Images tab)
Summary:
- User can add multiple images; uploads may create `offline://` placeholder URLs (renderable immediately).
- User can remove images and set a primary image.
- Image grid supports lightbox/gallery behavior consistent with the cross-cutting contract.
- Attachment contract (required; GAP B):
  - Persisted space images are `AttachmentRef[]` (see `20_data/data_contracts.md`), with `kind: "image"`.
  - Upload state (`local_only | uploading | failed | uploaded`) is derived locally per `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`, not stored on the Space doc.

Parity evidence:
- Add images + upload activity UI: `src/pages/SpaceDetail.tsx` (`handleAddImage`, `UploadActivityIndicator`)
- Remove/set primary: `src/pages/SpaceDetail.tsx` (`handleRemoveImage`, `handleSetPrimaryImage`)
- Offline placeholders + resolution on cards: `src/components/spaces/SpacePreviewCard.tsx` (offline blob resolution)
- Cross-cutting gallery: `40_features/_cross_cutting/ui/components/image_gallery_lightbox.md`

### 6) Manage checklists (Space detail → Checklists tab)
Summary:
- A space holds an ordered array of checklists; each checklist holds an ordered array of checklist items.
- Checklist behaviors are “inline edit with commit”:
  - Add checklist (default name “New Checklist”), immediately persists.
  - Rename checklist: click name to edit; commit on blur or Enter; empty names become “Checklist”.
  - Delete checklist: immediately persists.
  - Toggle checklist item checked state: immediately persists.
  - Rename checklist item: click to edit; commit on blur or Enter; Escape cancels edit; empty text becomes “Item”.
  - Add checklist item: Enter or “Add” button; new item defaults to unchecked; immediately persists.
  - Delete checklist item: immediately persists.

Parity evidence:
- Checklists UI and commit rules: `src/pages/SpaceDetail.tsx` (`updateChecklists`, `commitChecklistName`, `commitChecklistItemText`, inline handlers)

Migration notes:
- For Firebase/RN, checklist edits should be deterministic Firestore updates (queued offline by Firestore-native persistence). If conflict strategy is needed, define it explicitly (e.g., last-write-wins with serverTimestamp ordering).

### 7) Save space as template (admin-only)
Summary:
- From SpaceDetail actions menu, admin can “Save as Template”.
- Template form defaults to the space’s name/notes.
- Template checklists are copied but normalized so all items are unchecked before saving.

Parity evidence:
- Admin-only action + modal + normalization: `src/pages/SpaceDetail.tsx` (`isAdmin` gate, `normalizeChecklistsForTemplate`, `spaceTemplatesService.createTemplate`)

Out-of-scope linkage:
- Managing templates (archive/rename/edit template checklists) belongs to settings/presets (`settings-and-admin`).

### 8) Edit space
Summary:
- Edit updates `name` and `notes`.
- Navigation respects `returnTo` and falls back to space detail or spaces list.

Parity evidence:
- Edit load + save + returnTo: `src/pages/SpaceEdit.tsx`

### 9) Delete space
Summary:
- Delete is confirmed.
- If the space has items assigned, show a warning that items will not be deleted but their space assignment will be cleared.
- On success: navigate back to Spaces list.

Parity evidence:
- Delete confirm + warning: `src/pages/SpaceDetail.tsx` (`showDeleteConfirm` block)
- Delete request: `spaceService.deleteSpace` in `src/services/spaceService.ts`

Migration note:
- In Firebase, enforce “clear assignment” semantics server-side if needed (e.g., on delete, clear `item.spaceId` for affected items) to avoid orphaned references.
- This must apply to **both** project spaces and inventory spaces (scoped to the relevant item collection).

## Offline-first behavior (mobile target)

### Local source of truth
- UI reads from **Firestore’s local cache** via the native Firestore SDK (cache-first reads with server reconciliation when online).
- User writes are **direct Firestore writes** (queued offline by Firestore-native persistence).
- Media attachments are represented locally immediately via `AttachmentRef.url = offline://<mediaId>` placeholders (with explicit `kind`).
  - When upload completes, the owning Space doc is patched by replacing the placeholder URL with a remote URL.
  - Do not persist transient upload state on the Space doc; state is local + derived.

### Restart behavior
- On cold start:
  - Spaces list should render from local cache (avoid empty flash).
  - Space detail should render from local cache (space + images + checklists + assigned items).

### Reconnect behavior
- When returning online, foregrounded screens should converge via Firestore listeners + queued-writes acknowledgement and clear any “hydrated from cache” stale indicator.

Canonical architecture source:
- `OFFLINE_FIRST_V2_SPEC.md`

## Collaboration / “realtime” expectations (mobile target)
- **Scoped listeners only (never unbounded)**:
  - Listen to spaces via bounded queries as needed (project scope).
  - For items assignment changes, rely on bounded item listeners for the visible UI surface (e.g., items in this space), not “all items”.
  - Detach listeners on background; reattach on resume.

Canonical migration source:
- `OFFLINE_FIRST_V2_SPEC.md`

## Permissions and gating
- User must be authenticated and have an active `accountId` to manage spaces.
- “Save as Template” is admin-only (client gating for UX; server enforcement required).
Business Inventory scope (required):
- Inventory spaces use the same authentication baseline.
- If Business Inventory creation/edit is role-gated (per `40_features/business-inventory/feature_spec.md`), inventory spaces should follow the same gating policy for consistency (client gating for UX; server enforcement required).

