import Foundation

/// Pure functions for computing find matches across visible entities.
enum FindMatchCalculations {

    /// Compute all match occurrences for a list of (entityID, searchableTexts) pairs.
    /// Returns one `FindMatch` per occurrence, ordered by entity then by field order.
    static func computeMatches(
        query: String,
        entities: [(id: String, texts: [String])]
    ) -> [FindMatch] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }

        var result: [FindMatch] = []

        for entity in entities {
            var occurrenceIndex = 0
            for text in entity.texts {
                let count = occurrenceCount(in: text, query: q)
                for _ in 0..<count {
                    result.append(FindMatch(
                        id: "\(entity.id)-\(occurrenceIndex)",
                        entityID: entity.id,
                        occurrenceIndex: occurrenceIndex
                    ))
                    occurrenceIndex += 1
                }
            }
        }

        return result
    }

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
