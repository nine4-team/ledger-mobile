import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Active Space checklist editor staging application")
@MainActor
struct SpaceChecklistEditorStagingExerciseTests {
    @Test("Unchanged drafts are no-ops and text edits preserve noncontiguous order evidence")
    func preservesExistingOrderTokens() async throws {
        let harness = try await Self.harness(operationIds: ["editor-operation-order"])
        let source = try Self.collection()
        let update = try Self.update(collection: source, revision: 7)
        await harness.receive(update)

        harness.editor.open()
        #expect(harness.editor.isPresented)
        #expect(!harness.editor.canSave)
        #expect(harness.editor.validationMessage == "No checklist changes to save.")

        harness.editor.renameChecklist(id: Self.installationId, name: "Final Installation")
        #expect(harness.editor.canSave)
        #expect(harness.editor.validationMessage == nil)
        await harness.editor.save()

        let command = try #require((await harness.acceptance.commands()).editorOnly)
        let collection = command.draft.collection
        #expect(collection.checklists.map(\.presentationOrder) == [5, 20])
        #expect(collection.checklists[0].items.map(\.presentationOrder) == [10, 30])
        #expect(collection.checklists[0].name.rawValue == "Final Installation")
        #expect(!harness.editor.isPresented)
        await harness.stop()
    }

    @Test("Every editor control produces one stable complete replacement")
    func completeEditingControls() async throws {
        let harness = try await Self.harness(
            operationIds: ["editor-operation-controls"],
            checklistIds: ["checklist-new"],
            itemIds: ["item-new"]
        )
        await harness.receive(try Self.update(collection: Self.collection(), revision: 7))
        harness.editor.open()

        harness.editor.renameChecklist(id: Self.installationId, name: "Install")
        harness.editor.editItemText(
            checklistId: Self.installationId,
            itemId: Self.firstItemId,
            text: "Hang framed art"
        )
        harness.editor.setItemChecked(
            checklistId: Self.installationId,
            itemId: Self.firstItemId,
            isChecked: true
        )
        harness.editor.reorderItems(
            checklistId: Self.installationId,
            itemIds: [Self.secondItemId, Self.firstItemId]
        )
        harness.editor.deleteChecklist(id: Self.emptyChecklistId)
        harness.editor.addChecklist()
        let newChecklist = try #require(harness.editor.checklists.last)
        #expect(newChecklist.items.isEmpty)
        harness.editor.addItem(to: newChecklist.id)
        let newItem = try #require(harness.editor.checklists.last?.items.editorOnly)
        harness.editor.editItemText(
            checklistId: newChecklist.id,
            itemId: newItem.id,
            text: "Confirm placement"
        )
        harness.editor.deleteItem(
            checklistId: Self.installationId,
            itemId: Self.secondItemId
        )

        await harness.editor.save()
        let command = try #require((await harness.acceptance.commands()).editorOnly)
        #expect(command.draft.expectedRevision == ExpectedSpaceRevision(7))
        #expect(command.draft.collection.checklists.map(\.id) == [
            Self.installationId,
            try SpaceChecklistID(validating: "checklist-new"),
        ])
        #expect(command.draft.collection.checklists[0].items.map(\.id) == [
            Self.firstItemId
        ])
        #expect(command.draft.collection.checklists[0].items[0].text.rawValue ==
                "Hang framed art")
        #expect(command.draft.collection.checklists[0].items[0].isChecked)
        #expect(command.draft.collection.checklists[1].items.editorOnly?.text.rawValue ==
                "Confirm placement")
        #expect(harness.coordinator.optimisticCollection == command.draft.collection)
        #expect((await harness.acceptance.commands()).count == 1)
        await harness.stop()
    }

    @Test("Cancel and invalid drafts dispatch no operation")
    func cancelAndValidation() async throws {
        let harness = try await Self.harness(operationIds: ["editor-operation-unused"])
        await harness.receive(try Self.update(collection: Self.collection(), revision: 7))
        harness.editor.open()
        harness.editor.renameChecklist(id: Self.installationId, name: "   ")
        #expect(!harness.editor.canSave)
        #expect(harness.editor.validationMessage == "Checklist names are required.")
        harness.editor.cancel()
        #expect(!harness.editor.isPresented)
        #expect((await harness.acceptance.commands()).isEmpty)
        await harness.stop()
    }

    @Test("Empty collection and zero-item checklist remain valid")
    func emptyAndZeroItemStates() async throws {
        let emptyHarness = try await Self.harness(operationIds: ["editor-operation-empty"])
        await emptyHarness.receive(try Self.update(collection: Self.collection(), revision: 7))
        emptyHarness.editor.open()
        for checklist in emptyHarness.editor.checklists {
            emptyHarness.editor.deleteChecklist(id: checklist.id)
        }
        #expect(emptyHarness.editor.checklists.isEmpty)
        #expect(emptyHarness.editor.canSave)
        await emptyHarness.editor.save()
        #expect((await emptyHarness.acceptance.commands()).editorOnly?
            .draft.collection.checklists == [])
        await emptyHarness.stop()

        let zeroHarness = try await Self.harness(
            operationIds: ["editor-operation-zero"],
            checklistIds: ["checklist-zero"]
        )
        await zeroHarness.receive(try Self.update(
            collection: SpaceChecklistCollection(checklists: []),
            revision: 3
        ))
        zeroHarness.editor.open()
        zeroHarness.editor.addChecklist()
        #expect(zeroHarness.editor.checklists.editorOnly?.items == [])
        #expect(zeroHarness.editor.canSave)
        await zeroHarness.editor.save()
        #expect((await zeroHarness.acceptance.commands()).editorOnly?
            .draft.collection.checklists.editorOnly?.items == [])
        await zeroHarness.stop()
    }

    @Test("Archived and incomplete detail cannot open or save")
    func activeCompleteAdmissionOnly() async throws {
        let harness = try await Self.harness(operationIds: ["editor-operation-blocked"])
        await harness.receive(try Self.update(
            collection: Self.collection(),
            revision: 7,
            lifecycle: .archived
        ))
        #expect(!harness.editor.canOpen)
        harness.editor.open()
        #expect(!harness.editor.isPresented)

        await harness.receive(try Self.update(
            collection: Self.collection(),
            revision: 7,
            quality: .partial
        ))
        #expect(!harness.editor.canOpen)
        #expect((await harness.acceptance.commands()).isEmpty)
        await harness.stop()
    }

    @Test("Complete cached detail remains editable while offline")
    func retryableCachedDetailRemainsEditable() async throws {
        let harness = try await Self.harness(operationIds: ["editor-operation-offline"])
        let cached = try Self.localSnapshot(
            collection: Self.collection(),
            revision: 7,
            version: "cached-offline"
        )
        let request = try SpaceCoreDetailsRequest(accountId: Self.accountId, spaceId: Self.spaceA)
        await harness.receive(try SpaceCoreDetailsUpdate(
            request: request,
            state: .failed(failure: .retryable, cached: cached)
        ))

        #expect(harness.coordinator.admission == .retryableStale)
        #expect(harness.editor.canOpen)
        harness.editor.open()
        harness.editor.renameChecklist(id: Self.installationId, name: "Edited Offline")
        #expect(harness.editor.canSave)
        await harness.editor.save()

        let command = try #require((await harness.acceptance.commands()).editorOnly)
        #expect(command.draft.expectedRevision == ExpectedSpaceRevision(7))
        #expect(command.draft.collection.checklists[0].name.rawValue == "Edited Offline")
        await harness.stop()
    }

    @Test("Rejected save preserves its draft and retries against refreshed revision")
    func rejectionPreservesDraft() async throws {
        let harness = try await Self.harness(operationIds: [
            "editor-operation-rejected",
            "editor-operation-retry",
        ])
        let source = try Self.collection()
        await harness.receive(try Self.update(collection: source, revision: 7))
        harness.editor.open()
        harness.editor.renameChecklist(id: Self.installationId, name: "Preserved Draft")
        await harness.editor.save()
        let first = try #require((await harness.acceptance.commands()).editorOnly)
        let firstStream = harness.operations.source(for: first.envelope.operationId)
        firstStream.yield(Self.snapshot(
            command: first,
            state: .rejected(Self.rejection()),
            updatedAt: Self.capturedAt.addingTimeInterval(2)
        ))
        await Self.waitUntil { harness.coordinator.operationState == .rejected }

        await harness.receive(try Self.update(
            collection: source,
            revision: 8,
            version: "refreshed"
        ))
        #expect(harness.editor.hasPreservedConflictDraft)
        #expect(harness.editor.checklists[0].name == "Preserved Draft")
        #expect(harness.editor.canReviewPreservedConflict)

        harness.editor.reviewPreservedConflict()
        #expect(harness.editor.isPresented)
        #expect(harness.editor.canSave)
        await harness.editor.save()
        let commands = await harness.acceptance.commands()
        #expect(commands.count == 2)
        #expect(commands[0].envelope.operationId.rawValue == "editor-operation-rejected")
        #expect(commands[1].envelope.operationId.rawValue == "editor-operation-retry")
        #expect(commands[1].draft.expectedRevision == ExpectedSpaceRevision(8))
        #expect(commands[1].draft.collection.checklists[0].id == Self.installationId)
        #expect(commands[1].draft.collection.checklists[0].name.rawValue == "Preserved Draft")
        await harness.stop()
    }

    @Test("A detail refresh arriving before rejection still preserves the draft")
    func detailBeforeRejectionPreservesDraft() async throws {
        let harness = try await Self.harness(operationIds: ["editor-operation-ordering"])
        let source = try Self.collection()
        await harness.receive(try Self.update(collection: source, revision: 7))
        harness.editor.open()
        harness.editor.renameChecklist(id: Self.installationId, name: "Keep Either Order")
        await harness.editor.save()
        let command = try #require((await harness.acceptance.commands()).editorOnly)

        await harness.receive(try Self.update(
            collection: source,
            revision: 8,
            version: "detail-before-rejection"
        ))
        #expect(harness.coordinator.hasActiveSubmission)

        harness.operations.source(for: command.envelope.operationId).yield(Self.snapshot(
            command: command,
            state: .rejected(Self.rejection()),
            updatedAt: Self.capturedAt.addingTimeInterval(2)
        ))
        await Self.waitUntil { !harness.coordinator.hasActiveSubmission }

        #expect(harness.editor.hasPreservedConflictDraft)
        #expect(harness.editor.canReviewPreservedConflict)
        harness.editor.reviewPreservedConflict()
        #expect(harness.editor.checklists[0].name == "Keep Either Order")
        await harness.stop()
    }

    @Test("Uncertain acceptance retries the identical operation from the editor")
    func uncertainAcceptanceRetriesExactly() async throws {
        let acceptance = EditorAcceptanceProbe(behaviors: [
            .failUncertain,
            .success(.queued),
        ])
        let harness = try await Self.harness(
            operationIds: ["editor-operation-uncertain"],
            acceptance: acceptance
        )
        await harness.receive(try Self.update(collection: Self.collection(), revision: 7))
        harness.editor.open()
        harness.editor.renameChecklist(id: Self.installationId, name: "Retry exactly")

        await harness.editor.save()
        #expect(harness.editor.isPresented)
        #expect(harness.editor.canRetryAmbiguousAcceptance)
        #expect(!harness.editor.canMutateDraft)
        #expect(!harness.editor.canCancel)
        #expect((await acceptance.commands()).count == 1)

        harness.editor.renameChecklist(id: Self.installationId, name: "Must not replace frozen draft")
        #expect(harness.editor.checklists[0].name == "Retry exactly")
        harness.editor.cancel()
        #expect(harness.editor.isPresented)

        await harness.editor.retryAmbiguousAcceptance()
        let commands = await acceptance.commands()
        #expect(commands.count == 2)
        #expect(commands[0] == commands[1])
        #expect(!harness.editor.isPresented)
        #expect(harness.coordinator.optimisticCollection == commands[0].draft.collection)
        await harness.stop()
    }

    @Test("A recreated editor adopts accepted optimism for later conflict review")
    func recreatedEditorAdoptsAcceptedDraft() async throws {
        let harness = try await Self.harness(operationIds: ["editor-operation-recreated"])
        let source = try Self.collection()
        let initial = try Self.update(collection: source, revision: 7)
        await harness.receive(initial)
        harness.editor.open()
        harness.editor.renameChecklist(id: Self.installationId, name: "Recovered Draft")
        await harness.editor.save()
        let command = try #require((await harness.acceptance.commands()).editorOnly)

        let recreated = SpaceChecklistEditorStagingExercise(
            coordinator: harness.coordinator,
            makeChecklistId: { try SpaceChecklistID(validating: "unused-checklist") },
            makeItemId: { try SpaceChecklistItemID(validating: "unused-item") }
        )
        await recreated.start()
        await recreated.receiveDetailUpdate(initial, selectedSpaceId: Self.spaceA)
        #expect(recreated.checklists[0].name == "Recovered Draft")

        harness.operations.source(for: command.envelope.operationId).yield(Self.snapshot(
            command: command,
            state: .rejected(Self.rejection()),
            updatedAt: Self.capturedAt.addingTimeInterval(2)
        ))
        await Self.waitUntil { harness.coordinator.operationState == .rejected }
        let refreshed = try Self.update(
            collection: source,
            revision: 8,
            version: "recreated-refreshed"
        )
        await harness.coordinator.receiveDetailUpdate(refreshed, selectedSpaceId: Self.spaceA)
        await recreated.receiveDetailUpdate(refreshed, selectedSpaceId: Self.spaceA)
        #expect(recreated.hasPreservedConflictDraft)
        #expect(recreated.checklists[0].name == "Recovered Draft")
        #expect(recreated.canReviewPreservedConflict)

        await recreated.stop()
        await harness.stop()
    }

    @Test("Selection replacement cancels and drains an in-flight save")
    func selectionReplacementDrainsSave() async throws {
        let acceptance = EditorAcceptanceProbe(behaviors: [.suspendUntilCancelled])
        let harness = try await Self.harness(
            operationIds: ["editor-operation-suspended"],
            acceptance: acceptance
        )
        await harness.receive(try Self.update(collection: Self.collection(), revision: 7))
        harness.editor.open()
        harness.editor.renameChecklist(id: Self.installationId, name: "Pending")
        let save = Task { await harness.editor.save() }
        await Self.waitUntil { harness.editor.isSaving }

        await harness.editor.receiveDetailUpdate(nil, selectedSpaceId: Self.spaceB)
        await save.value
        #expect(!harness.editor.isSaving)
        #expect(!harness.editor.isPresented)
        #expect(harness.editor.checklists.isEmpty)
        #expect(await acceptance.cancellationCount() == 1)
        await harness.stop()
    }

    @Test("Compiled SwiftUI exposes only the claimed accessible editor controls")
    func swiftUISourceContract() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(
            path: "LedgerTargetApp/SpaceCoreDetailsStagingExerciseView.swift"
        ))
        for token in [
            "target-space-checklist-editor-open",
            "target-space-checklist-editor-name-",
            "target-space-checklist-editor-item-text-",
            "target-space-checklist-editor-check-",
            "target-space-checklist-editor-add-item-",
            "target-space-checklist-editor-add-checklist",
            "target-space-checklist-editor-delete-item-",
            "target-space-checklist-editor-delete-checklist-",
            ".onMove",
            ".environment(\\.editMode, .constant(.active))",
            "target-space-checklist-editor-save",
            "target-space-checklist-editor-cancel",
            "target-space-checklist-editor-review-conflict",
            "target-space-checklist-editor-retry-acceptance",
        ] {
            #expect(source.contains(token), "Missing editor UI token: \(token)")
        }
        #expect(!source.contains("Space Options"))
        #expect(!source.contains("Save as Template"))
    }

    private static let accountId = try! AccountID(validating: "account-primary")
    private static let principalId = try! PrincipalID(validating: "principal-owner")
    private static let spaceA = try! SpaceID(validating: "space-primary")
    private static let spaceB = try! SpaceID(validating: "space-secondary")
    private static let projectId = try! ProjectID(validating: "project-primary")
    private static let installationId = try! SpaceChecklistID(validating: "installation")
    private static let emptyChecklistId = try! SpaceChecklistID(validating: "empty-list")
    private static let firstItemId = try! SpaceChecklistItemID(validating: "hang-art")
    private static let secondItemId = try! SpaceChecklistItemID(validating: "place-lamp")
    private static let capturedAt = Date(timeIntervalSince1970: 1_788_700_000)
    private static let contractVersion = try! OperationContractVersion(
        validating: "space-checklist-revision-v1"
    )

    private static func harness(
        operationIds: [String],
        checklistIds: [String] = [],
        itemIds: [String] = [],
        acceptance: EditorAcceptanceProbe? = nil
    ) async throws -> EditorHarness {
        let acceptance = acceptance ?? EditorAcceptanceProbe(
            behaviors: operationIds.map { _ in .success(.queued) }
        )
        let operations = EditorOperationWatchProbe()
        let operationSequence = EditorStringSequence(operationIds)
        let coordinator = SpaceChecklistItemToggleStagingExercise(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: contractVersion,
            makeIdentity: {
                SpaceChecklistItemToggleSubmissionIdentity(
                    operationId: try OperationID(validating: operationSequence.next())
                )
            },
            now: { capturedAt }
        )
        let checklistSequence = EditorStringSequence(checklistIds)
        let itemSequence = EditorStringSequence(itemIds)
        let editor = SpaceChecklistEditorStagingExercise(
            coordinator: coordinator,
            makeChecklistId: {
                try SpaceChecklistID(validating: checklistSequence.next())
            },
            makeItemId: {
                try SpaceChecklistItemID(validating: itemSequence.next())
            }
        )
        await coordinator.start(runtime: SpaceChecklistItemToggleStagingRuntime(
            reviseChecklists: { try await acceptance.revise($0) },
            watchOperation: { operations.watch($0) }
        ))
        await editor.start()
        return EditorHarness(
            coordinator: coordinator,
            editor: editor,
            acceptance: acceptance,
            operations: operations
        )
    }

    private static func collection() throws -> SpaceChecklistCollection {
        try SpaceChecklistCollection(checklists: [
            SpaceChecklistState(
                id: installationId,
                name: SpaceChecklistName(validating: "Installation"),
                presentationOrder: 5,
                items: [
                    SpaceChecklistItemState(
                        id: firstItemId,
                        text: SpaceChecklistItemText(validating: "Hang art"),
                        isChecked: false,
                        presentationOrder: 10
                    ),
                    SpaceChecklistItemState(
                        id: secondItemId,
                        text: SpaceChecklistItemText(validating: "Place lamp"),
                        isChecked: true,
                        presentationOrder: 30
                    ),
                ]
            ),
            SpaceChecklistState(
                id: emptyChecklistId,
                name: SpaceChecklistName(validating: "Empty list"),
                presentationOrder: 20,
                items: []
            ),
        ])
    }

    private static func update(
        collection: SpaceChecklistCollection,
        revision: UInt64,
        lifecycle: DirectoryLifecycleState = .active,
        quality: ListSnapshotQuality = .ready,
        version: String = "initial"
    ) throws -> SpaceCoreDetailsUpdate {
        let request = try SpaceCoreDetailsRequest(accountId: accountId, spaceId: spaceA)
        return try SpaceCoreDetailsUpdate(
            request: request,
            state: .snapshot(localSnapshot(
                collection: collection,
                revision: revision,
                lifecycle: lifecycle,
                quality: quality,
                version: version
            ))
        )
    }

    private static func localSnapshot(
        collection: SpaceChecklistCollection,
        revision: UInt64,
        lifecycle: DirectoryLifecycleState = .active,
        quality: ListSnapshotQuality = .ready,
        version: String = "initial"
    ) throws -> SpaceCoreDetailsLocalSnapshot {
        let request = try SpaceCoreDetailsRequest(accountId: accountId, spaceId: spaceA)
        let row = try SpaceCoreDetailsSnapshot(
            id: spaceA,
            accountId: accountId,
            scope: .project(projectId),
            displayName: SpaceDisplayName(validating: "Living Room"),
            notes: SpaceCreationNotes("Install before Friday"),
            lifecycle: lifecycle,
            revision: revision,
            createdAt: capturedAt.addingTimeInterval(-100),
            updatedAt: capturedAt.addingTimeInterval(TimeInterval(revision)),
            checklists: collection
        )
        return try SpaceCoreDetailsLocalSnapshot(
            request: request,
            rows: [row],
            visibleRowCountBeforeFiltering: 1,
            isCompleteForQuery: quality == .ready,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: capturedAt.addingTimeInterval(TimeInterval(revision))
        )
    }

    private static func snapshot(
        command: ReviseSpaceChecklistsCommand,
        state: OperationState,
        updatedAt: Date
    ) -> OperationSnapshot {
        OperationSnapshot(
            operationId: command.envelope.operationId,
            accountId: command.envelope.accountId,
            contractVersion: command.envelope.contractVersion,
            fingerprint: command.fingerprint,
            acceptedAt: capturedAt,
            updatedAt: updatedAt,
            state: state
        )
    }

    private static func rejection() -> OperationRejection {
        OperationRejection(
            error: ApplicationErrorSummary(
                code: try! ApplicationErrorCode(validating: "space_revision_conflict"),
                category: .conflict,
                retryDisposition: .afterUserCorrection
            ),
            rejectedAt: capturedAt.addingTimeInterval(2),
            conflictingEntities: []
        )
    }

    private static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for checklist editor state")
    }
}

@MainActor
private struct EditorHarness {
    let coordinator: SpaceChecklistItemToggleStagingExercise
    let editor: SpaceChecklistEditorStagingExercise
    let acceptance: EditorAcceptanceProbe
    let operations: EditorOperationWatchProbe

    func receive(_ update: SpaceCoreDetailsUpdate?) async {
        await coordinator.receiveDetailUpdate(update, selectedSpaceId: update?.request.spaceId)
        await editor.receiveDetailUpdate(update, selectedSpaceId: update?.request.spaceId)
    }

    func stop() async {
        await editor.stop()
        await coordinator.stop()
    }
}

private final class EditorStringSequence {
    private var values: [String]

    init(_ values: [String]) { self.values = values }

    @MainActor
    func next() -> String { values.removeFirst() }
}

private actor EditorAcceptanceProbe {
    enum Behavior: Sendable {
        case success(LocalOperationState)
        case failUncertain
        case suspendUntilCancelled
    }

    private var behaviors: [Behavior]
    private var recorded: [ReviseSpaceChecklistsCommand] = []
    private var cancellations = 0

    init(behaviors: [Behavior]) { self.behaviors = behaviors }

    func revise(_ command: ReviseSpaceChecklistsCommand) async throws -> OperationReceipt {
        recorded.append(command)
        let behavior = behaviors.removeFirst()
        switch behavior {
        case .success(let state):
            return OperationReceipt(operationId: command.envelope.operationId, localState: state)
        case .failUncertain:
            throw EditorAcceptanceFailure.uncertain
        case .suspendUntilCancelled:
            do {
                try await Task.sleep(for: .seconds(60))
                throw CancellationError()
            } catch is CancellationError {
                cancellations += 1
                throw CancellationError()
            }
        }
    }

    func commands() -> [ReviseSpaceChecklistsCommand] { recorded }
    func cancellationCount() -> Int { cancellations }
}

private enum EditorAcceptanceFailure: Error {
    case uncertain
}

private final class EditorOperationWatchProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [OperationID: EditorControlledStream<OperationSnapshot>] = [:]

    func source(for id: OperationID) -> EditorControlledStream<OperationSnapshot> {
        lock.withLock {
            if let source = sources[id] { return source }
            let source = EditorControlledStream<OperationSnapshot>()
            sources[id] = source
            return source
        }
    }

    func watch(_ id: OperationID) -> AsyncThrowingStream<OperationSnapshot, Error> {
        source(for: id).stream
    }
}

private final class EditorControlledStream<Element: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Element, Error>
    private let continuation: AsyncThrowingStream<Element, Error>.Continuation

    init() {
        var captured: AsyncThrowingStream<Element, Error>.Continuation!
        stream = AsyncThrowingStream { captured = $0 }
        continuation = captured
    }

    func yield(_ element: Element) { continuation.yield(element) }
}

private extension Array {
    var editorOnly: Element? { count == 1 ? first : nil }
}
