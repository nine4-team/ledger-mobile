import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Space Checklist Revision Operation Contracts")
struct SpaceChecklistRevisionOperationTests {
    @Test("Checklist revision is one complete ordered hierarchy on one revision-aware Space")
    func typedRevisionHasExactHierarchyAndProgress() throws {
        let command = try Self.command()
        let clear = try Self.command(
            operationID: "operation-clear-space-checklists",
            collection: SpaceChecklistCollection(checklists: [])
        )
        let duplicateLabels = try SpaceChecklistCollection(checklists: [
            Self.checklist(
                id: "checklist-duplicate-a",
                name: "  Install  ",
                order: 2,
                items: [
                    Self.item(id: "item-duplicate-a", text: "  Confirm  ", checked: false, order: 1)
                ]
            ),
            Self.checklist(
                id: "checklist-duplicate-b",
                name: "Install",
                order: 1,
                items: [
                    Self.item(id: "item-duplicate-b", text: "Confirm", checked: true, order: 1)
                ]
            )
        ])

        #expect(command.draft.spaceId.rawValue == "space-studio")
        #expect(command.draft.collection.checklists.map(\.id.rawValue) == [
            "checklist-arrival", "checklist-installation"
        ])
        #expect(command.draft.collection.checklists.map(\.presentationOrder) == [1, 2])
        #expect(command.draft.collection.checklists[0].items.isEmpty)
        #expect(
            command.draft.collection.checklists[1].items.map(\.id.rawValue) ==
                ["item-walls", "item-lamp"]
        )
        #expect(
            command.draft.collection.checklists[1].items.map(\.presentationOrder) ==
                [1, 2]
        )
        #expect(command.draft.collection.checklists[1].name.rawValue == "Installation\n Tasks")
        #expect(command.draft.collection.checklists[1].items[1].text.rawValue == "Connect\n lamp")
        #expect(command.draft.collection.completedItemCount == 1)
        #expect(command.draft.collection.totalItemCount == 2)
        #expect(clear.draft.collection.checklists.isEmpty)
        #expect(clear.draft.collection.completedItemCount == 0)
        #expect(clear.draft.collection.totalItemCount == 0)
        #expect(duplicateLabels.checklists.map(\.name.rawValue) == ["Install", "Install"])
        #expect(
            duplicateLabels.checklists.flatMap(\.items).map(\.text.rawValue) ==
                ["Confirm", "Confirm"]
        )
        #expect(command.envelope.payload == ReviseSpaceChecklistsPayload(
            spaceId: command.draft.spaceId,
            collection: command.draft.collection
        ))
        #expect(command.subject.kind == .space)
        #expect(command.subject.id.rawValue == command.draft.spaceId.rawValue)
        #expect(command.envelope.preconditions == [
            .expectedRevision(subject: command.subject, revision: 71)
        ])

        let bytes = try OperationContractCodec.encode(command)
        #expect(Set(try Self.jsonObject(bytes).keys) == Set([
            "draft", "envelope", "fingerprint", "subject"
        ]))
        #expect(try Self.objectKeys(bytes, path: ["envelope", "payload"]) == Set([
            "spaceId", "collection"
        ]))
        #expect(
            try Self.objectKeys(
                bytes,
                path: ["envelope", "payload", "collection"]
            ) == Set(["checklists"])
        )
        #expect(
            try Self.objectKeys(
                bytes,
                path: ["envelope", "payload", "collection", "checklists", "0"]
            ) == Set(["id", "name", "presentationOrder", "items"])
        )
        #expect(
            try Self.objectKeys(
                bytes,
                path: [
                    "envelope", "payload", "collection", "checklists", "1",
                    "items", "0"
                ]
            ) == Set(["id", "text", "isChecked", "presentationOrder"])
        )

        let encodedText = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "projectid", "businessinventory", "displayname", "notes", "template",
            "attachment", "review", "iscomplete", "archive", "transaction",
            "occurrence", "invoice", "budget", "payer", "price", "fieldmap",
            "collectionpath", "sql", "servertimestamp"
        ] {
            #expect(!encodedText.contains(forbidden))
        }
    }

    @Test("Canonical replace and clear evidence survive byte-identical offline restart")
    func canonicalRestartPreservesExactEvidence() throws {
        for command in [
            try Self.command(),
            try Self.command(
                operationID: "operation-clear-space-checklists",
                collection: SpaceChecklistCollection(checklists: [])
            )
        ] {
            let bytes = try OperationContractCodec.encode(command)
            let restored = try OperationContractCodec.decode(
                ReviseSpaceChecklistsCommand.self,
                from: bytes
            )

            #expect(restored == command)
            #expect(try OperationContractCodec.encode(restored) == bytes)
            #expect(restored.envelope.accountId.rawValue == "account-space-test")
            #expect(restored.envelope.actorPrincipalId.rawValue == "principal-space-test")
            #expect(restored.envelope.contractVersion.rawValue == "space-checklist-revision-v1")
            #expect(restored.envelope.clientCreatedAt == Self.t0)
            #expect(restored.fingerprint == (try OperationFingerprint.make(for: restored.envelope)))

            let text = String(decoding: bytes, as: UTF8.self).lowercased()
            for forbidden in [
                "firebase", "firestore", "supabase", "powersync", "https://", "file://",
                "bearer", "token", "secret", "serverresult", "server_result",
                "authorization", "authorized", "migrated", "production"
            ] {
                #expect(!text.contains(forbidden))
            }
        }
    }

    @Test("Invalid, noncanonical, duplicate, rebound, and tampered hierarchy fails atomically")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.failure {
            try SpaceChecklistName(validating: " \n\t ")
        } == .invalidChecklistName)
        #expect(Self.failure {
            try SpaceChecklistItemText(validating: " \n\t ")
        } == .invalidChecklistItemText)

        let duplicateItemIdentity = [
            try Self.item(id: "item-same", text: "First", checked: false, order: 1),
            try Self.item(id: "item-same", text: "Second", checked: true, order: 2)
        ]
        #expect(Self.failure {
            try Self.checklist(
                id: "checklist-one",
                name: "One",
                order: 1,
                items: duplicateItemIdentity
            )
        } == .duplicateChecklistItemIdentity)
        let duplicateItemOrder = [
            try Self.item(id: "item-one", text: "First", checked: false, order: 1),
            try Self.item(id: "item-two", text: "Second", checked: true, order: 1)
        ]
        #expect(Self.failure {
            try Self.checklist(
                id: "checklist-one",
                name: "One",
                order: 1,
                items: duplicateItemOrder
            )
        } == .duplicateChecklistItemPresentationOrder)

        let checklistOne = try Self.checklist(
            id: "checklist-same",
            name: "One",
            order: 1,
            items: []
        )
        let checklistDuplicateID = try Self.checklist(
            id: "checklist-same",
            name: "Two",
            order: 2,
            items: []
        )
        #expect(Self.failure {
            try SpaceChecklistCollection(
                checklists: [checklistOne, checklistDuplicateID]
            )
        } == .duplicateChecklistIdentity)
        let checklistDuplicateOrder = try Self.checklist(
            id: "checklist-two",
            name: "Two",
            order: 1,
            items: []
        )
        #expect(Self.failure {
            try SpaceChecklistCollection(
                checklists: [checklistOne, checklistDuplicateOrder]
            )
        } == .duplicateChecklistPresentationOrder)
        #expect(Self.failure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidCapturedAt)
        #expect(Self.failure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .nan))
        } == .invalidCapturedAt)

        let command = try Self.command()
        let bytes = try OperationContractCodec.encode(command)
        let noncanonicalName = try Self.mutate(
            bytes,
            path: ["draft", "collection", "checklists", "0", "name"],
            value: "  Arrival  "
        )
        #expect(Self.decodeFailure(noncanonicalName) == .invalidEncodedChecklistName)
        let noncanonicalText = try Self.mutate(
            bytes,
            path: [
                "draft", "collection", "checklists", "1", "items", "0", "text"
            ],
            value: "  Prepare walls  "
        )
        #expect(Self.decodeFailure(noncanonicalText) == .invalidEncodedChecklistItemText)
        let noncanonicalChecklistOrder = try Self.reverseArray(
            bytes,
            path: ["draft", "collection", "checklists"]
        )
        #expect(Self.decodeFailure(noncanonicalChecklistOrder) == .invalidEncodedCollection)
        let noncanonicalItemOrder = try Self.reverseArray(
            bytes,
            path: ["draft", "collection", "checklists", "1", "items"]
        )
        #expect(Self.decodeFailure(noncanonicalItemOrder) == .invalidEncodedChecklist)

        let changedAccount = try Self.mutate(
            bytes,
            path: ["envelope", "accountId"],
            value: "account-other"
        )
        #expect(Self.decodeFailure(changedAccount) == .draftAccountMismatch)
        let changedActor = try Self.mutate(
            bytes,
            path: ["envelope", "actorPrincipalId"],
            value: "principal-other"
        )
        #expect(Self.decodeFailure(changedActor) == .draftActorMismatch)
        let changedContract = try Self.mutate(
            bytes,
            path: ["envelope", "contractVersion"],
            value: "space-checklist-revision-v2"
        )
        #expect(Self.decodeFailure(changedContract) == .draftContractMismatch)
        let changedSpace = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "spaceId"],
            value: "space-other"
        )
        #expect(Self.decodeFailure(changedSpace) == .draftPayloadMismatch)
        let changedName = try Self.mutate(
            bytes,
            path: [
                "envelope", "payload", "collection", "checklists", "0", "name"
            ],
            value: "Delivery"
        )
        #expect(Self.decodeFailure(changedName) == .draftPayloadMismatch)
        let changedCheckedState = try Self.mutate(
            bytes,
            path: [
                "envelope", "payload", "collection", "checklists", "1",
                "items", "0", "isChecked"
            ],
            value: false
        )
        #expect(Self.decodeFailure(changedCheckedState) == .draftPayloadMismatch)
        let changedItemOrder = try Self.mutate(
            bytes,
            path: [
                "envelope", "payload", "collection", "checklists", "1",
                "items", "0", "presentationOrder"
            ],
            value: 0
        )
        #expect(Self.decodeFailure(changedItemOrder) == .draftPayloadMismatch)

        let revisionSubject = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "subject", "id"],
            value: "space-other"
        )
        #expect(Self.decodeFailure(revisionSubject) == .revisionPreconditionMismatch)
        let revisionValue = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "revision"],
            value: 72
        )
        #expect(Self.decodeFailure(revisionValue) == .revisionPreconditionMismatch)
        let noPreconditions = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions"],
            value: []
        )
        #expect(Self.decodeFailure(noPreconditions) == .revisionPreconditionMismatch)
        let duplicatePreconditions = try Self.duplicateFirstPrecondition(bytes)
        #expect(Self.decodeFailure(duplicatePreconditions) == .revisionPreconditionMismatch)

        let changedSubject = try Self.mutate(
            bytes,
            path: ["subject", "id"],
            value: "space-other"
        )
        #expect(Self.decodeFailure(changedSubject) == .subjectMismatch)
        let changedFingerprint = try Self.mutate(
            bytes,
            path: ["fingerprint"],
            value: String(repeating: "0", count: 64)
        )
        #expect(Self.decodeFailure(changedFingerprint) == .fingerprintMismatch)
        #expect(Self.failure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)

        #expect(Self.failure {
            try OperationContractCodec.decode(
                SpaceChecklistRevisionDraft.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDraft)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(SpaceChecklistRevisionFailure, String)] = [
            (.invalidChecklistName, "space_checklist_name_invalid"),
            (.invalidChecklistItemText, "space_checklist_item_text_invalid"),
            (.duplicateChecklistIdentity, "space_checklist_identity_duplicate"),
            (.duplicateChecklistPresentationOrder, "space_checklist_order_duplicate"),
            (.duplicateChecklistItemIdentity, "space_checklist_item_identity_duplicate"),
            (.duplicateChecklistItemPresentationOrder, "space_checklist_item_order_duplicate"),
            (.invalidCapturedAt, "space_checklist_revision_captured_at_invalid"),
            (.draftAccountMismatch, "space_checklist_revision_account_mismatch"),
            (.draftActorMismatch, "space_checklist_revision_actor_mismatch"),
            (.draftContractMismatch, "space_checklist_revision_contract_mismatch"),
            (.draftPayloadMismatch, "space_checklist_revision_payload_mismatch"),
            (.revisionPreconditionMismatch, "space_checklist_revision_precondition_mismatch"),
            (.subjectMismatch, "space_checklist_revision_subject_mismatch"),
            (.fingerprintMismatch, "space_checklist_revision_fingerprint_mismatch"),
            (.receiptMismatch, "space_checklist_revision_receipt_mismatch"),
            (.localAcceptanceFailed, "space_checklist_revision_local_acceptance_failed"),
            (.invalidEncodedChecklistName, "space_checklist_name_encoding_invalid"),
            (.invalidEncodedChecklistItemText, "space_checklist_item_text_encoding_invalid"),
            (.invalidEncodedChecklistItem, "space_checklist_item_encoding_invalid"),
            (.invalidEncodedChecklist, "space_checklist_encoding_invalid"),
            (.invalidEncodedCollection, "space_checklist_collection_encoding_invalid"),
            (.invalidEncodedDraft, "space_checklist_revision_draft_encoding_invalid"),
            (.invalidEncodedCommand, "space_checklist_revision_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The checklist revision port reuses shared queued receipt and replay semantics")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command()
        let adapter = JournalSpaceChecklistRevisionAdapter(acceptedAt: Self.t1)
        let first = try await adapter.reviseChecklists(command)
        let replay = try await adapter.reviseChecklists(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let renamed = try Self.defaultCollection(firstChecklistName: "Delivery")
        let checked = try Self.defaultCollection(firstItemChecked: false)
        let reordered = try Self.defaultCollection(firstChecklistOrder: 3)
        let variants = [
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                spaceID: "space-other"
            ),
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                collection: renamed
            ),
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                collection: checked
            ),
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                collection: reordered
            ),
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                revision: 72
            )
        ]
        for variant in variants {
            do {
                _ = try await adapter.reviseChecklists(variant)
                Issue.record("A reused OperationID accepted changed checklist intent")
            } catch let failure as OperationContractFailure {
                #expect(failure == .payloadMismatch(command.envelope.operationId))
            }
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingSpaceChecklistRevisionAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.reviseChecklists(command)
        } catch let failure as SpaceChecklistRevisionFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_000_001)

    private static func item(
        id: String,
        text: String,
        checked: Bool,
        order: UInt32
    ) throws -> SpaceChecklistItemState {
        SpaceChecklistItemState(
            id: try SpaceChecklistItemID(validating: id),
            text: try SpaceChecklistItemText(validating: text),
            isChecked: checked,
            presentationOrder: order
        )
    }

    private static func checklist(
        id: String,
        name: String,
        order: UInt32,
        items: [SpaceChecklistItemState]
    ) throws -> SpaceChecklistState {
        try SpaceChecklistState(
            id: SpaceChecklistID(validating: id),
            name: SpaceChecklistName(validating: name),
            presentationOrder: order,
            items: items
        )
    }

    private static func defaultCollection(
        firstChecklistName: String = "  Arrival  ",
        firstItemChecked: Bool = true,
        firstChecklistOrder: UInt32 = 1
    ) throws -> SpaceChecklistCollection {
        let installation = try checklist(
            id: "checklist-installation",
            name: "  Installation\n Tasks  ",
            order: 2,
            items: [
                try item(
                    id: "item-lamp",
                    text: "  Connect\n lamp  ",
                    checked: false,
                    order: 2
                ),
                try item(
                    id: "item-walls",
                    text: "  Prepare walls  ",
                    checked: firstItemChecked,
                    order: 1
                )
            ]
        )
        let arrival = try checklist(
            id: "checklist-arrival",
            name: firstChecklistName,
            order: firstChecklistOrder,
            items: []
        )
        return try SpaceChecklistCollection(checklists: [installation, arrival])
    }

    private static func draft(
        spaceID: String = "space-studio",
        collection: SpaceChecklistCollection? = nil,
        revision: UInt64 = 71,
        capturedAt: Date = t0
    ) throws -> SpaceChecklistRevisionDraft {
        try SpaceChecklistRevisionDraft(
            accountId: AccountID(validating: "account-space-test"),
            actorPrincipalId: PrincipalID(validating: "principal-space-test"),
            operationContractVersion: OperationContractVersion(
                validating: "space-checklist-revision-v1"
            ),
            spaceId: SpaceID(validating: spaceID),
            collection: collection ?? defaultCollection(),
            expectedRevision: ExpectedSpaceRevision(revision),
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-revise-space-checklists",
        spaceID: String = "space-studio",
        collection: SpaceChecklistCollection? = nil,
        revision: UInt64 = 71
    ) throws -> ReviseSpaceChecklistsCommand {
        try ReviseSpaceChecklistsCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(
                spaceID: spaceID,
                collection: collection,
                revision: revision
            )
        )
    }

    private static func failure<T>(
        _ operation: () throws -> T
    ) -> SpaceChecklistRevisionFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as SpaceChecklistRevisionFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure(_ data: Data) -> SpaceChecklistRevisionFailure? {
        failure {
            try OperationContractCodec.decode(
                ReviseSpaceChecklistsCommand.self,
                from: data
            )
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpaceChecklistRevisionFailure.invalidEncodedCommand
        }
        return object
    }

    private static func objectKeys(_ data: Data, path: [String]) throws -> Set<String> {
        var value: Any = try jsonObject(data)
        for key in path {
            if let object = value as? [String: Any], let next = object[key] {
                value = next
            } else if let array = value as? [Any],
                      let index = Int(key),
                      array.indices.contains(index) {
                value = array[index]
            } else {
                throw SpaceChecklistRevisionFailure.invalidEncodedCommand
            }
        }
        guard let object = value as? [String: Any] else {
            throw SpaceChecklistRevisionFailure.invalidEncodedCommand
        }
        return Set(object.keys)
    }

    private static func mutate(_ data: Data, path: [String], value: Any) throws -> Data {
        var object = try jsonObject(data)
        try Self.set(value, at: path[...], in: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func reverseArray(_ data: Data, path: [String]) throws -> Data {
        var object = try jsonObject(data)
        try Self.reverse(at: path[...], in: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func duplicateFirstPrecondition(_ data: Data) throws -> Data {
        var object = try jsonObject(data)
        guard var envelope = object["envelope"] as? [String: Any],
              var preconditions = envelope["preconditions"] as? [Any],
              let first = preconditions.first else {
            throw SpaceChecklistRevisionFailure.invalidEncodedCommand
        }
        preconditions.append(first)
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
            throw SpaceChecklistRevisionFailure.invalidEncodedCommand
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
            let tail = remaining.dropFirst()
            if tail.isEmpty {
                array[index] = value
            } else {
                guard var child = array[index] as? [String: Any] else {
                    throw SpaceChecklistRevisionFailure.invalidEncodedCommand
                }
                try set(value, at: tail, in: &child)
                array[index] = child
            }
            object[key] = array
            return
        }
        throw SpaceChecklistRevisionFailure.invalidEncodedCommand
    }

    private static func reverse(
        at path: ArraySlice<String>,
        in object: inout [String: Any]
    ) throws {
        guard let key = path.first else {
            throw SpaceChecklistRevisionFailure.invalidEncodedCommand
        }
        if path.count == 1 {
            guard let array = object[key] as? [Any] else {
                throw SpaceChecklistRevisionFailure.invalidEncodedCommand
            }
            object[key] = Array(array.reversed())
            return
        }

        let remaining = path.dropFirst()
        if var child = object[key] as? [String: Any] {
            try reverse(at: remaining, in: &child)
            object[key] = child
            return
        }
        if var array = object[key] as? [Any],
           let index = Int(remaining.first ?? ""),
           array.indices.contains(index),
           var child = array[index] as? [String: Any] {
            try reverse(at: remaining.dropFirst(), in: &child)
            array[index] = child
            object[key] = array
            return
        }
        throw SpaceChecklistRevisionFailure.invalidEncodedCommand
    }
}

private actor JournalSpaceChecklistRevisionAdapter: SpaceChecklistRevising {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func reviseChecklists(
        _ command: ReviseSpaceChecklistsCommand
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

private struct FailingSpaceChecklistRevisionAdapter: SpaceChecklistRevising {
    func reviseChecklists(
        _ command: ReviseSpaceChecklistsCommand
    ) async throws -> OperationReceipt {
        throw SpaceChecklistRevisionFailure.localAcceptanceFailed
    }
}
