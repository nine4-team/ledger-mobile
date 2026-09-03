import Foundation
import Testing
import LedgerTargetCore

@Suite("Project Rename Use Case Contracts")
struct ProjectRenameUseCaseTests {
    @Test("Public transient intent has the exact typed four-field shape")
    func publicTransientIntentShape() throws {
        Self.requireEquatableAndSendable(ProjectRenameIntent.self)
        let zero = try Self.intent(revision: 0)
        let maximum = try Self.intent(
            projectID: "project-maximum-revision",
            revision: UInt64.max,
            displayName: "Maximum revision project"
        )

        #expect(zero.expectedRevision == ExpectedProjectRevision(0))
        #expect(maximum.expectedRevision == ExpectedProjectRevision(UInt64.max))
        #expect(zero != maximum)
        #expect(!Self.isEncodable(zero))
        #expect(!Self.isDecodableType(ProjectRenameIntent.self))
        #expect(Set(Mirror(reflecting: zero).children.compactMap(\.label)) == [
            "accountId", "projectId", "expectedRevision", "newDisplayName"
        ])
        #expect(
            Mirror(reflecting: zero).children.first { $0.label == "newDisplayName" }?.value
                is ProjectDisplayName
        )
    }

    @Test("Validated display-name bytes reach draft and payload unchanged")
    func exactDisplayNameBytes() async throws {
        let whitespace = "  Café 👩🏽‍💻\nsecond\tline  "
        let whitespaceCommand = try await Self.recordedCommand(displayName: whitespace)
        #expect(whitespaceCommand.draft.newDisplayName.rawValue == whitespace)
        #expect(whitespaceCommand.envelope.payload.displayName.rawValue == whitespace)
        #expect(
            Data(whitespaceCommand.draft.newDisplayName.rawValue.utf8) ==
                Data(whitespace.utf8)
        )
        #expect(
            Data(whitespaceCommand.envelope.payload.displayName.rawValue.utf8) ==
                Data(whitespace.utf8)
        )

        let long = String(repeating: "界🙂é", count: 1_200)
        #expect(long.utf8.count > 8 * 1_024)
        let longCommand = try await Self.recordedCommand(displayName: long)
        #expect(longCommand.draft.newDisplayName.rawValue == long)
        #expect(longCommand.envelope.payload.displayName.rawValue == long)
        #expect(Data(longCommand.draft.newDisplayName.rawValue.utf8) == Data(long.utf8))
    }

    @Test("Every receipt state and revision boundary dispatches exactly once")
    func exactReceiptStatesAndRevisionBoundaries() async throws {
        for state in LocalOperationState.allCases {
            let operationID = try OperationID(
                validating: "operation-project-rename-\(state.rawValue)"
            )
            let renamer = RecordingProjectRenamer(response: .matching(state))
            let receipt = try await ProjectRenameUseCase(renamer: renamer).execute(
                input: try Self.intent(
                    accountID: "account-exact",
                    projectID: "project-exact",
                    revision: 73,
                    displayName: "Exact Project"
                ),
                operationId: operationID,
                actorPrincipalId: PrincipalID(validating: "principal-exact"),
                operationContractVersion: OperationContractVersion(
                    validating: "project-rename-v7"
                ),
                capturedAt: Self.t0
            )

            #expect(receipt == OperationReceipt(operationId: operationID, localState: state))
            let commands = await renamer.recordedCommands()
            #expect(commands.count == 1)
            let command = try #require(commands.first)
            #expect(command.draft.accountId.rawValue == "account-exact")
            #expect(command.draft.projectId.rawValue == "project-exact")
            #expect(command.draft.expectedRevision == ExpectedProjectRevision(73))
            #expect(command.draft.newDisplayName.rawValue == "Exact Project")
            #expect(command.envelope.preconditions == [
                .expectedRevision(subject: command.subject, revision: 73)
            ])
            #expect(try command.validate(receipt) == receipt)
        }

        for revision in [UInt64(0), UInt64.max] {
            let command = try await Self.recordedCommand(revision: revision)
            #expect(command.draft.expectedRevision == ExpectedProjectRevision(revision))
            #expect(command.envelope.preconditions == [
                .expectedRevision(subject: command.subject, revision: revision)
            ])
        }
    }

    @Test("Every caller field changes only its literal encoded owners")
    func reciprocalLiteralEncodedLeafOwnership() async throws {
        let baseline = try await Self.recordedCommand()
        #expect(try Self.flattenedFields(baseline) == [
            "draft.accountId": "string:account-project-rename-use-case",
            "draft.actorPrincipalId": "string:principal-project-rename-use-case",
            "draft.capturedAt": "number:1802100000000",
            "draft.expectedRevision.rawValue": "number:42",
            "draft.newDisplayName": "string:Project display name",
            "draft.operationContractVersion": "string:project-rename-use-case-v1",
            "draft.projectId": "string:project-residence",
            "envelope.accountId": "string:account-project-rename-use-case",
            "envelope.actorPrincipalId": "string:principal-project-rename-use-case",
            "envelope.clientCreatedAt": "number:1802100000000",
            "envelope.contractVersion": "string:project-rename-use-case-v1",
            "envelope.operationId": "string:operation-project-rename-use-case",
            "envelope.payload.displayName": "string:Project display name",
            "envelope.payload.projectId": "string:project-residence",
            "envelope.preconditions.0.expectedRevision.revision": "number:42",
            "envelope.preconditions.0.expectedRevision.subject.id":
                "string:project-residence",
            "envelope.preconditions.0.expectedRevision.subject.kind": "string:project",
            "fingerprint":
                "string:2894e905af41c3441b687b17c7bd70409782b0b255f51a1a965034d2cf61090f",
            "subject.id": "string:project-residence",
            "subject.kind": "string:project"
        ])

        let variants: [(RenameProjectCommand, Set<String>)] = [
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
            (try await Self.recordedCommand(displayName: "Changed Project"), [
                "draft.newDisplayName", "envelope.payload.displayName", "fingerprint"
            ]),
            (try await Self.recordedCommand(operationID: "operation-other"), [
                "envelope.operationId", "fingerprint"
            ]),
            (try await Self.recordedCommand(actorID: "principal-other"), [
                "draft.actorPrincipalId", "envelope.actorPrincipalId", "fingerprint"
            ]),
            (try await Self.recordedCommand(contractVersion: "project-rename-v2"), [
                "draft.operationContractVersion", "envelope.contractVersion", "fingerprint"
            ]),
            (try await Self.recordedCommand(capturedAt: Self.t1), [
                "draft.capturedAt", "envelope.clientCreatedAt", "fingerprint"
            ])
        ]

        #expect(variants.count == 8)
        for (variant, expectedChangedLeaves) in variants {
            #expect(variant != baseline)
            #expect(
                try Self.changedLeaves(from: baseline, to: variant) ==
                    expectedChangedLeaves
            )
        }
    }

    @Test("Construction fails before dispatch and receipt mismatch follows one call")
    func zeroAndOneCallFailureBoundaries() async throws {
        for value in [Double.infinity, Double.nan] {
            let renamer = RecordingProjectRenamer(response: .matching(.queued))
            do {
                _ = try await ProjectRenameUseCase(renamer: renamer).execute(
                    input: try Self.intent(),
                    operationId: OperationID(validating: "operation-invalid-time"),
                    actorPrincipalId: PrincipalID(
                        validating: "principal-project-rename-use-case"
                    ),
                    operationContractVersion: OperationContractVersion(
                        validating: "project-rename-use-case-v1"
                    ),
                    capturedAt: Date(timeIntervalSinceReferenceDate: value)
                )
                Issue.record("Nonfinite capture time returned a receipt")
            } catch let failure as ProjectRenameFailure {
                #expect(failure == .invalidCapturedAt)
            }
            #expect(await renamer.recordedCommands().isEmpty)
        }

        let mismatch = RecordingProjectRenamer(
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
        } catch let failure as ProjectRenameFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await mismatch.recordedCommands().count == 1)
    }

    @Test("All typed failures, cancellation, and unknown errors stay bounded")
    func exhaustiveFailureMapping() async throws {
        let failures: [ProjectRenameFailure] = [
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
            .invalidEncodedDraft,
            .invalidEncodedCommand
        ]
        #expect(failures.count == 12)
        for failure in failures {
            let renamer = RecordingProjectRenamer(response: .typedFailure(failure))
            do {
                _ = try await Self.execute(
                    using: renamer,
                    operationID: "operation-\(failure.diagnosticCode)"
                )
                Issue.record("Typed failure returned a receipt")
            } catch let received as ProjectRenameFailure {
                #expect(received == failure)
            }
            #expect(await renamer.recordedCommands().count == 1)
        }

        let cancelled = RecordingProjectRenamer(response: .cancelled)
        do {
            _ = try await Self.execute(using: cancelled, operationID: "operation-cancelled")
            Issue.record("Cancellation returned a receipt")
        } catch is CancellationError {
            // Expected structured-concurrency control flow.
        } catch {
            Issue.record("Cancellation was rewritten as \(error)")
        }
        #expect(await cancelled.recordedCommands().count == 1)

        let raw = RecordingProjectRenamer(response: .rawFailure)
        do {
            _ = try await Self.execute(using: raw, operationID: "operation-raw")
            Issue.record("Unknown port error returned a receipt")
        } catch let failure as ProjectRenameFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(await raw.recordedCommands().count == 1)
    }

    @Test("Diagnostics remain an exact privacy-safe enumeration")
    func exactPrivacySafeDiagnostics() {
        let diagnostics: [(ProjectRenameFailure, String)] = [
            (.invalidCapturedAt, "project_rename_captured_at_invalid"),
            (.draftAccountMismatch, "project_rename_account_mismatch"),
            (.draftActorMismatch, "project_rename_actor_mismatch"),
            (.draftContractMismatch, "project_rename_contract_mismatch"),
            (.draftPayloadMismatch, "project_rename_payload_mismatch"),
            (.revisionPreconditionMismatch, "project_rename_revision_precondition_mismatch"),
            (.subjectMismatch, "project_rename_subject_mismatch"),
            (.fingerprintMismatch, "project_rename_fingerprint_mismatch"),
            (.receiptMismatch, "project_rename_receipt_mismatch"),
            (.localAcceptanceFailed, "project_rename_local_acceptance_failed"),
            (.invalidEncodedDraft, "project_rename_draft_encoding_invalid"),
            (.invalidEncodedCommand, "project_rename_command_encoding_invalid")
        ]
        #expect(diagnostics.count == 12)
        #expect(Set(diagnostics.map(\.0)).count == 12)
        #expect(Set(diagnostics.map(\.1)).count == 12)
        for (failure, expected) in diagnostics {
            #expect(failure.diagnosticCode == expected)
            for secret in [
                "account-project-rename-use-case", "project-residence",
                "Project display name", "operation-project-rename-use-case",
                "principal-project-rename-use-case", "raw-provider-detail",
                "credential", "service-role", "production"
            ] {
                #expect(!failure.diagnosticCode.contains(secret))
            }
        }
    }

    @Test("Encoded command topology stays inside the rename-only boundary")
    func exactTopologyAndExclusions() async throws {
        let command = try await Self.recordedCommand()
        let encoded = try OperationContractCodec.encode(command)
        let root = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(Set(root.keys) == ["draft", "envelope", "subject", "fingerprint"])

        let draft = try #require(root["draft"] as? [String: Any])
        #expect(Set(draft.keys) == [
            "accountId", "actorPrincipalId", "operationContractVersion",
            "projectId", "newDisplayName", "expectedRevision", "capturedAt"
        ])
        #expect(draft["newDisplayName"] as? String == "Project display name")
        let expectedRevision = try #require(draft["expectedRevision"] as? [String: Any])
        #expect(Set(expectedRevision.keys) == ["rawValue"])

        let envelope = try #require(root["envelope"] as? [String: Any])
        #expect(Set(envelope.keys) == [
            "operationId", "contractVersion", "accountId", "actorPrincipalId",
            "clientCreatedAt", "payload", "preconditions"
        ])
        let payload = try #require(envelope["payload"] as? [String: Any])
        #expect(Set(payload.keys) == ["projectId", "displayName"])
        #expect(payload["displayName"] as? String == "Project display name")
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
            "rawName", "clientId", "clientName", "description", "categoryId",
            "categoryAllocations", "allocation", "budget", "attachment", "media",
            "image", "lifecycle", "archived", "deleted", "child", "item",
            "transaction", "invoice", "accounting", "history", "readiness",
            "route", "dismissal", "fields", "updates", "provider", "credential",
            "token", "secret"
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

    private static let t0 = Date(timeIntervalSince1970: 1_802_100_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_100_001)

    private static func requireEquatableAndSendable<T: Equatable & Sendable>(
        _ type: T.Type
    ) {}

    private static func isEncodable(_ value: Any) -> Bool {
        value is any Encodable
    }

    private static func isDecodableType(_ type: Any.Type) -> Bool {
        type is any Decodable.Type
    }

    private static func intent(
        accountID: String = "account-project-rename-use-case",
        projectID: String = "project-residence",
        revision: UInt64 = 42,
        displayName: String = "Project display name"
    ) throws -> ProjectRenameIntent {
        try ProjectRenameIntent(
            accountId: AccountID(validating: accountID),
            projectId: ProjectID(validating: projectID),
            expectedRevision: ExpectedProjectRevision(revision),
            newDisplayName: ProjectDisplayName(validating: displayName)
        )
    }

    private static func execute(
        using renamer: RecordingProjectRenamer,
        operationID: String
    ) async throws -> OperationReceipt {
        try await ProjectRenameUseCase(renamer: renamer).execute(
            input: intent(),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(
                validating: "principal-project-rename-use-case"
            ),
            operationContractVersion: OperationContractVersion(
                validating: "project-rename-use-case-v1"
            ),
            capturedAt: t0
        )
    }

    private static func recordedCommand(
        accountID: String = "account-project-rename-use-case",
        projectID: String = "project-residence",
        revision: UInt64 = 42,
        displayName: String = "Project display name",
        operationID: String = "operation-project-rename-use-case",
        actorID: String = "principal-project-rename-use-case",
        contractVersion: String = "project-rename-use-case-v1",
        capturedAt: Date = t0
    ) async throws -> RenameProjectCommand {
        let renamer = RecordingProjectRenamer(response: .matching(.queued))
        _ = try await ProjectRenameUseCase(renamer: renamer).execute(
            input: intent(
                accountID: accountID,
                projectID: projectID,
                revision: revision,
                displayName: displayName
            ),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: actorID),
            operationContractVersion: OperationContractVersion(
                validating: contractVersion
            ),
            capturedAt: capturedAt
        )
        let commands = await renamer.recordedCommands()
        #expect(commands.count == 1)
        return try #require(commands.first)
    }

    private static func changedLeaves(
        from baseline: RenameProjectCommand,
        to variant: RenameProjectCommand
    ) throws -> Set<String> {
        let baselineFields = try flattenedFields(baseline)
        let variantFields = try flattenedFields(variant)
        return Set(baselineFields.keys).union(variantFields.keys).filter {
            baselineFields[$0] != variantFields[$0]
        }
    }

    private static func flattenedFields(
        _ command: RenameProjectCommand
    ) throws -> [String: String] {
        let object = try JSONSerialization.jsonObject(
            with: OperationContractCodec.encode(command)
        )
        var fields: [String: String] = [:]
        flattenJSON(object, path: "", into: &fields)
        return fields
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

private enum ProjectRenamerResponse: Sendable {
    case matching(LocalOperationState)
    case mismatched(OperationID)
    case typedFailure(ProjectRenameFailure)
    case rawFailure
    case cancelled
}

private actor RecordingProjectRenamer: ProjectRenaming {
    private let response: ProjectRenamerResponse
    private var commands: [RenameProjectCommand] = []

    init(response: ProjectRenamerResponse) {
        self.response = response
    }

    func rename(_ command: RenameProjectCommand) async throws -> OperationReceipt {
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
            throw RawProjectRenamePortFailure.transport("raw-provider-detail")
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedCommands() -> [RenameProjectCommand] {
        commands
    }
}

private enum RawProjectRenamePortFailure: Error {
    case transport(String)
}
