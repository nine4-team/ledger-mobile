import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Setup Use Case Contracts")
struct ProjectSetupUseCaseTests {
    @Test("PSETUPUSE-TEST-001 exact matching evidence dispatches complete setup")
    func matchingEvidenceDispatchesExactlyOnce() async throws {
        Self.requireValueCapabilities(ProjectSetupFormSelection.self)
        Self.requireValueCapabilities(ProjectSetupFormPreparation.self)
        Self.requireSendable(ProjectSetupUseCase<RecordingProjectSetup>.self)

        let usd = try CurrencyCode(validating: "USD")
        let eur = try CurrencyCode(validating: "EUR")
        let allocations = try [
            Self.allocation("category-c", Money(minorUnits: 5_000_000_000, currency: eur)),
            Self.allocation("category-a", nil),
            Self.allocation("category-b", Money(minorUnits: 0, currency: usd))
        ]
        let qualities = ListSnapshotQuality.allCases
        for clientQuality in qualities {
            for categoryQuality in qualities {
                let preparation = try Self.preparation(
                    clientQuality: clientQuality,
                    categoryQuality: categoryQuality
                )
                let clientInputs = [
                    ProjectClientSelectionInput.existing(
                        try ClientID(validating: "client-a")
                    ),
                    ProjectClientSelectionInput(
                        newClientId: try ClientID(validating: "client-new"),
                        displayName: try ClientDisplayName(validating: "New Client")
                    )
                ]
                for (index, clientInput) in clientInputs.enumerated() {
                    let selection = try preparation.selection(
                        client: clientInput,
                        projectDisplayName: ProjectDisplayName(
                            validating: "  Exact Project Name  "
                        ),
                        rawDescription: "  Exact description\n",
                        categoryAllocations: allocations
                    )
                    let setup = RecordingProjectSetup(response: .matching(.queued))
                    let operationID = try OperationID(
                        validating: "operation-\(clientQuality)-\(categoryQuality)-\(index)"
                    )
                    let receipt = try await Self.useCase(setup).execute(
                        selection: selection,
                        currentPreparation: preparation,
                        projectId: try ProjectID(validating: "project-new"),
                        operationId: operationID,
                        actorPrincipalId: try PrincipalID(validating: "principal-one"),
                        operationContractVersion: try OperationContractVersion(
                            validating: "project-setup-use-case-v1"
                        ),
                        capturedAt: Self.t5
                    )

                    #expect(receipt == OperationReceipt(
                        operationId: operationID,
                        localState: .queued
                    ))
                    let commands = await setup.recordedCommands()
                    #expect(commands.count == 1)
                    let command = try #require(commands.first)
                    #expect(command.draft.clientSelection == clientInput)
                    #expect(command.draft.displayName.rawValue == "  Exact Project Name  ")
                    #expect(command.draft.description == "Exact description")
                    #expect(command.draft.categoryAllocations == allocations.sorted {
                        $0.categoryId.rawValue < $1.categoryId.rawValue
                    })
                    #expect(command.draft.categoryAllocations[0].allocation == nil)
                    #expect(command.draft.categoryAllocations[1].allocation == Money(
                        minorUnits: 0,
                        currency: usd
                    ))
                    #expect(command.draft.categoryAllocations[2].allocation == Money(
                        minorUnits: 5_000_000_000,
                        currency: eur
                    ))
                    #expect(command.draft.description == "Exact description")
                    #expect(command.envelope.payload.description == "Exact description")
                }
            }
        }

        for (quality, clientInput) in try [
            (ListSnapshotQuality.ready, ProjectClientSelectionInput.existing(
                ClientID(validating: "client-a")
            )),
            (ListSnapshotQuality.partial, ProjectClientSelectionInput(
                newClientId: ClientID(validating: "client-clear-partial"),
                displayName: ClientDisplayName(validating: "Clear Partial")
            )),
            (ListSnapshotQuality.stale, ProjectClientSelectionInput.existing(
                ClientID(validating: "client-b")
            ))
        ] {
            let preparation = try Self.preparation(
                clientQuality: quality,
                categoryQuality: quality
            )
            let selection = try preparation.selection(
                client: clientInput,
                projectDisplayName: ProjectDisplayName(validating: "No Categories"),
                rawDescription: nil,
                categoryAllocations: []
            )
            let setup = RecordingProjectSetup(response: .matching(.applied))
            _ = try await Self.execute(
                using: setup,
                selection: selection,
                preparation: preparation,
                operationID: "operation-empty-\(quality)"
            )
            let commands = await setup.recordedCommands()
            #expect(commands.count == 1)
            let command = try #require(commands.first)
            #expect(command.draft.categoryAllocations.isEmpty)
            #expect(command.draft.description == nil)
            #expect(command.envelope.payload.description == nil)
        }
    }

    @Test("PSETUPUSE-TEST-002 derivation failures make zero calls")
    func changedEvidenceAndInvalidTimeDoNotDispatch() async throws {
        let original = try Self.preparation()
        let selection = try Self.selection(preparation: original)
        let changedPreparations = try Self.changedPreparations()
        #expect(changedPreparations.count == 32)
        for (index, changed) in changedPreparations.enumerated() {
            let setup = RecordingProjectSetup(response: .matching(.queued))
            do {
                _ = try await Self.execute(
                    using: setup,
                    selection: selection,
                    preparation: changed,
                    operationID: "operation-changed-\(index)"
                )
                Issue.record("Changed preparation dispatched at index \(index)")
            } catch let failure as ProjectSetupFormFailure {
                #expect(failure == .selectionPreparationMismatch)
            } catch {
                Issue.record("Unexpected changed-evidence error: \(error)")
            }
            #expect(await setup.recordedCommands().isEmpty)
        }

        for (index, interval) in [Double.infinity, -Double.infinity, Double.nan].enumerated() {
            let setup = RecordingProjectSetup(response: .matching(.queued))
            do {
                _ = try await Self.useCase(setup).execute(
                    selection: selection,
                    currentPreparation: original,
                    projectId: try ProjectID(validating: "project-new"),
                    operationId: try OperationID(validating: "operation-time-\(index)"),
                    actorPrincipalId: try PrincipalID(validating: "principal-one"),
                    operationContractVersion: try OperationContractVersion(
                        validating: "project-setup-use-case-v1"
                    ),
                    capturedAt: Date(timeIntervalSinceReferenceDate: interval)
                )
                Issue.record("Nonfinite capture time dispatched")
            } catch let failure as ProjectSetupFailure {
                #expect(failure == .invalidProjectCreatedAt)
            }
            #expect(await setup.recordedCommands().isEmpty)
        }
    }

    @Test("PSETUPUSE-TEST-003 every local state returns in the exact receipt")
    func exactReceiptsAndMismatch() async throws {
        let preparation = try Self.preparation()
        let selection = try Self.selection(preparation: preparation)
        for state in LocalOperationState.allCases {
            let setup = RecordingProjectSetup(response: .matching(state))
            let operationID = "operation-state-\(state.rawValue)"
            let receipt = try await Self.execute(
                using: setup,
                selection: selection,
                preparation: preparation,
                operationID: operationID
            )
            #expect(receipt == OperationReceipt(
                operationId: try OperationID(validating: operationID),
                localState: state
            ))
            let commands = await setup.recordedCommands()
            #expect(commands.count == 1)
            let command = try #require(commands.first)
            #expect(command.subject.kind == .project)
            #expect(command.subject.id.rawValue == "project-new")
            #expect(command.envelope.preconditions.isEmpty)
            #expect(command.envelope.payload.categoryAllocations ==
                command.draft.categoryAllocations)
        }

        let mismatch = RecordingProjectSetup(response: .mismatched(
            try OperationID(validating: "operation-wrong")
        ))
        do {
            _ = try await Self.execute(
                using: mismatch,
                selection: selection,
                preparation: preparation,
                operationID: "operation-mismatch"
            )
            Issue.record("Mismatched receipt returned")
        } catch let failure as ProjectSetupFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await mismatch.recordedCommands().count == 1)
    }

    @Test("PSETUPUSE-TEST-004 reciprocal fields reach only existing owners")
    func reciprocalFieldsAndPreparationNonLeakage() async throws {
        let baseline = try await Self.recordedCommand()
        let accountPreparation = try Self.preparation(account: "account-other")
        let account = try await Self.recordedCommand(preparation: accountPreparation)
        let project = try await Self.recordedCommand(projectID: "project-other")
        let existingClient = try await Self.recordedCommand(
            clientInput: .existing(ClientID(validating: "client-b"))
        )
        let newClientPreparation = try Self.preparation(
            clientRows: Array(Self.defaultClients().dropFirst())
        )
        let newClient = try await Self.recordedCommand(
            preparation: newClientPreparation,
            clientInput: ProjectClientSelectionInput(
                newClientId: ClientID(validating: "client-a"),
                displayName: ClientDisplayName(validating: "New Client")
            )
        )
        let projectName = try await Self.recordedCommand(
            projectName: "Different Project"
        )
        let description = try await Self.recordedCommand(
            rawDescription: "Different description"
        )
        let noDescription = try await Self.recordedCommand(rawDescription: nil)
        let operation = try await Self.recordedCommand(operationID: "operation-other")
        let actor = try await Self.recordedCommand(actor: "principal-other")
        let contract = try await Self.recordedCommand(contract: "project-setup-v2")
        let time = try await Self.recordedCommand(capturedAt: Self.t6)

        let categoryIdentityPreparation = try Self.preparation(categoryRows: [
            Self.category("category-aa", name: "Category A", order: 10),
            Self.category("category-b", name: "Category B", order: 20),
            Self.category("category-c", name: "Category C", order: 30),
            Self.category("category-system", name: "System", order: 40, isSystem: true),
            Self.category(
                "category-archived",
                name: "Archived",
                order: 50,
                lifecycle: .archived
            )
        ])
        let categoryIdentity = try await Self.recordedCommand(
            preparation: categoryIdentityPreparation,
            allocations: Self.baselineAllocations(firstCategory: "category-aa")
        )
        let categoryAbsent = try await Self.recordedCommand(
            allocations: Array(try Self.baselineAllocations().dropLast())
        )
        var nullToZeroAllocations = try Self.baselineAllocations()
        nullToZeroAllocations[0] = try Self.allocation(
            "category-a",
            Money(minorUnits: 0, currency: CurrencyCode(validating: "USD"))
        )
        let nullToZero = try await Self.recordedCommand(
            allocations: nullToZeroAllocations
        )
        var minorUnitAllocations = try Self.baselineAllocations()
        minorUnitAllocations[1] = try Self.allocation(
            "category-b",
            Money(minorUnits: 99, currency: CurrencyCode(validating: "USD"))
        )
        let minorUnits = try await Self.recordedCommand(allocations: minorUnitAllocations)
        var currencyAllocations = try Self.baselineAllocations()
        currencyAllocations[1] = try Self.allocation(
            "category-b",
            Money(minorUnits: 0, currency: CurrencyCode(validating: "CAD"))
        )
        let currency = try await Self.recordedCommand(allocations: currencyAllocations)

        let variants: [(CreateProjectCommand, Set<String>)] = [
            (account, ["draft.accountId", "envelope.accountId", "fingerprint"]),
            (project, [
                "draft.projectId", "envelope.payload.projectId", "subject.id", "fingerprint"
            ]),
            (existingClient, [
                "draft.clientSelection.clientId",
                "envelope.payload.clientSelection.clientId", "fingerprint"
            ]),
            (newClient, [
                "draft.clientSelection.kind",
                "draft.clientSelection.displayName",
                "envelope.payload.clientSelection.kind",
                "envelope.payload.clientSelection.displayName", "fingerprint"
            ]),
            (projectName, [
                "draft.displayName", "envelope.payload.displayName", "fingerprint"
            ]),
            (description, [
                "draft.description", "envelope.payload.description", "fingerprint"
            ]),
            (noDescription, [
                "draft.description", "envelope.payload.description", "fingerprint"
            ]),
            (categoryIdentity, [
                "draft.categoryAllocations.0.categoryId",
                "envelope.payload.categoryAllocations.0.categoryId", "fingerprint"
            ]),
            (categoryAbsent, [
                "draft.categoryAllocations.2.categoryId",
                "draft.categoryAllocations.2.allocation.currency",
                "draft.categoryAllocations.2.allocation.minorUnits",
                "envelope.payload.categoryAllocations.2.categoryId",
                "envelope.payload.categoryAllocations.2.allocation.currency",
                "envelope.payload.categoryAllocations.2.allocation.minorUnits", "fingerprint"
            ]),
            (nullToZero, [
                "draft.categoryAllocations.0.allocation.currency",
                "draft.categoryAllocations.0.allocation.minorUnits",
                "envelope.payload.categoryAllocations.0.allocation.currency",
                "envelope.payload.categoryAllocations.0.allocation.minorUnits", "fingerprint"
            ]),
            (minorUnits, [
                "draft.categoryAllocations.1.allocation.minorUnits",
                "envelope.payload.categoryAllocations.1.allocation.minorUnits", "fingerprint"
            ]),
            (currency, [
                "draft.categoryAllocations.1.allocation.currency",
                "envelope.payload.categoryAllocations.1.allocation.currency", "fingerprint"
            ]),
            (operation, ["envelope.operationId", "fingerprint"]),
            (actor, [
                "draft.actorPrincipalId", "envelope.actorPrincipalId", "fingerprint"
            ]),
            (contract, [
                "draft.operationContractVersion", "envelope.contractVersion", "fingerprint"
            ]),
            (time, ["draft.capturedAt", "envelope.clientCreatedAt", "fingerprint"])
        ]
        for (variant, expectedDelta) in variants {
            #expect(variant != baseline)
            #expect(variant.envelope.payload.categoryAllocations ==
                variant.draft.categoryAllocations)
            #expect(variant.fingerprint == (try OperationFingerprint.make(
                for: variant.envelope
            )))
            #expect(try Self.fieldDelta(from: baseline, to: variant) == expectedDelta)
        }

        let newID = try await Self.recordedCommand(clientInput: ProjectClientSelectionInput(
            newClientId: ClientID(validating: "client-other"),
            displayName: ClientDisplayName(validating: "New Client")
        ))
        let newName = try await Self.recordedCommand(
            preparation: newClientPreparation,
            clientInput: ProjectClientSelectionInput(
                newClientId: ClientID(validating: "client-a"),
                displayName: ClientDisplayName(validating: "Renamed New Client")
            )
        )
        #expect(try Self.fieldDelta(from: newClient, to: newID) == [
            "draft.clientSelection.clientId",
            "envelope.payload.clientSelection.clientId", "fingerprint"
        ])
        #expect(try Self.fieldDelta(from: newClient, to: newName) == [
            "draft.clientSelection.displayName",
            "envelope.payload.clientSelection.displayName", "fingerprint"
        ])

        let noDescriptionObject = try #require(JSONSerialization.jsonObject(
            with: OperationContractCodec.encode(noDescription)
        ) as? [String: Any])
        let noDescriptionDraft = try #require(
            noDescriptionObject["draft"] as? [String: Any]
        )
        #expect(noDescriptionDraft["description"] == nil)
        let noDescriptionEnvelope = try #require(
            noDescriptionObject["envelope"] as? [String: Any]
        )
        let noDescriptionPayload = try #require(
            noDescriptionEnvelope["payload"] as? [String: Any]
        )
        #expect(noDescriptionPayload["description"] == nil)

        let orderedAllocations = try Self.baselineAllocations()
        let reordered = try await Self.recordedCommand(allocations: [
            orderedAllocations[2], orderedAllocations[0], orderedAllocations[1]
        ])
        #expect(reordered == baseline)
        #expect(try Self.fieldDelta(from: baseline, to: reordered).isEmpty)

        let equivalentPreparations = try Self.equivalentIntentPreparations()
        #expect(equivalentPreparations.count == 16)
        for preparation in equivalentPreparations {
            let command = try await Self.recordedCommand(preparation: preparation)
            #expect(command == baseline)
            #expect(try Self.fieldDelta(from: baseline, to: command).isEmpty)
        }
    }

    @Test("PSETUPUSE-TEST-005 every typed failure and cancellation stays distinct")
    func exhaustiveFailureMapping() async throws {
        let preparation = try Self.preparation()
        let selection = try Self.selection(preparation: preparation)
        let formFailures: [ProjectSetupFormFailure] = [
            .accountScopeMismatch, .clientNotSelectable, .newClientIdentityCollision,
            .categoryNotSelectable, .duplicateCategoryIdentity,
            .invalidPreparationFingerprint, .invalidSelectionFingerprint,
            .preparationFingerprintMismatch, .selectionFingerprintMismatch,
            .selectionPreparationMismatch, .invalidEncodedPreparation,
            .invalidEncodedSelection
        ]
        #expect(formFailures.count == 12)
        for (index, expected) in formFailures.enumerated() {
            let setup = RecordingProjectSetup(response: .formFailure(expected))
            do {
                _ = try await Self.execute(
                    using: setup,
                    selection: selection,
                    preparation: preparation,
                    operationID: "operation-form-failure-\(index)"
                )
                Issue.record("Form failure returned a receipt")
            } catch let failure as ProjectSetupFormFailure {
                #expect(failure == expected)
            } catch {
                Issue.record("Unexpected form-failure type: \(error)")
            }
            #expect(await setup.recordedCommands().count == 1)
        }

        let setupFailures: [ProjectSetupFailure] = [
            .invalidClientSelection, .negativeCategoryAllocation, .duplicateCategoryIdentity,
            .invalidProjectCreatedAt, .draftAccountMismatch, .draftActorMismatch,
            .draftContractMismatch, .draftPayloadMismatch, .unexpectedPreconditions,
            .subjectMismatch, .fingerprintMismatch, .receiptMismatch,
            .localAcceptanceFailed, .invalidEncodedCategoryAllocation,
            .invalidEncodedDraft, .invalidEncodedCommand
        ]
        #expect(setupFailures.count == 16)
        for (index, expected) in setupFailures.enumerated() {
            let setup = RecordingProjectSetup(response: .setupFailure(expected))
            do {
                _ = try await Self.execute(
                    using: setup,
                    selection: selection,
                    preparation: preparation,
                    operationID: "operation-setup-failure-\(index)"
                )
                Issue.record("Setup failure returned a receipt")
            } catch let failure as ProjectSetupFailure {
                #expect(failure == expected)
            } catch {
                Issue.record("Unexpected setup-failure type: \(error)")
            }
            #expect(await setup.recordedCommands().count == 1)
        }

        let cancelled = RecordingProjectSetup(response: .cancelled)
        do {
            _ = try await Self.execute(
                using: cancelled,
                selection: selection,
                preparation: preparation,
                operationID: "operation-cancelled"
            )
            Issue.record("Cancellation returned a receipt")
        } catch is CancellationError {
        } catch {
            Issue.record("Cancellation changed type: \(error)")
        }
        #expect(await cancelled.recordedCommands().count == 1)

        let raw = RecordingProjectSetup(response: .rawFailure)
        do {
            _ = try await Self.execute(
                using: raw,
                selection: selection,
                preparation: preparation,
                operationID: "operation-raw"
            )
            Issue.record("Raw failure returned a receipt")
        } catch let failure as ProjectSetupFailure {
            #expect(failure == .localAcceptanceFailed)
        } catch {
            Issue.record("Raw failure escaped: \(error)")
        }
        #expect(await raw.recordedCommands().count == 1)
    }

    @Test("PSETUPUSE-TEST-006 diagnostics and encoding stay inside setup intent")
    func diagnosticsEncodingAndExclusions() async throws {
        let diagnostics: [(String, String)] = [
            (ProjectSetupFormFailure.accountScopeMismatch.diagnosticCode,
             "project_setup_form_account_scope_mismatch"),
            (ProjectSetupFormFailure.clientNotSelectable.diagnosticCode,
             "project_setup_form_client_not_selectable"),
            (ProjectSetupFormFailure.newClientIdentityCollision.diagnosticCode,
             "project_setup_form_new_client_identity_collision"),
            (ProjectSetupFormFailure.categoryNotSelectable.diagnosticCode,
             "project_setup_form_category_not_selectable"),
            (ProjectSetupFormFailure.duplicateCategoryIdentity.diagnosticCode,
             "project_setup_form_category_identity_duplicate"),
            (ProjectSetupFormFailure.invalidPreparationFingerprint.diagnosticCode,
             "project_setup_form_preparation_fingerprint_invalid"),
            (ProjectSetupFormFailure.invalidSelectionFingerprint.diagnosticCode,
             "project_setup_form_selection_fingerprint_invalid"),
            (ProjectSetupFormFailure.preparationFingerprintMismatch.diagnosticCode,
             "project_setup_form_preparation_fingerprint_mismatch"),
            (ProjectSetupFormFailure.selectionFingerprintMismatch.diagnosticCode,
             "project_setup_form_selection_fingerprint_mismatch"),
            (ProjectSetupFormFailure.selectionPreparationMismatch.diagnosticCode,
             "project_setup_form_selection_preparation_mismatch"),
            (ProjectSetupFormFailure.invalidEncodedPreparation.diagnosticCode,
             "project_setup_form_preparation_encoding_invalid"),
            (ProjectSetupFormFailure.invalidEncodedSelection.diagnosticCode,
             "project_setup_form_selection_encoding_invalid"),
            (ProjectSetupFailure.invalidClientSelection.diagnosticCode,
             "project_setup_client_selection_invalid"),
            (ProjectSetupFailure.negativeCategoryAllocation.diagnosticCode,
             "project_setup_category_allocation_negative"),
            (ProjectSetupFailure.duplicateCategoryIdentity.diagnosticCode,
             "project_setup_category_identity_duplicate"),
            (ProjectSetupFailure.invalidProjectCreatedAt.diagnosticCode,
             "project_setup_created_at_invalid"),
            (ProjectSetupFailure.draftAccountMismatch.diagnosticCode,
             "project_setup_account_mismatch"),
            (ProjectSetupFailure.draftActorMismatch.diagnosticCode,
             "project_setup_actor_mismatch"),
            (ProjectSetupFailure.draftContractMismatch.diagnosticCode,
             "project_setup_contract_mismatch"),
            (ProjectSetupFailure.draftPayloadMismatch.diagnosticCode,
             "project_setup_payload_mismatch"),
            (ProjectSetupFailure.unexpectedPreconditions.diagnosticCode,
             "project_setup_preconditions_unexpected"),
            (ProjectSetupFailure.subjectMismatch.diagnosticCode,
             "project_setup_subject_mismatch"),
            (ProjectSetupFailure.fingerprintMismatch.diagnosticCode,
             "project_setup_fingerprint_mismatch"),
            (ProjectSetupFailure.receiptMismatch.diagnosticCode,
             "project_setup_receipt_mismatch"),
            (ProjectSetupFailure.localAcceptanceFailed.diagnosticCode,
             "project_setup_local_acceptance_failed"),
            (ProjectSetupFailure.invalidEncodedCategoryAllocation.diagnosticCode,
             "project_setup_category_allocation_encoding_invalid"),
            (ProjectSetupFailure.invalidEncodedDraft.diagnosticCode,
             "project_setup_draft_encoding_invalid"),
            (ProjectSetupFailure.invalidEncodedCommand.diagnosticCode,
             "project_setup_command_encoding_invalid")
        ]
        #expect(diagnostics.count == 28)
        for (actual, expected) in diagnostics {
            #expect(actual == expected)
            #expect(actual.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" })
        }

        let command = try await Self.recordedCommand()
        let bytes = try OperationContractCodec.encode(command)
        let object = try #require(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        #expect(Set(object.keys) == ["draft", "envelope", "fingerprint", "subject"])
        #expect((object["fingerprint"] as? String)?.count == 64)
        let draft = try #require(object["draft"] as? [String: Any])
        #expect(Set(draft.keys) == [
            "accountId", "actorPrincipalId", "operationContractVersion", "projectId",
            "clientSelection", "displayName", "description", "categoryAllocations",
            "capturedAt"
        ])
        let envelope = try #require(object["envelope"] as? [String: Any])
        #expect(Set(envelope.keys) == [
            "operationId", "contractVersion", "accountId", "actorPrincipalId",
            "clientCreatedAt", "payload", "preconditions"
        ])
        let payload = try #require(envelope["payload"] as? [String: Any])
        #expect(Set(payload.keys) == [
            "projectId", "clientSelection", "displayName", "description",
            "categoryAllocations"
        ])
        #expect((envelope["preconditions"] as? [Any])?.isEmpty == true)
        let subject = try #require(object["subject"] as? [String: Any])
        #expect(Set(subject.keys) == ["kind", "id"])
        #expect(subject["kind"] as? String == "project")

        for container in [draft, payload] {
            let client = try #require(container["clientSelection"] as? [String: Any])
            #expect(Set(client.keys) == ["kind", "clientId"])
            let allocations = try #require(
                container["categoryAllocations"] as? [[String: Any]]
            )
            #expect(allocations.count == 3)
            #expect(Set(allocations[0].keys) == ["categoryId"])
            for allocation in allocations.dropFirst() {
                #expect(Set(allocation.keys) == ["categoryId", "allocation"])
                let money = try #require(allocation["allocation"] as? [String: Any])
                #expect(Set(money.keys) == ["minorUnits", "currency"])
            }
        }

        let newCommand = try await Self.recordedCommand(
            clientInput: ProjectClientSelectionInput(
                newClientId: ClientID(validating: "client-new"),
                displayName: ClientDisplayName(validating: "New Client")
            )
        )
        let newObject = try #require(JSONSerialization.jsonObject(
            with: OperationContractCodec.encode(newCommand)
        ) as? [String: Any])
        let newDraft = try #require(newObject["draft"] as? [String: Any])
        let newClient = try #require(newDraft["clientSelection"] as? [String: Any])
        #expect(Set(newClient.keys) == ["kind", "clientId", "displayName"])
        let newEnvelope = try #require(newObject["envelope"] as? [String: Any])
        let newPayload = try #require(newEnvelope["payload"] as? [String: Any])
        let newPayloadClient = try #require(
            newPayload["clientSelection"] as? [String: Any]
        )
        #expect(Set(newPayloadClient.keys) == ["kind", "clientId", "displayName"])

        let encoded = String(decoding: bytes, as: UTF8.self).lowercased()
        for required in [
            "account-one", "project-new", "client-a", "category-a", "category-b",
            "category-c", "baseline project", "baseline description", "operation-one",
            "principal-one", "project-setup-use-case-v1"
        ] {
            #expect(encoded.contains(required))
        }
        let forbidden = [
            "preparation", "readiness", "completeness", "localdataversion",
            "queryfingerprint", "evidencefingerprint", "selectionfingerprint",
            "defaultselection", "categorydefinition", "attachment", "heroimage",
            "lifecycle", "archive", "delete", "merge", "reassign", "correction",
            "accounting", "history", "swiftui", "route", "credential", "bearer",
            "token", "secret", ["fire", "base"].joined(), ["fire", "store"].joined(),
            ["supa", "base"].joined(), ["power", "sync"].joined(),
            ["pro", "vider"].joined(),
            ["private", "adapter", "detail"].joined(separator: "-"),
            "https://", "file://"
        ]
        for value in forbidden {
            #expect(!encoded.contains(value))
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_803_100_000)
    private static let t1 = Date(timeIntervalSince1970: 1_803_100_001)
    private static let t2 = Date(timeIntervalSince1970: 1_803_100_002)
    private static let t3 = Date(timeIntervalSince1970: 1_803_100_003)
    private static let t4 = Date(timeIntervalSince1970: 1_803_100_004)
    private static let t5 = Date(timeIntervalSince1970: 1_803_100_005)
    private static let t6 = Date(timeIntervalSince1970: 1_803_100_006)

    private static func requireSendable<Value: Sendable>(_: Value.Type) {}

    private static func requireValueCapabilities<
        Value: Codable & Equatable & Sendable
    >(_: Value.Type) {}

    private static func useCase(
        _ setup: RecordingProjectSetup
    ) -> ProjectSetupUseCase<RecordingProjectSetup> {
        ProjectSetupUseCase(setup: setup)
    }

    private static func execute(
        using setup: RecordingProjectSetup,
        selection: ProjectSetupFormSelection,
        preparation: ProjectSetupFormPreparation,
        operationID: String
    ) async throws -> OperationReceipt {
        try await useCase(setup).execute(
            selection: selection,
            currentPreparation: preparation,
            projectId: ProjectID(validating: "project-new"),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: "principal-one"),
            operationContractVersion: OperationContractVersion(
                validating: "project-setup-use-case-v1"
            ),
            capturedAt: t5
        )
    }

    private static func selection(
        preparation: ProjectSetupFormPreparation,
        clientInput: ProjectClientSelectionInput? = nil,
        projectName: String = "Baseline Project",
        rawDescription: String? = " Baseline description ",
        allocations: [NullableCategoryAllocation]? = nil
    ) throws -> ProjectSetupFormSelection {
        try preparation.selection(
            client: try clientInput ?? .existing(ClientID(validating: "client-a")),
            projectDisplayName: ProjectDisplayName(validating: projectName),
            rawDescription: rawDescription,
            categoryAllocations: try allocations ?? baselineAllocations()
        )
    }

    private static func recordedCommand(
        preparation suppliedPreparation: ProjectSetupFormPreparation? = nil,
        clientInput: ProjectClientSelectionInput? = nil,
        projectName: String = "Baseline Project",
        rawDescription: String? = " Baseline description ",
        allocations: [NullableCategoryAllocation]? = nil,
        projectID: String = "project-new",
        operationID: String = "operation-one",
        actor: String = "principal-one",
        contract: String = "project-setup-use-case-v1",
        capturedAt: Date = t5
    ) async throws -> CreateProjectCommand {
        let preparation = try suppliedPreparation ?? self.preparation()
        let selection = try self.selection(
            preparation: preparation,
            clientInput: clientInput,
            projectName: projectName,
            rawDescription: rawDescription,
            allocations: allocations
        )
        let setup = RecordingProjectSetup(response: .matching(.queued))
        _ = try await useCase(setup).execute(
            selection: selection,
            currentPreparation: preparation,
            projectId: ProjectID(validating: projectID),
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: actor),
            operationContractVersion: OperationContractVersion(validating: contract),
            capturedAt: capturedAt
        )
        let commands = await setup.recordedCommands()
        #expect(commands.count == 1)
        return try #require(commands.first)
    }

    private static func client(
        _ id: String,
        account: String = "account-one",
        name: String = "Client Name",
        lifecycle: DirectoryLifecycleState = .active,
        createdAt: Date = t0,
        updatedAt: Date = t1
    ) throws -> ClientSummary {
        try ClientSummary(
            id: ClientID(validating: id),
            accountId: AccountID(validating: account),
            displayName: ClientDisplayName(validating: name),
            lifecycle: lifecycle,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func category(
        _ id: String,
        account: String = "account-one",
        name: String,
        kind: BudgetCategoryKind = .general,
        order: UInt32,
        lifecycle: DirectoryLifecycleState = .active,
        isSystem: Bool = false,
        excludes: Bool = false,
        revision: UInt64 = 1
    ) throws -> BudgetCategoryDefinitionSnapshot {
        BudgetCategoryDefinitionSnapshot(
            id: try BudgetCategoryID(validating: id),
            accountId: try AccountID(validating: account),
            name: try BudgetCategoryName(validating: name),
            kind: kind,
            lifecycle: lifecycle,
            isSystem: isSystem,
            excludesFromOverallBudget: excludes,
            presentationOrder: order,
            revision: revision
        )
    }

    private static func defaultClients(account: String = "account-one") throws -> [ClientSummary] {
        try [
            client("client-a", account: account, name: "Client A"),
            client("client-b", account: account, name: "Client B"),
            client(
                "client-archived",
                account: account,
                name: "Archived Client",
                lifecycle: .archived
            )
        ]
    }

    private static func defaultCategories(
        account: String = "account-one"
    ) throws -> [BudgetCategoryDefinitionSnapshot] {
        try [
            category("category-a", account: account, name: "Category A", order: 10),
            category("category-b", account: account, name: "Category B", order: 20),
            category("category-c", account: account, name: "Category C", order: 30),
            category(
                "category-system",
                account: account,
                name: "System",
                order: 40,
                isSystem: true
            ),
            category(
                "category-archived",
                account: account,
                name: "Archived",
                order: 50,
                lifecycle: .archived
            )
        ]
    }

    private static func preparation(
        account: String = "account-one",
        clientRows: [ClientSummary]? = nil,
        clientVisibleCount: Int? = nil,
        clientQuality: ListSnapshotQuality = .ready,
        clientComplete: Bool? = nil,
        clientVersion: String = "clients-one",
        clientAsOf: Date = t1,
        clientQuerySeed: Character = "1",
        categoryRows: [BudgetCategoryDefinitionSnapshot]? = nil,
        categoryQuality: ListSnapshotQuality = .ready,
        categoryComplete: Bool? = nil,
        categoryVersion: String = "categories-one",
        categoryAsOf: Date = t2,
        categoryQuerySeed: Character = "2"
    ) throws -> ProjectSetupFormPreparation {
        let resolvedClients = try clientRows ?? defaultClients(account: account)
        let clientLocal = try ListLocalSnapshot(
            queryFingerprint: ListQueryFingerprint(
                validating: String(repeating: clientQuerySeed, count: 64)
            ),
            rows: resolvedClients,
            visibleRowCountBeforeFiltering: clientVisibleCount ?? resolvedClients.count,
            isCompleteForQuery: clientComplete ?? (clientQuality == .ready),
            quality: clientQuality,
            localDataVersion: LocalDataVersion(validating: clientVersion),
            asOf: clientAsOf
        )
        let clients = try ProjectExistingClientSelectionSnapshot(
            directory: ClientListSnapshot(
                accountId: AccountID(validating: account),
                local: clientLocal
            )
        )
        let resolvedCategories = try categoryRows ?? defaultCategories(account: account)
        let categoryLocal = try ListLocalSnapshot(
            queryFingerprint: ListQueryFingerprint(
                validating: String(repeating: categoryQuerySeed, count: 64)
            ),
            rows: resolvedCategories,
            visibleRowCountBeforeFiltering: resolvedCategories.count,
            isCompleteForQuery: categoryComplete ?? (categoryQuality == .ready),
            quality: categoryQuality,
            localDataVersion: LocalDataVersion(validating: categoryVersion),
            asOf: categoryAsOf
        )
        let categories = try BudgetCategoryReferenceSnapshot(
            accountId: AccountID(validating: account),
            local: categoryLocal
        )
        return try ProjectSetupFormPresentation.prepare(
            clientSelectionSnapshot: clients,
            categoryReferenceSnapshot: categories
        )
    }

    private static func changedPreparations() throws -> [ProjectSetupFormPreparation] {
        let clients = try defaultClients()
        let categories = try defaultCategories()
        return try [
            preparation(account: "account-other"),
            preparation(clientQuerySeed: "3"),
            preparation(clientVisibleCount: clients.count + 1),
            preparation(clientComplete: false),
            preparation(clientQuality: .partial),
            preparation(clientQuality: .stale),
            preparation(clientVersion: "clients-other"),
            preparation(clientAsOf: t3),
            preparation(clientRows: [clients[1], clients[0], clients[2]]),
            preparation(clientRows: clients + [client("client-c", name: "Client C")]),
            preparation(clientRows: [clients[0], clients[2]]),
            preparation(clientRows: [
                client("client-a", name: "Changed Client A"), clients[1], clients[2]
            ]),
            preparation(clientRows: [
                client("client-a", name: "Client A", lifecycle: .archived),
                clients[1], clients[2]
            ]),
            preparation(clientRows: [
                client(
                    "client-a",
                    name: "Client A",
                    createdAt: t0.addingTimeInterval(-1)
                ),
                clients[1], clients[2]
            ]),
            preparation(clientRows: [
                client("client-a", name: "Client A", updatedAt: t4), clients[1], clients[2]
            ]),
            preparation(clientRows: [
                client("client-z", name: "Client A"), clients[1], clients[2]
            ]),
            preparation(categoryQuerySeed: "4"),
            preparation(categoryComplete: false),
            preparation(categoryQuality: .partial),
            preparation(categoryQuality: .stale),
            preparation(categoryVersion: "categories-other"),
            preparation(categoryAsOf: t4),
            preparation(categoryRows: [
                category("category-a", name: "Category A", order: 10, excludes: true)
            ] + categories.dropFirst()),
            preparation(categoryRows: categories + [
                category("category-d", name: "Category D", order: 60)
            ]),
            preparation(categoryRows: Array(categories.dropLast())),
            preparation(categoryRows: [
                category("category-aa", name: "Category A", order: 10)
            ] + categories.dropFirst()),
            preparation(categoryRows: [
                category("category-a", name: "Changed Category", order: 10)
            ] + categories.dropFirst()),
            preparation(categoryRows: [
                category("category-a", name: "Category A", kind: .fee, order: 10)
            ] + categories.dropFirst()),
            preparation(categoryRows: [
                category("category-a", name: "Category A", order: 10, lifecycle: .archived)
            ] + categories.dropFirst()),
            preparation(categoryRows: [
                category("category-a", name: "Category A", order: 10, isSystem: true)
            ] + categories.dropFirst()),
            preparation(categoryRows: [
                category("category-a", name: "Category A", order: 11)
            ] + categories.dropFirst()),
            preparation(categoryRows: [
                category("category-a", name: "Category A", order: 10, revision: 2)
            ] + categories.dropFirst())
        ]
    }

    private static func equivalentIntentPreparations() throws -> [ProjectSetupFormPreparation] {
        let clients = try defaultClients()
        let categories = try defaultCategories()
        return try [
            preparation(clientQuerySeed: "3"),
            preparation(clientVisibleCount: clients.count + 1),
            preparation(clientComplete: false),
            preparation(clientQuality: .partial),
            preparation(clientQuality: .stale),
            preparation(clientVersion: "clients-other"),
            preparation(clientAsOf: t3),
            preparation(clientRows: [
                client("client-a", name: "Changed Client A", createdAt: t3, updatedAt: t4),
                clients[1], clients[2]
            ]),
            preparation(categoryQuerySeed: "4"),
            preparation(categoryComplete: false),
            preparation(categoryQuality: .partial),
            preparation(categoryQuality: .stale),
            preparation(categoryVersion: "categories-other"),
            preparation(categoryAsOf: t4),
            preparation(categoryRows: [
                category(
                    "category-a",
                    name: "Renamed Category",
                    kind: .fee,
                    order: 15,
                    excludes: true,
                    revision: 2
                ),
                categories[1], categories[2], categories[3], categories[4]
            ]),
            preparation(categoryRows: categories + [
                category("category-d", name: "Category D", order: 60)
            ])
        ]
    }

    private static func baselineAllocations(
        firstCategory: String = "category-a"
    ) throws -> [NullableCategoryAllocation] {
        try [
            allocation(firstCategory, nil),
            allocation(
                "category-b",
                Money(minorUnits: 0, currency: CurrencyCode(validating: "USD"))
            ),
            allocation(
                "category-c",
                Money(minorUnits: 5_000_000_000, currency: CurrencyCode(validating: "EUR"))
            )
        ]
    }

    private static func allocation(
        _ categoryID: String,
        _ money: Money?
    ) throws -> NullableCategoryAllocation {
        try NullableCategoryAllocation(
            categoryId: BudgetCategoryID(validating: categoryID),
            allocation: money
        )
    }

    private static func fieldDelta(
        from baseline: CreateProjectCommand,
        to variant: CreateProjectCommand
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
}

private enum ProjectSetupResponse: Sendable {
    case matching(LocalOperationState)
    case mismatched(OperationID)
    case formFailure(ProjectSetupFormFailure)
    case setupFailure(ProjectSetupFailure)
    case rawFailure
    case cancelled
}

private actor RecordingProjectSetup: ProjectSetupOperating {
    private let response: ProjectSetupResponse
    private var commands: [CreateProjectCommand] = []

    init(response: ProjectSetupResponse) {
        self.response = response
    }

    func create(_ command: CreateProjectCommand) async throws -> OperationReceipt {
        commands.append(command)
        switch response {
        case .matching(let state):
            return OperationReceipt(operationId: command.envelope.operationId, localState: state)
        case .mismatched(let operationID):
            return OperationReceipt(operationId: operationID, localState: .queued)
        case .formFailure(let failure):
            throw failure
        case .setupFailure(let failure):
            throw failure
        case .rawFailure:
            throw OpaqueProjectSetupPortFailure.sensitive(
                ["private", "adapter", "detail"].joined(separator: "-")
            )
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedCommands() -> [CreateProjectCommand] {
        commands
    }
}

private enum OpaqueProjectSetupPortFailure: Error {
    case sensitive(String)
}
