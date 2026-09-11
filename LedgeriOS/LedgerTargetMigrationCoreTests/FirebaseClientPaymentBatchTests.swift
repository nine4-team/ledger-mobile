import Testing
import LedgerTargetCore
@testable import LedgerTargetMigrationCore

@Suite("Client payment batch reconciliation")
struct FirebaseClientPaymentBatchTests {
    @Test("Explicit scope and stable identity reproduce payment counts, totals and evidence on replay")
    func replay() throws {
        let f = try Fixture()
        let first = f.run()
        #expect(first == f.run())
        #expect(first.entries.map(\.source) == f.payments)
        #expect(first.entries.map(\.targetID) == f.identities.map { Optional($0.targetID) })
        #expect(first.mappedCount == 2)
        #expect(first.unresolvedCount == 0)
        #expect(first.mappedTotalCents == 3_000)
        #expect(first.isFullyReconciled)
    }

    @Test("Names do not prove Client ownership and changed or duplicate source Projects invalidate mappings")
    func projectMappingDenials() throws {
        let f = try Fixture()
        for result in [f.run(mappings: []), f.run(projects: []),
            f.run(projects: [f.project, f.project]),
            f.run(projects: [Self.project(name: "changed")]),
            f.run(mappings: [f.mapping, f.mapping])] {
            #expect(result.mappedCount == 0)
            #expect(result.unresolvedCount == 2)
            #expect(result.entries.allSatisfy { $0.issues.contains(.unresolvedProjectMapping) })
            #expect(!result.isFullyReconciled)
        }
        let foreign = FirebasePaymentProjectMapping(sourceProject: f.project,
            targetScope: .project(accountId: try AccountID(validating: "foreign"),
                projectId: f.scope.projectId!, clientId: f.scope.clientId!))
        #expect(f.run(mappings: [foreign]).mappedCount == 0)
    }

    @Test("Duplicate source and target identities remain unresolved without dropping a source")
    func duplicateDenials() throws {
        let f = try Fixture()
        let duplicateSource = f.run(payments: [f.payments[0], f.payments[0]])
        #expect(duplicateSource.entries.count == 2)
        #expect(duplicateSource.mappedCount == 0)
        #expect(duplicateSource.entries.allSatisfy { $0.issues.contains(.duplicateSourcePath) })
        let collision = f.run(identities: [f.identities[0],
            .init(sourcePath: f.payments[1].documentPathSegments, targetID: f.identities[0].targetID)])
        #expect(collision.mappedCount == 0)
        #expect(collision.entries.allSatisfy { $0.issues.contains(.duplicateTargetID) })
        #expect(f.run(identities: []).unresolvedCount == 2)
        #expect(f.run(identities: [f.identities[0], f.identities[0]]).unresolvedCount == 2)
    }

    @Test("Reconciliation never wraps money or treats an unsupported type as a client payment")
    func moneyDenials() throws {
        let f = try Fixture()
        let overflow = f.run(payments: [Self.payment("one", amount: String(Int64.max)), Self.payment("two", amount: "1")])
        #expect(overflow.mappedCount == 2)
        #expect(overflow.mappedTotalCents == nil)
        #expect(!overflow.isFullyReconciled)
        let ambiguous = f.run(payments: [Self.payment("one", type: "purchase"), f.payments[1]])
        #expect(ambiguous.mappedCount == 1)
        #expect(ambiguous.unresolvedCount == 1)
        #expect(ambiguous.mappedTotalCents == 2_000)
        #expect(!ambiguous.isFullyReconciled)
    }

    @Test("Broader import plans create no extra payments and distinct Projects cannot collapse into one")
    func broaderPlan() throws {
        let f = try Fixture()
        let unusedID = FirebasePaymentIdentityMapping(sourcePath: ["accounts", "source", "transactions", "unused"],
            targetID: try TransactionID(validating: "target-unused"))
        let unrelated = FirebaseSourceDocument(accountScopeID: "foreign",
            documentPathSegments: ["accounts", "foreign", "projects", "unused"],
            entityCode: "projects", evidenceKind: .record, fields: .map([]), sourceRecordID: "unused")
        let unusedMapping = FirebasePaymentProjectMapping(sourceProject: unrelated,
            targetScope: .project(accountId: f.scope.accountId, projectId: try ProjectID(validating: "unused"),
                clientId: f.scope.clientId!))
        #expect(f.run(mappings: [f.mapping, unusedMapping], identities: f.identities + [unusedID]) == f.run())
        let collision = FirebasePaymentProjectMapping(sourceProject: unrelated, targetScope: f.scope)
        let rejected = f.run(mappings: [f.mapping, collision])
        #expect(rejected.mappedCount == 0)
        #expect(rejected.entries.allSatisfy { $0.conversion == nil })
    }

    private struct Fixture {
        let scope: TransactionScope
        let project = FirebaseClientPaymentBatchTests.project()
        let payments = [FirebaseClientPaymentBatchTests.payment("one"), FirebaseClientPaymentBatchTests.payment("two", amount: "2000")]
        let identities: [FirebasePaymentIdentityMapping]
        var mapping: FirebasePaymentProjectMapping { .init(sourceProject: project, targetScope: scope) }
        init() throws {
            scope = .project(accountId: try AccountID(validating: "target-account"),
                projectId: try ProjectID(validating: "target-project"), clientId: try ClientID(validating: "explicit-client"))
            identities = try ["one", "two"].map {
                .init(sourcePath: ["accounts", "source", "transactions", $0], targetID: try TransactionID(validating: "target-\($0)"))
            }
        }
        func run(payments: [FirebaseSourceDocument]? = nil, projects: [FirebaseSourceDocument]? = nil,
            mappings: [FirebasePaymentProjectMapping]? = nil, identities: [FirebasePaymentIdentityMapping]? = nil) -> FirebasePaymentBatchResult {
            FirebaseClientPaymentBatch.convert(transactions: payments ?? self.payments,
                projects: projects ?? [project], sourceAccountID: "source", targetAccountID: scope.accountId,
                projectMappings: mappings ?? [mapping], identityMappings: identities ?? self.identities)
        }
    }

    private static func project(name: String = "same-name-does-not-establish-identity") -> FirebaseSourceDocument {
        .init(accountScopeID: "source", documentPathSegments: ["accounts", "source", "projects", "project"],
            entityCode: "projects", evidenceKind: .record,
            fields: .map([.init(key: "clientName", value: .string(name))]), sourceRecordID: "project-source")
    }
    private static func payment(_ id: String, amount: String = "1000", type: String = "paymentToBusiness") -> FirebaseSourceDocument {
        .init(accountScopeID: "source", documentPathSegments: ["accounts", "source", "transactions", id],
            entityCode: "transactions", evidenceKind: .record,
            fields: .map([.init(key: "amountCents", value: .integer(amount)), .init(key: "projectId", value: .string("project")),
                .init(key: "type", value: .string(type))]), sourceRecordID: id)
    }
}
