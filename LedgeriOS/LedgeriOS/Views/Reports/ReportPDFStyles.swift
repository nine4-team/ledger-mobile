import SwiftUI

/// PDF-specific color palette and styling constants matching the original
/// `reportHtml.ts` stylesheet. These are fixed (non-adaptive) colors
/// because PDFs always render on a white background.
enum ReportPDFStyles {

    // MARK: - Colors (from reportHtml.ts getReportStyles)

    /// Brand primary — report titles, section headers, net due highlight, receipt badges
    static let brand = Color(red: 152/255, green: 126/255, blue: 85/255)             // #987e55

    /// Primary body text
    static let textPrimary = Color(red: 26/255, green: 26/255, blue: 26/255)         // #1a1a1a

    /// Section titles, total labels
    static let textDark = Color(red: 51/255, green: 51/255, blue: 51/255)            // #333333

    /// Secondary text — table headers, card labels, meta info
    static let textSecondary = Color(red: 102/255, green: 102/255, blue: 102/255)    // #666666

    /// Item sub-text
    static let textSub = Color(red: 136/255, green: 136/255, blue: 136/255)          // #888888

    /// Footer text
    static let textFooter = Color(red: 153/255, green: 153/255, blue: 153/255)       // #999999

    /// Error/missing price indicator
    static let error = Color(red: 192/255, green: 57/255, blue: 43/255)              // #c0392b

    /// Table header background, receipt badge background
    static let headerBg = Color(red: 247/255, green: 243/255, blue: 238/255)         // #f7f3ee

    /// Card background, even row striping
    static let cardBg = Color(red: 250/255, green: 248/255, blue: 245/255)           // #faf8f5

    /// Border color — card borders, section underlines, table header border
    static let border = Color(red: 224/255, green: 213/255, blue: 197/255)           // #e0d5c5

    /// Subtle row divider
    static let rowBorder = Color(red: 240/255, green: 235/255, blue: 228/255)        // #f0ebe4

    // MARK: - Layout

    /// Standard PDF page width (US Letter at 72dpi = 612pt)
    static let pageWidth: CGFloat = 800

    /// Page padding
    static let pagePadding: CGFloat = 40

    /// Header bottom border width
    static let headerBorderWidth: CGFloat = 2

    /// Net due top border width
    static let netDueBorderWidth: CGFloat = 2

    // MARK: - Fonts (matching reportHtml.ts sizes)

    /// Report title — 22px / 700 weight
    static let titleFont: Font = .system(size: 22, weight: .bold)

    /// Report subtitle (report type) — 16px / 600
    static let subtitleFont: Font = .system(size: 16, weight: .semibold)

    /// Section header (h2) — 16px / 600
    static let sectionHeaderFont: Font = .system(size: 16, weight: .semibold)

    /// Table header — 11px / 600
    static let tableHeaderFont: Font = .system(size: 11, weight: .semibold)

    /// Body text — 13px
    static let bodyFont: Font = .system(size: 13)

    /// Body bold — 13px / 600
    static let bodyBoldFont: Font = .system(size: 13, weight: .semibold)

    /// Net due — 15px / 700
    static let netDueFont: Font = .system(size: 15, weight: .bold)

    /// Card label — 11px / 600
    static let cardLabelFont: Font = .system(size: 11, weight: .semibold)

    /// Card value — 20px / 700
    static let cardValueFont: Font = .system(size: 20, weight: .bold)

    /// Sub-item text — 11px
    static let subItemFont: Font = .system(size: 11)

    /// Missing price — 11px italic
    static let missingPriceFont: Font = .system(size: 11).italic()

    /// Receipt badge — 10px / 600
    static let badgeFont: Font = .system(size: 10, weight: .semibold)

    /// Footer — 11px
    static let footerFont: Font = .system(size: 11)

    /// Meta info — 12px
    static let metaFont: Font = .system(size: 12)

    /// Meta label — 12px / 600
    static let metaLabelFont: Font = .system(size: 12, weight: .semibold)
}
