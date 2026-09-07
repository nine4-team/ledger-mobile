import Foundation

/// Source identities from one Account's export, not target authorization or an
/// assertion that the exported collection is complete.
public struct FirebaseLineageReferenceIndex: Sendable {
    public let accountScopeID: String
    fileprivate let itemIDs: Set<Data>
    fileprivate let transactionIDs: Set<Data>
    fileprivate let projectIDs: Set<Data>

    public init(accountScopeID: String, itemIDs: [String],
                transactionIDs: [String], projectIDs: [String]) {
        self.accountScopeID = accountScopeID
        self.itemIDs = Set(itemIDs.map { Data($0.utf8) })
        self.transactionIDs = Set(transactionIDs.map { Data($0.utf8) })
        self.projectIDs = Set(projectIDs.map { Data($0.utf8) })
    }
}

public enum FirebaseLineageReferenceIssue: Equatable, Sendable {
    case invalidSourceEvidence
    case accountScopeMismatch
    case duplicateDocument
    case conflictingDocument
    case missingItem(String)
    case missingTransaction(String)
    case missingProject(String)
}

public struct ReconciledFirebaseLineageEvidence: Equatable, Sendable {
    public let source: FirebaseLineageEvidence
    public let issues: [FirebaseLineageReferenceIssue]

    /// Only eligibility for later semantic mapping, not proof of target history
    /// completeness, correct accounting, or migration success.
    public var canAttemptMapping: Bool { issues.isEmpty }
}

public enum FirebaseLineageReconciler {
    private struct SourceKey: Hashable {
        let account: Data
        let document: Data
    }
    /// Preserves input order and every raw record, including conflicting copies.
    /// Absent references remain unknown: they do not prove deletion or Inventory
    /// placement, and a source `returned` edge never implies a cash refund.
    public static func reconcile(
        _ records: [FirebaseLineageEvidence],
        against index: FirebaseLineageReferenceIndex
    ) -> [ReconciledFirebaseLineageEvidence] {
        let groups = Dictionary(grouping: records) {
            SourceKey(account: Data($0.sourceAccountScopeID.utf8), document: Data($0.lineageDocumentID.utf8))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let duplicateIssues = groups.compactMapValues { copies -> FirebaseLineageReferenceIssue? in
            guard copies.count > 1 else { return nil }
            guard let first = try? encoder.encode(copies[0].rawFields) else { return .conflictingDocument }
            return copies.dropFirst().allSatisfy { (try? encoder.encode($0.rawFields)) == first }
                ? .duplicateDocument : .conflictingDocument
        }
        return records.map { record in
            var issues: [FirebaseLineageReferenceIssue] = []
            if !record.isStructurallyValid { issues.append(.invalidSourceEvidence) }
            let sameEnvelope = record.sourceAccountScopeID.utf8.elementsEqual(index.accountScopeID.utf8)
            let sameEmbeddedAccount = record.accountID.map { $0.utf8.elementsEqual(index.accountScopeID.utf8) }
            if !sameEnvelope || sameEmbeddedAccount == false {
                issues.append(.accountScopeMismatch)
            }
            let key = SourceKey(account: Data(record.sourceAccountScopeID.utf8), document: Data(record.lineageDocumentID.utf8))
            if let issue = duplicateIssues[key] { issues.append(issue) }
            // Do not cross-resolve a mismatched Account against this index.
            if sameEnvelope && sameEmbeddedAccount == true {
                if let id = record.itemID, !index.itemIDs.contains(Data(id.utf8)) {
                    issues.append(.missingItem(id))
                }
                for id in [record.fromTransactionID, record.toTransactionID].compactMap({ $0 }) {
                    if !index.transactionIDs.contains(Data(id.utf8)) { issues.append(.missingTransaction(id)) }
                }
                for id in [record.fromProjectID, record.toProjectID].compactMap({ $0 }) {
                    if !index.projectIDs.contains(Data(id.utf8)) { issues.append(.missingProject(id)) }
                }
            }
            return ReconciledFirebaseLineageEvidence(source: record, issues: issues)
        }
    }
}
