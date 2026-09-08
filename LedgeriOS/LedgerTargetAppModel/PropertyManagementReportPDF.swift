#if canImport(CoreGraphics) && canImport(CoreText)
import Foundation
import CoreGraphics
import CoreText
import LedgerTargetCore

public enum PropertyManagementReportPDFFailure: Error {
    case couldNotCreateContext, couldNotPaginate
}

/// Pure on-device renderer. CoreText flows all text across Letter-sized pages;
/// it never fetches assets or recomputes report eligibility, values or totals.
public enum PropertyManagementReportPDF {
    public static func render(_ snapshot: PropertyManagementReportSnapshot) throws -> Data {
        let text = NSMutableAttributedString(string: "")
        var blocks: [NSRange] = []
        func append(_ value: String, size: CGFloat = 11, bold: Bool = false) {
            let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
            text.append(NSAttributedString(string: value + "\n", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)
            ]))
        }
        func totals(_ value: PropertyManagementReportTotals) {
            let start = text.length
            append("Items: \(value.itemCount)")
            if let total = value.totalMarketValue {
                append("Total market value: \(PropertyManagementReportHTML.value(total))", bold: true)
            } else {
                append("Known market value subtotal: \(PropertyManagementReportHTML.value(value.knownMarketValueSubtotal))", bold: true)
                append("Unknown values: \(value.unknownMarketValueCount)")
            }
            blocks.append(NSRange(location: start, length: text.length - start))
        }
        append("PROPERTY MANAGEMENT", size: 10, bold: true)
        append(snapshot.project.name, size: 22, bold: true)
        append(snapshot.project.address ?? "Property address not provided")
        let date = Date(timeIntervalSince1970: Double(snapshot.provenance.asOf.rawValue) / 1000)
        append("As of \(ISO8601DateFormatter().string(from: date))", size: 9)
        append("")
        if snapshot.totals.itemCount == 0 { append("No data for this report") }
        for group in snapshot.groups {
            let headingStart = text.length
            append(group.name, size: 15, bold: true)
            for (index, item) in group.rows.enumerated() {
                let start = index == 0 ? headingStart : text.length
                append(item.name, bold: true)
                append("SKU: \(item.sku ?? "Not provided")")
                append("Market value: \(PropertyManagementReportHTML.value(item.marketValue))")
                append("Item ID: \(item.itemId.rawValue)", size: 8)
                append("")
                blocks.append(NSRange(location: start, length: text.length - start))
            }
            totals(group.totals)
            append("")
        }
        append("Report totals", size: 15, bold: true)
        totals(snapshot.totals)
        append("")
        append("Snapshot: \(snapshot.reference.snapshotID.rawValue)", size: 8)
        append("Source: \(snapshot.provenance.source.kind)", size: 8)
        append("Data version: \(snapshot.provenance.localDataVersion?.rawValue ?? snapshot.sourceSetHash.rawValue)", size: 8)
        append("Authority: \(snapshot.provenance.authorityVersion.rawValue)", size: 8)

        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, [
                kCGPDFContextTitle: "Property Management Report",
                kCGPDFContextSubject: snapshot.reference.snapshotHash.rawValue,
                kCGPDFContextCreator: "Ledger"
              ] as CFDictionary) else { throw PropertyManagementReportPDFFailure.couldNotCreateContext }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let bounds = CGRect(x: 42, y: 48, width: 528, height: 696)
        let path = CGPath(rect: bounds, transform: nil)
        var offset = 0
        var page = 1
        while offset < text.length {
            var frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let naturalRange = CTFrameGetVisibleStringRange(frame)
            let naturalEnd = naturalRange.location + naturalRange.length
            // Keep ordinary Item records and totals together. Oversized records
            // still flow across pages, so long user text is never truncated.
            if let block = blocks.first(where: { $0.location > offset && $0.location < naturalEnd && NSMaxRange($0) > naturalEnd }) {
                let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
                    CFRange(location: block.location, length: block.length), nil,
                    CGSize(width: bounds.width, height: .greatestFiniteMagnitude), nil)
                if ceil(size.height) <= bounds.height {
                    frame = CTFramesetterCreateFrame(framesetter,
                        CFRange(location: offset, length: block.location - offset), path, nil)
                }
            }
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else {
                context.closePDF()
                throw PropertyManagementReportPDFFailure.couldNotPaginate
            }
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            let footer = NSAttributedString(string: "Ledger  |  Property Management  |  Page \(page)", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 8, nil)
            ])
            context.textPosition = CGPoint(x: 42, y: 25)
            CTLineDraw(CTLineCreateWithAttributedString(footer), context)
            context.endPDFPage()
            offset += visible.length
            page += 1
        }
        context.closePDF()
        return output as Data
    }
}
#endif
