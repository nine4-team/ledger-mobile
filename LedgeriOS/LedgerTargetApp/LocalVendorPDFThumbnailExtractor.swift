import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Conservative local evidence for the simple, unrotated Wayfair layout.
/// A missing result means unavailable/ambiguous evidence, never an empty image.
/// Geometry establishes a unique spatial association, not semantic recognition:
/// a lone logo placed exactly like a product image cannot be distinguished here.
/// Crops retain the rendered page pixels, including any overlaid page content.
enum LocalVendorPDFThumbnailExtractor {
    struct Request: Sendable {
        let id: Int
        let sku: String
    }

    struct Bounds: Equatable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ rect: CGRect) {
            x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
        }
    }

    struct Thumbnail: Equatable, Sendable {
        let sourceRowID: Int
        let pageNumber: Int
        let anchorUTF16Location: Int
        let anchorUTF16Length: Int
        let anchorBounds: Bounds
        let bounds: Bounds
        let pngBytes: Data
    }

    private struct Anchor {
        let rowID: Int
        let pageIndex: Int
        let range: NSRange
        let bounds: CGRect
    }

    private final class ScanState {
        var transform = CGAffineTransform.identity
        var stack: [CGAffineTransform] = []
        var images: [CGRect] = []
        var unsupported = false
    }

    static func extract(from bytes: Data, rows: [Request]) -> [Int: Thumbnail] {
        guard !rows.isEmpty, Set(rows.map(\.id)).count == rows.count,
              let document = PDFDocument(data: bytes), document.pageCount <= 100 else { return [:] }
        let skuCounts = Dictionary(grouping: rows, by: { $0.sku.lowercased() }).mapValues(\.count)
        var anchors: [Anchor] = []
        var allAnchors: [Anchor] = []
        for row in rows {
            guard !row.sku.isEmpty, row.sku.utf16.count <= 128 else { continue }
            var occurrences: [Anchor] = []
            var occurrenceCount = 0
            let pattern = "(?<![A-Za-z0-9-])" + NSRegularExpression.escapedPattern(for: row.sku)
                + "(?![A-Za-z0-9-])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex), let string = page.string else { continue }
                for match in regex.matches(in: string, range: NSRange(location: 0, length: string.utf16.count)) {
                    occurrenceCount += 1
                    guard let selection = page.selection(for: match.range) else { continue }
                    occurrences.append(Anchor(rowID: row.id, pageIndex: pageIndex,
                        range: match.range, bounds: selection.bounds(for: page)))
                }
            }
            allAnchors.append(contentsOf: occurrences)
            if occurrenceCount == 1, occurrences.count == 1, skuCounts[row.sku.lowercased()] == 1 {
                anchors.append(occurrences[0])
            }
        }

        var results: [Int: Thumbnail] = [:]
        for pageIndex in Set(anchors.map(\.pageIndex)).sorted() {
            guard let page = document.page(at: pageIndex), page.rotation == 0,
                  let reference = page.pageRef else { continue }
            let pageBounds = page.bounds(for: .mediaBox)
            // Bound raster memory and reject coordinate systems not covered by fixtures.
            guard pageBounds.origin == .zero, page.bounds(for: .cropBox) == pageBounds,
                  pageBounds.width > 0, pageBounds.height > 0,
                  pageBounds.width <= 1500, pageBounds.height <= 1500,
                  let images = placements(reference), !images.isEmpty else { continue }
            let candidates = images.filter { box in
                pageBounds.contains(box) && box.width >= 15 && box.height >= 15
                    && box.width <= 180 && box.height <= 180 && box.minX <= 220
                    && max(box.width, box.height) / min(box.width, box.height) <= 2.3
            }
            let pageAnchors = anchors.filter { $0.pageIndex == pageIndex }
            let competingAnchors = allAnchors.filter { $0.pageIndex == pageIndex }
            func matches(_ anchor: Anchor, _ box: CGRect) -> Bool {
                anchor.bounds.width > 0 && anchor.bounds.height > 0
                    && box.maxX <= anchor.bounds.minX
                    && anchor.bounds.minX - box.maxX <= 100
                    && anchor.bounds.midY >= box.minY && anchor.bounds.midY <= box.maxY
            }
            let pairs = pageAnchors.compactMap { anchor -> (Anchor, CGRect)? in
                let matching = candidates.filter { matches(anchor, $0) }
                guard matching.count == 1, let box = matching.first,
                      competingAnchors.filter({ matches($0, box) }).count == 1,
                      // A crop overlapping another image is composite/ambiguous evidence.
                      images.filter({ $0.intersects(box) }).count == 1 else { return nil }
                return (anchor, box)
            }
            guard !pairs.isEmpty, let rendered = render(page, bounds: pageBounds) else { continue }
            for (anchor, box) in pairs {
                let crop = CGRect(x: box.minX * 2, y: (pageBounds.height - box.maxY) * 2,
                                  width: box.width * 2, height: box.height * 2).integral
                guard let image = rendered.cropping(to: crop), let png = encode(image), !png.isEmpty else { continue }
                results[anchor.rowID] = Thumbnail(sourceRowID: anchor.rowID, pageNumber: pageIndex + 1,
                    anchorUTF16Location: anchor.range.location, anchorUTF16Length: anchor.range.length,
                    anchorBounds: Bounds(anchor.bounds), bounds: Bounds(box), pngBytes: png)
            }
        }
        return results
    }

    private static func state(_ info: UnsafeMutableRawPointer?) -> ScanState {
        Unmanaged<ScanState>.fromOpaque(info!).takeUnretainedValue()
    }

    private static func placements(_ page: CGPDFPage) -> [CGRect]? {
        guard let table = CGPDFOperatorTableCreate() else { return nil }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let value = LocalVendorPDFThumbnailExtractor.state(info)
            guard value.stack.count < 64 else { value.unsupported = true; return }
            value.stack.append(value.transform)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let value = LocalVendorPDFThumbnailExtractor.state(info)
            guard let transform = value.stack.popLast() else { value.unsupported = true; return }
            value.transform = transform
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let value = LocalVendorPDFThumbnailExtractor.state(info)
            var values = [CGPDFReal](repeating: 0, count: 6)
            for index in (0..<6).reversed() {
                guard CGPDFScannerPopNumber(scanner, &values[index]) else { value.unsupported = true; return }
            }
            guard values.allSatisfy(\.isFinite), values[0] > 0, values[3] > 0,
                  values[1] == 0, values[2] == 0 else { value.unsupported = true; return }
            value.transform = CGAffineTransform(a: values[0], b: values[1], c: values[2],
                d: values[3], tx: values[4], ty: values[5]).concatenating(value.transform)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let value = LocalVendorPDFThumbnailExtractor.state(info)
            var name: UnsafePointer<CChar>?
            let content = CGPDFScannerGetContentStream(scanner)
            guard CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(content, "XObject", name) else {
                value.unsupported = true; return
            }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream) else { value.unsupported = true; return }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype,
                  String(cString: subtype) == "Image", value.images.count < 500 else {
                value.unsupported = true; return
            }
            let box = CGRect(x: 0, y: 0, width: 1, height: 1).applying(value.transform)
            guard [box.minX, box.minY, box.width, box.height].allSatisfy(\.isFinite) else {
                value.unsupported = true; return
            }
            value.images.append(box)
        }
        // Forms, clipping, inline images and custom graphics state can change the
        // visible pixels or their bounds. Skip the entire page when encountered.
        for operation in ["W", "W*", "BI", "ID", "EI", "gs", "Tr"] {
            CGPDFOperatorTableSetCallback(table, operation) { _, info in
                LocalVendorPDFThumbnailExtractor.state(info).unsupported = true
            }
        }
        let value = ScanState()
        let content = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(value).toOpaque())
        guard CGPDFScannerScan(scanner), !value.unsupported, value.stack.isEmpty else { return nil }
        return value.images
    }

    private static func render(_ page: PDFPage, bounds: CGRect) -> CGImage? {
        let width = Int(ceil(bounds.width * 2)), height = Int(ceil(bounds.height * 2))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: 2, y: 2)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private static func encode(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
