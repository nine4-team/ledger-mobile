import SwiftUI

/// Drop-in replacement for `Text(string)` that supports find-on-page highlighting
/// and text selection. When no find query is active, renders identically to `Text`.
///
/// Usage:
/// ```swift
/// FindableText(item.displayName)
///     .font(Typography.h3)
///     .foregroundStyle(BrandColors.textPrimary)
/// ```
struct FindableText: View {
    let text: String

    /// Which entity this text belongs to (for current-match tracking).
    var entityID: String?

    /// The cumulative occurrence offset for this text field within the entity.
    /// Used to determine which specific occurrence is the "current match."
    var occurrenceOffset: Int = 0

    @Environment(FindStateManager.self) private var findState

    var body: some View {
        if findState.debouncedQuery.isEmpty {
            Text(text)
                .textSelection(.enabled)
        } else {
            Text(highlightedString)
                .textSelection(.enabled)
        }
    }

    private var highlightedString: AttributedString {
        let query = findState.debouncedQuery
        var attributed = AttributedString(text)

        let ranges = FindMatchCalculations.matchRanges(in: text, query: query)
        guard !ranges.isEmpty else { return attributed }

        let currentEntityID = findState.currentMatchID.flatMap { matchID in
            findState.matches.first(where: { $0.id == matchID })?.entityID
        }
        let currentOccurrence = findState.currentOccurrenceIndex

        for (index, range) in ranges.enumerated() {
            // Convert String.Index range to AttributedString range
            guard let attrRange = Range(range, in: attributed) else { continue }

            let globalOccurrenceIndex = occurrenceOffset + index
            let isCurrent = entityID == currentEntityID && globalOccurrenceIndex == currentOccurrence

            if isCurrent {
                attributed[attrRange].backgroundColor = Color(
                    red: 152/255, green: 126/255, blue: 85/255, opacity: 0.4
                )
            } else {
                attributed[attrRange].backgroundColor = Color.yellow.opacity(0.25)
            }
        }

        return attributed
    }
}

// Convenience initializer matching Text(string) pattern
extension FindableText {
    init(_ text: String) {
        self.text = text
    }
}
