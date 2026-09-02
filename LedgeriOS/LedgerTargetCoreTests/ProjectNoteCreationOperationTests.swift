import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Note Creation Operation Contracts")
struct ProjectNoteCreationOperationTests {
    @Test("One typed command preserves stable note intent and excludes authoritative audit")
    func typedCommandPreservesExactIntent() throws {
        let first = try Self.command()
        let second = try Self.command(
            operationID: "operation-add-note-second",
            noteID: "note-second"
        )

        #expect(first.draft.noteId != second.draft.noteId)
        #expect(first.envelope.payload.text == second.envelope.payload.text)
        #expect(first.envelope.payload.requestedSource == second.envelope.payload.requestedSource)
        #expect(first.fingerprint != second.fingerprint)
        #expect(first.parentProject.kind == .project)
        #expect(first.parentProject.id.rawValue == first.draft.projectId.rawValue)
        #expect(first.envelope.preconditions.isEmpty)
        #expect(first.envelope.accountId == first.draft.accountId)
        #expect(first.envelope.actorPrincipalId == first.draft.actorPrincipalId)
        #expect(first.envelope.contractVersion == first.draft.operationContractVersion)

        let root = try Self.jsonObject(OperationContractCodec.encode(first))
        #expect(Set(root.keys) == Set(["draft", "envelope", "fingerprint", "parentProject"]))
        let envelope = try #require(root["envelope"] as? [String: Any])
        let payload = try #require(envelope["payload"] as? [String: Any])
        #expect(
            Set(payload.keys) ==
                Set(["projectId", "noteId", "text", "requestedSource"])
        )

        let encodedText = String(
            decoding: try OperationContractCodec.encode(first),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "createdby", "creatordisplayname", "servercreatedat", "lastedited",
            "revision", "deletion", "authorization", "clientname", "projectname",
            "firebase", "firestore", "supabase", "powersync", "collection/", "sql"
        ] {
            #expect(!encodedText.contains(forbidden))
        }
    }

    @Test("Canonical note intent survives structured restart without provider claims")
    func canonicalRestartIsByteIdentical() throws {
        let command = try Self.command()
        let bytes = try OperationContractCodec.encode(command)
        let restored = try OperationContractCodec.decode(
            AddProjectNoteCommand.self,
            from: bytes
        )

        #expect(restored == command)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.envelope.operationId.rawValue == "operation-add-note-entry")
        #expect(restored.envelope.accountId.rawValue == "account-note-create-test")
        #expect(restored.envelope.actorPrincipalId.rawValue == "principal-note-create-test")
        #expect(restored.envelope.contractVersion.rawValue == "project-note-add-v1")
        #expect(restored.envelope.clientCreatedAt == Self.t0)
        #expect(restored.envelope.payload.projectId.rawValue == "project-note-create-test")
        #expect(restored.envelope.payload.noteId.rawValue == "note-entry")
        #expect(restored.envelope.payload.text.rawValue == "Gate code is 4816")
        #expect(restored.envelope.payload.requestedSource.rawValue == "text")
        #expect(restored.parentProject.kind == .project)
        #expect(restored.parentProject.id.rawValue == "project-note-create-test")
        #expect(restored.fingerprint == (try OperationFingerprint.make(for: restored.envelope)))

        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "https://", "file://", "bearer", "token", "secret",
            "serverresult", "server_result", "serviceaccount", "service_account"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Invalid, rebound, and tampered note intent fails atomically")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.noteDataFailure {
            try ProjectNoteText(validating: " \n\t ")
        } == .invalidText)
        #expect(Self.noteDataFailure {
            try ProjectNoteSource(validating: "MCP")
        } == .invalidSource)
        #expect(Self.creationFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidClientCreatedAt)
        #expect(Self.creationFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .nan))
        } == .invalidClientCreatedAt)

        let command = try Self.command()
        let bytes = try OperationContractCodec.encode(command)
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
            value: "project-note-add-v2"
        )
        #expect(Self.decodeFailure(changedContract) == .draftContractMismatch)
        let changedProject = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "projectId"],
            value: "project-other"
        )
        #expect(Self.decodeFailure(changedProject) == .draftPayloadMismatch)
        let changedNote = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "noteId"],
            value: "note-other"
        )
        #expect(Self.decodeFailure(changedNote) == .draftPayloadMismatch)
        let changedText = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "text"],
            value: "Different note"
        )
        #expect(Self.decodeFailure(changedText) == .draftPayloadMismatch)
        let changedSource = try Self.mutate(
            bytes,
            path: ["envelope", "payload", "requestedSource"],
            value: "mcp"
        )
        #expect(Self.decodeFailure(changedSource) == .draftPayloadMismatch)

        let precondition = OperationPrecondition.expectedRevision(
            subject: command.parentProject,
            revision: 4
        )
        let preconditionJSON = try JSONSerialization.jsonObject(
            with: OperationContractCodec.encode([precondition])
        )
        let changedPreconditions = try Self.mutate(
            bytes,
            path: ["envelope", "preconditions"],
            value: preconditionJSON
        )
        #expect(Self.decodeFailure(changedPreconditions) == .unexpectedPreconditions)

        let changedParentKind = try Self.mutate(
            bytes,
            path: ["parentProject", "kind"],
            value: "client"
        )
        #expect(Self.decodeFailure(changedParentKind) == .parentProjectMismatch)
        let changedParentID = try Self.mutate(
            bytes,
            path: ["parentProject", "id"],
            value: "project-other"
        )
        #expect(Self.decodeFailure(changedParentID) == .parentProjectMismatch)
        let changedFingerprint = try Self.mutate(
            bytes,
            path: ["fingerprint"],
            value: String(repeating: "0", count: 64)
        )
        #expect(Self.decodeFailure(changedFingerprint) == .fingerprintMismatch)
        #expect(Self.creationFailure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(ProjectNoteCreationFailure, String)] = [
            (.invalidClientCreatedAt, "project_note_creation_client_time_invalid"),
            (.draftAccountMismatch, "project_note_creation_account_mismatch"),
            (.draftActorMismatch, "project_note_creation_actor_mismatch"),
            (.draftContractMismatch, "project_note_creation_contract_mismatch"),
            (.draftPayloadMismatch, "project_note_creation_payload_mismatch"),
            (.unexpectedPreconditions, "project_note_creation_preconditions_unexpected"),
            (.parentProjectMismatch, "project_note_creation_parent_project_mismatch"),
            (.fingerprintMismatch, "project_note_creation_fingerprint_mismatch"),
            (.receiptMismatch, "project_note_creation_receipt_mismatch"),
            (.localAcceptanceFailed, "project_note_creation_local_acceptance_failed"),
            (.invalidEncodedCommand, "project_note_creation_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The create port reuses shared queued receipt and replay semantics")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command()
        let adapter = JournalProjectNoteCreationAdapter(acceptedAt: Self.t1)
        let first = try await adapter.add(command)
        let replay = try await adapter.add(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let changed = try Self.command(
            operationID: command.envelope.operationId.rawValue,
            text: "Changed intent"
        )
        do {
            _ = try await adapter.add(changed)
            Issue.record("A reused OperationID accepted changed Project-note intent")
        } catch let failure as OperationContractFailure {
            #expect(failure == .payloadMismatch(command.envelope.operationId))
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingProjectNoteCreationAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.add(command)
        } catch let failure as ProjectNoteCreationFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_700_000)
    private static let t1 = Date(timeIntervalSince1970: 1_800_700_001)

    private static func draft(
        capturedAt: Date = t0,
        projectID: String = "project-note-create-test",
        noteID: String = "note-entry",
        text: String = "Gate code is 4816",
        requestedSource: String = "text"
    ) throws -> ProjectNoteCreationDraft {
        try ProjectNoteCreationDraft(
            accountId: AccountID(validating: "account-note-create-test"),
            actorPrincipalId: PrincipalID(validating: "principal-note-create-test"),
            operationContractVersion: OperationContractVersion(
                validating: "project-note-add-v1"
            ),
            projectId: ProjectID(validating: projectID),
            noteId: ProjectNoteID(validating: noteID),
            text: ProjectNoteText(validating: text),
            requestedSource: ProjectNoteSource(validating: requestedSource),
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-add-note-entry",
        projectID: String = "project-note-create-test",
        noteID: String = "note-entry",
        text: String = "Gate code is 4816",
        requestedSource: String = "text"
    ) throws -> AddProjectNoteCommand {
        try AddProjectNoteCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(
                projectID: projectID,
                noteID: noteID,
                text: text,
                requestedSource: requestedSource
            )
        )
    }

    private static func creationFailure<T>(
        _ operation: () throws -> T
    ) -> ProjectNoteCreationFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ProjectNoteCreationFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func noteDataFailure<T>(
        _ operation: () throws -> T
    ) -> ProjectNoteDataFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ProjectNoteDataFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure(_ data: Data) -> ProjectNoteCreationFailure? {
        creationFailure {
            try OperationContractCodec.decode(AddProjectNoteCommand.self, from: data)
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectNoteCreationFailure.invalidEncodedCommand
        }
        return object
    }

    private static func mutate(_ data: Data, path: [String], value: Any) throws -> Data {
        var object = try jsonObject(data)
        try Self.set(value, at: path[...], in: &object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func set(
        _ value: Any,
        at path: ArraySlice<String>,
        in object: inout [String: Any]
    ) throws {
        guard let key = path.first else {
            throw ProjectNoteCreationFailure.invalidEncodedCommand
        }
        if path.count == 1 {
            object[key] = value
            return
        }
        guard var child = object[key] as? [String: Any] else {
            throw ProjectNoteCreationFailure.invalidEncodedCommand
        }
        try set(value, at: path.dropFirst(), in: &child)
        object[key] = child
    }
}

private actor JournalProjectNoteCreationAdapter: ProjectNoteCreating {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func add(_ command: AddProjectNoteCommand) async throws -> OperationReceipt {
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

private struct FailingProjectNoteCreationAdapter: ProjectNoteCreating {
    func add(_ command: AddProjectNoteCommand) async throws -> OperationReceipt {
        throw ProjectNoteCreationFailure.localAcceptanceFailed
    }
}
