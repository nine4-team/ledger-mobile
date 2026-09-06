import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Category Configuration Read Contracts")
struct ProjectCategoryConfigurationDataTests {
    @Test("Visible Project configuration preserves exact relationship and allocation truth")
    func configurationStatesAreExact() throws {
        let fixture = try Self.fixture()
        let rows = fixture.snapshot.local.rows

        #expect(fixture.snapshot.accountId == fixture.accountId)
        #expect(fixture.snapshot.projectId == fixture.projectId)
        #expect(fixture.snapshot.configurationRevision == 9)
        #expect(rows.map { $0.category.presentationOrder } == [1, 2, 3, 4, 5])
        #expect(rows[0].state == .enabledWithAllocation(
            Money(minorUnits: 250_000, currency: fixture.currency)
        ))
        #expect(rows[1].state == .enabledWithAllocation(
            .zero(currency: fixture.currency)
        ))
        #expect(rows[2].state == .enabledWithoutAllocation)
        #expect(rows[3].state == .noRelationship)
        #expect(rows[3].category.lifecycle == .archived)
        #expect(!rows[3].category.isSelectableForProjectConfiguration)
        #expect(rows[4].state == .noRelationship)
        #expect(rows[4].category.isSystem)
        #expect(!rows[4].category.isSelectableForProjectConfiguration)
        #expect(fixture.snapshot.local.visibleRowCountBeforeFiltering == rows.count)

        let text = String(
            decoding: try OperationContractCodec.encode(fixture.snapshot),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "https://", "file://",
            "bearer", "token", "secret", "serviceaccount", "service_account",
            "principal", "membership", "grant", "policy", "sql", "spend", "budgettotal"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Ready, partial, stale, and authoritative-empty evidence survives restart")
    func readinessAndRelationshipEvidenceSurviveRestart() throws {
        let fixture = try Self.fixture()
        let first = fixture.snapshot.local.rows[0]
        let incomplete = try ProjectCategoryConfigurationRow(
            category: fixture.snapshot.local.rows[3].category,
            state: .relationshipEvidenceIncomplete
        )
        let partial = try Self.snapshot(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            rows: [incomplete, first],
            quality: .partial,
            isComplete: false,
            fingerprintCharacter: "b",
            version: "project-category-partial",
            asOf: Self.t1
        )
        let stale = try Self.snapshot(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            rows: [first],
            quality: .stale,
            isComplete: false,
            fingerprintCharacter: "c",
            version: "project-category-stale",
            asOf: Self.t2
        )
        let authoritativeEmpty = try Self.snapshot(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            rows: [],
            quality: .ready,
            isComplete: true,
            fingerprintCharacter: "d",
            version: "project-category-empty",
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
        #expect(restored.ready.local.isCompleteForQuery)
        #expect(restored.ready.local.quality == .ready)
        #expect(restored.partial.local.quality == .partial)
        #expect(!restored.partial.local.isCompleteForQuery)
        #expect(restored.partial.local.rows[1].state == .relationshipEvidenceIncomplete)
        #expect(restored.stale.local.quality == .stale)
        #expect(!restored.stale.local.isCompleteForQuery)
        #expect(restored.authoritativeEmpty.local.rows.isEmpty)
        #expect(restored.authoritativeEmpty.local.isCompleteForQuery)
        #expect(restored.authoritativeEmpty.local.visibleRowCountBeforeFiltering == 0)
    }

    @Test("Invalid allocation, scope, identity, count, and completeness fail atomically")
    func invalidConfigurationEvidenceFailsClosed() throws {
        let fixture = try Self.fixture()
        let rows = fixture.snapshot.local.rows
        let negative = Money(minorUnits: -1, currency: fixture.currency)
        #expect(Self.configurationFailure {
            try ProjectCategoryConfigurationRow(
                category: rows[0].category,
                state: .enabledWithAllocation(negative)
            )
        } == .negativeAllocation)
        #expect(Self.configurationFailure {
            try OperationContractCodec.decode(
                ProjectCategoryConfigurationState.self,
                from: Data(
                    #"{"allocation":{"currency":"USD","minorUnits":-1},"kind":"enabledWithAllocation"}"#.utf8
                )
            )
        } == .negativeAllocation)
        #expect(Self.configurationFailure {
            try OperationContractCodec.decode(
                ProjectCategoryConfigurationState.self,
                from: Data(
                    #"{"allocation":{"currency":"usd","minorUnits":1},"kind":"enabledWithAllocation"}"#.utf8
                )
            )
        } == .invalidEncodedState)
        #expect(Self.configurationFailure {
            try OperationContractCodec.decode(
                ProjectCategoryConfigurationState.self,
                from: Data(#"{"kind":"unknown"}"#.utf8)
            )
        } == .invalidEncodedState)
        #expect(Self.configurationFailure {
            try OperationContractCodec.decode(
                ProjectCategoryConfigurationState.self,
                from: Data(
                    #"{"allocation":{"currency":"USD","minorUnits":0},"kind":"noRelationship"}"#.utf8
                )
            )
        } == .invalidEncodedState)

        let otherAccount = try AccountID(validating: "account-other")
        let crossAccount = try Self.row(
            id: "category-cross-account",
            accountId: otherAccount,
            name: "Cross Account",
            order: 10,
            state: .enabledWithoutAllocation
        )
        #expect(Self.configurationFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: [crossAccount]
            )
        } == .categoryAccountScopeMismatch)

        let duplicateIdentity = try Self.row(
            id: rows[0].category.id.rawValue,
            accountId: fixture.accountId,
            name: "Different Name",
            order: 10,
            state: .enabledWithoutAllocation
        )
        #expect(Self.configurationFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: [rows[0], duplicateIdentity]
            )
        } == .duplicateCategoryIdentity)

        let duplicateName = try Self.row(
            id: "category-duplicate-name",
            accountId: fixture.accountId,
            name: rows[0].category.name.rawValue.uppercased(),
            order: 10,
            state: .enabledWithoutAllocation
        )
        #expect(Self.configurationFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: [rows[0], duplicateName]
            )
        } == .duplicateCategoryName)

        let duplicateOrder = try Self.row(
            id: "category-duplicate-order",
            accountId: fixture.accountId,
            name: "Unique Name",
            order: rows[0].category.presentationOrder,
            state: .enabledWithoutAllocation
        )
        #expect(Self.configurationFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: [rows[0], duplicateOrder]
            )
        } == .duplicatePresentationOrder)

        #expect(Self.configurationFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: [rows[0]],
                visibleCount: 2
            )
        } == .visibleCountMismatch)
        #expect(Self.configurationFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: [rows[3]],
                quality: .partial,
                isComplete: false
            )
        } == .relationshipCompletenessMismatch)

        let incomplete = try ProjectCategoryConfigurationRow(
            category: rows[3].category,
            state: .relationshipEvidenceIncomplete
        )
        #expect(Self.configurationFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: [incomplete]
            )
        } == .relationshipCompletenessMismatch)
        #expect(Self.configurationFailure {
            try Self.snapshot(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: [rows[0]],
                asOf: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidSnapshotAsOf)

        #expect(Self.configurationFailure {
            try OperationContractCodec.decode(
                ProjectCategoryConfigurationRow.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedRow)
        #expect(Self.configurationFailure {
            try OperationContractCodec.decode(
                ProjectCategoryConfigurationSnapshot.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedSnapshot)

        let snapshotBytes = try OperationContractCodec.encode(fixture.snapshot)
        let negativeRevision = Data(
            String(decoding: snapshotBytes, as: UTF8.self)
                .replacingOccurrences(
                    of: #""configurationRevision":9"#,
                    with: #""configurationRevision":-1"#
                )
                .utf8
        )
        #expect(Self.configurationFailure {
            try OperationContractCodec.decode(
                ProjectCategoryConfigurationSnapshot.self,
                from: negativeRevision
            )
        } == .invalidEncodedSnapshot)

        let diagnostics: [(ProjectCategoryConfigurationFailure, String)] = [
            (.negativeAllocation, "project_category_configuration_allocation_negative"),
            (
                .categoryAccountScopeMismatch,
                "project_category_configuration_category_account_mismatch"
            ),
            (.duplicateCategoryIdentity, "project_category_configuration_identity_duplicate"),
            (.duplicateCategoryName, "project_category_configuration_name_duplicate"),
            (.duplicatePresentationOrder, "project_category_configuration_order_duplicate"),
            (.visibleCountMismatch, "project_category_configuration_visible_count_mismatch"),
            (
                .relationshipCompletenessMismatch,
                "project_category_configuration_relationship_completeness_mismatch"
            ),
            (.invalidSnapshotAsOf, "project_category_configuration_as_of_invalid"),
            (
                .requestAccountMismatch,
                "project_category_configuration_request_account_mismatch"
            ),
            (
                .requestProjectMismatch,
                "project_category_configuration_request_project_mismatch"
            ),
            (.localReadFailed, "project_category_configuration_local_read_failed"),
            (.invalidEncodedState, "project_category_configuration_state_encoding_invalid"),
            (.invalidEncodedRow, "project_category_configuration_row_encoding_invalid"),
            (
                .invalidEncodedSnapshot,
                "project_category_configuration_snapshot_encoding_invalid"
            )
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The read port returns only the exact Account and Project snapshot")
    func readPortIsScopeExactAndFailureSafe() async throws {
        let fixture = try Self.fixture()
        let port = FixtureProjectCategoryConfigurationPort(snapshot: fixture.snapshot)
        var received: [ProjectCategoryConfigurationSnapshot] = []
        for try await snapshot in port.watchProjectCategoryConfiguration(
            accountId: fixture.accountId,
            projectId: fixture.projectId
        ) {
            received.append(snapshot)
        }
        #expect(received == [fixture.snapshot])

        let otherAccount = try AccountID(validating: "account-other")
        var mismatchedAccountRows: [ProjectCategoryConfigurationSnapshot] = []
        var accountFailure: ProjectCategoryConfigurationFailure?
        do {
            for try await snapshot in port.watchProjectCategoryConfiguration(
                accountId: otherAccount,
                projectId: fixture.projectId
            ) {
                mismatchedAccountRows.append(snapshot)
            }
        } catch let failure as ProjectCategoryConfigurationFailure {
            accountFailure = failure
        }
        #expect(mismatchedAccountRows.isEmpty)
        #expect(accountFailure == .requestAccountMismatch)

        let otherProject = try ProjectID(validating: "project-other")
        var mismatchedProjectRows: [ProjectCategoryConfigurationSnapshot] = []
        var projectFailure: ProjectCategoryConfigurationFailure?
        do {
            for try await snapshot in port.watchProjectCategoryConfiguration(
                accountId: fixture.accountId,
                projectId: otherProject
            ) {
                mismatchedProjectRows.append(snapshot)
            }
        } catch let failure as ProjectCategoryConfigurationFailure {
            projectFailure = failure
        }
        #expect(mismatchedProjectRows.isEmpty)
        #expect(projectFailure == .requestProjectMismatch)

        let failing = FailingProjectCategoryConfigurationPort()
        var falseSnapshots: [ProjectCategoryConfigurationSnapshot] = []
        var localFailure: ProjectCategoryConfigurationFailure?
        do {
            for try await snapshot in failing.watchProjectCategoryConfiguration(
                accountId: fixture.accountId,
                projectId: fixture.projectId
            ) {
                falseSnapshots.append(snapshot)
            }
        } catch let failure as ProjectCategoryConfigurationFailure {
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
        let projectId: ProjectID
        let currency: CurrencyCode
        let snapshot: ProjectCategoryConfigurationSnapshot
    }

    private struct RestartFixture: Codable, Equatable, Sendable {
        let ready: ProjectCategoryConfigurationSnapshot
        let partial: ProjectCategoryConfigurationSnapshot
        let stale: ProjectCategoryConfigurationSnapshot
        let authoritativeEmpty: ProjectCategoryConfigurationSnapshot
    }

    private static func fixture() throws -> Fixture {
        let accountId = try AccountID(validating: "account-project-category-test")
        let projectId = try ProjectID(validating: "project-category-test")
        let currency = try CurrencyCode(validating: "USD")
        let rows = [
            try row(
                id: "category-system-adjustment",
                accountId: accountId,
                name: "Other Client Charges and Credits",
                isSystem: true,
                order: 5,
                state: .noRelationship
            ),
            try row(
                id: "category-archived",
                accountId: accountId,
                name: "Archived Furnishings",
                kind: .itemized,
                lifecycle: .archived,
                order: 4,
                revision: 2,
                state: .noRelationship
            ),
            try row(
                id: "category-install",
                accountId: accountId,
                name: "Install",
                order: 3,
                state: .enabledWithoutAllocation
            ),
            try row(
                id: "category-design-fee",
                accountId: accountId,
                name: "Design Fee",
                kind: .fee,
                excludesFromOverallBudget: true,
                order: 2,
                revision: 8,
                state: .enabledWithAllocation(.zero(currency: currency))
            ),
            try row(
                id: "category-furnishings",
                accountId: accountId,
                name: "Furnishings",
                kind: .itemized,
                order: 1,
                revision: 12,
                state: .enabledWithAllocation(
                    Money(minorUnits: 250_000, currency: currency)
                )
            )
        ]
        return Fixture(
            accountId: accountId,
            projectId: projectId,
            currency: currency,
            snapshot: try snapshot(
                accountId: accountId,
                projectId: projectId,
                rows: rows
            )
        )
    }

    private static func row(
        id: String,
        accountId: AccountID,
        name: String,
        kind: BudgetCategoryKind = .general,
        lifecycle: DirectoryLifecycleState = .active,
        isSystem: Bool = false,
        excludesFromOverallBudget: Bool = false,
        order: UInt32,
        revision: UInt64 = 1,
        state: ProjectCategoryConfigurationState
    ) throws -> ProjectCategoryConfigurationRow {
        try ProjectCategoryConfigurationRow(
            category: BudgetCategoryDefinitionSnapshot(
                id: BudgetCategoryID(validating: id),
                accountId: accountId,
                name: BudgetCategoryName(validating: name),
                kind: kind,
                lifecycle: lifecycle,
                isSystem: isSystem,
                excludesFromOverallBudget: excludesFromOverallBudget,
                presentationOrder: order,
                revision: revision
            ),
            state: state
        )
    }

    private static func snapshot(
        accountId: AccountID,
        projectId: ProjectID,
        rows: [ProjectCategoryConfigurationRow],
        quality: ListSnapshotQuality = .ready,
        isComplete: Bool = true,
        visibleCount: Int? = nil,
        fingerprintCharacter: Character = "a",
        version: String = "project-category-ready",
        asOf: Date = t0
    ) throws -> ProjectCategoryConfigurationSnapshot {
        try ProjectCategoryConfigurationSnapshot(
            accountId: accountId,
            projectId: projectId,
            configurationRevision: 9,
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

    private static func configurationFailure<Value>(
        _ body: () throws -> Value
    ) -> ProjectCategoryConfigurationFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as ProjectCategoryConfigurationFailure {
            return failure
        } catch {
            return nil
        }
    }
}

private struct FixtureProjectCategoryConfigurationPort: ProjectCategoryConfigurationQuerying {
    let snapshot: ProjectCategoryConfigurationSnapshot

    func watchProjectCategoryConfiguration(
        accountId: AccountID,
        projectId: ProjectID
    ) -> AsyncThrowingStream<ProjectCategoryConfigurationSnapshot, Error> {
        AsyncThrowingStream { continuation in
            guard accountId == snapshot.accountId else {
                continuation.finish(
                    throwing: ProjectCategoryConfigurationFailure.requestAccountMismatch
                )
                return
            }
            guard projectId == snapshot.projectId else {
                continuation.finish(
                    throwing: ProjectCategoryConfigurationFailure.requestProjectMismatch
                )
                return
            }
            continuation.yield(snapshot)
            continuation.finish()
        }
    }
}

private struct FailingProjectCategoryConfigurationPort: ProjectCategoryConfigurationQuerying {
    func watchProjectCategoryConfiguration(
        accountId: AccountID,
        projectId: ProjectID
    ) -> AsyncThrowingStream<ProjectCategoryConfigurationSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: ProjectCategoryConfigurationFailure.localReadFailed
            )
        }
    }
}
