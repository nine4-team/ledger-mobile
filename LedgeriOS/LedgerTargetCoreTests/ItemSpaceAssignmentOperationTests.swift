import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Item-to-Space Assignment Operation Contracts")
struct ItemSpaceAssignmentOperationTests {
    @Test("Project and Inventory assignment preserve one exact canonical bulk intent")
    func exactScopeItemsAndPreconditions() throws {
        let project = try Self.command(
            items: [("item-zeta", 9), ("item-alpha", 4)]
        )
        let spaceSubject = try Self.reference(.space, "space-install")
        let projectSubject = try Self.reference(.project, "project-lake")
        let alphaSubject = try Self.reference(.item, "item-alpha")
        let zetaSubject = try Self.reference(.item, "item-zeta")
        let belongsToProject = try EntityStateCode(validating: "belongs_to_project")

        #expect(project.draft.items.map(\.itemId.rawValue) == ["item-alpha", "item-zeta"])
        #expect(project.envelope.payload.itemIds == project.draft.items.map(\.itemId))
        #expect(project.envelope.payload.destinationSpaceId.rawValue == "space-install")
        #expect(project.envelope.payload.scope == .project(
            try ProjectID(validating: "project-lake")
        ))
        #expect(project.subject == spaceSubject)
        #expect(project.envelope.preconditions == [
            .expectedState(
                subject: spaceSubject,
                state: try EntityStateCode(validating: "active")
            ),
            .expectedRevision(subject: spaceSubject, revision: 12),
            .expectedRelationship(
                subject: spaceSubject,
                relation: belongsToProject,
                target: projectSubject
            ),
            .expectedRevision(subject: alphaSubject, revision: 4),
            .expectedRelationship(
                subject: alphaSubject,
                relation: belongsToProject,
                target: projectSubject
            ),
            .expectedRevision(subject: zetaSubject, revision: 9),
            .expectedRelationship(
                subject: zetaSubject,
                relation: belongsToProject,
                target: projectSubject
            )
        ])

        let inventory = try Self.command(
            operationID: "operation-assign-inventory-items",
            destinationSpaceID: "space-warehouse",
            scope: .businessInventory,
            spaceRevision: 3,
            items: [("item-stock", 8)]
        )
        let inventorySpace = try Self.reference(.space, "space-warehouse")
        let account = try Self.reference(.account, "account-space-assignment-test")
        #expect(inventory.envelope.preconditions == [
            .expectedState(
                subject: inventorySpace,
                state: try EntityStateCode(validating: "active")
            ),
            .expectedRevision(subject: inventorySpace, revision: 3),
            .expectedRelationship(
                subject: inventorySpace,
                relation: try EntityStateCode(validating: "belongs_to_business_inventory"),
                target: account
            ),
            .expectedRevision(
                subject: try Self.reference(.item, "item-stock"),
                revision: 8
            ),
            .expectedRelationship(
                subject: try Self.reference(.item, "item-stock"),
                relation: try EntityStateCode(validating: "belongs_to_business_inventory"),
                target: account
            )
        ])

        let bytes = try OperationContractCodec.encode(project)
        #expect(Set(try Self.jsonObject(bytes).keys) == Set([
            "draft", "envelope", "fingerprint", "subject"
        ]))
        #expect(try Self.objectKeys(bytes, path: ["envelope", "payload"]) == Set([
            "destinationSpaceId", "scope", "itemIds"
        ]))
        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "transaction", "invoice", "occurrence", "budget", "category",
            "amount", "price", "payer", "acquisition", "attachment",
            "clearassignment", "archive", "delete", "fieldmap", "sql"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Single, bulk, Project, and Inventory evidence survives canonical restart")
    func canonicalRestartAndInputOrdering() throws {
        let project = try Self.command()
        let projectReordered = try Self.command(
            items: [("item-lamp", 4), ("item-chair", 2)]
        )
        let inventory = try Self.command(
            operationID: "operation-assign-inventory-restart",
            destinationSpaceID: "space-stockroom",
            scope: .businessInventory,
            spaceRevision: 7,
            items: [("item-inventory", 11)]
        )

        #expect(try OperationContractCodec.encode(project) ==
            OperationContractCodec.encode(projectReordered))
        #expect(project.fingerprint == projectReordered.fingerprint)

        for command in [project, inventory] {
            let bytes = try OperationContractCodec.encode(command)
            let restored = try OperationContractCodec.decode(
                AssignItemsToSpaceCommand.self,
                from: bytes
            )
            #expect(restored == command)
            #expect(try OperationContractCodec.encode(restored) == bytes)
            #expect(restored.fingerprint == (try OperationFingerprint.make(
                for: restored.envelope
            )))

            let text = String(decoding: bytes, as: UTF8.self).lowercased()
            for forbidden in [
                "firebase", "firestore", "supabase", "powersync", "https://",
                "file://", "bearer", "token", "secret", "serverresult",
                "authorization", "authorized", "migrated", "production"
            ] {
                #expect(!text.contains(forbidden))
            }
        }
    }

    @Test("Empty, duplicate, rebound, and tampered assignment evidence fails closed")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.assignmentFailure {
            try Self.draft(items: [])
        } == .emptyItemSelection)
        #expect(Self.assignmentFailure {
            try Self.draft(items: [("item-chair", 2), ("item-chair", 3)])
        } == .duplicateItemIdentity)
        #expect(Self.assignmentFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidCapturedAt)
        #expect(Self.assignmentFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .nan))
        } == .invalidCapturedAt)

        let command = try Self.command()
        let bytes = try OperationContractCodec.encode(command)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "accountId"],
            value: "account-other"
        )) == .draftAccountMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "actorPrincipalId"],
            value: "principal-other"
        )) == .draftActorMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "contractVersion"],
            value: "item-space-assignment-v2"
        )) == .draftContractMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "payload", "destinationSpaceId"],
            value: "space-other"
        )) == .draftPayloadMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "payload", "itemIds", "0"],
            value: "item-other"
        )) == .draftPayloadMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["draft", "expectedSpaceRevision", "rawValue"],
            value: 13
        )) == .assignmentPreconditionsMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["draft", "items", "0", "expectedRevision", "rawValue"],
            value: 99
        )) == .assignmentPreconditionsMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedState", "state"],
            value: "archived"
        )) == .assignmentPreconditionsMismatch)
        #expect(Self.decodeFailure(try Self.removeLastPrecondition(bytes)) ==
            .assignmentPreconditionsMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["subject", "kind"],
            value: "project"
        )) == .subjectMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["fingerprint"],
            value: String(repeating: "0", count: 64)
        )) == .fingerprintMismatch)
        #expect(Self.assignmentFailure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)

        let inventoryScope = try OperationContractCodec.encode(
            ItemPlacementScope.businessInventory
        )
        #expect(Self.scopeFailure(try Self.mutate(
            inventoryScope,
            path: ["projectId"],
            value: "project-invalid"
        )) == .invalidEncodedScope)
        #expect(Self.assignmentFailure {
            try OperationContractCodec.decode(
                ItemSpaceAssignmentCandidate.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedCandidate)
        #expect(Self.assignmentFailure {
            try OperationContractCodec.decode(
                ItemSpaceAssignmentDraft.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDraft)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(ItemSpaceAssignmentFailure, String)] = [
            (.emptyItemSelection, "item_space_assignment_selection_empty"),
            (.duplicateItemIdentity, "item_space_assignment_item_duplicate"),
            (.invalidCapturedAt, "item_space_assignment_captured_at_invalid"),
            (.draftAccountMismatch, "item_space_assignment_account_mismatch"),
            (.draftActorMismatch, "item_space_assignment_actor_mismatch"),
            (.draftContractMismatch, "item_space_assignment_contract_mismatch"),
            (.draftPayloadMismatch, "item_space_assignment_payload_mismatch"),
            (.assignmentPreconditionsMismatch, "item_space_assignment_preconditions_mismatch"),
            (.subjectMismatch, "item_space_assignment_subject_mismatch"),
            (.fingerprintMismatch, "item_space_assignment_fingerprint_mismatch"),
            (.receiptMismatch, "item_space_assignment_receipt_mismatch"),
            (.localAcceptanceFailed, "item_space_assignment_local_acceptance_failed"),
            (.invalidEncodedScope, "item_space_assignment_scope_encoding_invalid"),
            (.invalidEncodedCandidate, "item_space_assignment_candidate_encoding_invalid"),
            (.invalidEncodedDraft, "item_space_assignment_draft_encoding_invalid"),
            (.invalidEncodedCommand, "item_space_assignment_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The assignment port reuses shared queued replay semantics atomically")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command()
        let adapter = JournalItemSpaceAssignmentAdapter(acceptedAt: Self.t1)
        let first = try await adapter.assignItemsToSpace(command)
        let replay = try await adapter.assignItemsToSpace(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let variants = try [
            Self.command(
                operationID: command.envelope.operationId.rawValue,
                destinationSpaceID: "space-other"
            ),
            Self.command(
                operationID: command.envelope.operationId.rawValue,
                scope: .businessInventory
            ),
            Self.command(
                operationID: command.envelope.operationId.rawValue,
                items: [("item-chair", 3), ("item-lamp", 4)]
            ),
            Self.command(
                operationID: command.envelope.operationId.rawValue,
                items: [("item-chair", 2)]
            )
        ]
        for variant in variants {
            do {
                _ = try await adapter.assignItemsToSpace(variant)
                Issue.record("A reused OperationID accepted changed assignment intent")
            } catch let failure as OperationContractFailure {
                #expect(failure == .payloadMismatch(command.envelope.operationId))
            }
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingItemSpaceAssignmentAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.assignItemsToSpace(command)
        } catch let failure as ItemSpaceAssignmentFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_200_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_200_001)

    private static func draft(
        accountID: String = "account-space-assignment-test",
        principalID: String = "principal-space-assignment-test",
        destinationSpaceID: String = "space-install",
        scope: ItemPlacementScope = .project(try! ProjectID(validating: "project-lake")),
        spaceRevision: UInt64 = 12,
        items: [(String, UInt64)] = [("item-chair", 2), ("item-lamp", 4)],
        capturedAt: Date = t0
    ) throws -> ItemSpaceAssignmentDraft {
        try ItemSpaceAssignmentDraft(
            accountId: AccountID(validating: accountID),
            actorPrincipalId: PrincipalID(validating: principalID),
            operationContractVersion: OperationContractVersion(
                validating: "item-space-assignment-v1"
            ),
            destinationSpaceId: SpaceID(validating: destinationSpaceID),
            scope: scope,
            expectedSpaceRevision: ExpectedSpaceRevision(spaceRevision),
            items: try items.map {
                ItemSpaceAssignmentCandidate(
                    itemId: try ItemID(validating: $0.0),
                    expectedRevision: ExpectedItemPlacementRevision($0.1)
                )
            },
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-assign-items-to-space",
        accountID: String = "account-space-assignment-test",
        principalID: String = "principal-space-assignment-test",
        destinationSpaceID: String = "space-install",
        scope: ItemPlacementScope = .project(try! ProjectID(validating: "project-lake")),
        spaceRevision: UInt64 = 12,
        items: [(String, UInt64)] = [("item-chair", 2), ("item-lamp", 4)]
    ) throws -> AssignItemsToSpaceCommand {
        try AssignItemsToSpaceCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(
                accountID: accountID,
                principalID: principalID,
                destinationSpaceID: destinationSpaceID,
                scope: scope,
                spaceRevision: spaceRevision,
                items: items
            )
        )
    }

    private static func reference(
        _ kind: LedgerEntityKind,
        _ id: String
    ) throws -> LedgerEntityReference {
        LedgerEntityReference(kind: kind, id: try EntityID(validating: id))
    }

    private static func assignmentFailure<T>(
        _ operation: () throws -> T
    ) -> ItemSpaceAssignmentFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ItemSpaceAssignmentFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure(_ data: Data) -> ItemSpaceAssignmentFailure? {
        assignmentFailure {
            try OperationContractCodec.decode(
                AssignItemsToSpaceCommand.self,
                from: data
            )
        }
    }

    private static func scopeFailure(_ data: Data) -> ItemSpaceAssignmentFailure? {
        assignmentFailure {
            try OperationContractCodec.decode(ItemPlacementScope.self, from: data)
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ItemSpaceAssignmentFailure.invalidEncodedCommand
        }
        return object
    }

    private static func objectKeys(_ data: Data, path: [String]) throws -> Set<String> {
        var value: Any = try jsonObject(data)
        for key in path {
            guard let object = value as? [String: Any], let next = object[key] else {
                throw ItemSpaceAssignmentFailure.invalidEncodedCommand
            }
            value = next
        }
        guard let object = value as? [String: Any] else {
            throw ItemSpaceAssignmentFailure.invalidEncodedCommand
        }
        return Set(object.keys)
    }

    private static func mutate(_ data: Data, path: [String], value: Any) throws -> Data {
        var object = try jsonObject(data)
        try Self.set(value, at: path[...], in: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func removeLastPrecondition(_ data: Data) throws -> Data {
        var object = try jsonObject(data)
        guard var envelope = object["envelope"] as? [String: Any],
              var preconditions = envelope["preconditions"] as? [Any],
              !preconditions.isEmpty else {
            throw ItemSpaceAssignmentFailure.invalidEncodedCommand
        }
        preconditions.removeLast()
        envelope["preconditions"] = preconditions
        object["envelope"] = envelope
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func set(
        _ value: Any,
        at path: ArraySlice<String>,
        in object: inout [String: Any]
    ) throws {
        guard let key = path.first else {
            throw ItemSpaceAssignmentFailure.invalidEncodedCommand
        }
        if path.count == 1 {
            object[key] = value
            return
        }

        let remaining = path.dropFirst()
        if var child = object[key] as? [String: Any] {
            try set(value, at: remaining, in: &child)
            object[key] = child
            return
        }
        if var array = object[key] as? [Any],
           let index = Int(remaining.first ?? ""),
           array.indices.contains(index) {
            if remaining.count == 1 {
                array[index] = value
            } else if var child = array[index] as? [String: Any] {
                try set(value, at: remaining.dropFirst(), in: &child)
                array[index] = child
            } else {
                throw ItemSpaceAssignmentFailure.invalidEncodedCommand
            }
            object[key] = array
            return
        }
        throw ItemSpaceAssignmentFailure.invalidEncodedCommand
    }
}

private actor JournalItemSpaceAssignmentAdapter: ItemSpaceAssigning {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func assignItemsToSpace(
        _ command: AssignItemsToSpaceCommand
    ) async throws -> OperationReceipt {
        let receipt = try journal.accept(command.envelope, at: acceptedAt)
        return try command.validate(receipt)
    }

    var snapshotCount: Int {
        journal.snapshots.count
    }

    func fingerprint(for operationId: OperationID) -> OperationFingerprint? {
        journal.snapshot(for: operationId)?.fingerprint
    }
}

private struct FailingItemSpaceAssignmentAdapter: ItemSpaceAssigning {
    func assignItemsToSpace(
        _ command: AssignItemsToSpaceCommand
    ) async throws -> OperationReceipt {
        throw ItemSpaceAssignmentFailure.localAcceptanceFailed
    }
}
