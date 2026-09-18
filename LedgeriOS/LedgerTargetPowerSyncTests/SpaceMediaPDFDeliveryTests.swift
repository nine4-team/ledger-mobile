import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetPowerSync

@Suite("Space PDF protected delivery")
@MainActor
struct SpaceMediaPDFDeliveryTests {
    private let bytes = Data("%PDF-1.4\nSpace fixture".utf8)
    private func catalog(revision: Int64 = 1) throws -> DownloadedSpaceMedia {
        let account = try AccountID(validating: "account")
        let hash = try AttachmentContentSHA256.make(bytes: bytes).rawValue
        let attachment = try DownloadedSpaceMedia.Attachment(id: .init(validating: "reference"),
            object: .init(accountId: account,attachmentId: "object",sha256: hash,byteCount: String(bytes.count),
                mediaType: "application/pdf",storagePath: "accounts/account/attachments/object/\(hash)",kind: .pdf),
            position: 0,isPrimary: false)
        return try .init(accountId: account,spaceId: .init(validating: "space"),scope: .businessInventory,
            revision: revision,isComplete: true,attachments: [attachment])
    }
    @Test func fileExistsOnlyDuringNativeHandoff() async throws {
        let value = try catalog(), attachment = try #require(value.attachments.first)
        var delivered: URL?
        try await SpaceMediaPDFDelivery.deliver(data: bytes,catalog: value,attachment: attachment,
            reader: SpacePDFReader(catalog: value)) { url in
                delivered = url
                let actual = try Data(contentsOf: url)
                #expect(actual == bytes)
            }
        let url = try #require(delivered)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
    @Test func changedReferenceNeverReachesHandoff() async throws {
        let value = try catalog(), attachment = try #require(value.attachments.first)
        await #expect(throws: DownloadedSpaceMedia.Failure.unavailable) {
            try await SpaceMediaPDFDelivery.deliver(data: bytes,catalog: value,attachment: attachment,
                reader: SpacePDFReader(catalog: try catalog(revision: 2))) { _ in Issue.record("Stale PDF exported") }
        }
    }
    @Test func invalidBytesNeverReachHandoff() async throws {
        let value = try catalog(), attachment = try #require(value.attachments.first)
        await #expect(throws: DownloadedSpaceMedia.Failure.invalidEvidence) {
            try await SpaceMediaPDFDelivery.deliver(data: Data("wrong".utf8),catalog: value,attachment: attachment,
                reader: SpacePDFReader(catalog: value)) { _ in Issue.record("Wrong bytes exported") }
        }
    }
}
private struct SpacePDFReader: DownloadedSpaceMediaReading {
    let catalog: DownloadedSpaceMedia
    func readDownloadedSpaceMedia(accountId: AccountID,spaceId: SpaceID,scope: SpaceCreationScope) async throws -> DownloadedSpaceMedia { catalog }
    func watchDownloadedSpaceMedia(accountId: AccountID,spaceId: SpaceID,scope: SpaceCreationScope) -> AsyncThrowingStream<DownloadedSpaceMedia?,Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func loadDownloadedSpaceMedia(catalog: DownloadedSpaceMedia,attachment: DownloadedSpaceMedia.Attachment,allowDownload: Bool) async throws -> Data? { nil }
}
