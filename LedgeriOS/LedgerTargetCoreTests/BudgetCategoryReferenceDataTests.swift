import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Budget Category Reference Read Contracts")
struct BudgetCategoryReferenceDataTests {
    @Test("Visible category definitions preserve exact kind, order, and eligibility")
    func definitionsAndEligibilityAreExact() throws {
        let fixture = try Self.fixture()
        let rows = fixture.snapshot.local.rows

        #expect(BudgetCategoryKind.allCases == [.general, .itemized, .fee])
        #expect(rows.map(\.id.rawValue) == [
            "category-furnishings",
            "category-install",
            "category-design-fee",
            "category-system-adjustment",
            "category-archived-itemized"
        ])
        #expect(rows.map(\.presentationOrder) == [1, 2, 3, 4, 5])
        #expect(rows[0].kind == .itemized)
        #expect(rows[0].isSelectableForProjectConfiguration)
        #expect(rows[0].isSelectableForItemizedProjectWorkflow)
        #expect(rows[1].kind == .general)
        #expect(rows[1].isSelectableForProjectConfiguration)
        #expect(!rows[1].isSelectableForItemizedProjectWorkflow)
        #expect(rows[2].kind == .fee)
        #expect(rows[2].excludesFromOverallBudget)
        #expect(rows[2].isSelectableForProjectConfiguration)
        #expect(!rows[2].isSelectableForItemizedProjectWorkflow)
        #expect(rows[3].isSystem)
        #expect(!rows[3].isSelectableForProjectConfiguration)
        #expect(!rows[4].isSelectableForProjectConfiguration)
        #expect(rows[4].lifecycle == .archived)
        #expect(fixture.snapshot.local.visibleRowCountBeforeFiltering == rows.count)

        let text = String(
            decoding: try OperationContractCodec.encode(fixture.snapshot),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "https://", "file://",
            "bearer", "token", "secret", "serviceaccount", "service_account",
            "authorized", "authorization", "hiddenrow", "hidden_row", "sql"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Ready, partial, stale, and authorized-empty evidence survives restart")
    func readinessSurvivesCanonicalRestart() throws {
        let fixture = try Self.fixture()
        let first = fixture.snapshot.local.rows[0]
        let partial = try Self.snapshot(
            accountId: fixture.accountId,
            rows: [first],
            quality: .partial,
            isComplete: false,
            fingerprintCharacter: "b",
            version: "category-local-partial",
            asOf: Self.t1
        )
        let stale = try Self.snapshot(
            accountId: fixture.accountId,
            rows: [first],
            quality: .stale,
            isComplete: false,
            fingerprintCharacter: "c",
            version: "category-local-stale",
            asOf: Self.t2
        )
        let authoritativeEmpty = try Self.snapshot(
            accountId: fixture.accountId,
            rows: [],
            quality: .ready,
            isComplete: true,
            fingerprintCharacter: "d",
            version: "category-local-empty",
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
        #expect(restored.authoritativeEmpty.local.rows.isEmpty)
        #expect(restored.authoritativeEmpty.local.isCompleteForQuery)
        #expect(restored.authoritativeEmpty.local.visibleRowCountBeforeFiltering == 0)
    }

    @Test("Invalid, cross-scope, duplicate, and malformed reference evidence fails")
    func invalidReferenceEvidenceFailsClosed() throws {
        #expect(try BudgetCategoryName(validating: "  Install  ").rawValue == "Install")
        for name in ["", " \n\t ", "Install\u{0007}", String(repeating: "a", count: 101)] {
            #expect(Self.referenceFailure {
                try BudgetCategoryName(validating: name)
            } == .invalidName)
        }

        let fixture = try Self.fixture()
        let rows = fixture.snapshot.local.rows
        let otherAccount = try AccountID(validating: "account-other")
        let crossAccount = try Self.category(
            id: "category-cross-account",
            accountId: otherAccount,
            name: "Cross Account",
            order: 10
        )
        #expect(Self.referenceFailure {
            try Self.snapshot(accountId: fixture.accountId, rows: [crossAccount])
        } == .accountScopeMismatch)

        let duplicateIdentity = try Self.category(
            id: rows[0].id.rawValue,
            accountId: fixture.accountId,
            name: "Different Name",
            order: 10
        )
        #expect(Self.referenceFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                rows: [rows[0], duplicateIdentity]
            )
        } == .duplicateCategoryIdentity)

        let duplicateName = try Self.category(
            id: "category-duplicate-name",
            accountId: fixture.accountId,
            name: rows[0].name.rawValue.uppercased(),
            order: 10
        )
        #expect(Self.referenceFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                rows: [rows[0], duplicateName]
            )
        } == .duplicateCategoryName)

        let duplicateOrder = try Self.category(
            id: "category-duplicate-order",
            accountId: fixture.accountId,
            name: "Unique Name",
            order: rows[0].presentationOrder
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
            try ListLocalSnapshot<BudgetCategoryDefinitionSnapshot>(
                queryFingerprint: Self.fingerprint("e"),
                rows: [],
                visibleRowCountBeforeFiltering: 0,
                isCompleteForQuery: true,
                quality: .partial,
                localDataVersion: LocalDataVersion(validating: "category-invalid-local"),
                asOf: Self.t3
            )
        } == .incompleteAuthoritativeEmpty)

        let definitionBytes = try OperationContractCodec.encode(rows[1])
        let unknownKind = Data(
            String(decoding: definitionBytes, as: UTF8.self)
                .replacingOccurrences(of: #""kind":"general""#, with: #""kind":"unknown""#)
                .utf8
        )
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                BudgetCategoryDefinitionSnapshot.self,
                from: unknownKind
            )
        } == .invalidEncodedDefinition)
        let negativeRevision = Data(
            String(decoding: definitionBytes, as: UTF8.self)
                .replacingOccurrences(of: #""revision":1"#, with: #""revision":-1"#)
                .utf8
        )
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                BudgetCategoryDefinitionSnapshot.self,
                from: negativeRevision
            )
        } == .invalidEncodedDefinition)
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                BudgetCategoryDefinitionSnapshot.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDefinition)
        #expect(Self.referenceFailure {
            try OperationContractCodec.decode(
                BudgetCategoryReferenceSnapshot.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedSnapshot)

        let diagnostics: [(BudgetCategoryReferenceFailure, String)] = [
            (.invalidName, "budget_category_reference_name_invalid"),
            (.accountScopeMismatch, "budget_category_reference_account_mismatch"),
            (.duplicateCategoryIdentity, "budget_category_reference_identity_duplicate"),
            (.duplicateCategoryName, "budget_category_reference_name_duplicate"),
            (.duplicatePresentationOrder, "budget_category_reference_order_duplicate"),
            (.visibleCountMismatch, "budget_category_reference_visible_count_mismatch"),
            (.invalidSnapshotAsOf, "budget_category_reference_as_of_invalid"),
            (.localReadFailed, "budget_category_reference_local_read_failed"),
            (
                .invalidEncodedDefinition,
                "budget_category_reference_definition_encoding_invalid"
            ),
            (
                .invalidEncodedSnapshot,
                "budget_category_reference_snapshot_encoding_invalid"
            )
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The reference port returns only its exact Account snapshot")
    func referencePortIsAccountExactAndFailureSafe() async throws {
        let fixture = try Self.fixture()
        let port = FixtureBudgetCategoryReferencePort(snapshot: fixture.snapshot)
        var received: [BudgetCategoryReferenceSnapshot] = []
        for try await snapshot in port.watchBudgetCategories(accountId: fixture.accountId) {
            received.append(snapshot)
        }
        #expect(received == [fixture.snapshot])

        let otherAccount = try AccountID(validating: "account-other")
        var mismatchedRows: [BudgetCategoryReferenceSnapshot] = []
        var mismatchFailure: BudgetCategoryReferenceFailure?
        do {
            for try await snapshot in port.watchBudgetCategories(accountId: otherAccount) {
                mismatchedRows.append(snapshot)
            }
        } catch let failure as BudgetCategoryReferenceFailure {
            mismatchFailure = failure
        }
        #expect(mismatchedRows.isEmpty)
        #expect(mismatchFailure == .accountScopeMismatch)

        let failing = FailingBudgetCategoryReferencePort()
        var falseSnapshots: [BudgetCategoryReferenceSnapshot] = []
        var localFailure: BudgetCategoryReferenceFailure?
        do {
            for try await snapshot in failing.watchBudgetCategories(
                accountId: fixture.accountId
            ) {
                falseSnapshots.append(snapshot)
            }
        } catch let failure as BudgetCategoryReferenceFailure {
            localFailure = failure
        }
        #expect(falseSnapshots.isEmpty)
        #expect(localFailure == .localReadFailed)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_800_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_800_001)
    private static let t2 = Date(timeIntervalSince1970: 1_800_800_002)
    private static let t3 = Date(timeIntervalSince1970: 1_800_800_003)

    private struct Fixture {
        let accountId: AccountID
        let snapshot: BudgetCategoryReferenceSnapshot
    }

    private struct RestartFixture: Codable, Equatable, Sendable {
        let ready: BudgetCategoryReferenceSnapshot
        let partial: BudgetCategoryReferenceSnapshot
        let stale: BudgetCategoryReferenceSnapshot
        let authoritativeEmpty: BudgetCategoryReferenceSnapshot
    }

    private static func fixture() throws -> Fixture {
        let accountId = try AccountID(validating: "account-category-test")
        let categories = [
            try category(
                id: "category-archived-itemized",
                accountId: accountId,
                name: "Archived Furnishings",
                kind: .itemized,
                lifecycle: .archived,
                order: 5,
                revision: 2
            ),
            try category(
                id: "category-system-adjustment",
                accountId: accountId,
                name: "Other Client Charges & Credits",
                isSystem: true,
                order: 4
            ),
            try category(
                id: "category-design-fee",
                accountId: accountId,
                name: "Design Fee",
                kind: .fee,
                excludesFromOverallBudget: true,
                order: 3,
                revision: 8
            ),
            try category(
                id: "category-install",
                accountId: accountId,
                name: "Install",
                order: 2
            ),
            try category(
                id: "category-furnishings",
                accountId: accountId,
                name: "Furnishings",
                kind: .itemized,
                order: 1,
                revision: 12
            )
        ]
        return Fixture(
            accountId: accountId,
            snapshot: try snapshot(accountId: accountId, rows: categories)
        )
    }

    private static func category(
        id: String,
        accountId: AccountID,
        name: String,
        kind: BudgetCategoryKind = .general,
        lifecycle: DirectoryLifecycleState = .active,
        isSystem: Bool = false,
        excludesFromOverallBudget: Bool = false,
        order: UInt32,
        revision: UInt64 = 1
    ) throws -> BudgetCategoryDefinitionSnapshot {
        BudgetCategoryDefinitionSnapshot(
            id: try BudgetCategoryID(validating: id),
            accountId: accountId,
            name: try BudgetCategoryName(validating: name),
            kind: kind,
            lifecycle: lifecycle,
            isSystem: isSystem,
            excludesFromOverallBudget: excludesFromOverallBudget,
            presentationOrder: order,
            revision: revision
        )
    }

    private static func snapshot(
        accountId: AccountID,
        rows: [BudgetCategoryDefinitionSnapshot],
        quality: ListSnapshotQuality = .ready,
        isComplete: Bool = true,
        visibleCount: Int? = nil,
        fingerprintCharacter: Character = "a",
        version: String = "category-local-ready",
        asOf: Date = t0
    ) throws -> BudgetCategoryReferenceSnapshot {
        try BudgetCategoryReferenceSnapshot(
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

    private static func referenceFailure<Value>(
        _ body: () throws -> Value
    ) -> BudgetCategoryReferenceFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as BudgetCategoryReferenceFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func listFailure<Value>(
        _ body: () throws -> Value
    ) -> ListQueryContractFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as ListQueryContractFailure {
            return failure
        } catch {
            return nil
        }
    }
}

private struct FixtureBudgetCategoryReferencePort: BudgetCategoryReferenceQuerying {
    let snapshot: BudgetCategoryReferenceSnapshot

    func watchBudgetCategories(
        accountId: AccountID
    ) -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            guard accountId == snapshot.accountId else {
                continuation.finish(
                    throwing: BudgetCategoryReferenceFailure.accountScopeMismatch
                )
                return
            }
            continuation.yield(snapshot)
            continuation.finish()
        }
    }
}

private struct FailingBudgetCategoryReferencePort: BudgetCategoryReferenceQuerying {
    func watchBudgetCategories(
        accountId: AccountID
    ) -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: BudgetCategoryReferenceFailure.localReadFailed)
        }
    }
}
