import Foundation
@testable import LedgeriOS

/// Test double for `BatchWriting` that records all operations for assertion.
final class RecordingBatch: BatchWriting, @unchecked Sendable {

    struct SetOperation {
        let fields: [String: Any]
        let path: String
        let merge: Bool
    }

    struct UpdateOperation {
        let fields: [String: Any]
        let path: String
    }

    struct AutoIdSetOperation {
        let fields: [String: Any]
        let collectionPath: String
    }

    struct DeleteOperation {
        let path: String
    }

    private(set) var sets: [SetOperation] = []
    private(set) var updates: [UpdateOperation] = []
    private(set) var autoIdSets: [AutoIdSetOperation] = []
    private(set) var deletes: [DeleteOperation] = []
    private(set) var commitCalled = false

    func setData(_ fields: [String: Any], forDocumentAt path: String, merge: Bool) {
        sets.append(SetOperation(fields: fields, path: path, merge: merge))
    }

    func updateData(_ fields: [String: Any], forDocumentAt path: String) {
        updates.append(UpdateOperation(fields: fields, path: path))
    }

    func setDataAutoId(_ fields: [String: Any], inCollection collectionPath: String) {
        autoIdSets.append(AutoIdSetOperation(fields: fields, collectionPath: collectionPath))
    }

    func deleteDocument(atPath path: String) {
        deletes.append(DeleteOperation(path: path))
    }

    func commit() async throws {
        commitCalled = true
    }

    // MARK: - Query Helpers

    func setsForPath(_ path: String) -> [SetOperation] {
        sets.filter { $0.path == path }
    }

    func updatesForPath(_ path: String) -> [UpdateOperation] {
        updates.filter { $0.path == path }
    }

    func deletesForPath(_ path: String) -> [DeleteOperation] {
        deletes.filter { $0.path == path }
    }

    func autoIdSetsInCollection(_ collectionPath: String) -> [AutoIdSetOperation] {
        autoIdSets.filter { $0.collectionPath == collectionPath }
    }

    func lineageEdges(accountId: String) -> [AutoIdSetOperation] {
        autoIdSetsInCollection("accounts/\(accountId)/lineageEdges")
    }

    func lineageEdges(accountId: String, itemId: String) -> [AutoIdSetOperation] {
        lineageEdges(accountId: accountId).filter { ($0.fields["itemId"] as? String) == itemId }
    }
}
