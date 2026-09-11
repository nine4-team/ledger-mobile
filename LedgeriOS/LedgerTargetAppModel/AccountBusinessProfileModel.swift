import Foundation
import LedgerTargetCore
import Observation

#if canImport(ImageIO)
import ImageIO

/// Shared bounded decoding for Settings and report output. Original media bytes
/// remain in the durable cache; rendering never changes their identity.
public enum AccountBusinessLogoImage {
    public static func decode(_ bytes: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}
#endif

@MainActor @Observable
public final class AccountBusinessProfileModel {
    public enum State: Equatable, Sendable {
        case idle, loading, unavailable
        case downloaded(AccountBusinessProfile)
    }

    public private(set) var state: State = .idle
    private var generation = UUID()
    public init() {}

    public func load(accountId: AccountID, reader: any AccountBusinessProfileReading) async {
        let request = UUID()
        generation = request
        state = .loading
        do {
            for try await profile in reader.watchAccountBusinessProfile(accountId: accountId) {
                try Task.checkCancellation()
                guard request == generation else { return }
                guard profile.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8) else {
                    state = .unavailable
                    return
                }
                state = .downloaded(profile)
            }
            guard request == generation else { return }
            if Task.isCancelled { state = .idle }
            else if state == .loading { state = .unavailable }
        } catch {
            guard request == generation else { return }
            state = Task.isCancelled ? .idle : .unavailable
        }
    }

    public func clear() {
        generation = UUID()
        state = .idle
    }
}
