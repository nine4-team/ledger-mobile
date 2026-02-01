# Shared UI contracts (canonical — single file)

This is the **single source of truth** for **shared UI behavior** in the Ledger Mobile migration.

If a UI behavior/component is shared across multiple features (or must remain consistent across the app), it is defined **here** and **feature specs must reference it** rather than redefining it.

## Non-goals

- This is not a UI-kit design system doc (tokens/styles live in `src/ui/**`).
- This is not a per-screen spec (screens live in feature folders).
- This is not a “document every component” catalog.

## Rules (how we keep this consistent across many AI chats)

### 1) Canonical location rule

- **All shared UI contracts live in this file**.
- Do **not** create new `ui/components/*.md` contract files.

### 2) Append-only structure rule

To keep this stable across many chats:

- Prefer **adding** content to the correct section over rewriting existing text.
- When content is missing/uncertain, add an **Open question** instead of guessing.
- Do not reorder headings. Add new headings only under “Shared surfaces index”.

### 3) Evidence rule (anti-hallucination)

For non-obvious behavior, include one of:

- **Parity evidence**: pointer to `/Users/benjaminmackenzie/Dev/ledger/...` (file + component/function), or
- **Intentional delta**: what changes for mobile and why.

### 4) Ownership rule (anti-fork)

- If a feature needs a shared UI surface, it must use the **one shared implementation** (code) and reference the relevant section here.
- Feature specs can specify **feature wiring** (data fields, routes, permissions), but not redefine the shared UI behavior.

## Shared surfaces index (stable headings)

- List controls + control bar (search/filter/sort/group + state restore)
- Selection + bulk actions
- Action menus + action registry
- Pickers (space/transaction/category) conventions
- Global messaging (toast/confirm/banner)
- Offline + pending + error UI semantics
- Media UI surfaces (upload/preview/gallery + quota guardrails)
- Navigation + “return to list” + scroll restoration (UI-owned parts)
- Performance + large-list constraints (UI-visible implications)
- Accessibility + keyboard rules (cross-cutting minimums)
- Item preview/list card (shared card semantics)
- Grouped item card (summary + grouped list semantics)
- Empty / loading / error state semantics (lists + detail + forms)
- Offline prerequisite gating UI (banner placement + retry affordance)
- Loading spinner / skeleton conventions (shared)
- Access denied / no access surfaces (consistent gating UX)
- Duplicate grouping UI semantics (collapsed groups + counts + interactions)
- Sync health + network status indicators (banner + background errors)
- Upload activity indicator (queued uploads + progress)

---

## List controls + control bar (search/filter/sort/group + state restore)

**Intent**

Define the canonical “list control bar” behavior used across Items/Transactions/Spaces lists (both project and inventory scopes).

**Contract (stub)**

- Search/filter/sort/group controls must be:
  - scope-aware (project vs inventory can differ in available filters)
  - stateful (persisted and restored per list)
  - compatible with long lists (no jank, stable restore)

**Parity evidence pointers**

- Web list state patterns are referenced in:
  - `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`
  - (web) `ledger/src/pages/InventoryList.tsx`, `ledger/src/pages/TransactionsList.tsx`, `ledger/src/pages/BusinessInventory.tsx`

**Open questions**

- What is the canonical “control bar” component boundary in RN (single component vs composed header)?
- Which lists require grouping in v1 mobile parity?

---

## Selection + bulk actions

**Intent**

Define the canonical selection model and bulk-action lifecycle so bulk UX behaves the same across lists/scopes.

**Contract (baseline)**

- **Visibility**:
  - Bulk actions UI renders **nothing** when selection count is 0.
- **Placement**:
  - Support a bottom “bulk actions bar” that can be either:
    - fixed to viewport (mobile default), or
    - sticky within a container (optional).
- **One entry point**:
  - A single “Bulk Actions” entry point that opens a menu/list of actions.
  - Clicking outside closes the menu.
- **Action lifecycle (consistent across all bulk actions)**:
  - Open modal/dialog to collect inputs (when needed).
  - Confirm triggers async work.
  - While processing:
    - disable controls
    - show “Working…” copy (or equivalent)
  - On success:
    - close dialog
    - clear selection
  - On failure:
    - keep dialog open (or show inline error)
    - do **not** clear selection
- **Suggested action set (scope-driven)**:
  - Assign to transaction
  - Set space (or clear)
  - Set disposition
  - Set SKU
  - Delete selected

**Parity evidence pointers**

- (web) `ledger/src/components/ui/BulkItemControls.tsx`

**Open questions**

- Do we need “select all matching filter” semantics in mobile v1, or only “select visible/loaded”?

---

## Action menus + action registry

**Intent**

Ensure “…” menus (per-row actions) and bulk actions share the same action definitions, gated consistently by scope + permissions.

**Contract (stub)**

- Menu actions must be generated from a single “registry” filtered by:
  - scope (`project` vs `inventory`)
  - permissions/roles
  - entity state (pending, conflict, etc.)

**Parity evidence pointers**

- (web) actions are split across modules, but the drift problem is real: enforce a single registry in mobile.

**Open questions**

- Where should action registry live in the RN codebase (domain module vs UI module)?

---

## Pickers (space/transaction/category) conventions

**Intent**

Define consistent picker behavior (search, empty states, create-from-picker, disabled states) across features.

**Contract (stub)**

- Pickers must share:
  - input/search behavior (explicit match fields)
  - “create new” affordance rules (where permitted)
  - offline prerequisite gating behavior

**Parity evidence pointers**

- (web) examples:
  - `ledger/src/components/spaces/SpaceSelector.tsx`
  - `ledger/src/components/CategorySelect.tsx`
  - `ledger/src/components/transactions/TransactionItemPicker.tsx`

---

## Global messaging (toast/confirm/banner)

**Intent**

Define the canonical way to surface non-blocking and blocking messages across the app.

**Contract (baseline)**

- **Toast system**:
  - Supports: success/error/warning/info.
  - Imperative API: show toast returns an id; toasts can be removed by id.
  - Default durations:
    - error: ~6000ms
    - others: ~4000ms
  - Stacking behavior is consistent (web: stacks top-right; mobile placement TBD but must be consistent).
- **Blocking confirm dialog**:
  - Renders nothing when closed.
  - Blocks background interaction when open.
  - Has Cancel + Confirm actions.
  - Supports “Working…” state that disables actions during confirm.
  - Variant: danger (default for destructive) vs primary.
  - A11y minimums:
    - `role="dialog"`, `aria-modal="true"` (web parity)
    - best-effort focus on confirm button when opened.
- **Banners**:
  - Used for app-wide status surfaces (offline, sync health, prerequisite gating).

**Parity evidence pointers**

- (web) `ledger/src/components/ui/ToastContext.tsx`, `ledger/src/components/ui/Toast.tsx`
- (web) `ledger/src/components/ui/BlockingConfirmDialog.tsx`
- (web) `ledger/src/components/NetworkStatus.tsx`, `ledger/src/components/SyncStatus.tsx`

---

## Offline + pending + error UI semantics

**Intent**

Shared, user-trust-building semantics for:

- local-first writes
- queued uploads
- request-doc operation states
- retry surfaces

**Contract (baseline)**

- Every mutation-capable UI must have explicit states:
  - ready
  - saving/pending
  - waiting-for-connectivity
  - failed (with retry)

**Parity evidence pointers**

- (web) `ledger/src/components/ui/RetrySyncButton.tsx`
- (web) operation queue + offline UX patterns (see feature specs under `connectivity-and-sync-status`)

---

## Media UI surfaces (upload/preview/gallery + quota guardrails)

**Intent**

Shared attachment UI patterns across items, transactions, spaces, etc.

**Contract (baseline)**

- **Upload surface**:
  - Shows placeholder states and supports retry/remove where applicable.
  - While offline, attachment selection must be validated against available local storage (quota guardrails).
- **Preview surface**:
  - Resolves local/offline media references for rendering.
- **Gallery / lightbox**:
  - Open:
    - tapping an image tile opens the gallery at that image index.
    - switching images resets view (zoom=1, panX=0, panY=0).
  - Close:
    - X closes the gallery.
    - Escape:
      - if zoomed in (\(zoom > 1.01\)) resets zoom first
      - otherwise closes the gallery.
    - background content must not scroll while the gallery is open.
  - Navigation:
    - prev/next appear when multiple images
    - keyboard left/right navigates (when not zoom-panning)
    - wrap-around: first↔last
  - Zoom + pan:
    - zoom in: `+` / `=`
    - zoom out: `-` / `_` (disabled at zoom=1)
    - reset zoom: `0`
    - wheel zoom prevents page scroll and is cursor-centered (web parity)
    - drag pans when zoomed; pan is clamped
    - pinch zoom maintains content under pinch center
    - double-tap/double-click toggles 2x zoom around tap/cursor
  - UI auto-hide:
    - UI auto-hides after ~2.2s inactivity only when not zoomed
    - any interaction shows UI
    - tapping modal background toggles UI visibility (no accidental close after drag/pinch)
  - Optional “pin image”:
    - if provided by caller, show Pin control that callbacks with current image
    - pinned layout is screen-owned.
- **Quota warning thresholds + offline attachment gating**:
  - Global warning banner when usagePercent ≥ 80
    - warning: \(80\% \le usage < 90\%\)
    - critical: \(usage \ge 90\%\)
  - Banner is dismissible; dismissal is in-memory only (resets on restart).
  - Sampling:
    - don’t check until offline store initialized
    - check cadence ~30s + initial check
    - fail silently if storage system unavailable
  - Offline selection gating rule:
    - compute \(projectedUsage = usedBytes + incomingFileSize\)
    - hard block if \(projectedUsage > totalBytes\)
    - hard block if \(projectedUsage / totalBytes \ge 0.9\)
  - Copy (preferred):
    - “Not enough storage space. Please delete some media files first.”
    - “Storage quota nearly full (90%+). Please free up space before uploading.”
    - file-size limits: “File too large. Maximum size is 10MB.”
  - Migration note:
    - web parity assumes ~50MB local quota; RN must use platform-appropriate accounting but keep 80%/90% semantics.

**Parity evidence pointers**

- (web) `ledger/src/components/ui/ImageUpload.tsx`, `ledger/src/components/ui/ImagePreview.tsx`, `ledger/src/components/ui/ImageGallery.tsx`
- Existing cross-cutting docs:
  - `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`
- Gallery details (web parity):
  - `ledger/src/components/ui/ImageGallery.tsx` (`handleKeyDown`, pointer handlers, `handleDoubleClick`, `onWheel`, `showUi`)
- Offline preview resolution (web parity):
  - `ledger/src/components/ui/ImagePreview.tsx` (resolves `offline://` via `offlineMediaService.getMediaFile`)
- Quota thresholds + cadence (web parity):
  - `ledger/src/components/ui/StorageQuotaWarning.tsx`
- Offline attachment gating (web parity):
  - `ledger/src/components/ui/ImageUpload.tsx` + `ledger/src/services/offlineAwareImageService.ts`

---

## Navigation + “return to list” + scroll restoration (UI-owned parts)

**Intent**

Define what the shared list modules must do to support “back to where I was” UX.

**Contract (seed)**

- List modules persist UI state (filters/sort/search) keyed by `listStateKey`.
- List → detail records restore hint (anchorId preferred, optional scrollOffset).

**Parity evidence pointers**

- `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`
- (web) `ledger/src/contexts/NavigationStackContext.tsx` and list pages (state + restore patterns)

---

## Performance + large-list constraints (UI-visible implications)

**Intent**

Make performance constraints explicit where they change UX requirements.

**Contract (stub)**

- Lists must support “large N” without losing:
  - selection correctness
  - state restoration
  - smooth scroll

**Open questions**

- What is the target “large N” baseline per list (items, transactions)?

---

## Accessibility + keyboard rules (cross-cutting minimums)

**Intent**

Set minimum a11y expectations for shared UI elements (dialog focus, keyboard triggers, etc.).

**Contract (stub)**

- Dialogs: focus primary action on open (best-effort), role/labels correct.
- Expand/collapse controls: support Enter/Space.

**Parity evidence pointers**

- (web) `ledger/src/components/ui/BlockingConfirmDialog.tsx`
- (web) `ledger/src/components/ui/CollapsedDuplicateGroup.tsx`

---

## Empty / loading / error state semantics (lists + detail + forms)

**Intent**

Define consistent, parity-aligned semantics for the most common UX glue states:

- “loading” vs “refreshing”
- “no data yet” vs “no results”
- “error (retryable)” vs “blocked (offline/prerequisite/permissions)”

This section is intentionally **semantics-first**: screens/features can own copy where needed, but the behavior rules and state taxonomy must be consistent across the app.

**Contract**

- **State taxonomy (required)**:
  - **Loading (initial)**: first load where no meaningful content is rendered yet.
  - **Refreshing (non-blocking)**: content is present; a refresh is happening in the background.
  - **Empty (no data)**: the dataset is empty *without filters/search applied* (e.g., “no items yet”).
  - **Empty (no results)**: filters/search are applied and yield 0 results (e.g., “no results”).
  - **Error (retryable)**: request failed; user can retry.
  - **Blocked**: user cannot proceed due to a prerequisite (offline / permissions / incomplete setup). Blocked states should use the dedicated contracts:
    - Offline prerequisite gating UI
    - Access denied / no access surfaces
- **Lists**
  - When **Loading (initial)**: show a list-appropriate loading surface (spinner or skeleton per loading conventions).
  - When **Refreshing**: keep existing content visible and show a lightweight refresh affordance (screen-owned), not a full-screen blocker.
  - When **Empty (no data)**:
    - show an empty state that clearly indicates there is no data yet
    - if the feature has a natural “create” CTA, provide it (screen-owned, but consistent placement)
  - When **Empty (no results)**:
    - show an empty state that clearly indicates filters/search eliminated results
    - provide an obvious “clear filters/search” affordance (screen-owned wiring; semantics are required)
  - Empty states must **visually differentiate** “no data yet” vs “no results” (copy + iconography can be screen-owned, but the distinction is required).
  - When **Error (retryable)**:
    - show an error state with an explicit Retry affordance
    - do not silently auto-retry in a loop without surfacing state
- **Detail screens**
  - If the entity cannot be loaded:
    - show Error (retryable) when retry is meaningful
    - use Access denied / no access surfaces when permissions are the cause
- **Forms**
  - **Validation errors** (client-side) must render inline near the relevant field(s) and block submit until resolved.
  - **Submit failures** (server/offline) must:
    - keep user input intact
    - show a clear failure state
    - provide Retry where safe (align with Offline + pending + error UI semantics).

**Parity evidence pointers**

- List shell/state patterns are referenced in:
  - `40_features/_cross_cutting/ui/shared_items_and_transactions_modules.md`
  - (web) `ledger/src/pages/InventoryList.tsx`, `ledger/src/pages/TransactionsList.tsx`, `ledger/src/pages/BusinessInventory.tsx`
- Empty-state messaging patterns (no data vs no results) appear in:
  - (web) `ledger/src/pages/ProjectSpacesPage.tsx`
  - (web) `ledger/src/pages/TransactionsList.tsx`
  - (web) `ledger/src/pages/BusinessInventory.tsx`
- Additional empty-state examples:
  - (web) `ledger/src/pages/InventoryList.tsx`
  - (web) `ledger/src/pages/SpaceDetail.tsx`
  - (web) `ledger/src/components/spaces/SpaceItemPicker.tsx`
- Inline form error presentation examples:
  - (web) `ledger/src/components/TransactionItemForm.tsx`
- Form + detail “no data” messaging examples:
  - (web) `ledger/src/pages/AddItem.tsx`, `ledger/src/pages/EditItem.tsx`
- Error banner example:
  - (web) `ledger/src/components/BudgetCategoriesManager.tsx`

**Open questions**

- What are the canonical web components (if any) for empty/error surfaces (so we can cite them explicitly), or is this a mobile-native convention?
- What is the preferred copy taxonomy for “no data yet” vs “no results” across Items/Transactions/Spaces?

---

## Offline prerequisite gating UI (banner placement + retry affordance)

**Intent**

Provide a consistent, user-trust-building “prerequisite not met” surface for offline / sync prerequisites that block an action or screen from proceeding.

This is distinct from “mutation pending” and “retry a sync operation” (covered elsewhere); this is about **gating**.

**Contract**

- **When to show**
  - Show when a screen or action requires an online/synced prerequisite that is currently unmet.
  - Prefer showing *one* gating surface at a time (avoid stacking multiple banners for the same underlying state).
- **Placement (consistent)**
  - Default placement is a **top-of-screen banner** within the screen content area (below the top header, above list/form content).
  - It must not shift content unpredictably during scroll (stable height; avoid layout jank).
  - Banner styling should match the shared “banner” visual language defined under Global messaging.
- **Retry affordance (required when meaningful)**
  - If retrying can resolve the prerequisite, the banner must include a primary “Retry” affordance.
  - Retry must trigger the relevant sync/reconnect attempt and reflect “working” state (disabled controls + progress feedback).
- **Interaction**
  - Banner must be non-destructive and must not hide the primary content when the user *can* still browse read-only.
  - If the prerequisite blocks the entire screen (no useful read-only view), the screen may choose a full-screen blocked state, but must still adhere to the “blocked” semantics in the empty/loading/error taxonomy.

**Parity evidence pointers**

- (web) `ledger/src/components/ui/OfflinePrerequisiteBanner.tsx`
- (web) Usage examples:
  - `ledger/src/components/TransactionItemForm.tsx`
  - `ledger/src/pages/AddTransaction.tsx`
  - `ledger/src/components/ProjectForm.tsx`
  - `ledger/src/components/CategorySelect.tsx`
- Related web status surfaces (adjacent but not identical):
  - (web) `ledger/src/components/NetworkStatus.tsx`, `ledger/src/components/SyncStatus.tsx`
- Implementation note (web): `OfflinePrerequisiteBanner` currently logs state and returns `null` (no UI).

**Open questions**

- What are the canonical prerequisites that should use this banner (offline only, or also “sync unhealthy”, “requires auth refresh”, etc.)?
- Is the banner dismissible in web parity? If so, is dismissal persistent or in-memory?
- What is the canonical copy for offline prerequisite gating in web parity (not yet cited in current migration docs)?

---

## Loading spinner / skeleton conventions (shared)

**Intent**

Standardize when the app shows a spinner vs skeletons so loading feels consistent and avoids jank, especially on long lists.

**Contract**

- **Default choice**
  - Use **spinner** for short, global, or modal “please wait” moments where structure is not meaningful.
  - Use **skeletons** for list/card-heavy surfaces where showing layout while data loads improves perceived performance.
- **Initial vs refresh**
  - Initial load can use spinner/skeleton per above.
  - Refresh must not blank the screen; keep content and show a lightweight refresh affordance.
- **Anti-jank**
  - Do not rapidly flip between “no loader” and “loader” during fast requests; apply a small delay before showing an initial loader (exact timing is implementation-defined).
  - For large lists, avoid expensive per-row skeleton rendering that harms scroll performance.
  - Skeletons should preserve the **final layout structure** (row height + key columns) to avoid layout shift.

**Parity evidence pointers**

- (web) `ledger/src/components/ui/LoadingSpinner.tsx`
- (web) Usage examples:
  - `ledger/src/App.tsx` (Suspense fallback)
  - `ledger/src/pages/ImportAmazonInvoice.tsx`
  - `ledger/src/pages/ImportWayfairInvoice.tsx`
- Skeleton loading example (not a shared component, but parity reference):
  - (web) `ledger/src/components/ui/BudgetProgress.tsx`

**Open questions**

- Do we have any web parity skeleton implementation that should be matched (not yet cited in current migration docs)?
- What is the agreed “delay before showing loader” convention for mobile?

---

## Access denied / no access surfaces (consistent gating UX)

**Intent**

Ensure the app uses one consistent UX for “you can’t see/do this” cases so users understand what happened and what to do next.

**Contract**

- **When to show**
  - Use this surface when access is denied due to role/permissions/scoping, not for transient network failures.
- **Minimum UI**
  - Clear “no access” message (screen-owned copy is allowed, but should be short and consistent).
  - A primary “Go back” / “Close” action that returns the user to a safe screen.
  - Optional secondary actions owned by the screen context (e.g., switch scope/workspace) where applicable.
  - Do not show a “Retry” action unless the denial is expected to be transient (default is **no retry**).
- **Do not leak data**
  - Do not render partial content that implies access to restricted data.

**Parity evidence pointers**

- Access denied screen examples:
  - (web) `ledger/src/pages/EditItem.tsx`
  - (web) `ledger/src/pages/AddItem.tsx`
  - (web) `ledger/src/pages/ImportAmazonInvoice.tsx`
  - (web) `ledger/src/pages/ImportWayfairInvoice.tsx`
  - (web) `ledger/src/pages/AddTransaction.tsx`
  - (web) `ledger/src/pages/EditTransaction.tsx`
  - (web) `ledger/src/pages/AddBusinessInventoryItem.tsx`
  - (web) `ledger/src/components/auth/UserManagement.tsx`

**Open questions**

- What are the canonical web components/routes for access denied, and what is the preferred copy/actions?
- When access is denied mid-session (permissions changed), do we show a toast + redirect, or a full-screen gate?

---

## Duplicate grouping UI semantics (collapsed groups + counts + interactions)

**Intent**

Define shared semantics for “duplicate grouping” list UI so grouping behavior remains consistent across lists that support it.

**Contract**

- **Collapsed group summary**
  - A collapsed group must show:
    - a human-readable group label (screen-owned)
    - the duplicate count (e.g., “+3” or “4 items”)
  - Summary row must be interactive and clearly afford expand/collapse.
- **Expand / collapse**
  - Tapping the summary toggles expanded/collapsed state.
  - Expanded state reveals the grouped rows with stable ordering (screen-owned ordering rules, but must not shuffle on toggle).
- **Selection interaction (when lists support selection)**
  - Expanding/collapsing must not clear selection.
  - Selecting within a group must behave the same as selecting in an ungrouped list (no special hidden semantics).
- **Accessibility**
  - Expand/collapse controls must be keyboard-triggerable (Enter/Space) where applicable.

**Parity evidence pointers**

- (web) `ledger/src/components/ui/CollapsedDuplicateGroup.tsx`
- (web) Usage examples:
  - `ledger/src/pages/InventoryList.tsx`
  - `ledger/src/pages/BusinessInventory.tsx`
  - `ledger/src/components/TransactionItemsList.tsx`
  - `ledger/src/components/spaces/SpaceItemPicker.tsx`
  - `ledger/src/components/transactions/TransactionItemPicker.tsx`

**Open questions**

- Is grouping used for Items only, or also Transactions, in v1 mobile parity?
- Is the group label/copy standardized in web parity, or list-owned?
- Should collapsed groups render a thumbnail (first item vs composite), or suppress thumbnails entirely?

---

## ItemCard (shared card semantics)

**Intent**

Define the shared `ItemCard` semantics used across lists and grouped list summaries so item rows feel consistent across scopes.

**Contract**

- **Card identity**
  - A single shared `ItemCard` surface is used anywhere a compact item summary row is needed (list rows, grouped summaries).
- **Required fields**
  - A human-readable description/title is always shown.
- **Optional metadata**
  - SKU, source label, location label, notes, price, and status are optional; when present they render in a consistent order.
- **Selection + actions**
  - When selection is enabled, the selection affordance renders in the top row.
  - Bookmark and “more” menu actions (when provided) render in the top row and do not alter the core card layout.
- **Thumbnail behavior**
  - If a thumbnail is present, show it.
  - If no thumbnail is present and the surface allows adding media, show a placeholder affordance that triggers “add image”.

**Parity evidence pointers**

- (web) `ledger/src/components/items/ItemPreviewCard.tsx` (exports `ItemCard`)
- (mobile) Existing component: `src/components/ItemPreviewCard.tsx` (exports `ItemCard`; may need polish)

**Open questions**

- Are there any “detail card” variants in web parity that should be treated as a separate shared surface, or is ItemCard sufficient for v1 mobile parity?

---

## GroupedItemCard (collapsed + expanded summary)

**Intent**

Define the shared “grouped item card” semantics used for collapsed duplicate groups and their expanded rows so grouped lists behave consistently.

**Contract**

- **Component name (shared)**
  - Use `GroupedItemCard` as the shared surface name in mobile.
  - Beginnings of the component already exist in `src/components/GroupedItemListCard.tsx`.
- **Composition**
  - Grouped card renders a **summary row** plus **child item rows** when expanded.
  - Summary row uses the ItemCard content model but may suppress controls not relevant to summary view.
- **Counts + totals**
  - Summary row shows a duplicate count (e.g., “×2”).
  - If a total value is available, it renders in the summary row (currency formatting is screen-owned).
- **Expand/collapse**
  - Tapping summary toggles expanded/collapsed state.
  - Expanded rows preserve stable ordering and do not clear selection.
- **Selection behavior**
  - Group selection reflects the selection state of child items but does not implicitly select hidden items without user action.

**Parity evidence pointers**

- (web) Grouped list behavior is embodied by:
  - `ledger/src/components/ui/CollapsedDuplicateGroup.tsx`
  - `ledger/src/pages/InventoryList.tsx`, `ledger/src/pages/BusinessInventory.tsx`

**Open questions**

- Should group selection in mobile allow “select all in group” semantics, or only reflect child selection state?
- Should `GroupedItemCard` be used in pickers (e.g., space/transaction item pickers) or only in list screens?

---

## Sync health + network status indicators (banner + background errors)

**Intent**

Provide a consistent, always-on view of network + sync health so users understand when data is stale, syncing, or erroring in the background.

**Contract (baseline)**

- **Network status indicator**
  - Shows when the app is offline or reconnecting.
  - Must not block core content; it is informational unless paired with a prerequisite gate.
- **Sync status indicator**
  - Shows when background sync is running or stalled.
  - Includes a concise status label; no verbose logs.
- **Background sync errors**
  - If a background sync error occurs, surface a lightweight alert (banner or toast) that does not block the screen.
  - Include a clear next step (e.g., “Retry sync”) when available.

**Parity evidence pointers**

- (web) `ledger/src/components/NetworkStatus.tsx`
- (web) `ledger/src/components/SyncStatus.tsx`
- (web) `ledger/src/components/BackgroundSyncErrorNotifier.tsx`

**Open questions**

- Should sync errors display inline in list screens, or remain global only?
- What is the preferred placement on mobile (top banner vs in-header indicator)?

---

## Upload activity indicator (queued uploads + progress)

**Intent**

Provide a consistent, cross-feature indicator when uploads are queued or actively running, without blocking the current task.

**Contract (baseline)**

- **Visibility**
  - Show when there are active or queued uploads.
  - Hide when idle (no uploads pending).
- **Content**
  - Show a compact “Uploading…” label or icon with optional count.
  - If progress is available, show a minimal progress affordance (bar or percent).
- **Interaction**
  - Non-blocking; tapping may open a detail panel when available (screen-owned).

**Parity evidence pointers**

- (web) `ledger/src/components/ui/UploadActivityIndicator.tsx`

**Open questions**

- Should this indicator be global (header-level) or scoped to screens that own uploads?
- Do we need a “view uploads” action in v1 mobile parity?

