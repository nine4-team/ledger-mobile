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

    /// Resolves the display name for a transaction, from the project's point of view.
    ///
    /// Inventory movement direction is derived implicitly from the transaction
    /// shape. Inventory → project is a Purchase from an inventory source.
    /// Project → inventory acquisition is a Sale with source-category `budgetCategoryId`. Legacy
    /// canonical sales that carry `inventorySaleDirection` are honored as a
    /// fallback.
    ///
    /// Naming convention:
    /// - Purchase, inventory → project → `"Purchase from [source]"`
    /// - Sale, project → inventory → `"Sale to [source]"`
    /// - Return → `"Return to [source]"`
    /// - Fee → "Fee" (source is the business itself — no counterparty)
    /// - Expense → source as-is (vendor name)
    /// - Purchase / other → source as-is
    /// - Legacy canonical sale with empty source → "Purchase from Inventory" /
    ///   "Sale to Inventory" / "Inventory Transfer"
    /// - Fallback → ID prefix, then "Untitled Transaction"
    static func displayName(for transaction: Transaction) -> String {
        let source = transaction.source?.trimmingCharacters(in: .whitespaces) ?? ""

        if !source.isEmpty {
            switch transaction.transactionType {
            case .sale:
                if let direction = transaction.inventorySaleDirection {
                    switch direction {
                    case .projectToBusiness: return "Sale to \(source)"
                    case .businessToProject: return "Purchase from \(source)"
                    }
                }
                return "Sale to \(source)"
            case .return:
                return "Return to \(source)"
            case .fee:
                return "Fee"
            case .purchase:
                if transaction.isInventoryMovement {
                    return "Purchase from \(source)"
                }
                return source
            case .expense, nil:
                return source
            }
        }

        // Empty source — Fee is the only type with a reliable default label
        // (counterparty is implicitly the business).
        if transaction.transactionType == .fee {
            return "Fee"
        }

        // Legacy canonical inventory sale with empty source
        if transaction.isCanonicalInventorySale == true {
            if let direction = transaction.inventorySaleDirection {
                switch direction {
                case .businessToProject:
                    return "Purchase from Inventory"
                case .projectToBusiness:
                    return "Sale to Inventory"
                }
            }
            return "Inventory Transfer"
        }

        // ID prefix fallback
        if let id = transaction.id, !id.isEmpty {
            return String(id.prefix(6))
        }

        return "Untitled Transaction"
    }

    // MARK: - Badge Configs

    /// Returns ordered array of badges for a transaction.
    /// Order: needs review → type → category.
    static func badgeConfigs(for transaction: Transaction, category: BudgetCategory?) -> [BadgeConfig] {
        var badges: [BadgeConfig] = []

        // 1. Needs review badge (always leftmost) — shows when isComplete is false or nil, but not for canceled transactions
        if transaction.isComplete != true && transaction.status != .canceled {
            badges.append(BadgeConfig(
                text: "Needs Review",
                color: StatusColors.badgeNeedsReview,
                backgroundOpacity: 0.08,
                borderOpacity: 0.20
            ))
        }

        // 2. Type badge
        if let type = transaction.transactionType {
            badges.append(BadgeConfig(text: type.displayLabel, color: BrandColors.primary))
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
        TransactionCardCalculations.formattedDate(transaction.effectiveSortDate)
    }

    // MARK: - Canonical Type Label

    /// Returns the canonical display label for a transaction type.
    static func canonicalTypeLabel(for type: TransactionType?) -> String? {
        type?.displayLabel
    }

    // MARK: - Project Label

    /// Resolves the project label for a transaction.
    ///
    /// - If `projectId` is set, returns the project's name (or `"Unknown Project"`
    ///   if no matching project is found — indicates data drift).
    /// - If `projectId` is nil, returns `"Business Inventory"`. In the data model,
    ///   a null `projectId` on an itemized transaction (Purchase, Sale, Return)
    ///   means inventory scope — not "unassigned." Surfacing this as a real label
    ///   makes the inventory scope visible to users instead of rendering as
    ///   absence.
    ///
    /// Note: this returns `"Business Inventory"` for any transaction with a null
    /// `projectId`, including non-itemized types (Fee, Expense). If those have
    /// no project they're business-overhead, but for now we treat null as
    /// inventory uniformly. Refine if/when a separate "Business Overhead" scope
    /// is introduced.
    static func projectLabel(for transaction: Transaction, projects: [Project]) -> String {
        if let projectId = transaction.projectId {
            return projects.first(where: { $0.id == projectId })?.name ?? "Unknown Project"
        }
        return "Business Inventory"
    }
}
