import SwiftUI

/// Pure functions for TransactionCard display logic.
/// Badge generation, amount formatting, date formatting, and note truncation.
enum TransactionCardCalculations {

    /// Returns ordered array of badges for a transaction.
    /// Order: needs review → type
    static func badgeItems(
        transactionType: TransactionType?,
        reimbursementType: String?,
        hasEmailReceipt: Bool,
        isComplete: Bool?,
        status: TransactionStatus?,
        isCanonicalInventorySale: Bool? = nil,
        inventorySaleDirection: InventorySaleDirection? = nil,
        budgetCategoryId: String? = nil,
        invoiceStatus: InvoiceStatus? = nil
    ) -> [CardBadge] {
        var badges: [CardBadge] = []

        // 1. Needs review badge (always leftmost) — shows when isComplete is false or nil, but not for canceled transactions
        if isComplete != true && status != .canceled {
            badges.append(CardBadge(
                text: "Needs Review",
                color: StatusColors.badgeNeedsReview,
                backgroundOpacity: 0.08,
                borderOpacity: 0.20
            ))
        }

        // 2. Transaction type badge
        if let type = transactionType {
            let label: String
            let color: Color
            if type == .sale,
               inventorySaleDirection == .businessToProject {
                // Inventory -> project uses the Purchase label, including
                // legacy Sale-shaped records that predate the type correction.
                label = TransactionType.purchase.displayLabel
                color = BrandColors.primary
            } else {
                // New per-batch inventory purchases show "Purchase"; sale-to-inventory
                // shows "Sale"; everything else uses its own label.
                label = type.displayLabel
                switch type {
                case .sale:      color = StatusColors.atRiskBar
                case .return:    color = StatusColors.badgeNeedsReview
                case .fee:       color = StatusColors.badgeWarning
                case .expense:   color = BrandColors.primary
                case .paymentToBusiness: color = StatusColors.metText
                case .purchase:  color = BrandColors.primary
                }
            }
            badges.append(CardBadge(text: label, color: color))
        }

        // Invoice-derived badge — only for non-itemized transactions (itemized
        // derive from children). The caller is responsible for passing nil
        // when the transaction is itemized.
        if let invoice = invoiceStatus, invoice != .voided {
            let text = invoice == .paid ? "Paid" : "Invoiced"
            let color: Color = invoice == .paid ? StatusColors.metText : StatusColors.inProgressText
            badges.append(CardBadge(text: text, color: color))
        }

        return badges
    }

    /// Formats transaction amount with sign prefix.
    /// Purchase/to-inventory → "$X.XX", sale/return → "$X.XX"
    /// The RN app shows "$X.XX" format (with decimals) for transaction amounts.
    static func formattedAmount(amountCents: Int?, transactionType: TransactionType?) -> String {
        guard let cents = amountCents else { return "—" }
        return CurrencyFormatting.formatCentsWithDecimals(cents)
    }

    /// Formats ISO date string to "MMM d, yyyy" (e.g., "Feb 25, 2026").
    static func formattedDate(_ dateString: String?) -> String {
        guard let dateString, !dateString.isEmpty else { return "—" }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try with fractional seconds first, then without
        var date = isoFormatter.date(from: dateString)
        if date == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            date = isoFormatter.date(from: dateString)
        }
        // Try simple date-only format (yyyy-MM-dd)
        if date == nil {
            let simple = DateFormatter()
            simple.dateFormat = "yyyy-MM-dd"
            simple.locale = Locale(identifier: "en_US_POSIX")
            date = simple.date(from: dateString)
        }

        guard let parsed = date else { return "—" }

        let display = DateFormatter()
        display.dateFormat = "MMM d, yyyy"
        display.locale = Locale(identifier: "en_US_POSIX")
        return display.string(from: parsed)
    }

    /// Formats a `Date` (e.g. `createdAt`) as "MMM d, yyyy". Returns "—" if nil.
    static func formattedCreatedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let display = DateFormatter()
        display.dateFormat = "MMM d, yyyy"
        display.locale = Locale(identifier: "en_US_POSIX")
        return display.string(from: date)
    }

    /// Truncates notes to maxLength, appending "..." if truncated.
    /// Returns nil if notes is nil or empty.
    static func truncatedNotes(_ notes: String?, maxLength: Int = 100) -> String? {
        guard let notes, !notes.isEmpty else { return nil }
        if notes.count <= maxLength { return notes }
        let truncated = notes.prefix(maxLength)
        return String(truncated) + "..."
    }
}
