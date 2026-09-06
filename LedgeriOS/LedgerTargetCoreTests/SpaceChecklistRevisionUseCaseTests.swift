import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Space Checklist Revision Use Case Contracts")
struct SpaceChecklistRevisionUseCaseTests {
    @Test("SPCHECKUSE-TEST-001 exact current and retryable cached evidence dispatch the same draft")
    func bothAdmissibleReadinessPaths() async throws {
        let original = try Self.update()
        let longName = "Long 🚀  Interior " + String(repeating: "名", count: 8_192)
        let longText = "Long 🧰  Interior " + String(repeating: "文", count: 8_192)
        var draft = try Self.draft(from: original)
        draft = try draft.renamingChecklist(
            id: SpaceChecklistID(validating: "checklist-arrival"),
            name: "  \(longName)  "
        )
        draft = try draft.renamingChecklist(
            id: SpaceChecklistID(validating: "checklist-installation"),
            name: longName
        )
        draft = try draft.editingItemText(
            checklistId: SpaceChecklistID(validating: "checklist-installation"),
            itemId: SpaceChecklistItemID(validating: "item-walls"),
            text: "  \(longText)  "
        )
        draft = try draft.editingItemText(
            checklistId: SpaceChecklistID(validating: "checklist-installation"),
            itemId: SpaceChecklistItemID(validating: "item-lamp"),
            text: longText
        )

        let refreshedCurrent = try Self.update(
            mode: .current,
            version: "version-refreshed-current",
            asOf: Self.t3,
            displayName: "Renamed without checklist change",
            notes: "Refreshed notes",
            createdAt: Self.t1,
            updatedAt: Self.t3
        )
        let refreshedRetryable = try Self.update(
            mode: .retryable,
            version: "version-refreshed-cached",
            asOf: Self.t4,
            displayName: "Another nonsemantic name",
            notes: nil,
            createdAt: Self.t2,
            updatedAt: Self.t4
        )

        for (suffix, update) in [
            ("current", refreshedCurrent),
            ("retryable", refreshedRetryable)
        ] {
            let reviser = RecordingSpaceChecklistReviser(response: .matching(.queued))
            let operationID = try OperationID(validating: "operation-both-\(suffix)")
            let receipt = try await Self.useCase(reviser).execute(
                draft: draft,
                currentUpdate: update,
                operationId: operationID,
                actorPrincipalId: PrincipalID(validating: "principal-both"),
                operationContractVersion: OperationContractVersion(
                    validating: "space-checklist-use-case-v1"
                ),
                capturedAt: Self.t5
            )

            #expect(receipt == OperationReceipt(operationId: operationID, localState: .queued))
            let commands = await reviser.recordedCommands()
            #expect(commands.count == 1)
            let command = try #require(commands.first)
            #expect(command.draft.accountId.rawValue == "account-one")
            #expect(command.draft.spaceId.rawValue == "space-one")
            #expect(command.draft.expectedRevision == ExpectedSpaceRevision(71))
            #expect(command.draft.collection.checklists.map(\.id.rawValue) == [
                "checklist-arrival", "checklist-installation"
            ])
            #expect(command.draft.collection.checklists.map(\.presentationOrder) == [3, 9])
            #expect(command.draft.collection.checklists.map(\.name.rawValue) == [
                longName, longName
            ])
            #expect(command.draft.collection.checklists[0].name.rawValue.utf8.count > 8_192)
            #expect(command.draft.collection.checklists[0].items.isEmpty)
            #expect(command.draft.collection.checklists[1].items.map(\.id.rawValue) == [
                "item-walls", "item-lamp"
            ])
            #expect(command.draft.collection.checklists[1].items.map(\.presentationOrder) == [2, 8])
            #expect(command.draft.collection.checklists[1].items.map(\.text.rawValue) == [
                longText, longText
            ])
            #expect(command.draft.collection.checklists[1].items[0].text.rawValue.utf8.count > 8_192)
            #expect(command.draft.collection.checklists[1].items.map(\.isChecked) == [true, false])
        }

        for (revision, revisionSuffix) in [
            (UInt64.zero, "zero"),
            (UInt64.max, "maximum")
        ] {
            for (mode, modeSuffix) in [
                (UpdateMode.current, "current"),
                (UpdateMode.retryable, "retryable")
            ] {
                let update = try Self.update(mode: mode, revision: revision)
                let boundaryDraft = try Self.draft(from: update)
                let reviser = RecordingSpaceChecklistReviser(response: .matching(.applied))
                _ = try await Self.execute(
                    using: reviser,
                    draft: boundaryDraft,
                    update: update,
                    operationID: "operation-boundary-\(revisionSuffix)-\(modeSuffix)"
                )
                let commands = await reviser.recordedCommands()
                #expect(commands.count == 1)
                #expect(try #require(commands.first).draft.expectedRevision ==
                    ExpectedSpaceRevision(revision))
            }
        }

        for (mode, suffix) in [
            (UpdateMode.current, "current"),
            (UpdateMode.retryable, "retryable")
        ] {
            let clearUpdate = try Self.update(
                mode: mode,
                collection: SpaceChecklistCollection(checklists: [])
            )
            let clearReviser = RecordingSpaceChecklistReviser(response: .matching(.queued))
            _ = try await Self.execute(
                using: clearReviser,
                draft: Self.draft(from: clearUpdate),
                update: clearUpdate,
                operationID: "operation-clear-\(suffix)"
            )
            #expect(try #require(await clearReviser.recordedCommands().first)
                .draft.collection.checklists.isEmpty)
            #expect(await clearReviser.recordedCommands().count == 1)
        }

        let projectScope = try SpaceCreationScope.project(
            ProjectID(validating: "project-one")
        )
        for (scope, lifecycle, semanticsSuffix) in [
            (projectScope, DirectoryLifecycleState.archived, "archived-project"),
            (.businessInventory, .active, "active-inventory"),
            (.businessInventory, .archived, "archived-inventory")
        ] {
            for (mode, modeSuffix) in [
                (UpdateMode.current, "current"),
                (UpdateMode.retryable, "retryable")
            ] {
                let update = try Self.update(
                    mode: mode,
                    scope: scope,
                    lifecycle: lifecycle
                )
                let semanticDraft = try Self.draft(from: update)
                let reviser = RecordingSpaceChecklistReviser(response: .matching(.queued))
                _ = try await Self.execute(
                    using: reviser,
                    draft: semanticDraft,
                    update: update,
                    operationID: "operation-semantic-\(semanticsSuffix)-\(modeSuffix)"
                )
                let commands = await reviser.recordedCommands()
                #expect(commands.count == 1)
                let command = try #require(commands.first)
                #expect(command.draft.spaceId == update.request.spaceId)
                #expect(command.draft.accountId == update.request.accountId)
            }
        }
    }

    @Test("SPCHECKUSE-TEST-002 derivation failures make zero port calls")
    func derivationFailuresDoNotDispatch() async throws {
        let original = try Self.update()
        let draft = try Self.draft(from: original)
        let noneditable = try [
            Self.update(mode: .waiting),
            Self.update(mode: .incomplete),
            Self.update(mode: .partial),
            Self.update(mode: .retryablePartial),
            Self.update(mode: .unavailable),
            Self.update(mode: .requiredUpdate),
            Self.update(mode: .absence)
        ]
        for (index, update) in noneditable.enumerated() {
            let reviser = RecordingSpaceChecklistReviser(response: .matching(.queued))
            do {
                _ = try await Self.execute(
                    using: reviser,
                    draft: draft,
                    update: update,
                    operationID: "operation-noneditable-\(index)"
                )
                Issue.record("Noneditable evidence dispatched")
            } catch let failure as SpaceChecklistEditingFailure {
                #expect(failure == .sourceNotEditable)
            }
            #expect(await reviser.recordedCommands().isEmpty)
        }

        let changedSemanticUpdates = try [
            Self.update(account: "account-other", space: "space-one"),
            Self.update(account: "account-one", space: "space-other"),
            Self.update(scope: .businessInventory),
            Self.update(lifecycle: .archived),
            Self.update(revision: 72),
            Self.update(collection: Self.collection(firstName: "Changed hierarchy"))
        ]
        for (index, update) in changedSemanticUpdates.enumerated() {
            let reviser = RecordingSpaceChecklistReviser(response: .matching(.queued))
            do {
                _ = try await Self.execute(
                    using: reviser,
                    draft: draft,
                    update: update,
                    operationID: "operation-semantic-change-\(index)"
                )
                Issue.record("Changed semantic base dispatched")
            } catch let failure as SpaceChecklistEditingFailure {
                #expect(failure == .semanticBaseMismatch)
            }
            #expect(await reviser.recordedCommands().isEmpty)
        }

        let malformed = try draft.renamingChecklist(
            id: SpaceChecklistID(validating: "checklist-arrival"),
            name: " \n\t "
        )
        let malformedReviser = RecordingSpaceChecklistReviser(response: .matching(.queued))
        do {
            _ = try await Self.execute(
                using: malformedReviser,
                draft: malformed,
                update: original,
                operationID: "operation-malformed"
            )
            Issue.record("Malformed draft dispatched")
        } catch let failure as SpaceChecklistRevisionFailure {
            #expect(failure == .invalidChecklistName)
        }
        #expect(await malformedReviser.recordedCommands().isEmpty)

        let malformedItem = try draft.editingItemText(
            checklistId: SpaceChecklistID(validating: "checklist-installation"),
            itemId: SpaceChecklistItemID(validating: "item-walls"),
            text: " \n\t "
        )
        let malformedItemReviser = RecordingSpaceChecklistReviser(response: .matching(.queued))
        do {
            _ = try await Self.execute(
                using: malformedItemReviser,
                draft: malformedItem,
                update: original,
                operationID: "operation-malformed-item"
            )
            Issue.record("Malformed item draft dispatched")
        } catch let failure as SpaceChecklistRevisionFailure {
            #expect(failure == .invalidChecklistItemText)
        }
        #expect(await malformedItemReviser.recordedCommands().isEmpty)

        for (index, interval) in [Double.infinity, -Double.infinity, Double.nan].enumerated() {
            let reviser = RecordingSpaceChecklistReviser(response: .matching(.queued))
            do {
                _ = try await Self.useCase(reviser).execute(
                    draft: draft,
                    currentUpdate: original,
                    operationId: OperationID(validating: "operation-invalid-time-\(index)"),
                    actorPrincipalId: PrincipalID(validating: "principal-one"),
                    operationContractVersion: OperationContractVersion(
                        validating: "space-checklist-use-case-v1"
                    ),
                    capturedAt: Date(timeIntervalSinceReferenceDate: interval)
                )
                Issue.record("Nonfinite capture time dispatched")
            } catch let failure as SpaceChecklistRevisionFailure {
                #expect(failure == .invalidCapturedAt)
            }
            #expect(await reviser.recordedCommands().isEmpty)
        }
    }

    @Test("SPCHECKUSE-TEST-003 one complete command preserves every local receipt state")
    func everyReceiptStateAndMismatch() async throws {
        let update = try Self.update()
        let draft = try Self.draft(from: update)
        for state in LocalOperationState.allCases {
            let reviser = RecordingSpaceChecklistReviser(response: .matching(state))
            let operationID = "operation-state-\(state.rawValue)"
            let receipt = try await Self.execute(
                using: reviser,
                draft: draft,
                update: update,
                operationID: operationID
            )
            #expect(receipt.operationId.rawValue == operationID)
            #expect(receipt.localState == state)
            let commands = await reviser.recordedCommands()
            #expect(commands.count == 1)
            let command = try #require(commands.first)
            #expect(command.envelope.payload.collection == (try draft.collection()))
            #expect(command.envelope.preconditions == [
                .expectedRevision(subject: command.subject, revision: 71)
            ])
        }

        let mismatched = RecordingSpaceChecklistReviser(
            response: .mismatched(try OperationID(validating: "operation-wrong"))
        )
        do {
            _ = try await Self.execute(
                using: mismatched,
                draft: draft,
                update: update,
                operationID: "operation-receipt-mismatch"
            )
            Issue.record("Mismatched receipt returned")
        } catch let failure as SpaceChecklistRevisionFailure {
            #expect(failure == .receiptMismatch)
        }
        #expect(await mismatched.recordedCommands().count == 1)
    }

    @Test("SPCHECKUSE-TEST-004 reciprocal fields reach only their command owners")
    func reciprocalFieldForwarding() async throws {
        let baseline = try await Self.recordedCommand()
        let account = try await Self.recordedCommand(account: "account-other")
        let space = try await Self.recordedCommand(space: "space-other")
        let revision = try await Self.recordedCommand(revision: UInt64.max)
        let checklistID = try await Self.recordedCommand(checklistID: "checklist-other")
        let itemID = try await Self.recordedCommand(itemID: "item-other")
        let checklistOrder = try await Self.recordedCommand(checklistOrder: 4)
        let itemOrder = try await Self.recordedCommand(itemOrder: 7)
        let name = try await Self.recordedCommand(editedName: "  Revised   name  ")
        let text = try await Self.recordedCommand(editedText: "  Revised   text  ")
        let checked = try await Self.recordedCommand(editedChecked: false)
        let operation = try await Self.recordedCommand(operationID: "operation-other")
        let actor = try await Self.recordedCommand(actor: "principal-other")
        let contract = try await Self.recordedCommand(contract: "space-checklist-v2")
        let time = try await Self.recordedCommand(capturedAt: Self.t6)

        #expect(account.draft.accountId.rawValue == "account-other")
        #expect(account.envelope.accountId == account.draft.accountId)
        #expect(space.draft.spaceId.rawValue == "space-other")
        #expect(space.envelope.payload.spaceId == space.draft.spaceId)
        #expect(space.subject.id.rawValue == "space-other")
        #expect(revision.draft.expectedRevision == ExpectedSpaceRevision(UInt64.max))
        #expect(revision.envelope.preconditions == [
            .expectedRevision(subject: revision.subject, revision: UInt64.max)
        ])
        #expect(checklistID.draft.collection.checklists[0].id.rawValue == "checklist-other")
        #expect(itemID.draft.collection.checklists[1].items[0].id.rawValue == "item-other")
        #expect(checklistOrder.draft.collection.checklists[0].presentationOrder == 4)
        #expect(checklistOrder.draft.collection.checklists[1].presentationOrder == 9)
        #expect(itemOrder.draft.collection.checklists[1].items.map(\.presentationOrder) == [7, 8])
        #expect(name.draft.collection.checklists[0].name.rawValue == "Revised   name")
        #expect(text.draft.collection.checklists[1].items[0].text.rawValue == "Revised   text")
        #expect(checked.draft.collection.checklists[1].items[0].isChecked == false)
        #expect(operation.envelope.operationId.rawValue == "operation-other")
        #expect(actor.draft.actorPrincipalId.rawValue == "principal-other")
        #expect(actor.envelope.actorPrincipalId == actor.draft.actorPrincipalId)
        #expect(contract.draft.operationContractVersion.rawValue == "space-checklist-v2")
        #expect(contract.envelope.contractVersion == contract.draft.operationContractVersion)
        #expect(time.draft.capturedAt == Self.t6)
        #expect(time.envelope.clientCreatedAt == Self.t6)

        let variants: [(ReviseSpaceChecklistsCommand, Set<String>)] = [
            (account, [
                "draft.accountId", "envelope.accountId", "fingerprint"
            ]),
            (space, [
                "draft.spaceId", "envelope.payload.spaceId",
                "envelope.preconditions.0.expectedRevision.subject.id",
                "subject.id", "fingerprint"
            ]),
            (revision, [
                "draft.expectedRevision.rawValue",
                "envelope.preconditions.0.expectedRevision.revision", "fingerprint"
            ]),
            (checklistID, [
                "draft.collection.checklists.0.id",
                "envelope.payload.collection.checklists.0.id", "fingerprint"
            ]),
            (itemID, [
                "draft.collection.checklists.1.items.0.id",
                "envelope.payload.collection.checklists.1.items.0.id", "fingerprint"
            ]),
            (checklistOrder, [
                "draft.collection.checklists.0.presentationOrder",
                "envelope.payload.collection.checklists.0.presentationOrder", "fingerprint"
            ]),
            (itemOrder, [
                "draft.collection.checklists.1.items.0.presentationOrder",
                "envelope.payload.collection.checklists.1.items.0.presentationOrder", "fingerprint"
            ]),
            (name, [
                "draft.collection.checklists.0.name",
                "envelope.payload.collection.checklists.0.name", "fingerprint"
            ]),
            (text, [
                "draft.collection.checklists.1.items.0.text",
                "envelope.payload.collection.checklists.1.items.0.text", "fingerprint"
            ]),
            (checked, [
                "draft.collection.checklists.1.items.0.isChecked",
                "envelope.payload.collection.checklists.1.items.0.isChecked", "fingerprint"
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
            #expect(variant.envelope.payload.collection == variant.draft.collection)
            #expect(variant.fingerprint == (try OperationFingerprint.make(for: variant.envelope)))
            #expect(try Self.fieldDelta(from: baseline, to: variant) == expectedDelta)
        }
    }

    @Test("SPCHECKUSE-TEST-005 typed failures and cancellation remain distinct")
    func boundedFailureMapping() async throws {
        let update = try Self.update()
        let draft = try Self.draft(from: update)
        let cases: [(ReviserResponse, FailureExpectation)] = [
            (.editingFailure(.draftFingerprintMismatch), .editing(.draftFingerprintMismatch)),
            (.revisionFailure(.draftPayloadMismatch), .revision(.draftPayloadMismatch)),
            (.rawFailure, .revision(.localAcceptanceFailed)),
            (.cancelled, .cancelled)
        ]

        for (index, entry) in cases.enumerated() {
            let reviser = RecordingSpaceChecklistReviser(response: entry.0)
            do {
                _ = try await Self.execute(
                    using: reviser,
                    draft: draft,
                    update: update,
                    operationID: "operation-failure-\(index)"
                )
                Issue.record("Failure returned a receipt")
            } catch is CancellationError {
                #expect(entry.1 == .cancelled)
            } catch let failure as SpaceChecklistEditingFailure {
                #expect(entry.1 == .editing(failure))
            } catch let failure as SpaceChecklistRevisionFailure {
                #expect(entry.1 == .revision(failure))
            } catch {
                Issue.record("Unexpected error escaped: \(error)")
            }
            #expect(await reviser.recordedCommands().count == 1)
        }
    }

    @Test("SPCHECKUSE-TEST-006 diagnostics and encoding stay inside checklist replacement")
    func diagnosticsEncodingAndExclusions() async throws {
        let diagnostics: [(String, String)] = [
            (SpaceChecklistEditingFailure.sourceNotEditable.diagnosticCode,
             "space_checklist_editing_source_not_editable"),
            (SpaceChecklistEditingFailure.checklistNotFound.diagnosticCode,
             "space_checklist_editing_checklist_not_found"),
            (SpaceChecklistEditingFailure.checklistIdentityCollision.diagnosticCode,
             "space_checklist_editing_checklist_identity_collision"),
            (SpaceChecklistEditingFailure.checklistOrderOverflow.diagnosticCode,
             "space_checklist_editing_checklist_order_overflow"),
            (SpaceChecklistEditingFailure.itemNotFound.diagnosticCode,
             "space_checklist_editing_item_not_found"),
            (SpaceChecklistEditingFailure.itemIdentityCollision.diagnosticCode,
             "space_checklist_editing_item_identity_collision"),
            (SpaceChecklistEditingFailure.itemOrderOverflow.diagnosticCode,
             "space_checklist_editing_item_order_overflow"),
            (SpaceChecklistEditingFailure.invalidItemPermutation.diagnosticCode,
             "space_checklist_editing_item_permutation_invalid"),
            (SpaceChecklistEditingFailure.semanticBaseMismatch.diagnosticCode,
             "space_checklist_editing_semantic_base_mismatch"),
            (SpaceChecklistEditingFailure.invalidPresentationFingerprint.diagnosticCode,
             "space_checklist_editing_presentation_fingerprint_invalid"),
            (SpaceChecklistEditingFailure.invalidSemanticBaseFingerprint.diagnosticCode,
             "space_checklist_editing_semantic_base_fingerprint_invalid"),
            (SpaceChecklistEditingFailure.invalidDraftFingerprint.diagnosticCode,
             "space_checklist_editing_draft_fingerprint_invalid"),
            (SpaceChecklistEditingFailure.presentationFingerprintMismatch.diagnosticCode,
             "space_checklist_editing_presentation_fingerprint_mismatch"),
            (SpaceChecklistEditingFailure.semanticBaseFingerprintMismatch.diagnosticCode,
             "space_checklist_editing_semantic_base_fingerprint_mismatch"),
            (SpaceChecklistEditingFailure.draftFingerprintMismatch.diagnosticCode,
             "space_checklist_editing_draft_fingerprint_mismatch"),
            (SpaceChecklistEditingFailure.invalidEncodedPresentation.diagnosticCode,
             "space_checklist_editing_presentation_encoding_invalid"),
            (SpaceChecklistEditingFailure.invalidEncodedPreparation.diagnosticCode,
             "space_checklist_editing_preparation_encoding_invalid"),
            (SpaceChecklistEditingFailure.invalidEncodedDraft.diagnosticCode,
             "space_checklist_editing_draft_encoding_invalid"),
            (SpaceChecklistRevisionFailure.invalidChecklistName.diagnosticCode,
             "space_checklist_name_invalid"),
            (SpaceChecklistRevisionFailure.invalidChecklistItemText.diagnosticCode,
             "space_checklist_item_text_invalid"),
            (SpaceChecklistRevisionFailure.duplicateChecklistIdentity.diagnosticCode,
             "space_checklist_identity_duplicate"),
            (SpaceChecklistRevisionFailure.duplicateChecklistPresentationOrder.diagnosticCode,
             "space_checklist_order_duplicate"),
            (SpaceChecklistRevisionFailure.duplicateChecklistItemIdentity.diagnosticCode,
             "space_checklist_item_identity_duplicate"),
            (SpaceChecklistRevisionFailure.duplicateChecklistItemPresentationOrder.diagnosticCode,
             "space_checklist_item_order_duplicate"),
            (SpaceChecklistRevisionFailure.invalidCapturedAt.diagnosticCode,
             "space_checklist_revision_captured_at_invalid"),
            (SpaceChecklistRevisionFailure.draftAccountMismatch.diagnosticCode,
             "space_checklist_revision_account_mismatch"),
            (SpaceChecklistRevisionFailure.draftActorMismatch.diagnosticCode,
             "space_checklist_revision_actor_mismatch"),
            (SpaceChecklistRevisionFailure.draftContractMismatch.diagnosticCode,
             "space_checklist_revision_contract_mismatch"),
            (SpaceChecklistRevisionFailure.draftPayloadMismatch.diagnosticCode,
             "space_checklist_revision_payload_mismatch"),
            (SpaceChecklistRevisionFailure.revisionPreconditionMismatch.diagnosticCode,
             "space_checklist_revision_precondition_mismatch"),
            (SpaceChecklistRevisionFailure.subjectMismatch.diagnosticCode,
             "space_checklist_revision_subject_mismatch"),
            (SpaceChecklistRevisionFailure.fingerprintMismatch.diagnosticCode,
             "space_checklist_revision_fingerprint_mismatch"),
            (SpaceChecklistRevisionFailure.receiptMismatch.diagnosticCode,
             "space_checklist_revision_receipt_mismatch"),
            (SpaceChecklistRevisionFailure.localAcceptanceFailed.diagnosticCode,
             "space_checklist_revision_local_acceptance_failed"),
            (SpaceChecklistRevisionFailure.invalidEncodedChecklistName.diagnosticCode,
             "space_checklist_name_encoding_invalid"),
            (SpaceChecklistRevisionFailure.invalidEncodedChecklistItemText.diagnosticCode,
             "space_checklist_item_text_encoding_invalid"),
            (SpaceChecklistRevisionFailure.invalidEncodedChecklistItem.diagnosticCode,
             "space_checklist_item_encoding_invalid"),
            (SpaceChecklistRevisionFailure.invalidEncodedChecklist.diagnosticCode,
             "space_checklist_encoding_invalid"),
            (SpaceChecklistRevisionFailure.invalidEncodedCollection.diagnosticCode,
             "space_checklist_collection_encoding_invalid"),
            (SpaceChecklistRevisionFailure.invalidEncodedDraft.diagnosticCode,
             "space_checklist_revision_draft_encoding_invalid"),
            (SpaceChecklistRevisionFailure.invalidEncodedCommand.diagnosticCode,
             "space_checklist_revision_command_encoding_invalid")
        ]
        #expect(diagnostics.count == 41)
        for (actual, expected) in diagnostics {
            #expect(actual == expected)
            for privateValue in [
                "raw-provider-detail", "account-one", "space-one",
                "principal-one", "operation-one", "production"
            ] {
                #expect(!actual.contains(privateValue))
            }
        }

        let command = try await Self.recordedCommand(
            editedName: "  Canonical  Name  ",
            editedText: "  Canonical  Text  "
        )
        let bytes = try OperationContractCodec.encode(command)
        let object = try #require(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        #expect(Set(object.keys) == ["draft", "envelope", "fingerprint", "subject"])
        #expect(object["fingerprint"] is String)
        #expect((object["fingerprint"] as? String)?.count == 64)
        let draft = try #require(object["draft"] as? [String: Any])
        #expect(Set(draft.keys) == [
            "accountId", "actorPrincipalId", "operationContractVersion", "spaceId",
            "collection", "expectedRevision", "capturedAt"
        ])
        let expectedRevision = try #require(draft["expectedRevision"] as? [String: Any])
        #expect(Set(expectedRevision.keys) == ["rawValue"])
        let draftCollection = try #require(draft["collection"] as? [String: Any])
        #expect(Set(draftCollection.keys) == ["checklists"])
        let draftChecklists = try #require(draftCollection["checklists"] as? [[String: Any]])
        #expect(draftChecklists.count == 2)
        for checklist in draftChecklists {
            #expect(Set(checklist.keys) == ["id", "name", "presentationOrder", "items"])
            let items = try #require(checklist["items"] as? [[String: Any]])
            for item in items {
                #expect(Set(item.keys) == ["id", "text", "isChecked", "presentationOrder"])
            }
        }
        let envelope = try #require(object["envelope"] as? [String: Any])
        #expect(Set(envelope.keys) == [
            "operationId", "contractVersion", "accountId", "actorPrincipalId",
            "clientCreatedAt", "payload", "preconditions"
        ])
        let payload = try #require(envelope["payload"] as? [String: Any])
        #expect(Set(payload.keys) == ["spaceId", "collection"])
        let payloadCollection = try #require(payload["collection"] as? [String: Any])
        #expect(Set(payloadCollection.keys) == ["checklists"])
        let payloadChecklists = try #require(
            payloadCollection["checklists"] as? [[String: Any]]
        )
        #expect(payloadChecklists.count == 2)
        for checklist in payloadChecklists {
            #expect(Set(checklist.keys) == ["id", "name", "presentationOrder", "items"])
            let items = try #require(checklist["items"] as? [[String: Any]])
            for item in items {
                #expect(Set(item.keys) == ["id", "text", "isChecked", "presentationOrder"])
            }
        }
        let preconditions = try #require(envelope["preconditions"] as? [[String: Any]])
        #expect(preconditions.count == 1)
        #expect(Set(try #require(preconditions.first).keys) == ["expectedRevision"])
        let revisionPrecondition = try #require(
            preconditions.first?["expectedRevision"] as? [String: Any]
        )
        #expect(Set(revisionPrecondition.keys) == ["subject", "revision"])
        let preconditionSubject = try #require(
            revisionPrecondition["subject"] as? [String: Any]
        )
        #expect(Set(preconditionSubject.keys) == ["kind", "id"])
        let subject = try #require(object["subject"] as? [String: Any])
        #expect(Set(subject.keys) == ["kind", "id"])

        let encoded = String(decoding: bytes, as: UTF8.self).lowercased()
        for required in [
            "account-one", "space-one", "checklist-arrival", "checklist-installation",
            "item-walls", "item-lamp", "canonical  name", "canonical  text",
            "operation-one", "principal-one", "space-checklist-use-case-v1",
            "presentationorder", "ischecked", "expectedrevision"
        ] {
            #expect(encoded.contains(required))
        }
        for forbidden in [
            "displayname", "notes", "projectid", "businessinventory", "lifecycle",
            "template", "attachment", "media", "image", "itemplacement", "spaceidassignment",
            "review", "completion", "iscomplete", "accounting", "transaction", "occurrence",
            "invoice", "budget", "payer", "price", "swiftui", "route", "readiness",
            "queryfingerprint", "localdataversion", "firebase", "firestore", "supabase",
            "powersync", "provider", "raw-provider-detail", "credential", "bearer",
            "token", "secret", "production", "https://", "file://"
        ] {
            #expect(!encoded.contains(forbidden))
        }
    }

    private enum UpdateMode {
        case current
        case retryable
        case waiting
        case incomplete
        case partial
        case retryablePartial
        case unavailable
        case requiredUpdate
        case absence
    }

    private enum FailureExpectation: Equatable {
        case editing(SpaceChecklistEditingFailure)
        case revision(SpaceChecklistRevisionFailure)
        case cancelled
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_100_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_100_001)
    private static let t2 = Date(timeIntervalSince1970: 1_802_100_002)
    private static let t3 = Date(timeIntervalSince1970: 1_802_100_003)
    private static let t4 = Date(timeIntervalSince1970: 1_802_100_004)
    private static let t5 = Date(timeIntervalSince1970: 1_802_100_005)
    private static let t6 = Date(timeIntervalSince1970: 1_802_100_006)

    private static func useCase(
        _ reviser: RecordingSpaceChecklistReviser
    ) -> SpaceChecklistRevisionUseCase<RecordingSpaceChecklistReviser> {
        SpaceChecklistRevisionUseCase(reviser: reviser)
    }

    private static func execute(
        using reviser: RecordingSpaceChecklistReviser,
        draft: SpaceChecklistEditingDraft,
        update: SpaceCoreDetailsUpdate,
        operationID: String
    ) async throws -> OperationReceipt {
        try await useCase(reviser).execute(
            draft: draft,
            currentUpdate: update,
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: "principal-one"),
            operationContractVersion: OperationContractVersion(
                validating: "space-checklist-use-case-v1"
            ),
            capturedAt: t5
        )
    }

    private static func draft(
        from update: SpaceCoreDetailsUpdate
    ) throws -> SpaceChecklistEditingDraft {
        try SpaceChecklistEditingPresentation(projecting: update).prepare().draft
    }

    private static func fieldDelta(
        from baseline: ReviseSpaceChecklistsCommand,
        to variant: ReviseSpaceChecklistsCommand
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

    private static func collection(
        firstName: String = "Arrival",
        checklistID: String = "checklist-arrival",
        itemID: String = "item-walls",
        checklistOrder: UInt32 = 3,
        itemOrder: UInt32 = 2
    ) throws -> SpaceChecklistCollection {
        try SpaceChecklistCollection(checklists: [
            checklist(
                id: "checklist-installation",
                name: "Installation",
                order: checklistOrder == 9 ? 10 : 9,
                items: [
                    item(id: "item-lamp", text: "Connect lamp", checked: false, order: 8),
                    item(id: itemID, text: "Prepare walls", checked: true, order: itemOrder)
                ]
            ),
            checklist(id: checklistID, name: firstName, order: checklistOrder, items: [])
        ])
    }

    private static func update(
        mode: UpdateMode = .current,
        account: String = "account-one",
        space: String = "space-one",
        scope: SpaceCreationScope? = nil,
        lifecycle: DirectoryLifecycleState = .active,
        revision: UInt64 = 71,
        version: String = "version-one",
        asOf: Date = t2,
        displayName: String = "Studio",
        notes: String? = "North wall",
        createdAt: Date = t0,
        updatedAt: Date = t2,
        collection suppliedCollection: SpaceChecklistCollection? = nil
    ) throws -> SpaceCoreDetailsUpdate {
        let request = try SpaceCoreDetailsRequest(
            accountId: AccountID(validating: account),
            spaceId: SpaceID(validating: space)
        )
        let collection = try suppliedCollection ?? Self.collection()
        let row = try SpaceCoreDetailsSnapshot(
            id: SpaceID(validating: space),
            accountId: AccountID(validating: account),
            scope: try scope ?? .project(ProjectID(validating: "project-one")),
            displayName: SpaceDisplayName(validating: displayName),
            notes: SpaceCreationNotes(notes),
            lifecycle: lifecycle,
            revision: revision,
            createdAt: createdAt,
            updatedAt: updatedAt,
            checklists: collection
        )
        func local(
            rows: [SpaceCoreDetailsSnapshot],
            quality: ListSnapshotQuality = .ready,
            complete: Bool = true
        ) throws -> SpaceCoreDetailsLocalSnapshot {
            try SpaceCoreDetailsLocalSnapshot(
                request: request,
                rows: rows,
                visibleRowCountBeforeFiltering: rows.count,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: asOf
            )
        }

        let state: SpaceCoreDetailsUpdateState
        switch mode {
        case .current:
            state = .snapshot(try local(rows: [row]))
        case .retryable:
            state = .failed(failure: .retryable, cached: try local(rows: [row]))
        case .waiting:
            state = .waiting(.loading)
        case .incomplete:
            state = .snapshot(try local(rows: [row], complete: false))
        case .partial:
            state = .snapshot(try local(rows: [row], quality: .partial, complete: false))
        case .retryablePartial:
            state = .failed(
                failure: .retryable,
                cached: try local(rows: [row], quality: .partial, complete: false)
            )
        case .unavailable:
            state = .failed(failure: .unavailable, cached: nil)
        case .requiredUpdate:
            state = .failed(failure: .requiredUpdate, cached: try local(rows: [row]))
        case .absence:
            state = .snapshot(try local(rows: []))
        }
        return try SpaceCoreDetailsUpdate(request: request, state: state)
    }

    private static func recordedCommand(
        account: String = "account-one",
        space: String = "space-one",
        revision: UInt64 = 71,
        checklistID: String = "checklist-arrival",
        itemID: String = "item-walls",
        checklistOrder: UInt32 = 3,
        itemOrder: UInt32 = 2,
        editedName: String? = nil,
        editedText: String? = nil,
        editedChecked: Bool? = nil,
        operationID: String = "operation-one",
        actor: String = "principal-one",
        contract: String = "space-checklist-use-case-v1",
        capturedAt: Date = t5
    ) async throws -> ReviseSpaceChecklistsCommand {
        let sourceCollection = try collection(
            checklistID: checklistID,
            itemID: itemID,
            checklistOrder: checklistOrder,
            itemOrder: itemOrder
        )
        let update = try self.update(
            account: account,
            space: space,
            revision: revision,
            collection: sourceCollection
        )
        var draft = try self.draft(from: update)
        let editableChecklistID = try SpaceChecklistID(validating: checklistID)
        let installationID = try SpaceChecklistID(validating: "checklist-installation")
        let editableItemID = try SpaceChecklistItemID(validating: itemID)
        if let editedName {
            draft = try draft.renamingChecklist(id: editableChecklistID, name: editedName)
        }
        if let editedText {
            draft = try draft.editingItemText(
                checklistId: installationID,
                itemId: editableItemID,
                text: editedText
            )
        }
        if let editedChecked {
            draft = try draft.settingItemChecked(
                checklistId: installationID,
                itemId: editableItemID,
                isChecked: editedChecked
            )
        }
        let reviser = RecordingSpaceChecklistReviser(response: .matching(.queued))
        _ = try await useCase(reviser).execute(
            draft: draft,
            currentUpdate: update,
            operationId: OperationID(validating: operationID),
            actorPrincipalId: PrincipalID(validating: actor),
            operationContractVersion: OperationContractVersion(validating: contract),
            capturedAt: capturedAt
        )
        let commands = await reviser.recordedCommands()
        #expect(commands.count == 1)
        return try #require(commands.first)
    }
}

private enum ReviserResponse: Sendable {
    case matching(LocalOperationState)
    case mismatched(OperationID)
    case editingFailure(SpaceChecklistEditingFailure)
    case revisionFailure(SpaceChecklistRevisionFailure)
    case rawFailure
    case cancelled
}

private actor RecordingSpaceChecklistReviser: SpaceChecklistRevising {
    private let response: ReviserResponse
    private var commands: [ReviseSpaceChecklistsCommand] = []

    init(response: ReviserResponse) {
        self.response = response
    }

    func reviseChecklists(
        _ command: ReviseSpaceChecklistsCommand
    ) async throws -> OperationReceipt {
        commands.append(command)
        switch response {
        case .matching(let state):
            return OperationReceipt(operationId: command.envelope.operationId, localState: state)
        case .mismatched(let operationID):
            return OperationReceipt(operationId: operationID, localState: .queued)
        case .editingFailure(let failure):
            throw failure
        case .revisionFailure(let failure):
            throw failure
        case .rawFailure:
            throw RawChecklistRevisionPortFailure.providerPayload("raw-provider-detail")
        case .cancelled:
            throw CancellationError()
        }
    }

    func recordedCommands() -> [ReviseSpaceChecklistsCommand] {
        commands
    }
}

private enum RawChecklistRevisionPortFailure: Error {
    case providerPayload(String)
}
