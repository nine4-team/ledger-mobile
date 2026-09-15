import LedgerTargetCore
import LedgerTargetAppModel
import LedgerTargetPowerSync
import PDFKit
import SwiftUI

/// Transaction-specific catalog/access binding around the original media views.
struct TransactionAttachmentsSection: View {
    let scope: TransactionScope
    let transactionId: TransactionID
    let section: TransactionAttachmentSection
    let reader: any DownloadedTransactionAttachmentReading
    var onPin: ((TransactionPinnedAttachment) -> Void)? = nil
    @State private var expanded: Bool
    @State private var catalog: DownloadedTransactionAttachments?
    @State private var selected: DownloadedTransactionAttachment?
    @State private var loading = true
    @State private var request = UUID()
    @State private var exporting = false
    @State private var exportNotice: String?
    @State private var showCaptureMenu = false
    @State private var capturing = false
    @State private var captureError: String?
    private var capturer: (any TransactionAttachmentCapturing)? { reader as? any TransactionAttachmentCapturing }
    private var canCapture: Bool {
        capturer != nil && catalog?.isComplete == true && !capturing
            && (catalog?.attachments.count ?? 50) < TransactionAttachmentCaptureAdmission.maximumAttachments
    }
    private var title: String { section == .receipts ? "Receipts" : "Other Images" }

    init(scope: TransactionScope, transactionId: TransactionID, section: TransactionAttachmentSection,
         reader: any DownloadedTransactionAttachmentReading, onPin: ((TransactionPinnedAttachment) -> Void)? = nil) {
        self.scope = scope; self.transactionId = transactionId; self.section = section; self.reader = reader
        self.onPin = onPin
        _expanded = State(initialValue: section == .receipts)
    }

    var body: some View {
        CollapsibleSection(title: title, isExpanded: $expanded,
            badge: catalog.map { $0.isComplete ? String($0.attachments.count) : "…" } ?? "…") {
            VStack(spacing: Spacing.sm) {
                if loading { ProgressView("Loading attachment information…") }
                else if let catalog {
                    if !catalog.isComplete {
                        Text("Attachment information is not fully downloaded. More attachments may be missing.").font(.caption)
                    }
                    if catalog.attachments.isEmpty && !canCapture {
                        Text(catalog.isComplete ? "No attachments" : "No attachment references downloaded yet").font(.caption)
                    } else {
                        ThumbnailGridPresentation(count: catalog.attachments.count,
                            showAddTile: canCapture,
                            isPrimary: { catalog.attachments[$0].isPrimary }, thumbnail: { index in
                                let attachment = catalog.attachments[index]
                                if attachment.object.mediaType == "application/pdf" {
                                    PDFThumbnailTile(fileName: attachment.fileName)
                                } else {
                                    photo(catalog, attachment: attachment, thumbnail: true, scale: .constant(1))
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(attachment.fileName ?? "Image")
                                        .contextMenu {
                                            if let onPin {
                                                Button("Pin Image", systemImage: "pin") {
                                                    onPin(.init(catalog: catalog, attachment: attachment))
                                                }
                                            }
                                        }
                                }
                            }, upload: { index in
                                if catalog.attachments[index].localReceipt != nil {
                                    let rejected = catalog.localUploadRejections[catalog.attachments[index].object.attachmentId] != nil
                                    AttachmentUploadStatusOverlay(icon: rejected ? "exclamationmark.triangle" : "clock")
                                        .accessibilityLabel(rejected ? "Upload rejected; original saved on this device" : "Saved on this device; upload pending")
                                        .accessibilityIdentifier(rejected ? "target-transaction-attachment-rejected" : "target-transaction-attachment-pending")
                                        .allowsHitTesting(false)
                                }
                            }, onThumbnailTap: { selected = catalog.attachments[$0] },
                            onAddTap: { showCaptureMenu = true })
                        if !catalog.localUploadRejections.isEmpty {
                            Text("Some uploads could not finish. Originals are saved on this device. Open an attachment to share a copy.")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("target-transaction-attachment-recovery")
                        }
                    }
                } else { Text("Attachments unavailable. Reconnect and try again.").font(.caption) }
                if capturing { ProgressView("Saving attachment on this device…") }
                if let captureError { Text(captureError).font(.caption).foregroundStyle(BrandColors.destructive) }
            }.padding(.top, Spacing.xs)
        }
        .accessibilityIdentifier("target-transaction-attachments-" + section.rawValue)
        #if os(iOS)
        .fullScreenCover(item: $selected) { viewer($0) }
        #else
        .adaptivePresentation(item: $selected, style: .viewer) { viewer($0) }
        #endif
        .modifier(MediaCapturePresentation(showAddSourceMenu: $showCaptureMenu, isUploading: $capturing,
            uploadError: $captureError,
            remainingSlots: catalog?.isComplete == true && capturer != nil
                ? max(0, TransactionAttachmentCaptureAdmission.maximumAttachments - (catalog?.attachments.count ?? 0)) : 0,
            allowedKinds: section == .receipts ? [.image, .pdf] : [.image],
            onUploadAttachmentFile: capturer == nil ? nil : { try await capture($0.data, fileName: $0.displayFileName) },
            onUploadDocument: section == .receipts && capturer != nil ? { try await capture($0, fileName: $1) } : nil,
            allowsImagePaste: true))
        .alert("Attachment", isPresented: Binding(get: { exportNotice != nil }, set: { if !$0 { exportNotice = nil } })) {
            Button("OK") { exportNotice = nil }
        } message: { Text(exportNotice ?? "") }
        .task(id: [scope.accountId.rawValue, scope.ownerKind.rawValue, scope.projectId?.rawValue ?? "",
            scope.clientId?.rawValue ?? "", transactionId.rawValue, section.rawValue]) {
            let generation = UUID()
            request = generation; catalog = nil; selected = nil; loading = true
            do {
                for try await value in reader.watchDownloadedTransactionAttachments(scope: scope,
                    transactionId: transactionId, section: section) {
                    try Task.checkCancellation()
                    guard request == generation else { return }
                    guard value == nil || (value?.scope == scope && value?.transactionId == transactionId && value?.section == section) else {
                        break
                    }
                    if let selection = selected, let previous = catalog,
                       let replacement = value?.publishedReplacement(for: selection, from: previous) {
                        selected = replacement
                    } else if value?.revision != catalog?.revision || selected.map({ value?.attachments.contains($0) != true }) == true {
                        selected = nil
                    }
                    catalog = value; loading = false
                }
            } catch {}
            guard request == generation else { return }
            catalog = nil; selected = nil; loading = false
        }
        .onDisappear {
            request = UUID(); catalog = nil; selected = nil
        }
    }

    private func capture(_ bytes: Data, fileName: String) async throws {
        let generation = request
        guard let capturer, catalog?.isComplete == true else { throw TransactionAttachmentCaptureFailure.unavailable }
        let captureScope = try await capturer.transactionAttachmentCaptureScope(scope: scope, transactionId: transactionId)
        let section = section
        let prepared = try await Task.detached(priority: .userInitiated) { @Sendable in
            try AttachmentCapturePreparation.prepare(bytes: bytes, fileName: fileName,
                allowsPDF: section == .receipts, attachmentId: AttachmentID(validating: UUID().uuidString.lowercased()),
                scope: captureScope, transactionSection: section,
                capturedAt: AttachmentEpochMilliseconds(validating: Int64(Date().timeIntervalSince1970 * 1000)))
        }.value
        guard request == generation, catalog?.isComplete == true else { throw CancellationError() }
        _ = try await capturer.captureTransactionAttachment(prepared, scope: scope)
    }

    @ViewBuilder private func viewer(_ selection: DownloadedTransactionAttachment) -> some View {
        if let catalog, catalog.attachments.contains(selection) {
            let presented = Binding(get: { selected != nil }, set: {
                if !$0 { selected = nil }
            })
            if selection.object.mediaType == "application/pdf" {
                TransactionAttachmentPDFView(catalog: catalog, attachment: selection, reader: reader,
                    isPresented: presented,
                    onPin: onPin.map { action in { action(.init(catalog: catalog, attachment: selection)) } },
                    onShare: exporting ? nil : { exportAttachment(catalog, attachment: selection, action: .share) })
                    .id(identity(catalog, selection))
            } else {
                let images = catalog.attachments.filter { $0.object.mediaType.hasPrefix("image/") }
                ImageGalleryPresentation(imageIDs: images.map { identity(catalog, $0) },
                    initialIndex: images.firstIndex(of: selection) ?? 0, isPresented: presented,
                    onPinImage: onPin.map { action in { action(.init(catalog: catalog, attachment: images[$0])) } },
                    onSaveImage: saveAction(catalog, images: images),
                    onShareImage: { exportAttachment(catalog, attachment: images[$0], action: .share) },
                    onCopyImage: { index in
                        do { try await performExport(catalog, attachment: images[index], action: .copy) }
                        catch { throw ExportMessage(errorDescription: exportFailureMessage(error)) }
                    },
                    caption: { images[$0].fileName }, actionsDisabled: exporting,
                    accessibilityPrefix: "target-transaction") { context in
                        photo(catalog, attachment: images[context.index], thumbnail: false,
                            scale: context.zoom, onTap: context.onTap)
                    }
            }
        } else { ContentUnavailableView("Attachment unavailable", systemImage: "doc") }
    }

    private func identity(_ catalog: DownloadedTransactionAttachments, _ attachment: DownloadedTransactionAttachment) -> AnyHashable {
        transactionAttachmentIdentity(catalog, attachment)
    }

    private func saveAction(_ value: DownloadedTransactionAttachments,
        images: [DownloadedTransactionAttachment]) -> ((Int) async throws -> Void)? {
        #if os(iOS) || os(macOS)
        { index in
            do { try await performExport(value, attachment: images[index], action: .save) }
            catch is CancellationError { throw CancellationError() }
            catch { throw ExportMessage(errorDescription: exportFailureMessage(error)) }
        }
        #else
        nil
        #endif
    }

    private enum ExportAction { case save, share, copy }

    private func exportAttachment(_ value: DownloadedTransactionAttachments,
        attachment: DownloadedTransactionAttachment, action: ExportAction) {
        guard !exporting else { return }
        let generation = request
        Task { @MainActor in
            do {
                try await performExport(value, attachment: attachment, action: action)
            } catch is CancellationError {
                return
            } catch {
                guard request == generation else { return }
                exportNotice = exportFailureMessage(error)
            }
        }
    }

    private func performExport(_ value: DownloadedTransactionAttachments,
        attachment: DownloadedTransactionAttachment, action: ExportAction) async throws {
        guard !exporting else { throw AuthorizedMediaExport.Failure.alreadyExporting }
        exporting = true
        defer { exporting = false }
        let generation = request
        let save = action == .save
        #if os(macOS)
        var destination: URL?
        #endif
        // Return only after native delivery completes; the existing gallery
        // owns Save feedback. Authorization remains checked before handoff.
        try await AuthorizedMediaExport.perform(validate: {
            guard request == generation, let current = catalog,
                  current.retains(attachment, from: value) else {
                throw DownloadedTransactionAttachments.Failure.unavailable
            }
        }, prepareDestination: {
            #if os(iOS)
            if save { try await DownloadedImagePhotoSaving.requestPermission() }
            #elseif os(macOS)
            if save {
                destination = try await PropertyManagementReportSystemDelivery.imageSaveDestination(
                    fileName: attachment.fileName, mediaType: attachment.object.mediaType)
            }
            #endif
        }, load: {
            try await reader.loadDownloadedTransactionAttachment(catalog: value,
                attachment: attachment, allowDownload: true)
        }, handoff: { bytes in
            if action == .copy {
                try Clipboard.copyImage(bytes, mediaType: attachment.object.mediaType)
                return
            }
            if attachment.object.mediaType == "application/pdf" {
                try await TransactionAttachmentPDFDelivery.deliver(data: bytes, catalog: value,
                    attachment: attachment, reader: reader) { url in
                    guard request == generation, catalog?.retains(attachment, from: value) == true else {
                        throw DownloadedTransactionAttachments.Failure.unavailable
                    }
                    try await PropertyManagementReportSystemDelivery.handoff(url, action: .share)
                }
                return
            }
            #if os(iOS)
            if save { try await DownloadedImagePhotoSaving.save(bytes); return }
            #elseif os(macOS)
            if save {
                guard let destination, destination.isFileURL else {
                    throw PropertyManagementReportSystemDelivery.Failure.unavailablePresenter
                }
                try await PropertyManagementReportSystemDelivery.saveImage(bytes, to: destination)
                return
            }
            #endif
            try await PropertyManagementReportSystemDelivery.handoffImage(bytes)
        })
    }

    private struct ExportMessage: LocalizedError {
        let errorDescription: String?
    }

    private func exportFailureMessage(_ error: Error) -> String {
        if let failure = error as? Clipboard.ImageFailure { return failure.localizedDescription }
        if let failure = error as? ReportScratchFailure {
            #if DEBUG
            // Error cases contain operation/errno only, never attachment bytes or paths.
            return "The temporary attachment file could not be prepared securely. Diagnostic: \(failure)"
            #else
            return "The temporary attachment file could not be prepared securely. Please try again."
            #endif
        }
        if let failure = error as? PropertyManagementReportSystemDelivery.Failure {
            return failure.localizedDescription
        }
        if let failure = error as? AuthorizedMediaExport.Failure {
            switch failure {
            case .alreadyExporting: return "Finish the current attachment export first."
            case .missingBytes: return "This attachment is not downloaded. Reconnect and try again."
            case .unavailable: return "The attachment or your access changed. Reopen it and try again."
            }
        }
        if let failure = error as? DownloadedTransactionAttachments.Failure {
            return failure == .unavailable ? "The attachment or your access changed. Reopen it and try again."
                : "The downloaded attachment did not match its saved reference. Reconnect and try again."
        }
        #if os(iOS)
        if let permission = error as? DownloadedImagePhotoSaving.Failure {
            return permission.localizedDescription
        }
        #endif
        return "The attachment could not be exported. Its data or your access may have changed. Reconnect and try again."
    }

    private func photo(_ catalog: DownloadedTransactionAttachments, attachment: DownloadedTransactionAttachment,
        thumbnail: Bool, scale: Binding<CGFloat>, onTap: (() -> Void)? = nil) -> some View {
        DownloadedMediaPhotoView(identity: identity(catalog, attachment), load: {
            try await reader.loadDownloadedTransactionAttachment(catalog: catalog, attachment: attachment, allowDownload: true)
        }, thumbnail: thumbnail, onTap: onTap, scale: scale)
        .id(identity(catalog, attachment))
    }
}

struct TransactionPinnedAttachment: Identifiable {
    let id = UUID()
    let catalog: DownloadedTransactionAttachments
    let attachment: DownloadedTransactionAttachment
}

private func transactionAttachmentIdentity(_ catalog: DownloadedTransactionAttachments,
    _ attachment: DownloadedTransactionAttachment) -> AnyHashable {
    AnyHashable([catalog.scope.accountId.rawValue, catalog.scope.ownerKind.rawValue,
        catalog.scope.projectId?.rawValue ?? "", catalog.scope.clientId?.rawValue ?? "",
        catalog.transactionId.rawValue, catalog.section.rawValue, String(catalog.revision ?? 0),
        attachment.id.rawValue, attachment.object.storagePath].map { Data($0.utf8) })
}

/// View-local selected reference; no backend pin record or second media store.
struct TransactionPinnedAttachmentView: View {
    let pin: TransactionPinnedAttachment
    let reader: any DownloadedTransactionAttachmentReading
    let onClose: () -> Void
    @State private var catalog: DownloadedTransactionAttachments?
    @State private var selected: EntityID?
    @State private var zoom: CGFloat = 1
    @State private var generation = UUID()

    var body: some View {
        ZStack {
            if let catalog {
                let images = catalog.attachments.filter { $0.object.mediaType.hasPrefix("image/") }
                if pin.attachment.object.mediaType == "application/pdf",
                   let attachment = catalog.attachments.first(where: { $0.id == pin.attachment.id }) {
                    PinnedImagePresentation(imageCount: 1, currentIndex: .constant(0),
                        zoomScale: $zoom, onClose: onClose, onChangeImage: { _ in },
                        accessibilityPrefix: "target-transaction-pinned") {
                            TransactionAttachmentPDFContent(catalog: catalog, attachment: attachment, reader: reader)
                        } actions: { EmptyView() }
                } else if let index = images.firstIndex(where: { $0.id == (selected ?? pin.attachment.id) }) {
                    let attachment = images[index]
                    PinnedImagePresentation(imageCount: images.count,
                        currentIndex: Binding(get: { index }, set: { selected = images[$0].id }),
                        zoomScale: $zoom, onClose: onClose, onChangeImage: { selected = images[$0].id },
                        accessibilityPrefix: "target-transaction-pinned", allowsSwipePaging: true) {
                            DownloadedMediaPhotoView(identity: transactionAttachmentIdentity(catalog, attachment),
                                load: { try await reader.loadDownloadedTransactionAttachment(catalog: catalog,
                                    attachment: attachment, allowDownload: true) }, scale: $zoom)
                                .id(transactionAttachmentIdentity(catalog, attachment))
                        } actions: { EmptyView() }
                }
            } else { ProgressView("Loading pinned image…") }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("target-transaction-pinned-panel")
        .task(id: pin.id) {
            let request = UUID()
            generation = request; catalog = nil; selected = pin.attachment.id; zoom = 1
            var previous = pin.catalog
            var anchor = pin.attachment
            do {
                for try await value in reader.watchDownloadedTransactionAttachments(scope: pin.catalog.scope,
                    transactionId: pin.catalog.transactionId, section: pin.catalog.section) {
                    try Task.checkCancellation()
                    guard generation == request else { return }
                    guard let value else { break }
                    if let published = value.publishedReplacement(for: anchor, from: previous) {
                        anchor = published
                    } else if !value.retains(anchor, from: previous) { break }
                    guard let oldSelection = previous.attachments.first(where: { $0.id == selected }),
                          value.attachments.contains(where: {
                              $0.id == oldSelection.id && $0.object == oldSelection.object
                          }) else { break }
                    catalog = value
                    previous = value
                }
            } catch { }
            guard generation == request else { return }
            catalog = nil; onClose()
        }
        .onDisappear { generation = UUID(); catalog = nil; zoom = 1 }
    }
}

private struct TransactionAttachmentPDFView: View {
    let catalog: DownloadedTransactionAttachments
    let attachment: DownloadedTransactionAttachment
    let reader: any DownloadedTransactionAttachmentReading
    @Binding var isPresented: Bool
    let onPin: (() -> Void)?
    let onShare: (() -> Void)?
    var body: some View {
        AuthorizedPDFViewer(fileName: attachment.fileName, load: {
            try await reader.loadDownloadedTransactionAttachment(catalog: catalog,
                attachment: attachment, allowDownload: true)
        }, isPresented: $isPresented, onPin: onPin, onShare: onShare)
        .accessibilityIdentifier("target-transaction-pdf-viewer")
    }
}

/// Shared authorized-byte binding; rendering, paging and zoom remain in the original PDF viewer.
struct AuthorizedPDFViewer: View {
    let fileName: String?
    let load: @Sendable () async throws -> Data?
    @Binding var isPresented: Bool
    var onPin: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    @State private var document: PDFDocument?
    @State private var loading = true
    var body: some View {
        PDFViewerPresentation(fileName: fileName, pdfDocument: document,
            isLoading: loading, isPresented: $isPresented,
            onPinImage: document == nil ? nil : onPin, onShare: document == nil ? nil : onShare)
            .task {
                document = nil; loading = true
                do {
                    let bytes = try await load()
                    try Task.checkCancellation()
                    document = bytes.flatMap { PDFDocument(data: $0) }
                } catch { }
                if !Task.isCancelled { loading = false }
            }
            .onDisappear { document = nil }
    }
}

/// Authorized byte loading only; PDF rendering and gestures stay in PDFKit.
private struct TransactionAttachmentPDFContent: View {
    let catalog: DownloadedTransactionAttachments
    let attachment: DownloadedTransactionAttachment
    let reader: any DownloadedTransactionAttachmentReading
    @State private var document: PDFDocument?
    @State private var loading = true

    var body: some View {
        PDFDocumentPresentation(document: document, isLoading: loading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("target-transaction-pinned-pdf")
            .accessibilityValue(document.map { "\($0.pageCount) PDF pages" } ?? "PDF unavailable")
            .task {
                document = nil; loading = true
                do {
                    let bytes = try await reader.loadDownloadedTransactionAttachment(catalog: catalog,
                        attachment: attachment, allowDownload: true)
                    try Task.checkCancellation()
                    document = bytes.flatMap { PDFDocument(data: $0) }
                } catch { }
                if !Task.isCancelled { loading = false }
            }
            .onDisappear { document = nil }
    }
}
