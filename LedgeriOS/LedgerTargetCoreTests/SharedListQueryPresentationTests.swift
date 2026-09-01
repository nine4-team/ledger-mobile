import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Shared List Query Presentation")
struct SharedListQueryPresentationTests {
    @Test("Named query state is bounded, deterministic, and cursor safe")
    func namedQueryStateIsBounded() throws {
        let profile = try Self.profile()
        let active = try NamedFilterID(validating: "active_only")
        let assigned = try NamedFilterID(validating: "assigned_only")
        let search = try ListSearchTerm(normalizing: "  Walnut   table  ")
        let query = try ListQueryState(
            profile: profile,
            sortId: try NamedSortID(validating: "name_order"),
            direction: .descending,
            activeFilters: [assigned, active],
            search: search,
            pageSize: 50
        )

        #expect(query.activeFilters.map(\.rawValue) == ["active_only", "assigned_only"])
        #expect(query.search?.normalizedValue == "Walnut table")
        #expect(query.sort.tieBreaker == .stableEntityID)
        #expect(query.sort.cursorContractVersion.rawValue == "cursor-v1")
        #expect(query.fingerprint.sha256.count == 64)

        let cursor = try query.cursor(validating: "page_2.cursor")
        let nextPage = try ListQueryState(
            profile: profile,
            sortId: query.sort.sortId,
            direction: query.sort.direction,
            activeFilters: query.activeFilters,
            search: query.search,
            pageSize: query.pageSize,
            cursor: cursor
        )
        #expect(nextPage.cursor == cursor)
        #expect(nextPage.fingerprint == query.fingerprint)

        let changedQueryFailure = Self.captureListFailure {
            _ = try ListQueryState(
                profile: profile,
                sortId: query.sort.sortId,
                direction: query.sort.direction,
                activeFilters: [active],
                search: query.search,
                pageSize: query.pageSize,
                cursor: cursor
            )
        }
        #expect(changedQueryFailure == .cursorQueryMismatch)

        let rawField = try NamedSortID(validating: "created_at")
        let unsupportedSortFailure = Self.captureListFailure {
            _ = try ListQueryState(
                profile: profile,
                sortId: rawField,
                pageSize: 20
            )
        }
        #expect(unsupportedSortFailure == .unsupportedSort(rawField))

        let duplicateFilterFailure = Self.captureListFailure {
            _ = try ListQueryState(
                profile: profile,
                activeFilters: [active, active],
                pageSize: 20
            )
        }
        #expect(duplicateFilterFailure == .duplicateFilter(active))

        let pageSizeFailure = Self.captureListFailure {
            _ = try ListQueryState(profile: profile, pageSize: 101)
        }
        #expect(pageSizeFailure == .invalidPageSize)

        let intent = ListPresentationIntent.changeSort(
            id: query.sort.sortId,
            direction: .ascending
        )
        let roundTripIntent = try OperationContractCodec.decode(
            ListPresentationIntent.self,
            from: OperationContractCodec.encode(intent)
        )
        #expect(roundTripIntent == intent)
        try query.validate(roundTripIntent)

        let unsupportedAction = try NamedListActionID(validating: "delete_everything")
        let unsupportedActionFailure = Self.captureListFailure {
            try query.validate(.add(unsupportedAction))
        }
        #expect(unsupportedActionFailure == .unsupportedAction(unsupportedAction))

        let retryMismatch = Self.captureListFailure {
            try query.validate(.retry(RetryQueryIntent(
                profileId: query.profile.id,
                queryFingerprint: try ListQueryFingerprint(
                    validating: String(repeating: "0", count: 64)
                )
            )))
        }
        #expect(retryMismatch == .retryQueryMismatch)
    }

    @Test("Restart reconstruction preserves local partial and empty truth")
    func restartReconstructsTheSamePresentation() throws {
        let query = try ListQueryState(profile: Self.profile(), pageSize: 40)
        let row = try FixtureRow(
            id: EntityID(validating: "item-001"),
            title: "Locally cached chair"
        )
        let partial = try ListLocalSnapshot(
            queryFingerprint: query.fingerprint,
            rows: [row],
            visibleRowCountBeforeFiltering: 1,
            isCompleteForQuery: false,
            quality: .partial,
            localDataVersion: LocalDataVersion(validating: "local-42"),
            asOf: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let fixture = RestartFixture(
            query: query,
            update: .snapshot(partial)
        )
        let beforeRestart = try ListPresentationReducer.reduce(
            query: fixture.query,
            update: fixture.update
        )
        let restored = try OperationContractCodec.decode(
            RestartFixture.self,
            from: OperationContractCodec.encode(fixture)
        )
        let afterRestart = try ListPresentationReducer.reduce(
            query: restored.query,
            update: restored.update
        )

        #expect(afterRestart == beforeRestart)
        #expect(afterRestart.rows == [row])
        #expect(afterRestart.readiness == .partial)
        #expect(afterRestart.emptyState == nil)

        let incompleteEmpty = try ListLocalSnapshot<FixtureRow>(
            queryFingerprint: query.fingerprint,
            rows: [],
            visibleRowCountBeforeFiltering: 0,
            isCompleteForQuery: false,
            quality: .partial,
            localDataVersion: LocalDataVersion(validating: "local-43"),
            asOf: Date(timeIntervalSince1970: 1_800_000_001)
        )
        let incompleteState = try ListPresentationReducer.reduce(
            query: query,
            update: .snapshot(incompleteEmpty)
        )
        #expect(incompleteState.emptyState == nil)
        #expect(incompleteState.readiness == .partial)

        let authoritativeEmpty = try ListLocalSnapshot<FixtureRow>(
            queryFingerprint: query.fingerprint,
            rows: [],
            visibleRowCountBeforeFiltering: 0,
            isCompleteForQuery: true,
            quality: .ready,
            localDataVersion: LocalDataVersion(validating: "local-44"),
            asOf: Date(timeIntervalSince1970: 1_800_000_002)
        )
        let emptyState = try ListPresentationReducer.reduce(
            query: query,
            update: .snapshot(authoritativeEmpty)
        )
        #expect(emptyState.emptyState == .authoritativeEmpty)

        let noMatches = try ListLocalSnapshot<FixtureRow>(
            queryFingerprint: query.fingerprint,
            rows: [],
            visibleRowCountBeforeFiltering: 7,
            isCompleteForQuery: true,
            quality: .ready,
            localDataVersion: LocalDataVersion(validating: "local-45"),
            asOf: Date(timeIntervalSince1970: 1_800_000_003)
        )
        let noMatchesState = try ListPresentationReducer.reduce(
            query: query,
            update: .snapshot(noMatches)
        )
        #expect(noMatchesState.emptyState == .noMatches)
    }

    @Test("Failure presentation is non-enumerating and preserves safe cached rows")
    func failurePresentationIsSafe() throws {
        let query = try ListQueryState(profile: Self.profile(), pageSize: 40)
        let cached = try ListLocalSnapshot(
            queryFingerprint: query.fingerprint,
            rows: [try FixtureRow(
                id: EntityID(validating: "item-002"),
                title: "Cached desk"
            )],
            visibleRowCountBeforeFiltering: 1,
            isCompleteForQuery: true,
            quality: .ready,
            localDataVersion: LocalDataVersion(validating: "local-50"),
            asOf: Date(timeIntervalSince1970: 1_800_000_010)
        )

        let notFound = try ListPresentationReducer.reduce(
            query: query,
            update: .failed(failure: ListQueryFailureCause.notFound.presentation, cached: cached)
        )
        let notAuthorized = try ListPresentationReducer.reduce(
            query: query,
            update: .failed(
                failure: ListQueryFailureCause.notAuthorized.presentation,
                cached: cached
            )
        )
        #expect(notFound == notAuthorized)
        #expect(notFound.failure == .unavailable)
        #expect(notFound.rows.isEmpty)
        #expect(notFound.localDataVersion == nil)
        #expect(notFound.retryIntent == nil)

        let transient = try ListPresentationReducer.reduce(
            query: query,
            update: .failed(
                failure: ListQueryFailureCause.transientInfrastructure.presentation,
                cached: cached
            )
        )
        #expect(transient.rows == cached.rows)
        #expect(transient.readiness == .stale)
        #expect(transient.failure == .retryable)
        #expect(transient.emptyState == nil)
        #expect(transient.retryIntent == RetryQueryIntent(
            profileId: query.profile.id,
            queryFingerprint: query.fingerprint
        ))

        let requiredUpdate: ListPresentationSnapshot<FixtureRow> = try ListPresentationReducer.reduce(
            query: query,
            update: .failed(
                failure: ListQueryFailureCause.unsupportedContract.presentation,
                cached: nil
            )
        )
        #expect(requiredUpdate.failure == .requiredUpdate)
        #expect(requiredUpdate.readiness == .blocked)

        let otherQuery = try ListQueryState(
            profile: Self.profile(),
            activeFilters: [try NamedFilterID(validating: "active_only")],
            pageSize: 40
        )
        let mismatch = Self.captureListFailure {
            _ = try ListPresentationReducer.reduce(
                query: otherQuery,
                update: .snapshot(cached)
            )
        }
        #expect(mismatch == .querySnapshotMismatch)

        let invalidCompletion = Self.captureListFailure {
            _ = try ListLocalSnapshot<FixtureRow>(
                queryFingerprint: query.fingerprint,
                rows: [],
                visibleRowCountBeforeFiltering: 0,
                isCompleteForQuery: true,
                quality: .partial,
                localDataVersion: LocalDataVersion(validating: "local-51"),
                asOf: Date(timeIntervalSince1970: 1_800_000_011)
            )
        }
        #expect(invalidCompletion == .incompleteAuthoritativeEmpty)
    }

    private static func profile() throws -> NamedListQueryProfile {
        let cursorVersion = try ListCursorContractVersion(validating: "cursor-v1")
        return try NamedListQueryProfile(
            id: NamedQueryProfileID(validating: "project_items"),
            sorts: [
                try NamedSortOption(
                    id: NamedSortID(validating: "updated_order"),
                    allowedDirections: [.descending],
                    defaultDirection: .descending,
                    cursorContractVersion: cursorVersion
                ),
                try NamedSortOption(
                    id: NamedSortID(validating: "name_order"),
                    allowedDirections: [.ascending, .descending],
                    defaultDirection: .ascending,
                    cursorContractVersion: cursorVersion
                )
            ],
            defaultSortId: NamedSortID(validating: "updated_order"),
            filters: [
                NamedFilterID(validating: "active_only"),
                NamedFilterID(validating: "assigned_only")
            ],
            actions: [NamedListActionID(validating: "create_item")],
            allowsSearch: true,
            maximumPageSize: 100
        )
    }

    private static func captureListFailure(
        _ operation: () throws -> Void
    ) -> ListQueryContractFailure? {
        do {
            try operation()
            return nil
        } catch let failure as ListQueryContractFailure {
            return failure
        } catch {
            return nil
        }
    }

    private struct FixtureRow: Codable, Equatable, Sendable {
        let id: EntityID
        let title: String

        init(id: EntityID, title: String) throws {
            guard !title.isEmpty else {
                throw ListQueryContractFailure.invalidSearchTerm
            }
            self.id = id
            self.title = title
        }
    }

    private struct RestartFixture: Codable, Equatable, Sendable {
        let query: ListQueryState
        let update: ListQueryUpdate<FixtureRow>
    }
}
