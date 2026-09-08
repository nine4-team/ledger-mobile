/// An ``AsyncSequence`` merging all items emitted between calls to ``AsyncIteratorProtocol/next``.
/// 
/// This is useful for sequences where we just want to know that an event has occurred, without needing
/// to know about the exact event. We use this internally to implement `watch()` queries with a throttle:
/// If any amount of events have occurred between throttled calls to `next()`, we want to dispatch a single
/// event.
struct MergeItemSequence<Base: AsyncSequence & Sendable>: AsyncSequence where Base.Element == () {
    typealias AsyncIterator = IteratorImpl
    typealias Element = ()

    private let inner: Base

    init(inner: Base) {
        self.inner = inner
    }

    func makeAsyncIterator() -> IteratorImpl {
        IteratorImpl(inner: self.inner)
    }

    private final class IteratorState: Sendable {
        let inner = Mutex(MergeSequenceState.idle)
    }

    final class IteratorImpl: AsyncIteratorProtocol, Sendable {
        private let state: IteratorState
        let pollTask: Task<(), any Error>

        init(inner: Base) {
            let state = IteratorState()
            self.pollTask = Task {
                do {
                    for try await _ in inner {
                        state.inner.withLock { $0.markHasEvent() }?.resume()
                    }

                    state.inner.withLock { $0.transitionToDone() }?.resume()
                } catch {
                    state.inner.withLock { $0.markFailed(error: error) }?.resume()
                }
            }

            self.state = state
        }

        func next() async throws -> ()? {
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        state.inner.withLock { $0.registerListener(continuation) }?.resume()
                    }
                },
                onCancel: {
                    let completion = state.inner.withLock { $0.transitionToDone() }
                    pollTask.cancel()
                    completion?.resume()
                }
            )
        }
        
        deinit {
            self.pollTask.cancel()
        }
    }
}

// Never resume a continuation under the state mutex: cancellation holds a Swift
// task-status lock while invoking onCancel, which needs this same mutex. Resuming
// under it can wait for that task-status lock and deadlock database close.
private struct MergeSequenceCompletion {
    let continuation: CheckedContinuation<()?, any Error>
    let result: Result<()?, any Error>

    func resume() { continuation.resume(with: result) }
}

private enum MergeSequenceState {
    /// No one waiting on next(), no pending emit either.
    case idle
    /// We're waiting in next() for an upstream emission.
    case waitingForUpstream(CheckedContinuation<()?, any Error>)
    /// We have an upstream emission that has not yet been sent (due to backpressure or throttle).
    case hasPendingEvent
    /// Fetching from upstream failed.
    /// 
    /// For the task fetching events, this is a final state: Once errored, it will not emit any
    /// further events, and it won't set the state to `done` like it would if the source iterator
    /// had completed normally.
    /// 
    /// This exists as a separate state to ensure a subsequent call to `next()` can throw. Once
    /// the error was observed there, this state transitions to `done`.
    case failure(any Error)
    case done
    
    mutating func registerListener(_ continuation: CheckedContinuation<()?, any Error>) -> MergeSequenceCompletion? {
        switch self {
        case .idle:
            self = .waitingForUpstream(continuation)
        case .waitingForUpstream(_):
            fatalError("Async throttle sequence has two concurrent listeners?!")
        case .hasPendingEvent:
            self = .idle
            return .init(continuation: continuation, result: .success(()))
        case .failure(let error):
            self = .done
            return .init(continuation: continuation, result: .failure(error))
        case .done:
            return .init(continuation: continuation, result: .success(nil))
        }
        return nil
    }

    mutating func markHasEvent() -> MergeSequenceCompletion? {
        switch self {
        case .waitingForUpstream(let continuation):
            self = .idle
            return .init(continuation: continuation, result: .success(()))
        case .idle, .hasPendingEvent:
            self = .hasPendingEvent
        case .done, .failure:
            break
        }
        return nil
    }

    mutating func markFailed(error: any Error) -> MergeSequenceCompletion? {
        switch self {
        case .waitingForUpstream(let continuation):
            self = .done
            return .init(continuation: continuation, result: .failure(error))
        case .idle, .hasPendingEvent:
            self = .failure(error)
        case .done, .failure:
            break
        }
        return nil
    }

    mutating func transitionToDone() -> MergeSequenceCompletion? {
        let completion: MergeSequenceCompletion?
        if case let .waitingForUpstream(continuation) = self {
            completion = .init(continuation: continuation, result: .success(nil))
        } else {
            completion = nil
        }
        self = .done
        return completion
    }
}
