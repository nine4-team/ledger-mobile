import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Budget Segment Read Contracts")
struct ProjectBudgetSegmentDataTests {
    @Test("Requests bind all scope and signed segments derive recognized once")
    func exactScopeAndArithmetic() throws {
        let fixture = try Self.fixture()
        let rows = fixture.ready.local.rows
        #expect(rows.map(\.category.id.rawValue) == ["paid", "zero", "negative"])
        #expect(rows.map(\.clientPaid.minorUnits) == [1_000, -500, -750])
        #expect(rows.map(\.invoicingUnpaid.minorUnits) == [250, 500, 100])
        #expect(rows.map(\.recognized.minorUnits) == [1_250, 0, -650])
        #expect(rows.map(\.recognized.sign) == [.positive, .zero, .negative])

        let before = try Self.segment("collection", order: 40, paid: 0, unpaid: 2_400)
        let after = try Self.segment("collection", order: 40, paid: 2_400, unpaid: 0)
        #expect(before.recognized == after.recognized)
        #expect(after.recognized.minorUnits == 2_400)

        let requests = try [
            Self.request(),
            Self.request(account: "other-account"),
            Self.request(project: "other-project"),
            Self.request(currency: "EUR")
        ]
        #expect(requests[0] == fixture.request)
        #expect(Set(requests.map(\.queryFingerprint)).count == requests.count)
    }

    @Test("Readiness states and reordered input restart byte-identically")
    func canonicalRestart() throws {
        let fixture = try Self.fixture()
        let first = fixture.ready.local.rows[0]
        let reordered = try Self.snapshot(
            Array(fixture.ready.local.rows.reversed()),
            revision: 51,
            version: "ready"
        )
        #expect(reordered == fixture.ready)
        #expect(try OperationContractCodec.encode(reordered) == OperationContractCodec.encode(fixture.ready))

        let states = try [
            fixture.ready,
            Self.snapshot([], revision: 52, version: "empty", date: Self.t1),
            Self.snapshot([], revision: 53, complete: false, version: "empty-incomplete", date: Self.t2),
            Self.snapshot([first], revision: 54, quality: .partial, complete: false, version: "partial", date: Self.t3),
            Self.snapshot([first], revision: 55, quality: .stale, complete: false, version: "stale", date: Self.t4)
        ]
        let bytes = try OperationContractCodec.encode(RestartFixture(states: states))
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)
        #expect(restored.states == states)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.states.map(\.accountingProjectionRevision) == [51, 52, 53, 54, 55])
        #expect(restored.states.map(\.local.localDataVersion.rawValue) == [
            "ready", "empty", "empty-incomplete", "partial", "stale"
        ])
        #expect(restored.states[1].local.rows.isEmpty && restored.states[1].local.isCompleteForQuery)
        #expect(restored.states[2].local.rows.isEmpty && !restored.states[2].local.isCompleteForQuery)
        #expect(restored.states[2].local.quality == .ready)
        #expect(restored.states[3].local.quality == .partial && !restored.states[3].local.isCompleteForQuery)
        #expect(restored.states[4].local.quality == .stale && !restored.states[4].local.isCompleteForQuery)
    }

    @Test("Invalid, inconsistent, and rebound evidence fails through bounded diagnostics")
    func refusalAndTamperCases() throws {
        let fixture = try Self.fixture()
        let first = fixture.ready.local.rows[0]
        let crossAccount = try Self.segment("cross", account: "other-account", order: 40)
        let euro = try Self.segment("euro", order: 41, currency: "EUR")
        let duplicateOrder = try Self.segment("same-order", order: first.category.presentationOrder)

        #expect(Self.failure { try Self.snapshot([crossAccount]) } == .accountScopeMismatch)
        #expect(Self.failure { try Self.snapshot([euro]) } == .currencyMismatch)
        #expect(Self.failure {
            try ProjectBudgetCategorySegment(
                category: first.category,
                clientPaid: Self.money(1),
                invoicingUnpaid: Self.money(1, currency: "EUR")
            )
        } == .currencyMismatch)
        #expect(Self.failure {
            try ProjectBudgetCategorySegment(
                category: first.category,
                clientPaid: Self.money(.max),
                invoicingUnpaid: Self.money(1)
            )
        } == .arithmeticOverflow)
        #expect(Self.failure { try Self.snapshot([first, first]) } == .duplicateCategoryIdentity)
        #expect(Self.failure { try Self.snapshot([first, duplicateOrder]) } == .duplicatePresentationOrder)
        #expect(Self.failure { try Self.snapshot([first], visibleCount: 2) } == .visibleCountMismatch)
        #expect(Self.failure {
            try Self.snapshot([first], date: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidSnapshotAsOf)
        #expect(Self.failure { try Self.snapshot([first], revision: 0) } == .invalidAccountingProjectionRevision)

        let wrongFingerprint = try ListQueryFingerprint(validating: String(repeating: "a", count: 64))
        #expect(Self.failure {
            try ProjectBudgetSegmentSnapshot(
                request: fixture.request,
                accountingProjectionRevision: 1,
                local: Self.local([first], fingerprint: wrongFingerprint)
            )
        } == .queryFingerprintMismatch)
        #expect(Self.listFailure {
            try Self.local([], quality: .partial, complete: true)
        } == .incompleteAuthoritativeEmpty)

        #expect(Self.decodeFailure(ProjectBudgetSegmentRequest.self, Data("{}".utf8)) == .invalidEncodedRequest)
        #expect(Self.decodeFailure(ProjectBudgetCategorySegment.self, Data("{}".utf8)) == .invalidEncodedSegment)
        #expect(Self.decodeFailure(ProjectBudgetSegmentSnapshot.self, Data("{}".utf8)) == .invalidEncodedSnapshot)

        let requestBytes = try OperationContractCodec.encode(fixture.request)
        let badFingerprint = try Self.mutate(requestBytes) {
            $0["queryFingerprint"] = String(repeating: "b", count: 64)
        }
        #expect(Self.decodeFailure(ProjectBudgetSegmentRequest.self, badFingerprint) == .requestFingerprintMismatch)

        let snapshotBytes = try OperationContractCodec.encode(fixture.ready)
        let badRecognized = try Self.mutate(snapshotBytes) { root in
            var local = root["local"] as! [String: Any]
            var rows = local["rows"] as! [[String: Any]]
            var recognized = rows[0]["recognized"] as! [String: Any]
            recognized["minorUnits"] = 99_999
            rows[0]["recognized"] = recognized
            local["rows"] = rows
            root["local"] = local
        }
        #expect(Self.decodeFailure(ProjectBudgetSegmentSnapshot.self, badRecognized) == .recognizedValueMismatch)
        let rebound = try Self.mutate(snapshotBytes) { root in
            var request = root["request"] as! [String: Any]
            request["projectId"] = "rebound-project"
            root["request"] = request
        }
        #expect(Self.decodeFailure(ProjectBudgetSegmentSnapshot.self, rebound) == .requestFingerprintMismatch)

        let diagnostics: [(ProjectBudgetSegmentFailure, String)] = [
            (.accountScopeMismatch, "account_scope_mismatch"),
            (.projectScopeMismatch, "project_scope_mismatch"),
            (.currencyMismatch, "currency_mismatch"),
            (.duplicateCategoryIdentity, "category_identity_duplicate"),
            (.duplicatePresentationOrder, "category_order_duplicate"),
            (.visibleCountMismatch, "visible_count_mismatch"),
            (.invalidSnapshotAsOf, "as_of_invalid"),
            (.invalidAccountingProjectionRevision, "accounting_projection_revision_invalid"),
            (.arithmeticOverflow, "arithmetic_overflow"),
            (.recognizedValueMismatch, "recognized_value_mismatch"),
            (.requestFingerprintMismatch, "request_fingerprint_mismatch"),
            (.queryFingerprintMismatch, "query_fingerprint_mismatch"),
            (.localReadFailed, "local_read_failed"),
            (.invalidEncodedRequest, "request_encoding_invalid"),
            (.invalidEncodedSegment, "row_encoding_invalid"),
            (.invalidEncodedSnapshot, "snapshot_encoding_invalid")
        ]
        for (failure, suffix) in diagnostics {
            #expect(failure.diagnosticCode == "project_budget_segment_\(suffix)")
            #expect(failure.diagnosticCode.utf8.count <= 80)
        }
    }

    @Test("The port is request-exact and failure never yields a false snapshot")
    func exactPortAndUpstreamFailure() async throws {
        let fixture = try Self.fixture()
        let port = FixturePort(snapshot: fixture.ready)
        let exact = await Self.collect(port, fixture.request)
        #expect(exact.snapshots == [fixture.ready] && exact.failure == nil)

        let mismatches = try [
            (Self.request(account: "other-account"), ProjectBudgetSegmentFailure.accountScopeMismatch),
            (Self.request(project: "other-project"), .projectScopeMismatch),
            (Self.request(currency: "EUR"), .currencyMismatch)
        ]
        for (request, expected) in mismatches {
            let result = await Self.collect(port, request)
            #expect(result.snapshots.isEmpty && result.failure == expected)
        }

        let failed = await Self.collect(FailingPort(), fixture.request)
        #expect(failed.snapshots.isEmpty && failed.failure == .localReadFailed)
    }

    @Test("Cancellation stops delivery and encoding stays inside the frozen boundary")
    func cancellationAndContractShape() async throws {
        let fixture = try Self.fixture()
        let probe = CancellationProbe()
        let port = CancellablePort(snapshot: fixture.ready, probe: probe)
        let consumer = Task { () -> [ProjectBudgetSegmentSnapshot] in
            var snapshots: [ProjectBudgetSegmentSnapshot] = []
            do {
                for try await snapshot in port.watchProjectBudgetSegments(fixture.request) {
                    snapshots.append(snapshot)
                    await probe.markFirstDelivery()
                }
            } catch {}
            return snapshots
        }
        await probe.waitForFirstDelivery()
        consumer.cancel()
        #expect(await consumer.value == [fixture.ready])
        await probe.waitForCancellation()

        let bytes = try OperationContractCodec.encode(fixture.ready)
        let root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(root.keys) == ["request", "accountingProjectionRevision", "local"])
        let request = try #require(root["request"] as? [String: Any])
        #expect(Set(request.keys) == ["accountId", "projectId", "currency", "queryFingerprint"])
        let local = try #require(root["local"] as? [String: Any])
        let row = try #require((local["rows"] as? [[String: Any]])?.first)
        #expect(Set(row.keys) == ["category", "clientPaid", "invoicingUnpaid", "recognized"])
        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "token", "secret",
            "authorized", "attachment", "media", "transaction", "invoiceid",
            "contribution", "sourcekind", "budgetlimit", "remaining", "overbudget",
            "percentage", "settlement", "sql"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_000_001)
    private static let t2 = Date(timeIntervalSince1970: 1_802_000_002)
    private static let t3 = Date(timeIntervalSince1970: 1_802_000_003)
    private static let t4 = Date(timeIntervalSince1970: 1_802_000_004)

    private struct Fixture {
        let request: ProjectBudgetSegmentRequest
        let ready: ProjectBudgetSegmentSnapshot
    }

    private struct RestartFixture: Codable, Equatable, Sendable {
        let states: [ProjectBudgetSegmentSnapshot]
    }

    private static func fixture() throws -> Fixture {
        let rows = try [
            segment("negative", order: 30, paid: -750, unpaid: 100),
            segment("paid", order: 10, paid: 1_000, unpaid: 250),
            segment("zero", order: 20, paid: -500, unpaid: 500)
        ]
        return try Fixture(request: request(), ready: snapshot(rows, revision: 51, version: "ready"))
    }

    private static func request(
        account: String = "budget-account",
        project: String = "budget-project",
        currency: String = "USD"
    ) throws -> ProjectBudgetSegmentRequest {
        try ProjectBudgetSegmentRequest(
            accountId: AccountID(validating: account),
            projectId: ProjectID(validating: project),
            currency: CurrencyCode(validating: currency)
        )
    }

    private static func money(_ minorUnits: Int64, currency: String = "USD") throws -> Money {
        try Money(minorUnits: minorUnits, currency: CurrencyCode(validating: currency))
    }

    private static func segment(
        _ id: String,
        account: String = "budget-account",
        order: UInt32,
        paid: Int64 = 1,
        unpaid: Int64 = 2,
        currency: String = "USD"
    ) throws -> ProjectBudgetCategorySegment {
        try ProjectBudgetCategorySegment(
            category: BudgetCategoryDefinitionSnapshot(
                id: BudgetCategoryID(validating: id),
                accountId: AccountID(validating: account),
                name: BudgetCategoryName(validating: id),
                kind: .itemized,
                lifecycle: .active,
                isSystem: false,
                excludesFromOverallBudget: false,
                presentationOrder: order,
                revision: UInt64(order) + 1
            ),
            clientPaid: money(paid, currency: currency),
            invoicingUnpaid: money(unpaid, currency: currency)
        )
    }

    private static func local(
        _ rows: [ProjectBudgetCategorySegment],
        fingerprint: ListQueryFingerprint? = nil,
        visibleCount: Int? = nil,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String = "test",
        date: Date = t0
    ) throws -> ListLocalSnapshot<ProjectBudgetCategorySegment> {
        let request = try request()
        return try ListLocalSnapshot(
            queryFingerprint: fingerprint ?? request.queryFingerprint,
            rows: rows,
            visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: date
        )
    }

    private static func snapshot(
        _ rows: [ProjectBudgetCategorySegment],
        visibleCount: Int? = nil,
        revision: UInt64 = 1,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String = "test",
        date: Date = t0
    ) throws -> ProjectBudgetSegmentSnapshot {
        let request = try request()
        return try ProjectBudgetSegmentSnapshot(
            request: request,
            accountingProjectionRevision: revision,
            local: local(
                rows,
                visibleCount: visibleCount,
                quality: quality,
                complete: complete,
                version: version,
                date: date
            )
        )
    }

    private static func failure<Value>(_ body: () throws -> Value) -> ProjectBudgetSegmentFailure? {
        do { _ = try body(); return nil }
        catch let failure as ProjectBudgetSegmentFailure { return failure }
        catch { return nil }
    }

    private static func listFailure<Value>(_ body: () throws -> Value) -> ListQueryContractFailure? {
        do { _ = try body(); return nil }
        catch let failure as ListQueryContractFailure { return failure }
        catch { return nil }
    }

    private static func decodeFailure<Value: Decodable>(
        _ type: Value.Type,
        _ bytes: Data
    ) -> ProjectBudgetSegmentFailure? {
        failure { try OperationContractCodec.decode(type, from: bytes) }
    }

    private static func mutate(
        _ bytes: Data,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        body(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func collect<Port: ProjectBudgetSegmentQuerying>(
        _ port: Port,
        _ request: ProjectBudgetSegmentRequest
    ) async -> (snapshots: [ProjectBudgetSegmentSnapshot], failure: ProjectBudgetSegmentFailure?) {
        var snapshots: [ProjectBudgetSegmentSnapshot] = []
        do {
            for try await snapshot in port.watchProjectBudgetSegments(request) {
                snapshots.append(snapshot)
            }
            return (snapshots, nil)
        } catch let failure as ProjectBudgetSegmentFailure {
            return (snapshots, failure)
        } catch {
            return (snapshots, nil)
        }
    }
}

private struct FixturePort: ProjectBudgetSegmentQuerying {
    let snapshot: ProjectBudgetSegmentSnapshot

    func watchProjectBudgetSegments(
        _ request: ProjectBudgetSegmentRequest
    ) -> AsyncThrowingStream<ProjectBudgetSegmentSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let expected = snapshot.request
            if request.accountId != expected.accountId {
                continuation.finish(throwing: ProjectBudgetSegmentFailure.accountScopeMismatch)
            } else if request.projectId != expected.projectId {
                continuation.finish(throwing: ProjectBudgetSegmentFailure.projectScopeMismatch)
            } else if request.currency != expected.currency {
                continuation.finish(throwing: ProjectBudgetSegmentFailure.currencyMismatch)
            } else if request != expected {
                continuation.finish(throwing: ProjectBudgetSegmentFailure.requestFingerprintMismatch)
            } else {
                continuation.yield(snapshot)
                continuation.finish()
            }
        }
    }
}

private struct FailingPort: ProjectBudgetSegmentQuerying {
    func watchProjectBudgetSegments(
        _ request: ProjectBudgetSegmentRequest
    ) -> AsyncThrowingStream<ProjectBudgetSegmentSnapshot, Error> {
        AsyncThrowingStream { $0.finish(throwing: ProjectBudgetSegmentFailure.localReadFailed) }
    }
}

private struct CancellablePort: ProjectBudgetSegmentQuerying {
    let snapshot: ProjectBudgetSegmentSnapshot
    let probe: CancellationProbe

    func watchProjectBudgetSegments(
        _ request: ProjectBudgetSegmentRequest
    ) -> AsyncThrowingStream<ProjectBudgetSegmentSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                continuation.yield(snapshot)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard !Task.isCancelled else { return }
                continuation.yield(snapshot)
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
                Task { await probe.markCancelled() }
            }
        }
    }
}

private actor CancellationProbe {
    private var deliveredFirst = false
    private var cancelled = false
    private var firstWaiter: CheckedContinuation<Void, Never>?
    private var cancellationWaiter: CheckedContinuation<Void, Never>?

    func markFirstDelivery() {
        deliveredFirst = true
        firstWaiter?.resume()
        firstWaiter = nil
    }

    func waitForFirstDelivery() async {
        guard !deliveredFirst else { return }
        await withCheckedContinuation { firstWaiter = $0 }
    }

    func markCancelled() {
        cancelled = true
        cancellationWaiter?.resume()
        cancellationWaiter = nil
    }

    func waitForCancellation() async {
        guard !cancelled else { return }
        await withCheckedContinuation { cancellationWaiter = $0 }
    }
}
