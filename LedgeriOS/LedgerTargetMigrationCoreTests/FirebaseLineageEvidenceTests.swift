import Testing
@testable import LedgerTargetMigrationCore

@Suite("Firebase lineage source evidence")
struct FirebaseLineageEvidenceTests {
    @Test("Known returned evidence is preserved without assigning accounting meaning")
    func knownReturnedEvidence() {
        let fields = Self.fields([
            "accountId": .string("account-source"),
            "createdAt": .timestamp(seconds: "1750000000", nanoseconds: 42),
            "createdBy": .string("actor-original"),
            "fromProjectId": .string("project-from"),
            "fromTransactionId": .string("transaction-from"),
            "itemId": .string("item-original"),
            "movementKind": .string("returned"),
            "note": .string("source note"),
            "source": .string("app"),
            "toProjectId": .string("project-to"),
            "toTransactionId": .string("transaction-to"),
            "unknownFutureField": .map([
                .init(key: "retained", value: .bool(true))
            ])
        ])

        let evidence = FirebaseLineageEvidenceReader.read(
            accountScopeID: "account-source",
            documentID: "lineage-document-original",
            fields: fields
        )

        #expect(evidence.sourceAccountScopeID == "account-source")
        #expect(evidence.lineageDocumentID == "lineage-document-original")
        #expect(evidence.rawFields == fields)
        #expect(evidence.accountID == "account-source")
        #expect(evidence.itemID == "item-original")
        #expect(evidence.fromTransactionID == "transaction-from")
        #expect(evidence.toTransactionID == "transaction-to")
        #expect(evidence.fromProjectID == "project-from")
        #expect(evidence.toProjectID == "project-to")
        #expect(evidence.movementKind == .returned)
        #expect(evidence.movementKindRaw == "returned")
        #expect(evidence.actorID == "actor-original")
        #expect(evidence.note == "source note")
        #expect(evidence.source == "app")
        #expect(evidence.createdAt == .init(seconds: "1750000000", nanoseconds: 42))
        #expect(evidence.issues.isEmpty)
        #expect(evidence.isStructurallyValid)
    }

    @Test("Optional absent and null source fields are not invented")
    func optionalFieldsRemainAbsent() {
        let fields = Self.fields([
            "accountId": .string("account-source"),
            "createdAt": .timestamp(seconds: "1750000001", nanoseconds: 0),
            "fromProjectId": .null,
            "itemId": .string("item-original"),
            "movementKind": .string("association"),
            "note": .string(""),
            "source": .string("migration")
        ])

        let evidence = FirebaseLineageEvidenceReader.read(
            accountScopeID: "account-source",
            documentID: "lineage-document",
            fields: fields
        )

        #expect(evidence.fromProjectID == nil)
        #expect(evidence.toProjectID == nil)
        #expect(evidence.fromTransactionID == nil)
        #expect(evidence.toTransactionID == nil)
        #expect(evidence.actorID == nil)
        #expect(evidence.note == "")
        #expect(evidence.rawFields == fields)
        #expect(evidence.isStructurallyValid)
    }

    @Test("Missing invalid cross-account and unknown evidence stays unresolved")
    func unresolvedEvidence() {
        let fields = Self.fields([
            "accountId": .string("foreign-account"),
            "createdAt": .string("not-a-timestamp"),
            "createdBy": .integer("7"),
            "fromTransactionId": .integer("9"),
            "fromProjectId": .string("bad/project"),
            "movementKind": .string("cashRefund"),
            "toProjectId": .string("project-retained")
        ])

        let evidence = FirebaseLineageEvidenceReader.read(
            accountScopeID: "expected-account",
            documentID: "lineage-document",
            fields: fields
        )

        #expect(evidence.rawFields == fields)
        #expect(evidence.itemID == nil)
        #expect(evidence.fromTransactionID == nil)
        #expect(evidence.toProjectID == "project-retained")
        #expect(evidence.movementKind == nil)
        #expect(evidence.movementKindRaw == "cashRefund")
        #expect(!evidence.isStructurallyValid)
        #expect(evidence.issues.contains(.missingRequiredField("itemId")))
        #expect(evidence.issues.contains(.invalidField("createdAt")))
        #expect(evidence.issues.contains(.invalidField("createdBy")))
        #expect(evidence.issues.contains(.invalidField("fromTransactionId")))
        #expect(evidence.issues.contains(.invalidField("fromProjectId")))
        #expect(evidence.issues.contains(.unknownMovementKind("cashRefund")))
        #expect(evidence.issues.contains(
            .crossAccount(expected: "expected-account", actual: "foreign-account")
        ))
    }

    @Test("Invalid envelope identities and duplicate raw keys fail closed without data loss")
    func malformedEnvelope() {
        let fields = [
            FirebaseSourceMapEntry(key: "accountId", value: .string("account-source")),
            FirebaseSourceMapEntry(key: "accountId", value: .string("conflicting-account")),
            FirebaseSourceMapEntry(key: "itemId", value: .string("item-original")),
            FirebaseSourceMapEntry(key: "movementKind", value: .string("sold")),
            FirebaseSourceMapEntry(
                key: "createdAt",
                value: .timestamp(seconds: "1750000002", nanoseconds: 0)
            )
        ]

        let evidence = FirebaseLineageEvidenceReader.read(
            accountScopeID: "bad/account",
            documentID: "",
            fields: fields
        )

        #expect(evidence.rawFields == fields)
        #expect(evidence.accountID == nil)
        #expect(evidence.itemID == "item-original")
        #expect(evidence.issues.contains(.invalidRawFields))
        #expect(evidence.issues.contains(.invalidSourceAccountScopeID))
        #expect(evidence.issues.contains(.invalidLineageDocumentID))
        #expect(evidence.issues.contains(.invalidField("accountId")))
        #expect(!evidence.isStructurallyValid)
    }

    @Test("Account scope comparison is exact UTF-8 and source IDs are not normalized")
    func byteExactAccountScope() {
        let decomposedAccount = "cafe\u{301}"
        let composedAccount = "caf\u{E9}"
        let fields = Self.fields([
            "accountId": .string(decomposedAccount),
            "createdAt": .timestamp(seconds: "1750000003", nanoseconds: 0),
            "itemId": .string(decomposedAccount),
            "movementKind": .string("sold")
        ])

        let evidence = FirebaseLineageEvidenceReader.read(
            accountScopeID: composedAccount,
            documentID: decomposedAccount,
            fields: fields
        )

        #expect(evidence.sourceAccountScopeID.utf8.elementsEqual(composedAccount.utf8))
        #expect(evidence.lineageDocumentID.utf8.elementsEqual(decomposedAccount.utf8))
        #expect(evidence.itemID?.utf8.elementsEqual(decomposedAccount.utf8) == true)
        let mismatch = evidence.issues.first {
            if case .crossAccount = $0 { return true }
            return false
        }
        guard case .crossAccount(let expected, let actual)? = mismatch else {
            Issue.record("Expected an exact-byte Account mismatch")
            return
        }
        #expect(expected.utf8.elementsEqual(composedAccount.utf8))
        #expect(actual.utf8.elementsEqual(decomposedAccount.utf8))
    }

    private static func fields(_ values: [String: FirebaseSourceValue]) -> [FirebaseSourceMapEntry] {
        values.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map {
            FirebaseSourceMapEntry(key: $0, value: values[$0]!)
        }
    }
}
