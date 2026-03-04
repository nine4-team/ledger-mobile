import SwiftUI

/// Pure functions for transaction display logic on detail views.
/// Display name resolution, badge generation, amount/date formatting.
enum TransactionDisplayCalculations {

    struct BadgeConfig: Equatable {
        let text: String
        let color: Color
        var backgroundOpacity: Double = 0.10
        var borderOpacity: Double = 0.20
    }

    enum TransactionBadgeType {
        case type, reimbursement, receipt, needsReview, category
    }

    // MARK: - Display Name

    /// Resolves the display name for a transaction.
    /// Priority: source → canonical inventory sale label → ID prefix → "Untitled Transaction".
    static func displayName(for transaction: Transaction) -> String {
        // 1. Source if non-nil and non-empty
        if let source = transaction.source, !source.trimmingCharacters(in: .whitespaces).isEmpty {
            return source
        }

        // 2. Canonical inventory sale label
        if transaction.isCanonicalInventorySale == true {
            if let direction = transaction.inventorySaleDirection {
                switch direction {
                case .businessToProject:
                    return "To Inventory"
                case .projectToBusiness:
                    return "From Inventory"
                }
            }
            return "Inventory Transfer"
        }

        // 3. ID prefix (first 6 characters)
        if let id = transaction.id, !id.isEmpty {
            return String(id.prefix(6))
        }

        // 4. Fallback
        return "Untitled Transaction"
    }

    // MARK: - Badge Configs

    /// Returns ordered array of badges for a transaction.
    /// Order: needs review → type → category.
    static func badgeConfigs(for transaction: Transaction, category: BudgetCategory?) -> [BadgeConfig] {
        var badges: [BadgeConfig] = []

        // 1. Needs review badge (always leftmost)
        if transaction.needsReview == true {
            badges.append(BadgeConfig(
                text: "Needs Review",
                color: StatusColors.badgeNeedsReview,
                backgroundOpacity: 0.08,
                borderOpacity: 0.20
            ))
        }

        // 2. Type badge (purchase/return only)
        if let type = transaction.transactionType?.lowercased() {
            switch type {
            case "purchase":
                badges.append(BadgeConfig(text: "Purchase", color: BrandColors.primary))
            case "return":
                badges.append(BadgeConfig(text: "Return", color: BrandColors.primary))
            default:
                break
            }
        }

        // 3. Category badge
        if let cat = category, let name = cat.id, !name.isEmpty {
            let displayName = cat.name.isEmpty ? "Category" : cat.name
            badges.append(BadgeConfig(text: displayName, color: BrandColors.primary))
        }

        return badges
    }

    // MARK: - Formatted Amount

    /// Formats transaction amount as a currency string (e.g. "$49.99").
    static func formattedAmount(for transaction: Transaction) -> String {
        guard let cents = transaction.amountCents else { return "—" }
        return CurrencyFormatting.formatCentsWithDecimals(cents)
    }

    // MARK: - Formatted Date

    /// Formats transaction date as "MMM d, yyyy". Returns empty string if nil.
    static func formattedDate(for transaction: Transaction) -> String {
        TransactionCardCalculations.formattedDate(transaction.transactionDate)
    }

    // MARK: - Canonical Type Label

    /// Returns the canonical display label for a transaction type.
    static func canonicalTypeLabel(for type: String?) -> String? {
        guard let type = type?.lowercased() else { return nil }
        switch type {
        case "purchase": return "Purchase"
        case "sale": return "Sale"
        case "return": return "Return"
        case "to-inventory": return "To Inventory"
        default: return nil
        }
    }
}
