import ImageIO
import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

/// Reads one selected original at a time. No list-wide eager image downloads,
/// signed-URL identity, or fallback from missing metadata to an empty gallery.
struct DownloadedItemImagesView: View {
    let accountId: AccountID
    let itemId: ItemID
    let reader: any DownloadedItemImageReading
    var initialSelection: EntityID? = nil
    var onPin: ((EntityID) -> Void)? = nil
    var onUnpin: (() -> Void)? = nil
    private var isPinned: Bool { onUnpin != nil }
    @Environment(\.dismiss) private var dismiss
    @State private var model = DownloadedItemImagesModel()
    @State private var selection: EntityID?
    @State private var refresh = UUID()
    private struct Request: Equatable {
        let accountId: AccountID
        let itemId: ItemID
        let refresh: UUID
    }

    var body: some View {
        VStack(spacing: isPinned ? 2 : 12) {
            HStack {
                Text(isPinned ? "Pinned reference image" : "Item images")
                    .font(isPinned ? .caption : .headline).lineLimit(1)
                Spacer()
                if let onUnpin {
                    Button("Unpin image", action: onUnpin)
                        .accessibilityIdentifier("target-item-image-unpin")
                } else {
                    Button("Done") { dismiss() }.accessibilityIdentifier("target-item-images-done")
                }
            }
            switch model.state {
            case .idle, .loading: ProgressView("Loading image information…")
            case .unavailable:
                Text("Images are unavailable. Reconnect and try again.")
                    .accessibilityIdentifier("target-item-images-unavailable")
            case .downloaded(let catalog):
                if catalog.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8),
                   catalog.itemId.rawValue.utf8.elementsEqual(itemId.rawValue.utf8) {
                    if !catalog.isComplete {
                        Text("Image information is not fully downloaded. More images may be missing.")
                            .font(.caption).accessibilityIdentifier("target-item-images-incomplete")
                    }
                    if catalog.images.isEmpty {
                        Text(catalog.isComplete ? "No images" : "No image references downloaded yet")
                            .accessibilityIdentifier("target-item-images-empty")
                    } else {
                        let selected = catalog.images.first {
                            $0.id.rawValue.utf8.elementsEqual((selection?.rawValue ?? "").utf8)
                        } ?? catalog.primaryImage!
                        DownloadedItemPhotoView(accountId: accountId, itemId: itemId, image: selected,
                            reader: reader, compact: isPinned)
                            .id([accountId.rawValue, itemId.rawValue, selected.referenceId.rawValue,
                                 String(selected.setRevision), selected.object.attachmentId.rawValue,
                                 selected.object.contentSHA256.rawValue])
                        let index = catalog.images.firstIndex { $0 == selected } ?? 0
                        if catalog.images.count > 1 { HStack {
                            Button("Previous") { selection = catalog.images[(index + catalog.images.count - 1) % catalog.images.count].id }
                                .accessibilityIdentifier(isPinned ? "target-pinned-images-previous" : "target-item-images-previous")
                            Text("\(index + 1) of \(catalog.images.count)")
                                .accessibilityIdentifier(isPinned ? "target-pinned-images-counter" : "target-item-images-counter")
                            Button("Next") { selection = catalog.images[(index + 1) % catalog.images.count].id }
                                .accessibilityIdentifier(isPinned ? "target-pinned-images-next" : "target-item-images-next")
                        } }
                        if !isPinned {
                            if selected.isPrimary { Text("Primary image").font(.caption) }
                            if let onPin {
                                Button("Pin image for reference") { onPin(selected.id); dismiss() }
                                    .accessibilityIdentifier("target-item-image-pin")
                            }
                        }
                    }
                }
            }
            if !isPinned {
                Button("Refresh images") { refresh = UUID() }
                    .accessibilityIdentifier("target-item-images-refresh")
            }
        }
        .padding(isPinned ? 8 : 16).frame(minWidth: 280, minHeight: isPinned ? 80 : 360)
        .onChange(of: initialSelection?.rawValue.utf8.map { $0 }, initial: true) { _, _ in
            selection = initialSelection
        }
        .task(id: Request(accountId: accountId, itemId: itemId, refresh: refresh)) {
            await model.load(accountId: accountId, itemId: itemId, reader: reader)
        }
        .onDisappear { model.clear(); selection = nil }
    }
}

private struct DownloadedItemPhotoView: View {
    let accountId: AccountID
    let itemId: ItemID
    let image: DownloadedItemImage
    let reader: any DownloadedItemImageReading
    var compact = false
    @State private var rendered: CGImage?
    @State private var message = "Loading image…"
    @State private var refresh = UUID()
    @State private var scale: CGFloat = 1
    private struct Request: Equatable {
        let image: DownloadedItemImage
        let refresh: UUID
    }

    var body: some View {
        VStack {
            if let rendered {
                DownloadedImageZoomSurface(image: rendered, zoomScale: $scale)
                    .frame(minHeight: compact ? 0 : 200)
                if !compact { HStack {
                    Button("Zoom out") { scale = max(1, scale - 0.5) }
                        .disabled(scale <= 1).accessibilityIdentifier("target-item-image-zoom-out")
                    Text(Double(scale).formatted(.number.precision(.fractionLength(1))) + "×")
                        .accessibilityIdentifier("target-item-image-zoom-level")
                    Button("Zoom in") { scale = min(5, scale + 0.5) }
                        .disabled(scale >= 5).accessibilityIdentifier("target-item-image-zoom-in")
                }
                // Keep the image viewport stable when Reset appears. A real
                // viewport resize intentionally resets the native surface to fit.
                ZStack {
                    Color.clear
                    if scale > 1.01 {
                        Button("Reset zoom") { scale = 1 }
                            .accessibilityIdentifier("target-item-image-zoom-reset")
                    }
                }.frame(height: 32) }
            } else {
                Text(message).accessibilityIdentifier("target-item-image-state")
                Button("Retry image") { refresh = UUID() }
                    .accessibilityIdentifier("target-item-image-retry")
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 0 : 240, maxHeight: compact ? .infinity : 400).clipped()
        .task(id: Request(image: image, refresh: refresh)) {
            rendered = nil; message = "Loading image…"; scale = 1
            do {
                guard let bytes = try await reader.loadDownloadedItemImage(accountId: accountId,
                    itemId: itemId, image: image, allowDownload: true) else {
                    try Task.checkCancellation(); message = "Image not downloaded. Reconnect and retry."; return
                }
                try Task.checkCancellation()
                guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                      let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 4096
                      ] as CFDictionary) else { throw DownloadedItemImageFailure.malformed }
                try Task.checkCancellation()
                rendered = decoded
            } catch { if !Task.isCancelled { message = "Image unavailable. Retry when connected." } }
        }
        .onDisappear { rendered = nil }
    }
}
