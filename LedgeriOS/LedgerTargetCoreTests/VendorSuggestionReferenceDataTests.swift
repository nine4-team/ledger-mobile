import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Vendor Suggestion Reference Read Contracts")
struct VendorSuggestionReferenceDataTests {
    @Test("Ordered suggestions preserve display text and select only source snapshots")
    func exactValuesAndSourceTextSemantics() throws {
        let fixture = try Self.fixture()
        let rows = fixture.snapshot.local.rows

        #expect(rows.map(\.id.rawValue) == [
            "suggestion-home-depot",
            "suggestion-amazon",
            "suggestion-archived"
        ])
        #expect(rows.map(\.presentationOrder) == [1, 2, 3])
        #expect(rows.map(\.revision) == [11, 12, 13])
        #expect(rows[0].displayValue.rawValue == "Home  Depot")
        #expect(rows[0].displayValue.normalizedComparisonKey == "home depot")
        #expect(rows[0].sourceSnapshot == "Home  Depot")
        #expect(rows[0].isSelectable)
        #expect(rows[2].lifecycle == .archived)
        #expect(!rows[2].isSelectable)
        #expect(fixture.snapshot.selectableSourceSnapshots == ["Home  Depot", "Amazon"])
        #expect(fixture.snapshot.local.visibleRowCountBeforeFiltering == rows.count)

        let bytes = try OperationContractCodec.encode(fixture.snapshot)
        let root = try #require(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        #expect(Set(root.keys) == Set(["accountId", "local"]))
        let local = try #require(root["local"] as? [String: Any])
        let encodedRows = try #require(local["rows"] as? [[String: Any]])
        let first = try #require(encodedRows.first)
        #expect(Set(first.keys) == Set([
            "id", "accountId", "displayValue", "lifecycle",
            "presentationOrder", "revision"
        ]))

        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "https://", "file://",
            "bearer", "token", "secret", "serviceaccount", "service_account",
            "vendorid", "vendor_id", "transactionid", "transaction_id",
            "amount", "budget", "role", "capability", "sql"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Ready, partial, stale, and authoritative-empty evidence survives restart")
    func readinessSurvivesCanonicalRestart() throws {
        let fixture = try Self.fixture()
        let first = fixture.snapshot.local.rows[0]
        let partial = try Self.snapshot(
            accountId: fixture.accountId,
            rows: [first],
            quality: .partial,
            isComplete: false,
            fingerprintCharacter: "b",
            version: "vendor-suggestion-partial",
            asOf: Self.t1
        )
        let stale = try Self.snapshot(
            accountId: fixture.accountId,
            rows: [first],
            quality: .stale,
            isComplete: false,
            fingerprintCharacter: "c",
            version: "vendor-suggestion-stale",
            asOf: Self.t2
        )
        let authoritativeEmpty = try Self.snapshot(
            accountId: fixture.accountId,
            rows: [],
            quality: .ready,
            isComplete: true,
            fingerprintCharacter: "d",
            version: "vendor-suggestion-empty",
            asOf: Self.t3
        )
        let restart = RestartFixture(
            ready: fixture.snapshot,
            partial: partial,
            stale: stale,
            authoritativeEmpty: authoritativeEmpty
        )

        let bytes = try OperationContractCodec.encode(restart)
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)

        #expect(restored == restart)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.ready.local.quality == .ready)
        #expect(restored.ready.local.isCompleteForQuery)
        #expect(restored.partial.local.quality == .partial)
        #expect(!restored.partial.local.isCompleteForQuery)
        #expect(restored.stale.local.quality == .stale)
        #expect(!restored.stale.local.isCompleteForQuery)
        #expect(restored.authoritativeEmpty.local.rows.isEmpty)
        #expect(restored.authoritativeEmpty.local.isCompleteForQuery)
        #expect(restored.authoritativeEmpty.selectableSourceSnapshots.isEmpty)
    }

    @Test("Invalid, cross-scope, duplicate, and malformed suggestion evidence fails")
    func invalidSuggestionEvidenceFailsClosed() throws {
        let cleaned = try VendorSuggestionDisplayValue(validating: "  Crate  & Barrel  ")
        #expect(cleaned.rawValue == "Crate  & Barrel")
        #expect(cleaned.normalizedComparisonKey == "crate & barrel")
        for value in [
            "",
            "   ",
            "Home\nDepot",
            String(repeating: "é", count: 101)
        ] {
            #expect(Self.referenceFailure {
                try VendorSuggestionDisplayValue(validating: value)
            } == .invalidDisplayValue)
        }

        let fixture = try Self.fixture()
        let rows = fixture.snapshot.local.rows
        let otherAccount = try AccountID(validating: "account-other")
        let crossAccount = try Self.suggestion(
            id: "suggestion-cross-account",
            accountId: otherAccount,
            value: "Cross Account",
            order: 10,
            revision: 1
        )
        #expect(Self.referenceFailure {
            try Self.snapshot(accountId: fixture.accountId, rows: [crossAccount])
        } == .accountScopeMismatch)

        let duplicateIdentity = try Self.suggestion(
            id: rows[0].id.rawValue,
            accountId: fixture.accountId,
            value: "Different Value",
            order: 10,
            revision: 1
        )
        #expect(Self.referenceFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                rows: [rows[0], duplicateIdentity]
            )
        } == .duplicateSuggestionIdentity)

        let duplicateValue = try Self.suggestion(
            id: "suggestion-duplicate-value",
            accountId: fixture.accountId,
            value: "HOME DEPOT",
            order: 10,
            revision: 1
        )
        #expect(Self.referenceFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                rows: [rows[0], duplicateValue]
            )
        } == .duplicateNormalizedValue)

        let duplicateOrder = try Self.suggestion(
            id: "suggestion-duplicate-order",
            accountId: fixture.accountId,
            value: "Unique Value",
            order: rows[0].presentationOrder,
            revision: 1
        )
        #expect(Self.referenceFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                rows: [rows[0], duplicateOrder]
            )
        } == .duplicatePresentationOrder)

        #expect(Self.referenceFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                rows: [rows[0]],
                visibleCount: 2
            )
        } == .visibleCountMismatch)
        #expect(Self.referenceFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                rows: [rows[0]],
                asOf: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidSnapshotAsOf)

        #expect(Self.listFailure {
            try ListLocalSnapshot<VendorSuggestionSnapshot>(
                queryFingerprint: Self.fingerprint("e"),
                rows: [],
                visibleRowCountBeforeFiltering: 0,
                isCompleteForQuery: true,
                quality: .partial,
                localDataVersion: LocalDataVersion(
                    validating: "vendor-suggestion-invalid-local"
                ),
                asOf: Self.t3
            )
        } == .incompleteAuthoritativeEmpty)

        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                VendorSuggestionDisplayValue.self,
                from: Data("123".utf8)
            )
        } == .invalidEncodedDisplayValue)

        let suggestionBytes = try OperationContractCodec.encode(rows[0])
        let unknownLifecycle = Data(
            String(decoding: suggestionBytes, as: UTF8.self)
                .replacingOccurrences(of: #""lifecycle":"active""#, with: #""lifecycle":"unknown""#)
                .utf8
        )
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                VendorSuggestionSnapshot.self,
                from: unknownLifecycle
            )
        } == .invalidEncodedSuggestion)
        let negativeRevision = Data(
            String(decoding: suggestionBytes, as: UTF8.self)
                .replacingOccurrences(of: #""revision":11"#, with: #""revision":-1"#)
                .utf8
        )
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                VendorSuggestionSnapshot.self,
                from: negativeRevision
            )
        } == .invalidEncodedSuggestion)
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                VendorSuggestionReferenceSnapshot.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedSnapshot)

        let diagnostics: [(VendorSuggestionReferenceFailure, String)] = [
            (.invalidDisplayValue, "vendor_suggestion_display_value_invalid"),
            (.accountScopeMismatch, "vendor_suggestion_account_scope_mismatch"),
            (.duplicateSuggestionIdentity, "vendor_suggestion_identity_duplicate"),
            (
                .duplicateNormalizedValue,
                "vendor_suggestion_normalized_value_duplicate"
            ),
            (.duplicatePresentationOrder, "vendor_suggestion_order_duplicate"),
            (.visibleCountMismatch, "vendor_suggestion_visible_count_mismatch"),
            (.invalidSnapshotAsOf, "vendor_suggestion_as_of_invalid"),
            (.localReadFailed, "vendor_suggestion_local_read_failed"),
            (
                .invalidEncodedDisplayValue,
                "vendor_suggestion_display_value_encoding_invalid"
            ),
            (.invalidEncodedSuggestion, "vendor_suggestion_encoding_invalid"),
            (.invalidEncodedSnapshot, "vendor_suggestion_snapshot_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The query port streams only its exact Account snapshot")
    func queryPortIsAccountExactAndFailureSafe() async throws {
        let fixture = try Self.fixture()
        let port = FixtureVendorSuggestionPort(snapshot: fixture.snapshot)
        var received: [VendorSuggestionReferenceSnapshot] = []
        for try await snapshot in port.watchVendorSuggestions(accountId: fixture.accountId) {
            received.append(snapshot)
        }
        #expect(received == [fixture.snapshot])

        let otherAccount = try AccountID(validating: "account-other")
        var mismatchedRows: [VendorSuggestionReferenceSnapshot] = []
        var mismatchFailure: VendorSuggestionReferenceFailure?
        do {
            for try await snapshot in port.watchVendorSuggestions(accountId: otherAccount) {
                mismatchedRows.append(snapshot)
            }
        } catch let failure as VendorSuggestionReferenceFailure {
            mismatchFailure = failure
        }
        #expect(mismatchedRows.isEmpty)
        #expect(mismatchFailure == .accountScopeMismatch)

        let failing = FailingVendorSuggestionPort()
        var falseSnapshots: [VendorSuggestionReferenceSnapshot] = []
        var localFailure: VendorSuggestionReferenceFailure?
        do {
            for try await snapshot in failing.watchVendorSuggestions(
                accountId: fixture.accountId
            ) {
                falseSnapshots.append(snapshot)
            }
        } catch let failure as VendorSuggestionReferenceFailure {
            localFailure = failure
        }
        #expect(falseSnapshots.isEmpty)
        #expect(localFailure == .localReadFailed)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_900_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_900_001)
    private static let t2 = Date(timeIntervalSince1970: 1_800_900_002)
    private static let t3 = Date(timeIntervalSince1970: 1_800_900_003)

    private struct Fixture {
        let accountId: AccountID
        let snapshot: VendorSuggestionReferenceSnapshot
    }

    private struct RestartFixture: Codable, Equatable, Sendable {
        let ready: VendorSuggestionReferenceSnapshot
        let partial: VendorSuggestionReferenceSnapshot
        let stale: VendorSuggestionReferenceSnapshot
        let authoritativeEmpty: VendorSuggestionReferenceSnapshot
    }

    private static func fixture() throws -> Fixture {
        let accountId = try AccountID(validating: "account-vendor-suggestions")
        let rows = [
            try suggestion(
                id: "suggestion-archived",
                accountId: accountId,
                value: "Former Vendor",
                lifecycle: .archived,
                order: 3,
                revision: 13
            ),
            try suggestion(
                id: "suggestion-amazon",
                accountId: accountId,
                value: "Amazon",
                order: 2,
                revision: 12
            ),
            try suggestion(
                id: "suggestion-home-depot",
                accountId: accountId,
                value: "  Home  Depot  ",
                order: 1,
                revision: 11
            )
        ]
        return Fixture(
            accountId: accountId,
            snapshot: try snapshot(accountId: accountId, rows: rows)
        )
    }

    private static func suggestion(
        id: String,
        accountId: AccountID,
        value: String,
        lifecycle: DirectoryLifecycleState = .active,
        order: UInt32,
        revision: UInt64
    ) throws -> VendorSuggestionSnapshot {
        VendorSuggestionSnapshot(
            id: try VendorSuggestionID(validating: id),
            accountId: accountId,
            displayValue: try VendorSuggestionDisplayValue(validating: value),
            lifecycle: lifecycle,
            presentationOrder: order,
            revision: revision
        )
    }

    private static func snapshot(
        accountId: AccountID,
        rows: [VendorSuggestionSnapshot],
        visibleCount: Int? = nil,
        quality: ListSnapshotQuality = .ready,
        isComplete: Bool = true,
        fingerprintCharacter: Character = "a",
        version: String = "vendor-suggestion-ready",
        asOf: Date = t0
    ) throws -> VendorSuggestionReferenceSnapshot {
        try VendorSuggestionReferenceSnapshot(
            accountId: accountId,
            local: ListLocalSnapshot(
                queryFingerprint: fingerprint(fingerprintCharacter),
                rows: rows,
                visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
                isCompleteForQuery: isComplete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: asOf
            )
        )
    }

    private static func fingerprint(_ character: Character) throws -> ListQueryFingerprint {
        try ListQueryFingerprint(validating: String(repeating: character, count: 64))
    }

    private static func referenceFailure<T>(
        _ operation: () throws -> T
    ) -> VendorSuggestionReferenceFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as VendorSuggestionReferenceFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func listFailure<T>(
        _ operation: () throws -> T
    ) -> ListQueryContractFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ListQueryContractFailure {
            return failure
        } catch {
            return nil
        }
    }
}

private struct FixtureVendorSuggestionPort: VendorSuggestionQuerying {
    let snapshot: VendorSuggestionReferenceSnapshot

    func watchVendorSuggestions(
        accountId: AccountID
    ) -> AsyncThrowingStream<VendorSuggestionReferenceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            guard accountId == snapshot.accountId else {
                continuation.finish(
                    throwing: VendorSuggestionReferenceFailure.accountScopeMismatch
                )
                return
            }
            continuation.yield(snapshot)
            continuation.finish()
        }
    }
}

private struct FailingVendorSuggestionPort: VendorSuggestionQuerying {
    func watchVendorSuggestions(
        accountId: AccountID
    ) -> AsyncThrowingStream<VendorSuggestionReferenceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: VendorSuggestionReferenceFailure.localReadFailed
            )
        }
    }
}
