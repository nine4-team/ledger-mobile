import AppKit
import CoreText
import Foundation
import LedgerTargetAppModel
import LedgerTargetCore
import PDFKit

/// Entirely synthetic PDFs generated in memory. Exercise the shipping adapter
/// and unchanged parser sources, including PDFKit extraction and async review.
@main
struct LocalVendorPDFParserFixtureTests {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
    }

    static func pdf(_ pages: [String], textX: CGFloat = 36,
                    images: [(CGRect, CGColor)] = []) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output) else { throw Failure(description: "PDF consumer") }
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
            throw Failure(description: "PDF context")
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        for page in pages {
            context.beginPDFPage(nil)
            for (rect, color) in images {
                guard let raster = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                    bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw Failure(description: "Fixture image context")
                }
                raster.setFillColor(color)
                raster.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                guard let image = raster.makeImage() else { throw Failure(description: "Fixture image") }
                context.draw(image, in: rect)
            }
            for (index, line) in page.components(separatedBy: "\n").enumerated() {
                let attributed = NSAttributedString(string: line, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font
                ])
                context.textPosition = CGPoint(x: textX, y: CGFloat(750 - index * 18))
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    static func imageOnlyPDF() throws -> Data {
        // A real raster page with no text layer, not merely invalid/empty bytes.
        let image = NSImage(size: NSSize(width: 300, height: 100))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 300, height: 100).fill()
        ("Synthetic raster invoice" as NSString).draw(at: NSPoint(x: 10, y: 40),
            withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
        image.unlockFocus()
        guard let page = PDFPage(image: image) else { throw Failure(description: "Raster PDF page") }
        let document = PDFDocument()
        document.insert(page, at: 0)
        guard let bytes = document.dataRepresentation() else { throw Failure(description: "Raster PDF bytes") }
        return bytes
    }

    static func fails(_ bytes: Data, with expected: LocalVendorDocumentFailure) async throws {
        do {
            _ = try await LocalVendorPDFParser().parse(bytes)
            throw Failure(description: "Expected \(expected), but parse succeeded")
        } catch let failure as LocalVendorDocumentFailure {
            try check(failure == expected, "Expected \(expected), got \(failure)")
        }
    }

    @MainActor
    static func main() async throws {
        let amazonBytes = try pdf(["""
        Amazon.com order number: 111-2222222-3333333
        Order Placed: January 2, 2025
        Project code: SYNTHETIC-ROOM
        Visa | Last digits: 1234
        Shipped on January 3, 2025
        2 of: Synthetic Table Lamp $12.50
        Item(s) Subtotal: $25.00
        """, """
        Shipped on January 4, 2025
        1 of: Synthetic Desk Mat $5.00
        Shipping & Handling: $3.00
        Estimated Tax: $2.00
        Grand Total: $35.00
        """])
        let amazon = try await LocalVendorPDFParser().parse(amazonBytes)
        try check(amazon.vendor == .amazon && amazon.pageCount == 2, "Amazon vendor/pages")
        try check(amazon.rows.map(\.id) == [0, 1], "Amazon source row ordinals")
        try check(amazon.fields["Order number"] == "111-2222222-3333333", "Amazon order number")
        try check(amazon.fields["Order date"] == "2025-01-02", "Amazon order date")
        try check(amazon.fields["Project code"] == "SYNTHETIC-ROOM", "Amazon project code")
        try check(amazon.fields["Payment method"] == "Visa | Last digits: 1234", "Amazon payment text")
        try check(amazon.fields["Total"] == "35.00" && amazon.fields["Tax"] == "2.00"
            && amazon.fields["Shipping"] == "3.00", "Amazon header money")
        try check(amazon.rows[0].description == "Synthetic Table Lamp" && amazon.rows[0].quantity == 2
            && amazon.rows[0].unitPrice == "12.50" && amazon.rows[0].total == "25.00", "Amazon row money")
        try check(amazon.rows[0].details["Shipped on"] == "2025-01-03"
            && amazon.rows[1].details["Shipped on"] == "2025-01-04", "Amazon shipment association")
        try check(amazon.rawText.contains("Synthetic Desk Mat"), "Amazon source text")
        try check(amazon.warnings.isEmpty, "Unexpected Amazon warnings: \(amazon.warnings)")
        print("PASS Amazon actual two-page PDF: fields, rows, shipment association, source text")

        let wayfairBytes = try pdf(["""
        Wayfair
        Invoice Number: 123456789
        Order Date: February 3, 2025
        Shipped On February 5, 2025
        Synthetic Accent Chair
        SKU: SYN123456
        Color: Blue
        Size: Large
        Fabric: Linen
        $40.00 2 $80.00 $4.00 $2.00 $6.00 $88.00
        Items to be Shipped
        Synthetic Side Table
        SKU: SYN654321
        $10.00 1 $10.00 $0.00 $0.00 $1.00 $11.00
        Subtotal: $90.00
        Shipping: $4.00
        Adjustments: $2.00
        Tax Total: $7.00
        Order Total: $99.00
        """])
        let wayfair = try await LocalVendorPDFParser().parse(wayfairBytes)
        try check(wayfair.vendor == .wayfair && wayfair.pageCount == 1, "Wayfair vendor/pages")
        try check(wayfair.rows.map(\.id) == [0, 1], "Wayfair source row ordinals: \(wayfair.rows)")
        try check(wayfair.fields["Invoice number"] == "123456789"
            && wayfair.fields["Order date"] == "2025-02-03", "Wayfair identifiers/date")
        try check(wayfair.fields["Total"] == "99.00" && wayfair.fields["Subtotal"] == "90.00"
            && wayfair.fields["Shipping"] == "4.00" && wayfair.fields["Tax"] == "7.00"
            && wayfair.fields["Adjustments"] == "2.00" && wayfair.fields["Calculated subtotal"] == "92.00",
            "Wayfair header money preserves parser output")
        let chair = wayfair.rows[0]
        try check(chair.description == "Synthetic Accent Chair" && chair.quantity == 2
            && chair.unitPrice == "40.00" && chair.total == "88.00" && chair.sku == "SYN123456",
            "Wayfair row identity/money: \(chair)")
        try check(chair.attributes == ["Color: Blue", "Size: Large", "Fabric: Linen"], "Wayfair raw attributes")
        try check(chair.details == ["Subtotal": "80.00", "Shipping": "4.00", "Adjustment": "2.00",
            "Tax": "6.00", "Shipped on": "2025-02-05", "Section": "shipped", "Color": "Blue", "Size": "Large"],
            "Wayfair detailed fields: \(chair.details)")
        try check(wayfair.rows[1].details["Section"] == "to_be_shipped"
            && wayfair.rows[1].details["Shipped on"] == nil, "Unshipped row does not inherit shipment date")
        try check(wayfair.rawText.contains("Fabric: Linen"), "Wayfair source text")
        try check(wayfair.warnings == WayfairInvoiceParser.parse(wayfair.rawText).warnings,
            "Wayfair warnings must survive adapter mapping")
        print("PASS Wayfair actual PDF: SKU, attributes, money columns, shipped/unshipped details")

        let incompleteAmazon = try await LocalVendorPDFParser().parse(pdf(["""
        Amazon.com order number: 111-4444444-5555555
        2 of: Synthetic Unpriced Lamp
        Grand Total: $25.00
        """]))
        try check(incompleteAmazon.fields["Order date"] == nil, "Missing Amazon date must remain absent")
        try check(incompleteAmazon.rows.isEmpty, "Missing Amazon unit price must not become grand total")
        try check(incompleteAmazon.warnings.contains(where: { $0.contains("unit price") }), "Missing price warning")
        let incompleteWayfair = try await LocalVendorPDFParser().parse(pdf(["""
        Wayfair
        Invoice Number: 987654321
        Synthetic Unpriced Chair
        Qty: 2 $88.00
        Order Total: $88.00
        """]))
        try check(incompleteWayfair.fields["Order date"] == nil, "Missing Wayfair date must remain absent")
        try check(incompleteWayfair.rows.isEmpty, "Wayfair total-only row must not synthesize a unit price")
        try check(!incompleteWayfair.warnings.isEmpty, "Incomplete Wayfair must preserve parser warnings")
        print("PASS missing dates stay absent; unpriced rows are omitted, not assigned totals")

        try await fails(Data("synthetic corrupt bytes".utf8), with: .corruptDocument)
        try await fails(imageOnlyPDF(), with: .imageOnlyDocument)
        try await fails(pdf(["Synthetic Other Vendor Invoice 123456"]), with: .unsupportedVendor)
        try await fails(pdf(["Amazon.com order number: 111-2222222-3333333\nWayfair Invoice Number: 123456789"]),
            with: .ambiguousVendor)
        print("PASS actual corrupt, raster-only, unsupported and ambiguous vendor inputs")

        let review = LocalVendorDocumentReview(accountId: try AccountID(validating: "synthetic-fixture-account"))
        await review.load(amazonBytes, parser: LocalVendorPDFParser())
        try check(review.state == .review && review.document == amazon && review.sourceBytes == amazonBytes,
            "Actual parser-to-review preserves source document/bytes")
        guard let hash = review.documentHash else { throw Failure(description: "Missing digest") }
        let expectedHash = try ProtectedArtifactSHA256.make(bytes: amazonBytes)
        try check(hash == expectedHash, "Digest binds original PDF bytes")
        review.update(id: 0, documentHash: hash) { $0.description = "Edited lamp"; $0.included = false }
        try check(review.document == amazon && review.sourceBytes == amazonBytes && review.rows[0].original == amazon.rows[0],
            "Draft edits must preserve original PDF evidence")
        try check(review.rows[1].id == 1 && review.includedCount == 1, "Exclusion keeps second source row identity")
        try check(review.documentHash == hash, "Editing must preserve source digest")
        print("PASS actual PDF-to-review draft edits preserve source bytes, digest and row identity")
        let illustrated = try pdf(["""
        Wayfair
        Invoice Number: 123456789
        Synthetic Chair
        SKU: SYN111111
        $10.00 1 $10.00 $0.00 $0.00 $0.00 $10.00
        Synthetic Table
        SKU: SYN222222
        $20.00 1 $20.00 $0.00 $0.00 $0.00 $20.00
        Order Total: $30.00
        """], textX: 150, images: [
            (CGRect(x: 60, y: 680, width: 40, height: 40), CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
            (CGRect(x: 60, y: 620, width: 40, height: 40), CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ])
        let illustratedReview = LocalVendorDocumentReview(accountId: try AccountID(validating: "synthetic-fixture-account"))
        await illustratedReview.load(illustrated, parser: LocalVendorPDFParser())
        try check(illustratedReview.rows.count == 2, "Illustrated PDF parsed row count")
        guard let first = illustratedReview.rows[0].original.thumbnail,
              let second = illustratedReview.rows[1].original.thumbnail,
              let illustratedHash = illustratedReview.documentHash else {
            throw Failure(description: "Actual adapter did not retain image evidence")
        }
        try check(first.pngBytes != second.pngBytes && first.pageIndex == 0 && second.pageIndex == 0,
            "Different source images must remain distinct")
        illustratedReview.update(id: 0, documentHash: illustratedHash) { $0.included = false }
        illustratedReview.update(id: 1, documentHash: illustratedHash) { $0.description = "Edited table" }
        try check(illustratedReview.rows[1].original.thumbnail == second,
            "Exclusion and description edit must not rebind the remaining thumbnail")
        illustratedReview.close()
        try check(illustratedReview.rows.isEmpty && illustratedReview.sourceBytes == nil,
            "Closing must release original document and thumbnail evidence")
        print("PASS actual illustrated PDF -> adapter -> editable review keeps per-row image provenance")
        print("All local vendor PDF fixture checks passed.")
    }
}
