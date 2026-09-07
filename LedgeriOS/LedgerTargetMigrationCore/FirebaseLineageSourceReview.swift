import Foundation

public struct FirebaseLineageSourceDocumentIssue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case invalidPath, accountScopeMismatch, nonRecordEvidence, duplicateDocument, invalidFields
    }
    public let sourceRecordID: String
    public let kind: Kind
}

public struct FirebaseLineageSourceReviewResult: Equatable, Sendable {
    /// Every document remains available, including unrelated and rejected evidence.
    public let documents: [FirebaseSourceDocument]
    public let lineage: [ReconciledFirebaseLineageEvidence]
    public let issues: [FirebaseLineageSourceDocumentIssue]
}

/// Connects validated source documents to lineage reconciliation. Collection paths,
/// not classification labels or current Item.transactionId, establish references.
/// This establishes source relationships only, never target accounting meaning.
public enum FirebaseLineageSourceReview {
    public static func review(_ fixture: ValidatedFirebaseSourceFixture) -> FirebaseLineageSourceReviewResult {
        review(documents: fixture.firestoreDocuments, accountScopeID: fixture.accountScopeID.rawValue)
    }

    // Package access permits source-shaped synthetic tests without adding them to
    // the frozen privacy-reviewed fixture catalog or opening an import bypass.
    package static func review(documents: [FirebaseSourceDocument], accountScopeID: String) -> FirebaseLineageSourceReviewResult {
        let collections: Set<String> = ["items", "transactions", "projects", "lineageEdges"]
        let paths = Dictionary(grouping: documents) { $0.documentPathSegments.map { Data($0.utf8) } }
        var issues: [FirebaseLineageSourceDocumentIssue] = []
        var items: [String] = [], transactions: [String] = [], projects: [String] = []
        var lineage: [FirebaseLineageEvidence] = []
        var invalidLineage: [Bool] = []

        for document in documents {
            let path = document.documentPathSegments
            // Recognize malformed/nested evidence too, so a lineage-shaped record
            // cannot silently disappear merely because its path is invalid.
            let collectionTokens = path.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
            let collection = collectionTokens.contains("lineageEdges") ? "lineageEdges"
                : collectionTokens.first { collections.contains($0) }
            guard let collection else { continue }
            let start = issues.count
            func reject(_ kind: FirebaseLineageSourceDocumentIssue.Kind) {
                issues.append(.init(sourceRecordID: document.sourceRecordID, kind: kind))
            }
            let validPath = path.count == 4 && path.first == "accounts"
                && path[2] == collection && (try? FirebaseSourceValue.reference(segments: path).validated()) != nil
            if !validPath { reject(.invalidPath) }
            if !document.accountScopeID.utf8.elementsEqual(accountScopeID.utf8)
                || (validPath && !path[1].utf8.elementsEqual(accountScopeID.utf8)) {
                reject(.accountScopeMismatch)
            }
            if document.evidenceKind != .record { reject(.nonRecordEvidence) }
            if (paths[path.map { Data($0.utf8) }]?.count ?? 0) > 1 { reject(.duplicateDocument) }

            let fields: [FirebaseSourceMapEntry]
            if case .map(let entries) = document.fields {
                fields = entries
                if (try? document.fields.validated()) == nil { reject(.invalidFields) }
                if let account = entries.first(where: { $0.key == "accountId" }) {
                    if case .string(let embedded) = account.value,
                       embedded.utf8.elementsEqual(accountScopeID.utf8) {
                        // Optional on reference documents, required by lineage reader.
                    } else { reject(.accountScopeMismatch) }
                }
            } else {
                fields = []
                reject(.invalidFields)
            }
            if collection == "lineageEdges" {
                lineage.append(FirebaseLineageEvidenceReader.read(
                    accountScopeID: document.accountScopeID,
                    documentID: path.last ?? document.sourceRecordID, fields: fields))
                invalidLineage.append(issues.count != start)
            } else if issues.count == start {
                switch collection {
                case "items": items.append(path[3])
                case "transactions": transactions.append(path[3])
                case "projects": projects.append(path[3])
                default: break
                }
            }
        }
        let index = FirebaseLineageReferenceIndex(accountScopeID: accountScopeID,
            itemIDs: items, transactionIDs: transactions, projectIDs: projects)
        let reconciled = FirebaseLineageReconciler.reconcile(lineage, against: index)
        let checked = zip(reconciled, invalidLineage).map { record, invalid in
            ReconciledFirebaseLineageEvidence(source: record.source,
                issues: record.issues + (invalid ? [.invalidSourceDocument] : []))
        }
        return .init(documents: documents, lineage: checked, issues: issues)
    }
}
