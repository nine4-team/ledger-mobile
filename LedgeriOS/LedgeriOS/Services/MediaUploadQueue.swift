import Foundation
import FirebaseFirestore

// MARK: - Upload Metadata

struct UploadMetadata: Codable, Identifiable {
    let id: String
    let accountId: String
    let entityType: String          // "items", "projects", "spaces"
    let entityId: String
    let storagePath: String
    let contentType: String         // "image/jpeg", "image/png"
    let updateType: UpdateType
    let fileName: String?
    var thumbnailStoragePathSm: String?
    var thumbnailStoragePathMd: String?
    let createdAt: Date
    var attemptCount: Int
    var lastError: String?

    enum UpdateType: Codable {
        case setField(String)                                       // e.g. "mainImageUrl"
        case appendToArray(field: String, kind: String, isPrimary: Bool)  // appends to array field
    }

    /// File extension derived from content type, used for local file storage.
    var fileExtension: String {
        switch contentType {
        case "image/png": "png"
        case "image/jpeg": "jpg"
        case "image/heic": "heic"
        case "image/heif": "heif"
        case "application/pdf": "pdf"
        default: "dat"
        }
    }

    init(
        accountId: String,
        entityType: String,
        entityId: String,
        storagePath: String,
        contentType: String = "image/jpeg",
        updateType: UpdateType,
        fileName: String? = nil
    ) {
        self.id = UUID().uuidString
        self.accountId = accountId
        self.entityType = entityType
        self.entityId = entityId
        self.storagePath = storagePath
        self.contentType = contentType
        self.updateType = updateType
        self.fileName = fileName
        self.createdAt = Date()
        self.attemptCount = 0
        self.lastError = nil
    }
}

// MARK: - MediaUploadQueue

/// Persistent image upload queue backed by the file system.
/// Survives app restarts — images are saved to disk immediately on enqueue,
/// then uploaded and written back to Firestore when the queue is processed.
@MainActor
@Observable
final class MediaUploadQueue {
    private(set) var pendingCount: Int = 0
    private(set) var failedCount: Int = 0
    private(set) var failedUploads: [UploadMetadata] = []
    private(set) var isProcessing: Bool = false

    private let mediaService: MediaService
    private let maxAttempts = 10

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PendingUploads", isDirectory: true)
    }

    init(mediaService: MediaService) {
        self.mediaService = mediaService
        ensureDirectory()
        refreshCounts()
    }

    // MARK: - Enqueue

    /// Saves image data and metadata to disk. Returns the upload ID for local display.
    @discardableResult
    func enqueue(imageData: Data, metadata: UploadMetadata) -> String {
        let imageURL = Self.directory.appendingPathComponent("\(metadata.id).\(metadata.fileExtension)")
        let metaURL = Self.directory.appendingPathComponent("\(metadata.id).json")

        do {
            try imageData.write(to: imageURL, options: .atomic)
            try Self.encode(metadata).write(to: metaURL, options: .atomic)
            refreshCounts()
        } catch {
            print("[MediaUploadQueue] Failed to enqueue \(metadata.id): \(error.localizedDescription)")
        }

        return metadata.id
    }

    // MARK: - Process Queue

    /// Uploads all pending images and writes URLs back to Firestore.
    /// Call on app launch and when connectivity is restored.
    func processQueue() {
        guard !isProcessing else { return }
        isProcessing = true

        Task {
            defer {
                isProcessing = false
                refreshCounts()
            }

            let entries = loadEntries(where: { $0.attemptCount < maxAttempts })
            for entry in entries {
                await processEntry(entry)
            }
        }
    }

    /// Resets failed entries and reprocesses the queue.
    func retryFailed() {
        for var entry in loadEntries(where: { $0.attemptCount >= maxAttempts }) {
            entry.attemptCount = 0
            entry.lastError = nil
            saveMetadata(entry)
        }
        refreshCounts()
        processQueue()
    }

    func retryFailedUpload(id: String) {
        guard var entry = loadEntries(where: { $0.id == id && $0.attemptCount >= maxAttempts }).first else { return }
        entry.attemptCount = 0
        entry.lastError = nil
        saveMetadata(entry)
        refreshCounts()
        processQueue()
    }

    /// Removes a failed queue entry after the user has reviewed it.
    /// The local source is removed from the queue; successfully uploaded files
    /// are cleaned up automatically when a missing destination is detected.
    func removeFailedUpload(id: String) {
        guard let entry = loadEntries(where: { $0.id == id }).first else { return }
        removeFiles(for: entry)
        refreshCounts()
    }

    // MARK: - Local Image Access

    /// Returns a local file URL for an image that hasn't uploaded yet,
    /// allowing `FirebaseImage` to display it from disk.
    func localImageURL(for uploadId: String) -> URL? {
        for ext in ["jpg", "jpeg", "png", "heic", "heif", "dat", "pdf"] {
            let url = Self.directory.appendingPathComponent("\(uploadId).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Returns all pending upload IDs for a given entity, so callers can
    /// show local images before upload completes.
    func pendingUploadIds(entityType: String, entityId: String) -> [String] {
        loadEntries(where: { $0.entityType == entityType && $0.entityId == entityId })
            .map(\.id)
    }

    // MARK: - Private: Processing

    private func processEntry(_ metadata: UploadMetadata) async {
        guard let imageURL = localImageURL(for: metadata.id),
              let imageData = try? Data(contentsOf: imageURL) else {
            removeFiles(for: metadata)
            return
        }

        // A queued upload can outlive a draft/entity that was deleted. Treat
        // that as a terminal orphan instead of retrying forever.
        do {
            guard try await destinationExists(for: metadata) else {
                removeFiles(for: metadata)
                return
            }
        } catch {
            await recordFailure(error, for: metadata)
            return
        }

        var meta = metadata
        meta.attemptCount += 1
        meta.lastError = nil
        saveMetadata(meta)

        var uploadedOriginalURL: String?
        var uploadedThumbnailURLs: (String?, String?) = (nil, nil)
        do {
            // Upload the full-size image
            let url = try await mediaService.uploadData(imageData, path: meta.storagePath, contentType: meta.contentType)
            uploadedOriginalURL = url

            // Generate and upload thumbnails (failures don't block the primary upload)
            let thumbUrls = await uploadThumbnails(sourceData: imageData, metadata: meta)
            uploadedThumbnailURLs = (thumbUrls.sm, thumbUrls.md)

            try await writeBackURL(url, thumbnailUrlSm: thumbUrls.sm, thumbnailUrlMd: thumbUrls.md, metadata: meta)
            removeFiles(for: meta)
        } catch {
            // The entity may have been deleted after the preflight check. If
            // so, remove the uploaded objects and terminate the queue entry.
            if let exists = try? await destinationExists(for: meta), !exists {
                await deleteUploadedObjects(
                    originalURL: uploadedOriginalURL,
                    thumbnailURLs: uploadedThumbnailURLs
                )
                removeFiles(for: meta)
            } else {
                meta.lastError = error.localizedDescription
                saveMetadata(meta)
                print("[MediaUploadQueue] Failed \(meta.id) (attempt \(meta.attemptCount)): \(error.localizedDescription)")
            }
        }

        refreshCounts()
    }

    private func destinationExists(for metadata: UploadMetadata) async throws -> Bool {
        let ref = Firestore.firestore()
            .collection("accounts/\(metadata.accountId)/\(metadata.entityType)")
            .document(metadata.entityId)
        return try await ref.getDocument().exists
    }

    private func recordFailure(_ error: Error, for metadata: UploadMetadata) async {
        var meta = metadata
        meta.attemptCount += 1
        meta.lastError = error.localizedDescription
        saveMetadata(meta)
        print("[MediaUploadQueue] Failed \(meta.id) (attempt \(meta.attemptCount)): \(error.localizedDescription)")
        refreshCounts()
    }

    private func deleteUploadedObjects(
        originalURL: String?,
        thumbnailURLs: (String?, String?)
    ) async {
        for url in [originalURL, thumbnailURLs.0, thumbnailURLs.1].compactMap({ $0 }) {
            try? await mediaService.deleteImage(url: url)
        }
    }

    /// Generates sm and md thumbnails from source data and uploads them.
    /// Returns the download URLs for each size, or nil if generation/upload fails.
    private func uploadThumbnails(sourceData: Data, metadata: UploadMetadata) async -> (sm: String?, md: String?) {
        let isImage = metadata.contentType.hasPrefix("image/")
        guard isImage else { return (nil, nil) }

        return await mediaService.uploadThumbnails(
            for: sourceData,
            originalPath: metadata.storagePath,
            contentType: metadata.contentType
        )
    }

    private func writeBackURL(
        _ url: String,
        thumbnailUrlSm: String? = nil,
        thumbnailUrlMd: String? = nil,
        metadata: UploadMetadata
    ) async throws {
        let db = Firestore.firestore()
        let docRef = db.collection("accounts/\(metadata.accountId)/\(metadata.entityType)")
            .document(metadata.entityId)

        switch metadata.updateType {
        case .setField(let fieldName):
            var updates: [String: Any] = [fieldName: url]
            // Derive thumb field names: "mainImageUrl" → "mainImageThumbUrlSm"/"mainImageThumbUrlMd"
            let baseField = fieldName.hasSuffix("Url") ? String(fieldName.dropLast(3)) : fieldName
            if let smUrl = thumbnailUrlSm {
                updates[baseField + "ThumbUrlSm"] = smUrl
            }
            if let mdUrl = thumbnailUrlMd {
                updates[baseField + "ThumbUrlMd"] = mdUrl
            }
            try await docRef.updateData(updates)

        case .appendToArray(let field, let kind, let isPrimary):
            var entry: [String: Any] = ["url": url, "kind": kind]
            if isPrimary { entry["isPrimary"] = true }
            if let fileName = metadata.fileName { entry["fileName"] = fileName }
            entry["contentType"] = metadata.contentType
            if let smUrl = thumbnailUrlSm { entry["thumbnailUrlSm"] = smUrl }
            if let mdUrl = thumbnailUrlMd { entry["thumbnailUrlMd"] = mdUrl }
            nonisolated(unsafe) let transactionEntry = entry
            nonisolated(unsafe) let updateBlock: (FirebaseFirestore.Transaction, NSErrorPointer) -> Any? = { transaction, errorPointer in
                do {
                    let snapshot = try transaction.getDocument(docRef)
                    let existing = snapshot.data()?[field] as? [[String: Any]] ?? []
                    let normalized = AttachmentPrimaryPolicy.normalizedDictionaries(existing + [transactionEntry])
                    transaction.updateData([field: normalized], forDocument: docRef)
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            _ = try await db.runTransaction(updateBlock)
        }
    }

    // MARK: - Private: File System

    private func loadEntries(where predicate: (UploadMetadata) -> Bool) -> [UploadMetadata] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.directory, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? Self.decode(data)
            }
            .filter(predicate)
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func refreshCounts() {
        let entries = loadEntries(where: { _ in true })
        pendingCount = entries.filter { $0.attemptCount < maxAttempts }.count
        failedUploads = entries.filter { $0.attemptCount >= maxAttempts }
        failedCount = failedUploads.count
    }

    private func removeFiles(for metadata: UploadMetadata) {
        if let imageURL = localImageURL(for: metadata.id) {
            try? FileManager.default.removeItem(at: imageURL)
        }
        try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent("\(metadata.id).json"))
    }

    private func saveMetadata(_ metadata: UploadMetadata) {
        let metaURL = Self.directory.appendingPathComponent("\(metadata.id).json")
        if let data = try? Self.encode(metadata) {
            try? data.write(to: metaURL, options: .atomic)
        }
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
    }

    // MARK: - Codable Helpers

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func encode(_ metadata: UploadMetadata) throws -> Data {
        try encoder.encode(metadata)
    }

    private static func decode(_ data: Data) throws -> UploadMetadata {
        try decoder.decode(UploadMetadata.self, from: data)
    }
}
