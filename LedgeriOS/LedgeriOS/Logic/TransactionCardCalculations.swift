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
        status: TransactionStatus?
    ) -> [CardBadge] {
        var badges: [CardBadge] = []

        // 1. Needs review badge (always leftmost) — shows when isComplete is false or nil
        if isComplete != true {
            badges.append(CardBadge(
                text: "Needs Review",
                color: StatusColors.badgeNeedsReview,
                backgroundOpacity: 0.08,
                borderOpacity: 0.20
            ))
        }

        // 2. Transaction type badge
        if let type = transactionType {
            badges.append(CardBadge(text: type.displayLabel, color: BrandColors.primary))
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

    /// Truncates notes to maxLength, appending "..." if truncated.
    /// Returns nil if notes is nil or empty.
    static func truncatedNotes(_ notes: String?, maxLength: Int = 100) -> String? {
        guard let notes, !notes.isEmpty else { return nil }
        if notes.count <= maxLength { return notes }
        let truncated = notes.prefix(maxLength)
        return String(truncated) + "..."
    }
}
