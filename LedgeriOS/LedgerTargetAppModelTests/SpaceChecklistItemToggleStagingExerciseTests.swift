import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Active Space checklist-item toggle staging application")
@MainActor
struct SpaceChecklistItemToggleStagingExerciseTests {
    @Test("Compiled SwiftUI source exposes the bounded accessible toggle workflow")
    func swiftUISourceContract() throws {
        let ledgerDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(contentsOf: ledgerDirectory.appending(
            path: "LedgerTargetApp/SpaceCoreDetailsStagingExerciseView.swift"
        ))

        for required in [
            "DisclosureGroup(isExpanded: $isChecklistsExpanded)",
            "target-space-checklists-section",
            "target-space-checklists-empty",
            "target-space-checklists-unavailable",
            "target-space-checklist-item-",
            "target-space-checklist-operation-status",
            "target-space-checklist-admission",
            "target-space-checklist-diagnostic",
            "target-space-checklist-retry-acceptance",
            "checklistToggle.canToggle(",
            "await checklistToggle.toggle(",
            "await checklistToggle.receiveDetailUpdate(",
            "item.isChecked ? \"Checked\" : \"Not checked\"",
            "No checklists.",
            "Archived checklist progress",
        ] {
            #expect(view.contains(required), "Missing SwiftUI contract token: \(required)")
        }

        for excluded in [
            "Delete Space",
            "Mark space complete",
        ] {
            #expect(!view.contains(excluded), "Out-of-scope UI escaped: \(excluded)")
        }
        #expect(
            SpaceChecklistItemToggleAdmission.archived.explanation ==
                "Archived Spaces are read-only in this workflow."
        )
    }

    @Test("A fresh AppModel recovers a durable checklist operation and reattaches its watch")
    func restartRecovery() async throws {
        let acceptance = ChecklistRevisionAcceptanceProbe(behaviors: [])
        let operations = ChecklistOperationWatchProbe()
        let model = Self.model(identities: ChecklistIdentitySequence(["unused-operation"]))
        await model.start(runtime: Self.runtime(acceptance: acceptance, operations: operations))

        let projected = try Self.collection(firstChecked: true)
        let projection = try Self.projection(
            operationId: "checklist-operation-recovered",
            collection: projected,
            localState: .queued
        )
        let recoveredUpdate = try Self.update(
            collection: projected,
            revision: 8,
            version: "reopened-overlay",
            projection: projection
        )
        let updateBytes = try OperationContractCodec.encode(recoveredUpdate)
        #expect(
            try OperationContractCodec.decode(
                SpaceCoreDetailsUpdate.self,
                from: updateBytes
            ) == recoveredUpdate
        )
        let presentation = try SpaceChecklistEditingPresentation(
            projecting: recoveredUpdate
        )
        #expect(
            try OperationContractCodec.decode(
                SpaceChecklistEditingPresentation.self,
                from: OperationContractCodec.encode(presentation)
            ) == presentation
        )
        await model.receiveDetailUpdate(
            recoveredUpdate,
            selectedSpaceId: Self.spaceA
        )

        #expect(model.optimisticCollection == projected)
        #expect(model.operationState == .queued)
        #expect(model.operationIdLabel == projection.operationId.rawValue)
        #expect(!model.canToggle(checklistId: Self.checklistId, itemId: Self.firstItemId))
        #expect((await acceptance.recordedCommands()).isEmpty)
        await Self.waitUntil { operations.ids == [projection.operationId] }

        let stream = operations.source(for: projection.operationId)
        stream.yield(Self.snapshot(
            projection: projection,
            state: .applied(Self.appliedResult(revision: 8)),
            updatedAt: Self.capturedAt.addingTimeInterval(3)
        ))
        await Self.waitUntil { model.operationState == .applied }
        await model.receiveDetailUpdate(
            try Self.update(
                collection: projected,
                revision: 8,
                updatedAt: Self.capturedAt.addingTimeInterval(0.001),
                version: "reopened-authoritative"
            ),
            selectedSpaceId: Self.spaceA
        )
        #expect(model.optimisticCollection == nil)
        #expect(model.operationStatus == "applied — authoritative readback received")
        await model.stop()
    }

    @Test("Recovered optimism remains bound to the active principal")
    func recoveredPrincipalBinding() async throws {
        let model = Self.model(identities: ChecklistIdentitySequence(["unused-operation"]))
        await model.start(runtime: Self.runtime(
            acceptance: ChecklistRevisionAcceptanceProbe(behaviors: []),
            operations: ChecklistOperationWatchProbe()
        ))
        let collection = try Self.collection(firstChecked: true)
        let valid = try Self.projection(
            operationId: "checklist-operation-other-principal",
            collection: collection,
            localState: .queued
        )
        let rebound = try SpaceChecklistRevisionLocalProjection(
            operationId: valid.operationId,
            accountId: valid.accountId,
            actorPrincipalId: PrincipalID(validating: "principal-other"),
            contractVersion: valid.contractVersion,
            fingerprint: valid.fingerprint,
            spaceId: valid.spaceId,
            expectedRevision: valid.expectedRevision,
            projectedRevision: valid.projectedRevision,
            collection: valid.collection,
            acceptedAt: valid.acceptedAt,
            localState: valid.localState
        )
        await model.receiveDetailUpdate(
            try Self.update(
                collection: collection,
                revision: 8,
                version: "other-principal-overlay",
                projection: rebound
            ),
            selectedSpaceId: Self.spaceA
        )
        #expect(model.admission == .unavailable)
        #expect(model.diagnostic == "space_checklist_toggle_operation_evidence_invalid")
        #expect(!model.canToggle(checklistId: Self.checklistId, itemId: Self.firstItemId))
        await model.stop()
    }

    @Test("Rejection settles safely when detail arrives first and ignores overlay caches")
    func rejectionOrderingAndOverlayProvenance() async throws {
        let acceptance = ChecklistRevisionAcceptanceProbe(behaviors: [.success(.queued)])
        let operations = ChecklistOperationWatchProbe()
        let model = Self.model(identities: ChecklistIdentitySequence(["checklist-operation-ordering"]))
        await model.start(runtime: Self.runtime(acceptance: acceptance, operations: operations))
        let original = try Self.collection(firstChecked: false)
        await model.receiveDetailUpdate(
            try Self.update(collection: original, revision: 7),
            selectedSpaceId: Self.spaceA
        )
        await model.toggle(checklistId: Self.checklistId, itemId: Self.firstItemId)
        let command = try #require((await acceptance.recordedCommands()).only)
        await Self.waitUntil { operations.ids == [command.envelope.operationId] }

        let projection = try Self.projection(command: command, localState: .queued)
        let cachedOverlay = try Self.local(
            collection: command.draft.collection,
            revision: 8,
            quality: .ready,
            version: "delayed-overlay",
            projection: projection
        )
        await model.receiveDetailUpdate(
            try SpaceCoreDetailsUpdate(
                request: Self.request(),
                state: .failed(failure: .retryable, cached: cachedOverlay)
            ),
            selectedSpaceId: Self.spaceA
        )
        #expect(model.optimisticCollection != nil)

        await model.receiveDetailUpdate(
            try Self.update(collection: original, revision: 7, version: "detail-first"),
            selectedSpaceId: Self.spaceA
        )
        let stream = operations.source(for: command.envelope.operationId)
        stream.yield(Self.snapshot(
            command: command,
            state: .rejected(Self.rejection()),
            updatedAt: Self.capturedAt.addingTimeInterval(2)
        ))
        await Self.waitUntil { model.operationState == .rejected && model.optimisticCollection == nil }
        #expect(model.operationStatus == "rejected — review required")
        await model.stop()
    }

    @Test("Active represented toggle freezes one payload and reconciles applied readback")
    func toggleAndAppliedReadback() async throws {
        let acceptance = ChecklistRevisionAcceptanceProbe(behaviors: [.success(.queued)])
        let operations = ChecklistOperationWatchProbe()
        let model = Self.model(identities: ChecklistIdentitySequence(["checklist-operation-1"]))
        await model.start(runtime: Self.runtime(acceptance: acceptance, operations: operations))

        let source = try Self.collection(firstChecked: false)
        let initial = try Self.update(collection: source, revision: 7)
        await model.receiveDetailUpdate(initial, selectedSpaceId: Self.spaceA)

        #expect(model.admission == .ready)
        #expect(model.canToggle(checklistId: Self.checklistId, itemId: Self.firstItemId))
        await model.toggle(checklistId: Self.checklistId, itemId: Self.firstItemId)

        let command = try #require((await acceptance.recordedCommands()).only)
        #expect(command.envelope.operationId.rawValue == "checklist-operation-1")
        #expect(command.draft.expectedRevision == ExpectedSpaceRevision(7))
        #expect(command.draft.collection.checklists.count == 2)
        #expect(command.draft.collection.checklists[0].items[0].isChecked)
        #expect(command.draft.collection.checklists[0].items[1].isChecked)
        #expect(command.draft.collection.checklists[1].items.isEmpty)
        #expect(model.optimisticCollection == command.draft.collection)
        #expect(model.completedItemCount == 2)
        #expect(model.totalItemCount == 2)
        #expect(model.operationState == .queued)
        #expect(model.operationStatus == "queued — accepted locally")
        #expect(!model.canToggle(checklistId: Self.checklistId, itemId: Self.firstItemId))

        await Self.waitUntil { operations.ids == [command.envelope.operationId] }
        let stream = operations.source(for: command.envelope.operationId)
        stream.yield(Self.snapshot(command: command, state: .applying(
            attempt: 1,
            startedAt: Self.capturedAt.addingTimeInterval(1)
        ), updatedAt: Self.capturedAt.addingTimeInterval(1)))
        await Self.waitUntil { model.operationState == .applying }

        stream.yield(Self.snapshot(
            command: command,
            state: .applied(Self.appliedResult(revision: 8)),
            updatedAt: Self.capturedAt.addingTimeInterval(3)
        ))
        await Self.waitUntil { model.operationState == .applied }
        #expect(model.operationStatus == "applied — awaiting authoritative readback")
        #expect(model.optimisticCollection != nil)

        let projectedLocalOverlay = try Self.update(
            collection: command.draft.collection,
            revision: 8,
            version: "local-overlay-8"
        )
        await model.receiveDetailUpdate(projectedLocalOverlay, selectedSpaceId: Self.spaceA)
        #expect(model.optimisticCollection != nil)
        #expect(model.operationStatus == "applied — awaiting authoritative readback")

        let authoritative = try Self.update(
            collection: command.draft.collection,
            revision: 8,
            updatedAt: Self.capturedAt.addingTimeInterval(0.001),
            version: "authoritative-8"
        )
        await model.receiveDetailUpdate(authoritative, selectedSpaceId: Self.spaceA)
        #expect(model.optimisticCollection == nil)
        #expect(model.operationStatus == "applied — authoritative readback received")
        #expect(model.canToggle(checklistId: Self.checklistId, itemId: Self.firstItemId))
        await Self.waitUntil { stream.terminationCount == 1 }
        await model.stop()
    }

    @Test("Only current or retryable cached active evidence admits a toggle")
    func exactAdmissionBoundary() async throws {
        let acceptance = ChecklistRevisionAcceptanceProbe(behaviors: [.success(.queued)])
        let operations = ChecklistOperationWatchProbe()
        let model = Self.model(identities: ChecklistIdentitySequence(["checklist-operation-stale"]))
        await model.start(runtime: Self.runtime(acceptance: acceptance, operations: operations))
        let collection = try Self.collection(firstChecked: false)

        let partial = try Self.update(collection: collection, revision: 7, quality: .partial)
        await model.receiveDetailUpdate(partial, selectedSpaceId: Self.spaceA)
        #expect(model.admission == .incomplete)
        #expect(!model.canToggle(checklistId: Self.checklistId, itemId: Self.firstItemId))

        let archived = try Self.update(
            collection: collection,
            revision: 7,
            lifecycle: .archived,
            version: "archived"
        )
        await model.receiveDetailUpdate(archived, selectedSpaceId: Self.spaceA)
        #expect(model.admission == .archived)
        await model.toggle(checklistId: Self.checklistId, itemId: Self.firstItemId)
        #expect((await acceptance.recordedCommands()).isEmpty)

        let absent = try Self.update(rows: [], version: "absent")
        await model.receiveDetailUpdate(absent, selectedSpaceId: Self.spaceA)
        #expect(model.admission == .authoritativeAbsence)

        let unavailable = try SpaceCoreDetailsUpdate(
            request: Self.request(),
            state: .failed(failure: .unavailable, cached: nil)
        )
        await model.receiveDetailUpdate(unavailable, selectedSpaceId: Self.spaceA)
        #expect(model.admission == .unavailable)

        let cached = try Self.local(
            collection: collection,
            revision: 7,
            quality: .ready,
            version: "retryable-cache"
        )
        let stale = try SpaceCoreDetailsUpdate(
            request: Self.request(),
            state: .failed(failure: .retryable, cached: cached)
        )
        await model.receiveDetailUpdate(stale, selectedSpaceId: Self.spaceA)
        #expect(model.admission == .retryableStale)
        #expect(model.canToggle(checklistId: Self.checklistId, itemId: Self.firstItemId))
        await model.toggle(checklistId: Self.checklistId, itemId: Self.firstItemId)
        #expect((await acceptance.recordedCommands()).count == 1)
        await model.stop()
    }

    @Test("Rejected optimism becomes durable review-only work after refreshed evidence")
    func rejectedRefreshRemainsUnresolved() async throws {
        let acceptance = ChecklistRevisionAcceptanceProbe(
            behaviors: [.success(.queued), .success(.queued)]
        )
        let operations = ChecklistOperationWatchProbe()
        let model = Self.model(identities: ChecklistIdentitySequence([
            "checklist-operation-rejected",
            "checklist-operation-retry",
        ]))
        await model.start(runtime: Self.runtime(acceptance: acceptance, operations: operations))
        let original = try Self.collection(firstChecked: false)
        await model.receiveDetailUpdate(
            try Self.update(collection: original, revision: 7),
            selectedSpaceId: Self.spaceA
        )
        await model.toggle(checklistId: Self.checklistId, itemId: Self.firstItemId)
        let first = try #require((await acceptance.recordedCommands()).only)
        await Self.waitUntil { operations.ids.count == 1 }
        let firstStream = operations.source(for: first.envelope.operationId)
        firstStream.yield(Self.snapshot(
            command: first,
            state: .rejected(Self.rejection()),
            updatedAt: Self.capturedAt.addingTimeInterval(2)
        ))
        await Self.waitUntil { model.operationState == .rejected }

        #expect(model.optimisticCollection != nil)
        #expect(model.operationStatus == "rejected — review required")
        await model.toggle(checklistId: Self.checklistId, itemId: Self.firstItemId)
        #expect((await acceptance.recordedCommands()).count == 1)

        let delayedProjection = try Self.projection(command: first, localState: .queued)
        await model.receiveDetailUpdate(
            try Self.update(
                collection: first.draft.collection,
                revision: 8,
                version: "delayed-overlay-after-rejection",
                projection: delayedProjection
            ),
            selectedSpaceId: Self.spaceA
        )
        #expect(model.optimisticCollection != nil)
        let cachedOverlay = try Self.local(
            collection: first.draft.collection,
            revision: 8,
            quality: .ready,
            version: "cached-overlay-after-rejection",
            projection: delayedProjection
        )
        await model.receiveDetailUpdate(
            try SpaceCoreDetailsUpdate(
                request: Self.request(),
                state: .failed(failure: .retryable, cached: cachedOverlay)
            ),
            selectedSpaceId: Self.spaceA
        )
        #expect(model.optimisticCollection != nil)

        await model.receiveDetailUpdate(
            try Self.update(collection: original, revision: 8, version: "refreshed-8"),
            selectedSpaceId: Self.spaceA
        )
        #expect(model.optimisticCollection == nil)
        #expect(model.operationStatus == "rejected — review required")
        #expect(model.rejectedRecovery?.operationId == first.envelope.operationId)
        #expect(!model.canToggle(checklistId: Self.checklistId, itemId: Self.firstItemId))
        await Self.waitUntil { firstStream.terminationCount == 1 }

        await model.toggle(checklistId: Self.checklistId, itemId: Self.firstItemId)
        let commands = await acceptance.recordedCommands()
        #expect(commands.count == 1)
        #expect(commands[0].envelope.operationId.rawValue == "checklist-operation-rejected")
        await model.stop()
    }

    @Test("Ambiguous local acceptance retries the frozen command identity and payload")
    func ambiguousAcceptanceRetry() async throws {
        let acceptance = ChecklistRevisionAcceptanceProbe(
            behaviors: [.failure(ChecklistAcceptanceError()), .success(.queued)]
        )
        let operations = ChecklistOperationWatchProbe()
        let model = Self.model(identities: ChecklistIdentitySequence([
            "checklist-operation-ambiguous"
        ]))
        await model.start(runtime: Self.runtime(acceptance: acceptance, operations: operations))
        let original = try Self.collection(firstChecked: false)
        await model.receiveDetailUpdate(
            try Self.update(collection: original, revision: 7),
            selectedSpaceId: Self.spaceA
        )

        await model.toggle(checklistId: Self.checklistId, itemId: Self.firstItemId)
        #expect(model.canRetryAmbiguousAcceptance)
        #expect(model.operationStatus == "acceptance uncertain")
        #expect(model.optimisticCollection == nil)
        await model.retryAmbiguousAcceptance()

        let commands = await acceptance.recordedCommands()
        #expect(commands.count == 2)
        #expect(commands[0].envelope.operationId == commands[1].envelope.operationId)
        #expect(commands[0].fingerprint == commands[1].fingerprint)
        #expect(commands[0].draft.collection == commands[1].draft.collection)
        #expect(model.operationState == .queued)
        #expect(model.optimisticCollection == commands[1].draft.collection)
        await model.stop()
    }

    @Test("Wrong operation evidence fails closed")
    func invalidOperationEvidence() async throws {
        let acceptance = ChecklistRevisionAcceptanceProbe(behaviors: [.success(.queued)])
        let operations = ChecklistOperationWatchProbe()
        let model = Self.model(identities: ChecklistIdentitySequence(["checklist-operation-invalid"]))
        await model.start(runtime: Self.runtime(acceptance: acceptance, operations: operations))
        let original = try Self.collection(firstChecked: false)
        await model.receiveDetailUpdate(
            try Self.update(collection: original, revision: 7),
            selectedSpaceId: Self.spaceA
        )
        await model.toggle(checklistId: Self.checklistId, itemId: Self.firstItemId)
        let command = try #require((await acceptance.recordedCommands()).only)
        await Self.waitUntil { operations.ids.count == 1 }
        let stream = operations.source(for: command.envelope.operationId)
        stream.yield(OperationSnapshot(
            operationId: try OperationID(validating: "wrong-operation"),
            accountId: command.envelope.accountId,
            contractVersion: command.envelope.contractVersion,
            fingerprint: command.fingerprint,
            acceptedAt: Self.capturedAt,
            updatedAt: Self.capturedAt,
            state: .queued(attemptCount: 0, lastTransientError: nil)
        ))
        await Self.waitUntil {
            model.diagnostic == "space_checklist_toggle_operation_evidence_invalid"
        }
        await Self.waitUntil { stream.terminationCount == 1 }
        #expect(model.optimisticCollection != nil)
        #expect(!model.canToggle(checklistId: Self.checklistId, itemId: Self.firstItemId))
        await model.stop()
    }

    @Test("Reselection and stop cancel and drain operation observation")
    func reselectionAndStopDrainage() async throws {
        let acceptance = ChecklistRevisionAcceptanceProbe(
            behaviors: [.success(.queued), .success(.queued)]
        )
        let operations = ChecklistOperationWatchProbe()
        let model = Self.model(identities: ChecklistIdentitySequence([
            "checklist-operation-space-a",
            "checklist-operation-space-b",
        ]))
        await model.start(runtime: Self.runtime(acceptance: acceptance, operations: operations))
        let original = try Self.collection(firstChecked: false)
        await model.receiveDetailUpdate(
            try Self.update(collection: original, revision: 7),
            selectedSpaceId: Self.spaceA
        )
        await model.toggle(checklistId: Self.checklistId, itemId: Self.firstItemId)
        let first = try #require((await acceptance.recordedCommands()).only)
        await Self.waitUntil { operations.ids.count == 1 }
        let firstStream = operations.source(for: first.envelope.operationId)

        await model.receiveDetailUpdate(nil, selectedSpaceId: Self.spaceB)
        #expect(model.selectedSpaceId == Self.spaceB)
        #expect(model.optimisticCollection == nil)
        #expect(model.operationState == nil)
        await Self.waitUntil { firstStream.terminationCount == 1 }

        let secondCollection = try Self.collection(firstChecked: true)
        await model.receiveDetailUpdate(
            try Self.update(
                spaceId: Self.spaceB,
                collection: secondCollection,
                revision: 4,
                version: "space-b"
            ),
            selectedSpaceId: Self.spaceB
        )
        await model.toggle(checklistId: Self.checklistId, itemId: Self.firstItemId)
        let second = (await acceptance.recordedCommands())[1]
        await Self.waitUntil { operations.ids.count == 2 }
        let secondStream = operations.source(for: second.envelope.operationId)
        await model.stop()
        #expect(model.admission == .stopped)
        #expect(model.selectedSpaceId == nil)
        await Self.waitUntil { secondStream.terminationCount == 1 }
    }

    private static let accountId = try! AccountID(validating: "account-primary")
    private static let principalId = try! PrincipalID(validating: "principal-owner")
    private static let spaceA = try! SpaceID(validating: "space-primary")
    private static let spaceB = try! SpaceID(validating: "space-secondary")
    private static let projectId = try! ProjectID(validating: "project-primary")
    private static let checklistId = try! SpaceChecklistID(validating: "installation")
    private static let firstItemId = try! SpaceChecklistItemID(validating: "hang-art")
    private static let secondItemId = try! SpaceChecklistItemID(validating: "place-lamp")
    private static let capturedAt = Date(timeIntervalSince1970: 1_788_700_000)
    private static let contractVersion = try! OperationContractVersion(
        validating: "space-checklist-revision-v1"
    )

    private static func model(
        identities: ChecklistIdentitySequence
    ) -> SpaceChecklistItemToggleStagingExercise {
        SpaceChecklistItemToggleStagingExercise(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: contractVersion,
            makeIdentity: { try identities.next() },
            now: { capturedAt }
        )
    }

    private static func runtime(
        acceptance: ChecklistRevisionAcceptanceProbe,
        operations: ChecklistOperationWatchProbe
    ) -> SpaceChecklistItemToggleStagingRuntime {
        SpaceChecklistItemToggleStagingRuntime(
            reviseChecklists: { try await acceptance.revise($0) },
            watchOperation: { operations.watch($0) },
            rejectedOperations: { request in
                try RejectedOperationRecoverySnapshot(request: request, candidates: [])
            },
            watchRejectedOperations: { request in
                AsyncThrowingStream { continuation in
                    do {
                        continuation.yield(try RejectedOperationRecoverySnapshot(
                            request: request,
                            candidates: []
                        ))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        )
    }

    private static func request(
        spaceId: SpaceID = spaceA
    ) throws -> SpaceCoreDetailsRequest {
        try SpaceCoreDetailsRequest(accountId: accountId, spaceId: spaceId)
    }

    private static func collection(firstChecked: Bool) throws -> SpaceChecklistCollection {
        try SpaceChecklistCollection(checklists: [
            SpaceChecklistState(
                id: checklistId,
                name: SpaceChecklistName(validating: "Installation"),
                presentationOrder: 2,
                items: [
                    SpaceChecklistItemState(
                        id: firstItemId,
                        text: SpaceChecklistItemText(validating: "Hang art"),
                        isChecked: firstChecked,
                        presentationOrder: 4
                    ),
                    SpaceChecklistItemState(
                        id: secondItemId,
                        text: SpaceChecklistItemText(validating: "Place lamp"),
                        isChecked: true,
                        presentationOrder: 9
                    ),
                ]
            ),
            SpaceChecklistState(
                id: SpaceChecklistID(validating: "empty-list"),
                name: SpaceChecklistName(validating: "Empty valid list"),
                presentationOrder: 8,
                items: []
            ),
        ])
    }

    private static func row(
        spaceId: SpaceID = spaceA,
        collection: SpaceChecklistCollection,
        revision: UInt64,
        lifecycle: DirectoryLifecycleState = .active,
        updatedAt: Date = capturedAt
    ) throws -> SpaceCoreDetailsSnapshot {
        try SpaceCoreDetailsSnapshot(
            id: spaceId,
            accountId: accountId,
            scope: .project(projectId),
            displayName: SpaceDisplayName(validating: "Living Room"),
            notes: SpaceCreationNotes("Install before Friday"),
            lifecycle: lifecycle,
            revision: revision,
            createdAt: capturedAt.addingTimeInterval(-100),
            updatedAt: updatedAt,
            checklists: collection
        )
    }

    private static func local(
        spaceId: SpaceID = spaceA,
        collection: SpaceChecklistCollection,
        revision: UInt64,
        lifecycle: DirectoryLifecycleState = .active,
        updatedAt: Date = capturedAt,
        quality: ListSnapshotQuality,
        version: String,
        projection: SpaceChecklistRevisionLocalProjection? = nil
    ) throws -> SpaceCoreDetailsLocalSnapshot {
        let request = try request(spaceId: spaceId)
        return try SpaceCoreDetailsLocalSnapshot(
            request: request,
            rows: [try row(
                spaceId: spaceId,
                collection: collection,
                revision: revision,
                lifecycle: lifecycle,
                updatedAt: updatedAt
            )],
            visibleRowCountBeforeFiltering: 1,
            isCompleteForQuery: quality == .ready,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: capturedAt,
            checklistRevisionProjection: projection
        )
    }

    private static func update(
        spaceId: SpaceID = spaceA,
        collection: SpaceChecklistCollection,
        revision: UInt64,
        lifecycle: DirectoryLifecycleState = .active,
        updatedAt: Date = capturedAt,
        quality: ListSnapshotQuality = .ready,
        version: String = "initial",
        projection: SpaceChecklistRevisionLocalProjection? = nil
    ) throws -> SpaceCoreDetailsUpdate {
        let request = try request(spaceId: spaceId)
        return try SpaceCoreDetailsUpdate(
            request: request,
            state: .snapshot(try local(
                spaceId: spaceId,
                collection: collection,
                revision: revision,
                lifecycle: lifecycle,
                updatedAt: updatedAt,
                quality: quality,
                version: version,
                projection: projection
            ))
        )
    }

    private static func update(
        rows: [SpaceCoreDetailsSnapshot],
        version: String
    ) throws -> SpaceCoreDetailsUpdate {
        let request = try request()
        return try SpaceCoreDetailsUpdate(
            request: request,
            state: .snapshot(SpaceCoreDetailsLocalSnapshot(
                request: request,
                rows: rows,
                visibleRowCountBeforeFiltering: rows.count,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: capturedAt
            ))
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

    private static func snapshot(
        projection: SpaceChecklistRevisionLocalProjection,
        state: OperationState,
        updatedAt: Date
    ) -> OperationSnapshot {
        OperationSnapshot(
            operationId: projection.operationId,
            accountId: projection.accountId,
            contractVersion: projection.contractVersion,
            fingerprint: projection.fingerprint,
            acceptedAt: projection.acceptedAt,
            updatedAt: updatedAt,
            state: state
        )
    }

    private static func projection(
        operationId: String,
        collection: SpaceChecklistCollection,
        localState: LocalOperationState
    ) throws -> SpaceChecklistRevisionLocalProjection {
        let draft = try SpaceChecklistRevisionDraft(
            accountId: accountId,
            actorPrincipalId: principalId,
            operationContractVersion: contractVersion,
            spaceId: spaceA,
            collection: collection,
            expectedRevision: ExpectedSpaceRevision(7),
            capturedAt: capturedAt
        )
        return try projection(
            command: ReviseSpaceChecklistsCommand(
                operationId: OperationID(validating: operationId),
                draft: draft
            ),
            localState: localState
        )
    }

    private static func projection(
        command: ReviseSpaceChecklistsCommand,
        localState: LocalOperationState
    ) throws -> SpaceChecklistRevisionLocalProjection {
        try SpaceChecklistRevisionLocalProjection(
            operationId: command.envelope.operationId,
            accountId: command.envelope.accountId,
            actorPrincipalId: command.envelope.actorPrincipalId,
            contractVersion: command.envelope.contractVersion,
            fingerprint: command.fingerprint,
            spaceId: command.draft.spaceId,
            expectedRevision: command.draft.expectedRevision.rawValue,
            projectedRevision: command.draft.expectedRevision.rawValue + 1,
            collection: command.draft.collection,
            acceptedAt: capturedAt,
            localState: localState
        )
    }

    private static func appliedResult(revision: UInt64) -> AppliedOperationResult {
        AppliedOperationResult(
            resultCode: try! ApplicationResultCode(validating: "space_checklists_revised"),
            serverReceivedAt: capturedAt.addingTimeInterval(1),
            completedAt: capturedAt.addingTimeInterval(2),
            affectedRevisions: [
                EntityRevision(
                    entity: LedgerEntityReference(
                        kind: .space,
                        id: try! EntityID(validating: spaceA.rawValue)
                    ),
                    revision: revision
                )
            ]
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
            conflictingEntities: [
                LedgerEntityReference(
                    kind: .space,
                    id: try! EntityID(validating: spaceA.rawValue)
                )
            ]
        )
    }

    private static func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for checklist toggle state")
    }
}

private final class ChecklistIdentitySequence {
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    @MainActor
    func next() throws -> SpaceChecklistItemToggleSubmissionIdentity {
        SpaceChecklistItemToggleSubmissionIdentity(
            operationId: try OperationID(validating: values.removeFirst())
        )
    }
}

private actor ChecklistRevisionAcceptanceProbe {
    enum Behavior: @unchecked Sendable {
        case success(LocalOperationState)
        case failure(Error)
    }

    private var behaviors: [Behavior]
    private var commands: [ReviseSpaceChecklistsCommand] = []

    init(behaviors: [Behavior]) {
        self.behaviors = behaviors
    }

    func revise(_ command: ReviseSpaceChecklistsCommand) throws -> OperationReceipt {
        commands.append(command)
        guard !behaviors.isEmpty else {
            throw SpaceChecklistRevisionFailure.localAcceptanceFailed
        }
        switch behaviors.removeFirst() {
        case .success(let state):
            return OperationReceipt(
                operationId: command.envelope.operationId,
                localState: state
            )
        case .failure(let error):
            throw error
        }
    }

    func recordedCommands() -> [ReviseSpaceChecklistsCommand] { commands }
}

private final class ChecklistOperationWatchProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var watchedIds: [OperationID] = []
    private var sources: [OperationID: ChecklistControlledStream<OperationSnapshot>] = [:]

    var ids: [OperationID] { lock.withLock { watchedIds } }

    func source(
        for operationId: OperationID
    ) -> ChecklistControlledStream<OperationSnapshot> {
        lock.withLock {
            if let source = sources[operationId] { return source }
            let source = ChecklistControlledStream<OperationSnapshot>()
            sources[operationId] = source
            return source
        }
    }

    func watch(
        _ operationId: OperationID
    ) -> AsyncThrowingStream<OperationSnapshot, Error> {
        lock.withLock {
            watchedIds.append(operationId)
            if let source = sources[operationId] {
                return source.stream
            }
            let source = ChecklistControlledStream<OperationSnapshot>()
            sources[operationId] = source
            return source.stream
        }
    }
}

private final class ChecklistControlledStream<Value: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Value, Error>
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation
    private let termination = ChecklistTerminationProbe()

    init() {
        var captured: AsyncThrowingStream<Value, Error>.Continuation?
        let termination = termination
        stream = AsyncThrowingStream { continuation in
            captured = continuation
            continuation.onTermination = { _ in termination.record() }
        }
        continuation = captured!
    }

    var terminationCount: Int { termination.count }

    func yield(_ value: Value) {
        continuation.yield(value)
    }
}

private final class ChecklistTerminationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var count: Int { lock.withLock { storage } }

    func record() {
        lock.withLock { storage += 1 }
    }
}

private struct ChecklistAcceptanceError: Error {}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
