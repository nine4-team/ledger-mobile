# Image Pinning

## Purpose
Lets users pin an image to a persistent reference panel so they can view it while editing transaction or item details.

## Files

- `Components/PinnedImagePanel.swift` — The panel view: zoomable image, close button, image counter with navigation
- `Components/PinnedImageLayout.swift` — Adaptive layout wrapper. iPhone: vertical split with resize handle. iPad: leading sidebar.
- `Components/ZoomableScrollView.swift` — Extracted UIScrollView wrapper shared by ImageGallery and PinnedImagePanel
- `Logic/PinnedImageCalculations.swift` — Pure functions for resize clamping and pin eligibility

## State

No `@Observable` store. Pin state is view-local `@State` on each detail view:

- **TransactionDetailView:** `pinnedAttachment: AttachmentRef?` and `pinnedImageSource: [AttachmentRef]` (tracks which collection the pinned image came from — receipts or otherImages)
- **ItemDetailView:** `pinnedAttachment: AttachmentRef?` (single image source)

State resets automatically on navigation since it's `@State`. No persistence, no Firestore writes.

## Data

No Firestore reads or writes. Uses existing `AttachmentRef` from transaction/item image arrays.

## Sheets & Navigation

No sheets. The pin panel is an inline layout element, not a presented sheet.

- Pinning from the gallery (`ImageGallery.onPinImage`) dismisses the gallery fullScreenCover.
- Pinning from the attachment menu (`MediaGallerySection` options menu) dismisses the menu sheet.
- The gallery can open on top of the pin panel (both coexist — gallery is fullScreenCover, panel is inline).

## Entry Points

Two ways to pin:

1. **Gallery pin button** — Always-visible button next to close (X) in ImageGallery. Calls `onPinImage` with current image, dismisses gallery.
2. **Attachment menu** — "Pin Image" action in MediaGallerySection's per-thumbnail options menu. Only shown for image-kind attachments that aren't mid-upload.

## Component Hierarchy

```
TransactionDetailView / ItemDetailView
└── PinnedImageLayout<Content>      (adaptive: iPhone vertical split / iPad sidebar)
    ├── PinnedImagePanel             (when pinned)
    │   └── ZoomableScrollView       (shared UIScrollView wrapper)
    └── Content (ScrollView)         (always)
```

## Gotchas

- `PinnedImageLayout` introduces `@Environment(\.horizontalSizeClass)` — the first use in the codebase. iPhone returns `.compact`, iPad returns `.regular`.
- The resize handle uses `@GestureState` to capture the starting fraction on drag start. This auto-resets when the gesture ends, avoiding the common DragGesture cumulative-translation bug.
- `ZoomableScrollView` was extracted from `ImageGallery.swift` where it was `private`. It's now a top-level struct in its own file. Both ImageGallery and PinnedImagePanel depend on it.
- TransactionDetailView tracks `pinnedImageSource` separately because it has two image collections (receipts, otherImages). The counter navigates within whichever collection the pinned image came from.
