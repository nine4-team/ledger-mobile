import Foundation

public protocol TransactionExportReading: Sendable {
    /// The provider reads the complete authorized scope atomically, then applies
    /// the captured selection. nil means all; [] means a complete no-match set.
    func readTransactionExport(scope: TransactionScope, orderedTransactionIDs: [TransactionID]?,
                               asOf: ProtectedArtifactEpochMilliseconds) async throws -> TransactionExportSnapshot
}

/// Uses the same display/receipt facts as the browser, not a competing export
/// Transaction model. A reference binds even unselected authorized source rows,
/// so changes to the processed set cannot silently pass handoff revalidation.
public struct TransactionExportSnapshot: Encodable, Equatable, Sendable {
    public enum Failure: Error, Equatable { case incomplete, wrongScope, invalidSelection, missingReceipt }
    public let scope: TransactionScope
    public let principalId: PrincipalID
    public let asOf: ProtectedArtifactEpochMilliseconds
    public let sourceVersion: LocalDataVersion
    public let orderedTransactionIDs: [TransactionID]?
    public let rows: [TransactionDetailSnapshot]
    public let sourceSetHash: ProtectedArtifactSHA256
    public let reference: ProtectedArtifactSnapshotReference

    public init(scope: TransactionScope, principalId: PrincipalID, update: TransactionBrowserUpdate,
                orderedTransactionIDs: [TransactionID]? = nil, asOf: ProtectedArtifactEpochMilliseconds,
                sourceVersion: LocalDataVersion, visibilityScopeID: ProtectedArtifactVisibilityScopeID,
                authorityVersion: ProtectedArtifactAuthorityVersion) throws {
        guard scope.ownerKind == .project else { throw Failure.wrongScope }
        guard case .ready(let source) = update else { throw Failure.incomplete }
        guard source.allSatisfy({ $0.classification.scope == scope && $0.principalId == principalId }),
              Set(source.map(\.transactionId)).count == source.count else { throw Failure.wrongScope }
        guard source.allSatisfy({ $0.origin != .vendorPayment || $0.receipt != nil }) else { throw Failure.missingReceipt }
        let sourceRows = source.sorted { $0.transactionId.rawValue.utf8.lexicographicallyPrecedes($1.transactionId.rawValue.utf8) }
        let selected: [TransactionDetailSnapshot]
        if let ids = orderedTransactionIDs {
            let byID = Dictionary(uniqueKeysWithValues: source.map { ($0.transactionId, $0) })
            guard Set(ids).count == ids.count, ids.allSatisfy({ byID[$0] != nil }) else { throw Failure.invalidSelection }
            selected = ids.compactMap { byID[$0] }
        } else { selected = sourceRows }
        self.scope = scope; self.principalId = principalId; self.asOf = asOf
        self.sourceVersion = sourceVersion; self.orderedTransactionIDs = orderedTransactionIDs; rows = selected
        sourceSetHash = try .make(bytes: Self.encode(sourceRows))
        let content = Content(scope: scope, principalId: principalId, asOf: asOf, sourceVersion: sourceVersion,
            orderedTransactionIDs: orderedTransactionIDs, rows: selected, sourceSetHash: sourceSetHash,
            visibilityScopeID: visibilityScopeID, authorityVersion: authorityVersion)
        let hash = try ProtectedArtifactSHA256.make(bytes: Self.encode(content))
        reference = try .init(snapshotID: .init(validating: String(hash.rawValue.prefix(32))), snapshotHash: hash,
            visibilityScopeID: visibilityScopeID, profileVersion: .init(validating: "transaction-export-v1"),
            authorityVersion: authorityVersion)
    }

    public func canonicalData() throws -> Data { try Self.encode(self) }
    /// A processed selection is valid only for the complete source from which
    /// its filters/sort were evaluated, not a still-downloading browser subset.
    public func hasSameSourceRows(_ rows: [TransactionDetailSnapshot]) throws -> Bool {
        let ordered = rows.sorted { $0.transactionId.rawValue.utf8.lexicographicallyPrecedes($1.transactionId.rawValue.utf8) }
        return try ProtectedArtifactSHA256.make(bytes: Self.encode(ordered)) == sourceSetHash
    }
    public func canonicalContentData() throws -> Data {
        try Self.encode(Content(scope: scope, principalId: principalId, asOf: asOf, sourceVersion: sourceVersion,
            orderedTransactionIDs: orderedTransactionIDs, rows: rows, sourceSetHash: sourceSetHash,
            visibilityScopeID: reference.visibilityScopeID, authorityVersion: reference.authorityVersion))
    }
    private struct Content: Encodable {
        let scope: TransactionScope
        let principalId: PrincipalID
        let asOf: ProtectedArtifactEpochMilliseconds
        let sourceVersion: LocalDataVersion
        let orderedTransactionIDs: [TransactionID]?
        let rows: [TransactionDetailSnapshot]
        let sourceSetHash: ProtectedArtifactSHA256
        let visibilityScopeID: ProtectedArtifactVisibilityScopeID
        let authorityVersion: ProtectedArtifactAuthorityVersion
        let schemaVersion = "transaction-export-v1"
    }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
