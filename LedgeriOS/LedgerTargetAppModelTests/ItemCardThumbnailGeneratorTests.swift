import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import Testing
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

@Suite("Verified Item card thumbnail producer")
struct ItemCardThumbnailGeneratorTests {
    #if canImport(ImageIO)
    @Test("Native UI's tiny GIF original generates an actual JPEG card")
    func nativeGalleryFixture() throws {
        let bytes = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        let hash = try AttachmentContentSHA256.make(bytes: bytes).rawValue
        let original = try DownloadedImageObjectReference(accountId: .init(validating: "account"),
            attachmentId: "original",sha256: hash,byteCount: String(bytes.count),mediaType: "image/gif",
            storagePath: "accounts/account/attachments/original/\(hash)")
        let result = try ItemCardThumbnailGenerator.generate(originalBytes: bytes,expectedOriginal: original)
        #expect(result.width == 1 && result.height == 1 && result.mediaType == "image/jpeg")
        #expect(try decoded(result.bytes).width == 1)
    }

    @Test("Actual encoded derivative carries exact publication evidence without changing source")
    func publicationEvidence() throws {
        let source = try fixture(width: 1600,height: 800)
        let unchanged = source
        let original = try reference(source)
        let generated = try ItemCardThumbnailGenerator.generate(originalBytes: source,expectedOriginal: original)
        #expect(generated.original == original)
        #expect(generated.recipe == "item-card-300-jpeg-v1")
        #expect(generated.mediaType == "image/jpeg")
        #expect(generated.width == 300 && generated.height == 150)
        #expect(generated.byteCount == Int64(generated.bytes.count))
        #expect(try AttachmentContentSHA256.make(bytes: generated.bytes) == generated.contentSHA256)
        #expect(source == unchanged)
        #expect(try AttachmentContentSHA256.make(bytes: source) == original.contentSHA256)
        let decoded = try decoded(generated.bytes)
        #expect(decoded.width == generated.width && decoded.height == generated.height)
        let imageSource = try #require(CGImageSourceCreateWithData(generated.bytes as CFData,nil))
        #expect(CGImageSourceGetType(imageSource) as String? == "public.jpeg")
    }

    @Test("Small images are encoded without upscaling",arguments: [(80,40),(300,150),(1,1)])
    func noUpscale(dimensions: (Int,Int)) throws {
        let source = try fixture(width: dimensions.0,height: dimensions.1)
        let result = try ItemCardThumbnailGenerator.generate(originalBytes: source,expectedOriginal: reference(source))
        #expect(result.width == dimensions.0 && result.height == dimensions.1)
        #expect(try decoded(result.bytes).width == dimensions.0)
    }

    @Test("EXIF orientation rotates actual JPEG pixels before sizing")
    func rotation() throws {
        let source = try fixture(width: 600,height: 300,orientation: 6)
        let result = try ItemCardThumbnailGenerator.generate(originalBytes: source,expectedOriginal: reference(source))
        #expect(result.width == 150 && result.height == 300)
        let output = try decoded(result.bytes)
        #expect(output.width == 150 && output.height == 300)
        let imageSource = try #require(CGImageSourceCreateWithData(result.bytes as CFData,nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource,0,nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test("Mirrored orientation is baked into pixels, not merely a swapped dimension")
    func mirroring() throws {
        let source = try fixture(width: 120,height: 60,orientation: 2)
        let result = try ItemCardThumbnailGenerator.generate(originalBytes: source,expectedOriginal: reference(source))
        let output = try decoded(result.bytes)
        let left = try sample(output,x: 10,y: 20), right = try sample(output,x: 100,y: 20)
        #expect(left.blue > 200 && left.red < 40)
        #expect(right.red > 200 && right.blue < 40)
    }

    @Test("Corrupt and truncated encoded source is rejected even when hash and length match",arguments: [false,true])
    func corrupt(truncated: Bool) throws {
        let jpeg = try fixture(width: 600,height: 300)
        let bytes = truncated ? Data(jpeg.prefix(jpeg.count/2)) : Data("not image bytes".utf8)
        #expect(throws: ItemCardThumbnailGenerationFailure.invalidImage) {
            try ItemCardThumbnailGenerator.generate(originalBytes: bytes,expectedOriginal: reference(bytes))
        }
    }

    private func fixture(width: Int,height: Int,orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(data: nil,width: width,height: height,bitsPerComponent: 8,
            bytesPerRow: width*4,space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(CGColor(red: 1,green: 0,blue: 0,alpha: 1))
        context.fill(CGRect(x: 0,y: 0,width: width,height: height))
        context.setFillColor(CGColor(red: 0,green: 0,blue: 1,alpha: 1))
        context.fill(CGRect(x: width/2,y: 0,width: width-width/2,height: height))
        let image = try #require(context.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes as CFMutableData,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality: 1.0,
            kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    private func decoded(_ bytes: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData,nil))
        return try #require(CGImageSourceCreateImageAtIndex(source,0,nil))
    }

    private func sample(_ image: CGImage,x: Int,y: Int) throws -> (red: UInt8,blue: UInt8) {
        var pixels = [UInt8](repeating: 0,count: image.width*image.height*4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress,width: image.width,height: image.height,
                bitsPerComponent: 8,bytesPerRow: image.width*4,space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image,in: CGRect(x: 0,y: 0,width: image.width,height: image.height))
        }
        let offset = (y*image.width+x)*4
        return (pixels[offset],pixels[offset+2])
    }
    #else
    @Test("Unsupported platform explicitly rejects generation")
    func unsupportedPlatform() throws {
        let bytes = Data([1,2,3])
        #expect(throws: ItemCardThumbnailGenerationFailure.unsupportedPlatform) {
            try ItemCardThumbnailGenerator.generate(originalBytes: bytes,expectedOriginal: reference(bytes))
        }
    }
    #endif

    @Test("Original hash and length must match independently",arguments: [false,true])
    func originalIdentity(wrongLength: Bool) throws {
        let bytes = Data([1,2,3])
        let expected = try reference(bytes,count: wrongLength ? 4 : 3,
            hash: wrongLength ? nil : String(repeating: "0",count: 64))
        #expect(throws: ItemCardThumbnailGenerationFailure.sourceMismatch) {
            try ItemCardThumbnailGenerator.generate(originalBytes: bytes,expectedOriginal: expected)
        }
    }

    @Test("Encoded source ceiling matches existing image download limit before decode",arguments: [false,true])
    func sourceLimit(actual: Bool) throws {
        #expect(ItemCardThumbnailGenerator.maximumSourceBytes == 64*1024*1024)
        let over = Int(ItemCardThumbnailGenerator.maximumSourceBytes)+1
        let bytes = actual ? Data(repeating: 0,count: over) : Data([1])
        let expected = try reference(Data([1]),count: actual ? 1 : over)
        #expect(throws: ItemCardThumbnailGenerationFailure.sourceTooLarge) {
            try ItemCardThumbnailGenerator.generate(originalBytes: bytes,expectedOriginal: expected)
        }
    }

    private func reference(_ bytes: Data,count: Int? = nil,hash: String? = nil) throws -> DownloadedImageObjectReference {
        let digest = try hash ?? AttachmentContentSHA256.make(bytes: bytes).rawValue
        return try .init(accountId: .init(validating: "account"),attachmentId: "original",sha256: digest,
            byteCount: String(count ?? bytes.count),mediaType: "image/jpeg",
            storagePath: "accounts/account/attachments/original/\(digest)")
    }
}
