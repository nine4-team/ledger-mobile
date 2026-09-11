import Foundation

/// Downloaded app read boundary. Online MCP uses the same snapshot content but
/// authoritative source evidence, never fabricated download readiness.
public protocol PropertyManagementReportReading: Sendable {
    func readDownloadedPropertyManagementReport(accountId: AccountID, projectId: ProjectID,
        currency: CurrencyCode, asOf: ProtectedArtifactEpochMilliseconds) async throws -> PropertyManagementReportSnapshot
}

public enum PropertyManagementReportUpdate: Equatable, Sendable {
    case incomplete
    case ready(PropertyManagementReportSnapshot)
}

public protocol PropertyManagementReportWatching: Sendable {
    func watchPropertyManagementReport(accountId: AccountID, projectId: ProjectID,
        currency: CurrencyCode) -> AsyncThrowingStream<PropertyManagementReportUpdate, Error>
}

public enum PropertyManagementReportFailure: Error, Equatable, Sendable {
    case incompleteReadiness, scopeMismatch, invalidRevision
    case duplicateItem, duplicatePlacement, duplicateSpace, missingSpace, mixedCurrency
}

public struct PropertyManagementReportProject: Encodable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let name: String
    public let address: String?
    public let revision: UInt64

    public init(accountId: AccountID, projectId: ProjectID, name: String, address: String?, revision: UInt64) {
        self.accountId = accountId; self.projectId = projectId
        self.name = name; self.address = address; self.revision = revision
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(accountId, forKey: .accountId)
        try values.encode(projectId, forKey: .projectId)
        try values.encode(name, forKey: .name)
        try values.encode(address, forKey: .address)
        try values.encode(String(revision), forKey: .revision)
    }
    private enum CodingKeys: String, CodingKey { case accountId, projectId, name, address, revision }
}

public struct PropertyManagementReportSpace: Encodable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let spaceId: SpaceID
    public let name: String
    public let revision: UInt64

    public init(accountId: AccountID, projectId: ProjectID, spaceId: SpaceID, name: String, revision: UInt64) {
        self.accountId = accountId; self.projectId = projectId; self.spaceId = spaceId
        self.name = name; self.revision = revision
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(accountId, forKey: .accountId)
        try values.encode(projectId, forKey: .projectId)
        try values.encode(spaceId, forKey: .spaceId)
        try values.encode(name, forKey: .name)
        try values.encode(String(revision), forKey: .revision)
    }
    private enum CodingKeys: String, CodingKey { case accountId, projectId, spaceId, name, revision }
}

public struct PropertyManagementReportItem: Encodable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let itemId: ItemID
    public let placementId: EntityID
    public let spaceId: SpaceID?
    public let name: String
    public let sku: String?
    public let marketValue: Money?
    public let itemRevision: UInt64
    public let accounting: ProjectItemAccountingRow?

    public init(accountId: AccountID, projectId: ProjectID, itemId: ItemID, placementId: EntityID,
                spaceId: SpaceID?, name: String, sku: String?, marketValue: Money?, itemRevision: UInt64,
                accounting: ProjectItemAccountingRow? = nil) {
        self.accountId = accountId; self.projectId = projectId; self.itemId = itemId; self.placementId = placementId
        self.spaceId = spaceId; self.name = name; self.sku = sku; self.marketValue = marketValue; self.itemRevision = itemRevision
        self.accounting = accounting
    }

    // JSON consumers must not round exact cents through a JavaScript Number.
    // Null stays explicit; a zero-valued Money is a known value.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(accountId, forKey: .accountId)
        try values.encode(projectId, forKey: .projectId)
        try values.encode(itemId, forKey: .itemId)
        try values.encode(placementId, forKey: .placementId)
        try values.encode(spaceId, forKey: .spaceId)
        try values.encode(name, forKey: .name)
        try values.encode(sku, forKey: .sku)
        try values.encode(marketValue.map { String($0.minorUnits) }, forKey: .marketValueMinorUnits)
        try values.encode(marketValue?.currency, forKey: .marketValueCurrency)
        try values.encode(String(itemRevision), forKey: .itemRevision)
    }
    private enum CodingKeys: String, CodingKey {
        case accountId, projectId, itemId, placementId, spaceId, name, sku
        case marketValueMinorUnits, marketValueCurrency, itemRevision
    }
}

public enum PropertyManagementReportSource: Encodable, Equatable, Sendable {
    case downloaded(localDataVersion: LocalDataVersion, lastSyncedAt: ProtectedArtifactEpochMilliseconds)
    case authoritative

    public var kind: String {
        switch self { case .downloaded: "downloaded"; case .authoritative: "authoritative" }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        if case .downloaded(let version, let syncedAt) = self {
            try values.encode(version, forKey: .localDataVersion)
            try values.encode(syncedAt, forKey: .lastSyncedAt)
        }
    }
    private enum CodingKeys: String, CodingKey { case kind, localDataVersion, lastSyncedAt }
}

/// Provider evidence, not an authorization grant. Both sources require current
/// scope authorization and one coherent SQL read of Items/placements/parents.
/// Downloaded data additionally requires the exact retained stream checkpoint.
/// Public construction and `.ready` do not establish those provider guarantees.
public struct PropertyManagementReportProvenance: Encodable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let principalId: PrincipalID
    public let visibilityScopeID: ProtectedArtifactVisibilityScopeID
    public let source: PropertyManagementReportSource
    public let authorityVersion: ProtectedArtifactAuthorityVersion
    public let asOf: ProtectedArtifactEpochMilliseconds
    public let readiness: ListSnapshotQuality
    public var localDataVersion: LocalDataVersion? {
        if case .downloaded(let version, _) = source { return version }
        return nil
    }
    public var lastSyncedAt: ProtectedArtifactEpochMilliseconds? {
        if case .downloaded(_, let timestamp) = source { return timestamp }
        return nil
    }

    public init(accountId: AccountID, projectId: ProjectID, principalId: PrincipalID,
                visibilityScopeID: ProtectedArtifactVisibilityScopeID, localDataVersion: LocalDataVersion,
                authorityVersion: ProtectedArtifactAuthorityVersion, asOf: ProtectedArtifactEpochMilliseconds,
                readiness: ListSnapshotQuality, lastSyncedAt: ProtectedArtifactEpochMilliseconds) {
        self.init(accountId: accountId, projectId: projectId, principalId: principalId,
            visibilityScopeID: visibilityScopeID, source: .downloaded(localDataVersion: localDataVersion, lastSyncedAt: lastSyncedAt),
            authorityVersion: authorityVersion, asOf: asOf, readiness: readiness)
    }

    public init(accountId: AccountID, projectId: ProjectID, principalId: PrincipalID,
                visibilityScopeID: ProtectedArtifactVisibilityScopeID, source: PropertyManagementReportSource,
                authorityVersion: ProtectedArtifactAuthorityVersion, asOf: ProtectedArtifactEpochMilliseconds,
                readiness: ListSnapshotQuality) {
        self.accountId = accountId; self.projectId = projectId; self.principalId = principalId
        self.visibilityScopeID = visibilityScopeID; self.source = source
        self.authorityVersion = authorityVersion; self.asOf = asOf
        self.readiness = readiness
    }
}

public struct PropertyManagementReportTotals: Encodable, Equatable, Sendable {
    public let itemCount: Int
    public let knownMarketValueSubtotal: Money
    public let unknownMarketValueCount: Int
    /// A partial known subtotal is never labelled as a complete valuation.
    public var totalMarketValue: Money? { unknownMarketValueCount == 0 ? knownMarketValueSubtotal : nil }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(itemCount, forKey: .itemCount)
        try values.encode(String(knownMarketValueSubtotal.minorUnits), forKey: .knownMarketValueSubtotalMinorUnits)
        try values.encode(knownMarketValueSubtotal.currency, forKey: .currency)
        try values.encode(unknownMarketValueCount, forKey: .unknownMarketValueCount)
        try values.encode(totalMarketValue.map { String($0.minorUnits) }, forKey: .totalMarketValueMinorUnits)
    }
    private enum CodingKeys: String, CodingKey {
        case itemCount, knownMarketValueSubtotalMinorUnits, currency, unknownMarketValueCount, totalMarketValueMinorUnits
    }
}

public struct PropertyManagementReportGroup: Encodable, Equatable, Sendable {
    /// Nil identifies No Space; an actual Space named "No Space" remains distinct.
    public let spaceId: SpaceID?
    public let name: String
    public let rows: [PropertyManagementReportItem]
    public let totals: PropertyManagementReportTotals
}

/// One concrete projection for preview, PDF, print, CSV and MCP. Its factory
/// checks internal coherence only. It does not authorize exports, authenticate
/// checkpoints or promote a downloaded subset into a complete report.
public struct PropertyManagementReportSnapshot: Encodable, Equatable, Sendable {
    public let reference: ProtectedArtifactSnapshotReference
    public let project: PropertyManagementReportProject
    public let provenance: PropertyManagementReportProvenance
    public let currency: CurrencyCode
    /// Includes every supplied parent and revision, even an unoccupied Space.
    public let spaces: [PropertyManagementReportSpace]
    public let groups: [PropertyManagementReportGroup]
    public let totals: PropertyManagementReportTotals
    public let sourceSetHash: ProtectedArtifactSHA256
    public let reportKind = "property_management"

    public static func build(project: PropertyManagementReportProject, spaces: [PropertyManagementReportSpace],
                             items: [PropertyManagementReportItem], currency: CurrencyCode,
                             provenance: PropertyManagementReportProvenance) throws -> Self {
        guard provenance.readiness == .ready else { throw PropertyManagementReportFailure.incompleteReadiness }
        guard project.accountId == provenance.accountId, project.projectId == provenance.projectId else {
            throw PropertyManagementReportFailure.scopeMismatch
        }
        guard project.revision > 0 else { throw PropertyManagementReportFailure.invalidRevision }
        var spaceIDs = Set<SpaceID>()
        for space in spaces {
            guard space.accountId == project.accountId, space.projectId == project.projectId else {
                throw PropertyManagementReportFailure.scopeMismatch
            }
            guard space.revision > 0 else { throw PropertyManagementReportFailure.invalidRevision }
            guard spaceIDs.insert(space.spaceId).inserted else { throw PropertyManagementReportFailure.duplicateSpace }
        }
        var itemIDs = Set<ItemID>()
        var placementIDs = Set<EntityID>()
        for item in items {
            guard item.accountId == project.accountId, item.projectId == project.projectId else {
                throw PropertyManagementReportFailure.scopeMismatch
            }
            guard item.itemRevision > 0 else { throw PropertyManagementReportFailure.invalidRevision }
            guard itemIDs.insert(item.itemId).inserted else { throw PropertyManagementReportFailure.duplicateItem }
            guard placementIDs.insert(item.placementId).inserted else { throw PropertyManagementReportFailure.duplicatePlacement }
            if let spaceId = item.spaceId, !spaceIDs.contains(spaceId) { throw PropertyManagementReportFailure.missingSpace }
            if item.accounting?.resolution == .accountedFor,
               let amount = item.marketValue, amount.currency != currency {
                throw PropertyManagementReportFailure.mixedCurrency
            }
            guard let accounting = item.accounting,
                  accounting.resolution != .relationshipEvidenceIncomplete else {
                throw PropertyManagementReportFailure.incompleteReadiness
            }
            guard accounting.evidence.accountId == item.accountId,
                  accounting.evidence.projectId == item.projectId,
                  accounting.evidence.itemId == item.itemId,
                  accounting.evidence.spaceId == item.spaceId else {
                throw PropertyManagementReportFailure.scopeMismatch
            }
        }
        // Locale-independent byte order, with exact identity as the tie-breaker.
        func ordered(_ nameA: String, _ idA: String, _ nameB: String, _ idB: String) -> Bool {
            let a = Array(nameA.utf8), b = Array(nameB.utf8)
            return a == b ? idA.utf8.lexicographicallyPrecedes(idB.utf8) : a.lexicographicallyPrecedes(b)
        }
        let sortedSpaces = spaces.sorted { ordered($0.name, $0.spaceId.rawValue, $1.name, $1.spaceId.rawValue) }
        let sortedItems = items.filter { $0.accounting?.resolution == .accountedFor }
            .sorted { ordered($0.name, $0.itemId.rawValue, $1.name, $1.itemId.rawValue) }
        func summarize(_ rows: [PropertyManagementReportItem]) throws -> PropertyManagementReportTotals {
            var known = Money.zero(currency: currency)
            var unknown = 0
            for row in rows {
                if let amount = row.marketValue { known = try known.adding(amount) } else { unknown += 1 }
            }
            return .init(itemCount: rows.count, knownMarketValueSubtotal: known, unknownMarketValueCount: unknown)
        }
        var groups: [PropertyManagementReportGroup] = []
        for space in sortedSpaces {
            let rows = sortedItems.filter { $0.spaceId == space.spaceId }
            if !rows.isEmpty { groups.append(.init(spaceId: space.spaceId, name: space.name, rows: rows, totals: try summarize(rows))) }
        }
        let unplaced = sortedItems.filter { $0.spaceId == nil }
        if !unplaced.isEmpty { groups.append(.init(spaceId: nil, name: "No Space", rows: unplaced, totals: try summarize(unplaced))) }
        let totals = try summarize(sortedItems)
        // Bind exclusion decisions too, without exporting excluded Item details
        // or their private accounting relationships in the report envelope.
        let accountingHash = try ProtectedArtifactSHA256.make(bytes: encode(items
            .sorted { $0.itemId.rawValue.utf8.lexicographicallyPrecedes($1.itemId.rawValue.utf8) }
            .map(\.accounting)))
        let sourceHash = try ProtectedArtifactSHA256.make(bytes: encode(SourceSet(project: project, spaces: sortedSpaces,
            items: sortedItems, accountingEvidenceHash: accountingHash)))
        let payload = Content(reportKind: "property_management", project: project, provenance: provenance, currency: currency,
            spaces: sortedSpaces, groups: groups, totals: totals, sourceSetHash: sourceHash)
        let hash = try ProtectedArtifactSHA256.make(bytes: encode(payload))
        let reference = try ProtectedArtifactSnapshotReference(snapshotID: .init(validating: String(hash.rawValue.prefix(32))),
            snapshotHash: hash, visibilityScopeID: provenance.visibilityScopeID,
            profileVersion: .init(validating: "property-management-v1"), authorityVersion: provenance.authorityVersion)
        return .init(reference: reference, project: project, provenance: provenance, currency: currency,
            spaces: sortedSpaces, groups: groups, totals: totals, sourceSetHash: sourceHash)
    }

    /// The canonical envelope includes `reference`. Its digest is NOT the
    /// snapshotHash; the reference binds the content bytes below without a
    /// circular self-hash.
    public func canonicalData() throws -> Data { try Self.encode(self) }

    /// Exact bytes hashed by reference.snapshotHash and used to derive its ID.
    public func canonicalContentData() throws -> Data {
        try Self.encode(Content(reportKind: reportKind, project: project, provenance: provenance, currency: currency,
            spaces: spaces, groups: groups, totals: totals, sourceSetHash: sourceSetHash))
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private struct SourceSet: Encodable {
        let project: PropertyManagementReportProject
        let spaces: [PropertyManagementReportSpace]
        let items: [PropertyManagementReportItem]
        let accountingEvidenceHash: ProtectedArtifactSHA256
    }
    private struct Content: Encodable {
        let reportKind: String
        let project: PropertyManagementReportProject
        let provenance: PropertyManagementReportProvenance
        let currency: CurrencyCode
        let spaces: [PropertyManagementReportSpace]
        let groups: [PropertyManagementReportGroup]
        let totals: PropertyManagementReportTotals
        let sourceSetHash: ProtectedArtifactSHA256
    }
}
