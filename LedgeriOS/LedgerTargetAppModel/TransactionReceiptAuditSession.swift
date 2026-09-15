import Foundation
import LedgerTargetCore
import Observation

/// View-owned state for the existing receipt watch. No cache or operation queue;
/// the workspace runtime continues to own subscriptions and their drainage.
@MainActor @Observable
public final class TransactionReceiptAuditSession {
    public enum State: Equatable { case loading, ready, incomplete, unavailable, failed }
    public private(set) var state: State = .loading
    public private(set) var receipt: TransactionReceiptSnapshot?
    public private(set) var presentation: TransactionReceiptAuditPresentation?
    private let scope: TransactionScope
    private let principalId: PrincipalID
    private let transactionId: TransactionID
    private let watch: @Sendable () -> AsyncThrowingStream<TransactionReceiptUpdate, Error>
    private let locale: Locale
    private var generation = UUID()

    public init(scope: TransactionScope, principalId: PrincipalID, transactionId: TransactionID,
                locale: Locale = .autoupdatingCurrent,
                watch: @escaping @Sendable () -> AsyncThrowingStream<TransactionReceiptUpdate, Error>) {
        self.scope = scope
        self.principalId = principalId
        self.transactionId = transactionId
        self.locale = locale
        self.watch = watch
    }

    public func receive(_ update: TransactionReceiptUpdate) throws {
        switch update {
        case .ready(let receipt):
            do {
                try receipt.validate(accountId: scope.accountId, principalId: principalId, transactionId: transactionId)
                guard receipt.classification.scope == scope else { throw TransactionReceiptSnapshot.Failure.scopeMismatch }
                let presentation = try TransactionReceiptAuditPresentation(receipt: receipt, locale: locale)
                self.receipt = receipt
                self.presentation = presentation
                state = .ready
            } catch {
                clear(.failed)
                throw error
            }
        case .incomplete: clear(.incomplete)
        case .unavailable: clear(.unavailable)
        }
    }

    public func observe() async {
        let active = UUID()
        generation = active
        clear(.loading)
        do {
            for try await update in watch() {
                try Task.checkCancellation()
                guard generation == active else { return }
                try receive(update)
            }
            if generation == active { clear(.unavailable) }
        } catch is CancellationError {
            if generation == active { clear(.unavailable) }
        } catch {
            if generation == active { clear(.failed) }
        }
    }

    public func invalidate() {
        generation = UUID()
        clear(.unavailable)
    }

    private func clear(_ state: State) {
        receipt = nil
        presentation = nil
        self.state = state
    }
}
