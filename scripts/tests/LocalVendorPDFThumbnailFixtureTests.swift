import AppKit
import CoreText
import Foundation
import ImageIO
import PDFKit

@main
struct LocalVendorPDFThumbnailFixtureTests {
    struct Failure: Error { let message: String }
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(message: message) }
    }

    static func raster(red: CGFloat, green: CGFloat, split: Bool = false) throws -> CGImage {
        guard let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8,
            bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure(message: "Raster") }
        context.setFillColor(CGColor(red: red, green: green, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        if split {
            context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 10, width: 20, height: 10))
        }
        return context.makeImage()!
    }

    static func pdf(firstImage: Bool = true, logo: Bool = false, duplicate: Bool = false,
                    clipped: Bool = false, skewed: Bool = false,
                    competingImage: Bool = false, competingAnchor: Bool = false,
                    nestedTransforms: Bool = false, split: Bool = false) throws -> Data {
        let output = NSMutableData()
        let consumer = CGDataConsumer(data: output)!
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: consumer, mediaBox: &bounds, nil)!
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        func line(_ text: String, x: CGFloat, y: CGFloat) {
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        line("Wayfair Invoice Number: 123456789", x: 36, y: 750)
        line("SKU: FIRST123", x: 140, y: 660)
        line(duplicate ? "SKU: FIRST123" : "SKU: SECOND456", x: 140, y: competingAnchor ? 680 : 460)
        if clipped { context.clip(to: CGRect(x: 0, y: 0, width: 600, height: 790)) }
        if skewed { context.concatenate(CGAffineTransform(a: 1, b: 0.1, c: 0, d: 1, tx: 0, ty: 0)) }
        if firstImage { context.draw(try raster(red: 1, green: 0, split: split), in: CGRect(x: 36, y: 640, width: 60, height: 60)) }
        if nestedTransforms {
            context.saveGState()
            context.translateBy(x: 18, y: 220)
            context.saveGState()
            context.scaleBy(x: 0.5, y: 0.5)
            context.draw(try raster(red: 0, green: 1), in: CGRect(x: 36, y: 440, width: 120, height: 120))
            context.restoreGState()
            context.restoreGState()
        } else {
            context.draw(try raster(red: 0, green: 1), in: CGRect(x: 36, y: 440, width: 60, height: 60))
        }
        if logo { context.draw(try raster(red: 1, green: 0), in: CGRect(x: 36, y: 710, width: 30, height: 30)) }
        if competingImage {
            context.draw(try raster(red: 0, green: 1), in: CGRect(x: 100, y: 650, width: 30, height: 30))
        }
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    static func dominantChannel(_ data: Data, fractionY: CGFloat = 0.5) throws -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure(message: "PNG decoding") }
        return try dominantChannel(image, fractionY: fractionY)
    }

    static func dominantChannel(_ image: CGImage, fractionY: CGFloat) throws -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let color = bitmap.colorAt(x: image.width / 2, y: Int(CGFloat(image.height) * fractionY))?.usingColorSpace(.deviceRGB)
        else { throw Failure(message: "PNG pixel") }
        if color.redComponent > 0.8 && color.greenComponent < 0.35 && color.blueComponent < 0.35 { return 0 }
        if color.greenComponent > 0.8 && color.redComponent < 0.35 && color.blueComponent < 0.35 { return 1 }
        throw Failure(message: "Expected strongly red or green image pixel: \(color.redComponent), \(color.greenComponent), \(color.blueComponent), y=\(fractionY)")
    }

    static func main() throws {
        typealias Extractor = LocalVendorPDFThumbnailExtractor
        let rows = [Extractor.Request(id: 0, sku: "FIRST123"), Extractor.Request(id: 7, sku: "SECOND456")]
        let both = Extractor.extract(from: try pdf(), rows: rows)
        try check(Set(both.keys) == [0, 7], "Both original row identities")
        try check(try dominantChannel(both[0]!.pngBytes) == 0, "First row red")
        try check(try dominantChannel(both[7]!.pngBytes) == 1, "Second row green")
        try check(both[7]!.bounds == Extractor.Bounds(CGRect(x: 36, y: 440, width: 60, height: 60)), "Actual placement")
        let text = PDFDocument(data: try pdf())!.page(at: 0)!.string! as NSString
        try check(text.substring(with: NSRange(location: both[7]!.anchorUTF16Location,
            length: both[7]!.anchorUTF16Length)) == "SECOND456", "Exact source anchor range")
        let includedIDs = [7]
        let included = includedIDs.compactMap { both[$0] }
        try check(included.count == 1 && included[0].sourceRowID == 7 && included[0].pngBytes == both[7]!.pngBytes,
            "Exclusion retains original keyed evidence")
        let missing = Extractor.extract(from: try pdf(firstImage: false, logo: true), rows: rows)
        try check(Set(missing.keys) == [7], "Missing first image/extra logo cannot shift association")
        try check(try dominantChannel(missing[7]!.pngBytes) == 1, "Missing-first second row green")
        try check(Extractor.extract(from: try pdf(duplicate: true), rows: rows).isEmpty, "Repeated source SKU is ambiguous")
        try check(Extractor.extract(from: try pdf(), rows: [.init(id: 0, sku: "FIRST123"), .init(id: 1, sku: "FIRST123")]).isEmpty,
            "Repeated requested SKU is ambiguous")
        try check(Extractor.extract(from: Data("bad PDF".utf8), rows: rows).isEmpty, "Invalid PDF")
        try check(Extractor.extract(from: try pdf(clipped: true), rows: rows).isEmpty, "Clipping unsupported")
        try check(Extractor.extract(from: try pdf(skewed: true), rows: rows).isEmpty, "Skew unsupported")
        try check(Set(Extractor.extract(from: try pdf(competingImage: true), rows: rows).keys) == [7],
            "Multiple matching images reject ambiguous row")
        try check(Extractor.extract(from: try pdf(competingAnchor: true), rows: rows).isEmpty,
            "Multiple row anchors reject shared image")
        let rotated = PDFDocument(data: try pdf())!
        rotated.page(at: 0)!.rotation = 90
        try check(Extractor.extract(from: rotated.dataRepresentation()!, rows: rows).isEmpty, "Rotation unsupported")
        let shifted = PDFDocument(data: try pdf())!
        shifted.page(at: 0)!.setBounds(CGRect(x: 10, y: 10, width: 612, height: 792), for: .mediaBox)
        try check(Extractor.extract(from: shifted.dataRepresentation()!, rows: rows).isEmpty, "Nonzero origin unsupported")
        let nested = Extractor.extract(from: try pdf(nestedTransforms: true), rows: rows)
        try check(nested[7]?.bounds == both[7]?.bounds, "Nested positive transform composition")
        try check(try dominantChannel(nested[7]!.pngBytes) == 1, "Nested transform crop pixels")
        let striped = Extractor.extract(from: try pdf(split: true), rows: rows)
        let originalStripe = try raster(red: 1, green: 0, split: true)
        for fraction: CGFloat in [0.25, 0.75] {
            try check(try dominantChannel(striped[0]!.pngBytes, fractionY: fraction)
                == dominantChannel(originalStripe, fractionY: fraction), "Crop preserves source top/bottom orientation")
        }
        print("PASS local PDF thumbnails: real image placements/colors, stable row keys, missing image/logo, duplicate SKU, corrupt/clipped/skewed/rotated PDF")
    }
}
