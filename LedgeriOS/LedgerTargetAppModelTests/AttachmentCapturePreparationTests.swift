import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel
#if canImport(ImageIO) && canImport(CoreGraphics)
import ImageIO
import CoreGraphics
#endif

@Suite("Original attachment capture preparation")
struct AttachmentCapturePreparationTests {
    @Test("Capture failures explain the problem without exposing internal error names")
    func readableFailures() {
        for failure in [AttachmentCapturePreparation.Failure.tooLarge, .unsupportedOrDamagedFile, .unsupportedPlatform] {
            #expect(failure.localizedDescription == failure.errorDescription)
            #expect(!failure.localizedDescription.contains("LedgerTarget"))
            #expect(!failure.localizedDescription.contains("error 1"))
        }
        #expect(AttachmentCapturePreparation.Failure.tooLarge.localizedDescription.contains("64 MB"))
    }

    #if canImport(ImageIO) && canImport(CoreGraphics)
    @Test("Detect actual image type without re-encoding or trusting the filename", arguments: ["public.png", "public.jpeg", "public.heic"])
    func originalImages(type: String) throws {
        let bytes = try image(type: type)
        let capture = try prepare(bytes, name: "misleading.pdf")
        #expect(capture.bytes == bytes)
        let expectedType = ["public.png": "image/png", "public.jpeg": "image/jpeg", "public.heic": "image/heic"][type]
        #expect(capture.metadata?.mediaType == expectedType)
        #expect(capture.metadata?.fileName == "misleading.pdf")
        #expect(capture.metadata?.transactionSection == .receipts)
        #expect(capture.contentSHA256 == (try AttachmentContentSHA256.make(bytes: bytes)))
    }

    @Test("PDF acceptance follows the caller's permitted media kind and preserves the original")
    func pdf() throws {
        let output = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: output))
        var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        let bytes = output as Data
        let capture = try prepare(bytes, name: "Original.pdf", allowsPDF: true)
        #expect(capture.bytes == bytes)
        #expect(capture.metadata?.mediaType == "application/pdf")
        #expect(throws: AttachmentCapturePreparation.Failure.unsupportedOrDamagedFile) {
            try prepare(bytes, name: "pretend.png", allowsPDF: false)
        }
    }

    @Test("Empty, fake and incomplete files cannot become captures")
    func invalidFiles() throws {
        let jpeg = try image(type: "public.jpeg")
        for bytes in [Data(), Data("%PDF-1.7\nnot a document".utf8), Data("pretend image".utf8), Data(jpeg.dropLast(2))] {
            #expect(throws: AttachmentCapturePreparation.Failure.unsupportedOrDamagedFile) {
                try prepare(bytes, name: "image.jpg", allowsPDF: true)
            }
        }
    }

    private func image(type: String) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
    #endif

    private func prepare(_ bytes: Data, name: String, allowsPDF: Bool = false) throws -> LocalAttachmentCapture {
        try AttachmentCapturePreparation.prepare(bytes: bytes, fileName: name, allowsPDF: allowsPDF,
            attachmentId: AttachmentID(validating: "capture-file"),
            scope: AttachmentCaptureScope(environment: .targetLocal,
                principalId: PrincipalID(validating: "capture-principal"),
                accountId: AccountID(validating: "capture-account"),
                parent: .init(kind: .transaction, id: EntityID(validating: "capture-transaction"))),
            transactionSection: .receipts, capturedAt: AttachmentEpochMilliseconds(validating: 1000))
    }
}
