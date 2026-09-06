import Foundation
import Testing
import LedgerTargetCore

@Suite("Item Space Assignment Use Case Contracts")
struct ItemSpaceAssignmentUseCaseTests {
    @Test("Public transient intent has the exact typed four-field shape")
    func publicTransientIntentShape() throws {
        Self.requireEquatableAndSendable(ItemSpaceAssignmentIntent.self)
        let project = try Self.intent(
            scope: .project(ProjectID(validating: "project-intent")),
            items: [("item-zero", 0), ("item-maximum", UInt64.max)]
        )
        let inventory = try Self.intent(scope: .businessInventory)

        #expect(project.scope == .project(try ProjectID(validating: "project-intent")))
        #expect(project.items[0].expectedRevision == ExpectedItemPlacementRevision(0))
        #expect(project.items[1].expectedRevision == ExpectedItemPlacementRevision(UInt64.max))
        #expect(inventory.scope == .businessInventory)
        #expect(project != inventory)
        #expect(!Self.isEncodable(project))
        #expect(!Self.isDecodableType(ItemSpaceAssignmentIntent.self))
        #expect(Set(Mirror(reflecting: project).children.compactMap(\.label)) == [
            "accountId", "scope", "destinationSpaceId", "items"
        ])
        #expect(
            Mirror(reflecting: project).children.first { $0.label == "items" }?.value
                is [ItemSpaceAssignmentCandidate]
        )
    }

    @Test("Represented destinations dispatch from every local evidence quality")
    func representedReadyPartialAndStaleDestinationsDispatch() async throws {
        let project = ItemPlacementScope.project(
            try ProjectID(validating: "project-evidence")
        )
        let cases: [(ItemPlacementScope, ListSnapshotQuality, Bool, UInt64, UInt64)] = [
            (project, .ready, true, 0, UInt64.max),
            (project, .partial, false, 73, 0),
            (project, .stale, false, UInt64.max, UInt64.max),
            (.businessInventory, .ready, true, UInt64.max, 0),
            (.businessInventory, .partial, false, 0, UInt64.max),
            (.businessInventory, .stale, false, 73, 73)
        ]

        for (index, entry) in cases.enumerated() {
            let assigner = RecordingItemSpaceAssigner(response: .matching(.queued))
            let operationID = try OperationID(validating: "operation-evidence-\(index)")
            let accountID = try AccountID(validating: "account-evidence-\(index)")
            let destinationID = try SpaceID(validating: "space-evidence-\(index)")
            let input = try Self.intent(
                accountID: accountID.rawValue,
                scope: entry.0,
                destinationSpaceID: destinationID.rawValue,
                items: [("item-evidence-\(index)", entry.4)]
            )
            let directory = try Self.directory(
                accountID: accountID.rawValue,
                scope: entry.0,
                destinationSpaceID: destinationID.rawValue,
                spaceRevision: entry.3,
                decoyRevision: index == 0 ? UInt64.max : nil,
                quality: entry.1,
                isComplete: entry.2
            )

            let receipt = try await ItemSpaceAssignmentUseCase(assigner: assigner).execute(
                input: input,
                currentDestinations: directory,
                operationId: operationID,
                actorPrincipalId: PrincipalID(validating: "principal-evidence"),
                operationContractVersion: OperationContractVersion(
                    validating: "item-space-assignment-use-case-v1"
                ),
                capturedAt: Self.t0
            )

            #expect(receipt == OperationReceipt(operationId: operationID, localState: .queued))
            let commands = await assigner.recordedCommands()
            #expect(commands.count == 1)
            let command = try #require(commands.first)
            #expect(command.draft.accountId == accountID)
            #expect(command.draft.scope == entry.0)
            #expect(command.draft.destinationSpaceId == destinationID)
            #expect(command.draft.expectedSpaceRevision == ExpectedSpaceRevision(entry.3))
            #expect(command.draft.items[0].expectedRevision == ExpectedItemPlacementRevision(entry.4))
        }

        let forward = try await Self.recordedCommand(
            items: [("item-zeta", 9), ("item-alpha", 4)]
        )
        let reverse = try await Self.recordedCommand(
            items: [("item-alpha", 4), ("item-zeta", 9)]
        )
        #expect(forward == reverse)
        #expect(forward.draft.items.map(\.itemId.rawValue) == ["item-alpha", "item-zeta"])
    }

    @Test("Evidence and construction failures occur before the port")
    func evidenceAndConstructionFailuresMakeZeroCalls() async throws {
        let project = ItemPlacementScope.project(try ProjectID(validating: "project-baseline"))
        let baselineDirectory = try Self.directory(scope: project)

        let accountMismatch = RecordingItemSpaceAssigner(response: .matching(.queued))
        await Self.expectUseCaseFailure(
            .directoryAccountMismatch,
            assigner: accountMismatch,
            input: try Self.intent(accountID: "account-other", scope: project),
            directory: baselineDirectory
        )

        let scopeMismatch = RecordingItemSpaceAssigner(response: .matching(.queued))
        await Self.expectUseCaseFailure(
            .directoryScopeMismatch,
            assigner: scopeMismatch,
            input: try Self.intent(scope: .businessInventory),
            directory: baselineDirectory
        )

        for (index, evidence) in [
            (ListSnapshotQuality.ready, true),
            (ListSnapshotQuality.partial, false),
            (ListSnapshotQuality.stale, false)
        ].enumerated() {
            let missing = RecordingItemSpaceAssigner(response: .matching(.queued))
            let directory = try Self.directory(
                scope: project,
                destinationSpaceID: "space-represented",
                quality: evidence.0,
                isComplete: evidence.1,
                version: "directory-missing-\(index)"
            )
            await Self.expectUseCaseFailure(
                .destinationNotRepresented,
                assigner: missing,
                input: try Self.intent(
                    scope: project,
                    destinationSpaceID: "space-absent"
                ),
                directory: directory
            )
        }

        let invalidInputs: [ItemSpaceAssignmentIntent] = [
            try Self.intent(scope: project, items: []),
            try Self.intent(scope: project, items: [("item-repeat", 1), ("item-repeat", 2)])
        ]
        let expected: [ItemSpaceAssignmentFailure] = [
            .emptyItemSelection, .duplicateItemIdentity
        ]
        for (input, failure) in zip(invalidInputs, expected) {
            let assigner = RecordingItemSpaceAssigner(response: .matching(.queued))
            await Self.expectOperationFailure(
                failure,
                assigner: assigner,
                input: input,
                directory: baselineDirectory
            )
        }

        for value in [Double.infinity, -Double.infinity, Double.nan] {
            let assigner = RecordingItemSpaceAssigner(response: .matching(.queued))
            await Self.expectOperationFailure(
                .invalidCapturedAt,
                assigner: assigner,
                input: try Self.intent(scope: project),
                directory: baselineDirectory,
                capturedAt: Date(timeIntervalSinceReferenceDate: value)
            )
        }
    }

    @Test("Every receipt state is exact and mismatch follows one call")
    func exactReceiptStatesAndOneCallValidation() async throws {
        for state in LocalOperationState.allCases {
            let assigner = RecordingItemSpaceAssigner(response: .matching(state))
            let operationID = "operation-receipt-\(state.rawValue)"
            let receipt = try await Self.execute(using: assigner, operationID: operationID)
            #expect(receipt == OperationReceipt(
                operationId: try OperationID(validating: operationID),
                localState: state
            ))
            #expect(await assigner.recordedCommands().count == 1)
        }

        let mismatch = RecordingItemSpaceAssigner(
            response: .mismatched(try OperationID(validating: "operation-wrong-receipt"))
        )
        do {
            _ = try await Self.execute(
                using: mismatch,
                operationID: "operation-expected-receipt"
            )
            Issue.record("Mismatched receipt returned")
        } catch let failure as ItemSpaceAssignmentFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await mismatch.recordedCommands().count == 1)
    }

    @Test("Every caller and evidence field changes only literal encoded owners")
    func reciprocalLiteralEncodedLeafOwnership() async throws {
        let baseline = try await Self.recordedCommand()
        let fields = try Self.flattenedFields(baseline)
        #expect(fields == Self.literalBaselineFields)

        let variants: [(AssignItemsToSpaceCommand, Set<String>)] = [
            (try await Self.recordedCommand(accountID: "account-other"), [
                "draft.accountId", "envelope.accountId", "fingerprint"
            ]),
            (try await Self.recordedCommand(
                scope: .businessInventory
            ), Self.scopeChangedLeaves),
            (try await Self.recordedCommand(destinationSpaceID: "space-other"), [
                "draft.destinationSpaceId", "envelope.payload.destinationSpaceId",
                "envelope.preconditions.0.expectedState.subject.id",
                "envelope.preconditions.1.expectedRevision.subject.id",
                "envelope.preconditions.2.expectedRelationship.subject.id",
                "subject.id", "fingerprint"
            ]),
            (try await Self.recordedCommand(spaceRevision: UInt64.max), [
                "draft.expectedSpaceRevision.rawValue",
                "envelope.preconditions.1.expectedRevision.revision", "fingerprint"
            ]),
            (try await Self.recordedCommand(items: [("item-beta", 4), ("item-zeta", 9)]), [
                "draft.items.0.itemId", "envelope.payload.itemIds.0",
                "envelope.preconditions.3.expectedRevision.subject.id",
                "envelope.preconditions.4.expectedRelationship.subject.id", "fingerprint"
            ]),
            (try await Self.recordedCommand(items: [("item-alpha", 5), ("item-zeta", 9)]), [
                "draft.items.0.expectedRevision.rawValue",
                "envelope.preconditions.3.expectedRevision.revision", "fingerprint"
            ]),
            (try await Self.recordedCommand(items: [("item-alpha", 4), ("item-zulu", 9)]), [
                "draft.items.1.itemId", "envelope.payload.itemIds.1",
                "envelope.preconditions.5.expectedRevision.subject.id",
                "envelope.preconditions.6.expectedRelationship.subject.id", "fingerprint"
            ]),
            (try await Self.recordedCommand(items: [("item-alpha", 4), ("item-zeta", 10)]), [
                "draft.items.1.expectedRevision.rawValue",
                "envelope.preconditions.5.expectedRevision.revision", "fingerprint"
            ]),
            (try await Self.recordedCommand(operationID: "operation-other"), [
                "envelope.operationId", "fingerprint"
            ]),
            (try await Self.recordedCommand(actorID: "principal-other"), [
                "draft.actorPrincipalId", "envelope.actorPrincipalId", "fingerprint"
            ]),
            (try await Self.recordedCommand(contractVersion: "item-space-use-v2"), [
                "draft.operationContractVersion", "envelope.contractVersion", "fingerprint"
            ]),
            (try await Self.recordedCommand(capturedAt: Self.t1), [
                "draft.capturedAt", "envelope.clientCreatedAt", "fingerprint"
            ])
        ]

        #expect(variants.count == 12)
        for (variant, expectedChangedLeaves) in variants {
            #expect(variant != baseline)
            #expect(
                try Self.changedLeaves(from: baseline, to: variant) == expectedChangedLeaves
            )
        }
    }

    @Test("All typed failures and cancellation retain their exact boundaries")
    func exhaustiveFailureMapping() async throws {
        let useCaseFailures: [(ItemSpaceAssignmentUseCaseFailure, String)] = [
            (.directoryAccountMismatch, "item_space_assignment_directory_account_mismatch"),
            (.directoryScopeMismatch, "item_space_assignment_directory_scope_mismatch"),
            (.destinationNotRepresented, "item_space_assignment_destination_not_represented")
        ]
        #expect(useCaseFailures.count == 3)
        #expect(Set(useCaseFailures.map(\.0)).count == 3)
        #expect(Set(useCaseFailures.map(\.1)).count == 3)
        for (failure, code) in useCaseFailures {
            #expect(failure.diagnosticCode == code)
        }

        let operationFailures: [(ItemSpaceAssignmentFailure, String)] = [
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
        #expect(operationFailures.count == 16)
        #expect(Set(operationFailures.map(\.0)).count == 16)
        #expect(Set(operationFailures.map(\.1)).count == 16)
        for (failure, code) in operationFailures {
            #expect(failure.diagnosticCode == code)
            let assigner = RecordingItemSpaceAssigner(response: .typedFailure(failure))
            do {
                _ = try await Self.execute(
                    using: assigner,
                    operationID: "operation-\(code)"
                )
                Issue.record("Typed failure returned a receipt")
            } catch let received as ItemSpaceAssignmentFailure {
                #expect(received == failure)
            }
            #expect(await assigner.recordedCommands().count == 1)
        }

        let cancelled = RecordingItemSpaceAssigner(response: .cancelled)
        do {
            _ = try await Self.execute(using: cancelled, operationID: "operation-cancelled")
            Issue.record("Cancellation returned a receipt")
        } catch is CancellationError {
            // Expected structured-concurrency control flow.
        } catch {
            Issue.record("Cancellation was rewritten as \(error)")
        }
        #expect(await cancelled.recordedCommands().count == 1)

        let raw = RecordingItemSpaceAssigner(response: .rawFailure)
        do {
            _ = try await Self.execute(using: raw, operationID: "operation-raw")
            Issue.record("Unknown port error returned a receipt")
        } catch let failure as ItemSpaceAssignmentFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(await raw.recordedCommands().count == 1)

        let invalidPortUseCaseFailure = RecordingItemSpaceAssigner(
            response: .useCaseFailure(.destinationNotRepresented)
        )
        do {
            _ = try await Self.execute(
                using: invalidPortUseCaseFailure,
                operationID: "operation-invalid-port-use-case-failure"
            )
            Issue.record("Port-originated use-case failure returned a receipt")
        } catch let failure as ItemSpaceAssignmentFailure {
            #expect(failure == .localAcceptanceFailed)
        } catch {
            Issue.record("Port-originated use-case failure was not bounded as \(error)")
        }
        #expect(await invalidPortUseCaseFailure.recordedCommands().count == 1)

        for code in useCaseFailures.map(\.1) + operationFailures.map(\.1) {
            for secret in [
                "account-space-use-case", "project-baseline", "space-destination",
                "item-alpha", "principal-space-use-case", "raw-provider-detail",
                "credential", "service-role", "production"
            ] {
                #expect(!code.contains(secret))
            }
        }
    }

    @Test("Nested command topology stays inside assignment-only composition")
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
            "destinationSpaceId", "scope", "expectedSpaceRevision", "items", "capturedAt"
        ])
        let draftItems = try #require(draft["items"] as? [[String: Any]])
        #expect(draftItems.count == 2)
        #expect(draftItems.allSatisfy { Set($0.keys) == ["itemId", "expectedRevision"] })
        let expectedSpaceRevision = try #require(
            draft["expectedSpaceRevision"] as? [String: Any]
        )
        #expect(Set(expectedSpaceRevision.keys) == ["rawValue"])

        let envelope = try #require(root["envelope"] as? [String: Any])
        #expect(Set(envelope.keys) == [
            "operationId", "contractVersion", "accountId", "actorPrincipalId",
            "clientCreatedAt", "payload", "preconditions"
        ])
        let payload = try #require(envelope["payload"] as? [String: Any])
        #expect(Set(payload.keys) == ["destinationSpaceId", "scope", "itemIds"])
        let preconditions = try #require(envelope["preconditions"] as? [[String: Any]])
        #expect(preconditions.count == 7)
        #expect(Set(preconditions[0].keys) == ["expectedState"])
        #expect(Set(preconditions[1].keys) == ["expectedRevision"])
        #expect(Set(preconditions[2].keys) == ["expectedRelationship"])
        #expect(Set(preconditions[3].keys) == ["expectedRevision"])
        #expect(Set(preconditions[4].keys) == ["expectedRelationship"])
        #expect(Set(preconditions[5].keys) == ["expectedRevision"])
        #expect(Set(preconditions[6].keys) == ["expectedRelationship"])

        var keys = Set<String>()
        Self.collectKeys(root, into: &keys)
        let forbiddenKeys: Set<String> = [
            "displayName", "spaceName", "route", "backendPath", "authorization",
            "authorized", "attachment", "media", "image", "marker", "archive",
            "clear", "sourceScope", "destinationScope", "transaction", "occurrence",
            "invoice", "budget", "amount", "price", "payer", "accounting",
            "provenance", "uiState", "service", "provider", "credential", "token"
        ]
        #expect(keys.isDisjoint(with: forbiddenKeys))

        let text = String(decoding: encoded, as: UTF8.self).lowercased()
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "https://", "file://",
            "bearer", "raw-provider-detail", "production"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_300_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_300_001)

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
        accountID: String = "account-space-use-case",
        scope: ItemPlacementScope = .project(try! ProjectID(validating: "project-baseline")),
        destinationSpaceID: String = "space-destination",
        items: [(String, UInt64)] = [("item-alpha", 4), ("item-zeta", 9)]
    ) throws -> ItemSpaceAssignmentIntent {
        ItemSpaceAssignmentIntent(
            accountId: try AccountID(validating: accountID),
            scope: scope,
            destinationSpaceId: try SpaceID(validating: destinationSpaceID),
            items: try items.map {
                ItemSpaceAssignmentCandidate(
                    itemId: try ItemID(validating: $0.0),
                    expectedRevision: ExpectedItemPlacementRevision($0.1)
                )
            }
        )
    }

    private static func directory(
        accountID: String = "account-space-use-case",
        scope: ItemPlacementScope = .project(try! ProjectID(validating: "project-baseline")),
        destinationSpaceID: String = "space-destination",
        spaceRevision: UInt64 = 12,
        decoyRevision: UInt64? = nil,
        quality: ListSnapshotQuality = .ready,
        isComplete: Bool = true,
        version: String = "space-use-case-directory"
    ) throws -> SpaceAssignmentDestinationDirectorySnapshot {
        let accountId = try AccountID(validating: accountID)
        let request = try SpaceAssignmentDestinationRequest(
            accountId: accountId,
            scope: scope
        )
        let row = try SpaceAssignmentDestinationSnapshot(
            id: SpaceID(validating: destinationSpaceID),
            accountId: accountId,
            scope: scope,
            displayName: SpaceDisplayName(validating: "Local destination evidence"),
            lifecycle: .active,
            revision: spaceRevision
        )
        var rows = [row]
        if let decoyRevision {
            rows.append(try SpaceAssignmentDestinationSnapshot(
                id: SpaceID(validating: "space-decoy"),
                accountId: accountId,
                scope: scope,
                displayName: SpaceDisplayName(validating: "Unselected local evidence"),
                lifecycle: .active,
                revision: decoyRevision
            ))
        }
        return try SpaceAssignmentDestinationDirectorySnapshot(
            request: request,
            local: ListLocalSnapshot(
                queryFingerprint: request.queryFingerprint,
                rows: rows,
                visibleRowCountBeforeFiltering: rows.count,
                isCompleteForQuery: isComplete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: t0
            )
        )
    }

    private static func execute(
        using assigner: RecordingItemSpaceAssigner,
        operationID: String
    ) async throws -> OperationReceipt {
        try await ItemSpaceAssignmentUseCase(assigner: assigner).execute(
            input: intent(),
            currentDestinations: directory(),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: "principal-space-use-case"),
            operationContractVersion: OperationContractVersion(
                validating: "item-space-assignment-use-case-v1"
            ),
            capturedAt: t0
        )
    }

    private static func recordedCommand(
        accountID: String = "account-space-use-case",
        scope: ItemPlacementScope = .project(try! ProjectID(validating: "project-baseline")),
        destinationSpaceID: String = "space-destination",
        spaceRevision: UInt64 = 12,
        items: [(String, UInt64)] = [("item-alpha", 4), ("item-zeta", 9)],
        operationID: String = "operation-space-use-case",
        actorID: String = "principal-space-use-case",
        contractVersion: String = "item-space-assignment-use-case-v1",
        capturedAt: Date = t0
    ) async throws -> AssignItemsToSpaceCommand {
        let assigner = RecordingItemSpaceAssigner(response: .matching(.queued))
        _ = try await ItemSpaceAssignmentUseCase(assigner: assigner).execute(
            input: intent(
                accountID: accountID,
                scope: scope,
                destinationSpaceID: destinationSpaceID,
                items: items
            ),
            currentDestinations: directory(
                accountID: accountID,
                scope: scope,
                destinationSpaceID: destinationSpaceID,
                spaceRevision: spaceRevision
            ),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: actorID),
            operationContractVersion: OperationContractVersion(validating: contractVersion),
            capturedAt: capturedAt
        )
        let commands = await assigner.recordedCommands()
        #expect(commands.count == 1)
        return try #require(commands.first)
    }

    private static func expectUseCaseFailure(
        _ expected: ItemSpaceAssignmentUseCaseFailure,
        assigner: RecordingItemSpaceAssigner,
        input: ItemSpaceAssignmentIntent,
        directory: SpaceAssignmentDestinationDirectorySnapshot
    ) async {
        do {
            _ = try await ItemSpaceAssignmentUseCase(assigner: assigner).execute(
                input: input,
                currentDestinations: directory,
                operationId: OperationID(validating: "operation-use-case-failure"),
                actorPrincipalId: PrincipalID(validating: "principal-space-use-case"),
                operationContractVersion: OperationContractVersion(
                    validating: "item-space-assignment-use-case-v1"
                ),
                capturedAt: t0
            )
            Issue.record("Use-case failure returned a receipt")
        } catch let failure as ItemSpaceAssignmentUseCaseFailure {
            #expect(failure == expected)
        } catch {
            Issue.record("Use-case failure was rewritten as \(error)")
        }
        #expect(await assigner.recordedCommands().isEmpty)
    }

    private static func expectOperationFailure(
        _ expected: ItemSpaceAssignmentFailure,
        assigner: RecordingItemSpaceAssigner,
        input: ItemSpaceAssignmentIntent,
        directory: SpaceAssignmentDestinationDirectorySnapshot,
        capturedAt: Date = t0
    ) async {
        do {
            _ = try await ItemSpaceAssignmentUseCase(assigner: assigner).execute(
                input: input,
                currentDestinations: directory,
                operationId: OperationID(validating: "operation-construction-failure"),
                actorPrincipalId: PrincipalID(validating: "principal-space-use-case"),
                operationContractVersion: OperationContractVersion(
                    validating: "item-space-assignment-use-case-v1"
                ),
                capturedAt: capturedAt
            )
            Issue.record("Construction failure returned a receipt")
        } catch let failure as ItemSpaceAssignmentFailure {
            #expect(failure == expected)
        } catch {
            Issue.record("Construction failure was rewritten as \(error)")
        }
        #expect(await assigner.recordedCommands().isEmpty)
    }

    private static func changedLeaves(
        from baseline: AssignItemsToSpaceCommand,
        to variant: AssignItemsToSpaceCommand
    ) throws -> Set<String> {
        let baselineFields = try flattenedFields(baseline)
        let variantFields = try flattenedFields(variant)
        return Set(baselineFields.keys).union(variantFields.keys).filter {
            baselineFields[$0] != variantFields[$0]
        }
    }

    private static func flattenedFields(
        _ command: AssignItemsToSpaceCommand
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

    private static let scopeChangedLeaves: Set<String> = [
        "draft.scope.kind", "draft.scope.projectId",
        "envelope.payload.scope.kind", "envelope.payload.scope.projectId",
        "envelope.preconditions.2.expectedRelationship.relation",
        "envelope.preconditions.2.expectedRelationship.target.id",
        "envelope.preconditions.2.expectedRelationship.target.kind",
        "envelope.preconditions.4.expectedRelationship.relation",
        "envelope.preconditions.4.expectedRelationship.target.id",
        "envelope.preconditions.4.expectedRelationship.target.kind",
        "envelope.preconditions.6.expectedRelationship.relation",
        "envelope.preconditions.6.expectedRelationship.target.id",
        "envelope.preconditions.6.expectedRelationship.target.kind",
        "fingerprint"
    ]

    private static let literalBaselineFields: [String: String] = [
        "draft.accountId": "string:account-space-use-case",
        "draft.actorPrincipalId": "string:principal-space-use-case",
        "draft.capturedAt": "number:1802300000000",
        "draft.destinationSpaceId": "string:space-destination",
        "draft.expectedSpaceRevision.rawValue": "number:12",
        "draft.items.0.expectedRevision.rawValue": "number:4",
        "draft.items.0.itemId": "string:item-alpha",
        "draft.items.1.expectedRevision.rawValue": "number:9",
        "draft.items.1.itemId": "string:item-zeta",
        "draft.operationContractVersion": "string:item-space-assignment-use-case-v1",
        "draft.scope.kind": "string:project",
        "draft.scope.projectId": "string:project-baseline",
        "envelope.accountId": "string:account-space-use-case",
        "envelope.actorPrincipalId": "string:principal-space-use-case",
        "envelope.clientCreatedAt": "number:1802300000000",
        "envelope.contractVersion": "string:item-space-assignment-use-case-v1",
        "envelope.operationId": "string:operation-space-use-case",
        "envelope.payload.destinationSpaceId": "string:space-destination",
        "envelope.payload.itemIds.0": "string:item-alpha",
        "envelope.payload.itemIds.1": "string:item-zeta",
        "envelope.payload.scope.kind": "string:project",
        "envelope.payload.scope.projectId": "string:project-baseline",
        "envelope.preconditions.0.expectedState.state": "string:active",
        "envelope.preconditions.0.expectedState.subject.id": "string:space-destination",
        "envelope.preconditions.0.expectedState.subject.kind": "string:space",
        "envelope.preconditions.1.expectedRevision.revision": "number:12",
        "envelope.preconditions.1.expectedRevision.subject.id": "string:space-destination",
        "envelope.preconditions.1.expectedRevision.subject.kind": "string:space",
        "envelope.preconditions.2.expectedRelationship.relation":
            "string:belongs_to_project",
        "envelope.preconditions.2.expectedRelationship.subject.id":
            "string:space-destination",
        "envelope.preconditions.2.expectedRelationship.subject.kind": "string:space",
        "envelope.preconditions.2.expectedRelationship.target.id":
            "string:project-baseline",
        "envelope.preconditions.2.expectedRelationship.target.kind": "string:project",
        "envelope.preconditions.3.expectedRevision.revision": "number:4",
        "envelope.preconditions.3.expectedRevision.subject.id": "string:item-alpha",
        "envelope.preconditions.3.expectedRevision.subject.kind": "string:item",
        "envelope.preconditions.4.expectedRelationship.relation":
            "string:belongs_to_project",
        "envelope.preconditions.4.expectedRelationship.subject.id": "string:item-alpha",
        "envelope.preconditions.4.expectedRelationship.subject.kind": "string:item",
        "envelope.preconditions.4.expectedRelationship.target.id":
            "string:project-baseline",
        "envelope.preconditions.4.expectedRelationship.target.kind": "string:project",
        "envelope.preconditions.5.expectedRevision.revision": "number:9",
        "envelope.preconditions.5.expectedRevision.subject.id": "string:item-zeta",
        "envelope.preconditions.5.expectedRevision.subject.kind": "string:item",
        "envelope.preconditions.6.expectedRelationship.relation":
            "string:belongs_to_project",
        "envelope.preconditions.6.expectedRelationship.subject.id": "string:item-zeta",
        "envelope.preconditions.6.expectedRelationship.subject.kind": "string:item",
        "envelope.preconditions.6.expectedRelationship.target.id":
            "string:project-baseline",
        "envelope.preconditions.6.expectedRelationship.target.kind": "string:project",
        "fingerprint":
            "string:9cfea1b7a767b828e09a11c516de47e01aafefedb428af6605a36ad8bfe27db1",
        "subject.id": "string:space-destination",
        "subject.kind": "string:space"
    ]
}

private enum ItemSpaceAssignerResponse: Sendable {
    case matching(LocalOperationState)
    case mismatched(OperationID)
    case typedFailure(ItemSpaceAssignmentFailure)
    case useCaseFailure(ItemSpaceAssignmentUseCaseFailure)
    case rawFailure
    case cancelled
}

private actor RecordingItemSpaceAssigner: ItemSpaceAssigning {
    private let response: ItemSpaceAssignerResponse
    private var commands: [AssignItemsToSpaceCommand] = []

    init(response: ItemSpaceAssignerResponse) {
        self.response = response
    }

    func assignItemsToSpace(
        _ command: AssignItemsToSpaceCommand
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
        case .useCaseFailure(let failure):
            throw failure
        case .rawFailure:
            throw RawItemSpaceAssignmentPortFailure.transport("raw-provider-detail")
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedCommands() -> [AssignItemsToSpaceCommand] {
        commands
    }
}

private enum RawItemSpaceAssignmentPortFailure: Error {
    case transport(String)
}
