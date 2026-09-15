import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Original MediaGallerySection capture presentation, shared by backend adapters.
/// A callback must not return successfully before its own durable acceptance.
struct MediaCapturePresentation: ViewModifier {
    @Binding var showAddSourceMenu: Bool
    @Binding var isUploading: Bool
    @Binding var uploadError: String?
    let remainingSlots: Int
    var allowedKinds: [AttachmentKind] = [.image, .pdf]
    var onUploadAttachment: ((Data) async throws -> Void)?
    var onUploadAttachmentFile: ((AttachmentUpload) async throws -> Void)?
    var onUploadDocument: ((Data, String) async throws -> Void)?
    var sourceImagesTitle = "Transaction Images"
    var onSelectSourceImages: (() -> Void)?
    var allowsImagePaste = false

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var menuPendingAction: (() -> Void)?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var showFileImporter = false

    private var canUploadImages: Bool { onUploadAttachment != nil || onUploadAttachmentFile != nil }

    private enum CaptureFailure: LocalizedError {
        case unsupportedType, busy, full
        var errorDescription: String? {
            switch self {
            case .unsupportedType: "This file type cannot be added to this section."
            case .busy: "Finish saving the current attachment first."
            case .full: "This section has reached its attachment limit."
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .adaptivePresentation(isPresented: $showAddSourceMenu, style: .quickMenu, onDismiss: {
                menuPendingAction?(); menuPendingAction = nil
            }) {
                ActionMenuSheet(title: "Add Attachment", items: addSourceMenuItems,
                    onSelectAction: { menuPendingAction = $0 })
            }
            #if canImport(UIKit)
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture(onCapture: { _ in }, onDismiss: { showCamera = false },
                    isCaptureEnabled: remainingSlots > 0 && !isUploading,
                    captureDisabledMessage: remainingSlots == 0 ? "Attachment limit reached" : nil,
                    onCaptureAccepted: { data in
                        guard remainingSlots > 0 else { throw CaptureFailure.full }
                        guard !isUploading else { throw CaptureFailure.busy }
                        isUploading = true; uploadError = nil
                        defer { isUploading = false }
                        do { try await uploadImage(.image(data: data)) }
                        catch { report(error); throw error }
                    })
            }
            .fullScreenCover(isPresented: $showDocumentPicker) {
                DocumentPicker { data, fileName in
                    Task { await captureBatch { await handlePickedDocumentData(data, fileName: fileName) } }
                } onDismiss: { showDocumentPicker = false }
                  onFailure: { report($0) }
            }
            #endif
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItems,
                maxSelectionCount: remainingSlots, matching: .images,
                preferredItemEncoding: .current, photoLibrary: .shared())
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await captureBatch { for item in newItems { await handlePickedItem(item) } }
                    pickerItems = []
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: allowedFileImportTypes,
                allowsMultipleSelection: remainingSlots > 1) { result in
                Task {
                    await captureBatch {
                        do { await handleFileURLs(try result.get()) }
                        catch is CancellationError { }
                        catch let error as CocoaError where error.code == .userCancelled { }
                        catch { report(error) }
                    }
                }
            }
            #if os(macOS)
            .onDrop(of: acceptedDropTypeIdentifiers, isTargeted: nil) { providers in
                guard remainingSlots > 0, !isUploading else { return false }
                Task { await captureBatch { await handleDroppedItemProviders(providers) } }
                return true
            }
            #else
            .dropDestination(for: URL.self) { urls, _ in
                guard remainingSlots > 0, !isUploading else { return false }
                Task { await captureBatch { await handleFileURLs(urls) } }
                return true
            } isTargeted: { _ in }
            #endif
    }

    /// One source selection owns the busy state until every selected file has
    /// finished. Later successes must not erase an earlier failure in the batch.
    private func captureBatch(_ action: () async -> Void) async {
        guard !isUploading else { report(CaptureFailure.busy); return }
        isUploading = true; uploadError = nil
        defer { isUploading = false }
        await action()
    }

    private func report(_ error: Error) {
        if uploadError == nil { uploadError = error.localizedDescription }
    }

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw CocoaError(.fileReadUnknown)
            }
            let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) })
            await handlePickedImageUpload(.image(data: data, contentType: type))
        } catch is CancellationError { }
        catch { report(error) }
    }

    private func handlePickedImageUpload(_ upload: AttachmentUpload) async {
        do { try await uploadImage(upload) }
        catch is CancellationError { }
        catch { report(error) }
    }

    private func uploadImage(_ upload: AttachmentUpload) async throws {
        guard canUploadImages else { throw CaptureFailure.unsupportedType }
        if let onUploadAttachmentFile { try await onUploadAttachmentFile(upload) }
        else { try await onUploadAttachment?(upload.data) }
    }

    private func handlePickedDocumentData(_ data: Data, fileName: String) async {
        guard let onUploadDocument else { return }
        defer { showDocumentPicker = false }
        do { try await onUploadDocument(data, fileName) }
        catch is CancellationError { }
        catch { report(error) }
    }

    private func handleFileURLs(_ urls: [URL]) async {
        let limited = Array(urls.prefix(remainingSlots))
        for url in limited {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(forKeys: [.contentTypeKey, .localizedTypeDescriptionKey])
                guard let type = values.contentType ?? UTType(filenameExtension: url.pathExtension),
                    (type.conforms(to: .image) && allowedKinds.contains(.image) && canUploadImages)
                    || (type.conforms(to: .pdf) && allowedKinds.contains(.pdf) && onUploadDocument != nil) else {
                    throw CaptureFailure.unsupportedType
                }
                // Keep scoped access alive until the background read completes.
                let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
                if type.conforms(to: .image) {
                    await handlePickedImageUpload(.file(data: data, fileName: url.lastPathComponent, contentType: type))
                } else if type.conforms(to: .pdf), allowedKinds.contains(.pdf), onUploadDocument != nil {
                    await handlePickedDocumentData(data, fileName: url.lastPathComponent)
                }
            } catch { report(error) }
        }
    }

    private var addSourceMenuItems: [ActionMenuItem] {
        var items: [ActionMenuItem] = []
        #if canImport(UIKit)
        items.append(ActionMenuItem(id: "camera", label: "Camera", icon: "camera.fill", onPress: { showCamera = true }))
        #endif
        items.append(ActionMenuItem(id: "photo-library", label: "Photo Library", icon: "photo.on.rectangle", onPress: { showPhotoPicker = true }))
        if let onSelectSourceImages {
            items.append(ActionMenuItem(id: "source-images", label: sourceImagesTitle, icon: "photo.stack", onPress: onSelectSourceImages))
        }
        if allowsImagePaste, allowedKinds.contains(.image), canUploadImages {
            items.append(ActionMenuItem(id: "paste-image", label: "Paste Image", icon: "doc.on.clipboard", onPress: {
                guard remainingSlots > 0, !isUploading else { return }
                Task {
                    await captureBatch {
                        do {
                            let image = try Clipboard.pastedImage()
                            await handlePickedImageUpload(.image(data: image.data,
                                fileName: "Pasted Image.\(image.contentType.preferredFilenameExtension ?? "img")",
                                contentType: image.contentType))
                        } catch { report(error) }
                    }
                }
            }))
        }
        items.append(ActionMenuItem(id: "files", label: "Files", icon: "folder", onPress: { showFileImporter = true }))
        #if canImport(UIKit)
        if allowedKinds.contains(.pdf), onUploadDocument != nil {
            items.append(ActionMenuItem(id: "pdf", label: "PDF", icon: "doc.richtext", onPress: { showDocumentPicker = true }))
        }
        #endif
        return items
    }

    private var allowedFileImportTypes: [UTType] {
        var types: [UTType] = []
        if allowedKinds.contains(.image) { types.append(.image) }
        if allowedKinds.contains(.pdf), onUploadDocument != nil { types.append(.pdf) }
        return types.isEmpty ? [.data] : types
    }

    #if os(macOS)
    private var acceptedDropTypeIdentifiers: [String] {
        var types = [UTType.fileURL.identifier]
        if allowedKinds.contains(.image), canUploadImages { types.append(UTType.image.identifier) }
        if allowedKinds.contains(.pdf), onUploadDocument != nil { types.append(UTType.pdf.identifier) }
        return types
    }

    private func handleDroppedItemProviders(_ providers: [NSItemProvider]) async {
        for provider in providers.prefix(remainingSlots) {
            do {
                if let dropped = try await provider.loadAttachmentUploadIfAvailable(allowedKinds: allowedKinds) {
                    if dropped.contentType.conforms(to: .pdf), allowedKinds.contains(.pdf), onUploadDocument != nil {
                        await handlePickedDocumentData(dropped.upload.data, fileName: dropped.upload.displayFileName)
                    } else if dropped.contentType.conforms(to: .image), canUploadImages {
                        await handlePickedImageUpload(dropped.upload)
                    }
                } else if let url = try await provider.loadFileURLIfAvailable() { await handleFileURLs([url]) }
            } catch { report(error) }
        }
    }
    #endif
}

#if os(macOS)
@MainActor
private extension NSItemProvider {
    func loadFileURLIfAvailable() async throws -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { @Sendable item, error in
                if let error { continuation.resume(throwing: error) }
                else if let url = item as? URL { continuation.resume(returning: url) }
                else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else { continuation.resume(returning: nil) }
            }
        }
    }

    func loadAttachmentUploadIfAvailable(allowedKinds: [AttachmentKind]) async throws -> (upload: AttachmentUpload, contentType: UTType)? {
        let registeredTypes = registeredTypeIdentifiers.compactMap(UTType.init)
        let image = allowedKinds.contains(.image) ? registeredTypes.first(where: { $0.conforms(to: .image) }) : nil
        let pdf = allowedKinds.contains(.pdf) ? registeredTypes.first(where: { $0.conforms(to: .pdf) }) : nil
        guard let type = image ?? pdf else { return nil }
        let data: Data
        do { data = try await loadDataFromFileRepresentation(forTypeIdentifier: type.identifier) }
        catch { data = try await loadDataRepresentationAsync(forTypeIdentifier: type.identifier) }
        let fallbackName = type.conforms(to: .pdf) ? "Document" : "Screenshot"
        let trimmed = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed?.isEmpty == false ? trimmed! : fallbackName
        let fileName = URL(fileURLWithPath: baseName).pathExtension.isEmpty
            ? "\(baseName).\(type.preferredFilenameExtension ?? "dat")" : baseName
        return (.file(data: data, fileName: fileName, contentType: type), type)
    }

    private func loadDataFromFileRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: typeIdentifier) { @Sendable url, error in
                if let error { continuation.resume(throwing: error); return }
                guard let url else { continuation.resume(throwing: CocoaError(.fileReadNoSuchFile)); return }
                do { continuation.resume(returning: try Data(contentsOf: url)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func loadDataRepresentationAsync(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { @Sendable data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
    }
}
#endif
