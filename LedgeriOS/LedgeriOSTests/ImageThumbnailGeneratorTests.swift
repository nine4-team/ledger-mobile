import Foundation
import Testing
import ImageIO
#if canImport(UIKit)
import UIKit
#endif
@testable import LedgeriOS

@Suite("ImageThumbnailGenerator Tests")
struct ImageThumbnailGeneratorTests {

    // MARK: - Test Helpers

    /// Creates a JPEG Data from a solid-color image at the given dimensions.
    private func makeTestJPEG(width: Int, height: Int, quality: CGFloat = 0.9) -> Data {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.jpegData(withCompressionQuality: quality) { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        #else
        // macOS fallback: create a CGImage and encode to JPEG
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!
        let mutableData = NSMutableData()
        let dest = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return mutableData as Data
        #endif
    }

    /// Returns the pixel dimensions of an image in Data.
    private func imageDimensions(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    // MARK: - generateThumbnailData

    @Test("Sm thumbnail is smaller than source")
    func smThumbnailSmallerThanSource() {
        let source = makeTestJPEG(width: 2000, height: 1500)
        let thumb = ImageThumbnailGenerator.generateThumbnailData(from: source, size: .sm)
        #expect(thumb != nil)
        #expect(thumb!.count < source.count)
    }

    @Test("Md thumbnail is smaller than source")
    func mdThumbnailSmallerThanSource() {
        let source = makeTestJPEG(width: 2000, height: 1500)
        let thumb = ImageThumbnailGenerator.generateThumbnailData(from: source, size: .md)
        #expect(thumb != nil)
        #expect(thumb!.count < source.count)
    }

    @Test("Sm thumbnail dimensions <= 300px")
    func smThumbnailDimensions() {
        let source = makeTestJPEG(width: 2000, height: 1500)
        let thumb = ImageThumbnailGenerator.generateThumbnailData(from: source, size: .sm)!
        let dims = imageDimensions(of: thumb)!
        #expect(dims.width <= 300)
        #expect(dims.height <= 300)
    }

    @Test("Md thumbnail dimensions <= 800px")
    func mdThumbnailDimensions() {
        let source = makeTestJPEG(width: 2000, height: 1500)
        let thumb = ImageThumbnailGenerator.generateThumbnailData(from: source, size: .md)!
        let dims = imageDimensions(of: thumb)!
        #expect(dims.width <= 800)
        #expect(dims.height <= 800)
    }

    @Test("Thumbnail preserves aspect ratio")
    func thumbnailPreservesAspectRatio() {
        let source = makeTestJPEG(width: 2000, height: 1000)  // 2:1
        let thumb = ImageThumbnailGenerator.generateThumbnailData(from: source, size: .sm)!
        let dims = imageDimensions(of: thumb)!
        // Max dimension is 300, so width=300, height=150
        #expect(dims.width == 300)
        #expect(dims.height == 150)
    }

    @Test("Returns nil for corrupt data")
    func returnsNilForCorruptData() {
        let garbage = Data("not an image".utf8)
        let result = ImageThumbnailGenerator.generateThumbnailData(from: garbage, size: .sm)
        #expect(result == nil)
    }

    @Test("Handles already-small images")
    func handlesSmallImages() {
        let source = makeTestJPEG(width: 100, height: 100)
        let thumb = ImageThumbnailGenerator.generateThumbnailData(from: source, size: .sm)
        #expect(thumb != nil)
        let dims = imageDimensions(of: thumb!)!
        #expect(dims.width <= 300)
        #expect(dims.height <= 300)
    }

    // MARK: - thumbnailPath

    @Test("Derives sm path from JPEG")
    func thumbnailPathSmJpeg() {
        let path = "accounts/x/items/y/image_0.jpg"
        let result = ImageThumbnailGenerator.thumbnailPath(for: path, size: .sm)
        #expect(result == "accounts/x/items/y/image_0_sm.jpg")
    }

    @Test("Derives md path from JPEG")
    func thumbnailPathMdJpeg() {
        let path = "accounts/x/items/y/image_0.jpg"
        let result = ImageThumbnailGenerator.thumbnailPath(for: path, size: .md)
        #expect(result == "accounts/x/items/y/image_0_md.jpg")
    }

    @Test("Derives path from PNG (outputs .jpg)")
    func thumbnailPathFromPng() {
        let path = "accounts/x/items/y/photo.png"
        let result = ImageThumbnailGenerator.thumbnailPath(for: path, size: .sm)
        #expect(result == "accounts/x/items/y/photo_sm.jpg")
    }

    // MARK: - thumbnailPaths

    @Test("Returns both sm and md paths")
    func thumbnailPathsBoth() {
        let paths = ImageThumbnailGenerator.thumbnailPaths(for: "accounts/a/items/b/hero.jpg")
        #expect(paths.sm == "accounts/a/items/b/hero_sm.jpg")
        #expect(paths.md == "accounts/a/items/b/hero_md.jpg")
    }
}
