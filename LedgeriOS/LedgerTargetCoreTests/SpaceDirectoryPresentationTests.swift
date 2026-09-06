import CryptoKit
import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Space List Read and Presentation Contracts")
struct SpaceDirectoryPresentationTests {
    @Test("Exact scopes, active rows, total order, checklist progress, and unavailable Item count")
    func exactScopeActivePresentationAndDerivedProgress() throws {
        let project = try Self.projectFixture()
        let presentation = try ActiveSpaceDirectoryPresentationSnapshot(source: project.snapshot)

        #expect(project.request.accountId == project.accountId)
        #expect(project.request.scope == .project(project.projectId))
        #expect(presentation.accountId == project.accountId)
        #expect(presentation.scope == project.request.scope)
        #expect(presentation.sourceRows.map(\.id.rawValue) == [
            "space-archived", "space-kitchen", "space-loft-uppercase",
            "space-loft-a", "space-loft-z"
        ])
        #expect(presentation.rows.map(\.id.rawValue) == [
            "space-kitchen", "space-loft-uppercase", "space-loft-a", "space-loft-z"
        ])
        #expect(presentation.rows.map(\.displayName.rawValue) == ["Kitchen", "Loft", "loft", "loft"])
        #expect(presentation.rows.allSatisfy { $0.lifecycle == .active })
        #expect(presentation.rows.allSatisfy { $0.accountId == project.accountId })
        #expect(presentation.rows.allSatisfy { $0.scope == project.request.scope })
        #expect(presentation.rows.allSatisfy { $0.itemCountState == .unavailable })
        #expect(presentation.rows.map(\.completedChecklistItemCount) == [0, 0, 1, 0])
        #expect(presentation.rows.map(\.totalChecklistItemCount) == [0, 0, 2, 0])
        #expect(presentation.sourceRowCount == 5)
        #expect(presentation.visibleRowCountBeforeFiltering == 5)
        #expect(presentation.readiness == .ready)
        #expect(!presentation.isAuthoritativeEmpty)

        let inventoryRequest = try SpaceListRequest(accountId: project.accountId, scope: .businessInventory)
        let inventoryRow = try Self.row(
            id: "space-warehouse", accountId: project.accountId, scope: .businessInventory,
            name: "Warehouse", revision: 41, checklists: .empty
        )
        let inventory = try Self.snapshot(request: inventoryRequest, rows: [inventoryRow])
        #expect(inventory.local.rows == [inventoryRow])
        #expect(inventory.request != project.request)

        let crossAccount = try Self.row(
            id: "space-foreign", accountId: AccountID(validating: "account-other"),
            scope: project.request.scope, name: "Foreign", revision: 1, checklists: .empty
        )
        #expect(Self.failure { try Self.snapshot(request: project.request, rows: [crossAccount]) }
            == .accountScopeMismatch)
        let crossScope = try Self.row(
            id: "space-inventory", accountId: project.accountId, scope: .businessInventory,
            name: "Inventory", revision: 1, checklists: .empty
        )
        #expect(Self.failure { try Self.snapshot(request: project.request, rows: [crossScope]) }
            == .spaceScopeMismatch)
        #expect(Self.failure {
            try Self.snapshot(
                request: project.request,
                rows: [project.snapshot.local.rows[0], project.snapshot.local.rows[0]]
            )
        } == .duplicateSpaceIdentity)
    }

    @Test("Only complete ready exact-query evidence proves active-list absence")
    func falseEmptyAndFailureRefusal() throws {
        let request = try Self.request()
        let authoritative = try Self.snapshot(
            request: request, rows: [], complete: true, quality: .ready,
            version: "space-empty-ready"
        )
        let incomplete = try Self.snapshot(
            request: request, rows: [], complete: false, quality: .ready,
            version: "space-empty-incomplete"
        )
        let partial = try Self.snapshot(
            request: request, rows: [], complete: false, quality: .partial,
            version: "space-empty-partial"
        )
        let stale = try Self.snapshot(
            request: request, rows: [], complete: false, quality: .stale,
            version: "space-empty-stale"
        )
        #expect(try ActiveSpaceDirectoryPresentationSnapshot(source: authoritative).isAuthoritativeEmpty)
        #expect(!(try ActiveSpaceDirectoryPresentationSnapshot(source: incomplete)).isAuthoritativeEmpty)
        #expect(!(try ActiveSpaceDirectoryPresentationSnapshot(source: partial)).isAuthoritativeEmpty)
        #expect(!(try ActiveSpaceDirectoryPresentationSnapshot(source: stale)).isAuthoritativeEmpty)

        let represented = try Self.row(
            id: "space-cached", accountId: request.accountId, scope: request.scope,
            name: "Cached", revision: 2, checklists: .twoItems
        )
        for quality in [ListSnapshotQuality.partial, .stale] {
            let snapshot = try Self.snapshot(
                request: request, rows: [represented], complete: false, quality: quality,
                version: "space-\(quality.rawValue)"
            )
            let presentation = try ActiveSpaceDirectoryPresentationSnapshot(source: snapshot)
            #expect(presentation.rows.map(\.id) == [represented.id])
            #expect(presentation.readiness == quality.readiness)
            #expect(presentation.rows[0].itemCountState == .unavailable)
        }

        #expect(Self.failure {
            try Self.snapshot(request: request, rows: [], visibleCount: 1)
        } == .visibleCountMismatch)
        #expect(Self.failure {
            try Self.snapshot(request: request, rows: [], complete: true, quality: .partial)
        } == .invalidCompleteness)
        #expect(Self.failure {
            try Self.snapshot(
                request: request, rows: [], complete: false,
                asOf: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidSnapshotAsOf)
        let wrongFingerprint = try ListQueryFingerprint(validating: String(repeating: "d", count: 64))
        #expect(Self.failure {
            try SpaceListLocalSnapshot(
                request: request,
                local: ListLocalSnapshot(
                    queryFingerprint: wrongFingerprint, rows: [],
                    visibleRowCountBeforeFiltering: 0, isCompleteForQuery: false,
                    quality: .ready, localDataVersion: LocalDataVersion(validating: "wrong-query"),
                    asOf: Self.t0
                )
            )
        } == .queryFingerprintMismatch)
        #expect(Self.failure {
            try SpaceListUpdate(request: request, state: .failed(failure: .unavailable, cached: partial))
        } == .unavailableCachedEvidence)
        let representedReady = try Self.snapshot(
            request: request, rows: [represented], complete: true, quality: .ready,
            version: "space-cached-row-ready"
        )
        for failure in [ListFailureState.retryable, .requiredUpdate] {
            let failedEmpty = try SpaceListUpdate(
                request: request,
                state: .failed(failure: failure, cached: authoritative)
            )
            guard case .failed(let projectedFailure, let cachedEmpty) =
                try failedEmpty.presentingActiveDirectory() else {
                Issue.record("Cached failure did not project as an explicit failed presentation")
                continue
            }
            #expect(projectedFailure == failure)
            let cachedEmptyPresentation = try #require(cachedEmpty)
            #expect(cachedEmptyPresentation.rows.isEmpty)
            #expect(cachedEmptyPresentation.readiness == .stale)
            #expect(!cachedEmptyPresentation.isCompleteForQuery)
            #expect(!cachedEmptyPresentation.isAuthoritativeEmpty)

            let failedRepresented = try SpaceListUpdate(
                request: request,
                state: .failed(failure: failure, cached: representedReady)
            )
            guard case .failed(let representedFailure, let cachedRows) =
                try failedRepresented.presentingActiveDirectory() else {
                Issue.record("Represented cached failure did not retain failed evidence")
                continue
            }
            #expect(representedFailure == failure)
            let cachedRowsPresentation = try #require(cachedRows)
            #expect(cachedRowsPresentation.rows.map(\.id) == [represented.id])
            #expect(cachedRowsPresentation.readiness == .stale)
            #expect(!cachedRowsPresentation.isCompleteForQuery)
            #expect(!cachedRowsPresentation.isAuthoritativeEmpty)

            let failedWithoutCache = try SpaceListUpdate(
                request: request,
                state: .failed(failure: failure, cached: nil)
            )
            #expect(try failedWithoutCache.presentingActiveDirectory()
                == .failed(failure: failure, cached: nil))
        }
        let unavailable = try SpaceListUpdate(
            request: request,
            state: .failed(failure: .unavailable, cached: nil)
        )
        #expect(try unavailable.presentingActiveDirectory()
            == .failed(failure: .unavailable, cached: nil))
        let otherRequest = try SpaceListRequest(
            accountId: request.accountId,
            scope: .businessInventory
        )
        let otherSnapshot = try Self.snapshot(
            request: otherRequest,
            rows: [],
            version: "space-other-request-cache"
        )
        for failure in [ListFailureState.retryable, .requiredUpdate] {
            #expect(Self.failure {
                try SpaceListUpdate(
                    request: request,
                    state: .failed(failure: failure, cached: otherSnapshot)
                )
            } == .updateRequestMismatch)
        }
        #expect(try SpaceListUpdate(request: request, state: .snapshot(authoritative))
            .presentingActiveDirectory()
            == .snapshot(ActiveSpaceDirectoryPresentationSnapshot(source: authoritative)))
        for readiness in [ListReadiness.notRequested, .loading, .blocked] {
            #expect(try SpaceListUpdate(request: request, state: .waiting(readiness)).state
                == .waiting(readiness))
        }
        for readiness in [ListReadiness.ready, .partial, .stale] {
            #expect(Self.failure { try SpaceListUpdate(request: request, state: .waiting(readiness)) }
                == .invalidWaitingState)
        }
    }

    @Test("Request, source, presentation, and selection restart canonically and reject tamper")
    func canonicalRestartAndTamperRejection() throws {
        let fixture = try Self.projectFixture()
        let presentation = try ActiveSpaceDirectoryPresentationSnapshot(source: fixture.snapshot)
        let selection = try SpaceBrowsingSelection(selecting: presentation.rows[2].id, in: presentation)
        let restart = RestartFixture(
            request: fixture.request, snapshot: fixture.snapshot,
            presentation: presentation, selection: selection
        )
        let bytes = try OperationContractCodec.encode(restart)
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)
        #expect(restored == restart)
        #expect(try OperationContractCodec.encode(restored) == bytes)

        let expected = try Self.fingerprint(RequestFingerprintBasis(
            contractVersion: "space-list-request-v1",
            accountId: fixture.accountId,
            scope: fixture.request.scope
        ))
        #expect(fixture.request.queryFingerprint == expected)
        let expectedPresentation = try Self.fingerprint(PresentationFingerprintBasis(
            contractVersion: "space-list-presentation-evidence-v1",
            accountId: presentation.accountId,
            scope: presentation.scope,
            sourceRows: presentation.sourceRows,
            rows: presentation.rows,
            sourceQueryFingerprint: presentation.sourceQueryFingerprint,
            sourceRowCount: presentation.sourceRowCount,
            visibleRowCountBeforeFiltering: presentation.visibleRowCountBeforeFiltering,
            isCompleteForQuery: presentation.isCompleteForQuery,
            quality: presentation.quality,
            localDataVersion: presentation.localDataVersion,
            asOf: presentation.asOf
        ))
        #expect(presentation.evidenceFingerprint == expectedPresentation)
        let expectedSelection = try Self.fingerprint(SelectionFingerprintBasis(
            contractVersion: "space-browsing-selection-v1",
            accountId: selection.accountId,
            scope: selection.scope,
            row: selection.row,
            directoryEvidenceFingerprint: selection.directoryEvidenceFingerprint
        ))
        #expect(selection.selectionFingerprint == expectedSelection)
        #expect(fixture.request.queryFingerprint.sha256.utf8.count == 64)
        #expect(presentation.evidenceFingerprint.sha256.utf8.count == 64)
        #expect(selection.selectionFingerprint.sha256.utf8.count == 64)

        let requestBytes = try OperationContractCodec.encode(fixture.request)
        #expect(Self.failure {
            try OperationContractCodec.decode(
                SpaceListRequest.self,
                from: Self.mutating(requestBytes) {
                    $0["queryFingerprint"] = String(repeating: "a", count: 64)
                }
            )
        } == .requestFingerprintMismatch)
        #expect(Self.failure {
            try OperationContractCodec.decode(
                SpaceListRequest.self,
                from: Self.mutating(requestBytes) { $0["extra"] = true }
            )
        } == .invalidEncodedRequest)
        for removeKey in [false, true] {
            #expect(Self.failure {
                try OperationContractCodec.decode(
                    SpaceListRequest.self,
                    from: Self.mutating(requestBytes) {
                        var scope = $0["scope"] as! [String: Any]
                        if removeKey { scope.removeValue(forKey: "projectId") }
                        else { scope["extra"] = true }
                        $0["scope"] = scope
                    }
                )
            } == .invalidEncodedRequest)
        }
        let snapshotBytes = try OperationContractCodec.encode(fixture.snapshot)
        #expect(Self.failure {
            try OperationContractCodec.decode(
                SpaceListLocalSnapshot.self,
                from: Self.mutating(snapshotBytes) {
                    var local = $0["local"] as! [String: Any]
                    local["hidden"] = 0
                    $0["local"] = local
                }
            )
        } == .invalidEncodedLocalSnapshot)

        let presentationBytes = try OperationContractCodec.encode(presentation)
        #expect(Self.failure {
            try OperationContractCodec.decode(
                ActiveSpaceDirectoryPresentationSnapshot.self,
                from: Self.mutating(presentationBytes) {
                    $0["evidenceFingerprint"] = String(repeating: "b", count: 64)
                }
            )
        } == .presentationFingerprintMismatch)
        #expect(Self.failure {
            try OperationContractCodec.decode(
                ActiveSpaceDirectoryPresentationSnapshot.self,
                from: Self.mutating(presentationBytes) {
                    var rows = $0["sourceRows"] as! [[String: Any]]
                    rows.swapAt(0, 1)
                    $0["sourceRows"] = rows
                }
            )
        } == .noncanonicalRows)
        #expect(Self.failure {
            try OperationContractCodec.decode(
                ActiveSpaceDirectoryPresentationSnapshot.self,
                from: Self.mutating(presentationBytes) { $0["sourceRowCount"] = 99 }
            )
        } == .visibleCountMismatch)

        let selectionBytes = try OperationContractCodec.encode(selection)
        #expect(Self.failure {
            try OperationContractCodec.decode(
                SpaceBrowsingSelection.self,
                from: Self.mutating(selectionBytes) {
                    $0["selectionFingerprint"] = String(repeating: "c", count: 64)
                }
            )
        } == .selectionFingerprintMismatch)
        #expect(Self.failure {
            try OperationContractCodec.decode(
                SpaceBrowsingSelection.self,
                from: Self.mutating(selectionBytes) { $0.removeValue(forKey: "scope") }
            )
        } == .invalidEncodedSelection)
        let sourceRowBytes = try OperationContractCodec.encode(fixture.snapshot.local.rows[0])
        #expect(Self.failure {
            try OperationContractCodec.decode(
                SpaceListSourceRow.self,
                from: Self.mutating(sourceRowBytes) { $0["revision"] = -1 }
            )
        } == .invalidEncodedSourceRow)

        let checklistRow = try #require(
            fixture.snapshot.local.rows.first { $0.totalChecklistItemCount == 2 }
        )
        let checklistRowBytes = try OperationContractCodec.encode(checklistRow)
        for mutation in [NestedChecklistMutation.collection, .checklist, .item] {
            for removeKey in [false, true] {
                #expect(Self.failure {
                    try OperationContractCodec.decode(
                        SpaceListSourceRow.self,
                        from: Self.mutating(checklistRowBytes) {
                            Self.mutateChecklistJSON(
                                &$0,
                                mutation: mutation,
                                removeKey: removeKey
                            )
                        }
                    )
                } == .invalidEncodedSourceRow)
            }
        }

        let presentationRowBytes = try OperationContractCodec.encode(presentation.rows[0])
        for removeKey in [false, true] {
            #expect(Self.failure {
                try OperationContractCodec.decode(
                    SpaceDirectoryRowPresentation.self,
                    from: Self.mutating(presentationRowBytes) {
                        if removeKey { $0.removeValue(forKey: "lifecycle") }
                        else { $0["extra"] = true }
                    }
                )
            } == .invalidEncodedPresentationRow)
        }

        let waitingUpdate = try SpaceListUpdate(request: fixture.request, state: .waiting(.loading))
        let snapshotUpdate = try SpaceListUpdate(
            request: fixture.request,
            state: .snapshot(fixture.snapshot)
        )
        let failedUpdate = try SpaceListUpdate(
            request: fixture.request,
            state: .failed(failure: .retryable, cached: nil)
        )
        for (update, stateKey, associatedKey) in [
            (waitingUpdate, "waiting", "_0"),
            (snapshotUpdate, "snapshot", "_0"),
            (failedUpdate, "failed", "cached")
        ] {
            let updateBytes = try OperationContractCodec.encode(update)
            for removeKey in [false, true] {
                #expect(Self.failure {
                    try OperationContractCodec.decode(
                        SpaceListUpdate.self,
                        from: Self.mutating(updateBytes) {
                            var state = $0["state"] as! [String: Any]
                            var associated = state[stateKey] as! [String: Any]
                            if removeKey { associated.removeValue(forKey: associatedKey) }
                            else { associated["extra"] = true }
                            state[stateKey] = associated
                            $0["state"] = state
                        }
                    )
                } == .invalidEncodedUpdate)
            }
        }
    }

    @Test("Selection is represented-ID and evidence bound and preserves immutable detail identity")
    func exactSelectionAndDetailContinuity() throws {
        let fixture = try Self.projectFixture()
        let directory = try ActiveSpaceDirectoryPresentationSnapshot(source: fixture.snapshot)
        let selected = directory.rows[2]
        let selection = try SpaceBrowsingSelection(selecting: selected.id, in: directory)
        let request = try selection.detailRequest(validating: directory)
        #expect(request.accountId == fixture.accountId)
        #expect(request.spaceId == selected.id)
        #expect(selected.displayName == directory.rows[3].displayName)
        #expect(request.spaceId != directory.rows[3].id)
        #expect(Self.failure {
            try SpaceBrowsingSelection(selecting: fixture.archivedId, in: directory)
        } == .missingSelection)
        #expect(Self.failure {
            try SpaceBrowsingSelection(selecting: SpaceID(validating: "space-absent"), in: directory)
        } == .missingSelection)

        let refreshedRow = try Self.row(
            id: selected.id.rawValue, accountId: fixture.accountId, scope: fixture.request.scope,
            name: "Renamed Later", revision: selected.revision + 1, checklists: .twoItems
        )
        let refreshedSource = try Self.snapshot(
            request: fixture.request,
            rows: fixture.snapshot.local.rows.filter { $0.id != selected.id } + [refreshedRow],
            version: "space-project-refreshed", asOf: Self.t1
        )
        let refreshed = try ActiveSpaceDirectoryPresentationSnapshot(source: refreshedSource)
        #expect(Self.failure { try selection.detailRequest(validating: refreshed) }
            == .selectionEvidenceMismatch)

        let wrongAccountId = try AccountID(validating: "account-selection-other")
        let wrongAccountRequest = try SpaceListRequest(
            accountId: wrongAccountId,
            scope: fixture.request.scope
        )
        let wrongAccountRow = try Self.row(
            id: selected.id.rawValue,
            accountId: wrongAccountId,
            scope: fixture.request.scope,
            name: selected.displayName.rawValue,
            revision: selected.revision,
            checklists: .twoItems
        )
        let wrongAccountDirectory = try ActiveSpaceDirectoryPresentationSnapshot(
            source: Self.snapshot(
                request: wrongAccountRequest,
                rows: [wrongAccountRow],
                version: "space-selection-wrong-account"
            )
        )
        #expect(Self.failure {
            try selection.detailRequest(validating: wrongAccountDirectory)
        } == .selectionEvidenceMismatch)

        let wrongScopeRequest = try SpaceListRequest(
            accountId: fixture.accountId,
            scope: .businessInventory
        )
        let wrongScopeRow = try Self.row(
            id: selected.id.rawValue,
            accountId: fixture.accountId,
            scope: .businessInventory,
            name: selected.displayName.rawValue,
            revision: selected.revision,
            checklists: .twoItems
        )
        let wrongScopeDirectory = try ActiveSpaceDirectoryPresentationSnapshot(
            source: Self.snapshot(
                request: wrongScopeRequest,
                rows: [wrongScopeRow],
                version: "space-selection-wrong-scope"
            )
        )
        #expect(Self.failure {
            try selection.detailRequest(validating: wrongScopeDirectory)
        } == .selectionEvidenceMismatch)

        let laterDetail = try Self.detail(
            accountId: fixture.accountId, spaceId: selected.id, scope: fixture.request.scope,
            name: "Renamed Later", revision: selected.revision + 10, lifecycle: .archived
        )
        #expect(try selection.validateDetail(laterDetail) == laterDetail)
        #expect(Self.failure {
            try selection.validateDetail(Self.detail(
                accountId: AccountID(validating: "account-other"),
                spaceId: selected.id, scope: fixture.request.scope
            ))
        } == .detailIdentityMismatch)
        #expect(Self.failure {
            try selection.validateDetail(Self.detail(
                accountId: fixture.accountId, spaceId: SpaceID(validating: "space-other"),
                scope: fixture.request.scope
            ))
        } == .detailIdentityMismatch)
        #expect(Self.failure {
            try selection.validateDetail(Self.detail(
                accountId: fixture.accountId, spaceId: selected.id, scope: .businessInventory
            ))
        } == .detailIdentityMismatch)
    }

    @Test("Reference query validates exact updates and propagates failure and cancellation")
    func exactPortFailureAndCancellation() async throws {
        let fixture = try Self.projectFixture()
        let updates = try [
            SpaceListUpdate(request: fixture.request, state: .waiting(.loading)),
            SpaceListUpdate(request: fixture.request, state: .snapshot(fixture.snapshot))
        ]
        let exact = await Self.collect(ReferencePort(updates: updates), fixture.request)
        #expect(exact.updates == updates)
        #expect(exact.failure == nil)
        #expect(exact.unexpectedError == nil)

        let otherRequest = try SpaceListRequest(accountId: fixture.accountId, scope: .businessInventory)
        let rebound = await Self.collect(ReferencePort(updates: updates), otherRequest)
        #expect(rebound.updates.isEmpty)
        #expect(rebound.failure == .updateRequestMismatch)
        #expect(rebound.unexpectedError == nil)
        let failed = await Self.collect(FailingPort(), fixture.request)
        #expect(failed.updates.isEmpty)
        #expect(failed.failure == .localReadFailed)
        #expect(failed.unexpectedError == nil)
        let unexpected = await Self.collect(UnexpectedFailingPort(), fixture.request)
        #expect(unexpected.updates.isEmpty)
        #expect(unexpected.failure == nil)
        #expect(unexpected.unexpectedError?.contains("unexpectedPortFailure") == true)

        let probe = CancellationProbe()
        let cancellable = CancellablePort(updates: updates, probe: probe)
        let consumer = Task { () -> [SpaceListUpdate] in
            var received: [SpaceListUpdate] = []
            do {
                for try await update in cancellable.watchSpaces(fixture.request) {
                    received.append(try update.validating(request: fixture.request))
                    await probe.markFirstDelivery()
                }
            } catch {}
            return received
        }
        #expect(await probe.waitForFirstDelivery())
        consumer.cancel()
        #expect(await consumer.value == [updates[0]])
        #expect(await probe.waitForCancellation())
    }

    @Test("Encoded API is exactly the provider-free active-list foundation")
    func encodedBoundaryAndDiagnostics() throws {
        let fixture = try Self.projectFixture()
        let presentation = try ActiveSpaceDirectoryPresentationSnapshot(source: fixture.snapshot)
        let selection = try SpaceBrowsingSelection(selecting: presentation.rows[0].id, in: presentation)
        let update = try SpaceListUpdate(request: fixture.request, state: .snapshot(fixture.snapshot))
        let envelope = BoundaryFixture(
            request: fixture.request, source: fixture.snapshot, presentation: presentation,
            selection: selection, update: update
        )
        let bytes = try OperationContractCodec.encode(envelope)
        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        #expect(text.contains("itemcountstate"))
        #expect(text.contains("unavailable"))
        for forbidden in [
            "\"itemcount\":", "\"spaceitems\":", "media", "image", "attachment", "search",
            "route", "firebase", "firestore", "supabase", "powersync", "sql",
            "credential", "token", "authorized", "permission", "transaction",
            "invoice", "budget", "accounting", "mutation", "archivecommand"
        ] {
            #expect(!text.contains(forbidden))
        }
        #expect(try OperationContractCodec.encode(
            OperationContractCodec.decode(BoundaryFixture.self, from: bytes)
        ) == bytes)

        let diagnostics = SpaceListFailure.allForTests.map(\.diagnosticCode)
        #expect(Set(diagnostics).count == diagnostics.count)
        for code in diagnostics {
            #expect(code.utf8.count <= 80)
            #expect(code.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" })
            #expect(!code.contains("account-"))
            #expect(!code.contains("project-"))
            #expect(!code.contains("space-"))
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_804_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_804_000_001)

    private struct ProjectFixture {
        let accountId: AccountID
        let projectId: ProjectID
        let request: SpaceListRequest
        let snapshot: SpaceListLocalSnapshot
        let archivedId: SpaceID
    }

    private static func projectFixture() throws -> ProjectFixture {
        let accountId = try AccountID(validating: "account-space-list")
        let projectId = try ProjectID(validating: "project-space-list")
        let scope = SpaceCreationScope.project(projectId)
        let request = try SpaceListRequest(accountId: accountId, scope: scope)
        let archived = try row(
            id: "space-archived", accountId: accountId, scope: scope,
            name: "Archive", lifecycle: .archived, revision: 5, checklists: .empty
        )
        let rows = try [
            row(id: "space-loft-z", accountId: accountId, scope: scope, name: "loft", revision: 10, checklists: .empty),
            row(id: "space-kitchen", accountId: accountId, scope: scope, name: "Kitchen", revision: 7, checklists: .empty),
            archived,
            row(id: "space-loft-a", accountId: accountId, scope: scope, name: "loft", revision: 9, checklists: .twoItems),
            row(id: "space-loft-uppercase", accountId: accountId, scope: scope, name: "Loft", revision: 8, checklists: .zeroItemChecklist)
        ]
        return ProjectFixture(
            accountId: accountId, projectId: projectId, request: request,
            snapshot: try snapshot(request: request, rows: rows, version: "space-project-ready"),
            archivedId: archived.id
        )
    }

    private static func request() throws -> SpaceListRequest {
        try SpaceListRequest(
            accountId: AccountID(validating: "account-space-list"),
            scope: .project(ProjectID(validating: "project-space-list"))
        )
    }

    private static func row(
        id: String,
        accountId: AccountID,
        scope: SpaceCreationScope,
        name: String,
        lifecycle: DirectoryLifecycleState = .active,
        revision: UInt64,
        checklists: ChecklistFixture
    ) throws -> SpaceListSourceRow {
        SpaceListSourceRow(
            id: try SpaceID(validating: id), accountId: accountId, scope: scope,
            displayName: try SpaceDisplayName(validating: name), lifecycle: lifecycle,
            revision: revision, checklists: try checklists.collection()
        )
    }

    private static func snapshot(
        request: SpaceListRequest,
        rows: [SpaceListSourceRow],
        visibleCount: Int? = nil,
        complete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        version: String = "space-list-version",
        asOf: Date = t0
    ) throws -> SpaceListLocalSnapshot {
        try SpaceListLocalSnapshot(
            request: request, rows: rows,
            visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
            isCompleteForQuery: complete, quality: quality,
            localDataVersion: LocalDataVersion(validating: version), asOf: asOf
        )
    }

    private static func detail(
        accountId: AccountID,
        spaceId: SpaceID,
        scope: SpaceCreationScope,
        name: String = "Detail",
        revision: UInt64 = 1,
        lifecycle: DirectoryLifecycleState = .active
    ) throws -> SpaceCoreDetailsSnapshot {
        try SpaceCoreDetailsSnapshot(
            id: spaceId, accountId: accountId, scope: scope,
            displayName: SpaceDisplayName(validating: name),
            notes: SpaceCreationNotes("later notes"), lifecycle: lifecycle,
            revision: revision, createdAt: t0, updatedAt: t1,
            checklists: ChecklistFixture.twoItems.collection()
        )
    }

    private enum ChecklistFixture {
        case empty, zeroItemChecklist, twoItems

        func collection() throws -> SpaceChecklistCollection {
            switch self {
            case .empty:
                return try SpaceChecklistCollection(checklists: [])
            case .zeroItemChecklist:
                return try SpaceChecklistCollection(checklists: [
                    SpaceChecklistState(
                        id: SpaceChecklistID(validating: "checklist-empty"),
                        name: SpaceChecklistName(validating: "Empty"),
                        presentationOrder: 0, items: []
                    )
                ])
            case .twoItems:
                return try SpaceChecklistCollection(checklists: [
                    SpaceChecklistState(
                        id: SpaceChecklistID(validating: "checklist-main"),
                        name: SpaceChecklistName(validating: "Main"),
                        presentationOrder: 0,
                        items: [
                            SpaceChecklistItemState(
                                id: SpaceChecklistItemID(validating: "checklist-item-a"),
                                text: SpaceChecklistItemText(validating: "Done"),
                                isChecked: true, presentationOrder: 0
                            ),
                            SpaceChecklistItemState(
                                id: SpaceChecklistItemID(validating: "checklist-item-b"),
                                text: SpaceChecklistItemText(validating: "Pending"),
                                isChecked: false, presentationOrder: 1
                            )
                        ]
                    )
                ])
            }
        }
    }

    private struct RestartFixture: Codable, Equatable {
        let request: SpaceListRequest
        let snapshot: SpaceListLocalSnapshot
        let presentation: ActiveSpaceDirectoryPresentationSnapshot
        let selection: SpaceBrowsingSelection
    }

    private struct BoundaryFixture: Codable, Equatable {
        let request: SpaceListRequest
        let source: SpaceListLocalSnapshot
        let presentation: ActiveSpaceDirectoryPresentationSnapshot
        let selection: SpaceBrowsingSelection
        let update: SpaceListUpdate
    }

    private struct RequestFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let scope: SpaceCreationScope
    }

    private struct PresentationFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let scope: SpaceCreationScope
        let sourceRows: [SpaceListSourceRow]
        let rows: [SpaceDirectoryRowPresentation]
        let sourceQueryFingerprint: ListQueryFingerprint
        let sourceRowCount: Int
        let visibleRowCountBeforeFiltering: Int
        let isCompleteForQuery: Bool
        let quality: ListSnapshotQuality
        let localDataVersion: LocalDataVersion
        let asOf: Date
    }

    private struct SelectionFingerprintBasis: Codable {
        let contractVersion: String
        let accountId: AccountID
        let scope: SpaceCreationScope
        let row: SpaceDirectoryRowPresentation
        let directoryEvidenceFingerprint: ListQueryFingerprint
    }

    private enum NestedChecklistMutation: Equatable {
        case collection, checklist, item
    }

    private static func fingerprint<Value: Encodable>(_ value: Value) throws -> ListQueryFingerprint {
        let digest = SHA256.hash(data: try OperationContractCodec.encode(value))
            .map { String(format: "%02x", $0) }.joined()
        return try ListQueryFingerprint(validating: digest)
    }

    private static func mutating(
        _ data: Data,
        _ change: (inout [String: Any]) -> Void
    ) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func mutateChecklistJSON(
        _ root: inout [String: Any],
        mutation: NestedChecklistMutation,
        removeKey: Bool
    ) {
        var collection = root["checklists"] as! [String: Any]
        if mutation == .collection {
            if removeKey { collection.removeValue(forKey: "checklists") }
            else { collection["extra"] = true }
            root["checklists"] = collection
            return
        }

        var checklists = collection["checklists"] as! [[String: Any]]
        var checklist = checklists[0]
        if mutation == .checklist {
            if removeKey { checklist.removeValue(forKey: "name") }
            else { checklist["extra"] = true }
        } else {
            var items = checklist["items"] as! [[String: Any]]
            if removeKey { items[0].removeValue(forKey: "text") }
            else { items[0]["extra"] = true }
            checklist["items"] = items
        }
        checklists[0] = checklist
        collection["checklists"] = checklists
        root["checklists"] = collection
    }

    private static func failure<Value>(_ operation: () throws -> Value) -> SpaceListFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as SpaceListFailure {
            return failure
        } catch {
            Issue.record("Unexpected non-SpaceListFailure: \(error)")
            return nil
        }
    }

    private static func collect(
        _ port: some SpaceListQuerying,
        _ request: SpaceListRequest
    ) async -> (
        updates: [SpaceListUpdate],
        failure: SpaceListFailure?,
        unexpectedError: String?
    ) {
        var updates: [SpaceListUpdate] = []
        do {
            for try await update in port.watchSpaces(request) {
                updates.append(try update.validating(request: request))
            }
            return (updates, nil, nil)
        } catch let failure as SpaceListFailure {
            return (updates, failure, nil)
        } catch {
            return (updates, nil, String(describing: error))
        }
    }
}

private extension SpaceListFailure {
    static let allForTests: [Self] = [
        .accountScopeMismatch, .spaceScopeMismatch, .inactiveSelection, .missingSelection,
        .selectionEvidenceMismatch, .detailIdentityMismatch, .duplicateSpaceIdentity,
        .visibleCountMismatch, .invalidSnapshotAsOf, .invalidCompleteness,
        .noncanonicalRows, .requestFingerprintMismatch, .queryFingerprintMismatch,
        .presentationFingerprintMismatch, .selectionFingerprintMismatch,
        .updateRequestMismatch, .invalidWaitingState, .unavailableCachedEvidence,
        .localReadFailed, .invalidEncodedRequest, .invalidEncodedSourceRow,
        .invalidEncodedLocalSnapshot, .invalidEncodedPresentationRow,
        .invalidEncodedPresentation, .invalidEncodedSelection, .invalidEncodedUpdate
    ]
}

private struct ReferencePort: SpaceListQuerying {
    let updates: [SpaceListUpdate]
    func watchSpaces(_ request: SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        AsyncThrowingStream { continuation in
            do {
                for update in updates { continuation.yield(try update.validating(request: request)) }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
}

private struct FailingPort: SpaceListQuerying {
    func watchSpaces(_ request: SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        AsyncThrowingStream { $0.finish(throwing: SpaceListFailure.localReadFailed) }
    }
}

private enum UnexpectedPortError: Error { case unexpectedPortFailure }

private struct UnexpectedFailingPort: SpaceListQuerying {
    func watchSpaces(_ request: SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        AsyncThrowingStream { $0.finish(throwing: UnexpectedPortError.unexpectedPortFailure) }
    }
}

private struct CancellablePort: SpaceListQuerying {
    let updates: [SpaceListUpdate]
    let probe: CancellationProbe
    func watchSpaces(_ request: SpaceListRequest) -> AsyncThrowingStream<SpaceListUpdate, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                continuation.yield(updates[0])
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard !Task.isCancelled else { return }
                for update in updates.dropFirst() { continuation.yield(update) }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
                Task { await producer.value; await probe.markCancelled() }
            }
        }
    }
}

private actor CancellationProbe {
    private var firstDelivery = false
    private var cancelled = false
    func markFirstDelivery() { firstDelivery = true }
    func markCancelled() { cancelled = true }
    func waitForFirstDelivery() async -> Bool {
        for _ in 0..<5_000 {
            if firstDelivery { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
    func waitForCancellation() async -> Bool {
        for _ in 0..<5_000 {
            if cancelled { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}
