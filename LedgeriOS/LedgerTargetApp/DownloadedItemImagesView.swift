import ImageIO
import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Authorization/catalog/export adapter for the original shared gallery.
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
    @State private var pinnedZoom: CGFloat = 1
    @State private var exportNotice: String?
    private struct Request: Equatable {
        let accountId: AccountID
        let itemId: ItemID
        let refresh: UUID
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                statusPane { ProgressView("Loading image information…") }
            case .unavailable:
                statusPane {
                    Text("Images are unavailable. Reconnect and try again.")
                        .accessibilityIdentifier("target-item-images-unavailable")
                }
            case .downloaded(let catalog):
                if catalog.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8),
                   catalog.itemId.rawValue.utf8.elementsEqual(itemId.rawValue.utf8) {
                    VStack(spacing: 0) {
                        if !catalog.isComplete {
                            Text("Image information is not fully downloaded. More images may be missing.")
                                .font(.caption).accessibilityIdentifier("target-item-images-incomplete")
                        }
                        if catalog.images.isEmpty {
                            statusPane {
                                Text(catalog.isComplete ? "No images" : "No image references downloaded yet")
                                    .accessibilityIdentifier("target-item-images-empty")
                            }
                        } else {
                            let selected = catalog.images.first {
                                $0.id.rawValue.utf8.elementsEqual((selection?.rawValue ?? "").utf8)
                            } ?? catalog.primaryImage!
                            let index = catalog.images.firstIndex { $0 == selected } ?? 0
                            if isPinned {
                                PinnedImagePresentation(imageCount: catalog.images.count,
                                    currentIndex: Binding(get: { index }, set: { selection = catalog.images[$0].id }),
                                    zoomScale: $pinnedZoom, onClose: close,
                                    onChangeImage: { selection = catalog.images[$0].id },
                                    accessibilityPrefix: "target-pinned",
                                    closeAccessibilityIdentifier: "target-item-image-unpin",
                                    allowsSwipePaging: true) {
                                        DownloadedItemPhotoView(accountId: accountId, itemId: itemId,
                                            image: selected, reader: reader, compact: true,
                                            scale: $pinnedZoom)
                                            .id(identity(selected))
                                    } actions: { EmptyView() }
                                    .accessibilityElement(children: .contain)
                                    .accessibilityIdentifier("target-pinned-image-viewer")
                            } else {
                                ImageGalleryPresentation(
                                    imageIDs: catalog.images.map(identity),
                                    initialIndex: index,
                                    isPresented: Binding(get: { true }, set: { if !$0 { close() } }),
                                    onPinImage: onPin.map { action in { action(catalog.images[$0].id) } },
                                    onShareImage: { export(catalog.images[$0], saveToDevice: false) },
                                    onRequestSave: saveAction(catalog.images),
                                    caption: { catalog.images[$0].isPrimary ? "Primary image" : nil },
                                    onSelectionChange: { selection = catalog.images[$0].id },
                                    actionsDisabled: model.isExporting,
                                    accessibilityPrefix: "target-item",
                                    showsZoomLevel: true
                                ) { context in
                                    DownloadedItemPhotoView(accountId: accountId, itemId: itemId,
                                        image: catalog.images[context.index], reader: reader,
                                        onTap: context.onTap, scale: context.zoom)
                                }
                            }
                        }
                    }
                } else {
                    statusPane {
                        Text("Images are unavailable. Refresh and try again.")
                            .accessibilityIdentifier("target-item-images-unavailable")
                    }
                }
            }
        }
        .frame(minWidth: 280, minHeight: isPinned ? 80 : 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            if !isPinned {
                HStack {
                    Button("Refresh images") { refresh = UUID() }
                        .accessibilityIdentifier("target-item-images-refresh")
                    if model.isExporting {
                        ProgressView("Preparing or delivering image…")
                            .accessibilityIdentifier("target-item-image-exporting")
                    }
                }
            }
        }
        .alert("Image", isPresented: Binding(get: { exportNotice != nil }, set: { if !$0 { exportNotice = nil } })) {
            Button("OK") { exportNotice = nil }
        } message: { Text(exportNotice ?? "") }
        .onChange(of: initialSelection?.rawValue.utf8.map { $0 }, initial: true) { _, _ in
            selection = initialSelection
        }
        .task(id: Request(accountId: accountId, itemId: itemId, refresh: refresh)) {
            await model.load(accountId: accountId, itemId: itemId, reader: reader)
        }
        .onDisappear { model.clear(); selection = nil; pinnedZoom = 1 }
    }

    private func identity(_ image: DownloadedItemImage) -> AnyHashable {
        AnyHashable([accountId.rawValue, itemId.rawValue, image.referenceId.rawValue,
            String(image.setRevision), image.object.attachmentId.rawValue,
            image.object.contentSHA256.rawValue].map { Data($0.utf8) })
    }

    private func close() {
        if let onUnpin { onUnpin() } else { dismiss() }
    }

    private func saveAction(_ images: [DownloadedItemImage]) -> ((Int) -> Void)? {
        #if os(iOS) || os(macOS)
        { export(images[$0], saveToDevice: true) }
        #else
        nil
        #endif
    }

    private func statusPane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack {
            HStack {
                Text(isPinned ? "Pinned reference image" : "Item images")
                Spacer()
                Button(isPinned ? "Unpin image" : "Done", action: close)
                    .accessibilityIdentifier(isPinned ? "target-item-image-unpin" : "target-item-images-done")
            }
            content()
        }.padding()
    }

    private func export(_ image: DownloadedItemImage, saveToDevice: Bool) {
        guard !model.isExporting else { return }
        Task { @MainActor in
            #if os(macOS)
            var destination: URL?
            #endif
            do {
                try await model.exportImage(accountId: accountId, itemId: itemId, image: image,
                    reader: reader, prepareDestination: {
                        #if os(iOS)
                        if saveToDevice { try await DownloadedImagePhotoSaving.requestPermission() }
                        #elseif os(macOS)
                        if saveToDevice {
                            destination = try await PropertyManagementReportSystemDelivery.imageSaveDestination(
                                fileName: nil, mediaType: image.object.mediaType)
                        }
                        #endif
                    }, handoff: { bytes in
                        #if os(iOS)
                        if saveToDevice { try await DownloadedImagePhotoSaving.save(bytes); return }
                        #elseif os(macOS)
                        if saveToDevice {
                            guard let destination, destination.isFileURL else {
                                throw PropertyManagementReportSystemDelivery.Failure.unavailablePresenter
                            }
                            try await PropertyManagementReportSystemDelivery.saveImage(bytes, to: destination)
                            return
                        }
                        #endif
                        try await PropertyManagementReportSystemDelivery.handoffImage(bytes)
                    })
                if saveToDevice {
                    #if os(macOS)
                    exportNotice = "Image saved."
                    #else
                    exportNotice = "Image saved to Photos."
                    #endif
                }
            } catch is CancellationError {
                return
            } catch {
                if let failure = error as? DownloadedItemImagesModel.ExportFailure {
                    switch failure {
                    case .alreadyExporting: exportNotice = "Finish the current image export first."
                    case .unavailable: exportNotice = "The image or your access changed. Refresh the image and try again."
                    case .missingBytes: exportNotice = "This image is not downloaded. Reconnect and try again."
                    }
                    return
                }
                #if os(iOS)
                if let permission = error as? DownloadedImagePhotoSaving.Failure {
                    exportNotice = permission.localizedDescription
                    return
                }
                if saveToDevice {
                    exportNotice = "The image could not be saved. \(error.localizedDescription)"
                    return
                }
                #endif
                exportNotice = "The image could not be exported. Its data or your access may have changed. Reconnect and try again."
            }
        }
    }
}

private struct DownloadedItemPhotoView: View {
    let accountId: AccountID
    let itemId: ItemID
    let image: DownloadedItemImage
    let reader: any DownloadedItemImageReading
    var compact = false
    var onTap: (() -> Void)? = nil
    @Binding var scale: CGFloat
    var body: some View {
        DownloadedMediaPhotoView(identity: AnyHashable([accountId.rawValue, itemId.rawValue,
            image.referenceId.rawValue, String(image.setRevision), image.object.storagePath].map { Data($0.utf8) }),
            load: { try await reader.loadDownloadedItemImage(accountId: accountId, itemId: itemId,
                image: image, allowDownload: true) }, onTap: onTap, scale: $scale)
    }
}

/// Shared decoded-image adapter; the caller supplies its live authorized bytes.
/// Original zoom/paging remain in ZoomableScrollView/ImageGalleryPresentation.
struct DownloadedMediaPhotoView: View {
    let identity: AnyHashable
    let load: @Sendable () async throws -> Data?
    var thumbnail = false
    var onTap: (() -> Void)? = nil
    @Binding var scale: CGFloat
    @State private var rendered: CGImage?
    @State private var message = "Loading image…"
    @State private var refresh = UUID()
    private struct Request: Equatable {
        let identity: AnyHashable
        let refresh: UUID
    }

    var body: some View {
        Group {
            if let rendered {
                if thumbnail {
                    Image(decorative: rendered, scale: 1).resizable().scaledToFill()
                } else {
                    ZoomableScrollView(source: GalleryImageSource(
                    identity: AnyHashable(ObjectIdentifier(rendered)),
                    image: platformImage(rendered)),
                    zoomScale: $scale, onSingleTap: onTap,
                    imageAccessibilityIdentifier: "target-item-image-rendered")
                }
            } else {
                VStack {
                    Text(message).accessibilityIdentifier("target-item-image-state")
                    Button("Retry image") { refresh = UUID() }
                        .accessibilityIdentifier("target-item-image-retry")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: Request(identity: identity, refresh: refresh)) {
            rendered = nil; message = "Loading image…"; scale = 1
            do {
                guard let bytes = try await load() else {
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
    private func platformImage(_ image: CGImage) -> GalleryPlatformImage {
        #if os(iOS)
        UIImage(cgImage: image)
        #else
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        #endif
    }
}
