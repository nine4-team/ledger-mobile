import Testing
@testable import LedgerTargetAppModel

@Suite("Workspace removal presentation")
@MainActor
struct WorkspaceAccessPresentationTests {
    @Test("Confirmed bootstrap removal locks without opening a runtime or subscribing")
    func bootstrapRemovalStaysLocked() {
        let model = WorkspaceAccessPresentation()
        model.showRemoval()
        model.stop()
        model.observe(AsyncStream { $0.finish() })
        #expect(model.isLocked)
    }

    @Test("Buffered removal locks before any later observer data can reveal the workspace")
    func bufferedRemovalStaysLocked() async {
        let events = AsyncStream<Void>.makeStream()
        events.continuation.yield(())
        events.continuation.finish()
        let model = WorkspaceAccessPresentation()
        model.observe(events.stream)
        for _ in 0..<100 {
            if model.isLocked { break }
            await Task.yield()
        }
        #expect(model.isLocked)
        model.stop()
        model.observe(AsyncStream { $0.finish() })
        #expect(model.isLocked)
    }

    @Test("Observation cancellation is not removal and a cancelled source cannot lock a replacement")
    func cancelledSourceIsIgnored() async {
        let old = AsyncStream<Void>.makeStream()
        let current = AsyncStream<Void>.makeStream()
        let model = WorkspaceAccessPresentation()
        model.observe(old.stream)
        model.stop()
        model.observe(current.stream)
        old.continuation.yield(())
        old.continuation.finish()
        for _ in 0..<20 { await Task.yield() }
        #expect(!model.isLocked)
        current.continuation.yield(())
        current.continuation.finish()
        for _ in 0..<100 {
            if model.isLocked { break }
            await Task.yield()
        }
        #expect(model.isLocked)
        model.stop()
    }
}
