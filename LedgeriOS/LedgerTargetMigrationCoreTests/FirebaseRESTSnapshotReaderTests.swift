import Foundation
import Testing
@testable import LedgerTargetMigrationCore

@Suite("Typed Firebase REST snapshot")
struct FirebaseRESTSnapshotReaderTests {
    private let account = "projects/source/databases/(default)/documents/accounts/account"
    private func snapshot(_ fields: String, path: String = "accounts/account/items/item") -> Data {
        Data("""
        {"sourceProject":"source","account":"\(account)","documents":[{"name":"projects/source/databases/(default)/documents/\(path)","fields":\(fields)}]}
        """.utf8)
    }
    @Test func exactMoneyAndTimestamp() throws {
        let documents = try FirebaseRESTSnapshotReader.read(snapshot("""
        {"amountCents":{"integerValue":"9007199254740993"},"createdAt":{"timestampValue":"2026-01-01T00:00:00.123456789Z"},"empty":{"arrayValue":{}}}
        """), accountPath: account)
        guard case .map(let fields) = documents[0].fields else { Issue.record("Missing fields"); return }
        #expect(fields.first { $0.key == "amountCents" }?.value == .integer("9007199254740993"))
        #expect(fields.first { $0.key == "createdAt" }?.value == .timestamp(seconds: "1767225600", nanoseconds: 123456789))
        #expect(fields.first { $0.key == "empty" }?.value == .array([]))
    }
    @Test func rejectsScopeAndAmbiguousValues() {
        #expect(throws: (any Error).self) { try FirebaseRESTSnapshotReader.read(snapshot("{}", path: "accounts/other/items/item"), accountPath: account) }
        #expect(throws: (any Error).self) { try FirebaseRESTSnapshotReader.read(snapshot(#"{"x":{"integerValue":"1","stringValue":"1"}}"#), accountPath: account) }
        #expect(throws: (any Error).self) { try FirebaseRESTSnapshotReader.read(snapshot(#"{"x":{"referenceValue":"projects/other/databases/(default)/documents/accounts/account/items/item"}}"#), accountPath: account) }
    }
    @Test func sameDatabaseReference() throws {
        let documents = try FirebaseRESTSnapshotReader.read(snapshot(#"{"x":{"referenceValue":"projects/source/databases/(default)/documents/accounts/account/items/other"}}"#), accountPath: account)
        #expect(documents[0].fields == .map([.init(key: "x", value: .reference(segments: ["accounts", "account", "items", "other"]))]))
    }
    @Test func legacyPathScopeAndAuthorProvenance() throws {
        let documents = try FirebaseRESTSnapshotReader.read(snapshot(#"{"itemId":{"stringValue":"item"},"movementKind":{"stringValue":"association"},"createdBy":{"stringValue":"repair/batch"},"createdAt":{"timestampValue":"2026-01-01T00:00:00Z"}}"#, path: "accounts/account/lineageEdges/edge"), accountPath: account)
        let result = FirebaseLineageSourceReview.review(documents: documents, accountScopeID: "account")
        #expect(result.issues.isEmpty)
        #expect(result.lineage[0].source.issues.isEmpty)
        #expect(result.lineage[0].source.actorID == "repair/batch")
        // Missing duplicate accountId must not suppress reference checks.
        #expect(result.lineage[0].issues == [.missingItem("item")])
        #expect(!result.lineage[0].canAttemptMapping)
    }
    @Test func projectNotesAreRetainedButNotMisclassifiedAsProjects() throws {
        let documents = try FirebaseRESTSnapshotReader.read(snapshot(#"{"text":{"stringValue":"note"}}"#, path: "accounts/account/projects/project/notes/note"), accountPath: account)
        let result = FirebaseLineageSourceReview.review(documents: documents, accountScopeID: "account")
        #expect(result.documents == documents)
        #expect(result.issues.isEmpty)
        #expect(result.lineage.isEmpty)
    }
}
