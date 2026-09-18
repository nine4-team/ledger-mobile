import LedgerTargetCore
import LedgerTargetAppModel
import LedgerTargetPowerSync
import SwiftUI

struct SpacePinnedMedia: Identifiable {
    let catalog: DownloadedSpaceMedia
    let attachment: DownloadedSpaceMedia.Attachment
    var id: String { catalog.spaceId.rawValue + ":" + String(catalog.revision ?? 0) + ":" + attachment.id.rawValue }
}

/// Keep the original resizable pin layout outside scrolling detail content.
struct SpaceMediaPinHost<Content: View>: View {
    let reader: (any DownloadedSpaceMediaReading)?
    let route: ActiveWorkspaceToSpaceChecklistRoute
    @ViewBuilder let content: (@escaping (SpacePinnedMedia) -> Void) -> Content
    @State private var pin: SpacePinnedMedia?
    var body: some View {
        PinnedImageLayoutPresentation(pinIdentity: pin?.id) {
            if let pin, let reader { SpacePinnedMediaView(pin: pin,reader: reader,onClose: { self.pin = nil }) }
        } content: { content { pin = $0 } }
        .onChange(of: route) { _, _ in pin = nil }
    }
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
    @State private var exporting = false
    private enum ExportAction { case save, share, copy }

    var body: some View {
        CollapsibleSection(title: "MEDIA",isExpanded: $expanded,onPrint: printPhotos,
            isPrinting: printing,isPrintDisabled: catalog?.isComplete != true || catalog?.printableImages.isEmpty != false) {
            if loading { ProgressView("Loading media…") }
            else if let catalog {
                if !catalog.isComplete { Text("Media information is not fully downloaded.").font(.caption) }
                if catalog.attachments.isEmpty {
                    Text(catalog.isComplete ? "No media" : "No media references downloaded yet").font(.caption)
                } else {
                    ThumbnailGridPresentation(count: catalog.attachments.count,
                        isPrimary: { catalog.attachments[$0].isPrimary },thumbnail: { index in
                            let attachment = catalog.attachments[index]
                            Group {
                                if attachment.isImage { photo(catalog,attachment,thumbnail: true,scale: .constant(1)) }
                                else { PDFThumbnailTile(fileName: attachment.fileName) }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(attachment.fileName ?? "Space media")
                            .accessibilityIdentifier("target-space-media-" + attachment.id.rawValue)
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
        .alert("Space Media",isPresented: Binding(get: { notice != nil },set: { if !$0 { notice = nil } })) {
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
                    onSaveImage: { try await performExport(catalog,images[$0],action: .save) },
                    onShareImage: { export(catalog,images[$0],action: .share) },
                    onCopyImage: { try await performExport(catalog,images[$0],action: .copy) },
                    caption: { images[$0].fileName },actionsDisabled: exporting,accessibilityPrefix: "target-space") { context in
                        photo(catalog,images[context.index],scale: context.zoom,onTap: context.onTap)
                    }
            } else {
                AuthorizedPDFViewer(fileName: attachment.fileName,
                    load: { try await reader.loadDownloadedSpaceMedia(catalog: catalog,attachment: attachment,allowDownload: true) },
                    isPresented: presented,onPin: { onPin(.init(catalog: catalog,attachment: attachment)) },
                    onShare: exporting ? nil : { export(catalog,attachment,action: .share) })
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
    private func export(_ value: DownloadedSpaceMedia,_ attachment: DownloadedSpaceMedia.Attachment,action: ExportAction) {
        guard !exporting else { return }
        let request = generation
        Task {
            do { try await performExport(value,attachment,action: action) }
            catch is CancellationError { }
            catch { if generation == request { notice = error.localizedDescription } }
        }
    }

    private func performExport(_ value: DownloadedSpaceMedia,_ attachment: DownloadedSpaceMedia.Attachment,
                               action: ExportAction) async throws {
        guard !exporting else { throw AuthorizedMediaExport.Failure.alreadyExporting }
        exporting = true; defer { exporting = false }
        let request = generation
        #if os(macOS)
        var destination: URL?
        #endif
        try await AuthorizedMediaExport.perform(validate: {
            guard generation == request, catalog?.retains(attachment,from: value) == true else {
                throw DownloadedSpaceMedia.Failure.unavailable
            }
        },prepareDestination: {
            if action == .save {
                #if os(iOS)
                try await DownloadedImagePhotoSaving.requestPermission()
                #else
                destination = try await PropertyManagementReportSystemDelivery.imageSaveDestination(
                    fileName: attachment.fileName,mediaType: attachment.object.mediaType)
                #endif
            }
        },load: {
            try await reader.loadDownloadedSpaceMedia(catalog: value,attachment: attachment,allowDownload: true)
        },handoff: { bytes in
            let current = try await reader.readDownloadedSpaceMedia(accountId: accountId,spaceId: spaceId,scope: scope)
            guard generation == request, current.retains(attachment,from: value) else { throw DownloadedSpaceMedia.Failure.unavailable }
            if !attachment.isImage {
                try await SpaceMediaPDFDelivery.deliver(data: bytes,catalog: value,attachment: attachment,reader: reader) { url in
                    guard generation == request, catalog?.retains(attachment,from: value) == true else { throw CancellationError() }
                    try await PropertyManagementReportSystemDelivery.handoff(url,action: .share)
                }
            } else if action == .copy { try Clipboard.copyImage(bytes,mediaType: attachment.object.mediaType) }
            else if action == .save {
                #if os(iOS)
                try await DownloadedImagePhotoSaving.save(bytes)
                #else
                guard let destination else { throw CancellationError() }
                try await PropertyManagementReportSystemDelivery.saveImage(bytes,to: destination)
                #endif
            } else { try await PropertyManagementReportSystemDelivery.handoffImage(bytes) }
        })
    }

    private func printPhotos() {
        guard !printing, let value = catalog, value.isComplete, !value.printableImages.isEmpty else { return }
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
                guard generation == request, current.isComplete,
                      current.printableImages == value.printableImages,
                      value.printableImages.allSatisfy({ current.retains($0,from: value) }) else {
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
                    let next = value.selection(retaining: selected,fallback: pin.attachment)?.id
                    if selected != next { selected = next; zoom = 1 }
                    catalog = value
                }
            } catch { }
            catalog = nil
            if !Task.isCancelled { onClose() }
        }
    }
}
