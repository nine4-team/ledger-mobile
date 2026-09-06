import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Item Space-Assignment Clearing Operation Contracts")
struct ItemSpaceClearingOperationTests {
    @Test("Project and Inventory clearing preserve exact mixed-Space bulk intent")
    func exactScopeItemsAndPreconditions() throws {
        let project = try Self.command(items: [
            ("item-zeta", 9, "space-beta"),
            ("item-alpha", 4, "space-alpha"),
            ("item-gamma", 5, "space-beta")
        ])
        let projectSubject = try Self.reference(.project, "project-lake")
        let belongsToProject = try EntityStateCode(validating: "belongs_to_project")
        let assignedToSpace = try EntityStateCode(validating: "assigned_to_space")
        let alphaItem = try Self.reference(.item, "item-alpha")
        let gammaItem = try Self.reference(.item, "item-gamma")
        let zetaItem = try Self.reference(.item, "item-zeta")
        let alphaSpace = try Self.reference(.space, "space-alpha")
        let betaSpace = try Self.reference(.space, "space-beta")

        #expect(project.draft.items.map(\.itemId.rawValue) == [
            "item-alpha", "item-gamma", "item-zeta"
        ])
        #expect(project.envelope.payload.itemIds == project.draft.items.map(\.itemId))
        #expect(project.envelope.payload.scope == .project(
            try ProjectID(validating: "project-lake")
        ))
        #expect(project.subject == projectSubject)
        #expect(project.envelope.preconditions == [
            .expectedRelationship(
                subject: alphaSpace,
                relation: belongsToProject,
                target: projectSubject
            ),
            .expectedRelationship(
                subject: betaSpace,
                relation: belongsToProject,
                target: projectSubject
            ),
            .expectedRevision(subject: alphaItem, revision: 4),
            .expectedRelationship(
                subject: alphaItem,
                relation: belongsToProject,
                target: projectSubject
            ),
            .expectedRelationship(
                subject: alphaItem,
                relation: assignedToSpace,
                target: alphaSpace
            ),
            .expectedRevision(subject: gammaItem, revision: 5),
            .expectedRelationship(
                subject: gammaItem,
                relation: belongsToProject,
                target: projectSubject
            ),
            .expectedRelationship(
                subject: gammaItem,
                relation: assignedToSpace,
                target: betaSpace
            ),
            .expectedRevision(subject: zetaItem, revision: 9),
            .expectedRelationship(
                subject: zetaItem,
                relation: belongsToProject,
                target: projectSubject
            ),
            .expectedRelationship(
                subject: zetaItem,
                relation: assignedToSpace,
                target: betaSpace
            )
        ])

        let inventory = try Self.command(
            operationID: "operation-clear-inventory-spaces",
            scope: .businessInventory,
            items: [("item-stock", 8, "space-warehouse")]
        )
        let account = try Self.reference(.account, "account-space-clearing-test")
        let stock = try Self.reference(.item, "item-stock")
        let warehouse = try Self.reference(.space, "space-warehouse")
        let belongsToInventory = try EntityStateCode(
            validating: "belongs_to_business_inventory"
        )
        #expect(inventory.subject == account)
        #expect(inventory.envelope.preconditions == [
            .expectedRelationship(
                subject: warehouse,
                relation: belongsToInventory,
                target: account
            ),
            .expectedRevision(subject: stock, revision: 8),
            .expectedRelationship(
                subject: stock,
                relation: belongsToInventory,
                target: account
            ),
            .expectedRelationship(
                subject: stock,
                relation: assignedToSpace,
                target: warehouse
            )
        ])

        let bytes = try OperationContractCodec.encode(project)
        #expect(Set(try Self.jsonObject(bytes).keys) == Set([
            "draft", "envelope", "fingerprint", "subject"
        ]))
        #expect(try Self.objectKeys(bytes, path: ["envelope", "payload"]) == Set([
            "scope", "itemIds"
        ]))
        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "transaction", "invoice", "occurrence", "budget", "category",
            "amount", "price", "payer", "acquisition", "attachment",
            "marker", "photo", "delete", "archive", "fieldmap", "sql"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Single, mixed-Space bulk, Project, and Inventory evidence restarts canonically")
    func canonicalRestartAndInputOrdering() throws {
        let project = try Self.command()
        let reordered = try Self.command(items: [
            ("item-lamp", 4, "space-library"),
            ("item-chair", 2, "space-studio")
        ])
        let inventory = try Self.command(
            operationID: "operation-clear-inventory-restart",
            scope: .businessInventory,
            items: [("item-inventory", 11, "space-stockroom")]
        )

        #expect(try OperationContractCodec.encode(project) ==
            OperationContractCodec.encode(reordered))
        #expect(project.fingerprint == reordered.fingerprint)

        for command in [project, inventory] {
            let bytes = try OperationContractCodec.encode(command)
            let restored = try OperationContractCodec.decode(
                ClearItemSpaceAssignmentsCommand.self,
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

    @Test("Empty, duplicate, rebound, and tampered clearing evidence fails closed")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.clearingFailure {
            try Self.draft(items: [])
        } == .emptyItemSelection)
        #expect(Self.clearingFailure {
            try Self.draft(items: [
                ("item-chair", 2, "space-studio"),
                ("item-chair", 3, "space-library")
            ])
        } == .duplicateItemIdentity)
        #expect(Self.clearingFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidCapturedAt)
        #expect(Self.clearingFailure {
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
            value: "item-space-clearing-v2"
        )) == .draftContractMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "payload", "scope", "projectId"],
            value: "project-other"
        )) == .draftPayloadMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "payload", "itemIds", "0"],
            value: "item-other"
        )) == .draftPayloadMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["draft", "items", "0", "expectedRevision", "rawValue"],
            value: 99
        )) == .clearingPreconditionsMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["draft", "items", "0", "currentSpaceId"],
            value: "space-other"
        )) == .clearingPreconditionsMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRelationship", "target", "id"],
            value: "project-other"
        )) == .clearingPreconditionsMismatch)
        #expect(Self.decodeFailure(try Self.removeLastPrecondition(bytes)) ==
            .clearingPreconditionsMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["subject", "kind"],
            value: "account"
        )) == .subjectMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["fingerprint"],
            value: String(repeating: "0", count: 64)
        )) == .fingerprintMismatch)
        #expect(Self.clearingFailure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)
        #expect(Self.clearingFailure {
            try OperationContractCodec.decode(
                ItemSpaceClearingCandidate.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedCandidate)
        #expect(Self.clearingFailure {
            try OperationContractCodec.decode(
                ItemSpaceClearingDraft.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDraft)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(ItemSpaceClearingFailure, String)] = [
            (.emptyItemSelection, "item_space_clearing_selection_empty"),
            (.duplicateItemIdentity, "item_space_clearing_item_duplicate"),
            (.invalidCapturedAt, "item_space_clearing_captured_at_invalid"),
            (.draftAccountMismatch, "item_space_clearing_account_mismatch"),
            (.draftActorMismatch, "item_space_clearing_actor_mismatch"),
            (.draftContractMismatch, "item_space_clearing_contract_mismatch"),
            (.draftPayloadMismatch, "item_space_clearing_payload_mismatch"),
            (.clearingPreconditionsMismatch, "item_space_clearing_preconditions_mismatch"),
            (.subjectMismatch, "item_space_clearing_subject_mismatch"),
            (.fingerprintMismatch, "item_space_clearing_fingerprint_mismatch"),
            (.receiptMismatch, "item_space_clearing_receipt_mismatch"),
            (.localAcceptanceFailed, "item_space_clearing_local_acceptance_failed"),
            (.invalidEncodedCandidate, "item_space_clearing_candidate_encoding_invalid"),
            (.invalidEncodedDraft, "item_space_clearing_draft_encoding_invalid"),
            (.invalidEncodedCommand, "item_space_clearing_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The clearing port reuses shared queued replay semantics atomically")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command()
        let adapter = JournalItemSpaceClearingAdapter(acceptedAt: Self.t1)
        let first = try await adapter.clearItemSpaceAssignments(command)
        let replay = try await adapter.clearItemSpaceAssignments(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let variants = try [
            Self.command(
                operationID: command.envelope.operationId.rawValue,
                scope: .businessInventory
            ),
            Self.command(
                operationID: command.envelope.operationId.rawValue,
                items: [
                    ("item-chair", 2, "space-other"),
                    ("item-lamp", 4, "space-library")
                ]
            ),
            Self.command(
                operationID: command.envelope.operationId.rawValue,
                items: [
                    ("item-chair", 3, "space-studio"),
                    ("item-lamp", 4, "space-library")
                ]
            ),
            Self.command(
                operationID: command.envelope.operationId.rawValue,
                items: [("item-chair", 2, "space-studio")]
            )
        ]
        for variant in variants {
            do {
                _ = try await adapter.clearItemSpaceAssignments(variant)
                Issue.record("A reused OperationID accepted changed clearing intent")
            } catch let failure as OperationContractFailure {
                #expect(failure == .payloadMismatch(command.envelope.operationId))
            }
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingItemSpaceClearingAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.clearItemSpaceAssignments(command)
        } catch let failure as ItemSpaceClearingFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_300_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_300_001)

    private static func draft(
        accountID: String = "account-space-clearing-test",
        principalID: String = "principal-space-clearing-test",
        scope: ItemPlacementScope = .project(try! ProjectID(validating: "project-lake")),
        items: [(String, UInt64, String)] = [
            ("item-chair", 2, "space-studio"),
            ("item-lamp", 4, "space-library")
        ],
        capturedAt: Date = t0
    ) throws -> ItemSpaceClearingDraft {
        try ItemSpaceClearingDraft(
            accountId: AccountID(validating: accountID),
            actorPrincipalId: PrincipalID(validating: principalID),
            operationContractVersion: OperationContractVersion(
                validating: "item-space-clearing-v1"
            ),
            scope: scope,
            items: try items.map {
                ItemSpaceClearingCandidate(
                    itemId: try ItemID(validating: $0.0),
                    expectedRevision: ExpectedItemPlacementRevision($0.1),
                    currentSpaceId: try SpaceID(validating: $0.2)
                )
            },
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-clear-item-spaces",
        accountID: String = "account-space-clearing-test",
        principalID: String = "principal-space-clearing-test",
        scope: ItemPlacementScope = .project(try! ProjectID(validating: "project-lake")),
        items: [(String, UInt64, String)] = [
            ("item-chair", 2, "space-studio"),
            ("item-lamp", 4, "space-library")
        ]
    ) throws -> ClearItemSpaceAssignmentsCommand {
        try ClearItemSpaceAssignmentsCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(
                accountID: accountID,
                principalID: principalID,
                scope: scope,
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

    private static func clearingFailure<T>(
        _ operation: () throws -> T
    ) -> ItemSpaceClearingFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ItemSpaceClearingFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure(_ data: Data) -> ItemSpaceClearingFailure? {
        clearingFailure {
            try OperationContractCodec.decode(
                ClearItemSpaceAssignmentsCommand.self,
                from: data
            )
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ItemSpaceClearingFailure.invalidEncodedCommand
        }
        return object
    }

    private static func objectKeys(_ data: Data, path: [String]) throws -> Set<String> {
        var value: Any = try jsonObject(data)
        for key in path {
            guard let object = value as? [String: Any], let next = object[key] else {
                throw ItemSpaceClearingFailure.invalidEncodedCommand
            }
            value = next
        }
        guard let object = value as? [String: Any] else {
            throw ItemSpaceClearingFailure.invalidEncodedCommand
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
            throw ItemSpaceClearingFailure.invalidEncodedCommand
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
            throw ItemSpaceClearingFailure.invalidEncodedCommand
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
                throw ItemSpaceClearingFailure.invalidEncodedCommand
            }
            object[key] = array
            return
        }
        throw ItemSpaceClearingFailure.invalidEncodedCommand
    }
}

private actor JournalItemSpaceClearingAdapter: ItemSpaceAssignmentClearing {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func clearItemSpaceAssignments(
        _ command: ClearItemSpaceAssignmentsCommand
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

private struct FailingItemSpaceClearingAdapter: ItemSpaceAssignmentClearing {
    func clearItemSpaceAssignments(
        _ command: ClearItemSpaceAssignmentsCommand
    ) async throws -> OperationReceipt {
        throw ItemSpaceClearingFailure.localAcceptanceFailed
    }
}
