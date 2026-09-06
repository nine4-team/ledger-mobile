import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Space Details Update Operation Contracts")
struct SpaceDetailsUpdateOperationTests {
    @Test("Details update is one complete normalized pair on one revision-aware Space")
    func typedUpdateHasExactScopeAndNormalization() throws {
        let command = try Self.command(
            name: "  Guest\n Room  ",
            notes: "  East\n windows  "
        )
        let clear = try Self.command(
            operationID: "operation-clear-space-notes",
            name: "  Guest Room  ",
            notes: " \n\t "
        )
        let duplicateName = try Self.command(
            operationID: "operation-duplicate-space-name",
            spaceID: "space-other",
            name: "Guest\n Room",
            notes: nil
        )

        #expect(command.draft.spaceId.rawValue == "space-studio")
        #expect(command.draft.displayName.rawValue == "Guest\n Room")
        #expect(command.draft.notes.value == "East\n windows")
        #expect(clear.draft.displayName.rawValue == "Guest Room")
        #expect(clear.draft.notes.value == nil)
        #expect(duplicateName.draft.displayName == command.draft.displayName)
        #expect(duplicateName.draft.spaceId != command.draft.spaceId)
        #expect(command.envelope.payload == UpdateSpaceDetailsPayload(
            spaceId: command.draft.spaceId,
            displayName: command.draft.displayName,
            notes: command.draft.notes
        ))
        #expect(command.subject.kind == .space)
        #expect(command.subject.id.rawValue == command.draft.spaceId.rawValue)
        #expect(command.envelope.preconditions == [
            .expectedRevision(subject: command.subject, revision: 61)
        ])

        let bytes = try OperationContractCodec.encode(command)
        let clearBytes = try OperationContractCodec.encode(clear)
        #expect(Set(try Self.jsonObject(bytes).keys) == Set([
            "draft", "envelope", "fingerprint", "subject"
        ]))
        #expect(try Self.objectKeys(bytes, path: ["envelope", "payload"]) == Set([
            "spaceId", "displayName", "notes"
        ]))
        #expect(try Self.objectKeys(clearBytes, path: ["envelope", "payload", "notes"]) == Set([
            "value"
        ]))

        let clearObject = try Self.jsonObject(clearBytes)
        let clearEnvelope = try #require(clearObject["envelope"] as? [String: Any])
        let clearPayload = try #require(clearEnvelope["payload"] as? [String: Any])
        let clearNotes = try #require(clearPayload["notes"] as? [String: Any])
        #expect(clearNotes["value"] is NSNull)

        let encodedText = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "projectid", "businessinventory", "scope", "checklist", "template",
            "attachment", "review", "complete", "archive", "transaction",
            "occurrence", "invoice", "budget", "payer", "price", "fieldmap",
            "collectionpath", "sql", "servertimestamp"
        ] {
            #expect(!encodedText.contains(forbidden))
        }
    }

    @Test("Canonical set and clear details survive byte-identical offline restart")
    func canonicalRestartPreservesExactEvidence() throws {
        for command in [
            try Self.command(name: "Guest Room", notes: "East windows"),
            try Self.command(
                operationID: "operation-clear-space-notes",
                name: "Guest Room",
                notes: nil
            )
        ] {
            let bytes = try OperationContractCodec.encode(command)
            let restored = try OperationContractCodec.decode(
                UpdateSpaceDetailsCommand.self,
                from: bytes
            )

            #expect(restored == command)
            #expect(try OperationContractCodec.encode(restored) == bytes)
            #expect(restored.envelope.accountId.rawValue == "account-space-test")
            #expect(restored.envelope.actorPrincipalId.rawValue == "principal-space-test")
            #expect(restored.envelope.contractVersion.rawValue == "space-details-update-v1")
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

    @Test("Noncanonical, rebound, and tampered Space details evidence fails atomically")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.spaceValueFailure {
            try SpaceDisplayName(validating: " \n\t ")
        } == .invalidDisplayName)
        #expect(Self.detailsFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidCapturedAt)
        #expect(Self.detailsFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .nan))
        } == .invalidCapturedAt)

        let command = try Self.command()
        let bytes = try OperationContractCodec.encode(command)
        let noncanonicalName = try Self.mutate(
            bytes,
            path: ["draft", "displayName"],
            value: "  Studio  "
        )
        #expect(Self.decodeSpaceValueFailure(noncanonicalName) == .invalidEncodedDisplayName)
        let noncanonicalNotes = try Self.mutate(
            bytes,
            path: ["draft", "notes", "value"],
            value: "  East windows  "
        )
        #expect(Self.decodeSpaceValueFailure(noncanonicalNotes) == .invalidEncodedNotes)

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
            value: "space-details-update-v2"
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
            path: ["envelope", "payload", "displayName"],
            value: "Library"
        )
        #expect(Self.decodeFailure(changedName) == .draftPayloadMismatch)
        let changedNotes = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "notes", "value"],
            value: "West wall"
        )
        #expect(Self.decodeFailure(changedNotes) == .draftPayloadMismatch)

        let revisionSubject = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "subject", "id"],
            value: "space-other"
        )
        #expect(Self.decodeFailure(revisionSubject) == .revisionPreconditionMismatch)
        let revisionValue = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "revision"],
            value: 62
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
        #expect(Self.detailsFailure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)

        #expect(Self.detailsFailure {
            try OperationContractCodec.decode(
                SpaceDetailsUpdateDraft.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDraft)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(SpaceDetailsUpdateFailure, String)] = [
            (.invalidCapturedAt, "space_details_update_captured_at_invalid"),
            (.draftAccountMismatch, "space_details_update_account_mismatch"),
            (.draftActorMismatch, "space_details_update_actor_mismatch"),
            (.draftContractMismatch, "space_details_update_contract_mismatch"),
            (.draftPayloadMismatch, "space_details_update_payload_mismatch"),
            (
                .revisionPreconditionMismatch,
                "space_details_update_revision_precondition_mismatch"
            ),
            (.subjectMismatch, "space_details_update_subject_mismatch"),
            (.fingerprintMismatch, "space_details_update_fingerprint_mismatch"),
            (.receiptMismatch, "space_details_update_receipt_mismatch"),
            (.localAcceptanceFailed, "space_details_update_local_acceptance_failed"),
            (.invalidEncodedDraft, "space_details_update_draft_encoding_invalid"),
            (.invalidEncodedCommand, "space_details_update_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
        #expect(
            SpaceCreationFailure.invalidEncodedDisplayName.diagnosticCode ==
                "space_creation_display_name_encoding_invalid"
        )
        #expect(
            SpaceCreationFailure.invalidEncodedNotes.diagnosticCode ==
                "space_creation_notes_encoding_invalid"
        )
    }

    @Test("The Space details port reuses shared queued receipt and replay semantics")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command()
        let adapter = JournalSpaceDetailsUpdateAdapter(acceptedAt: Self.t1)
        let first = try await adapter.updateDetails(command)
        let replay = try await adapter.updateDetails(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let variants = [
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                spaceID: "space-other"
            ),
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                name: "Library"
            ),
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                notes: "West wall"
            ),
            try Self.command(
                operationID: command.envelope.operationId.rawValue,
                revision: 62
            )
        ]
        for variant in variants {
            do {
                _ = try await adapter.updateDetails(variant)
                Issue.record("A reused OperationID accepted changed Space details intent")
            } catch let failure as OperationContractFailure {
                #expect(failure == .payloadMismatch(command.envelope.operationId))
            }
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingSpaceDetailsUpdateAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.updateDetails(command)
        } catch let failure as SpaceDetailsUpdateFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_801_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_801_000_001)

    private static func draft(
        spaceID: String = "space-studio",
        name: String = "Studio",
        notes: String? = "East windows",
        revision: UInt64 = 61,
        capturedAt: Date = t0
    ) throws -> SpaceDetailsUpdateDraft {
        try SpaceDetailsUpdateDraft(
            accountId: AccountID(validating: "account-space-test"),
            actorPrincipalId: PrincipalID(validating: "principal-space-test"),
            operationContractVersion: OperationContractVersion(
                validating: "space-details-update-v1"
            ),
            spaceId: SpaceID(validating: spaceID),
            displayName: SpaceDisplayName(validating: name),
            notes: SpaceCreationNotes(notes),
            expectedRevision: ExpectedSpaceRevision(revision),
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-update-space-details",
        spaceID: String = "space-studio",
        name: String = "Studio",
        notes: String? = "East windows",
        revision: UInt64 = 61
    ) throws -> UpdateSpaceDetailsCommand {
        try UpdateSpaceDetailsCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(
                spaceID: spaceID,
                name: name,
                notes: notes,
                revision: revision
            )
        )
    }

    private static func detailsFailure<T>(
        _ operation: () throws -> T
    ) -> SpaceDetailsUpdateFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as SpaceDetailsUpdateFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func spaceValueFailure<T>(
        _ operation: () throws -> T
    ) -> SpaceCreationFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as SpaceCreationFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure(_ data: Data) -> SpaceDetailsUpdateFailure? {
        detailsFailure {
            try OperationContractCodec.decode(UpdateSpaceDetailsCommand.self, from: data)
        }
    }

    private static func decodeSpaceValueFailure(_ data: Data) -> SpaceCreationFailure? {
        spaceValueFailure {
            try OperationContractCodec.decode(UpdateSpaceDetailsCommand.self, from: data)
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpaceDetailsUpdateFailure.invalidEncodedCommand
        }
        return object
    }

    private static func objectKeys(_ data: Data, path: [String]) throws -> Set<String> {
        var value: Any = try jsonObject(data)
        for key in path {
            guard let object = value as? [String: Any], let next = object[key] else {
                throw SpaceDetailsUpdateFailure.invalidEncodedCommand
            }
            value = next
        }
        guard let object = value as? [String: Any] else {
            throw SpaceDetailsUpdateFailure.invalidEncodedCommand
        }
        return Set(object.keys)
    }

    private static func mutate(_ data: Data, path: [String], value: Any) throws -> Data {
        var object = try jsonObject(data)
        try Self.set(value, at: path[...], in: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func duplicateFirstPrecondition(_ data: Data) throws -> Data {
        var object = try jsonObject(data)
        guard var envelope = object["envelope"] as? [String: Any],
              var preconditions = envelope["preconditions"] as? [Any],
              let first = preconditions.first else {
            throw SpaceDetailsUpdateFailure.invalidEncodedCommand
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
            throw SpaceDetailsUpdateFailure.invalidEncodedCommand
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
                    throw SpaceDetailsUpdateFailure.invalidEncodedCommand
                }
                try set(value, at: tail, in: &child)
                array[index] = child
            }
            object[key] = array
            return
        }
        throw SpaceDetailsUpdateFailure.invalidEncodedCommand
    }
}

private actor JournalSpaceDetailsUpdateAdapter: SpaceDetailsUpdating {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func updateDetails(
        _ command: UpdateSpaceDetailsCommand
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

private struct FailingSpaceDetailsUpdateAdapter: SpaceDetailsUpdating {
    func updateDetails(
        _ command: UpdateSpaceDetailsCommand
    ) async throws -> OperationReceipt {
        throw SpaceDetailsUpdateFailure.localAcceptanceFailed
    }
}
