import Foundation
import LedgerTargetCore
#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import ImageIO
import UniformTypeIdentifiers
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Converts the original picker's bytes into capture input; does not accept,
/// upload, re-encode or authorize them. The runtime must persist the receipt.
public enum AttachmentCapturePreparation {
    public enum Failure: LocalizedError, Equatable, Sendable {
        case tooLarge, unsupportedOrDamagedFile, unsupportedPlatform

        public var errorDescription: String? {
            switch self {
            case .tooLarge:
                return "This attachment exceeds the 64 MB limit. Choose a smaller file."
            case .unsupportedOrDamagedFile:
                return "This file could not be added. It may be damaged or use an unsupported format. Choose another file."
            case .unsupportedPlatform:
                return "Adding attachments is not supported on this device."
            }
        }
    }

    public static func prepare(bytes: Data, fileName: String?, allowsPDF: Bool,
        attachmentId: AttachmentID, scope: AttachmentCaptureScope,
        transactionSection: TransactionAttachmentSection?, capturedAt: AttachmentEpochMilliseconds
    ) throws -> LocalAttachmentCapture {
        // Originals must fit the existing authenticated transport, not just a thumbnail.
        guard bytes.count <= ItemCardThumbnailGenerator.maximumSourceBytes else { throw Failure.tooLarge }
        let mediaType = try identify(bytes, allowsPDF: allowsPDF)
        return try LocalAttachmentCapture(attachmentId: attachmentId, scope: scope,
            capturedAt: capturedAt, bytes: bytes,
            metadata: AttachmentCaptureMetadata(mediaType: mediaType, fileName: fileName,
                transactionSection: transactionSection))
    }

    private static func identify(_ bytes: Data, allowsPDF: Bool) throws -> String {
        #if canImport(ImageIO) && canImport(UniformTypeIdentifiers) && canImport(CoreGraphics)
        if let original = try? OriginalImageSource(bytes: bytes),
           let identifier = CGImageSourceGetType(original.source) as String?,
           let type = UTType(identifier), type.conforms(to: .image),
           let mediaType = type.preferredMIMEType,
           CGImageSourceCreateThumbnailAtIndex(original.source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               // HEIC decoders can reject tiny (1–2 pixel) output even for a
               // complete valid original. Keep decoding bounded, not sub-block sized.
               kCGImageSourceThumbnailMaxPixelSize: 64,
               kCGImageSourceShouldCacheImmediately: true
           ] as CFDictionary) != nil,
           CGImageSourceGetStatusAtIndex(original.source, 0) == .statusComplete {
            return mediaType
        }
        // No extension/MIME hint can turn arbitrary data into an accepted PDF.
        // Retain password-protected originals too; attachment is not decryption.
        if allowsPDF, let provider = CGDataProvider(data: bytes as CFData),
           CGPDFDocument(provider) != nil { return "application/pdf" }
        throw Failure.unsupportedOrDamagedFile
        #else
        throw Failure.unsupportedPlatform
        #endif
    }
}
