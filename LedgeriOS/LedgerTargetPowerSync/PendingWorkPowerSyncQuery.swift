import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

enum PendingWorkPowerSyncQueryFailure: Error, Equatable, Sendable {
    case malformedOperationEvidence
    case operationScopeMismatch
    case attachmentScopeMismatch
    case attachmentObservationFailed
    case orphanedAttachmentEvidence
    case observationUnstable
    case countOverflow
    case invalidObservationTime
    case databaseReadFailed
    case observationJournalFailed
    case summaryConstructionFailed

    var diagnosticCode: String {
        switch self {
        case .malformedOperationEvidence: "pending_work_operation_evidence_malformed"
        case .operationScopeMismatch: "pending_work_operation_scope_mismatch"
        case .attachmentScopeMismatch: "pending_work_attachment_scope_mismatch"
        case .attachmentObservationFailed: "pending_work_attachment_observation_failed"
        case .orphanedAttachmentEvidence: "pending_work_attachment_orphaned"
        case .observationUnstable: "pending_work_observation_unstable"
        case .countOverflow: "pending_work_count_overflow"
        case .invalidObservationTime: "pending_work_observation_time_invalid"
        case .databaseReadFailed: "pending_work_database_read_failed"
        case .observationJournalFailed: "pending_work_observation_journal_failed"
        case .summaryConstructionFailed: "pending_work_summary_construction_failed"
        }
    }
}

enum PendingWorkPowerSyncQueryCheckpoint: Sendable {
    case afterInitialStableObservation
    case afterJournalCommit
}

actor PendingWorkPowerSyncQuery {
    private static let journalRowID = "pending-work-summary"

    private let database: any PowerSyncDatabaseProtocol
    private let attachmentObserver: any AttachmentPendingWorkObserving
    private let environment: LedgerEnvironmentKind
    private let principalId: PrincipalID
    private let accountId: AccountID
    private let now: @Sendable () -> Date
    private let maximumAttempts: Int
    private let checkpoint: @Sendable (PendingWorkPowerSyncQueryCheckpoint) async throws -> Void
    private let journalInterleave: @Sendable (any Transaction) throws -> Void
    private var observationInProgress = false
    private var observationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        database: any PowerSyncDatabaseProtocol,
        attachmentObserver: any AttachmentPendingWorkObserving,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accountId: AccountID,
        now: @Sendable @escaping () -> Date = Date.init,
        maximumAttempts: Int = 3,
        checkpoint: @Sendable @escaping (
            PendingWorkPowerSyncQueryCheckpoint
        ) async throws -> Void = { _ in },
        journalInterleave: @Sendable @escaping (any Transaction) throws -> Void = { _ in }
    ) {
        self.database = database
        self.attachmentObserver = attachmentObserver
        self.environment = environment
        self.principalId = principalId
        self.accountId = accountId
        self.now = now
        self.maximumAttempts = max(1, maximumAttempts)
        self.checkpoint = checkpoint
        self.journalInterleave = journalInterleave
    }

    func summary() async throws -> PendingLocalWorkSummary {
        await acquireObservationPermit()
        defer { releaseObservationPermit() }
        try Task.checkCancellation()

        return try await makeSummary()
    }

    private func makeSummary() async throws -> PendingLocalWorkSummary {
        for _ in 0..<maximumAttempts {
            guard let initial = try await stableEvidence() else { continue }
            guard initial.attachmentOrphans.isEmpty else {
                throw PendingWorkPowerSyncQueryFailure.orphanedAttachmentEvidence
            }

            try await invoke(.afterInitialStableObservation)
            let journal = try await observeJournal(evidenceSHA256: initial.sha256)
            try await invoke(.afterJournalCommit)

            guard let final = try await stableEvidence(),
                  final.sha256 == initial.sha256 else {
                continue
            }
            guard final.attachmentOrphans.isEmpty else {
                throw PendingWorkPowerSyncQueryFailure.orphanedAttachmentEvidence
            }
            guard try await journalRemainsCurrent(
                journal,
                evidenceSHA256: final.sha256
            ) else {
                continue
            }

            do {
                return try PendingLocalWorkSummary(
                    environment: environment,
                    principalId: principalId,
                    accountId: accountId,
                    snapshotRevision: journal.revision,
                    observedAt: journal.observedAt,
                    queuedOperationCount: final.counts.queued,
                    applyingOperationCount: final.counts.applying,
                    unresolvedRejectedOperationCount: final.counts.rejected,
                    unverifiedAttachmentCount: final.counts.attachments
                )
            } catch {
                throw PendingWorkPowerSyncQueryFailure.summaryConstructionFailed
            }
        }
        throw PendingWorkPowerSyncQueryFailure.observationUnstable
    }

    private func journalRemainsCurrent(
        _ expected: JournalObservation,
        evidenceSHA256: String
    ) async throws -> Bool {
        do {
            return try await database.readTransaction { transaction in
                let rows = try transaction.getAll(
                    sql: """
                    SELECT id, environment, principal_id, account_id,
                           evidence_sha256, snapshot_revision, observed_at_ms
                    FROM \(LedgerPowerSyncTable.pendingWorkObservations)
                    ORDER BY id ASC
                    """,
                    parameters: nil,
                    mapper: JournalRow.init(cursor:)
                )
                guard rows.count == 1 else {
                    throw PendingWorkPowerSyncQueryFailure.observationJournalFailed
                }
                let row = rows[0]
                guard row.id == Self.journalRowID,
                      row.environment == self.environment.rawValue,
                      row.principalID == self.principalId.rawValue,
                      row.accountID == self.accountId.rawValue,
                      Self.isSHA256(row.evidenceSHA256),
                      row.revision > 0 else {
                    throw PendingWorkPowerSyncQueryFailure.observationJournalFailed
                }
                let observation = try row.observation
                return row.evidenceSHA256 == evidenceSHA256 && observation == expected
            }
        } catch let failure as PendingWorkPowerSyncQueryFailure {
            throw failure
        } catch {
            throw PendingWorkPowerSyncQueryFailure.observationJournalFailed
        }
    }

    private func acquireObservationPermit() async {
        guard observationInProgress else {
            observationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            observationWaiters.append(continuation)
        }
    }

    private func releaseObservationPermit() {
        guard !observationWaiters.isEmpty else {
            observationInProgress = false
            return
        }
        observationWaiters.removeFirst().resume()
    }

    private func stableEvidence() async throws -> CompositeEvidence? {
        let firstOperations = try await structuredOperationEvidence()
        let firstAttachments = try await attachmentEvidence()
        let secondOperations = try await structuredOperationEvidence()
        let secondAttachments = try await attachmentEvidence()
        guard firstOperations == secondOperations,
              firstAttachments == secondAttachments else {
            return nil
        }
        return try CompositeEvidence(
            operations: secondOperations,
            attachments: secondAttachments,
            environment: environment,
            principalId: principalId,
            accountId: accountId
        )
    }

    private func structuredOperationEvidence() async throws -> [StructuredOperationEvidence] {
        do {
            return try await database.readTransaction { transaction in
                try transaction.getAll(
                    sql: """
                    SELECT id, account_id, actor_principal_id, contract_version,
                           fingerprint, subject_id, local_state, accepted_at_ms,
                           updated_at_ms
                    FROM \(LedgerPowerSyncTable.localOperations)
                    ORDER BY id ASC
                    """,
                    parameters: nil,
                    mapper: StructuredOperationEvidence.init(cursor:)
                )
            }
        } catch let failure as PendingWorkPowerSyncQueryFailure {
            throw failure
        } catch {
            throw PendingWorkPowerSyncQueryFailure.databaseReadFailed
        }
    }

    private func attachmentEvidence() async throws -> AttachmentPendingWorkObservation {
        do {
            let observation = try await attachmentObserver.pendingWorkObservation()
            for evidence in observation.queue {
                let scope = evidence.receipt.scope
                guard scope.environment == environment,
                      scope.principalId == principalId,
                      scope.accountId == accountId else {
                    throw PendingWorkPowerSyncQueryFailure.attachmentScopeMismatch
                }
            }
            return observation.canonicalized
        } catch let failure as PendingWorkPowerSyncQueryFailure {
            throw failure
        } catch {
            throw PendingWorkPowerSyncQueryFailure.attachmentObservationFailed
        }
    }

    private func observeJournal(evidenceSHA256: String) async throws -> JournalObservation {
        let proposedObservedAt = try observationTime(now())
        do {
            return try await database.writeTransaction { transaction in
                let rows = try transaction.getAll(
                    sql: """
                    SELECT id, environment, principal_id, account_id,
                           evidence_sha256, snapshot_revision, observed_at_ms
                    FROM \(LedgerPowerSyncTable.pendingWorkObservations)
                    ORDER BY id ASC
                    """,
                    parameters: nil,
                    mapper: JournalRow.init(cursor:)
                )
                guard rows.count <= 1 else {
                    throw PendingWorkPowerSyncQueryFailure.observationJournalFailed
                }
                let existing = rows.first
                if let existing {
                    guard existing.id == Self.journalRowID,
                          existing.environment == self.environment.rawValue,
                          existing.principalID == self.principalId.rawValue,
                          existing.accountID == self.accountId.rawValue,
                          Self.isSHA256(existing.evidenceSHA256),
                          existing.revision > 0 else {
                        throw PendingWorkPowerSyncQueryFailure.observationJournalFailed
                    }
                    if existing.evidenceSHA256 == evidenceSHA256 {
                        return try existing.observation
                    }
                }

                try self.journalInterleave(transaction)

                let nextRevision: Int64
                let nextObservedAtMilliseconds: Int64
                if let existing {
                    let (incremented, overflow) = existing.revision.addingReportingOverflow(1)
                    guard !overflow, incremented > existing.revision else {
                        throw PendingWorkPowerSyncQueryFailure.countOverflow
                    }
                    nextRevision = incremented
                    nextObservedAtMilliseconds = max(
                        proposedObservedAt.milliseconds,
                        existing.observedAtMilliseconds
                    )
                    _ = try transaction.execute(
                        sql: """
                        UPDATE \(LedgerPowerSyncTable.pendingWorkObservations)
                        SET evidence_sha256 = ?, snapshot_revision = ?, observed_at_ms = ?
                        WHERE id = ?
                        """,
                        parameters: [
                            evidenceSHA256, nextRevision,
                            nextObservedAtMilliseconds, Self.journalRowID
                        ]
                    )
                } else {
                    nextRevision = 1
                    nextObservedAtMilliseconds = proposedObservedAt.milliseconds
                    _ = try transaction.execute(
                        sql: """
                        INSERT INTO \(LedgerPowerSyncTable.pendingWorkObservations) (
                          id, environment, principal_id, account_id,
                          evidence_sha256, snapshot_revision, observed_at_ms
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                        parameters: [
                            Self.journalRowID, self.environment.rawValue,
                            self.principalId.rawValue, self.accountId.rawValue,
                            evidenceSHA256, nextRevision,
                            nextObservedAtMilliseconds
                        ]
                    )
                }
                let persisted = try transaction.get(
                    sql: """
                    SELECT id, environment, principal_id, account_id,
                           evidence_sha256, snapshot_revision, observed_at_ms
                    FROM \(LedgerPowerSyncTable.pendingWorkObservations)
                    WHERE id = ?
                    """,
                    parameters: [Self.journalRowID],
                    mapper: JournalRow.init(cursor:)
                )
                guard persisted.id == Self.journalRowID,
                      persisted.environment == self.environment.rawValue,
                      persisted.principalID == self.principalId.rawValue,
                      persisted.accountID == self.accountId.rawValue,
                      persisted.evidenceSHA256 == evidenceSHA256,
                      persisted.revision == nextRevision,
                      persisted.observedAtMilliseconds == nextObservedAtMilliseconds else {
                    throw PendingWorkPowerSyncQueryFailure.observationJournalFailed
                }
                return try persisted.observation
            }
        } catch let failure as PendingWorkPowerSyncQueryFailure {
            throw failure
        } catch {
            throw PendingWorkPowerSyncQueryFailure.observationJournalFailed
        }
    }

    private func observationTime(_ date: Date) throws -> ObservationTime {
        let milliseconds = date.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              let truncated = Int64(exactly: milliseconds.rounded(.towardZero)) else {
            throw PendingWorkPowerSyncQueryFailure.invalidObservationTime
        }
        return ObservationTime(
            milliseconds: truncated,
            date: Date(timeIntervalSince1970: Double(truncated) / 1_000)
        )
    }

    private func invoke(_ observed: PendingWorkPowerSyncQueryCheckpoint) async throws {
        do {
            try await checkpoint(observed)
        } catch let failure as PendingWorkPowerSyncQueryFailure {
            throw failure
        } catch {
            throw PendingWorkPowerSyncQueryFailure.observationUnstable
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        return value.utf8.count == 64 &&
            value.unicodeScalars.allSatisfy(hexadecimal.contains)
    }
}

private struct StructuredOperationEvidence: Codable, Equatable, Sendable {
    let id: String
    let accountID: String
    let principalID: String
    let contractVersion: String
    let fingerprint: String
    let subjectID: String
    let state: LocalOperationState
    let acceptedAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64

    init(cursor: any SqlCursor) throws {
        do {
            id = try cursor.getString(name: "id")
            accountID = try cursor.getString(name: "account_id")
            principalID = try cursor.getString(name: "actor_principal_id")
            contractVersion = try cursor.getString(name: "contract_version")
            fingerprint = try cursor.getString(name: "fingerprint")
            subjectID = try cursor.getString(name: "subject_id")
            let rawState = try cursor.getString(name: "local_state")
            acceptedAtMilliseconds = try cursor.getInt64(name: "accepted_at_ms")
            updatedAtMilliseconds = try cursor.getInt64(name: "updated_at_ms")

            guard (try? OperationID(validating: id)) != nil,
                  (try? AccountID(validating: accountID)) != nil,
                  (try? PrincipalID(validating: principalID)) != nil,
                  (try? OperationContractVersion(validating: contractVersion)) != nil,
                  (try? OperationFingerprint(validating: fingerprint)) != nil,
                  (try? EntityID(validating: subjectID)) != nil,
                  let state = LocalOperationState(rawValue: rawState),
                  acceptedAtMilliseconds >= 0,
                  updatedAtMilliseconds >= acceptedAtMilliseconds else {
                throw PendingWorkPowerSyncQueryFailure.malformedOperationEvidence
            }
            self.state = state
        } catch let failure as PendingWorkPowerSyncQueryFailure {
            throw failure
        } catch {
            throw PendingWorkPowerSyncQueryFailure.malformedOperationEvidence
        }
    }
}

private struct CompositeEvidenceBasis: Codable {
    let environment: LedgerEnvironmentKind
    let principalId: PrincipalID
    let accountId: AccountID
    let operations: [StructuredOperationEvidence]
    let attachments: [AttachmentEvidenceBasis]
    let attachmentOrphans: [AttachmentOrphanBasis]
}

private struct AttachmentEvidenceBasis: Codable, Equatable {
    let receipt: AttachmentLocalDurabilityReceipt
    let state: String
}

private struct AttachmentOrphanBasis: Codable, Equatable {
    let kind: String
    let opaqueIdentity: String
}

private struct PendingCounts: Equatable {
    var queued: UInt64 = 0
    var applying: UInt64 = 0
    var rejected: UInt64 = 0
    var attachments: UInt64 = 0

    mutating func increment(_ keyPath: WritableKeyPath<Self, UInt64>) throws {
        let (value, overflow) = self[keyPath: keyPath].addingReportingOverflow(1)
        guard !overflow else { throw PendingWorkPowerSyncQueryFailure.countOverflow }
        self[keyPath: keyPath] = value
    }
}

private struct CompositeEvidence {
    let sha256: String
    let counts: PendingCounts
    let attachmentOrphans: [AttachmentOrphanBasis]

    init(
        operations: [StructuredOperationEvidence],
        attachments: AttachmentPendingWorkObservation,
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accountId: AccountID
    ) throws {
        for operation in operations {
            guard operation.accountID == accountId.rawValue,
                  operation.principalID == principalId.rawValue else {
                throw PendingWorkPowerSyncQueryFailure.operationScopeMismatch
            }
        }

        let attachmentBasis = attachments.queue.map {
            AttachmentEvidenceBasis(receipt: $0.receipt, state: $0.state.rawValue)
        }
        let orphanBasis = attachments.orphans.map {
            AttachmentOrphanBasis(kind: $0.kind.rawValue, opaqueIdentity: $0.opaqueIdentity)
        }
        let basis = CompositeEvidenceBasis(
            environment: environment,
            principalId: principalId,
            accountId: accountId,
            operations: operations,
            attachments: attachmentBasis,
            attachmentOrphans: orphanBasis
        )
        let encoded: Data
        do {
            encoded = try OperationContractCodec.encode(basis)
        } catch {
            throw PendingWorkPowerSyncQueryFailure.malformedOperationEvidence
        }
        sha256 = SHA256.hash(data: encoded)
            .map { String(format: "%02x", $0) }
            .joined()

        var result = PendingCounts()
        for operation in operations {
            switch operation.state {
            case .queued: try result.increment(\.queued)
            case .applying: try result.increment(\.applying)
            case .rejected: try result.increment(\.rejected)
            case .applied, .superseded, .resolved: break
            }
        }
        for _ in attachmentBasis { try result.increment(\.attachments) }
        counts = result
        attachmentOrphans = orphanBasis
    }
}

private struct ObservationTime {
    let milliseconds: Int64
    let date: Date
}

private struct JournalObservation: Equatable, Sendable {
    let revision: UInt64
    let observedAt: Date
}

private struct JournalRow {
    let id: String
    let environment: String
    let principalID: String
    let accountID: String
    let evidenceSHA256: String
    let revision: Int64
    let observedAtMilliseconds: Int64

    init(cursor: any SqlCursor) throws {
        do {
            id = try cursor.getString(name: "id")
            environment = try cursor.getString(name: "environment")
            principalID = try cursor.getString(name: "principal_id")
            accountID = try cursor.getString(name: "account_id")
            evidenceSHA256 = try cursor.getString(name: "evidence_sha256")
            revision = try cursor.getInt64(name: "snapshot_revision")
            observedAtMilliseconds = try cursor.getInt64(name: "observed_at_ms")
        } catch {
            throw PendingWorkPowerSyncQueryFailure.observationJournalFailed
        }
    }

    var observation: JournalObservation {
        get throws {
            guard let revision = UInt64(exactly: revision) else {
                throw PendingWorkPowerSyncQueryFailure.observationJournalFailed
            }
            return JournalObservation(
                revision: revision,
                observedAt: Date(
                    timeIntervalSince1970: Double(observedAtMilliseconds) / 1_000
                )
            )
        }
    }
}

private extension AttachmentPendingWorkObservation {
    var canonicalized: Self {
        Self(
            queue: queue.sorted {
                ($0.receipt.attachmentId.rawValue, $0.state.rawValue) <
                    ($1.receipt.attachmentId.rawValue, $1.state.rawValue)
            },
            orphans: orphans.sorted {
                ($0.kind.rawValue, $0.opaqueIdentity) <
                    ($1.kind.rawValue, $1.opaqueIdentity)
            }
        )
    }
}
