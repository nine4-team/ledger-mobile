import Foundation

/// Shared currency formatting utilities.
/// Delegates to BudgetDisplayCalculations for basic formats to avoid duplication.
enum CurrencyFormatting {

    /// Formats cents as whole dollars: 15000 → "$150", 15099 → "$150"
    static func formatCents(_ cents: Int) -> String {
        BudgetDisplayCalculations.formatCentsAsDollars(cents)
    }

    /// Formats cents with two decimal places: 15099 → "$150.99"
    static func formatCentsWithDecimals(_ cents: Int) -> String {
        BudgetDisplayCalculations.formatCentsWithDecimals(cents)
    }

    /// Formats cents in compact notation for large amounts.
    /// Examples: 150000 → "$1.5K", 1500000 → "$15K", 150000000 → "$1.5M"
    /// Falls back to whole-dollar format for amounts under $1,000.
    static func formatCentsCompact(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let isNegative = dollars < 0
        let absDollars = abs(dollars)
        let prefix = isNegative ? "-" : ""

        if absDollars >= 1_000_000 {
            let millions = absDollars / 1_000_000
            if millions == millions.rounded(.down) {
                return "\(prefix)$\(Int(millions))M"
            }
            return "\(prefix)$\(String(format: "%.1f", millions))M"
        }

        if absDollars >= 1_000 {
            let thousands = absDollars / 1_000
            if thousands == thousands.rounded(.down) {
                return "\(prefix)$\(Int(thousands))K"
            }
            return "\(prefix)$\(String(format: "%.1f", thousands))K"
        }

        return formatCents(cents)
    }
}
