import Foundation

public protocol ItemImageCapturing: Sendable {
    func itemImageCaptureScope(accountId: AccountID, itemId: ItemID) async throws -> AttachmentCaptureScope
    func captureItemImage(_ capture: LocalAttachmentCapture) async throws -> AttachmentLocalDurabilityReceipt
}

public enum ItemImageCaptureFailure: Error, Equatable, Sendable {
    case invalidCapture, unavailable, galleryFull, alreadyCapturing, pendingMetadataUnavailable
}

/// Admission for an existing Item. The runtime supplies a currently authorized
/// complete catalog and serializes acceptance per Item, including pending bytes.
public enum ItemImageCaptureAdmission {
    public static let maximumImages = 50

    public static func assigningPlacement(_ capture: LocalAttachmentCapture,
        catalog: DownloadedItemImageCatalog, pending: [AttachmentLocalDurabilityReceipt]
    ) throws -> LocalAttachmentCapture {
        guard capture.scope.parent.kind == .item,
              capture.scope.accountId == catalog.accountId,
              capture.scope.parent.id.rawValue == catalog.itemId.rawValue,
              let metadata = capture.metadata, metadata.transactionSection == nil,
              DownloadedMediaObjectReference.isImageMediaType(metadata.mediaType) else {
            throw ItemImageCaptureFailure.invalidCapture
        }
        guard catalog.isComplete else { throw ItemImageCaptureFailure.unavailable }
        let ownPending = pending.filter { $0.scope == capture.scope }
        for receipt in ownPending {
            guard let saved = receipt.metadata, saved.transactionSection == nil,
                  DownloadedMediaObjectReference.isImageMediaType(saved.mediaType), saved.placement != nil else {
                throw ItemImageCaptureFailure.pendingMetadataUnavailable
            }
        }
        if let published = catalog.images.first(where: { $0.object.attachmentId == capture.attachmentId }) {
            guard published.object.contentSHA256 == capture.contentSHA256,
                  UInt64(published.object.byteCount) == capture.byteCount,
                  published.object.mediaType == metadata.mediaType else {
                throw ItemImageCaptureFailure.invalidCapture
            }
        }
        let occupied = Set(catalog.images.map { $0.object.attachmentId.rawValue })
            .union(ownPending.map { $0.attachmentId.rawValue })
        guard occupied.contains(capture.attachmentId.rawValue) || occupied.count < maximumImages else {
            throw ItemImageCaptureFailure.galleryFull
        }
        let placement: AttachmentCapturePlacement
        if let existing = ownPending.first(where: { $0.attachmentId == capture.attachmentId }) {
            guard existing.capturedAt == capture.capturedAt, existing.byteCount == capture.byteCount,
                  existing.contentSHA256 == capture.contentSHA256,
                  existing.metadata?.mediaType == metadata.mediaType,
                  existing.metadata?.fileName == metadata.fileName,
                  let retained = existing.metadata?.placement,
                  metadata.placement == nil || metadata.placement == retained else {
                throw ItemImageCaptureFailure.invalidCapture
            }
            placement = retained
        } else {
            guard metadata.placement == nil else { throw ItemImageCaptureFailure.invalidCapture }
            let highest = max(catalog.images.map(\.position).max() ?? -1,
                ownPending.compactMap { $0.metadata?.placement.map { Int($0.localPosition) } }.max() ?? -1)
            guard highest < Int.max, let next = UInt32(exactly: max(occupied.count, highest + 1)) else {
                throw ItemImageCaptureFailure.invalidCapture
            }
            placement = .init(localPosition: next, makePrimaryIfEmpty: occupied.isEmpty)
        }
        return try LocalAttachmentCapture(attachmentId: capture.attachmentId, scope: capture.scope,
            capturedAt: capture.capturedAt, bytes: capture.bytes,
            metadata: AttachmentCaptureMetadata(mediaType: metadata.mediaType, fileName: metadata.fileName,
                placement: placement))
    }
}
