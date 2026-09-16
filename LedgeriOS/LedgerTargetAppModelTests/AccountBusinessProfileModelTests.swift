import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import Testing

@Suite("Account business profile presentation") @MainActor
struct AccountBusinessProfileModelTests {
    @Test("An open silent watch never hides cached branding or leaves an uncached profile spinning", arguments: [false, true])
    func localReadBeforeSilentWatch(hasCache: Bool) async throws {
        let value = try profile()
        let updates = AsyncThrowingStream<AccountBusinessProfile, Error>.makeStream()
        let started = AsyncStream<Void>.makeStream()
        let reader = SilentReader(cached: hasCache ? value : nil, updates: updates.stream, started: started.continuation)
        let model = AccountBusinessProfileModel()
        let task = Task { await model.load(accountId: value.accountId, reader: reader) }
        var observed = started.stream.makeAsyncIterator()
        _ = await observed.next()
        #expect(model.state == (hasCache ? .downloaded(value) : .unavailable))
        updates.continuation.yield(value)
        updates.continuation.finish()
        await task.value
        #expect(model.state == .downloaded(value))
        started.continuation.finish()
    }

    @Test("Export comparison tolerates retrieval status but rejects changed branding")
    func exportBrandingComparison() throws {
        let unavailable = try profile(logo: .unavailable)
        #expect(unavailable.matchesExportedBranding(try profile(logo: .notDownloaded)))
        #expect(!unavailable.matchesExportedBranding(try profile(logo: .absent)))
        #expect(!unavailable.matchesExportedBranding(try profile(account: "foreign", logo: .unavailable)))
        #expect(!(try profile(logo: .downloaded(Data([1])))).matchesExportedBranding(try profile(logo: .downloaded(Data([2])))))
        let renamed = try AccountBusinessProfile(accountId: unavailable.accountId,
            name: AccountDisplayName(validating: "Renamed"), logo: .unavailable, isStale: true)
        #expect(!unavailable.matchesExportedBranding(renamed))
    }

    @Test("Cached branding preserves name, logo state and staleness", arguments: [
        AccountBusinessProfile.Logo.absent, .notDownloaded, .unavailable, .downloaded(Data([1, 2]))
    ])
    func cached(logo: AccountBusinessProfile.Logo) async throws {
        let profile = try profile(logo: logo)
        let model = AccountBusinessProfileModel()
        await model.load(accountId: profile.accountId, reader: Reader(values: [profile]))
        #expect(model.state == .downloaded(profile))
        model.clear()
        #expect(model.state == .idle)
    }

    @Test("Foreign or byte-distinct Account results clear previously visible branding",
          arguments: ["foreign", "cafe\u{301}"])
    func wrongAccount(id: String) async throws {
        let valid = try profile(account: "café")
        let model = AccountBusinessProfileModel()
        await model.load(accountId: valid.accountId,
                         reader: Reader(values: [valid, try profile(account: id)]))
        #expect(model.state == .unavailable)
    }

    @Test("Failure clears branding; an empty stream does not spin forever", arguments: [false, true])
    func unavailable(failure: Bool) async throws {
        let profile = try profile()
        let model = AccountBusinessProfileModel()
        await model.load(accountId: profile.accountId,
                         reader: Reader(values: failure ? [profile] : [], fails: failure))
        #expect(model.state == .unavailable)
    }

    private func profile(account: String = "account", logo: AccountBusinessProfile.Logo = .absent)
        throws -> AccountBusinessProfile {
        try AccountBusinessProfile(accountId: AccountID(validating: account),
            name: AccountDisplayName(validating: "1584 Design"), logo: logo, isStale: true)
    }
}

private struct SilentReader: AccountBusinessProfileReading {
    let cached: AccountBusinessProfile?
    let updates: AsyncThrowingStream<AccountBusinessProfile, Error>
    let started: AsyncStream<Void>.Continuation
    func readAccountBusinessProfile(accountId: AccountID) async throws -> AccountBusinessProfile {
        guard let cached else { throw Reader.Failure.unavailable }; return cached
    }
    func watchAccountBusinessProfile(accountId: AccountID) -> AsyncThrowingStream<AccountBusinessProfile, Error> {
        started.yield(()); return updates
    }
}

private struct Reader: AccountBusinessProfileReading {
    let values: [AccountBusinessProfile]
    var fails = false
    enum Failure: Error { case unavailable }
    func readAccountBusinessProfile(accountId: AccountID) async throws -> AccountBusinessProfile {
        guard !fails, let value = values.last else { throw Failure.unavailable }
        return value
    }
    func watchAccountBusinessProfile(accountId: AccountID)
        -> AsyncThrowingStream<AccountBusinessProfile, Error> {
        AsyncThrowingStream { continuation in
            for value in values { continuation.yield(value) }
            if fails { continuation.finish(throwing: Failure.unavailable) }
            else { continuation.finish() }
        }
    }
}
