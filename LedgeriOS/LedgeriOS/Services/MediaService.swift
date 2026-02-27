import Foundation
import FirebaseStorage

// Usage in views:
// @Environment(MediaService.self) private var mediaService

// MARK: - Storage Abstraction (for testability)

protocol StorageUploading: Sendable {
    func putData(_ data: Data, path: String, contentType: String) async throws -> String
    func delete(url: String) async throws
}

/// Live implementation backed by Firebase Storage.
struct FirebaseStorageUploader: StorageUploading {
    func putData(_ data: Data, path: String, contentType: String) async throws -> String {
        let ref = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    func delete(url: String) async throws {
        let ref = Storage.storage().reference(forURL: url)
        try await ref.delete()
    }
}

// MARK: - MediaService

@MainActor
@Observable
final class MediaService {
    private let uploader: StorageUploading

    init(uploader: StorageUploading = FirebaseStorageUploader()) {
        self.uploader = uploader
    }

    // MARK: - Path Helper

    /// Returns the Firebase Storage path for an entity's attachment.
    /// Pure function — call directly in unit tests without mocking.
    func uploadPath(accountId: String, entityType: String, entityId: String, filename: String) -> String {
        "accounts/\(accountId)/\(entityType)/\(entityId)/\(filename)"
    }

    // MARK: - Upload

    /// Uploads JPEG data to Firebase Storage and returns the public download URL.
    /// - Parameters:
    ///   - data: JPEG image data (use `UIImage.jpegData(compressionQuality: 0.8)` to produce this).
    ///   - path: Storage path produced by `uploadPath(...)`.
    /// - Returns: Download URL string.
    /// - Throws: `StorageErrorCode` on upload or URL fetch failure.
    func uploadImage(_ data: Data, path: String) async throws -> String {
        try await uploader.putData(data, path: path, contentType: "image/jpeg")
    }

    // MARK: - Delete

    /// Deletes the file at the given download URL from Firebase Storage.
    /// - Parameter url: The download URL string returned by `uploadImage`.
    /// - Throws: `StorageErrorCode` if the reference cannot be resolved or the delete fails.
    func deleteImage(url: String) async throws {
        try await uploader.delete(url: url)
    }
}
