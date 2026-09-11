import Foundation

/// Read-only workspace branding. Discovery continues to use AccountSummary.
public struct AccountBusinessProfile: Equatable, Sendable {
    public enum Logo: Equatable, Sendable {
        case absent
        case notDownloaded
        case unavailable
        /// Bytes verified against the authorized logo reference by the provider.
        case downloaded(Data)
    }

    public let accountId: AccountID
    public let name: AccountDisplayName
    public let logo: Logo
    public let isStale: Bool

    public init(accountId: AccountID, name: AccountDisplayName, logo: Logo, isStale: Bool) {
        self.accountId = accountId
        self.name = name
        self.logo = logo
        self.isStale = isStale
    }

    /// A failed network attempt and an absent local cache can describe the same
    /// branding. Neither supplies image bytes; their retry status is not a rename
    /// or logo change. Actual bytes and explicit logo removal remain significant.
    public func matchesExportedBranding(_ other: AccountBusinessProfile) -> Bool {
        guard accountId.rawValue.utf8.elementsEqual(other.accountId.rawValue.utf8),
              name.rawValue.utf8.elementsEqual(other.name.rawValue.utf8) else { return false }
        switch (logo, other.logo) {
        case (.notDownloaded, .unavailable), (.unavailable, .notDownloaded): return true
        default: return logo == other.logo
        }
    }
}

/// Implementations bind both profile metadata and logo bytes to active workspace
/// authorization, and stop yielding protected data when that access is removed.
public protocol AccountBusinessProfileReading: Sendable {
    /// Finite authorized local read; never waits for a network download.
    func readAccountBusinessProfile(accountId: AccountID) async throws -> AccountBusinessProfile
    func watchAccountBusinessProfile(accountId: AccountID)
        -> AsyncThrowingStream<AccountBusinessProfile, Error>
}
