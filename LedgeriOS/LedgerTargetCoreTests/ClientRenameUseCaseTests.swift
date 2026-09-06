import Foundation
import Testing
import LedgerTargetCore

@Suite("Client Rename Use Case Contracts")
struct ClientRenameUseCaseTests {
    @Test("Public transient intent has the exact typed four-field shape")
    func publicTransientIntentShape() throws {
        Self.requireEquatableAndSendable(ClientRenameIntent.self)
        let zero = try Self.intent(revision: 0)
        let maximum = try Self.intent(
            clientID: "client-maximum-revision",
            revision: UInt64.max,
            displayName: "Maximum revision client"
        )

        #expect(zero.expectedRevision == ExpectedClientRevision(0))
        #expect(maximum.expectedRevision == ExpectedClientRevision(UInt64.max))
        #expect(zero != maximum)
        #expect(!Self.isEncodable(zero))
        #expect(!Self.isDecodableType(ClientRenameIntent.self))
        #expect(Set(Mirror(reflecting: zero).children.compactMap(\.label)) == [
            "accountId", "clientId", "expectedRevision", "newDisplayName"
        ])
        #expect(
            Mirror(reflecting: zero).children.first { $0.label == "newDisplayName" }?.value
                is ClientDisplayName
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
        #expect(
            Data(longCommand.envelope.payload.displayName.rawValue.utf8) ==
                Data(long.utf8)
        )
    }

    @Test("Every receipt state and revision boundary dispatches exactly once")
    func exactReceiptStatesAndRevisionBoundaries() async throws {
        for state in LocalOperationState.allCases {
            let operationID = try OperationID(
                validating: "operation-client-rename-\(state.rawValue)"
            )
            let renamer = RecordingClientRenamer(response: .matching(state))
            let receipt = try await ClientRenameUseCase(renamer: renamer).execute(
                input: try Self.intent(
                    accountID: "account-exact",
                    clientID: "client-exact",
                    revision: 73,
                    displayName: "Exact Client"
                ),
                operationId: operationID,
                actorPrincipalId: PrincipalID(validating: "principal-exact"),
                operationContractVersion: OperationContractVersion(
                    validating: "client-rename-v7"
                ),
                capturedAt: Self.t0
            )

            #expect(receipt == OperationReceipt(operationId: operationID, localState: state))
            let commands = await renamer.recordedCommands()
            #expect(commands.count == 1)
            let command = try #require(commands.first)
            #expect(command.draft.accountId.rawValue == "account-exact")
            #expect(command.draft.clientId.rawValue == "client-exact")
            #expect(command.draft.expectedRevision == ExpectedClientRevision(73))
            #expect(command.draft.newDisplayName.rawValue == "Exact Client")
            #expect(command.envelope.preconditions == [
                .expectedRevision(subject: command.subject, revision: 73)
            ])
            #expect(try command.validate(receipt) == receipt)
        }

        for revision in [UInt64(0), UInt64.max] {
            let command = try await Self.recordedCommand(revision: revision)
            #expect(command.draft.expectedRevision == ExpectedClientRevision(revision))
            #expect(command.envelope.preconditions == [
                .expectedRevision(subject: command.subject, revision: revision)
            ])
        }
    }

    @Test("Every caller field changes only its literal encoded owners")
    func reciprocalLiteralEncodedLeafOwnership() async throws {
        let baseline = try await Self.recordedCommand()
        #expect(try Self.flattenedFields(baseline) == [
            "draft.accountId": "string:account-client-rename-use-case",
            "draft.actorPrincipalId": "string:principal-client-rename-use-case",
            "draft.capturedAt": "number:1802100000000",
            "draft.expectedRevision.rawValue": "number:42",
            "draft.newDisplayName": "string:Client display name",
            "draft.operationContractVersion": "string:client-rename-use-case-v1",
            "draft.clientId": "string:client-residence",
            "envelope.accountId": "string:account-client-rename-use-case",
            "envelope.actorPrincipalId": "string:principal-client-rename-use-case",
            "envelope.clientCreatedAt": "number:1802100000000",
            "envelope.contractVersion": "string:client-rename-use-case-v1",
            "envelope.operationId": "string:operation-client-rename-use-case",
            "envelope.payload.displayName": "string:Client display name",
            "envelope.payload.clientId": "string:client-residence",
            "envelope.preconditions.0.expectedRevision.revision": "number:42",
            "envelope.preconditions.0.expectedRevision.subject.id":
                "string:client-residence",
            "envelope.preconditions.0.expectedRevision.subject.kind": "string:client",
            "fingerprint":
                "string:07da52fd2b64793ef367972188ee33116bde4c892b205b2bbcc9d77060d6c2aa",
            "subject.id": "string:client-residence",
            "subject.kind": "string:client"
        ])

        let variants: [(RenameClientCommand, Set<String>)] = [
            (try await Self.recordedCommand(accountID: "account-other"), [
                "draft.accountId", "envelope.accountId", "fingerprint"
            ]),
            (try await Self.recordedCommand(clientID: "client-other"), [
                "draft.clientId", "envelope.payload.clientId",
                "envelope.preconditions.0.expectedRevision.subject.id",
                "subject.id", "fingerprint"
            ]),
            (try await Self.recordedCommand(revision: UInt64.max), [
                "draft.expectedRevision.rawValue",
                "envelope.preconditions.0.expectedRevision.revision", "fingerprint"
            ]),
            (try await Self.recordedCommand(displayName: "Changed Client"), [
                "draft.newDisplayName", "envelope.payload.displayName", "fingerprint"
            ]),
            (try await Self.recordedCommand(operationID: "operation-other"), [
                "envelope.operationId", "fingerprint"
            ]),
            (try await Self.recordedCommand(actorID: "principal-other"), [
                "draft.actorPrincipalId", "envelope.actorPrincipalId", "fingerprint"
            ]),
            (try await Self.recordedCommand(contractVersion: "client-rename-v2"), [
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
            let renamer = RecordingClientRenamer(response: .matching(.queued))
            do {
                _ = try await ClientRenameUseCase(renamer: renamer).execute(
                    input: try Self.intent(),
                    operationId: OperationID(validating: "operation-invalid-time"),
                    actorPrincipalId: PrincipalID(
                        validating: "principal-client-rename-use-case"
                    ),
                    operationContractVersion: OperationContractVersion(
                        validating: "client-rename-use-case-v1"
                    ),
                    capturedAt: Date(timeIntervalSinceReferenceDate: value)
                )
                Issue.record("Nonfinite capture time returned a receipt")
            } catch let failure as ClientRenameFailure {
                #expect(failure == .invalidCapturedAt)
            }
            #expect(await renamer.recordedCommands().isEmpty)
        }

        let mismatch = RecordingClientRenamer(
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
        } catch let failure as ClientRenameFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await mismatch.recordedCommands().count == 1)
    }

    @Test("All typed failures, cancellation, and unknown errors stay bounded")
    func exhaustiveFailureMapping() async throws {
        let failures: [ClientRenameFailure] = [
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
            let renamer = RecordingClientRenamer(response: .typedFailure(failure))
            do {
                _ = try await Self.execute(
                    using: renamer,
                    operationID: "operation-\(failure.diagnosticCode)"
                )
                Issue.record("Typed failure returned a receipt")
            } catch let received as ClientRenameFailure {
                #expect(received == failure)
            }
            #expect(await renamer.recordedCommands().count == 1)
        }

        let cancelled = RecordingClientRenamer(response: .cancelled)
        do {
            _ = try await Self.execute(using: cancelled, operationID: "operation-cancelled")
            Issue.record("Cancellation returned a receipt")
        } catch is CancellationError {
            // Expected structured-concurrency control flow.
        } catch {
            Issue.record("Cancellation was rewritten as \(error)")
        }
        #expect(await cancelled.recordedCommands().count == 1)

        let raw = RecordingClientRenamer(response: .rawFailure)
        do {
            _ = try await Self.execute(using: raw, operationID: "operation-raw")
            Issue.record("Unknown port error returned a receipt")
        } catch let failure as ClientRenameFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(await raw.recordedCommands().count == 1)
    }

    @Test("Diagnostics remain an exact privacy-safe enumeration")
    func exactPrivacySafeDiagnostics() {
        let diagnostics: [(ClientRenameFailure, String)] = [
            (.invalidCapturedAt, "client_rename_captured_at_invalid"),
            (.draftAccountMismatch, "client_rename_account_mismatch"),
            (.draftActorMismatch, "client_rename_actor_mismatch"),
            (.draftContractMismatch, "client_rename_contract_mismatch"),
            (.draftPayloadMismatch, "client_rename_payload_mismatch"),
            (.revisionPreconditionMismatch, "client_rename_revision_precondition_mismatch"),
            (.subjectMismatch, "client_rename_subject_mismatch"),
            (.fingerprintMismatch, "client_rename_fingerprint_mismatch"),
            (.receiptMismatch, "client_rename_receipt_mismatch"),
            (.localAcceptanceFailed, "client_rename_local_acceptance_failed"),
            (.invalidEncodedDraft, "client_rename_draft_encoding_invalid"),
            (.invalidEncodedCommand, "client_rename_command_encoding_invalid")
        ]
        #expect(diagnostics.count == 12)
        #expect(Set(diagnostics.map(\.0)).count == 12)
        #expect(Set(diagnostics.map(\.1)).count == 12)
        for (failure, expected) in diagnostics {
            #expect(failure.diagnosticCode == expected)
            for secret in [
                "account-client-rename-use-case", "client-residence",
                "Client display name", "operation-client-rename-use-case",
                "principal-client-rename-use-case", "raw-provider-detail",
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
            "clientId", "newDisplayName", "expectedRevision", "capturedAt"
        ])
        #expect(draft["newDisplayName"] as? String == "Client display name")
        let expectedRevision = try #require(draft["expectedRevision"] as? [String: Any])
        #expect(Set(expectedRevision.keys) == ["rawValue"])

        let envelope = try #require(root["envelope"] as? [String: Any])
        #expect(Set(envelope.keys) == [
            "operationId", "contractVersion", "accountId", "actorPrincipalId",
            "clientCreatedAt", "payload", "preconditions"
        ])
        let payload = try #require(envelope["payload"] as? [String: Any])
        #expect(Set(payload.keys) == ["clientId", "displayName"])
        #expect(payload["displayName"] as? String == "Client display name")
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
            "rawName", "clientName", "projectId", "projectName", "description",
            "alias", "merge", "reassignment", "categoryId",
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
        accountID: String = "account-client-rename-use-case",
        clientID: String = "client-residence",
        revision: UInt64 = 42,
        displayName: String = "Client display name"
    ) throws -> ClientRenameIntent {
        try ClientRenameIntent(
            accountId: AccountID(validating: accountID),
            clientId: ClientID(validating: clientID),
            expectedRevision: ExpectedClientRevision(revision),
            newDisplayName: ClientDisplayName(validating: displayName)
        )
    }

    private static func execute(
        using renamer: RecordingClientRenamer,
        operationID: String
    ) async throws -> OperationReceipt {
        try await ClientRenameUseCase(renamer: renamer).execute(
            input: intent(),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(
                validating: "principal-client-rename-use-case"
            ),
            operationContractVersion: OperationContractVersion(
                validating: "client-rename-use-case-v1"
            ),
            capturedAt: t0
        )
    }

    private static func recordedCommand(
        accountID: String = "account-client-rename-use-case",
        clientID: String = "client-residence",
        revision: UInt64 = 42,
        displayName: String = "Client display name",
        operationID: String = "operation-client-rename-use-case",
        actorID: String = "principal-client-rename-use-case",
        contractVersion: String = "client-rename-use-case-v1",
        capturedAt: Date = t0
    ) async throws -> RenameClientCommand {
        let renamer = RecordingClientRenamer(response: .matching(.queued))
        _ = try await ClientRenameUseCase(renamer: renamer).execute(
            input: intent(
                accountID: accountID,
                clientID: clientID,
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
        from baseline: RenameClientCommand,
        to variant: RenameClientCommand
    ) throws -> Set<String> {
        let baselineFields = try flattenedFields(baseline)
        let variantFields = try flattenedFields(variant)
        return Set(baselineFields.keys).union(variantFields.keys).filter {
            baselineFields[$0] != variantFields[$0]
        }
    }

    private static func flattenedFields(
        _ command: RenameClientCommand
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

private enum ClientRenamerResponse: Sendable {
    case matching(LocalOperationState)
    case mismatched(OperationID)
    case typedFailure(ClientRenameFailure)
    case rawFailure
    case cancelled
}

private actor RecordingClientRenamer: ClientRenaming {
    private let response: ClientRenamerResponse
    private var commands: [RenameClientCommand] = []

    init(response: ClientRenamerResponse) {
        self.response = response
    }

    func rename(_ command: RenameClientCommand) async throws -> OperationReceipt {
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
            throw RawClientRenamePortFailure.transport("raw-provider-detail")
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedCommands() -> [RenameClientCommand] {
        commands
    }
}

private enum RawClientRenamePortFailure: Error {
    case transport(String)
}
