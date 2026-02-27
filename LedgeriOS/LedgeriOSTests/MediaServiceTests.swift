import Foundation
import Testing
@testable import LedgeriOS

// MARK: - Mock Storage

private final class MockStorageUploader: StorageUploading, @unchecked Sendable {
    var uploadResult: Result<String, Error> = .success("https://example.com/image.jpg")
    var deleteResult: Result<Void, Error> = .success(())

    private(set) var lastUploadedPath: String?
    private(set) var lastUploadedData: Data?
    private(set) var lastUploadedContentType: String?
    private(set) var lastDeletedURL: String?

    func putData(_ data: Data, path: String, contentType: String) async throws -> String {
        lastUploadedPath = path
        lastUploadedData = data
        lastUploadedContentType = contentType
        return try uploadResult.get()
    }

    func delete(url: String) async throws {
        lastDeletedURL = url
        try deleteResult.get()
    }
}

// MARK: - Tests

@Suite("MediaService Tests")
@MainActor
struct MediaServiceTests {

    // MARK: - uploadPath

    @Test("uploadPath formats path correctly for all entity types")
    func uploadPathFormatsCorrectly() {
        let service = MediaService()
        let path = service.uploadPath(
            accountId: "acc1",
            entityType: "items",
            entityId: "item1",
            filename: "abc.jpg"
        )
        #expect(path == "accounts/acc1/items/item1/abc.jpg")
    }

    @Test("uploadPath handles different entity types")
    func uploadPathHandlesDifferentEntityTypes() {
        let service = MediaService()
        #expect(service.uploadPath(accountId: "a", entityType: "transactions", entityId: "t1", filename: "x.jpg")
                == "accounts/a/transactions/t1/x.jpg")
        #expect(service.uploadPath(accountId: "a", entityType: "spaces", entityId: "s1", filename: "y.jpg")
                == "accounts/a/spaces/s1/y.jpg")
    }

    @Test("uploadPath uses provided filename verbatim")
    func uploadPathUsesFilenameVerbatim() {
        let service = MediaService()
        let uuid = "550E8400-E29B-41D4-A716-446655440000"
        let path = service.uploadPath(accountId: "acct", entityType: "items", entityId: "itm", filename: "\(uuid).jpg")
        #expect(path.hasSuffix("\(uuid).jpg"))
    }

    // MARK: - uploadImage

    @Test("uploadImage returns download URL on success")
    func uploadImageReturnsURL() async throws {
        let mock = MockStorageUploader()
        mock.uploadResult = .success("https://storage.example.com/image.jpg")
        let service = MediaService(uploader: mock)

        let data = Data("fake-jpeg".utf8)
        let url = try await service.uploadImage(data, path: "accounts/acc1/items/item1/img.jpg")

        #expect(url == "https://storage.example.com/image.jpg")
        #expect(!url.isEmpty)
    }

    @Test("uploadImage passes correct path and content type to storage")
    func uploadImagePassesCorrectMetadata() async throws {
        let mock = MockStorageUploader()
        let service = MediaService(uploader: mock)

        let data = Data("jpeg-data".utf8)
        let path = "accounts/acc1/items/item1/photo.jpg"
        _ = try await service.uploadImage(data, path: path)

        #expect(mock.lastUploadedPath == path)
        #expect(mock.lastUploadedData == data)
        #expect(mock.lastUploadedContentType == "image/jpeg")
    }

    @Test("uploadImage propagates storage errors")
    func uploadImagePropagatesError() async {
        let mock = MockStorageUploader()
        let expectedError = NSError(domain: "StorageError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        mock.uploadResult = .failure(expectedError)
        let service = MediaService(uploader: mock)

        await #expect(throws: (any Error).self) {
            _ = try await service.uploadImage(Data(), path: "any/path.jpg")
        }
    }

    // MARK: - deleteImage

    @Test("deleteImage calls storage delete with correct URL")
    func deleteImageCallsStorageDelete() async throws {
        let mock = MockStorageUploader()
        let service = MediaService(uploader: mock)

        let url = "https://storage.example.com/accounts/acc1/items/i1/img.jpg"
        try await service.deleteImage(url: url)

        #expect(mock.lastDeletedURL == url)
    }

    @Test("deleteImage propagates storage errors")
    func deleteImagePropagatesError() async {
        let mock = MockStorageUploader()
        let expectedError = NSError(domain: "StorageError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Object not found"])
        mock.deleteResult = .failure(expectedError)
        let service = MediaService(uploader: mock)

        await #expect(throws: (any Error).self) {
            try await service.deleteImage(url: "https://storage.example.com/missing.jpg")
        }
    }
}
