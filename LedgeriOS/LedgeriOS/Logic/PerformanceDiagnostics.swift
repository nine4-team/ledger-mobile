import Foundation
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum PerformanceDiagnosticsConfiguration {
    static let argumentName = "-LedgerPerformanceDiagnostics"
    static let environmentName = "LEDGER_PERFORMANCE_DIAGNOSTICS"

    static func isEnabled(arguments: [String], environment: [String: String]) -> Bool {
        if let index = arguments.firstIndex(of: argumentName), arguments.indices.contains(index + 1) {
            return truthy(arguments[index + 1])
        }
        return truthy(environment[environmentName])
    }

    private static func truthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }
}

enum MainThreadStallSeverity: String, Sendable {
    case notice
    case severe
    case critical

    static func classify(milliseconds: Double) -> Self? {
        if milliseconds >= 5_000 { return .critical }
        if milliseconds >= 1_000 { return .severe }
        if milliseconds >= 250 { return .notice }
        return nil
    }
}

struct PerformanceDiagnosticEvent: Sendable, Equatable {
    let timestamp: Date
    let name: String
    let kind: String
    let count: Int
    let value: Int
    let durationMilliseconds: Double?
}

struct PerformanceDiagnosticRingBuffer: Sendable {
    let capacity: Int
    private(set) var events: [PerformanceDiagnosticEvent] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    mutating func append(_ event: PerformanceDiagnosticEvent) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }
}

struct PerformanceDiagnosticInterval: @unchecked Sendable {
    fileprivate let name: StaticString
    fileprivate let kind: String
    fileprivate let count: Int
    fileprivate let signpostID: OSSignpostID
    fileprivate let startedAt: UInt64
}

final class PerformanceDiagnostics: @unchecked Sendable {
    static let shared = PerformanceDiagnostics()

    let isEnabled: Bool

    private let signpostLog = OSLog(subsystem: "apps.nine4.ledger", category: "Performance")
    private let logger = Logger(subsystem: "apps.nine4.ledger", category: "Performance")
    private let lock = NSLock()
    private var ringBuffer = PerformanceDiagnosticRingBuffer(capacity: 500)
    private var counters: [String: Int] = [:]
    private var aggregates: [String: (count: Int, totalMilliseconds: Double, lastFlush: UInt64)] = [:]
    private var scenario = "app-session"
    private var stallMonitor: MainThreadStallMonitor?

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        isEnabled = PerformanceDiagnosticsConfiguration.isEnabled(
            arguments: arguments,
            environment: environment
        )
    }

    func start() {
        guard isEnabled else { return }
        lock.lock()
        if stallMonitor != nil {
            lock.unlock()
            return
        }
        let monitor = MainThreadStallMonitor(diagnostics: self)
        stallMonitor = monitor
        lock.unlock()

        event("DiagnosticsStarted", kind: "app-session")
        monitor.start()
    }

    func setScenario(_ name: String) {
        guard isEnabled else { return }
        let sanitized = Self.sanitizedKind(name)
        lock.lock()
        scenario = sanitized
        lock.unlock()
        event("ScenarioChanged", kind: sanitized)
    }

    func beginInterval(_ name: StaticString, kind: String, count: Int = 0) -> PerformanceDiagnosticInterval? {
        guard isEnabled else { return nil }
        let safeKind = Self.sanitizedKind(kind)
        let id = OSSignpostID(log: signpostLog)
        os_signpost(
            .begin,
            log: signpostLog,
            name: name,
            signpostID: id,
            "kind=%{public}s count=%ld",
            safeKind,
            count
        )
        return PerformanceDiagnosticInterval(
            name: name,
            kind: safeKind,
            count: count,
            signpostID: id,
            startedAt: DispatchTime.now().uptimeNanoseconds
        )
    }

    func endInterval(_ interval: PerformanceDiagnosticInterval?, value: Int = 0) {
        guard isEnabled, let interval else { return }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - interval.startedAt
        let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000
        os_signpost(
            .end,
            log: signpostLog,
            name: interval.name,
            signpostID: interval.signpostID,
            "kind=%{public}s count=%ld value=%ld duration_ms=%.3f",
            interval.kind,
            interval.count,
            value,
            elapsedMilliseconds
        )
        append(
            name: String(describing: interval.name),
            kind: interval.kind,
            count: interval.count,
            value: value,
            durationMilliseconds: elapsedMilliseconds
        )
    }

    func duration(_ name: StaticString, kind: String, milliseconds: Double, count: Int = 0, value: Int = 0) {
        guard isEnabled else { return }
        let safeKind = Self.sanitizedKind(kind)
        os_signpost(
            .event,
            log: signpostLog,
            name: name,
            "kind=%{public}s count=%ld value=%ld duration_ms=%.3f",
            safeKind,
            count,
            value,
            milliseconds
        )
        append(
            name: String(describing: name),
            kind: safeKind,
            count: count,
            value: value,
            durationMilliseconds: milliseconds
        )
    }

    func event(_ name: StaticString, kind: String, count: Int = 0, value: Int = 0) {
        guard isEnabled else { return }
        let safeKind = Self.sanitizedKind(kind)
        os_signpost(
            .event,
            log: signpostLog,
            name: name,
            "kind=%{public}s count=%ld value=%ld",
            safeKind,
            count,
            value
        )
        append(
            name: String(describing: name),
            kind: safeKind,
            count: count,
            value: value,
            durationMilliseconds: nil
        )
    }

    @discardableResult
    func adjustCounter(_ name: String, delta: Int) -> Int {
        guard isEnabled else { return 0 }
        let safeName = Self.sanitizedKind(name)
        lock.lock()
        let updated = max(0, (counters[safeName] ?? 0) + delta)
        counters[safeName] = updated
        lock.unlock()
        event("CounterChanged", kind: safeName, count: updated, value: delta)
        return updated
    }

    func counterValue(_ name: String) -> Int {
        let safeName = Self.sanitizedKind(name)
        lock.lock()
        defer { lock.unlock() }
        return counters[safeName] ?? 0
    }

    func aggregate(_ name: String, kind: String, milliseconds: Double) {
        guard isEnabled else { return }
        let key = Self.sanitizedKind("\(name).\(kind)")
        let now = DispatchTime.now().uptimeNanoseconds
        var flushed: (count: Int, totalMilliseconds: Double)?

        lock.lock()
        var aggregate = aggregates[key] ?? (0, 0, now)
        aggregate.count += 1
        aggregate.totalMilliseconds += milliseconds
        if now - aggregate.lastFlush >= 1_000_000_000 {
            flushed = (aggregate.count, aggregate.totalMilliseconds)
            aggregate = (0, 0, now)
        }
        aggregates[key] = aggregate
        lock.unlock()

        if let flushed {
            duration(
                "AggregatedWork",
                kind: key,
                milliseconds: flushed.totalMilliseconds,
                count: flushed.count
            )
        }
    }

    @inline(__always)
    func measureAggregate<T>(_ name: String, kind: String, operation: () -> T) -> T {
        guard isEnabled else { return operation() }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let result = operation()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        aggregate(name, kind: kind, milliseconds: elapsed)
        return result
    }

    func recentEvents() -> [PerformanceDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return ringBuffer.events
    }

    func currentScenario() -> String {
        lock.lock()
        defer { lock.unlock() }
        return scenario
    }

    private func append(
        name: String,
        kind: String,
        count: Int,
        value: Int,
        durationMilliseconds: Double?
    ) {
        let diagnosticEvent = PerformanceDiagnosticEvent(
            timestamp: Date(),
            name: name,
            kind: kind,
            count: count,
            value: value,
            durationMilliseconds: durationMilliseconds
        )
        lock.lock()
        ringBuffer.append(diagnosticEvent)
        lock.unlock()

        if let durationMilliseconds {
            logger.notice(
                "event=\(name, privacy: .public) kind=\(kind, privacy: .public) count=\(count) value=\(value) duration_ms=\(durationMilliseconds, format: .fixed(precision: 3))"
            )
        } else {
            logger.notice(
                "event=\(name, privacy: .public) kind=\(kind, privacy: .public) count=\(count) value=\(value)"
            )
        }
    }

    private static func sanitizedKind(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        return String(scalars.prefix(80))
    }
}

private final class MainThreadStallMonitor: @unchecked Sendable {
    private weak var diagnostics: PerformanceDiagnostics?
    private let queue = DispatchQueue(label: "apps.nine4.ledger.performance-stall-monitor", qos: .utility)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var heartbeatOutstanding = false
    private var observers: [NSObjectProtocol] = []
    private var applicationIsActive = true
    private var sampleNumber = 0

    init(diagnostics: PerformanceDiagnostics) {
        self.diagnostics = diagnostics
    }

    deinit {
        timer?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func start() {
        installLifecycleObservers()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250), leeway: .milliseconds(25))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        lock.lock()
        guard applicationIsActive, !heartbeatOutstanding else {
            lock.unlock()
            return
        }
        heartbeatOutstanding = true
        sampleNumber += 1
        let shouldSampleMemory = sampleNumber.isMultiple(of: 4)
        lock.unlock()

        let dispatchedAt = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - dispatchedAt) / 1_000_000
            lock.lock()
            heartbeatOutstanding = false
            lock.unlock()

            if let severity = MainThreadStallSeverity.classify(milliseconds: elapsed) {
                diagnostics?.duration(
                    "MainThreadStall",
                    kind: severity.rawValue,
                    milliseconds: elapsed,
                    value: Int(ProcessMemorySampler.physicalFootprintBytes() / 1_048_576)
                )
            }
            if shouldSampleMemory {
                diagnostics?.event(
                    "MemorySample",
                    kind: diagnostics?.currentScenario() ?? "app-session",
                    value: Int(ProcessMemorySampler.physicalFootprintBytes() / 1_048_576)
                )
            }
        }
    }

    private func installLifecycleObservers() {
        #if canImport(UIKit)
        observe(UIApplication.didBecomeActiveNotification, active: true)
        observe(UIApplication.willResignActiveNotification, active: false)
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: nil
            ) { [weak diagnostics] _ in
                diagnostics?.event(
                    "MemoryWarning",
                    kind: diagnostics?.currentScenario() ?? "app-session",
                    value: Int(ProcessMemorySampler.physicalFootprintBytes() / 1_048_576)
                )
            }
        )
        #elseif canImport(AppKit)
        observe(NSApplication.didBecomeActiveNotification, active: true)
        observe(NSApplication.willResignActiveNotification, active: false)
        #endif
    }

    private func observe(_ name: Notification.Name, active: Bool) {
        observers.append(
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.lock.lock()
                self?.applicationIsActive = active
                self?.lock.unlock()
            }
        )
    }
}

enum ProcessMemorySampler {
    static func physicalFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
