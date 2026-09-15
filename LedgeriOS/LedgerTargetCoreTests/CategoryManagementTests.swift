import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Category management")
struct CategoryManagementTests {
    @Test func nameRulesMatchMCPFixtures() throws {
        struct Fixture: Decodable { let input: String; let normalized: String?; let sameKeyAs: String? }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/category-names.json"))
        for fixture in try JSONDecoder().decode([Fixture].self, from: data) {
            if let expected = fixture.normalized {
                #expect(try BudgetCategoryName(validating: fixture.input).rawValue == expected)
                if let equivalent = fixture.sameKeyAs {
                    #expect(try BudgetCategoryName(validating: fixture.input).comparisonKey ==
                        BudgetCategoryName(validating: equivalent).comparisonKey)
                }
            } else {
                #expect(throws: BudgetCategoryReferenceFailure.invalidName) {
                    try BudgetCategoryName(validating: fixture.input)
                }
            }
        }
    }

    @Test func mcpAndSwiftEncodeTheSameCreateAndReorderCommands() throws {
        struct Fixture: Decodable { let envelopeJSON: String; let fingerprint: String }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: root.appendingPathComponent("LedgerTargetMCP/tests/fixtures/category-management.json"))
        for fixture in try JSONDecoder().decode([Fixture].self, from: bytes) {
            let decoded = try OperationContractCodec.decode(CategoryManagementCommand.self,
                from: Data("{\"envelope\":\(fixture.envelopeJSON)}".utf8))
            let rebuilt = try CategoryManagementCommand(operationId: decoded.envelope.operationId,
                accountId: decoded.envelope.accountId, actorPrincipalId: decoded.envelope.actorPrincipalId,
                capturedAt: decoded.envelope.clientCreatedAt, payload: decoded.envelope.payload)
            #expect(String(decoding: try OperationContractCodec.encode(rebuilt.envelope), as: UTF8.self) == fixture.envelopeJSON)
            #expect(try rebuilt.fingerprint.sha256 == fixture.fingerprint)
        }
    }

    @Test func createTrimsNameAndPreservesExistingDefinitions() throws {
        let original = try row("existing", order: 3)
        let payload = CategoryManagementPayload(action: .create,
            categoryId: try BudgetCategoryID(validating: "new"),
            name: try BudgetCategoryName(validating: "  Art & Décor  "),
            kind: .itemized, excludesFromOverallBudget: false)
        let result = try CategoryManagement.applying(payload, to: snapshot([original]))
        #expect(result.first == original)
        #expect(result.last?.name.rawValue == "Art & Décor")
        #expect(result.last?.presentationOrder == 4)
        #expect(result.last?.revision == 1)
        #expect(result.last?.isSelectableForItemizedProjectWorkflow == true)
    }

    @Test func everyExplicitTypeChangeKeepsIdentityAndOtherDefinitions() throws {
        for oldKind in BudgetCategoryKind.allCases {
            for newKind in BudgetCategoryKind.allCases {
                let original = try row("category", kind: oldKind, order: 0)
                let untouched = try row("untouched", order: 1)
                let payload = edit(original, kind: newKind)
                let result = try CategoryManagement.applying(payload,
                    to: snapshot([original, untouched]))
                #expect(result[0].id == original.id)
                #expect(result[0].accountId == original.accountId)
                #expect(result[0].kind == newKind)
                #expect(result[0].revision == (oldKind == newKind ? 1 : 2))
                #expect(result[0].isSelectableForItemizedProjectWorkflow == (newKind == .itemized))
                #expect(result[1] == untouched)
                // The command changes definitions only. No previous-kind state,
                // Transaction/Item creation, or accounting rewrite is in its payload.
            }
        }
    }

    @Test func archiveRestoreKeepsHistoricalIdentityAndNoOpRevision() throws {
        let original = try row("category", kind: .itemized, order: 0)
        let archive = CategoryManagementPayload(action: .archive,
            categoryId: original.id, expectedRevision: 1)
        let archived = try CategoryManagement.applying(archive, to: snapshot([original]))[0]
        #expect(archived.id == original.id)
        #expect(archived.kind == original.kind)
        #expect(archived.revision == 2)
        #expect(!archived.isSelectableForProjectConfiguration)
        let again = CategoryManagementPayload(action: .archive,
            categoryId: original.id, expectedRevision: 2)
        #expect(try CategoryManagement.applying(again, to: snapshot([archived])) == [archived])
        let restore = CategoryManagementPayload(action: .restore,
            categoryId: original.id, expectedRevision: 2)
        let restored = try CategoryManagement.applying(restore, to: snapshot([archived]))[0]
        #expect(restored.id == original.id)
        #expect(restored.isSelectableForItemizedProjectWorkflow)
        #expect(restored.revision == 3)
    }

    @Test func typeEditsChangeAuditApplicabilityWithoutChangingTransactionEvidence() throws {
        let account = try AccountID(validating: "account")
        let currency = try CurrencyCode(validating: "USD")
        let classification = try TransactionClassification(type: .purchase,
            scope: .project(accountId: account, projectId: ProjectID(validating: "project"),
                            clientId: ClientID(validating: "client")), role: .standalone)
        let evidence = try TransactionReceiptReconstruction(accountId: account,
            transactionId: TransactionID(validating: "transaction"), classification: classification,
            recordedFinalAmount: Money(minorUnits: 100, currency: currency),
            physicalItemTotal: Money(minorUnits: 99, currency: currency), lines: [])
        let originalBytes = try OperationContractCodec.encode(evidence)
        var category = try row("Category", kind: .general, order: 0)
        for kind: BudgetCategoryKind in [.itemized, .general, .fee, .itemized] {
            category = try CategoryManagement.applying(edit(category, kind: kind),
                to: snapshot([category]))[0]
            #expect(evidence.auditStatus(for: category.kind) == (kind == .itemized ? .mismatch : .notApplicable))
            #expect(try OperationContractCodec.encode(evidence) == originalBytes)
        }
        let archived = try CategoryManagement.applying(.init(action: .archive,
            categoryId: category.id, expectedRevision: category.revision), to: snapshot([category]))[0]
        #expect(evidence.auditStatus(for: archived.kind) == .mismatch)
        #expect(archived.id == category.id)
    }

    @Test func equivalentUnicodeSpellingEditRetainsBytesAndAdvancesRevision() throws {
        let original = try row("Décor", order: 0)
        let spelling = "De\u{0301}cor"
        let payload = CategoryManagementPayload(action: .edit, categoryId: original.id,
            expectedRevision: original.revision, name: try BudgetCategoryName(validating: spelling),
            kind: original.kind, excludesFromOverallBudget: original.excludesFromOverallBudget)
        let updated = try CategoryManagement.applying(payload, to: snapshot([original]))[0]
        #expect(Array(updated.name.rawValue.utf8) == Array(spelling.utf8))
        #expect(updated.revision == original.revision + 1)
        let sameBytes = edit(updated)
        #expect(try CategoryManagement.applying(sameBytes, to: snapshot([updated]))[0].revision == updated.revision)
    }

    @Test func duplicatesIncludeArchivedAndCaseVariants() throws {
        let archived = try row("Art & Décor", lifecycle: .archived, order: 0)
        let other = try row("other", order: 1)
        let payload = CategoryManagementPayload(action: .edit, categoryId: other.id,
            expectedRevision: 1, name: try BudgetCategoryName(validating: "ART & DÉCOR"),
            kind: .general, excludesFromOverallBudget: false)
        #expect(throws: CategoryManagementFailure.duplicateName) {
            try CategoryManagement.applying(payload, to: snapshot([archived, other]))
        }
    }

    @Test func partialDirectorySystemAndStaleEditsAreRejected() throws {
        let ordinary = try row("ordinary", order: 0)
        #expect(throws: CategoryManagementFailure.incompleteDirectory) {
            try CategoryManagement.applying(edit(ordinary), to: snapshot([ordinary], complete: false))
        }
        let system = try row("system", isSystem: true, order: 1)
        #expect(throws: CategoryManagementFailure.protectedCategory) {
            try CategoryManagement.applying(edit(system), to: snapshot([system]))
        }
        let stale = CategoryManagementPayload(action: .archive,
            categoryId: ordinary.id, expectedRevision: 2)
        #expect(throws: CategoryManagementFailure.revisionConflict) {
            try CategoryManagement.applying(stale, to: snapshot([ordinary]))
        }
    }

    @Test func reorderIsCompleteAndPreservesReservedSlots() throws {
        let a = try row("a", order: 0)
        let system = try row("system", isSystem: true, order: 1)
        let archived = try row("archived", lifecycle: .archived, order: 2)
        let b = try row("b", order: 4)
        let original = try snapshot([a, system, archived, b])
        let payload = CategoryManagementPayload(action: .reorder, order: [
            CategoryOrderEntry(categoryId: b.id, expectedRevision: 1),
            CategoryOrderEntry(categoryId: a.id, expectedRevision: 1)
        ])
        let result = try CategoryManagement.applying(payload, to: original)
        #expect(result.map(\.id) == [b.id, system.id, archived.id, a.id])
        #expect(result.map(\.presentationOrder) == [0, 1, 2, 4])
        #expect(result.map(\.revision) == [2, 1, 1, 2])
        #expect(result[1] == system)
        #expect(result[2] == archived)
        let partial = CategoryManagementPayload(action: .reorder, order: [
            CategoryOrderEntry(categoryId: a.id, expectedRevision: 1)
        ])
        #expect(throws: CategoryManagementFailure.invalidOrder) {
            try CategoryManagement.applying(partial, to: original)
        }
        let stale = CategoryManagementPayload(action: .reorder, order: [
            CategoryOrderEntry(categoryId: b.id, expectedRevision: 1),
            CategoryOrderEntry(categoryId: a.id, expectedRevision: 2)
        ])
        #expect(throws: CategoryManagementFailure.revisionConflict) {
            try CategoryManagement.applying(stale, to: original)
        }
        #expect(original.local.rows == [a, system, archived, b])
    }

    @Test func commandRoundTripPreservesFingerprintAndRejectsInvalidShapes() throws {
        let original = try row("category", order: 0)
        let command = try CategoryManagementCommand(
            operationId: OperationID(validating: "test-category-command"),
            accountId: original.accountId, actorPrincipalId: PrincipalID(validating: "member"),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000.123456), payload: edit(original))
        let bytes = try OperationContractCodec.encode(command)
        let restored = try OperationContractCodec.decode(CategoryManagementCommand.self, from: bytes)
        #expect(try command.fingerprint == restored.fingerprint)
        let envelope = try #require(JSONSerialization.jsonObject(
            with: OperationContractCodec.encode(command.envelope)) as? [String: Any])
        #expect((envelope["clientCreatedAt"] as? NSNumber)?.int64Value == 1_800_000_000_123)
        #expect((envelope["clientCreatedAt"] as? NSNumber)?.doubleValue == 1_800_000_000_123)
        for revision in ["0", "01", "-1", "1.0", "9223372036854775807", "18446744073709551615"] {
            #expect(throws: CategoryManagementFailure.invalidCommand) {
                try CategoryManagementPayload.validateRevision(revision)
            }
        }
        #expect(throws: CategoryManagementFailure.invalidCommand) {
            try CategoryManagementPayload(action: .archive, categoryId: original.id,
                expectedRevision: 1, name: original.name).validate()
        }
        #expect(throws: CategoryManagementFailure.invalidOrder) {
            try CategoryManagementPayload(action: .reorder, order: [
                CategoryOrderEntry(categoryId: original.id, expectedRevision: 1),
                CategoryOrderEntry(categoryId: original.id, expectedRevision: 1)
            ]).validate()
        }
    }

    private func edit(_ row: BudgetCategoryDefinitionSnapshot,
                      kind: BudgetCategoryKind? = nil) -> CategoryManagementPayload {
        CategoryManagementPayload(action: .edit, categoryId: row.id, expectedRevision: row.revision,
            name: row.name, kind: kind ?? row.kind,
            excludesFromOverallBudget: row.excludesFromOverallBudget)
    }

    private func row(_ name: String, kind: BudgetCategoryKind = .general,
                     lifecycle: DirectoryLifecycleState = .active, isSystem: Bool = false,
                     order: UInt32) throws -> BudgetCategoryDefinitionSnapshot {
        BudgetCategoryDefinitionSnapshot(id: try BudgetCategoryID(validating: "category-\(order)"),
            accountId: try AccountID(validating: "account"), name: try BudgetCategoryName(validating: name),
            kind: kind, lifecycle: lifecycle, isSystem: isSystem, excludesFromOverallBudget: false,
            presentationOrder: order, revision: 1)
    }

    private func snapshot(_ rows: [BudgetCategoryDefinitionSnapshot], complete: Bool = true) throws
        -> BudgetCategoryReferenceSnapshot {
        try BudgetCategoryReferenceSnapshot(accountId: AccountID(validating: "account"),
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(validating: String(repeating: "a", count: 64)),
                rows: rows, visibleRowCountBeforeFiltering: rows.count, isCompleteForQuery: complete,
                quality: .ready, localDataVersion: LocalDataVersion(validating: "category-tests"),
                asOf: Date(timeIntervalSince1970: 1_800_000_000)))
    }
}
