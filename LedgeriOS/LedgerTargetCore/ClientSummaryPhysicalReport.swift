import Foundation

public enum ClientSummaryPhysicalReportUpdate: Equatable, Sendable {
    case incomplete
    case ready(ClientSummaryPhysicalReportSnapshot)
}

public protocol ClientSummaryPhysicalReportWatching: Sendable {
    func watchClientSummaryPhysicalReport(accountId: AccountID, projectId: ProjectID)
        -> AsyncThrowingStream<ClientSummaryPhysicalReportUpdate, Error>
}

public protocol ClientSummaryPhysicalReportReading: Sendable {
    func readDownloadedClientSummaryPhysicalReport(accountId: AccountID, projectId: ProjectID,
        asOf: ProtectedArtifactEpochMilliseconds) async throws -> ClientSummaryPhysicalReportSnapshot
}

public enum ClientSummaryPhysicalReportClient: Encodable, Equatable, Sendable {
    case known(clientId: ClientID, name: String, revision: UInt64)
    case unavailable(clientId: ClientID)

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .known(let id, let name, let revision):
            try values.encode("known", forKey: .kind)
            try values.encode(id, forKey: .clientId)
            try values.encode(name, forKey: .name)
            try values.encode(String(revision), forKey: .revision)
        case .unavailable(let id):
            try values.encode("unavailable", forKey: .kind)
            try values.encode(id, forKey: .clientId)
        }
    }
    private enum CodingKeys: String, CodingKey { case kind, clientId, name, revision }
}

/// Missing association evidence is not an uncategorized Item. The reader must
/// supply the actual physical Item category identity, never an Invoice fallback.
public enum ClientSummaryPhysicalReportCategory: Encodable, Equatable, Sendable {
    case known(categoryId: BudgetCategoryID, name: String)
    case unavailable
}

public struct ClientSummaryPhysicalReportItem: Encodable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let itemId: ItemID
    public let placementId: EntityID
    public let spaceId: SpaceID?
    public let name: String
    public let sku: String?
    public let category: ClientSummaryPhysicalReportCategory
    public let itemRevision: UInt64
    public let accounting: ProjectItemAccountingRow?

    public init(accountId: AccountID, projectId: ProjectID, itemId: ItemID,
                placementId: EntityID, spaceId: SpaceID?, name: String, sku: String?,
                category: ClientSummaryPhysicalReportCategory, itemRevision: UInt64,
                accounting: ProjectItemAccountingRow? = nil) {
        self.accountId = accountId; self.projectId = projectId; self.itemId = itemId
        self.placementId = placementId; self.spaceId = spaceId; self.name = name
        self.sku = sku; self.category = category; self.itemRevision = itemRevision
        self.accounting = accounting
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(accountId, forKey: .accountId)
        try values.encode(projectId, forKey: .projectId)
        try values.encode(itemId, forKey: .itemId)
        try values.encode(placementId, forKey: .placementId)
        try values.encode(spaceId, forKey: .spaceId)
        try values.encode(name, forKey: .name)
        try values.encode(sku, forKey: .sku)
        try values.encode(category, forKey: .category)
        try values.encode(String(itemRevision), forKey: .itemRevision)
        try values.encode(accounting, forKey: .accounting)
    }
    private enum CodingKeys: String, CodingKey {
        case accountId, projectId, itemId, placementId, spaceId, name, sku, category, itemRevision, accounting
    }
}

public enum ClientSummaryPhysicalReportFailure: Error, Equatable, Sendable {
    case incompleteReadiness, scopeMismatch, invalidRevision
    case duplicateItem, duplicatePlacement, duplicateSpace, missingSpace, conflictingCategory
}

/// Physical detail only. Financial totals, budgets and receipt links are separate
/// governed capabilities and are deliberately absent from this payload.
public struct ClientSummaryPhysicalReportSnapshot: Encodable, Equatable, Sendable {
    public let reference: ProtectedArtifactSnapshotReference
    public let project: PropertyManagementReportProject
    public let client: ClientSummaryPhysicalReportClient
    public let spaces: [PropertyManagementReportSpace]
    public let items: [ClientSummaryPhysicalReportItem]
    public let provenance: PropertyManagementReportProvenance
    public let sourceSetHash: ProtectedArtifactSHA256
    public let accountingEvidenceHash: ProtectedArtifactSHA256
    public let reportKind = "client_summary_physical"

    /// Incomplete detail may be previewed, but cannot become a completed export.
    public var isComplete: Bool {
        guard case .known = client else { return false }
        return items.allSatisfy {
            guard $0.accounting?.resolution == .accountedFor else { return false }
            if case .known = $0.category { return true }; return false
        }
    }

    public static func build(project: PropertyManagementReportProject,
                             client: ClientSummaryPhysicalReportClient,
                             spaces: [PropertyManagementReportSpace],
                             items: [ClientSummaryPhysicalReportItem],
                             provenance: PropertyManagementReportProvenance) throws -> Self {
        guard provenance.readiness == .ready else { throw ClientSummaryPhysicalReportFailure.incompleteReadiness }
        guard project.accountId == provenance.accountId, project.projectId == provenance.projectId else {
            throw ClientSummaryPhysicalReportFailure.scopeMismatch
        }
        guard project.revision > 0 else { throw ClientSummaryPhysicalReportFailure.invalidRevision }
        if case .known(_, let name, let revision) = client {
            guard revision > 0 else { throw ClientSummaryPhysicalReportFailure.invalidRevision }
            _ = try ClientDisplayName(validating: name)
        }
        var spaceIDs = Set<SpaceID>()
        for space in spaces {
            guard space.accountId == project.accountId, space.projectId == project.projectId else {
                throw ClientSummaryPhysicalReportFailure.scopeMismatch
            }
            guard space.revision > 0 else { throw ClientSummaryPhysicalReportFailure.invalidRevision }
            guard spaceIDs.insert(space.spaceId).inserted else { throw ClientSummaryPhysicalReportFailure.duplicateSpace }
        }
        var itemIDs = Set<ItemID>(), placementIDs = Set<EntityID>()
        var categoryNames: [BudgetCategoryID: String] = [:]
        let clientId: ClientID
        switch client {
        case .known(let id, _, _), .unavailable(let id): clientId = id
        }
        for item in items {
            guard item.accountId == project.accountId, item.projectId == project.projectId else {
                throw ClientSummaryPhysicalReportFailure.scopeMismatch
            }
            guard item.itemRevision > 0 else { throw ClientSummaryPhysicalReportFailure.invalidRevision }
            if let evidence = item.accounting?.evidence {
                guard evidence.accountId == item.accountId,
                      evidence.projectId == item.projectId,
                      evidence.clientId == clientId,
                      evidence.itemId == item.itemId,
                      evidence.spaceId == item.spaceId else {
                    throw ClientSummaryPhysicalReportFailure.scopeMismatch
                }
            }
            guard itemIDs.insert(item.itemId).inserted else { throw ClientSummaryPhysicalReportFailure.duplicateItem }
            guard placementIDs.insert(item.placementId).inserted else { throw ClientSummaryPhysicalReportFailure.duplicatePlacement }
            if let space = item.spaceId, !spaceIDs.contains(space) { throw ClientSummaryPhysicalReportFailure.missingSpace }
            if case .known(let id, let name) = item.category {
                _ = try BudgetCategoryName(validating: name)
                if let previous = categoryNames[id], !previous.utf8.elementsEqual(name.utf8) {
                    throw ClientSummaryPhysicalReportFailure.conflictingCategory
                }
                categoryNames[id] = name
            }
        }
        func ordered(_ a: String, _ aid: String, _ b: String, _ bid: String) -> Bool {
            a.utf8.elementsEqual(b.utf8) ? aid.utf8.lexicographicallyPrecedes(bid.utf8) : a.utf8.lexicographicallyPrecedes(b.utf8)
        }
        let spaces = spaces.sorted { ordered($0.name, $0.spaceId.rawValue, $1.name, $1.spaceId.rawValue) }
        let items = items.sorted { ordered($0.name, $0.itemId.rawValue, $1.name, $1.itemId.rawValue) }
        // Commit the eligibility evidence, including excluded identities, without
        // putting Unaccounted For physical detail in the report payload.
        let accountingEvidenceHash = try ProtectedArtifactSHA256.make(bytes: encode(items.sorted {
            $0.itemId.rawValue.utf8.lexicographicallyPrecedes($1.itemId.rawValue.utf8)
        }.map {
            AccountingSource(itemId: $0.itemId, accounting: $0.accounting)
        }))
        let reportItems = items.filter { $0.accounting?.resolution != .unaccountedFor }
        let source = Source(project: project, client: client, spaces: spaces, items: reportItems,
                            accountingEvidenceHash: accountingEvidenceHash)
        let sourceHash = try ProtectedArtifactSHA256.make(bytes: encode(source))
        let content = Content(reportKind: "client_summary_physical", source: source, provenance: provenance, sourceSetHash: sourceHash)
        let hash = try ProtectedArtifactSHA256.make(bytes: encode(content))
        let reference = try ProtectedArtifactSnapshotReference(snapshotID: .init(validating: String(hash.rawValue.prefix(32))),
            snapshotHash: hash, visibilityScopeID: provenance.visibilityScopeID,
            profileVersion: .init(validating: "client-summary-physical-v1"), authorityVersion: provenance.authorityVersion)
        return .init(reference: reference, project: project, client: client, spaces: spaces,
                     items: reportItems, provenance: provenance, sourceSetHash: sourceHash,
                     accountingEvidenceHash: accountingEvidenceHash)
    }

    public func canonicalData() throws -> Data { try Self.encode(self) }
    public func canonicalContentData() throws -> Data {
        try Self.encode(Content(reportKind: reportKind,
            source: Source(project: project, client: client, spaces: spaces, items: items,
                           accountingEvidenceHash: accountingEvidenceHash),
            provenance: provenance, sourceSetHash: sourceSetHash))
    }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private struct Source: Encodable {
        let project: PropertyManagementReportProject
        let client: ClientSummaryPhysicalReportClient
        let spaces: [PropertyManagementReportSpace]
        let items: [ClientSummaryPhysicalReportItem]
        let accountingEvidenceHash: ProtectedArtifactSHA256
    }
    private struct AccountingSource: Encodable {
        let itemId: ItemID
        let accounting: ProjectItemAccountingRow?
    }
    private struct Content: Encodable {
        let reportKind: String
        let source: Source
        let provenance: PropertyManagementReportProvenance
        let sourceSetHash: ProtectedArtifactSHA256
    }
}
