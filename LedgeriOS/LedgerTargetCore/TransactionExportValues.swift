import Foundation

/// Target values for the existing field selector/CSV serializer. No reads,
/// lifecycle inference, signed-money reversal, or second Transaction model.
public enum TransactionExportValues {
    public enum Cell: Equatable, Sendable {
        case text(String), money(Money), boolean(Bool), unknown
    }
    public enum Failure: Error, Equatable {
        case unavailableField(String)
        case incompleteField(String)
        case unknownField(String)
    }

    public static func validate(fieldID: String) throws {
        switch fieldID {
        case "transactionId", "transactionDate", "source", "transactionType", "paymentMethod", "amount",
             "budgetCategory", "categoryId", "notes", "receiptEmailed", "createdAt", "projectId", "currency", "purchasedBy",
             "receiptAuditStatus", "receiptItemTotal", "receiptLineIncreaseTotal", "receiptLineDecreaseTotal",
             "receiptReconstructedTotal", "receiptVariance", "receiptLines", "receiptLinesJSON", "taxRatePct", "subtotal", "itemCategories": return
        case "reimbursementType", "status", "receiptImages",
             "inventorySaleDirection": throw Failure.unavailableField(fieldID)
        default: throw Failure.unknownField(fieldID)
        }
    }

    /// Field IDs are the original ExportFields IDs. Unsupported legacy fields
    /// fail explicitly until their owning target data/policy is implemented.
    /// Missing values in an otherwise supported field remain unknown, not false/0.
    public static func cell(fieldID: String, row: TransactionDetailSnapshot) throws -> Cell {
        switch fieldID {
        case "transactionId": return .text(row.transactionId.rawValue)
        case "transactionDate": return row.transactionDate.map(Cell.text) ?? .unknown
        case "source": return row.source.map(Cell.text) ?? .unknown
        case "transactionType":
            switch row.classification.type {
            case .purchase: return .text("Purchase")
            case .return: return .text("Return")
            case .transfer: return .text("Transfer")
            }
        case "paymentMethod": return row.paymentMethod.map(Cell.text) ?? .unknown
        case "amount": return .money(row.amount)
        case "budgetCategory": return row.category.map { .text($0.name) } ?? .unknown
        case "categoryId": return row.category.map { .text($0.id.rawValue) } ?? .unknown
        case "notes": return row.notes.map(Cell.text) ?? .unknown
        case "receiptEmailed": return row.hasEmailReceipt.map(Cell.boolean) ?? .unknown
        case "createdAt":
            guard let milliseconds = row.createdAtMilliseconds else { return .unknown }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return .text(formatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1_000)))
        case "projectId": return row.classification.scope.projectId.map { .text($0.rawValue) } ?? .unknown
        case "purchasedBy":
            // Canonical scope ownership, as displayed in Transaction detail.
            // A Return retains that purchase owner; it does not reverse them
            // into the vendor who issued the refund.
            return .text(row.classification.scope.ownerKind == .project ? "Client" : "1584")
        case "taxRatePct": return row.legacyTaxRatePct.map(Cell.text) ?? .unknown
        case "subtotal": return row.legacySubtotal.map(Cell.money) ?? .unknown
        case "itemCategories":
            guard let items = row.currentItemCategories, items.allSatisfy({ $0.categoryId != nil }) else {
                throw Failure.incompleteField(fieldID)
            }
            return .text(items.compactMap { $0.categoryId?.rawValue }.joined(separator: "|"))
        case "reimbursementType", "status", "receiptImages",
             "inventorySaleDirection":
            // No raw receipt URLs, invented payer, inferred tax/subtotal, or
            // reconstructed current Item categories from historical receipt links.
            throw Failure.unavailableField(fieldID)
        case "currency": return .text(row.amount.currency.rawValue)
        case "receiptAuditStatus": return row.receipt.map { .text($0.auditStatus.rawValue) } ?? .unknown
        case "receiptItemTotal": return row.receipt?.reconstruction.map { .money($0.physicalItemTotal) } ?? .unknown
        case "receiptLineIncreaseTotal": return row.receipt?.reconstruction.map { .money($0.lineIncreaseTotal) } ?? .unknown
        case "receiptLineDecreaseTotal": return row.receipt?.reconstruction.map { .money($0.lineDecreaseTotal) } ?? .unknown
        case "receiptReconstructedTotal": return row.receipt?.reconstruction.map { .money($0.reconstructedTotal) } ?? .unknown
        case "receiptVariance": return row.receipt?.reconstruction.map { .money($0.variance) } ?? .unknown
        case "receiptLines":
            guard let receipt = row.receipt else { return .unknown }
            return .text(ReceiptLineExport.readable(receipt.lines))
        case "receiptLinesJSON":
            guard let receipt = row.receipt else { return .unknown }
            return .text(try ReceiptLineExport.structured(receipt.lines))
        default: throw Failure.unknownField(fieldID)
        }
    }

}
