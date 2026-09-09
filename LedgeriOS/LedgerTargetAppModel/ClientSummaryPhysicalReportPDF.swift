#if canImport(CoreGraphics) && canImport(CoreText)
import Foundation
import CoreGraphics
import CoreText
import LedgerTargetCore

public enum ClientSummaryPhysicalReportPDFFailure: Error, Equatable {
    case couldNotCreateContext, couldNotPaginate, accountProfileMismatch, incompleteDetail
}

/// On-device physical-detail renderer. The authorized reader supplies all
/// identities and branding bytes; rendering never resolves remote assets.
public enum ClientSummaryPhysicalReportPDF {
    public static func render(_ snapshot: ClientSummaryPhysicalReportSnapshot,
                              profile: AccountBusinessProfile? = nil) throws -> Data {
        guard snapshot.isComplete else { throw ClientSummaryPhysicalReportPDFFailure.incompleteDetail }
        if let profile, !profile.accountId.rawValue.utf8.elementsEqual(snapshot.project.accountId.rawValue.utf8) {
            throw ClientSummaryPhysicalReportPDFFailure.accountProfileMismatch
        }
        let logo: CGImage?
        if case .downloaded(let bytes) = profile?.logo { logo = AccountBusinessLogoImage.decode(bytes) }
        else { logo = nil }
        let text = NSMutableAttributedString(string: "")
        var blocks: [NSRange] = []
        func append(_ value: String, size: CGFloat = 11, bold: Bool = false) {
            text.append(NSAttributedString(string: value + "\n", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String):
                    CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)
            ]))
        }
        if let profile {
            append(profile.name.rawValue, size: 16, bold: true)
            if profile.isStale { append("Saved business profile", size: 8) }
            switch profile.logo {
            case .absent: append("No business logo", size: 8)
            case .notDownloaded: append("Business logo not downloaded", size: 8)
            case .unavailable: append("Business logo unavailable", size: 8)
            case .downloaded: if logo == nil { append("Business logo unavailable", size: 8) }
            }
        }
        append("CLIENT SUMMARY", size: 10, bold: true)
        append("Physical Item detail", size: 10)
        append(snapshot.project.name, size: 22, bold: true)
        append(snapshot.project.address ?? "Property address not provided")
        if case .known(let id, let name, _) = snapshot.client {
            append("Client: \(name)")
            append("Client ID: \(id.rawValue)", size: 8)
        }
        let date = Date(timeIntervalSince1970: Double(snapshot.provenance.asOf.rawValue) / 1000)
        append("As of \(ISO8601DateFormatter().string(from: date))", size: 9)
        append("")
        if snapshot.items.isEmpty { append("No data for this report") }
        let spaces = Dictionary(uniqueKeysWithValues: snapshot.spaces.map { ($0.spaceId, $0.name) })
        for item in snapshot.items {
            let start = text.length
            append(item.name, bold: true)
            append("SKU: \(item.sku ?? "Not provided")")
            if case .known(let id, let name) = item.category {
                append("Category: \(name)")
                append("Category ID: \(id.rawValue)", size: 8)
            }
            append("Space: \(item.spaceId.flatMap { spaces[$0] } ?? "No Space")")
            if let id = item.spaceId { append("Space ID: \(id.rawValue)", size: 8) }
            append("Item ID: \(item.itemId.rawValue)", size: 8)
            append("")
            blocks.append(NSRange(location: start, length: text.length - start))
        }
        append("Items: \(snapshot.items.count)", bold: true)
        append("Snapshot: \(snapshot.reference.snapshotID.rawValue)", size: 8)
        append("Source: \(snapshot.provenance.source.kind)", size: 8)
        append("Data version: \(snapshot.provenance.localDataVersion?.rawValue ?? snapshot.sourceSetHash.rawValue)", size: 8)

        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, [
                kCGPDFContextTitle: "Client Summary — Physical Item Detail",
                kCGPDFContextSubject: snapshot.reference.snapshotHash.rawValue,
                kCGPDFContextCreator: "Ledger"
              ] as CFDictionary) else { throw ClientSummaryPhysicalReportPDFFailure.couldNotCreateContext }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let bounds = CGRect(x: 42, y: 48, width: 528, height: logo == nil ? 696 : 606)
        let path = CGPath(rect: bounds, transform: nil)
        var offset = 0, page = 1
        while offset < text.length {
            var frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let natural = CTFrameGetVisibleStringRange(frame)
            let end = natural.location + natural.length
            if let block = blocks.first(where: { $0.location > offset && $0.location < end && NSMaxRange($0) > end }) {
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
                throw ClientSummaryPhysicalReportPDFFailure.couldNotPaginate
            }
            context.beginPDFPage(nil)
            if let logo {
                let scale = min(180 / CGFloat(logo.width), 72 / CGFloat(logo.height))
                context.draw(logo, in: CGRect(x: 42, y: 666,
                    width: CGFloat(logo.width) * scale, height: CGFloat(logo.height) * scale))
            }
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            let footer = NSAttributedString(string: "Ledger  |  Client Summary  |  Page \(page)", attributes: [
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
