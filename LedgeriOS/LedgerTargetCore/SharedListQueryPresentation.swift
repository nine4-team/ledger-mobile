import CryptoKit
import Foundation

public enum ListQueryContractFailure: Error, Equatable, Sendable {
    case invalidSearchTerm
    case invalidPageSize
    case emptySortRegistry
    case duplicateSort(NamedSortID)
    case duplicateFilter(NamedFilterID)
    case duplicateAction(NamedListActionID)
    case unsupportedSort(NamedSortID)
    case unsupportedSortDirection(NamedSortID)
    case unsupportedFilter(NamedFilterID)
    case unsupportedAction(NamedListActionID)
    case invalidDefaultSort(NamedSortID)
    case invalidCursor
    case cursorQueryMismatch
    case retryQueryMismatch
    case invalidVisibleRowCount
    case incompleteAuthoritativeEmpty
    case querySnapshotMismatch
}

public enum NamedQueryProfileIDTag: Sendable {}
public enum NamedSortIDTag: Sendable {}
public enum NamedFilterIDTag: Sendable {}
public enum NamedListActionIDTag: Sendable {}
public enum LocalDataVersionTag: Sendable {}
public enum ListCursorContractVersionTag: Sendable {}

public typealias NamedQueryProfileID = StableCode<NamedQueryProfileIDTag>
public typealias NamedSortID = StableCode<NamedSortIDTag>
public typealias NamedFilterID = StableCode<NamedFilterIDTag>
public typealias NamedListActionID = StableCode<NamedListActionIDTag>
public typealias LocalDataVersion = LedgerIdentifier<LocalDataVersionTag>
public typealias ListCursorContractVersion = LedgerIdentifier<ListCursorContractVersionTag>

public enum SortDirection: String, Codable, CaseIterable, Sendable {
    case ascending
    case descending
}

public enum StableSortTieBreaker: String, Codable, CaseIterable, Sendable {
    case stableEntityID
}

public struct StableSortDescriptor: Codable, Equatable, Sendable {
    public let sortId: NamedSortID
    public let direction: SortDirection
    public let cursorContractVersion: ListCursorContractVersion
    public let tieBreaker: StableSortTieBreaker

    public init(
        sortId: NamedSortID,
        direction: SortDirection,
        cursorContractVersion: ListCursorContractVersion
    ) {
        self.sortId = sortId
        self.direction = direction
        self.cursorContractVersion = cursorContractVersion
        tieBreaker = .stableEntityID
    }
}

public struct NamedSortOption: Codable, Equatable, Sendable {
    public let id: NamedSortID
    public let allowedDirections: [SortDirection]
    public let defaultDirection: SortDirection
    public let cursorContractVersion: ListCursorContractVersion

    public init(
        id: NamedSortID,
        allowedDirections: [SortDirection],
        defaultDirection: SortDirection,
        cursorContractVersion: ListCursorContractVersion
    ) throws {
        guard !allowedDirections.isEmpty,
              Set(allowedDirections).count == allowedDirections.count,
              allowedDirections.contains(defaultDirection) else {
            throw ListQueryContractFailure.unsupportedSortDirection(id)
        }
        self.id = id
        self.allowedDirections = allowedDirections
        self.defaultDirection = defaultDirection
        self.cursorContractVersion = cursorContractVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(NamedSortID.self, forKey: .id),
            allowedDirections: container.decode([SortDirection].self, forKey: .allowedDirections),
            defaultDirection: container.decode(SortDirection.self, forKey: .defaultDirection),
            cursorContractVersion: container.decode(
                ListCursorContractVersion.self,
                forKey: .cursorContractVersion
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case allowedDirections
        case defaultDirection
        case cursorContractVersion
    }
}

public struct NamedListQueryProfile: Codable, Equatable, Sendable {
    public let id: NamedQueryProfileID
    public let sorts: [NamedSortOption]
    public let defaultSortId: NamedSortID
    public let filters: [NamedFilterID]
    public let actions: [NamedListActionID]
    public let allowsSearch: Bool
    public let maximumPageSize: UInt16

    public init(
        id: NamedQueryProfileID,
        sorts: [NamedSortOption],
        defaultSortId: NamedSortID,
        filters: [NamedFilterID],
        actions: [NamedListActionID],
        allowsSearch: Bool,
        maximumPageSize: UInt16
    ) throws {
        guard !sorts.isEmpty else {
            throw ListQueryContractFailure.emptySortRegistry
        }
        if let duplicate = Self.firstDuplicate(sorts.map(\.id)) {
            throw ListQueryContractFailure.duplicateSort(duplicate)
        }
        guard sorts.contains(where: { $0.id == defaultSortId }) else {
            throw ListQueryContractFailure.invalidDefaultSort(defaultSortId)
        }
        if let duplicate = Self.firstDuplicate(filters) {
            throw ListQueryContractFailure.duplicateFilter(duplicate)
        }
        if let duplicate = Self.firstDuplicate(actions) {
            throw ListQueryContractFailure.duplicateAction(duplicate)
        }
        guard maximumPageSize > 0, maximumPageSize <= 200 else {
            throw ListQueryContractFailure.invalidPageSize
        }
        self.id = id
        self.sorts = sorts
        self.defaultSortId = defaultSortId
        self.filters = filters
        self.actions = actions
        self.allowsSearch = allowsSearch
        self.maximumPageSize = maximumPageSize
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(NamedQueryProfileID.self, forKey: .id),
            sorts: container.decode([NamedSortOption].self, forKey: .sorts),
            defaultSortId: container.decode(NamedSortID.self, forKey: .defaultSortId),
            filters: container.decode([NamedFilterID].self, forKey: .filters),
            actions: container.decode([NamedListActionID].self, forKey: .actions),
            allowsSearch: container.decode(Bool.self, forKey: .allowsSearch),
            maximumPageSize: container.decode(UInt16.self, forKey: .maximumPageSize)
        )
    }

    public func sortOption(id: NamedSortID) -> NamedSortOption? {
        sorts.first { $0.id == id }
    }

    private static func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sorts
        case defaultSortId
        case filters
        case actions
        case allowsSearch
        case maximumPageSize
    }
}

public struct ListSearchTerm: Codable, Equatable, Hashable, Sendable {
    public let normalizedValue: String

    public init(normalizing value: String) throws {
        let normalized = value
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        let hasControl = normalized.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
        guard !normalized.isEmpty,
              normalized.utf8.count <= 200,
              !hasControl else {
            throw ListQueryContractFailure.invalidSearchTerm
        }
        normalizedValue = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(normalizing: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid list search term"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(normalizedValue)
    }
}

public struct ListQueryFingerprint: Codable, Equatable, Hashable, Sendable {
    public let sha256: String

    public init(validating sha256: String) throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard sha256.utf8.count == 64,
              sha256.unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw ListQueryContractFailure.invalidCursor
        }
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid list query fingerprint"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }
}

public struct StableCursor: Codable, Equatable, Hashable, Sendable {
    public let opaqueValue: String
    public let queryFingerprint: ListQueryFingerprint

    public init(
        validating opaqueValue: String,
        queryFingerprint: ListQueryFingerprint
    ) throws {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_.:"))
        guard !opaqueValue.isEmpty,
              opaqueValue.utf8.count <= 512,
              opaqueValue.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ListQueryContractFailure.invalidCursor
        }
        self.opaqueValue = opaqueValue
        self.queryFingerprint = queryFingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                validating: container.decode(String.self, forKey: .opaqueValue),
                queryFingerprint: container.decode(
                    ListQueryFingerprint.self,
                    forKey: .queryFingerprint
                )
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .opaqueValue,
                in: container,
                debugDescription: "Invalid stable cursor"
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case opaqueValue
        case queryFingerprint
    }
}

public struct ListQueryState: Codable, Equatable, Sendable {
    public let profile: NamedListQueryProfile
    public let sort: StableSortDescriptor
    public let activeFilters: [NamedFilterID]
    public let search: ListSearchTerm?
    public let pageSize: UInt16
    public let cursor: StableCursor?
    public let fingerprint: ListQueryFingerprint

    public init(
        profile: NamedListQueryProfile,
        sortId: NamedSortID? = nil,
        direction: SortDirection? = nil,
        activeFilters: [NamedFilterID] = [],
        search: ListSearchTerm? = nil,
        pageSize: UInt16,
        cursor: StableCursor? = nil
    ) throws {
        let selectedSortId = sortId ?? profile.defaultSortId
        guard let selectedSort = profile.sortOption(id: selectedSortId) else {
            throw ListQueryContractFailure.unsupportedSort(selectedSortId)
        }
        let selectedDirection = direction ?? selectedSort.defaultDirection
        guard selectedSort.allowedDirections.contains(selectedDirection) else {
            throw ListQueryContractFailure.unsupportedSortDirection(selectedSortId)
        }
        if let duplicate = Self.firstDuplicate(activeFilters) {
            throw ListQueryContractFailure.duplicateFilter(duplicate)
        }
        for filter in activeFilters where !profile.filters.contains(filter) {
            throw ListQueryContractFailure.unsupportedFilter(filter)
        }
        guard pageSize > 0, pageSize <= profile.maximumPageSize else {
            throw ListQueryContractFailure.invalidPageSize
        }
        guard search == nil || profile.allowsSearch else {
            throw ListQueryContractFailure.invalidSearchTerm
        }

        let normalizedFilters = activeFilters.sorted { $0.rawValue < $1.rawValue }
        let descriptor = StableSortDescriptor(
            sortId: selectedSortId,
            direction: selectedDirection,
            cursorContractVersion: selectedSort.cursorContractVersion
        )
        let fingerprint = try Self.makeFingerprint(
            profileId: profile.id,
            sort: descriptor,
            filters: normalizedFilters,
            search: search,
            pageSize: pageSize
        )
        if let cursor, cursor.queryFingerprint != fingerprint {
            throw ListQueryContractFailure.cursorQueryMismatch
        }

        self.profile = profile
        sort = descriptor
        self.activeFilters = normalizedFilters
        self.search = search
        self.pageSize = pageSize
        self.cursor = cursor
        self.fingerprint = fingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let descriptor = try container.decode(StableSortDescriptor.self, forKey: .sort)
        try self.init(
            profile: container.decode(NamedListQueryProfile.self, forKey: .profile),
            sortId: descriptor.sortId,
            direction: descriptor.direction,
            activeFilters: container.decode([NamedFilterID].self, forKey: .activeFilters),
            search: container.decodeIfPresent(ListSearchTerm.self, forKey: .search),
            pageSize: container.decode(UInt16.self, forKey: .pageSize),
            cursor: container.decodeIfPresent(StableCursor.self, forKey: .cursor)
        )
        guard descriptor.cursorContractVersion == sort.cursorContractVersion,
              descriptor.tieBreaker == sort.tieBreaker else {
            throw ListQueryContractFailure.cursorQueryMismatch
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encode(sort, forKey: .sort)
        try container.encode(activeFilters, forKey: .activeFilters)
        try container.encodeIfPresent(search, forKey: .search)
        try container.encode(pageSize, forKey: .pageSize)
        try container.encodeIfPresent(cursor, forKey: .cursor)
    }

    public func cursor(validating opaqueValue: String) throws -> StableCursor {
        try StableCursor(validating: opaqueValue, queryFingerprint: fingerprint)
    }

    public func validate(_ intent: ListPresentationIntent) throws {
        switch intent {
        case .changeSort(let id, let direction):
            guard let option = profile.sortOption(id: id) else {
                throw ListQueryContractFailure.unsupportedSort(id)
            }
            guard option.allowedDirections.contains(direction) else {
                throw ListQueryContractFailure.unsupportedSortDirection(id)
            }
        case .setFilter(let id, _):
            guard profile.filters.contains(id) else {
                throw ListQueryContractFailure.unsupportedFilter(id)
            }
        case .setSearch(let search):
            guard search == nil || profile.allowsSearch else {
                throw ListQueryContractFailure.invalidSearchTerm
            }
        case .requestNextPage(let cursor):
            guard cursor.queryFingerprint == fingerprint else {
                throw ListQueryContractFailure.cursorQueryMismatch
            }
        case .retry(let retry):
            guard retry.profileId == profile.id,
                  retry.queryFingerprint == fingerprint else {
                throw ListQueryContractFailure.retryQueryMismatch
            }
        case .add(let action):
            guard profile.actions.contains(action) else {
                throw ListQueryContractFailure.unsupportedAction(action)
            }
        case .setSelection, .clearSelection:
            break
        }
    }

    private static func makeFingerprint(
        profileId: NamedQueryProfileID,
        sort: StableSortDescriptor,
        filters: [NamedFilterID],
        search: ListSearchTerm?,
        pageSize: UInt16
    ) throws -> ListQueryFingerprint {
        let basis = ListQueryFingerprintBasis(
            profileId: profileId,
            sort: sort,
            filters: filters,
            search: search,
            pageSize: pageSize
        )
        let data = try OperationContractCodec.encode(basis)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return try ListQueryFingerprint(validating: digest)
    }

    private static func firstDuplicate<Value: Hashable>(_ values: [Value]) -> Value? {
        var seen: Set<Value> = []
        return values.first { !seen.insert($0).inserted }
    }

    private struct ListQueryFingerprintBasis: Codable {
        let profileId: NamedQueryProfileID
        let sort: StableSortDescriptor
        let filters: [NamedFilterID]
        let search: ListSearchTerm?
        let pageSize: UInt16
    }

    private enum CodingKeys: String, CodingKey {
        case profile
        case sort
        case activeFilters
        case search
        case pageSize
        case cursor
    }
}

public enum ListReadiness: String, Codable, CaseIterable, Sendable {
    case notRequested
    case loading
    case ready
    case partial
    case stale
    case blocked
}

public enum ListEmptyState: String, Codable, CaseIterable, Sendable {
    case authoritativeEmpty
    case noMatches
}

public enum ListFailureState: String, Codable, CaseIterable, Sendable {
    case unavailable
    case retryable
    case requiredUpdate
}

enum ListQueryFailureCause: String, Codable, CaseIterable, Sendable {
    case notFound
    case notAuthorized
    case notAuthenticated
    case transientInfrastructure
    case requiredUpdate
    case unsupportedContract

    var presentation: ListFailureState {
        switch self {
        case .notFound, .notAuthorized, .notAuthenticated:
            .unavailable
        case .transientInfrastructure:
            .retryable
        case .requiredUpdate, .unsupportedContract:
            .requiredUpdate
        }
    }
}

public enum ListSnapshotQuality: String, Codable, CaseIterable, Sendable {
    case ready
    case partial
    case stale

    public var readiness: ListReadiness {
        switch self {
        case .ready: .ready
        case .partial: .partial
        case .stale: .stale
        }
    }
}

public struct ListLocalSnapshot<Row: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let queryFingerprint: ListQueryFingerprint
    public let rows: [Row]
    public let visibleRowCountBeforeFiltering: Int
    public let isCompleteForQuery: Bool
    public let quality: ListSnapshotQuality
    public let localDataVersion: LocalDataVersion
    public let asOf: Date

    public init(
        queryFingerprint: ListQueryFingerprint,
        rows: [Row],
        visibleRowCountBeforeFiltering: Int,
        isCompleteForQuery: Bool,
        quality: ListSnapshotQuality,
        localDataVersion: LocalDataVersion,
        asOf: Date
    ) throws {
        guard visibleRowCountBeforeFiltering >= 0,
              visibleRowCountBeforeFiltering >= rows.count else {
            throw ListQueryContractFailure.invalidVisibleRowCount
        }
        guard quality == .ready || !isCompleteForQuery else {
            throw ListQueryContractFailure.incompleteAuthoritativeEmpty
        }
        self.queryFingerprint = queryFingerprint
        self.rows = rows
        self.visibleRowCountBeforeFiltering = visibleRowCountBeforeFiltering
        self.isCompleteForQuery = isCompleteForQuery
        self.quality = quality
        self.localDataVersion = localDataVersion
        self.asOf = asOf
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            queryFingerprint: container.decode(ListQueryFingerprint.self, forKey: .queryFingerprint),
            rows: container.decode([Row].self, forKey: .rows),
            visibleRowCountBeforeFiltering: container.decode(
                Int.self,
                forKey: .visibleRowCountBeforeFiltering
            ),
            isCompleteForQuery: container.decode(Bool.self, forKey: .isCompleteForQuery),
            quality: container.decode(ListSnapshotQuality.self, forKey: .quality),
            localDataVersion: container.decode(LocalDataVersion.self, forKey: .localDataVersion),
            asOf: container.decode(Date.self, forKey: .asOf)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case queryFingerprint
        case rows
        case visibleRowCountBeforeFiltering
        case isCompleteForQuery
        case quality
        case localDataVersion
        case asOf
    }
}

public enum ListQueryUpdate<Row: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    case waiting(ListReadiness)
    case snapshot(ListLocalSnapshot<Row>)
    case failed(failure: ListFailureState, cached: ListLocalSnapshot<Row>?)
}

public struct RetryQueryIntent: Codable, Equatable, Sendable {
    public let profileId: NamedQueryProfileID
    public let queryFingerprint: ListQueryFingerprint

    public init(profileId: NamedQueryProfileID, queryFingerprint: ListQueryFingerprint) {
        self.profileId = profileId
        self.queryFingerprint = queryFingerprint
    }
}

public enum ListPresentationIntent: Codable, Equatable, Sendable {
    case changeSort(id: NamedSortID, direction: SortDirection)
    case setFilter(id: NamedFilterID, isActive: Bool)
    case setSearch(ListSearchTerm?)
    case requestNextPage(StableCursor)
    case retry(RetryQueryIntent)
    case add(NamedListActionID)
    case setSelection(entityId: EntityID, isSelected: Bool)
    case clearSelection
}

public struct ListPresentationSnapshot<Row: Codable & Equatable & Sendable>: Equatable, Sendable {
    public let queryFingerprint: ListQueryFingerprint
    public let rows: [Row]
    public let readiness: ListReadiness
    public let emptyState: ListEmptyState?
    public let failure: ListFailureState?
    public let localDataVersion: LocalDataVersion?
    public let asOf: Date?

    public var retryIntent: RetryQueryIntent? {
        guard failure == .retryable else { return nil }
        return RetryQueryIntent(
            profileId: profileId,
            queryFingerprint: queryFingerprint
        )
    }

    private let profileId: NamedQueryProfileID

    fileprivate init(
        profileId: NamedQueryProfileID,
        queryFingerprint: ListQueryFingerprint,
        rows: [Row],
        readiness: ListReadiness,
        emptyState: ListEmptyState?,
        failure: ListFailureState?,
        localDataVersion: LocalDataVersion?,
        asOf: Date?
    ) {
        self.profileId = profileId
        self.queryFingerprint = queryFingerprint
        self.rows = rows
        self.readiness = readiness
        self.emptyState = emptyState
        self.failure = failure
        self.localDataVersion = localDataVersion
        self.asOf = asOf
    }
}

public enum ListPresentationReducer {
    public static func reduce<Row>(
        query: ListQueryState,
        update: ListQueryUpdate<Row>
    ) throws -> ListPresentationSnapshot<Row> where Row: Codable & Equatable & Sendable {
        switch update {
        case .waiting(let readiness):
            guard [.notRequested, .loading, .blocked].contains(readiness) else {
                throw ListQueryContractFailure.incompleteAuthoritativeEmpty
            }
            return ListPresentationSnapshot(
                profileId: query.profile.id,
                queryFingerprint: query.fingerprint,
                rows: [],
                readiness: readiness,
                emptyState: nil,
                failure: nil,
                localDataVersion: nil,
                asOf: nil
            )

        case .snapshot(let snapshot):
            try validate(snapshot, matches: query)
            return ListPresentationSnapshot(
                profileId: query.profile.id,
                queryFingerprint: query.fingerprint,
                rows: snapshot.rows,
                readiness: snapshot.quality.readiness,
                emptyState: emptyState(for: snapshot),
                failure: nil,
                localDataVersion: snapshot.localDataVersion,
                asOf: snapshot.asOf
            )

        case .failed(let failure, let cached):
            if failure == .unavailable {
                return ListPresentationSnapshot(
                    profileId: query.profile.id,
                    queryFingerprint: query.fingerprint,
                    rows: [],
                    readiness: .blocked,
                    emptyState: nil,
                    failure: .unavailable,
                    localDataVersion: nil,
                    asOf: nil
                )
            }
            if let cached {
                try validate(cached, matches: query)
                return ListPresentationSnapshot(
                    profileId: query.profile.id,
                    queryFingerprint: query.fingerprint,
                    rows: cached.rows,
                    readiness: .stale,
                    emptyState: nil,
                    failure: failure,
                    localDataVersion: cached.localDataVersion,
                    asOf: cached.asOf
                )
            }
            return ListPresentationSnapshot(
                profileId: query.profile.id,
                queryFingerprint: query.fingerprint,
                rows: [],
                readiness: .blocked,
                emptyState: nil,
                failure: failure,
                localDataVersion: nil,
                asOf: nil
            )
        }
    }

    private static func validate<Row>(
        _ snapshot: ListLocalSnapshot<Row>,
        matches query: ListQueryState
    ) throws where Row: Codable & Equatable & Sendable {
        guard snapshot.queryFingerprint == query.fingerprint else {
            throw ListQueryContractFailure.querySnapshotMismatch
        }
    }

    private static func emptyState<Row>(
        for snapshot: ListLocalSnapshot<Row>
    ) -> ListEmptyState? where Row: Codable & Equatable & Sendable {
        guard snapshot.rows.isEmpty,
              snapshot.quality == .ready,
              snapshot.isCompleteForQuery else {
            return nil
        }
        return snapshot.visibleRowCountBeforeFiltering == 0
            ? .authoritativeEmpty
            : .noMatches
    }
}
