import LedgerTargetCore
import SwiftUI

struct SpacePinnedMedia: Identifiable {
    let catalog: DownloadedSpaceMedia
    let attachment: DownloadedSpaceMedia.Attachment
    var id: String { catalog.spaceId.rawValue + ":" + String(catalog.revision ?? 0) + ":" + attachment.id.rawValue }
}

/// Space-scoped loading/actions around the existing gallery controls.
struct SpaceMediaSection: View {
    let accountId: AccountID
    let spaceId: SpaceID
    let scope: SpaceCreationScope
    let reader: any DownloadedSpaceMediaReading
    let onPin: (SpacePinnedMedia) -> Void
    @State private var expanded = true
    @State private var catalog: DownloadedSpaceMedia?
    @State private var selected: DownloadedSpaceMedia.Attachment?
    @State private var loading = true
    @State private var generation = UUID()
    @State private var printTask: Task<Void,Never>?
    @State private var printing = false
    @State private var notice: String?

    var body: some View {
        CollapsibleSection(title: "MEDIA",isExpanded: $expanded,onPrint: printPhotos,
            isPrinting: printing,isPrintDisabled: catalog?.printableImages.isEmpty != false) {
            if loading { ProgressView("Loading media…") }
            else if let catalog {
                if !catalog.isComplete { Text("Media information is not fully downloaded.").font(.caption) }
                if catalog.attachments.isEmpty {
                    Text(catalog.isComplete ? "No media" : "No media references downloaded yet").font(.caption)
                } else {
                    ThumbnailGridPresentation(count: catalog.attachments.count,
                        isPrimary: { catalog.attachments[$0].isPrimary },thumbnail: { index in
                            let attachment = catalog.attachments[index]
                            if attachment.isImage { photo(catalog,attachment,thumbnail: true,scale: .constant(1)) }
                            else { PDFThumbnailTile(fileName: attachment.fileName) }
                        },upload: { _ in EmptyView() },onThumbnailTap: { selected = catalog.attachments[$0] })
                }
            } else { Text("Media unavailable. Refresh Space to retry.").font(.caption) }
        }
        .accessibilityIdentifier("target-space-media")
        #if os(iOS)
        .fullScreenCover(item: $selected) { viewer($0) }
        #else
        .adaptivePresentation(item: $selected,style: .viewer) { viewer($0) }
        #endif
        .alert("Print Space Photos",isPresented: Binding(get: { notice != nil },set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: { Text(notice ?? "") }
        .task(id: [accountId.rawValue,spaceId.rawValue,String(describing: scope)]) {
            let request = UUID(); generation = request; catalog = nil; selected = nil; loading = true
            do {
                for try await value in reader.watchDownloadedSpaceMedia(accountId: accountId,spaceId: spaceId,scope: scope) {
                    try Task.checkCancellation()
                    guard generation == request else { return }
                    guard value == nil || (value?.accountId == accountId && value?.spaceId == spaceId && value?.scope == scope) else { break }
                    if let selection = selected, let previous = catalog, value?.retains(selection,from: previous) != true { selected = nil }
                    if value?.revision != catalog?.revision || value == nil { printTask?.cancel() }
                    catalog = value; loading = false
                }
            } catch { }
            if generation == request { catalog = nil; selected = nil; loading = false; printTask?.cancel() }
        }
        .onDisappear { generation = UUID(); printTask?.cancel(); printTask = nil; printing = false }
    }

    @ViewBuilder private func viewer(_ attachment: DownloadedSpaceMedia.Attachment) -> some View {
        if let catalog, catalog.attachments.contains(attachment) {
            let presented = Binding(get: { selected != nil },set: { if !$0 { selected = nil } })
            if attachment.isImage {
                let images = catalog.printableImages
                ImageGalleryPresentation(imageIDs: images.map { identity(catalog,$0) },
                    initialIndex: images.firstIndex(of: attachment) ?? 0,isPresented: presented,
                    onPinImage: { onPin(.init(catalog: catalog,attachment: images[$0])) },
                    caption: { images[$0].fileName },accessibilityPrefix: "target-space") { context in
                        photo(catalog,images[context.index],scale: context.zoom,onTap: context.onTap)
                    }
            } else {
                AuthorizedPDFViewer(fileName: attachment.fileName,
                    load: { try await reader.loadDownloadedSpaceMedia(catalog: catalog,attachment: attachment,allowDownload: true) },
                    isPresented: presented,onPin: { onPin(.init(catalog: catalog,attachment: attachment)) })
                    .id(identity(catalog,attachment))
            }
        }
    }

    private func identity(_ catalog: DownloadedSpaceMedia,_ attachment: DownloadedSpaceMedia.Attachment) -> AnyHashable {
        AnyHashable([accountId.rawValue,spaceId.rawValue,String(catalog.revision ?? 0),attachment.id.rawValue,attachment.object.storagePath])
    }
    private func photo(_ catalog: DownloadedSpaceMedia,_ attachment: DownloadedSpaceMedia.Attachment,
                       thumbnail: Bool = false,scale: Binding<CGFloat>,onTap: (() -> Void)? = nil) -> some View {
        DownloadedMediaPhotoView(identity: identity(catalog,attachment),
            load: { try await reader.loadDownloadedSpaceMedia(catalog: catalog,attachment: attachment,allowDownload: true) },
            thumbnail: thumbnail,onTap: onTap,scale: scale)
    }
    private func printPhotos() {
        guard !printing, let value = catalog, !value.printableImages.isEmpty else { return }
        let request = generation; printing = true
        printTask = Task {
            defer { if generation == request { printing = false; printTask = nil } }
            do {
                var photos: [Data] = []
                for attachment in value.printableImages {
                    guard let bytes = try await reader.loadDownloadedSpaceMedia(catalog: value,attachment: attachment,allowDownload: true) else {
                        throw PhotoPrintError.unavailablePhoto
                    }
                    photos.append(bytes)
                }
                let pdf = try PhotoPrintPresentation.makePDF(from: photos)
                let current = try await reader.readDownloadedSpaceMedia(accountId: accountId,spaceId: spaceId,scope: scope)
                guard generation == request, value.printableImages.allSatisfy({ current.retains($0,from: value) }) else {
                    throw CancellationError()
                }
                try Task.checkCancellation()
                try await PhotoPrintPresentation.presentPrintDialog(pdfData: pdf,jobName: "Space Photos")
            } catch is CancellationError { }
            catch { if generation == request { notice = error.localizedDescription } }
        }
    }
}

struct SpacePinnedMediaView: View {
    let pin: SpacePinnedMedia
    let reader: any DownloadedSpaceMediaReading
    let onClose: () -> Void
    @State private var catalog: DownloadedSpaceMedia?
    @State private var selected: EntityID?
    @State private var zoom: CGFloat = 1
    var body: some View {
        Group {
            if let catalog {
                let entries = pin.attachment.isImage ? catalog.printableImages : [pin.attachment]
                if let index = entries.firstIndex(where: { $0.id == (selected ?? pin.attachment.id) }) {
                    let attachment = entries[index]
                    PinnedImagePresentation(imageCount: entries.count,
                        currentIndex: Binding(get: { index },set: { selected = entries[$0].id }),zoomScale: $zoom,
                        onClose: onClose,onChangeImage: { selected = entries[$0].id },
                        accessibilityPrefix: "target-space-pinned",allowsSwipePaging: attachment.isImage) {
                            if attachment.isImage {
                                DownloadedMediaPhotoView(identity: attachment.object.storagePath,
                                    load: { try await reader.loadDownloadedSpaceMedia(catalog: catalog,attachment: attachment,allowDownload: true) },scale: $zoom)
                                    .id(attachment.id)
                            } else {
                                AuthorizedPDFContent(accessibilityIdentifier: "target-space-pinned-pdf") {
                                    try await reader.loadDownloadedSpaceMedia(catalog: catalog,attachment: attachment,allowDownload: true)
                                }.id(attachment.id)
                            }
                        } actions: { EmptyView() }
                }
            } else { ProgressView("Loading pinned media…") }
        }
        .task(id: pin.id) {
            catalog = nil; selected = nil; zoom = 1
            do {
                for try await value in reader.watchDownloadedSpaceMedia(accountId: pin.catalog.accountId,spaceId: pin.catalog.spaceId,scope: pin.catalog.scope) {
                    try Task.checkCancellation()
                    guard let value, value.retains(pin.attachment,from: pin.catalog) else { break }
                    catalog = value
                }
            } catch { }
            catalog = nil
            if !Task.isCancelled { onClose() }
        }
    }
}
