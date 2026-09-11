import Foundation
import Testing
import LedgerTargetCore

@Suite("Item Space Clearing Use Case Contracts")
struct ItemSpaceClearingUseCaseTests {
    @Test("Public transient intent has the exact typed three-field shape")
    func publicTransientIntentShape() throws {
        Self.requireEquatableAndSendable(ItemSpaceClearingIntent.self)
        let project = try Self.intent(
            scope: .project(ProjectID(validating: "project-intent")),
            items: [
                ("item-zero", 0, "space-zero"),
                ("item-maximum", UInt64.max, "space-maximum")
            ]
        )
        let inventory = try Self.intent(scope: .businessInventory)

        #expect(project.accountId == (try AccountID(validating: "account-space-use-case")))
        #expect(project.scope == .project(try ProjectID(validating: "project-intent")))
        #expect(project.items[0].expectedRevision == ExpectedItemPlacementRevision(0))
        #expect(project.items[0].currentSpaceId == (try SpaceID(validating: "space-zero")))
        #expect(project.items[1].expectedRevision == ExpectedItemPlacementRevision(UInt64.max))
        #expect(inventory.scope == .businessInventory)
        #expect(project != inventory)
        #expect(!Self.isEncodable(project))
        #expect(!Self.isDecodableType(ItemSpaceClearingIntent.self))
        #expect(Set(Mirror(reflecting: project).children.compactMap(\.label)) == [
            "accountId", "scope", "items"
        ])
        #expect(
            Mirror(reflecting: project).children.first { $0.label == "items" }?.value
                is [ItemSpaceClearingCandidate]
        )
    }

    @Test("Project, Inventory, single, mixed-Space, and reordered input dispatch exactly once")
    func exactDispatchCasesAndCanonicalOrdering() async throws {
        let project = ItemPlacementScope.project(
            try ProjectID(validating: "project-dispatch")
        )
        let cases: [(ItemPlacementScope, [(String, UInt64, String)])] = [
            (project, [("item-single", 0, "space-current")]),
            (project, [
                ("item-zeta", UInt64.max, "space-beta"),
                ("item-alpha", 0, "space-alpha")
            ]),
            (.businessInventory, [("item-stock", UInt64.max, "space-warehouse")]),
            (.businessInventory, [
                ("item-two", 2, "space-shared"),
                ("item-one", 1, "space-shared")
            ])
        ]

        for (index, entry) in cases.enumerated() {
            let clearer = RecordingItemSpaceClearer(response: .matching(.queued))
            let accountID = try AccountID(validating: "account-dispatch-\(index)")
            let operationID = try OperationID(validating: "operation-dispatch-\(index)")
            let receipt = try await ItemSpaceClearingUseCase(clearer: clearer).execute(
                input: try Self.intent(
                    accountID: accountID.rawValue,
                    scope: entry.0,
                    items: entry.1
                ),
                operationId: operationID,
                actorPrincipalId: PrincipalID(validating: "principal-dispatch"),
                operationContractVersion: OperationContractVersion(
                    validating: "item-space-clearing-use-case-v1"
                ),
                capturedAt: Self.t0
            )

            #expect(receipt == OperationReceipt(operationId: operationID, localState: .queued))
            let commands = await clearer.recordedCommands()
            #expect(commands.count == 1)
            let command = try #require(commands.first)
            #expect(command.draft.accountId == accountID)
            #expect(command.draft.scope == entry.0)
            #expect(command.draft.items.map(\.itemId.rawValue) == entry.1.map(\.0).sorted())
            #expect(command.draft.items.map(\.expectedRevision.rawValue) ==
                entry.1.sorted { $0.0 < $1.0 }.map(\.1))
            #expect(command.draft.items.map(\.currentSpaceId.rawValue) ==
                entry.1.sorted { $0.0 < $1.0 }.map(\.2))
        }

        let forward = try await Self.recordedCommand(items: [
            ("item-zeta", 9, "space-studio"),
            ("item-alpha", 4, "space-library")
        ])
        let reverse = try await Self.recordedCommand(items: [
            ("item-alpha", 4, "space-library"),
            ("item-zeta", 9, "space-studio")
        ])
        #expect(forward == reverse)
        #expect(forward.fingerprint == reverse.fingerprint)
        #expect(forward.draft.items.map(\.itemId.rawValue) == ["item-alpha", "item-zeta"])
    }

    @Test("Construction failures make zero calls while stale assigned-looking evidence dispatches")
    func constructionBoundariesAndUntrustedEvidence() async throws {
        let invalidInputs: [ItemSpaceClearingIntent] = [
            try Self.intent(items: []),
            try Self.intent(items: [
                ("item-repeat", 1, "space-one"),
                ("item-repeat", 2, "space-two")
            ])
        ]
        let expected: [ItemSpaceClearingFailure] = [
            .emptyItemSelection, .duplicateItemIdentity
        ]
        for (input, failure) in zip(invalidInputs, expected) {
            let clearer = RecordingItemSpaceClearer(response: .matching(.queued))
            await Self.expectConstructionFailure(
                failure,
                clearer: clearer,
                input: input
            )
        }

        for value in [Double.infinity, -Double.infinity, Double.nan] {
            let clearer = RecordingItemSpaceClearer(response: .matching(.queued))
            await Self.expectConstructionFailure(
                .invalidCapturedAt,
                clearer: clearer,
                input: try Self.intent(),
                capturedAt: Date(timeIntervalSinceReferenceDate: value)
            )
        }

        let staleEvidence = RecordingItemSpaceClearer(response: .matching(.queued))
        let staleReceipt = try await ItemSpaceClearingUseCase(
            clearer: staleEvidence
        ).execute(
            input: try Self.intent(items: [
                ("item-stale", UInt64.max, "space-stale-claim")
            ]),
            operationId: OperationID(validating: "operation-stale-evidence"),
            actorPrincipalId: PrincipalID(validating: "principal-space-use-case"),
            operationContractVersion: OperationContractVersion(
                validating: "item-space-clearing-use-case-v1"
            ),
            capturedAt: Self.t0
        )
        #expect(staleReceipt.localState == .queued)
        #expect(await staleEvidence.recordedCommands().count == 1)
    }

    @Test("Every receipt state is exact and mismatch follows one call")
    func exactReceiptStatesAndOneCallValidation() async throws {
        for state in LocalOperationState.allCases {
            let clearer = RecordingItemSpaceClearer(response: .matching(state))
            let operationID = "operation-receipt-\(state.rawValue)"
            let receipt = try await Self.execute(using: clearer, operationID: operationID)
            #expect(receipt == OperationReceipt(
                operationId: try OperationID(validating: operationID),
                localState: state
            ))
            #expect(await clearer.recordedCommands().count == 1)
        }

        let mismatch = RecordingItemSpaceClearer(
            response: .mismatched(try OperationID(validating: "operation-wrong-receipt"))
        )
        do {
            _ = try await Self.execute(
                using: mismatch,
                operationID: "operation-expected-receipt"
            )
            Issue.record("Mismatched receipt returned")
        } catch let failure as ItemSpaceClearingFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await mismatch.recordedCommands().count == 1)
    }

    @Test("Every caller field changes only literal encoded owners")
    func reciprocalLiteralEncodedLeafOwnership() async throws {
        let baseline = try await Self.recordedCommand()
        let fields = try Self.flattenedFields(baseline)
        #expect(fields == Self.literalBaselineFields)

        let variants: [(ClearItemSpaceAssignmentsCommand, Set<String>)] = [
            (try await Self.recordedCommand(accountID: "account-other"), [
                "draft.accountId", "envelope.accountId", "fingerprint"
            ]),
            (try await Self.recordedCommand(scope: .businessInventory),
                Self.scopeChangedLeaves),
            (try await Self.recordedCommand(items: [
                ("item-beta", 4, "space-library"),
                ("item-zeta", 9, "space-studio")
            ]), [
                "draft.items.0.itemId", "envelope.payload.itemIds.0",
                "envelope.preconditions.2.expectedRevision.subject.id",
                "envelope.preconditions.3.expectedRelationship.subject.id",
                "envelope.preconditions.4.expectedRelationship.subject.id", "fingerprint"
            ]),
            (try await Self.recordedCommand(items: [
                ("item-alpha", 5, "space-library"),
                ("item-zeta", 9, "space-studio")
            ]), [
                "draft.items.0.expectedRevision.rawValue",
                "envelope.preconditions.2.expectedRevision.revision", "fingerprint"
            ]),
            (try await Self.recordedCommand(items: [
                ("item-alpha", 4, "space-museum"),
                ("item-zeta", 9, "space-studio")
            ]), [
                "draft.items.0.currentSpaceId",
                "envelope.preconditions.0.expectedRelationship.subject.id",
                "envelope.preconditions.4.expectedRelationship.target.id", "fingerprint"
            ]),
            (try await Self.recordedCommand(items: [
                ("item-alpha", 4, "space-library"),
                ("item-zulu", 9, "space-studio")
            ]), [
                "draft.items.1.itemId", "envelope.payload.itemIds.1",
                "envelope.preconditions.5.expectedRevision.subject.id",
                "envelope.preconditions.6.expectedRelationship.subject.id",
                "envelope.preconditions.7.expectedRelationship.subject.id", "fingerprint"
            ]),
            (try await Self.recordedCommand(items: [
                ("item-alpha", 4, "space-library"),
                ("item-zeta", 10, "space-studio")
            ]), [
                "draft.items.1.expectedRevision.rawValue",
                "envelope.preconditions.5.expectedRevision.revision", "fingerprint"
            ]),
            (try await Self.recordedCommand(items: [
                ("item-alpha", 4, "space-library"),
                ("item-zeta", 9, "space-warehouse")
            ]), [
                "draft.items.1.currentSpaceId",
                "envelope.preconditions.1.expectedRelationship.subject.id",
                "envelope.preconditions.7.expectedRelationship.target.id", "fingerprint"
            ]),
            (try await Self.recordedCommand(operationID: "operation-other"), [
                "envelope.operationId", "fingerprint"
            ]),
            (try await Self.recordedCommand(actorID: "principal-other"), [
                "draft.actorPrincipalId", "envelope.actorPrincipalId", "fingerprint"
            ]),
            (try await Self.recordedCommand(contractVersion: "item-space-clear-v2"), [
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

    @Test("All fifteen typed failures and cancellation retain their exact boundaries")
    func exhaustiveFailureMapping() async throws {
        let failures: [(ItemSpaceClearingFailure, String)] = [
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
        #expect(failures.count == 15)
        #expect(Set(failures.map(\.0)).count == 15)
        #expect(Set(failures.map(\.1)).count == 15)

        for (failure, code) in failures {
            #expect(failure.diagnosticCode == code)
            let clearer = RecordingItemSpaceClearer(response: .typedFailure(failure))
            do {
                _ = try await Self.execute(
                    using: clearer,
                    operationID: "operation-\(code)"
                )
                Issue.record("Typed failure returned a receipt")
            } catch let received as ItemSpaceClearingFailure {
                #expect(received == failure)
            }
            #expect(await clearer.recordedCommands().count == 1)
        }

        let cancelled = RecordingItemSpaceClearer(response: .cancelled)
        do {
            _ = try await Self.execute(using: cancelled, operationID: "operation-cancelled")
            Issue.record("Cancellation returned a receipt")
        } catch is CancellationError {
            // Expected structured-concurrency control flow.
        } catch {
            Issue.record("Cancellation was rewritten as \(error)")
        }
        #expect(await cancelled.recordedCommands().count == 1)

        let raw = RecordingItemSpaceClearer(response: .rawFailure)
        do {
            _ = try await Self.execute(using: raw, operationID: "operation-raw")
            Issue.record("Unknown port error returned a receipt")
        } catch let failure as ItemSpaceClearingFailure {
            #expect(failure == .localAcceptanceFailed)
        }
        #expect(await raw.recordedCommands().count == 1)

        for code in failures.map(\.1) {
            for secret in [
                "account-space-use-case", "project-baseline", "space-library",
                "item-alpha", "principal-space-use-case", "raw-provider-detail",
                "credential", "service-role", "production"
            ] {
                #expect(!code.contains(secret))
            }
        }
    }

    @Test("Nested command topology stays inside clear-only composition")
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
            "scope", "items", "capturedAt"
        ])
        let draftItems = try #require(draft["items"] as? [[String: Any]])
        #expect(draftItems.count == 2)
        #expect(draftItems.allSatisfy {
            Set($0.keys) == ["itemId", "expectedRevision", "currentSpaceId"]
        })
        #expect(draftItems.allSatisfy {
            (($0["expectedRevision"] as? [String: Any]).map { Set($0.keys) }) == ["rawValue"]
        })

        let envelope = try #require(root["envelope"] as? [String: Any])
        #expect(Set(envelope.keys) == [
            "operationId", "contractVersion", "accountId", "actorPrincipalId",
            "clientCreatedAt", "payload", "preconditions"
        ])
        let payload = try #require(envelope["payload"] as? [String: Any])
        #expect(Set(payload.keys) == ["scope", "itemIds"])
        let preconditions = try #require(envelope["preconditions"] as? [[String: Any]])
        #expect(preconditions.count == 8)
        #expect(preconditions.prefix(2).allSatisfy {
            Set($0.keys) == ["expectedRelationship"]
        })
        #expect(Set(preconditions[2].keys) == ["expectedRevision"])
        #expect(Set(preconditions[3].keys) == ["expectedRelationship"])
        #expect(Set(preconditions[4].keys) == ["expectedRelationship"])
        #expect(Set(preconditions[5].keys) == ["expectedRevision"])
        #expect(Set(preconditions[6].keys) == ["expectedRelationship"])
        #expect(Set(preconditions[7].keys) == ["expectedRelationship"])

        var keys = Set<String>()
        Self.collectKeys(root, into: &keys)
        let forbiddenKeys: Set<String> = [
            "destinationSpaceId", "displayName", "spaceName", "route", "backendPath",
            "authorization", "authorized", "attachment", "media", "image", "marker",
            "archive", "sourceScope", "destinationScope", "transaction", "occurrence",
            "invoice", "budget", "amount", "price", "payer", "accounting", "provenance",
            "uiState", "service", "provider", "credential", "token", "serverResult"
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
        items: [(String, UInt64, String)] = [
            ("item-alpha", 4, "space-library"),
            ("item-zeta", 9, "space-studio")
        ]
    ) throws -> ItemSpaceClearingIntent {
        ItemSpaceClearingIntent(
            accountId: try AccountID(validating: accountID),
            scope: scope,
            items: try items.map {
                ItemSpaceClearingCandidate(
                    itemId: try ItemID(validating: $0.0),
                    expectedRevision: ExpectedItemPlacementRevision($0.1),
                    currentSpaceId: try SpaceID(validating: $0.2)
                )
            }
        )
    }

    private static func execute(
        using clearer: RecordingItemSpaceClearer,
        operationID: String
    ) async throws -> OperationReceipt {
        try await ItemSpaceClearingUseCase(clearer: clearer).execute(
            input: intent(),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: "principal-space-use-case"),
            operationContractVersion: OperationContractVersion(
                validating: "item-space-clearing-use-case-v1"
            ),
            capturedAt: t0
        )
    }

    private static func recordedCommand(
        accountID: String = "account-space-use-case",
        scope: ItemPlacementScope = .project(try! ProjectID(validating: "project-baseline")),
        items: [(String, UInt64, String)] = [
            ("item-alpha", 4, "space-library"),
            ("item-zeta", 9, "space-studio")
        ],
        operationID: String = "operation-space-clearing-use-case",
        actorID: String = "principal-space-use-case",
        contractVersion: String = "item-space-clearing-use-case-v1",
        capturedAt: Date = t0
    ) async throws -> ClearItemSpaceAssignmentsCommand {
        let clearer = RecordingItemSpaceClearer(response: .matching(.queued))
        _ = try await ItemSpaceClearingUseCase(clearer: clearer).execute(
            input: intent(accountID: accountID, scope: scope, items: items),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: actorID),
            operationContractVersion: OperationContractVersion(validating: contractVersion),
            capturedAt: capturedAt
        )
        let commands = await clearer.recordedCommands()
        #expect(commands.count == 1)
        return try #require(commands.first)
    }

    private static func expectConstructionFailure(
        _ expected: ItemSpaceClearingFailure,
        clearer: RecordingItemSpaceClearer,
        input: ItemSpaceClearingIntent,
        capturedAt: Date = t0
    ) async {
        do {
            _ = try await ItemSpaceClearingUseCase(clearer: clearer).execute(
                input: input,
                operationId: OperationID(validating: "operation-construction-failure"),
                actorPrincipalId: PrincipalID(validating: "principal-space-use-case"),
                operationContractVersion: OperationContractVersion(
                    validating: "item-space-clearing-use-case-v1"
                ),
                capturedAt: capturedAt
            )
            Issue.record("Construction failure returned a receipt")
        } catch let failure as ItemSpaceClearingFailure {
            #expect(failure == expected)
        } catch {
            Issue.record("Construction failure was rewritten as \(error)")
        }
        #expect(await clearer.recordedCommands().isEmpty)
    }

    private static func changedLeaves(
        from baseline: ClearItemSpaceAssignmentsCommand,
        to variant: ClearItemSpaceAssignmentsCommand
    ) throws -> Set<String> {
        let baselineFields = try flattenedFields(baseline)
        let variantFields = try flattenedFields(variant)
        return Set(baselineFields.keys).union(variantFields.keys).filter {
            baselineFields[$0] != variantFields[$0]
        }
    }

    private static func flattenedFields(
        _ command: ClearItemSpaceAssignmentsCommand
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
        "envelope.preconditions.0.expectedRelationship.relation",
        "envelope.preconditions.0.expectedRelationship.target.id",
        "envelope.preconditions.0.expectedRelationship.target.kind",
        "envelope.preconditions.1.expectedRelationship.relation",
        "envelope.preconditions.1.expectedRelationship.target.id",
        "envelope.preconditions.1.expectedRelationship.target.kind",
        "envelope.preconditions.3.expectedRelationship.relation",
        "envelope.preconditions.3.expectedRelationship.target.id",
        "envelope.preconditions.3.expectedRelationship.target.kind",
        "envelope.preconditions.6.expectedRelationship.relation",
        "envelope.preconditions.6.expectedRelationship.target.id",
        "envelope.preconditions.6.expectedRelationship.target.kind",
        "subject.id", "subject.kind", "fingerprint"
    ]

    private static let literalBaselineFields: [String: String] = [
        "draft.accountId": "string:account-space-use-case",
        "draft.actorPrincipalId": "string:principal-space-use-case",
        "draft.capturedAt": "number:1802300000000",
        "draft.items.0.currentSpaceId": "string:space-library",
        "draft.items.0.expectedRevision.rawValue": "number:4",
        "draft.items.0.itemId": "string:item-alpha",
        "draft.items.1.currentSpaceId": "string:space-studio",
        "draft.items.1.expectedRevision.rawValue": "number:9",
        "draft.items.1.itemId": "string:item-zeta",
        "draft.operationContractVersion": "string:item-space-clearing-use-case-v1",
        "draft.scope.kind": "string:project",
        "draft.scope.projectId": "string:project-baseline",
        "envelope.accountId": "string:account-space-use-case",
        "envelope.actorPrincipalId": "string:principal-space-use-case",
        "envelope.clientCreatedAt": "number:1802300000000",
        "envelope.contractVersion": "string:item-space-clearing-use-case-v1",
        "envelope.operationId": "string:operation-space-clearing-use-case",
        "envelope.payload.itemIds.0": "string:item-alpha",
        "envelope.payload.itemIds.1": "string:item-zeta",
        "envelope.payload.scope.kind": "string:project",
        "envelope.payload.scope.projectId": "string:project-baseline",
        "envelope.preconditions.0.expectedRelationship.relation":
            "string:belongs_to_project",
        "envelope.preconditions.0.expectedRelationship.subject.id":
            "string:space-library",
        "envelope.preconditions.0.expectedRelationship.subject.kind": "string:space",
        "envelope.preconditions.0.expectedRelationship.target.id":
            "string:project-baseline",
        "envelope.preconditions.0.expectedRelationship.target.kind": "string:project",
        "envelope.preconditions.1.expectedRelationship.relation":
            "string:belongs_to_project",
        "envelope.preconditions.1.expectedRelationship.subject.id": "string:space-studio",
        "envelope.preconditions.1.expectedRelationship.subject.kind": "string:space",
        "envelope.preconditions.1.expectedRelationship.target.id":
            "string:project-baseline",
        "envelope.preconditions.1.expectedRelationship.target.kind": "string:project",
        "envelope.preconditions.2.expectedRevision.revision": "number:4",
        "envelope.preconditions.2.expectedRevision.subject.id": "string:item-alpha",
        "envelope.preconditions.2.expectedRevision.subject.kind": "string:item",
        "envelope.preconditions.3.expectedRelationship.relation":
            "string:belongs_to_project",
        "envelope.preconditions.3.expectedRelationship.subject.id": "string:item-alpha",
        "envelope.preconditions.3.expectedRelationship.subject.kind": "string:item",
        "envelope.preconditions.3.expectedRelationship.target.id":
            "string:project-baseline",
        "envelope.preconditions.3.expectedRelationship.target.kind": "string:project",
        "envelope.preconditions.4.expectedRelationship.relation":
            "string:assigned_to_space",
        "envelope.preconditions.4.expectedRelationship.subject.id": "string:item-alpha",
        "envelope.preconditions.4.expectedRelationship.subject.kind": "string:item",
        "envelope.preconditions.4.expectedRelationship.target.id": "string:space-library",
        "envelope.preconditions.4.expectedRelationship.target.kind": "string:space",
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
        "envelope.preconditions.7.expectedRelationship.relation":
            "string:assigned_to_space",
        "envelope.preconditions.7.expectedRelationship.subject.id": "string:item-zeta",
        "envelope.preconditions.7.expectedRelationship.subject.kind": "string:item",
        "envelope.preconditions.7.expectedRelationship.target.id": "string:space-studio",
        "envelope.preconditions.7.expectedRelationship.target.kind": "string:space",
        "fingerprint":
            "string:1b479a9eb6789d2dd497d58b5abae90af3235a7b3e4e037008b8a65d515dc250",
        "subject.id": "string:project-baseline",
        "subject.kind": "string:project"
    ]
}

private enum ItemSpaceClearerResponse: Sendable {
    case matching(LocalOperationState)
    case mismatched(OperationID)
    case typedFailure(ItemSpaceClearingFailure)
    case rawFailure
    case cancelled
}

private actor RecordingItemSpaceClearer: ItemSpaceAssignmentClearing {
    private let response: ItemSpaceClearerResponse
    private var commands: [ClearItemSpaceAssignmentsCommand] = []

    init(response: ItemSpaceClearerResponse) {
        self.response = response
    }

    func clearItemSpaceAssignments(
        _ command: ClearItemSpaceAssignmentsCommand
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
            throw RawItemSpaceClearingPortFailure.transport("raw-provider-detail")
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedCommands() -> [ClearItemSpaceAssignmentsCommand] {
        commands
    }
}

private enum RawItemSpaceClearingPortFailure: Error {
    case transport(String)
}
