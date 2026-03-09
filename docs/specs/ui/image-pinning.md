# Image Pinning

Pin an image to a persistent reference panel so the user can view it while editing transaction or item details. The pinned image stays visible alongside form fields, eliminating the need to switch back and forth between the gallery and edit screens.

## Motivation

Users frequently need to reference receipt photos, invoice scans, or item images while filling in detail fields (vendor, amount, date, SKU, etc.). Today they must open the gallery, memorize the value, close the gallery, and type it in. Pinning removes that friction.

## Concept

A single image can be pinned at a time. Pinning places it in a persistent panel that coexists with the current editing context. The panel supports zoom and pan so the user can inspect fine details (e.g. small text on a receipt). Unpinning removes the panel and restores the normal layout.

## Where Pinning is Available

Pinning can be triggered from any image-viewing context within a transaction or item:

| Source | Trigger |
|--------|---------|
| `ImageGallery` fullscreen overlay | Pin button in top-left controls |
| Receipt/attachment thumbnail context menu | "Pin Image" action |
| Item image context menu | "Pin Image" action |

Pinning is scoped to detail views — `TransactionDetailView` and `ItemDetailView`. These are the screens where the user edits fields and benefits from a reference image.

## Layout

### iPhone (compact width)

The pinned image appears as a **resizable top panel** above the scrollable content.

- Default height: 33% of screen height (`0.33 * UIScreen.main.bounds.height`)
- Min height: ~20% of screen height
- Max height: ~50% of screen height
- User can drag a resize handle at the bottom edge to adjust the split
- Content area scrolls normally below the panel
- Panel has a subtle bottom border to separate it from content

```
┌─────────────────────┐
│                     │
│   Pinned Image      │  ← fixed top panel (zoomable/pannable)
│                     │
│ ─ ─ ─ resize ─ ─ ─ │  ← drag handle
├─────────────────────┤
│ Transaction Details │
│ ┌─────────────────┐ │
│ │ Edit fields...  │ │  ← scrollable content
│ │                 │ │
│ └─────────────────┘ │
└─────────────────────┘
```

### iPad / Mac Catalyst (regular width)

The pinned image appears as a **sidebar panel** on the leading edge.

- Width: 384pt (same as legacy web `w-96`)
- Sticky to the top of the visible area
- Content area fills the remaining width
- Panel has a subtle trailing border

```
┌──────────────┬──────────────────────┐
│              │ Transaction Details  │
│ Pinned Image │ ┌──────────────────┐ │
│              │ │ Edit fields...   │ │
│ (zoomable/   │ │                  │ │
│  pannable)   │ │                  │ │
│              │ └──────────────────┘ │
└──────────────┴──────────────────────┘
```

### Panel Chrome

- **Close (unpin) button:** Top-trailing corner of the panel. SF Symbol `xmark` in a circular semi-transparent background (same style as `ImageGallery` close button).
- **Image counter:** If the source had multiple images, show "2 of 5" label at the bottom of the panel. Tapping left/right or swiping cycles through images without leaving the pinned state.
- No other controls in the panel — zoom is gesture-driven, not button-driven (unlike the full gallery).

## Interaction

### Zoom and Pan

The pinned panel reuses the same `ZoomableScrollView` (UIScrollView wrapper) from `ImageGallery`:

- **Pinch to zoom:** 1x–5x range
- **Double-tap:** Toggle between fit-to-container and 2.5x zoom centered on tap point
- **Pan:** Drag to pan when zoomed past 1x
- **Reset:** Zoom resets to 1x when a new image is pinned or when unpinning

### Pinning

1. User taps pin action on an image
2. Gallery/overlay dismisses (if open)
3. Pin panel animates in (slide down on iPhone, slide from leading edge on iPad)
4. Image loads in the panel at fit-to-container zoom
5. Content area adjusts layout to accommodate the panel

### Unpinning

1. User taps close button on the pin panel
2. Panel animates out
3. Content area reclaims the full layout
4. All zoom/pan state resets

### Swapping Pinned Image

If the user pins a different image while one is already pinned, the panel crossfades to the new image and resets zoom/pan. No intermediate unpin step needed.

## State

Pinning is **view-local state** — it does not persist to Firestore or survive navigation. Navigating away from the detail view unpins automatically.

```
pinnedAttachment: AttachmentRef?    // nil = nothing pinned
pinPanelHeight: CGFloat             // iPhone only — resize handle state
```

These live on the detail view as `@State` properties. No new `@Observable` store needed — this is purely presentation state.

## Data Types

Uses the existing `AttachmentRef` model. No new types required.

```swift
struct AttachmentRef: Codable, Hashable {
    var url: String
    var kind: AttachmentKind
    var fileName: String?
    var contentType: String?
    var isPrimary: Bool?
    var isUploading: Bool?
}
```

## Component Breakdown

| Component | Responsibility |
|-----------|---------------|
| `PinnedImagePanel` | The panel view — displays the image via `ZoomableScrollView`, close button, optional image counter. Accepts `AttachmentRef` binding and `onClose` callback. |
| `ImageGallery` (modified) | Gains an `onPin: ((AttachmentRef) -> Void)?` callback. When non-nil, shows pin button in controls. Calls back with the current image and dismisses itself. |
| `TransactionDetailView` / `ItemDetailView` (modified) | Own `@State var pinnedAttachment: AttachmentRef?`. Conditionally render `PinnedImagePanel` and adjust layout. Pass `onPin` closure to image-viewing child components. |

## Accessibility

- Pin button: label "Pin image for reference"
- Close button on panel: label "Unpin image"
- Panel itself: `accessibilityLabel("Pinned reference image")` with hint "Double tap to unpin" on the close button
- Zoom level announced on change via `accessibilityValue`
- Resize handle (iPhone): `accessibilityLabel("Resize pinned image panel")`, adjustable trait

## Animations

- Panel appear/disappear: `.spring(response: 0.35, dampingFraction: 0.85)`
- Image crossfade on swap: `.easeInOut(duration: 0.2)`
- Resize handle drag: real-time (no animation, follows finger)

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Image fails to load in pin panel | Show error icon (same as `ImageGallery` error state). Close button still available. |
| Image is uploading (`isUploading == true`) | Show progress indicator in panel. Image appears when upload completes. |
| User navigates away while image is pinned | State resets — no cleanup needed since it's `@State`. |
| User opens gallery while image is pinned | Gallery opens normally as fullscreen overlay on top of the pinned panel. Pinning a different image from the gallery replaces the pinned one. |
| Device rotation | Panel adapts — recalculates proportional height (iPhone) or uses fixed width (iPad). Zoom resets to fit. |
| Sheet presented over detail view | Pin panel remains visible beneath the sheet (sheets are partial-height by default). |

## Out of Scope

- **Multi-image pinning:** Only one image at a time. Multi-pin would add complexity without clear user value.
- **Pinning across screens:** Pin state does not carry between TransactionDetail → ItemDetail or vice versa.
- **Persistence:** Pin state is ephemeral. No Firestore writes, no UserDefaults.
- **PDF pinning:** Only `AttachmentKind.image` is pinnable. PDFs and generic files are not.
