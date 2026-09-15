import Foundation
import LedgerTargetCore

/// Display values only; the receipt snapshot owns validity and exact arithmetic.
/// Progress-bar rounding never determines the audit verdict.
public struct TransactionReceiptAuditPresentation: Equatable, Sendable {
    public let isApplicable: Bool
    public let isComplete: Bool
    public let progressPercentage: Double?
    public let statusLabel: String
    public let details: [String]
    public let missingItemIds: [ItemID]
    public let missingItems: [MissingItem]
    public let itemCount: Int

    public struct MissingItem: Identifiable, Equatable, Sendable {
        public let id: ItemID
        public let name: String
        public let sku: String?
    }

    public init(receipt: TransactionReceiptSnapshot, locale: Locale = .autoupdatingCurrent) throws {
        isApplicable = receipt.categoryKind == .itemized
        isComplete = receipt.auditStatus == .balanced
        itemCount = receipt.items.count
        missingItems = receipt.items.filter { $0.amount == nil }.map {
            MissingItem(id: $0.id, name: $0.name.flatMap { $0.isEmpty ? nil : $0 }
                ?? "Item \($0.id.rawValue)", sku: $0.sku)
        }
        missingItemIds = missingItems.map(\.id)
        let currency = receipt.finalAmount.currency
        func format(_ cents: Int64) -> String {
            (Decimal(cents) / 100).formatted(.currency(code: currency.rawValue).locale(locale))
        }
        func total(_ values: [Money]) throws -> Int64 {
            try values.reduce(Money.zero(currency: currency)) { try $0.adding($1) }.minorUnits
        }
        var detail = ["Transaction total: \(format(receipt.finalAmount.minorUnits))"]
        if receipt.items.contains(where: { $0.membership != .linked }) {
            for (kind, name) in [(TransactionReceiptSnapshot.Membership.linked, "Linked items"),
                                 (.returned, "Returned items"), (.sold, "Sold items")] {
                let items = receipt.items.filter { $0.membership == kind }
                guard !items.isEmpty else { continue }
                let value = items.contains(where: { $0.amount == nil }) ? "Unknown"
                    : format(try total(items.compactMap(\.amount)))
                detail.append("\(name) (\(items.count)): \(value)")
            }
        }
        detail.append("Physical Item total: \(receipt.reconstruction.map { format($0.physicalItemTotal.minorUnits) } ?? "Unknown")")
        let increase = try total(receipt.lines.filter { $0.effect == .increase }.map(\.magnitude))
        let decrease = try total(receipt.lines.filter { $0.effect == .decrease }.map(\.magnitude))
        detail.append("Other receipt lines — increases: \(format(increase))")
        detail.append("Other receipt lines — decreases: \(format(decrease))")
        detail.append("Other receipt lines — net: \(format(increase - decrease))")
        if let calculation = receipt.reconstruction {
            detail.append("Reconstructed total: \(format(calculation.reconstructedTotal.minorUnits))")
            detail.append("Difference: \(format(calculation.variance.minorUnits))")
            progressPercentage = min(100, max(0,
                Double(calculation.reconstructedTotal.minorUnits) / Double(receipt.finalAmount.minorUnits) * 100))
            if !isApplicable { statusLabel = "Audit not applicable" }
            else if isComplete { statusLabel = "Balanced" }
            else { statusLabel = "Difference: \(format(calculation.variance.minorUnits))" }
        } else {
            detail.append("Reconstructed total: Unknown")
            detail.append("Difference: Unknown")
            progressPercentage = nil
            statusLabel = isApplicable ? "Receipt details incomplete" : "Audit not applicable"
        }
        details = detail
    }
}
