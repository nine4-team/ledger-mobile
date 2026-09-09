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
        VStack(spacing: 12) {
            HStack {
                Text("Item images").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.accessibilityIdentifier("target-item-images-done")
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
                        let selected = catalog.images.first { $0.id == selection } ?? catalog.primaryImage!
                        DownloadedItemPhotoView(accountId: accountId, itemId: itemId, image: selected, reader: reader)
                            .id([accountId.rawValue, itemId.rawValue, selected.referenceId.rawValue,
                                 String(selected.setRevision), selected.object.attachmentId.rawValue,
                                 selected.object.contentSHA256.rawValue])
                        let index = catalog.images.firstIndex { $0.id == selected.id } ?? 0
                        HStack {
                            Button("Previous") { selection = catalog.images[index - 1].id }
                                .disabled(index == 0).accessibilityIdentifier("target-item-images-previous")
                            Text("\(index + 1) of \(catalog.images.count)")
                                .accessibilityIdentifier("target-item-images-counter")
                            Button("Next") { selection = catalog.images[index + 1].id }
                                .disabled(index + 1 >= catalog.images.count).accessibilityIdentifier("target-item-images-next")
                        }
                        if selected.isPrimary { Text("Primary image").font(.caption) }
                    }
                }
            }
            Button("Refresh images") { refresh = UUID() }
                .accessibilityIdentifier("target-item-images-refresh")
        }
        .padding().frame(minWidth: 280, minHeight: 360)
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
    @State private var rendered: CGImage?
    @State private var message = "Loading image…"
    @State private var refresh = UUID()
    @State private var scale: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    private struct Request: Equatable {
        let image: DownloadedItemImage
        let refresh: UUID
    }

    var body: some View {
        VStack {
            if let rendered {
                Image(decorative: rendered, scale: 1).resizable().scaledToFit()
                    .scaleEffect(min(5, max(1, scale * magnification)))
                    .gesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                        .onEnded { scale = min(5, max(1, scale * $0.magnification)) })
                    .onTapGesture(count: 2) { scale = scale > 1 ? 1 : 2.5 }
                    .accessibilityLabel("Downloaded Item image")
                    .accessibilityHidden(false)
                    .accessibilityIdentifier("target-item-image-rendered")
            } else {
                Text(message).accessibilityIdentifier("target-item-image-state")
                Button("Retry image") { refresh = UUID() }
                    .accessibilityIdentifier("target-item-image-retry")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 400).clipped()
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
