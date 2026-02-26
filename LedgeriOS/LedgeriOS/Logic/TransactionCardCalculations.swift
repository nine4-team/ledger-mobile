import SwiftUI

/// Pure functions for TransactionCard display logic.
/// Badge generation, amount formatting, date formatting, and note truncation.
enum TransactionCardCalculations {

    /// A badge to display on a transaction card.
    struct BadgeItem: Equatable {
        let text: String
        let color: Color
    }

    /// Returns ordered array of badges for a transaction.
    /// Order: type → reimbursement → receipt → needs review → category
    static func badgeItems(
        transactionType: String?,
        reimbursementType: String?,
        hasEmailReceipt: Bool,
        needsReview: Bool,
        budgetCategoryName: String?,
        status: String?
    ) -> [BadgeItem] {
        var badges: [BadgeItem] = []

        // 1. Transaction type badge
        if let type = transactionType?.lowercased() {
            switch type {
            case "purchase":
                badges.append(BadgeItem(text: "Purchase", color: StatusColors.badgeSuccess))
            case "sale":
                badges.append(BadgeItem(text: "Sale", color: StatusColors.badgeInfo))
            case "return":
                badges.append(BadgeItem(text: "Return", color: StatusColors.badgeError))
            case "to-inventory":
                badges.append(BadgeItem(text: "To Inventory", color: BrandColors.primary))
            default:
                break
            }
        }

        // 2. Reimbursement badge
        if let reimburse = reimbursementType?.lowercased() {
            switch reimburse {
            case "owed-to-client":
                badges.append(BadgeItem(text: "Owed to Client", color: StatusColors.badgeWarning))
            case "owed-to-company":
                badges.append(BadgeItem(text: "Owed to Business", color: StatusColors.badgeWarning))
            default:
                break
            }
        }

        // 3. Email receipt badge
        if hasEmailReceipt {
            badges.append(BadgeItem(text: "Receipt", color: BrandColors.primary))
        }

        // 4. Needs review badge
        if needsReview {
            badges.append(BadgeItem(text: "Needs Review", color: StatusColors.badgeNeedsReview))
        }

        // 5. Budget category badge
        if let category = budgetCategoryName, !category.isEmpty {
            badges.append(BadgeItem(text: category, color: BrandColors.primary))
        }

        return badges
    }

    /// Formats transaction amount with sign prefix.
    /// Purchase/to-inventory → "$X.XX", sale/return → "$X.XX"
    /// The RN app shows "$X.XX" format (with decimals) for transaction amounts.
    static func formattedAmount(amountCents: Int?, transactionType: String?) -> String {
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
