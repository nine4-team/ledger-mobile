import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

enum SpaceCoreDetailsPowerSyncFailure: Error, Equatable, Sendable {
    case malformedScopeEvidence
    case malformedSpaceRow
}

protocol SpaceCoreDetailsLocalReading: Sendable {
    var hasLastSyncedAt: Bool { get }
    func readRows(request: SpaceCoreDetailsRequest, principalId: PrincipalID) async throws -> [SpaceCoreDetailsPowerSyncRow]
    func watchRows(request: SpaceCoreDetailsRequest, principalId: PrincipalID) throws -> AsyncThrowingStream<[SpaceCoreDetailsPowerSyncRow], Error>
}

final class PowerSyncSpaceCoreDetailsLocalReader: SpaceCoreDetailsLocalReading, @unchecked Sendable {
    private let database: any PowerSyncDatabaseProtocol
    init(database: any PowerSyncDatabaseProtocol) { self.database = database }
    var hasLastSyncedAt: Bool { database.currentStatus.lastSyncedAt != nil }

    func readRows(request: SpaceCoreDetailsRequest, principalId: PrincipalID) async throws -> [SpaceCoreDetailsPowerSyncRow] {
        try await database.getAll(sql: Self.sql, parameters: Self.parameters(request, principalId)) {
            try SpaceCoreDetailsPowerSyncRow(cursor: $0)
        }
    }

    func watchRows(request: SpaceCoreDetailsRequest, principalId: PrincipalID) throws -> AsyncThrowingStream<[SpaceCoreDetailsPowerSyncRow], Error> {
        try database.watch(sql: Self.sql, parameters: Self.parameters(request, principalId)) {
            try SpaceCoreDetailsPowerSyncRow(cursor: $0)
        }
    }

    private static func parameters(_ request: SpaceCoreDetailsRequest, _ principalId: PrincipalID) -> [any Sendable] {
        [
            request.accountId.rawValue,
            principalId.rawValue,
            request.accountId.rawValue,
            request.spaceId.rawValue,
            principalId.rawValue
        ]
    }

    private static let sql = """
        WITH scope AS (
          SELECT EXISTS (
            SELECT 1 FROM \(LedgerPowerSyncTable.memberships)
            WHERE account_id = ? AND principal_id = ? AND state = 'active'
          ) AS is_active
        ), selected_space AS (
          SELECT space.id, space.account_id, space.scope_kind, space.project_id,
                 space.display_name, space.lifecycle, space.revision
          FROM \(LedgerPowerSyncTable.spaces) AS space
          WHERE space.account_id = ? AND space.id = ?
            AND (SELECT is_active FROM scope)
        )
        SELECT CAST(scope.is_active AS INTEGER) AS is_active,
               (SELECT count(*) FROM selected_space) AS visible_count,
               space.id AS space_id, space.account_id, space.scope_kind,
               space.project_id, space.display_name, space.lifecycle, space.revision,
               detail.id AS detail_id, detail.account_id AS detail_account_id,
               detail.notes, detail.created_at_ms, detail.updated_at_ms,
               checklist.id AS checklist_row_id,
               checklist.account_id AS checklist_account_id,
               checklist.space_id AS checklist_space_id,
               checklist.checklist_id, checklist.name AS checklist_name,
               checklist.presentation_order AS checklist_order,
               item.id AS item_row_id, item.account_id AS item_account_id,
               item.space_id AS item_space_id,
               item.checklist_id AS item_checklist_id, item.item_id,
               item.item_text, item.is_checked,
               item.presentation_order AS item_order,
               overlay.operation_id AS overlay_operation_id,
               overlay.account_id AS overlay_account_id,
               overlay.actor_principal_id AS overlay_actor_principal_id,
               overlay.space_id AS overlay_space_id,
               overlay.fingerprint AS overlay_fingerprint,
               overlay.expected_revision AS overlay_expected_revision,
               overlay.projected_revision AS overlay_projected_revision,
               overlay.collection_json AS overlay_collection_json,
               overlay.accepted_at_ms AS overlay_accepted_at_ms,
               overlay_operation.account_id AS overlay_operation_account_id,
               overlay_operation.actor_principal_id
                 AS overlay_operation_actor_principal_id,
               overlay_operation.contract_version
                 AS overlay_operation_contract_version,
               overlay_operation.fingerprint AS overlay_operation_fingerprint,
               overlay_operation.subject_id AS overlay_operation_subject_id,
               overlay_operation.local_state AS overlay_operation_local_state,
               overlay_operation.command_type AS overlay_operation_command_type,
               overlay_operation.command_expected_revision
                 AS overlay_operation_expected_revision
        FROM scope
        LEFT JOIN selected_space AS space ON scope.is_active
        LEFT JOIN \(LedgerPowerSyncTable.spaceCoreDetails) AS detail
          ON detail.account_id = space.account_id AND detail.id = space.id
        LEFT JOIN \(LedgerPowerSyncTable.spaceChecklists) AS checklist
          ON checklist.account_id = space.account_id AND checklist.space_id = space.id
        LEFT JOIN \(LedgerPowerSyncTable.spaceChecklistItems) AS item
          ON item.account_id = checklist.account_id
         AND item.space_id = checklist.space_id
         AND item.checklist_id = checklist.checklist_id
        LEFT JOIN \(LedgerPowerSyncTable.spaceChecklistRevisionOverlays) AS overlay
          ON overlay.account_id = space.account_id
         AND overlay.space_id = space.id
         AND overlay.actor_principal_id = ?
        LEFT JOIN \(LedgerPowerSyncTable.localOperations) AS overlay_operation
          ON overlay_operation.id = overlay.operation_id
        ORDER BY checklist.presentation_order, checklist.checklist_id,
                 item.presentation_order, item.item_id
        """
}

private struct SpaceCoreDetailsSyncStreamIdentity: Equatable, Sendable, SyncStreamDescription {
    let name = "space_core_details"
    let parameters: JsonParam?
    init(accountId: AccountID, spaceId: SpaceID) {
        parameters = ["account_id": .string(accountId.rawValue), "space_id": .string(spaceId.rawValue)]
    }
}

private enum SpaceCoreDetailsFreshnessEvent: Equatable, Sendable {
    case subscriptionStarted
    case currentProcessSync(epoch: TimeInterval)
}

private struct SpaceCoreDetailsSyncStatus: Equatable, Sendable {
    let connected: Bool
    let active: Bool
    let hasExplicitSubscription: Bool
    let lastSyncedAt: TimeInterval?
}

private actor SpaceCoreDetailsFreshnessTracker {
    private enum Mode {
        case reliable(TimeInterval?)
        case causal(first: TimeInterval, accepted: TimeInterval?)
    }
    private var mode: Mode
    init(baseline: TimeInterval?) { mode = .reliable(baseline) }

    func establishCausalFirstSync(_ status: SpaceCoreDetailsSyncStatus) throws -> TimeInterval? {
        guard let epoch = status.lastSyncedAt, Self.valid(epoch) else {
            throw SpaceCoreDetailsPowerSyncFailure.malformedScopeEvidence
        }
        mode = .causal(first: epoch, accepted: nil)
        return accept(status)
    }

    func accept(_ status: SpaceCoreDetailsSyncStatus) -> TimeInterval? {
        guard status.connected, status.active, status.hasExplicitSubscription else { return nil }
        if let epoch = status.lastSyncedAt, !Self.valid(epoch) { return nil }
        switch mode {
        case .reliable(let baseline):
            guard let epoch = status.lastSyncedAt, baseline.map({ epoch > $0 }) ?? true else { return nil }
            mode = .reliable(epoch)
            return epoch
        case .causal(let first, let accepted):
            guard let epoch = status.lastSyncedAt, epoch >= first,
                  accepted.map({ epoch > $0 }) ?? true else { return nil }
            mode = .causal(first: first, accepted: epoch)
            return epoch
        }
    }

    private static func valid(_ epoch: TimeInterval) -> Bool { epoch.isFinite && epoch > 0 }
}

private final class PowerSyncSpaceCoreDetailsFreshnessSource: @unchecked Sendable {
    private let database: any PowerSyncDatabaseProtocol
    init(database: any PowerSyncDatabaseProtocol) { self.database = database }

    func observe(
        accountId: AccountID,
        spaceId: SpaceID,
        receive: @Sendable (SpaceCoreDetailsFreshnessEvent) async throws -> Void
    ) async throws {
        let identity = SpaceCoreDetailsSyncStreamIdentity(accountId: accountId, spaceId: spaceId)
        let baseline = try await baselineLastSyncedAt(for: identity)
        let subscription = try await database.syncStream(name: identity.name, params: identity.parameters).subscribe()
        do {
            try await receive(.subscriptionStarted)
            let tracker = SpaceCoreDetailsFreshnessTracker(baseline: baseline)
            if baseline == nil {
                try await subscription.waitForFirstSync()
                try Task.checkCancellation()
                guard let status = Self.status(database.currentStatus, stream: subscription) else {
                    throw SpaceCoreDetailsPowerSyncFailure.malformedScopeEvidence
                }
                if let epoch = try await tracker.establishCausalFirstSync(status) {
                    try await receive(.currentProcessSync(epoch: epoch))
                }
            }
            for await status in database.currentStatus.asFlow() {
                try Task.checkCancellation()
                guard let exact = Self.status(status, stream: subscription) else { continue }
                if let epoch = await tracker.accept(exact) {
                    try await receive(.currentProcessSync(epoch: epoch))
                }
            }
            try Task.checkCancellation()
        } catch {
            try? await subscription.unsubscribe()
            throw error
        }
        try? await subscription.unsubscribe()
    }

    private func baselineLastSyncedAt(for identity: SpaceCoreDetailsSyncStreamIdentity) async throws -> TimeInterval? {
        var statuses = database.currentStatus.asFlow().makeAsyncIterator()
        var publicEpoch: TimeInterval?
        while let status = await statuses.next() {
            try Task.checkCancellation()
            guard status.syncStreams != nil else { continue }
            publicEpoch = try Self.validatedEpoch(status.forStream(stream: identity)?.subscription.lastSyncedAt)
            break
        }
        struct Retained: Sendable { let parameters: String; let epoch: Int64 }
        let rows: [Retained] = try await database.getAll(
            sql: "SELECT local_params, last_synced_at FROM ps_stream_subscriptions WHERE stream_name = ? AND last_synced_at IS NOT NULL ORDER BY id",
            parameters: [identity.name]
        ) { Retained(parameters: try $0.getString(index: 0), epoch: try $0.getInt64(index: 1)) }
        let expected = identity.parameters.map(JsonValue.object) ?? .null
        let retained = try rows.compactMap { row -> TimeInterval? in
            let decoded = try JSONDecoder().decode(JsonValue.self, from: Data(row.parameters.utf8))
            guard decoded == expected else { return nil }
            return try Self.validatedCoreEpoch(row.epoch)
        }
        guard retained.count <= 1 else { throw SpaceCoreDetailsPowerSyncFailure.malformedScopeEvidence }
        return [publicEpoch, retained.first].compactMap { $0 }.max()
    }

    private static func status(_ status: any SyncStatusData, stream: any SyncStreamDescription) -> SpaceCoreDetailsSyncStatus? {
        guard let exact = status.forStream(stream: stream) else { return nil }
        return SpaceCoreDetailsSyncStatus(
            connected: status.connected,
            active: exact.subscription.active,
            hasExplicitSubscription: exact.subscription.hasExplicitSubscription,
            lastSyncedAt: exact.subscription.lastSyncedAt
        )
    }

    private static func validatedCoreEpoch(_ epoch: Int64) throws -> TimeInterval {
        guard let value = try validatedEpoch(TimeInterval(epoch) / 1_000_000) else {
            throw SpaceCoreDetailsPowerSyncFailure.malformedScopeEvidence
        }
        return value
    }

    private static func validatedEpoch(_ epoch: TimeInterval?) throws -> TimeInterval? {
        guard let epoch else { return nil }
        guard epoch.isFinite, epoch > 0 else { throw SpaceCoreDetailsPowerSyncFailure.malformedScopeEvidence }
        return epoch
    }
}

final class SpaceCoreDetailsPowerSyncQuery: SpaceCoreDetailsQuerying, @unchecked Sendable {
    typealias CompletenessObservation = @Sendable (AccountID, SpaceID) -> AsyncStream<Bool>
    private typealias FreshnessObservation = @Sendable (
        AccountID, SpaceID,
        @escaping @Sendable (SpaceCoreDetailsFreshnessEvent) async throws -> Void
    ) async throws -> Void
    private typealias OverlayReconciliation = @Sendable (
        SpaceChecklistRevisionReconciliationCandidate
    ) async throws -> Void

    private let localReader: any SpaceCoreDetailsLocalReading
    private let principalId: PrincipalID
    private let boundAccountId: AccountID
    private let freshnessObservation: FreshnessObservation
    private let overlayReconciliation: OverlayReconciliation
    private let now: @Sendable () -> Date
    private let watchRegistry = SpaceCoreDetailsWatchRegistry()

    convenience init(
        database: any PowerSyncDatabaseProtocol,
        principalId: PrincipalID,
        accountId: AccountID,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        let freshness = PowerSyncSpaceCoreDetailsFreshnessSource(database: database)
        self.init(
            localReader: PowerSyncSpaceCoreDetailsLocalReader(database: database),
            principalId: principalId,
            accountId: accountId,
            freshnessObservation: { account, space, receive in
                try await freshness.observe(accountId: account, spaceId: space, receive: receive)
            },
            overlayReconciliation: { candidate in
                try await PowerSyncOverlayReconciler.reconcileSpaceChecklistRevision(
                    database: database,
                    candidate: candidate
                )
            },
            now: now
        )
    }

    convenience init(
        localReader: any SpaceCoreDetailsLocalReading,
        principalId: PrincipalID,
        accountId: AccountID,
        completenessObservation: @escaping CompletenessObservation,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.init(
            localReader: localReader,
            principalId: principalId,
            accountId: accountId,
            freshnessObservation: { account, space, receive in
                var epoch: TimeInterval = 0
                for await complete in completenessObservation(account, space) {
                    try Task.checkCancellation()
                    if complete {
                        epoch += 1
                        try await receive(.currentProcessSync(epoch: epoch))
                    } else {
                        try await receive(.subscriptionStarted)
                    }
                }
                try Task.checkCancellation()
            },
            overlayReconciliation: { _ in },
            now: now
        )
    }

    private init(
        localReader: any SpaceCoreDetailsLocalReading,
        principalId: PrincipalID,
        accountId: AccountID,
        freshnessObservation: @escaping FreshnessObservation,
        overlayReconciliation: @escaping OverlayReconciliation,
        now: @Sendable @escaping () -> Date
    ) {
        self.localReader = localReader
        self.principalId = principalId
        boundAccountId = accountId
        self.freshnessObservation = freshnessObservation
        self.overlayReconciliation = overlayReconciliation
        self.now = now
    }

    func watchSpaceCoreDetails(_ request: SpaceCoreDetailsRequest) -> AsyncThrowingStream<SpaceCoreDetailsUpdate, Error> {
        guard request.accountId == boundAccountId else {
            return Self.failedStream(SpaceCoreDetailsFailure.accountScopeMismatch)
        }
        return AsyncThrowingStream { continuation in
            let id = UUID()
            let handle = SpaceCoreDetailsWatchTaskHandle()
            let registration = Task { await watchRegistry.register(id: id, handle: handle) }
            let task = Task {
                let admitted = await registration.value
                guard admitted, !Task.isCancelled else {
                    continuation.finish()
                    if admitted { await watchRegistry.finished(id: id) }
                    return
                }
                await runWatch(request: request, continuation: continuation)
                await watchRegistry.finished(id: id)
            }
            handle.install(task)
            continuation.onTermination = { _ in handle.cancel() }
        }
    }

    func cancelAndDrainWatches() async { await watchRegistry.cancelAndDrain() }

    private enum Event: Sendable {
        case rowsInvalidated
        case subscriptionStarted
        case currentProcessSync(TimeInterval)
    }

    private func runWatch(
        request: SpaceCoreDetailsRequest,
        continuation: AsyncThrowingStream<SpaceCoreDetailsUpdate, Error>.Continuation
    ) async {
        if let loading = try? SpaceCoreDetailsUpdate(request: request, state: .waiting(.loading)) {
            continuation.yield(loading)
        }
        let channel = AsyncThrowingStream<Event, Error>.makeStream()
        let rowTask = Task {
            do {
                let rows = try localReader.watchRows(request: request, principalId: principalId)
                for try await _ in rows {
                    try Task.checkCancellation()
                    channel.continuation.yield(.rowsInvalidated)
                }
                channel.continuation.finish()
            } catch is CancellationError {
                channel.continuation.finish()
            } catch { channel.continuation.finish(throwing: error) }
        }
        let freshnessTask = Task {
            do {
                try await freshnessObservation(request.accountId, request.spaceId) { event in
                    switch event {
                    case .subscriptionStarted: channel.continuation.yield(.subscriptionStarted)
                    case .currentProcessSync(let epoch): channel.continuation.yield(.currentProcessSync(epoch))
                    }
                }
            } catch is CancellationError {
                // Parent cancellation owns normal shutdown.
            } catch { channel.continuation.finish(throwing: error) }
        }

        do {
            var latest: [SpaceCoreDetailsPowerSyncRow]?
            var observedSubscription = false
            var completionEpoch: TimeInterval?
            var last: SpaceCoreDetailsUpdate?
            for try await event in channel.stream {
                try Task.checkCancellation()
                switch event {
                case .rowsInvalidated:
                    let fresh = try await localReader.readRows(request: request, principalId: principalId)
                    if try !Self.scope(fresh).isActive { completionEpoch = nil }
                    latest = fresh
                case .subscriptionStarted:
                    observedSubscription = true
                    completionEpoch = nil
                case .currentProcessSync(let epoch):
                    guard epoch.isFinite, epoch > 0 else { throw SpaceCoreDetailsPowerSyncFailure.malformedScopeEvidence }
                    observedSubscription = true
                    let fresh = try await localReader.readRows(request: request, principalId: principalId)
                    let evidence = try Self.scope(fresh)
                    latest = fresh
                    completionEpoch = evidence.isActive ? epoch : nil
                }
                guard let latest, observedSubscription else { continue }
                let snapshot = try Self.localSnapshot(
                    request: request,
                    rows: latest,
                    streamCompletionReported: completionEpoch != nil,
                    hasLastSyncedAt: localReader.hasLastSyncedAt,
                    asOf: now()
                )
                if completionEpoch != nil,
                   let candidate = try Self.reconciliationCandidate(rows: latest) {
                    try await overlayReconciliation(candidate)
                }
                let update = try SpaceCoreDetailsUpdate(request: request, state: .snapshot(snapshot))
                guard update != last else { continue }
                last = update
                continuation.yield(update)
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: SpaceCoreDetailsFailure.localReadFailed)
        }
        rowTask.cancel()
        freshnessTask.cancel()
        _ = await rowTask.result
        _ = await freshnessTask.result
        channel.continuation.finish()
    }

    static func localSnapshot(
        request: SpaceCoreDetailsRequest,
        rows: [SpaceCoreDetailsPowerSyncRow],
        streamCompletionReported: Bool,
        hasLastSyncedAt: Bool,
        asOf: Date
    ) throws -> SpaceCoreDetailsLocalSnapshot {
        let evidence = try scope(rows)
        let reconstruction = evidence.spaceIsVisible
            ? try reconstruct(request: request, rows: rows)
            : nil
        let represented = reconstruction.map { [$0.snapshot] } ?? []
        let complete = evidence.isActive && streamCompletionReported
        let quality: ListSnapshotQuality = complete ? .ready : (evidence.isActive && hasLastSyncedAt ? .stale : .partial)
        return try SpaceCoreDetailsLocalSnapshot(
            request: request,
            rows: represented,
            visibleRowCountBeforeFiltering: represented.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: try localDataVersion(
                request: request,
                scope: evidence,
                streamIsComplete: streamCompletionReported,
                quality: quality,
                rows: represented,
                checklistRevisionProjection: reconstruction?.projection
            ),
            asOf: asOf,
            checklistRevisionProjection: reconstruction?.projection
        )
    }

    private static func scope(_ rows: [SpaceCoreDetailsPowerSyncRow]) throws -> SpaceCoreDetailsScopeEvidence {
        guard let first = rows.first,
              first.scopeIsActive == 0 || first.scopeIsActive == 1,
              first.visibleCount == 0 || first.visibleCount == 1,
              rows.allSatisfy({ $0.scopeIsActive == first.scopeIsActive && $0.visibleCount == first.visibleCount }) else {
            throw SpaceCoreDetailsPowerSyncFailure.malformedScopeEvidence
        }
        let evidence = SpaceCoreDetailsScopeEvidence(
            isActive: first.scopeIsActive == 1,
            spaceIsVisible: first.visibleCount == 1
        )
        guard evidence.isActive || !evidence.spaceIsVisible else {
            throw SpaceCoreDetailsPowerSyncFailure.malformedScopeEvidence
        }
        if evidence.spaceIsVisible {
            guard rows.allSatisfy({ $0.spaceId != nil }) else { throw SpaceCoreDetailsPowerSyncFailure.malformedScopeEvidence }
        } else {
            guard rows.count == 1, first.isExactSentinel else { throw SpaceCoreDetailsPowerSyncFailure.malformedScopeEvidence }
        }
        return evidence
    }

    private static func reconstruct(
        request: SpaceCoreDetailsRequest,
        rows: [SpaceCoreDetailsPowerSyncRow]
    ) throws -> ReconstructedSpaceCoreDetails {
        guard let first = rows.first,
              let spaceId = first.spaceId, spaceId == request.spaceId.rawValue,
              let accountId = first.accountId, accountId == request.accountId.rawValue,
              let scopeKind = first.scopeKind,
              let displayName = first.displayName,
              let lifecycleRaw = first.lifecycle,
              let lifecycle = DirectoryLifecycleState(rawValue: lifecycleRaw),
              let revision = first.revision, revision > 0,
              first.detailId == spaceId, first.detailAccountId == accountId,
              let createdAt = first.createdAtMilliseconds,
              let updatedAt = first.updatedAtMilliseconds,
              rows.allSatisfy({ $0.sameParent(as: first) }) else {
            throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
        }
        let scope: SpaceCreationScope
        switch scopeKind {
        case "project":
            guard let projectId = first.projectId else { throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow }
            scope = .project(try ProjectID(validating: projectId))
        case "business_inventory":
            guard first.projectId == nil else { throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow }
            scope = .businessInventory
        default: throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
        }

        var order: [String] = []
        var builders: [String: ChecklistBuilder] = [:]
        for row in rows {
            guard let checklistRowId = row.checklistRowId else {
                guard row.hasNoChecklistOrItem else { throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow }
                continue
            }
            guard row.checklistAccountId == accountId, row.checklistSpaceId == spaceId,
                  let checklistId = row.checklistId, let checklistName = row.checklistName,
                  let rawOrder = row.checklistOrder, let checklistOrder = UInt32(exactly: rawOrder) else {
                throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
            }
            let header = ChecklistHeader(rowId: checklistRowId, id: checklistId, name: checklistName, order: checklistOrder)
            if let prior = builders[checklistRowId] {
                guard prior.header == header else { throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow }
            } else {
                order.append(checklistRowId)
                builders[checklistRowId] = ChecklistBuilder(header: header, items: [])
            }
            guard let itemRowId = row.itemRowId else {
                guard row.hasNoItem else { throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow }
                continue
            }
            guard row.itemAccountId == accountId, row.itemSpaceId == spaceId,
                  row.itemChecklistId == checklistId, let itemId = row.itemId,
                  let itemText = row.itemText, let checked = row.itemIsChecked,
                  checked == 0 || checked == 1, let rawItemOrder = row.itemOrder,
                  let itemOrder = UInt32(exactly: rawItemOrder),
                  var builder = builders[checklistRowId],
                  !builder.items.contains(where: { $0.rowId == itemRowId }) else {
                throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
            }
            builder.items.append(ItemBuilder(rowId: itemRowId, id: itemId, text: itemText, isChecked: checked == 1, order: itemOrder))
            builders[checklistRowId] = builder
        }

        let canonicalDisplayName = try SpaceDisplayName(validating: displayName)
        guard canonicalDisplayName.rawValue == displayName else {
            throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
        }
        let canonicalNotes = SpaceCreationNotes(first.notes)
        guard canonicalNotes.value == first.notes else {
            throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
        }
        let checklists = try order.compactMap { builders[$0] }.map { builder in
            let name = try SpaceChecklistName(validating: builder.header.name)
            guard name.rawValue == builder.header.name else {
                throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
            }
            return try SpaceChecklistState(
                id: SpaceChecklistID(validating: builder.header.id),
                name: name,
                presentationOrder: builder.header.order,
                items: try builder.items.map { item in
                    let text = try SpaceChecklistItemText(validating: item.text)
                    guard text.rawValue == item.text else {
                        throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
                    }
                    return SpaceChecklistItemState(
                        id: try SpaceChecklistItemID(validating: item.id),
                        text: text,
                        isChecked: item.isChecked,
                        presentationOrder: item.order
                    )
                }
            )
        }
        let authoritativeCollection = try SpaceChecklistCollection(
            checklists: checklists
        )
        let overlay = try first.checklistRevisionOverlay(
            accountId: accountId,
            spaceId: spaceId
        )
        let effectiveRevision: UInt64
        let effectiveCollection: SpaceChecklistCollection
        if let overlay {
            guard UInt64(revision) >= overlay.expectedRevision else {
                throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
            }
            if UInt64(revision) == overlay.expectedRevision,
               lifecycle == .active {
                effectiveRevision = overlay.projectedRevision
                effectiveCollection = overlay.collection
            } else {
                if UInt64(revision) == overlay.projectedRevision,
                   authoritativeCollection != overlay.collection {
                    throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
                }
                effectiveRevision = UInt64(revision)
                effectiveCollection = authoritativeCollection
            }
        } else {
            effectiveRevision = UInt64(revision)
            effectiveCollection = authoritativeCollection
        }
        let createdAtDate = try exactDate(milliseconds: createdAt)
        let updatedAtDate = try exactDate(milliseconds: updatedAt)
        let snapshot = try SpaceCoreDetailsSnapshot(
            id: SpaceID(validating: spaceId),
            accountId: AccountID(validating: accountId),
            scope: scope,
            displayName: canonicalDisplayName,
            notes: canonicalNotes,
            lifecycle: lifecycle,
            revision: effectiveRevision,
            createdAt: createdAtDate,
            updatedAt: updatedAtDate,
            checklists: effectiveCollection
        )
        let projection: SpaceChecklistRevisionLocalProjection?
        if let overlay,
           UInt64(revision) == overlay.expectedRevision,
           lifecycle == .active {
            projection = try overlay.localProjection()
        } else {
            projection = nil
        }
        return ReconstructedSpaceCoreDetails(snapshot: snapshot, projection: projection)
    }

    private static func exactDate(milliseconds: Int64) throws -> Date {
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        let roundTrip = date.timeIntervalSince1970 * 1_000
        guard date.timeIntervalSinceReferenceDate.isFinite,
              roundTrip.isFinite,
              Int64(exactly: roundTrip.rounded()) == milliseconds else {
            throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
        }
        return date
    }

    private static func reconciliationCandidate(
        rows: [SpaceCoreDetailsPowerSyncRow]
    ) throws -> SpaceChecklistRevisionReconciliationCandidate? {
        guard let first = rows.first,
              let accountId = first.accountId,
              let spaceId = first.spaceId,
              let revision = first.revision else {
            return nil
        }
        guard let overlay = try first.checklistRevisionOverlay(
            accountId: accountId,
            spaceId: spaceId
        ), overlay.localState == .applied,
           revision >= 0,
           UInt64(revision) >= overlay.projectedRevision else {
            return nil
        }
        return SpaceChecklistRevisionReconciliationCandidate(
            operationId: overlay.operationId.rawValue,
            accountId: overlay.accountId.rawValue,
            spaceId: overlay.spaceId.rawValue,
            fingerprint: overlay.fingerprint.sha256,
            projectedRevision: Int64(overlay.projectedRevision)
        )
    }

    private static func localDataVersion(
        request: SpaceCoreDetailsRequest,
        scope: SpaceCoreDetailsScopeEvidence,
        streamIsComplete: Bool,
        quality: ListSnapshotQuality,
        rows: [SpaceCoreDetailsSnapshot],
        checklistRevisionProjection: SpaceChecklistRevisionLocalProjection?
    ) throws -> LocalDataVersion {
        let basis = SpaceCoreDetailsLocalVersionBasis(
            contractVersion: "space-core-details-local-v2",
            requestFingerprint: request.queryFingerprint,
            scopeIsActive: scope.isActive,
            spaceIsVisible: scope.spaceIsVisible,
            streamIsComplete: streamIsComplete,
            quality: quality,
            rows: rows,
            checklistRevisionProjection: checklistRevisionProjection
        )
        let digest = SHA256.hash(data: try OperationContractCodec.encode(basis)).map { String(format: "%02x", $0) }.joined()
        return try LocalDataVersion(validating: "space-core-details-\(digest)")
    }

    private static func failedStream<Value: Sendable>(_ error: Error) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}

private struct SpaceCoreDetailsScopeEvidence: Equatable, Sendable {
    let isActive: Bool
    let spaceIsVisible: Bool
}

private struct SpaceCoreDetailsLocalVersionBasis: Codable {
    let contractVersion: String
    let requestFingerprint: ListQueryFingerprint
    let scopeIsActive: Bool
    let spaceIsVisible: Bool
    let streamIsComplete: Bool
    let quality: ListSnapshotQuality
    let rows: [SpaceCoreDetailsSnapshot]
    let checklistRevisionProjection: SpaceChecklistRevisionLocalProjection?
}

private struct ReconstructedSpaceCoreDetails: Equatable, Sendable {
    let snapshot: SpaceCoreDetailsSnapshot
    let projection: SpaceChecklistRevisionLocalProjection?
}

private struct ChecklistHeader: Equatable, Sendable {
    let rowId: String
    let id: String
    let name: String
    let order: UInt32
}

private struct ItemBuilder: Equatable, Sendable {
    let rowId: String
    let id: String
    let text: String
    let isChecked: Bool
    let order: UInt32
}

private struct ChecklistBuilder: Equatable, Sendable {
    let header: ChecklistHeader
    var items: [ItemBuilder]
}

private struct SpaceChecklistRevisionOverlayProjection: Equatable, Sendable {
    let operationId: OperationID
    let accountId: AccountID
    let actorPrincipalId: PrincipalID
    let contractVersion: OperationContractVersion
    let fingerprint: OperationFingerprint
    let spaceId: SpaceID
    let expectedRevision: UInt64
    let projectedRevision: UInt64
    let collection: SpaceChecklistCollection
    let acceptedAt: Date
    let localState: LocalOperationState

    func localProjection() throws -> SpaceChecklistRevisionLocalProjection {
        try SpaceChecklistRevisionLocalProjection(
            operationId: operationId,
            accountId: accountId,
            actorPrincipalId: actorPrincipalId,
            contractVersion: contractVersion,
            fingerprint: fingerprint,
            spaceId: spaceId,
            expectedRevision: expectedRevision,
            projectedRevision: projectedRevision,
            collection: collection,
            acceptedAt: acceptedAt,
            localState: localState
        )
    }
}

struct SpaceChecklistRevisionReconciliationCandidate: Equatable, Sendable {
    let operationId: String
    let accountId: String
    let spaceId: String
    let fingerprint: String
    let projectedRevision: Int64
}

struct SpaceCoreDetailsPowerSyncRow: Equatable, Sendable {
    let scopeIsActive: Int64
    let visibleCount: Int64
    let spaceId: String?
    let accountId: String?
    let scopeKind: String?
    let projectId: String?
    let displayName: String?
    let lifecycle: String?
    let revision: Int64?
    let detailId: String?
    let detailAccountId: String?
    let notes: String?
    let createdAtMilliseconds: Int64?
    let updatedAtMilliseconds: Int64?
    let checklistRowId: String?
    let checklistAccountId: String?
    let checklistSpaceId: String?
    let checklistId: String?
    let checklistName: String?
    let checklistOrder: Int64?
    let itemRowId: String?
    let itemAccountId: String?
    let itemSpaceId: String?
    let itemChecklistId: String?
    let itemId: String?
    let itemText: String?
    let itemIsChecked: Int64?
    let itemOrder: Int64?
    let overlayOperationId: String?
    let overlayAccountId: String?
    let overlayActorPrincipalId: String?
    let overlaySpaceId: String?
    let overlayFingerprint: String?
    let overlayExpectedRevision: String?
    let overlayProjectedRevision: Int64?
    let overlayCollectionJSON: String?
    let overlayAcceptedAtMilliseconds: Int64?
    let overlayOperationAccountId: String?
    let overlayOperationActorPrincipalId: String?
    let overlayOperationContractVersion: String?
    let overlayOperationFingerprint: String?
    let overlayOperationSubjectId: String?
    let overlayOperationLocalState: String?
    let overlayOperationCommandType: String?
    let overlayOperationExpectedRevision: String?

    init(
        scopeIsActive: Int64, visibleCount: Int64, spaceId: String? = nil,
        accountId: String? = nil, scopeKind: String? = nil, projectId: String? = nil,
        displayName: String? = nil, lifecycle: String? = nil, revision: Int64? = nil,
        detailId: String? = nil, detailAccountId: String? = nil, notes: String? = nil,
        createdAtMilliseconds: Int64? = nil, updatedAtMilliseconds: Int64? = nil,
        checklistRowId: String? = nil, checklistAccountId: String? = nil,
        checklistSpaceId: String? = nil, checklistId: String? = nil,
        checklistName: String? = nil, checklistOrder: Int64? = nil,
        itemRowId: String? = nil, itemAccountId: String? = nil,
        itemSpaceId: String? = nil, itemChecklistId: String? = nil,
        itemId: String? = nil, itemText: String? = nil,
        itemIsChecked: Int64? = nil, itemOrder: Int64? = nil,
        overlayOperationId: String? = nil, overlayAccountId: String? = nil,
        overlayActorPrincipalId: String? = nil, overlaySpaceId: String? = nil,
        overlayFingerprint: String? = nil, overlayExpectedRevision: String? = nil,
        overlayProjectedRevision: Int64? = nil,
        overlayCollectionJSON: String? = nil,
        overlayAcceptedAtMilliseconds: Int64? = nil,
        overlayOperationAccountId: String? = nil,
        overlayOperationActorPrincipalId: String? = nil,
        overlayOperationContractVersion: String? = nil,
        overlayOperationFingerprint: String? = nil,
        overlayOperationSubjectId: String? = nil,
        overlayOperationLocalState: String? = nil,
        overlayOperationCommandType: String? = nil,
        overlayOperationExpectedRevision: String? = nil
    ) {
        self.scopeIsActive = scopeIsActive; self.visibleCount = visibleCount
        self.spaceId = spaceId; self.accountId = accountId; self.scopeKind = scopeKind
        self.projectId = projectId; self.displayName = displayName; self.lifecycle = lifecycle
        self.revision = revision; self.detailId = detailId; self.detailAccountId = detailAccountId
        self.notes = notes; self.createdAtMilliseconds = createdAtMilliseconds
        self.updatedAtMilliseconds = updatedAtMilliseconds; self.checklistRowId = checklistRowId
        self.checklistAccountId = checklistAccountId; self.checklistSpaceId = checklistSpaceId
        self.checklistId = checklistId; self.checklistName = checklistName
        self.checklistOrder = checklistOrder; self.itemRowId = itemRowId
        self.itemAccountId = itemAccountId; self.itemSpaceId = itemSpaceId
        self.itemChecklistId = itemChecklistId; self.itemId = itemId
        self.itemText = itemText; self.itemIsChecked = itemIsChecked; self.itemOrder = itemOrder
        self.overlayOperationId = overlayOperationId
        self.overlayAccountId = overlayAccountId
        self.overlayActorPrincipalId = overlayActorPrincipalId
        self.overlaySpaceId = overlaySpaceId
        self.overlayFingerprint = overlayFingerprint
        self.overlayExpectedRevision = overlayExpectedRevision
        self.overlayProjectedRevision = overlayProjectedRevision
        self.overlayCollectionJSON = overlayCollectionJSON
        self.overlayAcceptedAtMilliseconds = overlayAcceptedAtMilliseconds
        self.overlayOperationAccountId = overlayOperationAccountId
        self.overlayOperationActorPrincipalId = overlayOperationActorPrincipalId
        self.overlayOperationContractVersion = overlayOperationContractVersion
        self.overlayOperationFingerprint = overlayOperationFingerprint
        self.overlayOperationSubjectId = overlayOperationSubjectId
        self.overlayOperationLocalState = overlayOperationLocalState
        self.overlayOperationCommandType = overlayOperationCommandType
        self.overlayOperationExpectedRevision = overlayOperationExpectedRevision
    }

    init(cursor: any SqlCursor) throws {
        scopeIsActive = try cursor.getInt64(name: "is_active")
        visibleCount = try cursor.getInt64(name: "visible_count")
        spaceId = try cursor.getStringOptional(name: "space_id")
        accountId = try cursor.getStringOptional(name: "account_id")
        scopeKind = try cursor.getStringOptional(name: "scope_kind")
        projectId = try cursor.getStringOptional(name: "project_id")
        displayName = try cursor.getStringOptional(name: "display_name")
        lifecycle = try cursor.getStringOptional(name: "lifecycle")
        revision = try cursor.getInt64Optional(name: "revision")
        detailId = try cursor.getStringOptional(name: "detail_id")
        detailAccountId = try cursor.getStringOptional(name: "detail_account_id")
        notes = try cursor.getStringOptional(name: "notes")
        createdAtMilliseconds = try cursor.getInt64Optional(name: "created_at_ms")
        updatedAtMilliseconds = try cursor.getInt64Optional(name: "updated_at_ms")
        checklistRowId = try cursor.getStringOptional(name: "checklist_row_id")
        checklistAccountId = try cursor.getStringOptional(name: "checklist_account_id")
        checklistSpaceId = try cursor.getStringOptional(name: "checklist_space_id")
        checklistId = try cursor.getStringOptional(name: "checklist_id")
        checklistName = try cursor.getStringOptional(name: "checklist_name")
        checklistOrder = try cursor.getInt64Optional(name: "checklist_order")
        itemRowId = try cursor.getStringOptional(name: "item_row_id")
        itemAccountId = try cursor.getStringOptional(name: "item_account_id")
        itemSpaceId = try cursor.getStringOptional(name: "item_space_id")
        itemChecklistId = try cursor.getStringOptional(name: "item_checklist_id")
        itemId = try cursor.getStringOptional(name: "item_id")
        itemText = try cursor.getStringOptional(name: "item_text")
        itemIsChecked = try cursor.getInt64Optional(name: "is_checked")
        itemOrder = try cursor.getInt64Optional(name: "item_order")
        overlayOperationId = try cursor.getStringOptional(name: "overlay_operation_id")
        overlayAccountId = try cursor.getStringOptional(name: "overlay_account_id")
        overlayActorPrincipalId = try cursor.getStringOptional(
            name: "overlay_actor_principal_id"
        )
        overlaySpaceId = try cursor.getStringOptional(name: "overlay_space_id")
        overlayFingerprint = try cursor.getStringOptional(name: "overlay_fingerprint")
        overlayExpectedRevision = try cursor.getStringOptional(
            name: "overlay_expected_revision"
        )
        overlayProjectedRevision = try cursor.getInt64Optional(
            name: "overlay_projected_revision"
        )
        overlayCollectionJSON = try cursor.getStringOptional(
            name: "overlay_collection_json"
        )
        overlayAcceptedAtMilliseconds = try cursor.getInt64Optional(
            name: "overlay_accepted_at_ms"
        )
        overlayOperationAccountId = try cursor.getStringOptional(
            name: "overlay_operation_account_id"
        )
        overlayOperationActorPrincipalId = try cursor.getStringOptional(
            name: "overlay_operation_actor_principal_id"
        )
        overlayOperationContractVersion = try cursor.getStringOptional(
            name: "overlay_operation_contract_version"
        )
        overlayOperationFingerprint = try cursor.getStringOptional(
            name: "overlay_operation_fingerprint"
        )
        overlayOperationSubjectId = try cursor.getStringOptional(
            name: "overlay_operation_subject_id"
        )
        overlayOperationLocalState = try cursor.getStringOptional(
            name: "overlay_operation_local_state"
        )
        overlayOperationCommandType = try cursor.getStringOptional(
            name: "overlay_operation_command_type"
        )
        overlayOperationExpectedRevision = try cursor.getStringOptional(
            name: "overlay_operation_expected_revision"
        )
    }

    var isExactSentinel: Bool {
        spaceId == nil && accountId == nil && scopeKind == nil && projectId == nil
            && displayName == nil && lifecycle == nil && revision == nil
            && detailId == nil && detailAccountId == nil && notes == nil
            && createdAtMilliseconds == nil && updatedAtMilliseconds == nil
            && hasNoChecklistOrItem && hasNoChecklistRevisionOverlay
    }
    var hasNoChecklistOrItem: Bool {
        checklistRowId == nil && checklistAccountId == nil && checklistSpaceId == nil
            && checklistId == nil && checklistName == nil && checklistOrder == nil && hasNoItem
    }
    var hasNoItem: Bool {
        itemRowId == nil && itemAccountId == nil && itemSpaceId == nil
            && itemChecklistId == nil && itemId == nil && itemText == nil
            && itemIsChecked == nil && itemOrder == nil
    }
    var hasNoChecklistRevisionOverlay: Bool {
        overlayOperationId == nil && overlayAccountId == nil
            && overlayActorPrincipalId == nil && overlaySpaceId == nil
            && overlayFingerprint == nil && overlayExpectedRevision == nil
            && overlayProjectedRevision == nil && overlayCollectionJSON == nil
            && overlayAcceptedAtMilliseconds == nil
            && overlayOperationAccountId == nil
            && overlayOperationActorPrincipalId == nil
            && overlayOperationContractVersion == nil
            && overlayOperationFingerprint == nil
            && overlayOperationSubjectId == nil
            && overlayOperationLocalState == nil
            && overlayOperationCommandType == nil
            && overlayOperationExpectedRevision == nil
    }
    func sameParent(as other: Self) -> Bool {
        spaceId == other.spaceId && accountId == other.accountId && scopeKind == other.scopeKind
            && projectId == other.projectId && displayName == other.displayName
            && lifecycle == other.lifecycle && revision == other.revision
            && detailId == other.detailId && detailAccountId == other.detailAccountId
            && notes == other.notes && createdAtMilliseconds == other.createdAtMilliseconds
            && updatedAtMilliseconds == other.updatedAtMilliseconds
            && overlayOperationId == other.overlayOperationId
            && overlayAccountId == other.overlayAccountId
            && overlayActorPrincipalId == other.overlayActorPrincipalId
            && overlaySpaceId == other.overlaySpaceId
            && overlayFingerprint == other.overlayFingerprint
            && overlayExpectedRevision == other.overlayExpectedRevision
            && overlayProjectedRevision == other.overlayProjectedRevision
            && overlayCollectionJSON == other.overlayCollectionJSON
            && overlayAcceptedAtMilliseconds == other.overlayAcceptedAtMilliseconds
            && overlayOperationAccountId == other.overlayOperationAccountId
            && overlayOperationActorPrincipalId
                == other.overlayOperationActorPrincipalId
            && overlayOperationContractVersion
                == other.overlayOperationContractVersion
            && overlayOperationFingerprint == other.overlayOperationFingerprint
            && overlayOperationSubjectId == other.overlayOperationSubjectId
            && overlayOperationLocalState == other.overlayOperationLocalState
            && overlayOperationCommandType == other.overlayOperationCommandType
            && overlayOperationExpectedRevision
                == other.overlayOperationExpectedRevision
    }

    fileprivate func checklistRevisionOverlay(
        accountId expectedAccountId: String,
        spaceId expectedSpaceId: String
    ) throws -> SpaceChecklistRevisionOverlayProjection? {
        if hasNoChecklistRevisionOverlay { return nil }
        guard let overlayOperationId,
              let overlayAccountId,
              let overlayActorPrincipalId,
              let overlaySpaceId,
              let overlayFingerprint,
              let overlayExpectedRevision,
              let overlayProjectedRevision,
              let overlayCollectionJSON,
              let overlayAcceptedAtMilliseconds,
              let overlayOperationAccountId,
              let overlayOperationActorPrincipalId,
              let overlayOperationContractVersion,
              let overlayOperationFingerprint,
              let overlayOperationSubjectId,
              let overlayOperationLocalState,
              let overlayOperationCommandType,
              let overlayOperationExpectedRevision,
              overlayAccountId == expectedAccountId,
              overlaySpaceId == expectedSpaceId,
              overlayOperationAccountId == overlayAccountId,
              overlayOperationActorPrincipalId == overlayActorPrincipalId,
              overlayOperationFingerprint == overlayFingerprint,
              overlayOperationSubjectId == overlaySpaceId,
              overlayOperationCommandType == "revise_space_checklists",
              overlayOperationExpectedRevision == overlayExpectedRevision,
              ["queued", "applying", "applied"].contains(
                  overlayOperationLocalState
              ),
              let fingerprint = try? OperationFingerprint(
                  validating: overlayFingerprint
              ),
              let operationId = try? OperationID(validating: overlayOperationId),
              let accountId = try? AccountID(validating: overlayAccountId),
              let actorPrincipalId = try? PrincipalID(validating: overlayActorPrincipalId),
              let contractVersion = try? OperationContractVersion(
                  validating: overlayOperationContractVersion
              ),
              let spaceId = try? SpaceID(validating: overlaySpaceId),
              let localState = LocalOperationState(rawValue: overlayOperationLocalState),
              let expectedRevision = UInt64(overlayExpectedRevision),
              expectedRevision > 0,
              expectedRevision < UInt64(Int64.max),
              String(expectedRevision) == overlayExpectedRevision,
              overlayProjectedRevision == Int64(expectedRevision) + 1,
              overlayAcceptedAtMilliseconds >= 0,
              SpaceChecklistRevisionPowerSyncStore.date(
                  overlayAcceptedAtMilliseconds
              ).timeIntervalSinceReferenceDate.isFinite,
              let collectionData = overlayCollectionJSON.data(using: .utf8),
              let collection = try? OperationContractCodec.decode(
                  SpaceChecklistCollection.self,
                  from: collectionData
              ),
              (try? OperationContractCodec.encode(collection)) == collectionData,
              SpaceChecklistRevisionOperationIdentity.isValid(
                  operationId,
                  accountId: accountId
              ) else {
            throw SpaceCoreDetailsPowerSyncFailure.malformedSpaceRow
        }
        return SpaceChecklistRevisionOverlayProjection(
            operationId: operationId,
            accountId: accountId,
            actorPrincipalId: actorPrincipalId,
            contractVersion: contractVersion,
            fingerprint: fingerprint,
            spaceId: spaceId,
            expectedRevision: expectedRevision,
            projectedRevision: UInt64(overlayProjectedRevision),
            collection: collection,
            acceptedAt: SpaceChecklistRevisionPowerSyncStore.date(
                overlayAcceptedAtMilliseconds
            ),
            localState: localState
        )
    }
}

private final class SpaceCoreDetailsWatchTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancellationRequested = false
    func install(_ task: Task<Void, Never>) {
        let cancel = lock.withLock { self.task = task; return cancellationRequested }
        if cancel { task.cancel() }
    }
    func cancel() {
        let installed = lock.withLock { cancellationRequested = true; return task }
        installed?.cancel()
    }
}

private actor SpaceCoreDetailsWatchRegistry {
    private var handles: [UUID: SpaceCoreDetailsWatchTaskHandle] = [:]
    private var isClosing = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []
    func register(id: UUID, handle: SpaceCoreDetailsWatchTaskHandle) -> Bool {
        guard !isClosing else { handle.cancel(); return false }
        handles[id] = handle
        return true
    }
    func finished(id: UUID) {
        handles.removeValue(forKey: id)
        guard handles.isEmpty else { return }
        let waiters = drainWaiters; drainWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }
    func cancelAndDrain() async {
        isClosing = true
        for handle in handles.values { handle.cancel() }
        guard !handles.isEmpty else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }
}
