import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Preference Read Contracts")
struct ProjectPreferenceDataTests {
    @Test("Stored preferences preserve exact personal scope, pin order, and revision")
    func storedPreferenceIsExact() throws {
        let request = try Self.request()
        let first = try Self.preference(
            projectID: "project-a",
            pinnedCategoryIDs: ["category-active", "category-archived", "category-stale"],
            revision: 7
        )
        let empty = try Self.preference(
            projectID: "project-b",
            pinnedCategoryIDs: [],
            revision: 2
        )
        let directory = try Self.directory(request: request, rows: [empty, first])

        #expect(directory.local.rows.map(\.projectId.rawValue) == ["project-a", "project-b"])
        #expect(directory.local.rows[0].pinnedCategoryIds.map(\.rawValue) == [
            "category-active", "category-archived", "category-stale"
        ])
        #expect(directory.local.rows[0].revision == 7)
        #expect(directory.local.rows[1].pinnedCategoryIds.isEmpty)
        #expect(directory.preference(for: first.projectId) == .stored(first))
        #expect(directory.local.visibleRowCountBeforeFiltering == 2)

        let root = try Self.jsonObject(OperationContractCodec.encode(first))
        #expect(Set(root.keys) == Set([
            "accountId", "pinnedCategoryIds", "principalId", "projectId", "revision"
        ]))
        let text = String(
            decoding: try OperationContractCodec.encode(directory),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "userid", "userpath", "categoryname", "lifecycle", "budgetcents",
            "spend", "allocation", "firebase", "firestore", "supabase", "powersync",
            "https://", "file://", "bearer", "token", "secret", "serviceaccount",
            "service_account", "membership", "grant", "policy", "sql"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Ready, partial, stale, and empty restart preserves absence truth")
    func readinessAndAbsenceSurviveRestart() throws {
        let request = try Self.request()
        let preference = try Self.preference(
            projectID: "project-a",
            pinnedCategoryIDs: ["category-active"]
        )
        let ready = try Self.directory(request: request, rows: [preference])
        let partial = try Self.directory(
            request: request,
            rows: [preference],
            quality: .partial,
            isComplete: false,
            version: "preference-partial",
            asOf: Self.t1
        )
        let stale = try Self.directory(
            request: request,
            rows: [],
            quality: .stale,
            isComplete: false,
            version: "preference-stale",
            asOf: Self.t2
        )
        let authoritativeEmpty = try Self.directory(
            request: request,
            rows: [],
            quality: .ready,
            isComplete: true,
            version: "preference-empty",
            asOf: Self.t3
        )
        let restart = RestartFixture(
            ready: ready,
            partial: partial,
            stale: stale,
            authoritativeEmpty: authoritativeEmpty
        )

        let bytes = try OperationContractCodec.encode(restart)
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)
        let missing = try ProjectID(validating: "project-missing")

        #expect(restored == restart)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.ready.preference(for: missing) == .notStored)
        #expect(restored.partial.preference(for: missing) == .notAvailable)
        #expect(restored.stale.preference(for: missing) == .notAvailable)
        #expect(restored.authoritativeEmpty.preference(for: missing) == .notStored)
        #expect(restored.authoritativeEmpty.local.visibleRowCountBeforeFiltering == 0)
        #expect(restored.authoritativeEmpty.local.isCompleteForQuery)
        #expect(restored.ready.request.queryFingerprint == request.queryFingerprint)
    }

    @Test("Cross-scope, duplicate, mismatched, and malformed evidence fails closed")
    func invalidEvidenceFailsAtomically() throws {
        let request = try Self.request()
        let first = try Self.preference(projectID: "project-a")
        let duplicatePin = try BudgetCategoryID(validating: "category-duplicate")
        #expect(Self.preferenceFailure {
            try ProjectPreferenceSnapshot(
                accountId: first.accountId,
                principalId: first.principalId,
                projectId: first.projectId,
                pinnedCategoryIds: [duplicatePin, duplicatePin],
                revision: 1
            )
        } == .duplicatePinnedCategoryIdentity)

        let otherAccount = try Self.preference(
            accountID: "account-other",
            projectID: "project-other-account"
        )
        #expect(Self.preferenceFailure {
            try Self.directory(request: request, rows: [otherAccount])
        } == .accountScopeMismatch)

        let otherPrincipal = try Self.preference(
            principalID: "principal-other",
            projectID: "project-other-principal"
        )
        #expect(Self.preferenceFailure {
            try Self.directory(request: request, rows: [otherPrincipal])
        } == .principalScopeMismatch)

        let duplicateProject = try Self.preference(
            projectID: first.projectId.rawValue,
            pinnedCategoryIDs: ["category-other"]
        )
        #expect(Self.preferenceFailure {
            try Self.directory(request: request, rows: [first, duplicateProject])
        } == .duplicateProjectIdentity)
        #expect(Self.preferenceFailure {
            try Self.directory(request: request, rows: [first], visibleCount: 2)
        } == .visibleCountMismatch)
        #expect(Self.preferenceFailure {
            try Self.directory(
                request: request,
                rows: [first],
                fingerprint: try ListQueryFingerprint(
                    validating: String(repeating: "f", count: 64)
                )
            )
        } == .queryFingerprintMismatch)
        #expect(Self.preferenceFailure {
            try Self.directory(
                request: request,
                rows: [first],
                asOf: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidSnapshotAsOf)

        let otherRequest = try Self.request(principalID: "principal-other")
        let directory = try Self.directory(request: request, rows: [first])
        #expect(Self.preferenceFailure {
            try otherRequest.validate(directory)
        } == .requestMismatch)
        #expect(Self.decodeFailure(ProjectPreferenceSnapshot.self) == .invalidEncodedPreference)
        #expect(Self.decodeFailure(ProjectPreferenceDirectoryRequest.self) == .invalidEncodedRequest)
        #expect(Self.decodeFailure(ProjectPreferenceDirectorySnapshot.self) == .invalidEncodedDirectory)

        let diagnostics: [(ProjectPreferenceDataFailure, String)] = [
            (.duplicatePinnedCategoryIdentity, "project_preference_pinned_category_duplicate"),
            (.accountScopeMismatch, "project_preference_account_scope_mismatch"),
            (.principalScopeMismatch, "project_preference_principal_scope_mismatch"),
            (.duplicateProjectIdentity, "project_preference_project_identity_duplicate"),
            (.visibleCountMismatch, "project_preference_visible_count_mismatch"),
            (.invalidSnapshotAsOf, "project_preference_as_of_invalid"),
            (.queryFingerprintMismatch, "project_preference_query_fingerprint_mismatch"),
            (.requestMismatch, "project_preference_request_mismatch"),
            (.localReadFailed, "project_preference_local_read_failed"),
            (.invalidEncodedPreference, "project_preference_encoding_invalid"),
            (.invalidEncodedRequest, "project_preference_request_encoding_invalid"),
            (.invalidEncodedDirectory, "project_preference_directory_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The read port returns only its exact current-Principal directory")
    func referencePortIsExact() async throws {
        let request = try Self.request()
        let directory = try Self.directory(
            request: request,
            rows: [try Self.preference(projectID: "project-a")]
        )
        let adapter = ReferenceProjectPreferenceAdapter(
            expectedRequest: request,
            snapshot: directory
        )
        var iterator = adapter.watchProjectPreferences(request).makeAsyncIterator()
        let returned = try #require(try await iterator.next())
        #expect(try request.validate(returned) == directory)
        #expect(try await iterator.next() == nil)

        let wrongRequest = try Self.request(accountID: "account-other")
        var wrongIterator = adapter.watchProjectPreferences(wrongRequest).makeAsyncIterator()
        do {
            _ = try await wrongIterator.next()
            Issue.record("A mismatched preference request yielded a directory")
        } catch let failure as ProjectPreferenceDataFailure {
            #expect(failure == .requestMismatch)
        }

        let failing = FailingProjectPreferenceAdapter()
        var failingIterator = failing.watchProjectPreferences(request).makeAsyncIterator()
        do {
            _ = try await failingIterator.next()
            Issue.record("A failing preference port yielded a directory")
        } catch let failure as ProjectPreferenceDataFailure {
            #expect(failure == .localReadFailed)
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_800_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_800_001)
    private static let t2 = Date(timeIntervalSince1970: 1_800_800_002)
    private static let t3 = Date(timeIntervalSince1970: 1_800_800_003)

    private static func request(
        accountID: String = "account-preference-test",
        principalID: String = "principal-preference-test"
    ) throws -> ProjectPreferenceDirectoryRequest {
        try ProjectPreferenceDirectoryRequest(
            accountId: AccountID(validating: accountID),
            principalId: PrincipalID(validating: principalID)
        )
    }

    private static func preference(
        accountID: String = "account-preference-test",
        principalID: String = "principal-preference-test",
        projectID: String,
        pinnedCategoryIDs: [String] = ["category-active"],
        revision: UInt64 = 1
    ) throws -> ProjectPreferenceSnapshot {
        try ProjectPreferenceSnapshot(
            accountId: AccountID(validating: accountID),
            principalId: PrincipalID(validating: principalID),
            projectId: ProjectID(validating: projectID),
            pinnedCategoryIds: try pinnedCategoryIDs.map(BudgetCategoryID.init(validating:)),
            revision: revision
        )
    }

    private static func directory(
        request: ProjectPreferenceDirectoryRequest,
        rows: [ProjectPreferenceSnapshot],
        visibleCount: Int? = nil,
        quality: ListSnapshotQuality = .ready,
        isComplete: Bool = true,
        fingerprint: ListQueryFingerprint? = nil,
        version: String = "preference-ready",
        asOf: Date = t0
    ) throws -> ProjectPreferenceDirectorySnapshot {
        try ProjectPreferenceDirectorySnapshot(
            request: request,
            local: ListLocalSnapshot(
                queryFingerprint: fingerprint ?? request.queryFingerprint,
                rows: rows,
                visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
                isCompleteForQuery: isComplete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: asOf
            )
        )
    }

    private static func preferenceFailure<T>(
        _ operation: () throws -> T
    ) -> ProjectPreferenceDataFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ProjectPreferenceDataFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure<Value: Decodable>(
        _ type: Value.Type
    ) -> ProjectPreferenceDataFailure? {
        preferenceFailure {
            try OperationContractCodec.decode(type, from: Data("{}".utf8))
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectPreferenceDataFailure.invalidEncodedPreference
        }
        return object
    }
}

private struct RestartFixture: Codable, Equatable, Sendable {
    let ready: ProjectPreferenceDirectorySnapshot
    let partial: ProjectPreferenceDirectorySnapshot
    let stale: ProjectPreferenceDirectorySnapshot
    let authoritativeEmpty: ProjectPreferenceDirectorySnapshot
}

private struct ReferenceProjectPreferenceAdapter: ProjectPreferenceQuerying {
    let expectedRequest: ProjectPreferenceDirectoryRequest
    let snapshot: ProjectPreferenceDirectorySnapshot

    func watchProjectPreferences(
        _ request: ProjectPreferenceDirectoryRequest
    ) -> AsyncThrowingStream<ProjectPreferenceDirectorySnapshot, Error> {
        AsyncThrowingStream { continuation in
            guard request == expectedRequest else {
                continuation.finish(throwing: ProjectPreferenceDataFailure.requestMismatch)
                return
            }
            continuation.yield(snapshot)
            continuation.finish()
        }
    }
}

private struct FailingProjectPreferenceAdapter: ProjectPreferenceQuerying {
    func watchProjectPreferences(
        _ request: ProjectPreferenceDirectoryRequest
    ) -> AsyncThrowingStream<ProjectPreferenceDirectorySnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ProjectPreferenceDataFailure.localReadFailed)
        }
    }
}
