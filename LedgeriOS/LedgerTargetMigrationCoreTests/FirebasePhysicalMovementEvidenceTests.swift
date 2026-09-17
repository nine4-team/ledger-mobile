import Testing
@testable import LedgerTargetMigrationCore

@Suite("Legacy physical movement meaning")
struct FirebasePhysicalMovementEvidenceTests {
    private func record(_ kind: String, from: FirebaseSourceValue? = nil,
                        to: FirebaseSourceValue? = nil, source: String = "app", id: String = "edge",
                        seconds: String = "100", transaction: String? = nil, nanos: Int = 0) -> ReconciledFirebaseLineageEvidence {
        var fields: [String:FirebaseSourceValue] = ["itemId":.string("item"),"movementKind":.string(kind),
            "source":.string(source),"createdAt":.timestamp(seconds:seconds,nanoseconds:nanos)]
        fields["fromProjectId"] = from; fields["toProjectId"] = to
        fields["fromTransactionId"] = transaction.map(FirebaseSourceValue.string)
        let edge = FirebaseLineageEvidenceReader.read(accountScopeID:"account",documentID:id,
            fields:fields.keys.sorted().map { .init(key:$0,value:fields[$0]!) })
        return FirebaseLineageReconciler.reconcile([edge],against:.init(accountScopeID:"account",
            itemIDs:["item"],transactionIDs:["original"],projectIDs:["a","b"]))[0]
    }
    @Test func saleReturnAndAcquisition() {
        #expect(FirebasePhysicalMovementEvidence.interpret(record("sold",to:.string("a"))) == .movement(from:.inventory,to:.project("a")))
        for kind in ["returned","soldToInventory"] {
            #expect(FirebasePhysicalMovementEvidence.interpret(record(kind,from:.string("a"))) == .movement(from:.project("a"),to:.inventory))
        }
        #expect(FirebasePhysicalMovementEvidence.interpret(record("sold",from:.string("a"),to:.string("b"))) == .movement(from:.project("a"),to:.project("b")))
    }
    @Test func sameProjectReturnIsNotPhysicalReturn() {
        #expect(FirebasePhysicalMovementEvidence.interpret(record("returned",from:.string("a"),to:.string("a"))) == .unchanged(.project("a")))
    }
    @Test func correctionRequiresExplicitScopes() {
        #expect(FirebasePhysicalMovementEvidence.interpret(record("correction",from:.string("a"),to:.null)) == .movement(from:.project("a"),to:.inventory))
        #expect(FirebasePhysicalMovementEvidence.interpret(record("correction",from:.string("a"))) == .unresolved)
    }
    @Test func unknownOrInvalidEvidenceCannotClaimMovement() {
        for value in [record("association"),record("sold"),record("returned"),
            record("returned",from:.string("a"),to:.string("b")),
            record("soldToInventory",from:.string("a"),to:.string("b")),
            record("sold",to:.string("a"),source:"server"),record("sold",to:.string("missing"))] {
            #expect(FirebasePhysicalMovementEvidence.interpret(value) == .unresolved)
        }
    }

    @Test func simultaneousProjectMoveKeepsBothEdgesWithoutInventoryInterval() {
        let sale = record("sold",to:.string("a"),id:"first")
        let link = record("returned",from:.string("a"),to:.string("a"),id:"link",seconds:"150")
        let exit = record("returned",from:.string("a"),id:"exit",seconds:"200",transaction:"original")
        let arrival = record("sold",from:.string("a"),to:.string("b"),id:"arrival",seconds:"200",transaction:"original")
        let timeline = FirebasePhysicalMovementEvidence.timeline([arrival,link,sale,exit],accountID:"account",itemID:"item",currentScope:.project("b"))
        #expect(timeline.unresolvedDocumentIDs.isEmpty)
        #expect(timeline.initialStartIsUnknown)
        #expect(timeline.transitions.count == 2)
        #expect(timeline.transitions.last?.from == .project("a"))
        #expect(timeline.transitions.last?.to == .project("b"))
        #expect(timeline.transitions.last?.sourceDocumentIDs == ["arrival","exit"])
        #expect(timeline.transitions.first?.at.seconds == "100")
    }

    @Test func inconsistentOrAmbiguousChainIsNotPartiallyImported() {
        let sale = record("sold",to:.string("a"),id:"first")
        let broken = record("sold",to:.string("b"),id:"broken",seconds:"200")
        for (records, current) in [([sale,broken],FirebasePhysicalMovementEvidence.Scope.project("b")),
            ([sale],.inventory),([sale,record("sold",to:.string("b"),id:"same-time")],.project("b")),
            ([sale,record("association",id:"unknown",seconds:"200")],.project("a"))] {
            let timeline = FirebasePhysicalMovementEvidence.timeline(records,accountID:"account",itemID:"item",currentScope:current)
            #expect(timeline.transitions.isEmpty)
            #expect(!timeline.unresolvedDocumentIDs.isEmpty)
        }
    }
    @Test func postgresPrecisionNeverSilentlyRoundsSourceTime() {
        let exact = record("sold",to:.string("a"),nanos:123000)
        let fine = record("sold",to:.string("a"),nanos:123001)
        let accepted = FirebasePhysicalMovementEvidence.timeline([exact],accountID:"account",itemID:"item",currentScope:.project("a"))
        #expect(accepted.transitions.first?.at.nanoseconds == 123000)
        let rejected = FirebasePhysicalMovementEvidence.timeline([fine],accountID:"account",itemID:"item",currentScope:.project("a"))
        #expect(rejected.transitions.isEmpty)
        #expect(rejected.unresolvedDocumentIDs == ["edge"])
    }
}
