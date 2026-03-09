import Foundation

/// Shared date parsing for invoice text extraction.
/// Port of `parseDateToIso` from both `amazonInvoiceParser.ts` and `wayfairInvoiceParser.ts`.
enum InvoiceDateParsing {

    /// Parses various date formats to YYYY-MM-DD.
    /// Supports: "01/15/2026", "January 15, 2026", "Jan 15, 2026", "Dec 1, 2024"
    static func parseDateToIso(_ input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // 1) MM/DD/YYYY
        if let match = s.firstMatch(of: /\b(\d{1,2})\/(\d{1,2})\/(\d{4})\b/) {
            let month = Int(match.1)!
            let day = Int(match.2)!
            let year = Int(match.3)!
            if month >= 1, month <= 12, day >= 1, day <= 31 {
                return formatIsoDate(year: year, month: month, day: day)
            }
        }

        // 2) Month DD, YYYY (e.g., January 15, 2026 or Jan 15, 2026)
        if let match = s.firstMatch(of: /\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\s+(\d{1,2}),\s*(\d{4})\b/),
           let monthNum = monthIndex(String(match.1)) {
            let day = Int(match.2)!
            let year = Int(match.3)!
            if day >= 1, day <= 31 {
                return formatIsoDate(year: year, month: monthNum, day: day)
            }
        }

        // 3) Fallback: DateFormatter
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["MMM d, yyyy", "MMMM d, yyyy", "MM/dd/yyyy", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: s) {
                let cal = Calendar(identifier: .gregorian)
                let comps = cal.dateComponents([.year, .month, .day], from: date)
                if let y = comps.year, let m = comps.month, let d = comps.day {
                    return formatIsoDate(year: y, month: m, day: d)
                }
            }
        }

        return nil
    }

    // MARK: - Private

    private static func formatIsoDate(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func monthIndex(_ abbrev: String) -> Int? {
        let key = abbrev.lowercased().prefix(3)
        let months: [Substring: Int] = [
            "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
            "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
        ]
        return months[key]
    }
}
