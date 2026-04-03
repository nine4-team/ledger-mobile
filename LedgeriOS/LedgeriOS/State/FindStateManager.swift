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

    /// The debounced query that FindableText reads.
    private(set) var debouncedQuery = ""

    /// Match count reported by each on-screen FindableText instance.
    /// Key = stable view identity string, Value = (entityID, matchCount).
    private var reportedMatches: [String: (entityID: String, count: Int)] = [:]

    /// Total match count across all visible FindableText instances.
    var totalMatchCount: Int {
        reportedMatches.values.reduce(0) { $0 + $1.count }
    }

    /// Ordered entity IDs that have matches (for scroll-to).
    /// Preserves insertion order via the sorted keys.
    var matchEntityIDs: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for key in reportedMatches.keys.sorted() {
            let entry = reportedMatches[key]!
            if entry.count > 0 && seen.insert(entry.entityID).inserted {
                result.append(entry.entityID)
            }
        }
        return result
    }

    /// Index of the current match (0-based into totalMatchCount).
    var currentMatchIndex = 0

    /// The entity ID of the current match, for scroll-to and card highlight.
    var currentMatchID: String? {
        let total = totalMatchCount
        guard total > 0, currentMatchIndex >= 0, currentMatchIndex < total else {
            return nil
        }
        // Walk through reported matches to find which entity the index lands in.
        var remaining = currentMatchIndex
        for key in reportedMatches.keys.sorted() {
            let entry = reportedMatches[key]!
            if entry.count > 0 {
                if remaining < entry.count {
                    return entry.entityID
                }
                remaining -= entry.count
            }
        }
        return nil
    }

    /// Which occurrence within the current entity is the active one.
    var currentOccurrenceInEntity: Int {
        let total = totalMatchCount
        guard total > 0, currentMatchIndex >= 0, currentMatchIndex < total else {
            return 0
        }
        var remaining = currentMatchIndex
        let targetEntity = currentMatchID
        for key in reportedMatches.keys.sorted() {
            let entry = reportedMatches[key]!
            if entry.count > 0 {
                if entry.entityID == targetEntity {
                    if remaining < entry.count {
                        return remaining
                    }
                    remaining -= entry.count
                } else {
                    remaining -= entry.count
                }
            }
        }
        return 0
    }

    /// The identity key of the FindableText that contains the current match.
    /// Used as scroll target — FindableText sets `.id(identity)` on itself.
    var currentMatchIdentity: String? {
        let total = totalMatchCount
        guard total > 0, currentMatchIndex >= 0, currentMatchIndex < total else {
            return nil
        }
        var remaining = currentMatchIndex
        for key in reportedMatches.keys.sorted() {
            let entry = reportedMatches[key]!
            if entry.count > 0 {
                if remaining < entry.count {
                    return key
                }
                remaining -= entry.count
            }
        }
        return nil
    }

    /// Combine publisher for scroll-to — fires on every arrow press.
    let scrollToPublisher = PassthroughSubject<String, Never>()

    private var debounceTask: Task<Void, Never>?

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
        searchText = ""
        debouncedQuery = ""
        reportedMatches = [:]
        currentMatchIndex = 0
        debounceTask?.cancel()
    }

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    func nextMatch() {
        guard totalMatchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % totalMatchCount
        emitScroll()
    }

    func previousMatch() {
        guard totalMatchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + totalMatchCount) % totalMatchCount
        emitScroll()
    }

    /// Called by each FindableText to report how many matches it contains.
    func reportMatchCount(_ count: Int, identity: String, entityID: String) {
        let oldCount = reportedMatches[identity]?.count ?? 0
        if oldCount != count || reportedMatches[identity]?.entityID != entityID {
            reportedMatches[identity] = (entityID: entityID, count: count)
            clampIndex()
            // Auto-scroll to first match when results first appear
            if oldCount == 0 && count > 0 {
                emitScroll()
            }
        }
    }

    /// Called when a FindableText disappears (navigated away).
    func removeReport(identity: String) {
        if reportedMatches.removeValue(forKey: identity) != nil {
            clampIndex()
        }
    }

    private func clampIndex() {
        let total = totalMatchCount
        if currentMatchIndex >= total {
            currentMatchIndex = max(0, total - 1)
        }
    }

    private func emitScroll() {
        if let id = currentMatchIdentity {
            scrollToPublisher.send(id)
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
