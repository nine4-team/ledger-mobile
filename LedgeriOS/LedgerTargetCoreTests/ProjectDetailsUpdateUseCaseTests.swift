import Foundation
import Testing
import LedgerTargetCore

@Suite("Project Details Update Use Case Contracts")
struct ProjectDetailsUpdateUseCaseTests {
    @Test("Public transient input preserves exact raw bytes and revision boundaries")
    func publicTransientInputShape() throws {
        Self.requireSendable(ProjectDetailsUpdateFormInput.self)
        let raw = "  Café 👩🏽‍💻\nsecond line  "
        let zero = try Self.input(revision: 0, description: raw)
        let maximum = try Self.input(
            projectID: "project-maximum-revision",
            revision: UInt64.max,
            description: nil
        )

        #expect(zero.rawDescription == raw)
        #expect(Data(try #require(zero.rawDescription).utf8) == Data(raw.utf8))
        #expect(zero.expectedRevision == ExpectedProjectRevision(0))
        #expect(maximum.expectedRevision == ExpectedProjectRevision(UInt64.max))
        #expect(zero != maximum)
        #expect(!Self.isEncodable(zero))
        #expect(!Self.isDecodableType(ProjectDetailsUpdateFormInput.self))
        #expect(Set(Mirror(reflecting: zero).children.compactMap(\.label)) == [
            "accountId", "projectId", "expectedRevision", "rawDescription"
        ])
    }

    @Test("Clear, trim, Unicode, and long text use canonical replacement")
    func canonicalDescriptionReplacement() async throws {
        let nilClear = try await Self.recordedCommand(description: nil)
        let emptyClear = try await Self.recordedCommand(description: "")
        let whitespaceClear = try await Self.recordedCommand(description: " \n\t ")
        #expect(nilClear.draft.descriptionReplacement.value == nil)
        #expect(nilClear == emptyClear)
        #expect(nilClear == whitespaceClear)
        #expect(nilClear.fingerprint == emptyClear.fingerprint)
        #expect(nilClear.fingerprint == whitespaceClear.fingerprint)

        let interior = "Café 👩🏽‍💻 \n second\tline"
        let padded = try await Self.recordedCommand(
            description: " \t\(interior)\n "
        )
        #expect(padded.draft.descriptionReplacement.value == interior)
        #expect(padded.envelope.payload.descriptionReplacement.value == interior)

        let long = String(repeating: "界🙂é", count: 1_200)
        #expect(long.utf8.count > 8 * 1_024)
        let longCommand = try await Self.recordedCommand(
            description: "\n \(long) \t"
        )
        #expect(longCommand.draft.descriptionReplacement.value == long)
        #expect(longCommand.envelope.payload.descriptionReplacement.value == long)
    }

    @Test("Every local state returns in one exact validated receipt")
    func exactReceiptStatesAndCommand() async throws {
        for state in LocalOperationState.allCases {
            let operationID = try OperationID(
                validating: "operation-project-details-\(state.rawValue)"
            )
            let updater = RecordingProjectDetailsUpdater(response: .matching(state))
            let receipt = try await ProjectDetailsUpdateUseCase(updater: updater).execute(
                input: try Self.input(
                    accountID: "account-exact",
                    projectID: "project-exact",
                    revision: 73,
                    description: "  Site visit \n notes  "
                ),
                operationId: operationID,
                actorPrincipalId: PrincipalID(validating: "principal-exact"),
                operationContractVersion: OperationContractVersion(
                    validating: "project-details-v7"
                ),
                capturedAt: Self.t0
            )

            #expect(receipt.operationId == operationID)
            #expect(receipt.localState == state)
            let commands = await updater.recordedCommands()
            #expect(commands.count == 1)
            let command = try #require(commands.first)
            try Self.expectCommand(
                command,
                accountID: "account-exact",
                projectID: "project-exact",
                revision: 73,
                description: "Site visit \n notes",
                operationID: operationID.rawValue,
                actorID: "principal-exact",
                contractVersion: "project-details-v7",
                capturedAt: Self.t0
            )
            #expect(try command.validate(receipt) == receipt)
        }
    }

    @Test("Every caller field changes only its literal encoded owners")
    func reciprocalEncodedLeafOwnership() async throws {
        let baseline = try await Self.recordedCommand()
        let variants: [(UpdateProjectDetailsCommand, Set<String>)] = [
            (try await Self.recordedCommand(accountID: "account-other"), [
                "draft.accountId", "envelope.accountId", "fingerprint"
            ]),
            (try await Self.recordedCommand(projectID: "project-other"), [
                "draft.projectId", "envelope.payload.projectId",
                "envelope.preconditions.0.expectedRevision.subject.id",
                "subject.id", "fingerprint"
            ]),
            (try await Self.recordedCommand(revision: UInt64.max), [
                "draft.expectedRevision.rawValue",
                "envelope.preconditions.0.expectedRevision.revision", "fingerprint"
            ]),
            (try await Self.recordedCommand(description: "Changed description"), [
                "draft.descriptionReplacement.value",
                "envelope.payload.descriptionReplacement.value", "fingerprint"
            ]),
            (try await Self.recordedCommand(operationID: "operation-other"), [
                "envelope.operationId", "fingerprint"
            ]),
            (try await Self.recordedCommand(actorID: "principal-other"), [
                "draft.actorPrincipalId", "envelope.actorPrincipalId", "fingerprint"
            ]),
            (try await Self.recordedCommand(contractVersion: "project-details-v2"), [
                "draft.operationContractVersion", "envelope.contractVersion", "fingerprint"
            ]),
            (try await Self.recordedCommand(capturedAt: Self.t1), [
                "draft.capturedAt", "envelope.clientCreatedAt", "fingerprint"
            ])
        ]

        #expect(variants.count == 8)
        for (variant, expectedDelta) in variants {
            #expect(variant != baseline)
            #expect(try Self.fieldDelta(from: baseline, to: variant) == expectedDelta)
        }

        let zeroRevision = try await Self.recordedCommand(revision: 0)
        #expect(zeroRevision.draft.expectedRevision == ExpectedProjectRevision(0))
        #expect(zeroRevision.envelope.preconditions == [
            .expectedRevision(subject: zeroRevision.subject, revision: 0)
        ])
        #expect(try Self.fieldDelta(from: baseline, to: zeroRevision) == [
            "draft.expectedRevision.rawValue",
            "envelope.preconditions.0.expectedRevision.revision", "fingerprint"
        ])

        let equivalent = try await Self.recordedCommand(
            description: " \nProject description\t "
        )
        #expect(equivalent == baseline)
        #expect(equivalent.fingerprint == baseline.fingerprint)
        #expect(try Self.fieldDelta(from: baseline, to: equivalent).isEmpty)
    }

    @Test("Construction fails before dispatch and receipt mismatch follows one call")
    func zeroAndOneCallFailureBoundaries() async throws {
        for value in [Double.infinity, Double.nan] {
            let updater = RecordingProjectDetailsUpdater(response: .matching(.queued))
            do {
                _ = try await ProjectDetailsUpdateUseCase(updater: updater).execute(
                    input: try Self.input(),
                    operationId: OperationID(validating: "operation-invalid-time"),
                    actorPrincipalId: PrincipalID(validating: "principal-test"),
                    operationContractVersion: OperationContractVersion(
                        validating: "project-details-v1"
                    ),
                    capturedAt: Date(timeIntervalSinceReferenceDate: value)
                )
                Issue.record("Nonfinite capture time returned a receipt")
            } catch let failure as ProjectDetailsUpdateFailure {
                #expect(failure == .invalidCapturedAt)
            }
            #expect(await updater.recordedCommands().isEmpty)
        }

        let mismatch = RecordingProjectDetailsUpdater(
            response: .mismatched(
                try OperationID(validating: "operation-wrong-receipt")
            )
        )
        do {
            _ = try await Self.execute(
                using: mismatch,
                operationID: "operation-expected-receipt"
            )
            Issue.record("Mismatched receipt returned")
        } catch let failure as ProjectDetailsUpdateFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await mismatch.recordedCommands().count == 1)
    }

    @Test("All typed failures, cancellation, and unknown errors stay bounded")
    func exhaustiveFailureMapping() async throws {
        let failures: [ProjectDetailsUpdateFailure] = [
            .invalidCapturedAt,
            .draftAccountMismatch,
            .draftActorMismatch,
            .draftContractMismatch,
            .draftPayloadMismatch,
            .revisionPreconditionMismatch,
            .subjectMismatch,
            .fingerprintMismatch,
            .receiptMismatch,
            .localAcceptanceFailed,
            .invalidEncodedDescriptionReplacement,
            .invalidEncodedDraft,
            .invalidEncodedCommand
        ]
        #expect(failures.count == 13)
        #expect(Set(failures.map(\.diagnosticCode)).count == 13)
        for failure in failures {
            let updater = RecordingProjectDetailsUpdater(response: .typedFailure(failure))
            do {
                _ = try await Self.execute(
                    using: updater,
                    operationID: "operation-\(failure.diagnosticCode)"
                )
                Issue.record("Typed failure returned a receipt")
            } catch let received as ProjectDetailsUpdateFailure {
                #expect(received == failure)
            }
            #expect(await updater.recordedCommands().count == 1)
        }

        let cancelled = RecordingProjectDetailsUpdater(response: .cancelled)
        do {
            _ = try await Self.execute(using: cancelled, operationID: "operation-cancelled")
            Issue.record("Cancellation returned a receipt")
        } catch is CancellationError {
            // Expected structured-concurrency control flow.
        } catch {
            Issue.record("Cancellation was rewritten as \(error)")
        }
        #expect(await cancelled.recordedCommands().count == 1)

        let raw = RecordingProjectDetailsUpdater(response: .rawFailure)
        do {
            _ = try await Self.execute(using: raw, operationID: "operation-raw")
            Issue.record("Unknown port error returned a receipt")
        } catch let failure as ProjectDetailsUpdateFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(await raw.recordedCommands().count == 1)
    }

    @Test("Diagnostics and encoded topology stay description-only")
    func diagnosticsTopologyAndExclusions() async throws {
        let diagnostics: [(ProjectDetailsUpdateFailure, String)] = [
            (.invalidCapturedAt, "project_details_update_captured_at_invalid"),
            (.draftAccountMismatch, "project_details_update_account_mismatch"),
            (.draftActorMismatch, "project_details_update_actor_mismatch"),
            (.draftContractMismatch, "project_details_update_contract_mismatch"),
            (.draftPayloadMismatch, "project_details_update_payload_mismatch"),
            (.revisionPreconditionMismatch,
             "project_details_update_revision_precondition_mismatch"),
            (.subjectMismatch, "project_details_update_subject_mismatch"),
            (.fingerprintMismatch, "project_details_update_fingerprint_mismatch"),
            (.receiptMismatch, "project_details_update_receipt_mismatch"),
            (.localAcceptanceFailed, "project_details_update_local_acceptance_failed"),
            (.invalidEncodedDescriptionReplacement,
             "project_details_update_description_replacement_encoding_invalid"),
            (.invalidEncodedDraft, "project_details_update_draft_encoding_invalid"),
            (.invalidEncodedCommand, "project_details_update_command_encoding_invalid")
        ]
        #expect(diagnostics.count == 13)
        for (failure, expected) in diagnostics {
            #expect(failure.diagnosticCode == expected)
            for secret in [
                "account-project-details", "project-residence",
                "Project description", "operation-project-details",
                "principal-project-details", "raw-provider-detail"
            ] {
                #expect(!failure.diagnosticCode.contains(secret))
            }
        }

        let command = try await Self.recordedCommand()
        let encoded = try OperationContractCodec.encode(command)
        let root = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(Set(root.keys) == ["draft", "envelope", "subject", "fingerprint"])

        let draft = try #require(root["draft"] as? [String: Any])
        #expect(Set(draft.keys) == [
            "accountId", "actorPrincipalId", "operationContractVersion",
            "projectId", "descriptionReplacement", "expectedRevision", "capturedAt"
        ])
        let draftReplacement = try #require(
            draft["descriptionReplacement"] as? [String: Any]
        )
        #expect(Set(draftReplacement.keys) == ["value"])
        let expectedRevision = try #require(draft["expectedRevision"] as? [String: Any])
        #expect(Set(expectedRevision.keys) == ["rawValue"])

        let envelope = try #require(root["envelope"] as? [String: Any])
        #expect(Set(envelope.keys) == [
            "operationId", "contractVersion", "accountId", "actorPrincipalId",
            "clientCreatedAt", "payload", "preconditions"
        ])
        let payload = try #require(envelope["payload"] as? [String: Any])
        #expect(Set(payload.keys) == ["projectId", "descriptionReplacement"])
        let payloadReplacement = try #require(
            payload["descriptionReplacement"] as? [String: Any]
        )
        #expect(Set(payloadReplacement.keys) == ["value"])
        let preconditions = try #require(envelope["preconditions"] as? [[String: Any]])
        #expect(preconditions.count == 1)
        let precondition = try #require(preconditions.first)
        #expect(Set(precondition.keys) == ["expectedRevision"])
        let revisionBody = try #require(
            precondition["expectedRevision"] as? [String: Any]
        )
        #expect(Set(revisionBody.keys) == ["subject", "revision"])
        let revisionSubject = try #require(revisionBody["subject"] as? [String: Any])
        #expect(Set(revisionSubject.keys) == ["kind", "id"])

        let subject = try #require(root["subject"] as? [String: Any])
        #expect(Set(subject.keys) == ["kind", "id"])
        #expect((root["fingerprint"] as? String)?.utf8.count == 64)

        var keys = Set<String>()
        Self.collectKeys(root, into: &keys)
        let forbiddenKeys: Set<String> = [
            "name", "displayName", "clientId", "clientName", "categoryId",
            "categoryAllocations", "allocation", "budget", "attachment",
            "media", "image", "lifecycle", "archived", "deleted", "child",
            "item", "transaction", "invoice", "accounting", "history",
            "fields", "updates", "provider", "credential", "token", "secret"
        ]
        #expect(keys.isDisjoint(with: forbiddenKeys))

        let text = String(decoding: encoded, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "https://",
            "file://", "bearer", "raw-provider-detail", "production"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_801_077_000)
    private static let t1 = Date(timeIntervalSince1970: 1_801_077_001)

    private static func requireSendable<T: Sendable>(_ type: T.Type) {}

    private static func isEncodable(_ value: Any) -> Bool {
        value is any Encodable
    }

    private static func isDecodableType(_ type: Any.Type) -> Bool {
        type is any Decodable.Type
    }

    private static func input(
        accountID: String = "account-project-details",
        projectID: String = "project-residence",
        revision: UInt64 = 42,
        description: String? = "Project description"
    ) throws -> ProjectDetailsUpdateFormInput {
        ProjectDetailsUpdateFormInput(
            accountId: try AccountID(validating: accountID),
            projectId: try ProjectID(validating: projectID),
            expectedRevision: ExpectedProjectRevision(revision),
            rawDescription: description
        )
    }

    private static func execute(
        using updater: RecordingProjectDetailsUpdater,
        operationID: String
    ) async throws -> OperationReceipt {
        try await ProjectDetailsUpdateUseCase(updater: updater).execute(
            input: input(),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: "principal-project-details"),
            operationContractVersion: OperationContractVersion(
                validating: "project-details-v1"
            ),
            capturedAt: t0
        )
    }

    private static func recordedCommand(
        accountID: String = "account-project-details",
        projectID: String = "project-residence",
        revision: UInt64 = 42,
        description: String? = "Project description",
        operationID: String = "operation-project-details",
        actorID: String = "principal-project-details",
        contractVersion: String = "project-details-v1",
        capturedAt: Date = t0
    ) async throws -> UpdateProjectDetailsCommand {
        let updater = RecordingProjectDetailsUpdater(response: .matching(.queued))
        _ = try await ProjectDetailsUpdateUseCase(updater: updater).execute(
            input: input(
                accountID: accountID,
                projectID: projectID,
                revision: revision,
                description: description
            ),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: actorID),
            operationContractVersion: OperationContractVersion(
                validating: contractVersion
            ),
            capturedAt: capturedAt
        )
        let commands = await updater.recordedCommands()
        #expect(commands.count == 1)
        return try #require(commands.first)
    }

    private static func expectCommand(
        _ command: UpdateProjectDetailsCommand,
        accountID: String,
        projectID: String,
        revision: UInt64,
        description: String?,
        operationID: String,
        actorID: String,
        contractVersion: String,
        capturedAt: Date
    ) throws {
        #expect(command.draft.accountId == (try AccountID(validating: accountID)))
        #expect(command.draft.projectId == (try ProjectID(validating: projectID)))
        #expect(command.draft.expectedRevision == ExpectedProjectRevision(revision))
        #expect(command.draft.descriptionReplacement.value == description)
        #expect(command.draft.actorPrincipalId == (try PrincipalID(validating: actorID)))
        #expect(
            command.draft.operationContractVersion ==
                (try OperationContractVersion(validating: contractVersion))
        )
        #expect(command.draft.capturedAt == capturedAt)
        #expect(command.envelope.operationId == (try OperationID(validating: operationID)))
        #expect(command.envelope.accountId == command.draft.accountId)
        #expect(command.envelope.actorPrincipalId == command.draft.actorPrincipalId)
        #expect(command.envelope.contractVersion == command.draft.operationContractVersion)
        #expect(command.envelope.clientCreatedAt == command.draft.capturedAt)
        #expect(command.envelope.payload.projectId == command.draft.projectId)
        #expect(
            command.envelope.payload.descriptionReplacement ==
                command.draft.descriptionReplacement
        )
        #expect(command.envelope.preconditions == [
            .expectedRevision(subject: command.subject, revision: revision)
        ])
        #expect(command.subject.kind == .project)
        #expect(command.subject.id.rawValue == projectID)
        #expect(command.fingerprint == (try OperationFingerprint.make(for: command.envelope)))
    }

    private static func fieldDelta(
        from baseline: UpdateProjectDetailsCommand,
        to variant: UpdateProjectDetailsCommand
    ) throws -> Set<String> {
        let baselineObject = try JSONSerialization.jsonObject(
            with: OperationContractCodec.encode(baseline)
        )
        let variantObject = try JSONSerialization.jsonObject(
            with: OperationContractCodec.encode(variant)
        )
        var baselineFields: [String: String] = [:]
        var variantFields: [String: String] = [:]
        flattenJSON(baselineObject, path: "", into: &baselineFields)
        flattenJSON(variantObject, path: "", into: &variantFields)
        return Set(baselineFields.keys).union(variantFields.keys).filter {
            baselineFields[$0] != variantFields[$0]
        }
    }

    private static func flattenJSON(
        _ value: Any,
        path: String,
        into fields: inout [String: String]
    ) {
        if let object = value as? [String: Any] {
            for key in object.keys.sorted() {
                flattenJSON(
                    object[key]!,
                    path: path.isEmpty ? key : "\(path).\(key)",
                    into: &fields
                )
            }
        } else if let array = value as? [Any] {
            for (index, element) in array.enumerated() {
                flattenJSON(
                    element,
                    path: path.isEmpty ? String(index) : "\(path).\(index)",
                    into: &fields
                )
            }
        } else if let string = value as? String {
            fields[path] = "string:\(string)"
        } else if let number = value as? NSNumber {
            fields[path] = "number:\(number.stringValue)"
        } else {
            fields[path] = String(describing: value)
        }
    }

    private static func collectKeys(_ value: Any, into keys: inout Set<String>) {
        if let object = value as? [String: Any] {
            for (key, child) in object {
                keys.insert(key)
                collectKeys(child, into: &keys)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectKeys(child, into: &keys)
            }
        }
    }
}

private enum ProjectDetailsUpdaterResponse: Sendable {
    case matching(LocalOperationState)
    case mismatched(OperationID)
    case typedFailure(ProjectDetailsUpdateFailure)
    case rawFailure
    case cancelled
}

private actor RecordingProjectDetailsUpdater: ProjectDetailsUpdating {
    private let response: ProjectDetailsUpdaterResponse
    private var commands: [UpdateProjectDetailsCommand] = []

    init(response: ProjectDetailsUpdaterResponse) {
        self.response = response
    }

    func updateDetails(
        _ command: UpdateProjectDetailsCommand
    ) async throws -> OperationReceipt {
        commands.append(command)
        switch response {
        case .matching(let state):
            return OperationReceipt(
                operationId: command.envelope.operationId,
                localState: state
            )
        case .mismatched(let operationID):
            return OperationReceipt(operationId: operationID, localState: .queued)
        case .typedFailure(let failure):
            throw failure
        case .rawFailure:
            throw RawProjectDetailsPortFailure.transport("raw-provider-detail")
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedCommands() -> [UpdateProjectDetailsCommand] {
        commands
    }
}

private enum RawProjectDetailsPortFailure: Error {
    case transport(String)
}
