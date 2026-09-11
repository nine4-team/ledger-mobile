import Testing
@testable import LedgerTargetMigrationCore

@Suite("Firebase lineage source review")
struct FirebaseLineageSourceReviewTests {
    @Test("Sale return resale chain retains exact source documents and resolves only declared links")
    func repeatedMovementChain() {
        let documents = [
            Self.reference(
                "item",
                collection: "items",
                id: "chair",
                fields: Self.fields([
                    "accountId": .string("account"),
                    // Current membership names only the latest resell. Earlier
                    // sale/return history must still come from lineage evidence.
                    "transactionId": .string("resale")
                ])
            ),
            Self.reference("purchase", collection: "transactions", id: "purchase"),
            Self.reference("sale", collection: "transactions", id: "sale"),
            Self.reference("return", collection: "transactions", id: "return"),
            Self.reference("resale", collection: "transactions", id: "resale"),
            Self.reference("project", collection: "projects", id: "project"),
            Self.lineage("sale-edge", kind: "sold", from: "purchase", to: "sale", toProject: "project"),
            Self.lineage("return-edge", kind: "returned", from: "sale", to: "return", fromProject: "project"),
            Self.lineage("resale-edge", kind: "sold", from: "return", to: "resale", toProject: "project")
        ]

        let result = FirebaseLineageSourceReview.review(
            documents: documents,
            accountScopeID: "account"
        )

        #expect(result.documents == documents)
        #expect(result.issues.isEmpty)
        #expect(result.lineage.map { $0.source.lineageDocumentID } == [
            "sale-edge", "return-edge", "resale-edge"
        ])
        #expect(result.lineage.map { $0.source.itemID } == ["chair", "chair", "chair"])
        #expect(result.lineage.map { $0.source.movementKind } == [
            FirebaseLineageMovementKind.sold,
            FirebaseLineageMovementKind.returned,
            FirebaseLineageMovementKind.sold
        ])
        #expect(result.lineage.allSatisfy { $0.canAttemptMapping })
        #expect(documents[0].mapFields.contains {
            $0.key == "transactionId" && $0.value == FirebaseSourceValue.string("resale")
        })
        #expect(result.lineage[1].source.rawFields == documents[7].mapFields)
    }

    @Test("Rejected reference documents cannot satisfy exact-account lineage links")
    func rejectedReferencesRemainMissing() throws {
        let documents = [
            Self.reference("duplicate-a", collection: "items", id: "duplicate-item"),
            Self.reference("duplicate-b", collection: "items", id: "duplicate-item"),
            Self.reference(
                "embedded-foreign",
                collection: "items",
                id: "embedded-item",
                fields: Self.fields(["accountId": .string("foreign")])
            ),
            Self.reference(
                "non-record",
                collection: "transactions",
                id: "non-record-transaction",
                evidenceKind: .ambiguous
            ),
            Self.reference(
                "invalid-fields",
                collection: "transactions",
                id: "invalid-transaction",
                rawFields: .string("not-a-map")
            ),
            Self.reference(
                "foreign-project",
                account: "foreign",
                collection: "projects",
                id: "foreign-project"
            ),
            Self.reference("path-foreign", collection: "items", id: "path-item",
                path: ["accounts", "foreign", "items", "path-item"]),
            Self.lineage(
                "rejected-links",
                kind: "sold",
                item: "duplicate-item",
                from: "non-record-transaction",
                to: "invalid-transaction",
                fromProject: "foreign-project"
            ),
            Self.lineage("embedded-link", kind: "association", item: "embedded-item"),
            Self.lineage("path-link", kind: "association", item: "path-item")
        ]

        let result = FirebaseLineageSourceReview.review(
            documents: documents,
            accountScopeID: "account"
        )

        #expect(result.documents == documents)
        #expect(result.issues.contains(Self.issue("duplicate-a", .duplicateDocument)))
        #expect(result.issues.contains(Self.issue("duplicate-b", .duplicateDocument)))
        #expect(result.issues.contains(Self.issue("embedded-foreign", .accountScopeMismatch)))
        #expect(result.issues.contains(Self.issue("non-record", .nonRecordEvidence)))
        #expect(result.issues.contains(Self.issue("invalid-fields", .invalidFields)))
        #expect(result.issues.contains(Self.issue("foreign-project", .accountScopeMismatch)))
        #expect(result.issues.contains(Self.issue("path-foreign", .accountScopeMismatch)))
        #expect(result.lineage.last?.issues.contains(.missingItem("path-item")) == true)
        #expect(result.lineage.last?.canAttemptMapping == false)

        guard let rejectedLinks = result.lineage.first(where: {
            $0.source.lineageDocumentID == "rejected-links"
        }) else {
            Issue.record("Expected retained rejected-links lineage")
            return
        }
        #expect(rejectedLinks.issues.contains(FirebaseLineageReferenceIssue.missingItem("duplicate-item")))
        #expect(rejectedLinks.issues.contains(FirebaseLineageReferenceIssue.missingTransaction("non-record-transaction")))
        #expect(rejectedLinks.issues.contains(FirebaseLineageReferenceIssue.missingTransaction("invalid-transaction")))
        #expect(rejectedLinks.issues.contains(FirebaseLineageReferenceIssue.missingProject("foreign-project")))
        #expect(!rejectedLinks.canAttemptMapping)

        guard let embeddedLink = result.lineage.first(where: {
            $0.source.lineageDocumentID == "embedded-link"
        }) else {
            Issue.record("Expected retained embedded-link lineage")
            return
        }
        #expect(embeddedLink.issues.contains(FirebaseLineageReferenceIssue.missingItem("embedded-item")))
        #expect(!embeddedLink.canAttemptMapping)
    }

    @Test("Malformed foreign tagged duplicate and non-map lineage remains visible and blocked")
    func rejectedLineageIsNeverDropped() {
        let duplicateA = Self.lineage("duplicate-a", documentID: "duplicate-edge", kind: "sold")
        let duplicateB = Self.lineage("duplicate-b", documentID: "duplicate-edge", kind: "returned")
        let tagged = Self.lineage("tagged-edge", kind: "association", evidenceKind: .ambiguous)
        let foreign = Self.lineage(
            "foreign-edge",
            account: "foreign",
            kind: "association"
        )
        let malformedPath = Self.lineage(
            "malformed-path-edge",
            kind: "association",
            path: ["items", "decoy", "lineageEdges", "malformed-edge-id"]
        )
        let nonMap = Self.reference(
            "non-map-edge",
            collection: "lineageEdges",
            id: "non-map-edge-id",
            rawFields: .string("not-a-map")
        )
        let documents = [duplicateA, duplicateB, tagged, foreign, malformedPath, nonMap]

        let result = FirebaseLineageSourceReview.review(
            documents: documents,
            accountScopeID: "account"
        )

        #expect(result.documents == documents)
        #expect(result.lineage.count == documents.count)
        #expect(result.lineage.map { $0.source.lineageDocumentID } == [
            "duplicate-edge",
            "duplicate-edge",
            "tagged-edge",
            "foreign-edge",
            "malformed-edge-id",
            "non-map-edge-id"
        ])
        #expect(result.issues.contains(Self.issue("duplicate-a", .duplicateDocument)))
        #expect(result.issues.contains(Self.issue("duplicate-b", .duplicateDocument)))
        #expect(result.issues.contains(Self.issue("tagged-edge", .nonRecordEvidence)))
        #expect(result.issues.contains(Self.issue("foreign-edge", .accountScopeMismatch)))
        #expect(result.issues.contains(Self.issue("malformed-path-edge", .invalidPath)))
        #expect(result.issues.contains(Self.issue("non-map-edge", .invalidFields)))
        #expect(result.lineage.allSatisfy { !$0.canAttemptMapping })
        #expect(result.lineage.allSatisfy {
            $0.issues.contains(FirebaseLineageReferenceIssue.invalidSourceDocument)
        })
        #expect(result.lineage[4].source.rawFields == malformedPath.mapFields)
        #expect(result.lineage[5].source.rawFields.isEmpty)
        #expect(nonMap.fields == FirebaseSourceValue.string("not-a-map"))
    }

    private static func reference(
        _ sourceRecordID: String,
        account: String = "account",
        collection: String,
        id: String,
        evidenceKind: FirebaseSourceEvidenceKind = .record,
        fields: [FirebaseSourceMapEntry] = [],
        rawFields: FirebaseSourceValue? = nil,
        path: [String]? = nil
    ) -> FirebaseSourceDocument {
        FirebaseSourceDocument(
            accountScopeID: account,
            documentPathSegments: path ?? ["accounts", account, collection, id],
            entityCode: collection,
            evidenceKind: evidenceKind,
            fields: rawFields ?? .map(fields),
            sourceRecordID: sourceRecordID
        )
    }

    private static func lineage(
        _ sourceRecordID: String,
        documentID: String? = nil,
        account: String = "account",
        kind: String,
        item: String = "chair",
        from: String? = nil,
        to: String? = nil,
        fromProject: String? = nil,
        toProject: String? = nil,
        evidenceKind: FirebaseSourceEvidenceKind = .record,
        path: [String]? = nil
    ) -> FirebaseSourceDocument {
        var values: [String: FirebaseSourceValue] = [
            "accountId": .string(account),
            "createdAt": .timestamp(seconds: "100", nanoseconds: 123),
            "itemId": .string(item),
            "movementKind": .string(kind),
            "source": .string("app")
        ]
        if let from { values["fromTransactionId"] = .string(from) }
        if let to { values["toTransactionId"] = .string(to) }
        if let fromProject { values["fromProjectId"] = .string(fromProject) }
        if let toProject { values["toProjectId"] = .string(toProject) }
        return Self.reference(
            sourceRecordID,
            account: account,
            collection: "lineageEdges",
            id: documentID ?? sourceRecordID,
            evidenceKind: evidenceKind,
            fields: Self.fields(values),
            path: path
        )
    }

    private static func fields(_ values: [String: FirebaseSourceValue]) -> [FirebaseSourceMapEntry] {
        values.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map {
            FirebaseSourceMapEntry(key: $0, value: values[$0]!)
        }
    }

    private static func issue(
        _ sourceRecordID: String,
        _ kind: FirebaseLineageSourceDocumentIssue.Kind
    ) -> FirebaseLineageSourceDocumentIssue {
        .init(sourceRecordID: sourceRecordID, kind: kind)
    }
}

private extension FirebaseSourceDocument {
    var mapFields: [FirebaseSourceMapEntry] {
        guard case .map(let fields) = self.fields else { return [] }
        return fields
    }
}
