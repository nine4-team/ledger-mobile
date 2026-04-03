import SwiftUI

// MARK: - Environment key for entity ID

/// Set at the card level so every FindableText inside inherits the entity ID.
/// Usage: `.findEntity(id: item.id)`
private struct FindEntityIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var findEntityID: String? {
        get { self[FindEntityIDKey.self] }
        set { self[FindEntityIDKey.self] = newValue }
    }
}

extension View {
    /// Sets the entity ID for find-on-page match tracking.
    /// Apply once at the card level — all FindableText children inherit it.
    func findEntity(id: String?) -> some View {
        environment(\.findEntityID, id)
    }
}

// MARK: - FindableText

/// Drop-in replacement for `Text(string)` that supports find-on-page highlighting
/// and text selection. When no find query is active, renders identically to `Text`.
///
/// Self-reports match counts to FindStateManager — no manual registration needed.
struct FindableText: View {
    let text: String

    /// Stable identity for match reporting. Defaults to the text content itself,
    /// combined with entityID to handle duplicate strings across entities.
    var reportID: String?

    @Environment(FindStateManager.self) private var findState
    @Environment(\.findEntityID) private var entityID

    private var identity: String {
        reportID ?? "\(entityID ?? ""):\(text)"
    }

    var body: some View {
        if findState.debouncedQuery.isEmpty {
            Text(text)
                .textSelection(.enabled)
                .onAppear { findState.removeReport(identity: identity) }
        } else {
            Text(highlightedString)
                .textSelection(.enabled)
                .id(identity)
                .onAppear { reportMatches() }
                .onDisappear { findState.removeReport(identity: identity) }
                .onChange(of: findState.debouncedQuery) { _, _ in reportMatches() }
        }
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

    private var highlightedString: AttributedString {
        let query = findState.debouncedQuery
        var attributed = AttributedString(text)

        let ranges = FindMatchCalculations.matchRanges(in: text, query: query)
        guard !ranges.isEmpty else { return attributed }

        let isCurrentEntity = entityID != nil && entityID == findState.currentMatchID

        for (_, range) in ranges.enumerated() {
            guard let attrRange = Range(range, in: attributed) else { continue }

            if isCurrentEntity {
                attributed[attrRange].backgroundColor = Color(
                    red: 152/255, green: 126/255, blue: 85/255, opacity: 0.45
                )
            } else {
                attributed[attrRange].backgroundColor = Color.yellow.opacity(0.25)
            }
        }

        return attributed
    }
}

extension FindableText {
    init(_ text: String) {
        self.text = text
    }
}
