# Image gallery / lightbox specs (thumbnails, full-screen viewer, pinning)

This document captures the **current state** in `ledger_mobile` and the **feature specs we can infer** from the older `ledger` app (web) for:

- **Thumbnail previews** (grid/tiles)
- **Full-screen image gallery (“lightbox”)**
- **Optional “pin image”** behavior (Transaction Detail)
- **Offline placeholder media** (`offline://...`) handling

It’s written so we can port the feature without needing to re-discover behavior from the web code.

---

## Current state in `ledger_mobile` (what we have vs. what we don’t)

- **We do have thumbnails in list cards**:
  - `src/components/ItemCard.tsx` renders a single thumbnail image and already supports `offline://...` via `resolveAttachmentUri(...)`.
  - Similar logic exists in grouped cards (`src/components/GroupedItemCard.tsx` and variants).
- **We do not have shared “gallery/lightbox” UI components**:
  - No reusable thumbnail grid component for multiple images.
  - No shared full-screen viewer (zoom/pan/swipe, etc.).
- **Item detail screen does not show a thumbnail grid/lightbox**:
  - `app/items/[id].tsx` currently shows images as a **text list with buttons** (set primary/remove), not a preview gallery.

---

## Where to use this in `ledger_mobile` (integration targets)

This section answers “where do we put thumbnails / image menus / lightbox in *our* app?”

### Item flows

- **Item Detail** (`app/items/[id].tsx`)
  - Replace the current “text list of images” with:
    - **Multi-image thumbnail grid** (with per-tile menu: Open / Primary / Delete)
    - **Full-screen lightbox** on tap
  - Keep existing behaviors:
    - Add multiple images
    - Remove image
    - Set primary
    - Respect max images = 5

- **New Item** (`app/items/new.tsx`)
  - Today: user can add up to 5 image URLs / offline local URIs, but only sees a count.
  - Target: show the same **thumbnail grid** (at least read-only + delete) so users can verify what they added before saving.

### Transaction flows

- **Transaction Detail** (`app/transactions/[id].tsx`)
  - Today: receipts/other images are URL inputs; there is no preview grid or viewer.
  - Target: two preview sections:
    - **Receipts**: preview tiles that support images + PDFs (PDF tiles open as files; images open lightbox)
    - **Other images**: preview tiles for images only
  - Lightbox should open on tapping an image tile.
  - Optional enhancement for parity with web: support “Pin image” while working in the transaction screen.

- **New Transaction** (`app/transactions/new.tsx`)
  - Today: user can add receipts/images but there is no preview.
  - Target: show preview tiles for:
    - Receipts (images + PDFs)
    - Other images (images only)

### List surfaces (already partially implemented)

- **Item list cards** already show a single thumbnail:
  - `src/components/ItemCard.tsx`
  - `src/components/GroupedItemCard.tsx`
  - These should remain the “one thumbnail” surfaces; the **multi-image grid + lightbox** belongs on detail/edit surfaces.

---

## Source-of-truth (where these specs come from)

The behavior below is derived from the older `ledger` app (web):

- Shared UI contract doc:
  - `ledger/.cursor/plans/firebase-mobile-migration/40_features/_cross_cutting/ui/components/image_gallery_lightbox.md`
- Implementations:
  - Thumbnail grid + menus + open lightbox: `ledger/src/components/ui/ImagePreview.tsx`
  - Full-screen lightbox: `ledger/src/components/ui/ImageGallery.tsx`
  - Transaction receipts + other images + pin panel wiring: `ledger/src/pages/TransactionDetail.tsx`

---

## Data model expectations (as used by the feature)

### Item images

- Stored as an ordered list (capped at **5** in existing UI flows).
- Each image has:
  - `url` (string, may be `offline://<mediaId>`)
  - `isPrimary` (boolean)
  - Optional metadata used for display in the viewer (web): `fileName`, `size`, `mimeType`, `uploadedAt`, `alt`, `caption`

**Primary image rules**

- If the user adds the first image and there is no primary yet, that image becomes **primary**.
- If the primary image is removed and there are images remaining, the first remaining image becomes primary.
- Setting primary switches `isPrimary` so that **exactly one** is primary (when list non-empty).

### Transaction attachments (receipts + other images)

- Two lists:
  - `receiptImages[]`: **may include PDFs**
  - `otherImages[]`: images only
- Attachments include metadata similar to item images (url, fileName, mimeType, size, uploadedAt).
- **Gallery set is images-only**:
  - PDFs are **not** included in the lightbox image set.
  - PDFs open as files (in web: new tab).

### Offline placeholder media (`ledger_mobile`)

`ledger_mobile` already has a concrete offline media model:

- `saveLocalMedia(...)` returns an `AttachmentRef` whose `url` is `offline://<mediaId>` and a `kind` (`image`/`pdf`/`file`).
- `resolveAttachmentUri(ref)` returns either:
  - A usable local `file://...` (or cached) URI when available, or
  - `null` if the local record isn’t present yet.
- `deleteLocalMediaByUrl('offline://...')` removes local cached media + queued jobs.

Any thumbnail grid / viewer must treat `offline://...` as a first-class URL format.

---

## Component-level behavior specs (what the UI does)

### 1) Thumbnail preview surface (multi-image “grid”)

This is a reusable surface for viewing and managing a list of images.

**Layout**

- Displays images as a compact grid of square tiles.
- Visually distinguishes the **primary** image (web uses a border + small crown badge).
- If the caller supports adding images, show an “Add image” tile/button when under the max.

**Web design details (reference implementation)**

These are the specific design choices used in `ledger/src/components/ui/ImagePreview.tsx` (Tailwind classes), useful if we want close visual parity:

- **Grid**
  - Columns: `grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6`
  - Gaps: `gap-3 sm:gap-4 md:gap-6`
- **Tile sizes**
  - `sm`: `w-20 h-20` (mobile) and `sm:w-16 sm:h-16` (≥ sm breakpoint)
  - `md`: `w-24 h-24` (mobile) and `sm:w-20 sm:h-20`
  - `lg`: `w-28 h-28` (mobile) and `sm:w-24 sm:h-24`
- **Tile container**
  - Rounded + bordered: `relative ... rounded-lg ... border-2`
  - Primary tile border: `border-primary-500 ring-2 ring-primary-200`
  - Non-primary border: `border-gray-200`
- **Thumbnail image**
  - Cover crop: `object-cover`
  - Hover affordance: `group-hover:scale-105` (subtle zoom)
- **Primary badge**
  - Position: top-left (`absolute top-1 left-1`)
  - Style: `bg-primary-500 bg-opacity-40 text-white text-xs p-1 rounded ... border border-white`
  - Icon: crown glyph
- **Options (“image menu”) button**
  - Position: top-right (`absolute top-1 right-1`)
  - Button style: `p-1.5 bg-primary-500 bg-opacity-40 rounded-full text-white border border-white`
  - Icon: chevron-down
- **Options dropdown**
  - Anchored under the chevron, centered: `absolute top-full left-1/2 ... -translate-x-1/2`
  - Card style: `w-32 bg-white rounded-md shadow-lg border border-gray-200 py-1 z-50`
  - Menu rows:
    - Open: neutral row with “external link” icon
    - Primary: neutral row with “star” icon (only when non-primary)
    - Delete: red row (trash icon)
- **Add-image tile**
  - Dashed outline: `border-2 border-dashed border-gray-300 rounded-lg`
  - Centered plus icon; hover darkens border/text (`hover:text-gray-600 hover:border-gray-400`)

**Interactions**

- **Tap a tile**: opens the lightbox at that image index.
- Each tile exposes a small “options” control (web uses a chevron menu) with actions:
  - **Open** (same as tapping the tile)
  - **Set primary** (only if the image is not already primary, and caller provided this action)
  - **Delete** (only if caller provided this action)

**Limits**

- Existing flows use `maxImages = 5`.
- If max is reached, the “Add image” tile is hidden/disabled.

**Offline placeholders**

- If the tile’s URL is `offline://...`, resolve to a local URI for rendering.
- If it can’t resolve yet, show a clear placeholder (e.g., “image not available yet”).

### 2) Transaction attachment preview surface (receipts/other)

This is similar to the image grid, but supports **non-image** attachments (specifically PDFs in receipts).

**Rendering rules**

- If attachment is an image (by `mimeType` or file extension), show it as a thumbnail tile and include it in the lightbox’s image list.
- If attachment is not renderable (PDF/file):
  - Show a generic file tile (web uses a “document” icon + “PDF” label).
  - Tapping it opens the file (mobile: native open/share flow; web: new tab).

**Web design details for non-image tiles (reference)**

From `TransactionImagePreview` in `ledger/src/components/ui/ImagePreview.tsx`:

- Non-image tile uses:
  - Container: `bg-gray-50 ... text-gray-600 p-2`
  - Icon: document glyph
  - Small label text: “PDF” or “File” (line-clamped)

**Tile menu options (per attachment)**

- Open / Open file
- Delete (if supported)
- Pin (optional; only for renderable images)

### 3) Full-screen image gallery (“lightbox”)

This is the shared full-screen viewer that opens from thumbnails.

**Open**

- Opening from a tile must open the modal at that tile’s index.
- When switching images (prev/next), the viewer resets to:
  - zoom = 1
  - panX/panY = 0

**Close**

- Close button **X** always available.
- “Back” equivalent closes the modal.
- Escape key behavior (web):
  - If zoomed in (\(zoom > 1.01\)), first **reset zoom**.
  - Otherwise closes the modal.

**Navigation**

- If multiple images:
  - Show prev/next controls.
  - Wrap-around behavior:
    - Prev from first → last
    - Next from last → first

**Zoom + pan**

- Zoom range: min 1, max 5 (web).
- Zoom step buttons:
  - Zoom in: +0.5
  - Zoom out: -0.5 (disabled at 1)
  - Reset zoom button appears when zoomed.
- Gestures (web):
  - Drag to pan when zoomed.
  - Pinch to zoom (maintain content under pinch center).
  - Double tap / double click toggles zoom:
    - If zoomed → reset
    - Else → zoom to 2x around the tap point.
- Pan is clamped so the image cannot be dragged completely out of view.

**UI auto-hide (viewer chrome)**

- The overlay controls auto-hide after ~2.2s of inactivity **only when not zoomed**.
- Any interaction (tap, move, keypress, wheel) makes controls visible again.
- Tapping the dark background toggles controls visibility.

**Info bar**

- Shows “\(index + 1\) of \(N\)”.
- Shows file name / label when available.
- Shows file size and uploaded date when available.
- Provides a “download/open externally” action (mobile: share/open).

### 4) Optional “Pin image” behavior (Transaction Detail)

This is used on Transaction Detail to keep an image visible while working on the transaction.

**Availability**

- If the caller provides an `onPinToggle` callback, the lightbox shows a Pin button.
- Transaction attachment tiles can also expose a Pin action in their tile menu.

**Behavior (web)**

- Pinning:
  - Sets pinned image state
  - Closes the lightbox
  - Opens a pinned image panel on the Transaction Detail screen
- Unpinning removes the panel.
- The pinned panel supports zoom/pan/pinch (same core interaction model as the lightbox).

**Mobile note**

Web uses a top “33svh” fixed panel on small screens and a sticky side panel on large screens.
On mobile, we can implement the same *concept* (pinned panel that doesn’t disappear while editing), but the exact layout will be a mobile UI decision.

---

## Acceptance criteria (port parity checklist)

### Thumbnail previews

- **Multiple images display as thumbnails**, not as text rows.
- **Primary image is visibly marked** and can be changed.
- **Tap opens lightbox at correct index**.
- **Max images = 5** enforced in UI.
- **Offline `offline://...` images render** when locally available; otherwise show a placeholder.

### Lightbox

- Full-screen modal viewer opens and closes reliably.
- Supports:
  - Prev/next navigation (wrap-around)
  - Pinch-to-zoom, pan when zoomed
  - Double-tap to zoom toggle at tap point
  - Reset zoom when switching images
  - Viewer chrome auto-hide when not zoomed

### Transactions

- Receipts support adding images + PDFs.
- PDFs show as file tiles and open as files (not in image gallery).
- “Pin image” is available (at least via tile menu) and keeps the image visible while interacting with the transaction.

