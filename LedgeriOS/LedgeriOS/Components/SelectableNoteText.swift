import SwiftUI

struct SelectableNoteText: View {
    enum Style {
        case body
        case small
    }

    let text: String
    let style: Style

    @Environment(FindStateManager.self) private var findState
    @Environment(\.findEntityID) private var entityID

    private var identity: String {
        "\(entityID ?? ""):note:\(text)"
    }

    var body: some View {
        NativeSelectableNoteText(
            text: text,
            style: style,
            query: findState.debouncedQuery,
            isCurrentEntity: entityID != nil && entityID == findState.currentMatchID
        )
        .onAppear { reportMatches() }
        .onDisappear { findState.removeReport(identity: identity) }
        .onChange(of: findState.debouncedQuery) { _, _ in reportMatches() }
    }

    private func reportMatches() {
        let query = findState.debouncedQuery
        guard !query.isEmpty else {
            findState.removeReport(identity: identity)
            return
        }
        let count = FindMatchCalculations.occurrenceCount(in: text, query: query.lowercased())
        findState.reportMatchCount(count, identity: identity, entityID: entityID ?? "")
    }
}

#if canImport(UIKit)
import UIKit

private struct NativeSelectableNoteText: UIViewRepresentable {
    let text: String
    let style: SelectableNoteText.Style
    let query: String
    let isCurrentEntity: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.attributedText = attributedText
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 0
        guard width > 0 else { return nil }

        uiView.attributedText = attributedText
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    private var attributedText: NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )

        let ranges = FindMatchCalculations.matchRanges(in: text, query: query)
        for range in ranges {
            attributed.addAttribute(
                .backgroundColor,
                value: highlightColor,
                range: NSRange(range, in: text)
            )
        }

        return attributed
    }

    private var font: UIFont {
        let base: UIFont
        switch style {
        case .body:
            base = UIFont(name: "AvenirNext-Regular", size: 16) ?? .preferredFont(forTextStyle: .body)
            return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        case .small:
            base = UIFont(name: "AvenirNext-Regular", size: 14) ?? .preferredFont(forTextStyle: .subheadline)
            return UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: base)
        }
    }

    private var textColor: UIColor {
        switch style {
        case .body: return .label
        case .small: return .secondaryLabel
        }
    }

    private var highlightColor: UIColor {
        isCurrentEntity
            ? UIColor(red: 152/255, green: 126/255, blue: 85/255, alpha: 0.45)
            : UIColor.systemYellow.withAlphaComponent(0.25)
    }
}
#elseif canImport(AppKit)
private struct NativeSelectableNoteText: View {
    let text: String
    let style: SelectableNoteText.Style
    let query: String
    let isCurrentEntity: Bool

    var body: some View {
        Text(highlightedString)
            .font(style == .body ? Typography.body : Typography.small)
            .foregroundStyle(style == .body ? BrandColors.textPrimary : BrandColors.textSecondary)
            .textSelection(.enabled)
    }

    private var highlightedString: AttributedString {
        var attributed = AttributedString(text)
        let ranges = FindMatchCalculations.matchRanges(in: text, query: query)

        for range in ranges {
            guard let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].backgroundColor = isCurrentEntity
                ? Color(red: 152/255, green: 126/255, blue: 85/255, opacity: 0.45)
                : Color.yellow.opacity(0.25)
        }

        return attributed
    }
}
#endif
