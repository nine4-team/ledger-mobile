import Foundation
import LedgerTargetAppModel

/// Compiles the same pure local parser sources as the existing app. No legacy
/// draft-to-Transaction helper or persistence service participates in review.
struct LocalVendorPDFParser: LocalVendorDocumentParsing {
    func parse(_ bytes: Data) async throws -> LocalVendorDocument {
        try await Task.detached(priority: .userInitiated) {
            try Self.extract(bytes)
        }.value
    }

    private static func extract(_ bytes: Data) throws -> LocalVendorDocument {
        guard let extraction = PdfTextExtractor.extractText(from: bytes) else {
            throw LocalVendorDocumentFailure.corruptDocument
        }
        let text = extraction.fullText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalVendorDocumentFailure.imageOnlyDocument
        }
        let amazon = AmazonInvoiceParser.isAmazonInvoice(text)
        let wayfair = WayfairInvoiceParser.isWayfairInvoice(text)
        guard !(amazon && wayfair) else { throw LocalVendorDocumentFailure.ambiguousVendor }
        func fields(_ values: [(String, String?)]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: values.compactMap { key, value in value.map { (key, $0) } })
        }
        if amazon {
            let parsed = AmazonInvoiceParser.parse(text)
            return LocalVendorDocument(vendor: .amazon,
                fields: fields([("Order number", parsed.orderNumber), ("Order date", parsed.orderPlacedDate),
                    ("Total", parsed.grandTotal), ("Tax", parsed.tax), ("Shipping", parsed.shipping),
                    ("Project code", parsed.projectCode), ("Payment method", parsed.paymentMethod)]),
                rows: parsed.lineItems.enumerated().map { index, row in
                    LocalVendorDocumentRow(id: index, description: row.description, quantity: row.qty,
                        unitPrice: row.unitPrice, total: row.total,
                        details: fields([("Shipped on", row.shippedOn)]))
                }, warnings: parsed.warnings, rawText: text, pageCount: extraction.stats.pageCount)
        }
        if wayfair {
            let parsed = WayfairInvoiceParser.parse(text)
            let thumbnails = LocalVendorPDFThumbnailExtractor.extract(from: bytes,
                rows: parsed.lineItems.enumerated().compactMap { index, row in
                    row.sku.map { .init(id: index, sku: $0) }
                }).mapValues { image in
                    LocalVendorDocumentThumbnail(pngBytes: image.pngBytes, pageIndex: image.pageNumber - 1,
                        anchorRange: NSRange(location: image.anchorUTF16Location, length: image.anchorUTF16Length),
                        imageBounds: .init(x: image.bounds.x, y: image.bounds.y,
                                            width: image.bounds.width, height: image.bounds.height))
                }
            return LocalVendorDocument(vendor: .wayfair,
                fields: fields([("Invoice number", parsed.invoiceNumber), ("Order date", parsed.orderDate),
                    ("Last updated", parsed.invoiceLastUpdated), ("Total", parsed.orderTotal),
                    ("Subtotal", parsed.subtotal), ("Shipping", parsed.shippingDeliveryTotal),
                    ("Tax", parsed.taxTotal), ("Adjustments", parsed.adjustmentsTotal),
                    ("Calculated subtotal", parsed.calculatedSubtotal)]),
                rows: parsed.lineItems.enumerated().map { index, row in
                    LocalVendorDocumentRow(id: index, description: row.description, quantity: row.qty,
                        unitPrice: row.unitPrice, total: row.total, sku: row.sku,
                        attributes: row.attributeLines ?? [],
                        details: fields([("Subtotal", row.subtotal), ("Shipping", row.shipping),
                            ("Adjustment", row.adjustment), ("Tax", row.tax), ("Shipped on", row.shippedOn),
                            ("Section", row.section?.rawValue), ("Color", row.attributes?.color),
                            ("Size", row.attributes?.size)]), thumbnail: thumbnails[index])
                }, warnings: parsed.warnings, rawText: text, pageCount: extraction.stats.pageCount)
        }
        throw LocalVendorDocumentFailure.unsupportedVendor
    }
}
