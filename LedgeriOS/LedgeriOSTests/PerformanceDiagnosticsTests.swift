import Foundation
import Testing
@testable import LedgeriOS

@Suite("Performance Diagnostics")
struct PerformanceDiagnosticsTests {
    @Test("Runtime gate accepts launch argument")
    func runtimeGateArgument() {
        #expect(PerformanceDiagnosticsConfiguration.isEnabled(
            arguments: ["Ledger", "-LedgerPerformanceDiagnostics", "YES"],
            environment: [:]
        ))
    }

    @Test("Runtime gate accepts environment variable")
    func runtimeGateEnvironment() {
        #expect(PerformanceDiagnosticsConfiguration.isEnabled(
            arguments: ["Ledger"],
            environment: ["LEDGER_PERFORMANCE_DIAGNOSTICS": "1"]
        ))
    }

    @Test("Runtime gate is disabled by default")
    func runtimeGateDefault() {
        #expect(!PerformanceDiagnosticsConfiguration.isEnabled(
            arguments: ["Ledger"],
            environment: [:]
        ))
    }

    @Test("Stall severity thresholds are deterministic")
    func stallSeverity() {
        #expect(MainThreadStallSeverity.classify(milliseconds: 249) == nil)
        #expect(MainThreadStallSeverity.classify(milliseconds: 250) == .notice)
        #expect(MainThreadStallSeverity.classify(milliseconds: 999) == .notice)
        #expect(MainThreadStallSeverity.classify(milliseconds: 1_000) == .severe)
        #expect(MainThreadStallSeverity.classify(milliseconds: 5_000) == .critical)
    }

    @Test("Ring buffer retains only newest events")
    func ringBufferCapacity() {
        var buffer = PerformanceDiagnosticRingBuffer(capacity: 2)
        for index in 0..<3 {
            buffer.append(PerformanceDiagnosticEvent(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                name: "event-\(index)",
                kind: "test",
                count: index,
                value: 0,
                durationMilliseconds: nil
            ))
        }

        #expect(buffer.events.map(\.name) == ["event-1", "event-2"])
    }

    @Test("Disabled diagnostics retain no events or counters")
    func disabledDiagnostics() {
        let diagnostics = PerformanceDiagnostics(arguments: ["Ledger"], environment: [:])
        diagnostics.event("DisabledTest", kind: "test")
        diagnostics.adjustCounter("test-counter", delta: 1)
        var invocationCount = 0
        let result = diagnostics.measureAggregate("DisabledMeasure", kind: "test") {
            invocationCount += 1
            return 42
        }

        #expect(diagnostics.recentEvents().isEmpty)
        #expect(diagnostics.counterValue("test-counter") == 0)
        #expect(invocationCount == 1)
        #expect(result == 42)
    }
}
