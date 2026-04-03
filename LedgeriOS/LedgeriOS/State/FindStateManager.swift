import SwiftUI
import Combine

/// Observable state for the find-on-page overlay (Cmd+F).
/// Injected via `.environment()` from LedgerApp.
@MainActor
@Observable
final class FindStateManager {
    var isActive = false
    var searchText = "" {
        didSet { scheduleDebouncedQuery() }
    }

    /// The debounced query that FindableText reads — avoids rebuilding
    /// AttributedStrings on every keystroke.
    private(set) var debouncedQuery = ""

    /// Per-source match lists — each view registers under its own key.
    /// The merged `matches` array is the flattened, ordered result.
    private var matchesBySource: [String: [FindMatch]] = [:]

    /// Ordered list of all matches across all sources.
    var matches: [FindMatch] {
        matchesBySource.keys.sorted().flatMap { matchesBySource[$0] ?? [] }
    }

    /// Index into `matches` for the currently focused match.
    var currentMatchIndex = 0

    /// The entity ID of the current match, for scroll-to.
    var currentMatchID: String? {
        guard !matches.isEmpty, currentMatchIndex >= 0, currentMatchIndex < matches.count else {
            return nil
        }
        return matches[currentMatchIndex].entityID
    }

    /// The occurrence index within the current entity, so FindableText
    /// can distinguish the "active" highlight from other highlights.
    var currentOccurrenceIndex: Int? {
        guard !matches.isEmpty, currentMatchIndex >= 0, currentMatchIndex < matches.count else {
            return nil
        }
        return matches[currentMatchIndex].occurrenceIndex
    }

    private var debounceTask: Task<Void, Never>?

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
        searchText = ""
        debouncedQuery = ""
        matchesBySource = [:]
        currentMatchIndex = 0
        debounceTask?.cancel()
    }

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    func previousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }

    /// Content views call this to report their matches, keyed by source.
    /// Each source overwrites only its own slot — other sources are preserved.
    func registerMatches(_ newMatches: [FindMatch], source: String) {
        matchesBySource[source] = newMatches
        // Clamp index if total matches shrank
        let total = matches.count
        if currentMatchIndex >= total {
            currentMatchIndex = max(0, total - 1)
        }
    }

    private func scheduleDebouncedQuery() {
        debounceTask?.cancel()
        let text = searchText
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            debouncedQuery = text
        }
    }
}

/// A single match occurrence for scroll-to and highlight tracking.
struct FindMatch: Identifiable, Equatable {
    let id: String // Unique: "\(entityID)-\(occurrenceIndex)"
    let entityID: String
    let occurrenceIndex: Int // Which occurrence within that entity (0-based)
}
