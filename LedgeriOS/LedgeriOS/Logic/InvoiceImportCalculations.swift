import Foundation
import CoreGraphics

// MARK: - Types

enum InvoiceVendor: String, CaseIterable {
    case amazon
    case wayfair
}

struct DraftLineItem: Identifiable {
    let id = UUID()
    var description: String
    var qty: Int
    var unitPrice: String
    var total: String
    var sku: String?
    var attributeLines: [String]?
    var thumbnailImage: CGImage?
    var isIncluded: Bool = true
}

// MARK: - Calculations

enum InvoiceImportCalculations {

    /// Auto-detect vendor from PDF text.
    static func detectVendor(_ fullText: String) -> InvoiceVendor? {
        if AmazonInvoiceParser.isAmazonInvoice(fullText) { return .amazon }
        if WayfairInvoiceParser.isWayfairInvoice(fullText) { return .wayfair }
        return nil
    }

    /// Map Amazon parse result to draft items.
    static func buildAmazonDraftItems(from result: AmazonInvoiceParser.ParseResult) -> [DraftLineItem] {
        result.lineItems.map { item in
            let unitPrice = item.unitPrice ?? item.total
            return DraftLineItem(
                description: item.description,
                qty: item.qty,
                unitPrice: unitPrice,
                total: item.total
            )
        }
    }

    /// Map Wayfair parse result to draft items.
    static func buildWayfairDraftItems(from result: WayfairInvoiceParser.ParseResult) -> [DraftLineItem] {
        result.lineItems.map { item in
            let unitPrice = item.unitPrice ?? item.total
            return DraftLineItem(
                description: item.description,
                qty: item.qty,
                unitPrice: unitPrice,
                total: item.total,
                sku: item.sku,
                attributeLines: item.attributeLines
            )
        }
    }

    /// Attach extracted thumbnail images to draft items by index (first image → first item).
    static func attachThumbnails(_ thumbnails: [PdfImageExtractor.ImagePlacement], to items: inout [DraftLineItem]) {
        for (index, placement) in thumbnails.prefix(items.count).enumerated() {
            items[index].thumbnailImage = placement.image
        }
    }

    /// Validate minimum requirements to create transaction.
    static func isReadyToImport(draftItems: [DraftLineItem]) -> Bool {
        draftItems.contains { $0.isIncluded }
    }

    /// Build source string for transaction.
    static func sourceString(vendor: InvoiceVendor?, amazonResult: AmazonInvoiceParser.ParseResult?, wayfairResult: WayfairInvoiceParser.ParseResult?) -> String {
        switch vendor {
        case .amazon:
            if let orderNumber = amazonResult?.orderNumber { return "Amazon #\(orderNumber)" }
            return "Amazon"
        case .wayfair:
            if let invoiceNumber = wayfairResult?.invoiceNumber { return "Wayfair #\(invoiceNumber)" }
            return "Wayfair"
        case nil:
            return "Invoice Import"
        }
    }

    /// Get the transaction date from parse results.
    static func transactionDate(vendor: InvoiceVendor?, amazonResult: AmazonInvoiceParser.ParseResult?, wayfairResult: WayfairInvoiceParser.ParseResult?) -> String {
        let parsed: String? = switch vendor {
        case .amazon: amazonResult?.orderPlacedDate
        case .wayfair: wayfairResult?.orderDate
        case nil: nil
        }
        return parsed ?? isoDateToday()
    }

    /// Get the total amount in cents from parse results.
    static func totalCents(vendor: InvoiceVendor?, amazonResult: AmazonInvoiceParser.ParseResult?, wayfairResult: WayfairInvoiceParser.ParseResult?) -> Int? {
        let totalString: String? = switch vendor {
        case .amazon: amazonResult?.grandTotal
        case .wayfair: wayfairResult?.orderTotal
        case nil: nil
        }
        return InvoiceMoneyParsing.parseCentsFromDollarString(totalString)
    }

    // MARK: - Private

    private static func isoDateToday() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
