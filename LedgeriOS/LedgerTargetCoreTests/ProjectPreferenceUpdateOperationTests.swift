import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Preference Update Operation Contracts")
struct ProjectPreferenceUpdateOperationTests {
    @Test("Absent and revisioned preferences carry one complete ordered replacement")
    func exactScopePayloadAndPreconditions() throws {
        let absent = try Self.command(expectedState: .notStored)

        #expect(absent.draft.accountId.rawValue == "account-preference-update-test")
        #expect(absent.draft.actorPrincipalId.rawValue == "principal-preference-update-test")
        #expect(absent.draft.projectId.rawValue == "project-north")
        #expect(absent.draft.pinnedCategoryIds.map(\.rawValue) == [
            "category-lighting", "category-furnishings"
        ])
        #expect(absent.envelope.payload.projectId == absent.draft.projectId)
        #expect(absent.envelope.payload.pinnedCategoryIds == absent.draft.pinnedCategoryIds)
        #expect(absent.subject.kind == .referenceData)
        #expect(absent.subject.id.rawValue.hasPrefix("project_preference:"))
        #expect(absent.subject.id.rawValue != absent.draft.projectId.rawValue)
        #expect(absent.envelope.preconditions == [
            .expectedState(
                subject: absent.subject,
                state: try EntityStateCode(validating: "not_stored")
            )
        ])

        let revisioned = try Self.command(
            operationID: "operation-update-project-pins-revisioned",
            expectedState: .revision(23)
        )
        #expect(revisioned.subject == absent.subject)
        #expect(revisioned.envelope.preconditions == [
            .expectedRevision(subject: revisioned.subject, revision: 23)
        ])
        let otherAccount = try Self.command(
            operationID: "operation-update-project-pins-other-account",
            accountID: "account-other",
            expectedState: .notStored
        )
        let otherPrincipal = try Self.command(
            operationID: "operation-update-project-pins-other-principal",
            principalID: "principal-other",
            expectedState: .notStored
        )
        #expect(otherAccount.subject != absent.subject)
        #expect(otherPrincipal.subject != absent.subject)

        let bytes = try OperationContractCodec.encode(absent)
        #expect(Set(try Self.jsonObject(bytes).keys) == Set([
            "draft", "envelope", "fingerprint", "subject"
        ]))
        #expect(try Self.objectKeys(bytes, path: ["envelope", "payload"]) == Set([
            "projectId", "pinnedCategoryIds"
        ]))

        let encodedText = String(decoding: bytes, as: UTF8.self).lowercased()
        for forbidden in [
            "categoryname", "displayname", "budgetcents", "allocation", "spend",
            "paid", "unpaid", "amount", "clientid", "userid", "userpath",
            "createcategory", "archivecategory", "field", "collection", "sql"
        ] {
            #expect(!encodedText.contains(forbidden))
        }
    }

    @Test("Absent, revisioned, reordered, and stored-empty intent survives restart")
    func canonicalRestartPreservesExactIntent() throws {
        let commands = try [
            Self.command(expectedState: .notStored),
            Self.command(
                operationID: "operation-update-project-pins-reordered",
                pins: ["category-furnishings", "category-lighting"],
                expectedState: .revision(23)
            ),
            Self.command(
                operationID: "operation-update-project-pins-empty",
                pins: [],
                expectedState: .revision(24)
            )
        ]

        for command in commands {
            let bytes = try OperationContractCodec.encode(command)
            let restored = try OperationContractCodec.decode(
                UpdateProjectPreferencesCommand.self,
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

        #expect(commands[0].fingerprint != commands[1].fingerprint)
        #expect(commands[1].fingerprint != commands[2].fingerprint)

        let emptyAbsent = try Self.command(
            operationID: "operation-update-project-pins-empty-absent",
            pins: [],
            expectedState: .notStored
        )
        #expect(emptyAbsent.fingerprint != commands[2].fingerprint)
        #expect(emptyAbsent.draft.expectedState == .notStored)
        #expect(commands[2].draft.expectedState == .revision(24))
    }

    @Test("Duplicate, rebound, and tampered preference intent fails atomically")
    func invalidAndTamperedEvidenceFailsClosed() throws {
        #expect(Self.updateFailure {
            try Self.draft(pins: ["category-lighting", "category-lighting"])
        } == .duplicatePinnedCategoryIdentity)
        #expect(Self.updateFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        } == .invalidCapturedAt)
        #expect(Self.updateFailure {
            try Self.draft(capturedAt: Date(timeIntervalSinceReferenceDate: .nan))
        } == .invalidCapturedAt)

        let command = try Self.command(expectedState: .revision(23))
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
            value: "project-preference-update-v2"
        )) == .draftContractMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "payload", "projectId"],
            value: "project-other"
        )) == .draftPayloadMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "payload", "pinnedCategoryIds"],
            value: ["category-furnishings", "category-lighting"]
        )) == .draftPayloadMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["draft", "pinnedCategoryIds"],
            value: ["category-furnishings", "category-lighting"]
        )) == .draftPayloadMismatch)

        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "subject", "id"],
            value: "project_preference:" + String(repeating: "0", count: 64)
        )) == .expectedStatePreconditionMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "preconditions", "0", "expectedRevision", "revision"],
            value: 24
        )) == .expectedStatePreconditionMismatch)
        #expect(Self.decodeFailure(try Self.mutate(
            bytes,
            path: ["envelope", "preconditions"],
            value: []
        )) == .expectedStatePreconditionMismatch)
        #expect(Self.decodeFailure(try Self.duplicateFirstPrecondition(bytes)) ==
            .expectedStatePreconditionMismatch)

        let absent = try Self.command(
            operationID: "operation-update-project-pins-absent-tamper",
            expectedState: .notStored
        )
        #expect(Self.decodeFailure(try Self.mutate(
            OperationContractCodec.encode(absent),
            path: ["envelope", "preconditions", "0", "expectedState", "state"],
            value: "stored"
        )) == .expectedStatePreconditionMismatch)

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
        #expect(Self.updateFailure {
            try command.validate(OperationReceipt(
                operationId: OperationID(validating: "operation-other"),
                localState: .queued
            ))
        } == .receiptMismatch)

        #expect(Self.updateFailure {
            try OperationContractCodec.decode(
                ProjectPreferenceUpdateDraft.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedDraft)
        #expect(Self.decodeFailure(Data("{}".utf8)) == .invalidEncodedCommand)

        let diagnostics: [(ProjectPreferenceUpdateFailure, String)] = [
            (.invalidCapturedAt, "project_preference_update_captured_at_invalid"),
            (.duplicatePinnedCategoryIdentity, "project_preference_update_pinned_category_duplicate"),
            (.draftAccountMismatch, "project_preference_update_account_mismatch"),
            (.draftActorMismatch, "project_preference_update_actor_mismatch"),
            (.draftContractMismatch, "project_preference_update_contract_mismatch"),
            (.draftPayloadMismatch, "project_preference_update_payload_mismatch"),
            (.expectedStatePreconditionMismatch, "project_preference_update_precondition_mismatch"),
            (.subjectMismatch, "project_preference_update_subject_mismatch"),
            (.fingerprintMismatch, "project_preference_update_fingerprint_mismatch"),
            (.receiptMismatch, "project_preference_update_receipt_mismatch"),
            (.localAcceptanceFailed, "project_preference_update_local_acceptance_failed"),
            (.invalidEncodedDraft, "project_preference_update_draft_encoding_invalid"),
            (.invalidEncodedCommand, "project_preference_update_command_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The preference update port reuses shared queued replay semantics")
    func referencePortReusesSharedOperationLifecycle() async throws {
        let command = try Self.command(expectedState: .notStored)
        let adapter = JournalProjectPreferenceUpdateAdapter(acceptedAt: Self.t1)
        let first = try await adapter.updateProjectPreferences(command)
        let replay = try await adapter.updateProjectPreferences(command)

        #expect(first == replay)
        #expect(first.operationId == command.envelope.operationId)
        #expect(first.localState == .queued)
        #expect(await adapter.snapshotCount == 1)
        #expect(await adapter.fingerprint(for: first.operationId) == command.fingerprint)

        let variants = try [
            Self.command(
                operationID: command.envelope.operationId.rawValue,
                projectID: "project-south",
                expectedState: .notStored
            ),
            Self.command(
                operationID: command.envelope.operationId.rawValue,
                pins: ["category-furnishings", "category-lighting"],
                expectedState: .notStored
            ),
            Self.command(
                operationID: command.envelope.operationId.rawValue,
                expectedState: .revision(23)
            )
        ]
        for variant in variants {
            do {
                _ = try await adapter.updateProjectPreferences(variant)
                Issue.record("A reused OperationID accepted changed preference intent")
            } catch let failure as OperationContractFailure {
                #expect(failure == .payloadMismatch(command.envelope.operationId))
            }
        }
        #expect(await adapter.snapshotCount == 1)

        let failing = FailingProjectPreferenceUpdateAdapter()
        var falseSuccess: OperationReceipt?
        do {
            falseSuccess = try await failing.updateProjectPreferences(command)
        } catch let failure as ProjectPreferenceUpdateFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(falseSuccess == nil)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_100_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_100_001)

    private static func draft(
        accountID: String = "account-preference-update-test",
        principalID: String = "principal-preference-update-test",
        projectID: String = "project-north",
        pins: [String] = ["category-lighting", "category-furnishings"],
        expectedState: ProjectPreferenceExpectedState = .notStored,
        capturedAt: Date = t0
    ) throws -> ProjectPreferenceUpdateDraft {
        try ProjectPreferenceUpdateDraft(
            accountId: AccountID(validating: accountID),
            actorPrincipalId: PrincipalID(validating: principalID),
            operationContractVersion: OperationContractVersion(
                validating: "project-preference-update-v1"
            ),
            projectId: ProjectID(validating: projectID),
            pinnedCategoryIds: try pins.map(BudgetCategoryID.init(validating:)),
            expectedState: expectedState,
            capturedAt: capturedAt
        )
    }

    private static func command(
        operationID: String = "operation-update-project-pins",
        accountID: String = "account-preference-update-test",
        principalID: String = "principal-preference-update-test",
        projectID: String = "project-north",
        pins: [String] = ["category-lighting", "category-furnishings"],
        expectedState: ProjectPreferenceExpectedState
    ) throws -> UpdateProjectPreferencesCommand {
        try UpdateProjectPreferencesCommand(
            operationId: OperationID(validating: operationID),
            draft: draft(
                accountID: accountID,
                principalID: principalID,
                projectID: projectID,
                pins: pins,
                expectedState: expectedState
            )
        )
    }

    private static func updateFailure<T>(
        _ operation: () throws -> T
    ) -> ProjectPreferenceUpdateFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ProjectPreferenceUpdateFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func decodeFailure(_ data: Data) -> ProjectPreferenceUpdateFailure? {
        updateFailure {
            try OperationContractCodec.decode(
                UpdateProjectPreferencesCommand.self,
                from: data
            )
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectPreferenceUpdateFailure.invalidEncodedCommand
        }
        return object
    }

    private static func objectKeys(_ data: Data, path: [String]) throws -> Set<String> {
        var value: Any = try jsonObject(data)
        for key in path {
            guard let object = value as? [String: Any], let next = object[key] else {
                throw ProjectPreferenceUpdateFailure.invalidEncodedCommand
            }
            value = next
        }
        guard let object = value as? [String: Any] else {
            throw ProjectPreferenceUpdateFailure.invalidEncodedCommand
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
            throw ProjectPreferenceUpdateFailure.invalidEncodedCommand
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
            throw ProjectPreferenceUpdateFailure.invalidEncodedCommand
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
                throw ProjectPreferenceUpdateFailure.invalidEncodedCommand
            }
            object[key] = array
            return
        }
        throw ProjectPreferenceUpdateFailure.invalidEncodedCommand
    }
}

private actor JournalProjectPreferenceUpdateAdapter: ProjectPreferenceUpdating {
    private var journal = OperationJournal()
    private let acceptedAt: Date

    init(acceptedAt: Date) {
        self.acceptedAt = acceptedAt
    }

    func updateProjectPreferences(
        _ command: UpdateProjectPreferencesCommand
    ) async throws -> OperationReceipt {
        let receipt = try journal.accept(
            command.envelope,
            at: acceptedAt
        )
        return try command.validate(receipt)
    }

    var snapshotCount: Int {
        journal.snapshots.count
    }

    func fingerprint(for operationId: OperationID) -> OperationFingerprint? {
        journal.snapshot(for: operationId)?.fingerprint
    }
}

private struct FailingProjectPreferenceUpdateAdapter: ProjectPreferenceUpdating {
    func updateProjectPreferences(
        _ command: UpdateProjectPreferencesCommand
    ) async throws -> OperationReceipt {
        throw ProjectPreferenceUpdateFailure.localAcceptanceFailed
    }
}
