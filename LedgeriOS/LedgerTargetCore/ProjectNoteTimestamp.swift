import Foundation

/// Exact historical note time. Date is a display projection, never ordering or
/// persistence authority. Seconds use the proleptic Gregorian years 0001–9999.
public struct ProjectNoteTimestamp: Codable, Hashable, Comparable, Sendable {
    public let secondsSince1970: Int64
    public let nanoseconds: Int32

    public init(secondsSince1970: Int64, nanoseconds: Int32) throws {
        guard (-62_135_596_800...253_402_300_799).contains(secondsSince1970),
              (0...999_999_999).contains(nanoseconds) else {
            throw ProjectNoteDataFailure.invalidAuditTime
        }
        self.secondsSince1970 = secondsSince1970
        self.nanoseconds = nanoseconds
    }

    /// Compatibility for the prior millisecond read contract, not a conversion
    /// of source nanoseconds through floating-point Date.
    public init(legacyMillisecondsDate date: Date) throws {
        let epoch = date.timeIntervalSince1970
        let milliseconds = (epoch * 1_000).rounded()
        guard epoch.isFinite, milliseconds.isFinite,
              milliseconds >= -62_135_596_800_000,
              milliseconds <= 253_402_300_799_999,
              Date(timeIntervalSince1970: milliseconds / 1_000) == date else {
            throw ProjectNoteDataFailure.invalidAuditTime
        }
        let integer = Int64(milliseconds)
        let seconds = integer / 1_000 - (integer % 1_000 < 0 ? 1 : 0)
        let remainder = integer - seconds * 1_000
        try self.init(secondsSince1970: seconds, nanoseconds: Int32(remainder * 1_000_000))
    }

    public var date: Date {
        Date(timeIntervalSince1970: Double(secondsSince1970) + Double(nanoseconds) / 1_000_000_000)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.secondsSince1970 == rhs.secondsSince1970
            ? lhs.nanoseconds < rhs.nanoseconds
            : lhs.secondsSince1970 < rhs.secondsSince1970
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(secondsSince1970: container.decode(Int64.self, forKey: .secondsSince1970),
            nanoseconds: container.decode(Int32.self, forKey: .nanoseconds))
    }

    private enum CodingKeys: String, CodingKey { case secondsSince1970, nanoseconds }
}

extension KeyedDecodingContainer {
    /// Even equal dual representations are rejected: each time has one authority.
    func decodeNoteTimestamp(exact: Key, legacy: Key) throws -> ProjectNoteTimestamp? {
        guard !(contains(exact) && contains(legacy)) else {
            throw ProjectNoteDataFailure.invalidAuditTime
        }
        if contains(exact) { return try decodeIfPresent(ProjectNoteTimestamp.self, forKey: exact) }
        return try decodeIfPresent(Date.self, forKey: legacy).map(ProjectNoteTimestamp.init(legacyMillisecondsDate:))
    }
}
