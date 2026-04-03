import Foundation

/// Pure functions for find-on-page text matching.
enum FindMatchCalculations {

    /// Count how many times `query` appears in `text` (case-insensitive, non-overlapping).
    static func occurrenceCount(in text: String, query: String) -> Int {
        guard !query.isEmpty, !text.isEmpty else { return 0 }
        let lower = text.lowercased()
        var count = 0
        var searchRange = lower.startIndex..<lower.endIndex
        while let range = lower.range(of: query, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<lower.endIndex
        }
        return count
    }

    /// Returns the ranges (in the original string) that match the query, case-insensitive.
    static func matchRanges(in text: String, query: String) -> [Range<String.Index>] {
        guard !query.isEmpty, !text.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<text.endIndex
        }
        return ranges
    }
}
