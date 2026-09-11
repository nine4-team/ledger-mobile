import Testing
@testable import LedgerTargetMigrationCore

@Suite("Source lineage reference reconciliation")
struct FirebaseLineageReconciliationTests {
    @Test("Repeated sale and return retain the same Item and every original link")
    func cycles() {
        let records = [
            edge("sale-1", kind: "sold", from: "purchase", to: "sale", toProject: "project"),
            edge("return-1", kind: "returned", from: "sale", to: "return", fromProject: "project"),
            edge("sale-2", kind: "sold", from: "return", to: "resale", toProject: "project")
        ]
        let result = FirebaseLineageReconciler.reconcile(records, against: index)
        #expect(result.map(\.source) == records)
        #expect(result.allSatisfy { $0.canAttemptMapping })
        #expect(result.map { $0.source.itemID } == ["chair", "chair", "chair"])
    }

    @Test("Missing links and conflicting copies are retained, not silently repaired")
    func unresolvedReferences() {
        let first = edge("same-id", kind: "sold", from: "missing", to: "sale", toProject: "unknown")
        let changed = edge("same-id", kind: "returned", from: "sale", to: "return")
        let result = FirebaseLineageReconciler.reconcile([first, changed], against: index)
        #expect(result.count == 2)
        #expect(result.map(\.source) == [first, changed])
        #expect(result[0].issues == [.conflictingDocument, .missingTransaction("missing"), .missingProject("unknown")])
        #expect(result[1].issues == [.conflictingDocument])
        #expect(!result[0].canAttemptMapping)
    }

    @Test("Exact repeated inputs are explicit duplicates; another Account cannot satisfy links")
    func duplicatesAndAccountIsolation() {
        let record = edge("sale-1", kind: "sold", from: "purchase", to: "sale")
        let duplicated = FirebaseLineageReconciler.reconcile([record, record], against: index)
        #expect(duplicated.allSatisfy { $0.issues == [.duplicateDocument] })
        let foreign = FirebaseLineageReferenceIndex(accountScopeID: "other", itemIDs: [], transactionIDs: [], projectIDs: [])
        let result = FirebaseLineageReconciler.reconcile([record], against: foreign)
        #expect(result[0].issues == [.accountScopeMismatch])
        #expect(result[0].source == record)
    }

    private var index: FirebaseLineageReferenceIndex {
        .init(accountScopeID: "account", itemIDs: ["chair"],
              transactionIDs: ["purchase", "sale", "return", "resale"], projectIDs: ["project"])
    }

    @Test("Foreign embedded Account does not resolve against an otherwise matching envelope")
    func foreignEmbeddedAccount() {
        let original = edge("foreign", kind: "sold", from: "unknown", to: "missing")
        let fields = original.rawFields.map {
            FirebaseSourceMapEntry(key: $0.key, value: $0.key == "accountId" ? .string("other") : $0.value)
        }
        let foreign = FirebaseLineageEvidenceReader.read(accountScopeID: "account", documentID: "foreign", fields: fields)
        let result = FirebaseLineageReconciler.reconcile([foreign], against: index)
        #expect(result[0].issues == [.invalidSourceEvidence, .accountScopeMismatch])
        #expect(result[0].source.rawFields == fields)
    }

    @Test("Opaque source IDs and conflicting raw values are compared byte-for-byte")
    func opaqueByteIdentity() {
        let composed = "caf\u{e9}"
        let decomposed = "cafe\u{301}"
        let first = edge("unicode", kind: "association", from: composed, to: "sale")
        let second = edge("unicode", kind: "association", from: decomposed, to: "sale")
        let scoped = FirebaseLineageReferenceIndex(accountScopeID: "account", itemIDs: ["chair"],
            transactionIDs: [decomposed, "sale"], projectIDs: [])
        let result = FirebaseLineageReconciler.reconcile([first, second], against: scoped)
        #expect(result[0].issues == [.conflictingDocument, .missingTransaction(composed)])
        #expect(result[1].issues == [.conflictingDocument])
        #expect(result[0].source.fromTransactionID?.utf8.elementsEqual(composed.utf8) == true)
        #expect(result[1].source.fromTransactionID?.utf8.elementsEqual(decomposed.utf8) == true)
    }

    private func edge(_ id: String, kind: String, from: String, to: String,
                      fromProject: String? = nil, toProject: String? = nil) -> FirebaseLineageEvidence {
        var values: [String: FirebaseSourceValue] = [
            "accountId": .string("account"), "itemId": .string("chair"),
            "movementKind": .string(kind), "fromTransactionId": .string(from),
            "toTransactionId": .string(to), "createdAt": .timestamp(seconds: "100", nanoseconds: 123)
        ]
        if let fromProject { values["fromProjectId"] = .string(fromProject) }
        if let toProject { values["toProjectId"] = .string(toProject) }
        let fields = values.keys.sorted().map { FirebaseSourceMapEntry(key: $0, value: values[$0]!) }
        return FirebaseLineageEvidenceReader.read(accountScopeID: "account", documentID: id, fields: fields)
    }
}
