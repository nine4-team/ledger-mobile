import Foundation
@testable import PowerSync
import Testing

/// Exercises the SDK sequence used by the real database update-log reader.
/// Closing a database cancels that reader while its producer may finish.
@Suite("PowerSync sequence cancellation", .serialized)
struct PowerSyncSequenceCancellationTests {
    private enum SourceFailure: Error { case failed }

    @Test("Ordinary event delivery and normal end remain intact")
    func eventAndEnd() async throws {
        let (stream, source) = AsyncThrowingStream<Void, any Error>.makeStream()
        let iterator = MergeItemSequence(inner: stream).makeAsyncIterator()
        let consumer = Task { try await iterator.next() }
        source.yield(())
        #expect(try await consumer.value != nil)
        source.finish()
        #expect(try await iterator.next() == nil)
        _ = await iterator.pollTask.result
    }

    @Test("Upstream errors reach an active consumer and then end")
    func errorDelivery() async throws {
        let (stream, source) = AsyncThrowingStream<Void, any Error>.makeStream()
        let iterator = MergeItemSequence(inner: stream).makeAsyncIterator()
        let consumer = Task { try await iterator.next() }
        source.finish(throwing: SourceFailure.failed)
        await #expect(throws: SourceFailure.self) { try await consumer.value }
        #expect(try await iterator.next() == nil)
        _ = await iterator.pollTask.result
    }

    @Test("An error buffered before the first consumer is not dropped")
    func bufferedErrorDelivery() async throws {
        let (stream, source) = AsyncThrowingStream<Void, any Error>.makeStream()
        let iterator = MergeItemSequence(inner: stream).makeAsyncIterator()
        source.finish(throwing: SourceFailure.failed)
        // Deterministically finish the producer before installing a listener.
        _ = await iterator.pollTask.result
        await #expect(throws: SourceFailure.self) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
    }

    @Test("Consumer cancellation races producer event, finish and failure without deadlock")
    func cancellationRaces() async {
        for mode in 0..<3 {
            for _ in 0..<200 {
                let (stream, source) = AsyncThrowingStream<Void, any Error>.makeStream()
                let iterator = MergeItemSequence(inner: stream).makeAsyncIterator()
                let consumer = Task { try await iterator.next() }
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { consumer.cancel() }
                    group.addTask {
                        switch mode {
                        case 0: source.yield(()); source.finish()
                        case 1: source.finish()
                        default: source.finish(throwing: SourceFailure.failed)
                        }
                    }
                }
                // Either an event, end or source error can win the race. Completion,
                // not which winner ran first, is the shutdown contract.
                _ = await consumer.result
                _ = await iterator.pollTask.result
            }
        }
    }

    @Test("Cancellation stays terminal when the producer receives late events")
    func terminalCancellation() async throws {
        let (stream, source) = AsyncThrowingStream<Void, any Error>.makeStream()
        let iterator = MergeItemSequence(inner: stream).makeAsyncIterator()
        let consumer = Task { try await iterator.next() }
        consumer.cancel()
        _ = await consumer.result
        source.yield(())
        source.finish(throwing: SourceFailure.failed)
        _ = await iterator.pollTask.result
        #expect(try await iterator.next() == nil)
    }
}
