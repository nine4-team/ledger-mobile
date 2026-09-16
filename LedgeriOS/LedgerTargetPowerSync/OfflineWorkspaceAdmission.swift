import Foundation
import LedgerTargetCore

/// Previously authorized, downloaded working set. Not an online credential or
/// permission to download more data. No timestamp/expiry is part of this grant.
public struct OfflineWorkspaceAdmission: Codable, Equatable, Sendable {
    public let authorization: WorkspaceMembershipAuthorization
    public let account: AccountSummary
}

@MainActor
final class OfflineWorkspaceAdmissionStore {
    private struct EndingPlan: Codable, Equatable {
        let requests: [SessionEndRequest]
        let workspaceBindings: [String: String]
    }
    enum Failure: Error, Equatable { case invalidRecord, identityMismatch, unavailable, sessionEndingPending }
    private struct Record: Codable {
        var version = 1
        var activeUserId: UUID?
        var workspaces: [OfflineWorkspaceAdmission] = []
        // Optional for compatibility with previously persisted version-1 records.
        var endingUserIds: [UUID]?
        var endingPlans: [String: EndingPlan]?
        var initialAccountRequestIds: [String: UUID]?
    }
    private let read: () throws -> Data?
    private let write: (Data) throws -> Void
    private let requireNotRemoved: (WorkspaceMembershipAuthorization) throws -> Void

    init(read: @escaping () throws -> Data?, write: @escaping (Data) throws -> Void,
         requireNotRemoved: @escaping (WorkspaceMembershipAuthorization) throws -> Void = {
             try LedgerWorkspaceSessionCleanup.requireNoPendingCleanup(environment: $0.environment,
                 principalId: $0.principalId, accountId: $0.accountId)
             try LedgerWorkspaceRemovalRegistry.requireNotRemoved(environment: $0.environment,
                 principalId: $0.principalId, accountId: $0.accountId)
         }) {
        self.read = read
        self.write = write
        self.requireNotRemoved = requireNotRemoved
    }

    convenience init(keychain: LedgerPowerSyncKeychain) {
        self.init(read: { try keychain.loadRecord(key: "admissions") },
            write: { try keychain.storeRecord(key: "admissions", value: $0) })
    }

    func selectIdentity(_ userId: UUID) throws {
        var record = try load()
        guard !(record.endingUserIds ?? []).contains(userId) else { throw Failure.sessionEndingPending }
        record.activeUserId = userId
        try save(record)
    }

    func pendingInitialAccountRequestId(userId: UUID, environment: LedgerEnvironmentKind) throws -> UUID? {
        try requireIdentityAvailable(userId)
        let record = try load()
        guard record.activeUserId == userId else { throw Failure.identityMismatch }
        return record.initialAccountRequestIds?["\(userId.uuidString):\(environment.rawValue)"]
    }

    func initialAccountRequestId(userId: UUID, environment: LedgerEnvironmentKind) throws -> UUID {
        try requireIdentityAvailable(userId)
        var record = try load()
        guard record.activeUserId == userId else { throw Failure.identityMismatch }
        let key = "\(userId.uuidString):\(environment.rawValue)"
        if let existing = record.initialAccountRequestIds?[key] { return existing }
        let id = UUID()
        var ids = record.initialAccountRequestIds ?? [:]
        ids[key] = id
        record.initialAccountRequestIds = ids
        try save(record)
        return id
    }

    func completeInitialAccountRequest(userId: UUID, environment: LedgerEnvironmentKind, requestId: UUID) throws {
        try requireIdentityAvailable(userId)
        var record = try load()
        guard record.activeUserId == userId else { throw Failure.identityMismatch }
        let key = "\(userId.uuidString):\(environment.rawValue)"
        guard record.initialAccountRequestIds?[key] == requestId else { throw Failure.invalidRecord }
        record.initialAccountRequestIds?.removeValue(forKey: key)
        try save(record)
    }

    func remember(_ authorization: WorkspaceMembershipAuthorization, account: AccountSummary) throws {
        var record = try load()
        guard record.activeUserId == authorization.authUserId else { throw Failure.identityMismatch }
        guard !(record.endingUserIds ?? []).contains(authorization.authUserId) else {
            throw Failure.sessionEndingPending
        }
        guard account.id == authorization.accountId else { throw Failure.invalidRecord }
        try requireNotRemoved(authorization)
        record.workspaces.removeAll {
            $0.authorization.authUserId == authorization.authUserId &&
            $0.authorization.environment == authorization.environment && $0.account.id == account.id
        }
        record.workspaces.append(.init(authorization: authorization, account: account))
        try save(record)
    }

    func downloaded(environment: LedgerEnvironmentKind, currentUserId: UUID?) throws -> [OfflineWorkspaceAdmission] {
        let record = try load()
        guard let active = record.activeUserId else { return [] }
        guard !(record.endingUserIds ?? []).contains(active) else { throw Failure.sessionEndingPending }
        // A new online identity cannot inherit an old user's offline working set.
        guard currentUserId == nil || currentUserId == active else { throw Failure.identityMismatch }
        return try record.workspaces.filter {
            guard $0.authorization.authUserId == active, $0.authorization.environment == environment else { return false }
            do { try requireNotRemoved($0.authorization); return true }
            catch LedgerWorkspaceRemovalFailure.removed { return false }
        }
    }

    func requireIdentityAvailable(_ userId: UUID) throws {
        guard !(try load().endingUserIds ?? []).contains(userId) else { throw Failure.sessionEndingPending }
    }

    func pendingSessionEndingUsers() throws -> [UUID] { try load().endingUserIds ?? [] }

    /// Includes every downloaded Account for the identity, even removed Accounts
    /// whose unsynced evidence must remain protected. This is not discard consent.
    func workspacesForSessionEnding(_ userId: UUID) throws -> [OfflineWorkspaceAdmission] {
        let record = try load()
        guard record.activeUserId == userId || (record.endingUserIds ?? []).contains(userId) else {
            throw Failure.identityMismatch
        }
        return record.workspaces.filter { $0.authorization.authUserId == userId }
    }

    /// Persist only after the coordinator has obtained the required dispositions
    /// for all affected Accounts. Retain the directory for interrupted recovery.
    func beginSessionEnding(_ userId: UUID, expectedWorkspaces: [OfflineWorkspaceAdmission]) throws {
        try persistEnding(userId, expectedWorkspaces: expectedWorkspaces, approvedRequests: nil)
    }

    func beginApprovedSessionEnding(_ userId: UUID, expectedWorkspaces: [OfflineWorkspaceAdmission],
                                    requests: [SessionEndRequest], workspaceBindings: [String: String]) throws {
        let scopes = try Set(requests.map { request in
            try LedgerWorkspaceRemovalRegistry.identity(environment: request.expectedSummary.environment,
                principalId: request.expectedSummary.principalId, accountId: request.expectedSummary.accountId)
        })
        guard Set(workspaceBindings.keys) == scopes,
              workspaceBindings.values.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else {
            throw Failure.invalidRecord
        }
        guard requests.count == expectedWorkspaces.count,
              expectedWorkspaces.allSatisfy({ workspace in
                  requests.filter { request in
                      let summary = request.expectedSummary
                      return summary.environment == workspace.authorization.environment &&
                          summary.principalId == workspace.authorization.principalId &&
                          summary.accountId == workspace.account.id
                  }.count == 1
              }) else { throw Failure.invalidRecord }
        try persistEnding(userId, expectedWorkspaces: expectedWorkspaces,
            approvedRequests: EndingPlan(requests: requests, workspaceBindings: workspaceBindings))
    }

    func approvedSessionEndingRequests(_ userId: UUID) throws -> [SessionEndRequest] {
        let record = try load()
        guard (record.endingUserIds ?? []).contains(userId),
              let requests = record.endingPlans?[userId.uuidString]?.requests else {
            throw Failure.invalidRecord
        }
        return requests
    }

    func requireApprovedCleanupLocation(_ userId: UUID, location: LedgerWorkspaceRuntimeLocation) throws {
        let record = try load()
        guard (record.endingUserIds ?? []).contains(userId),
              record.endingPlans?[userId.uuidString]?.workspaceBindings[location.sessionScopeIdentity] == location.cleanupBinding else {
            throw Failure.invalidRecord
        }
    }

    private func persistEnding(_ userId: UUID, expectedWorkspaces: [OfflineWorkspaceAdmission],
                               approvedRequests: EndingPlan?) throws {
        var record = try load()
        guard record.activeUserId == userId else { throw Failure.identityMismatch }
        guard record.workspaces.filter({ $0.authorization.authUserId == userId }) == expectedWorkspaces else {
            throw Failure.invalidRecord
        }
        if (record.endingUserIds ?? []).contains(userId) {
            guard record.endingPlans?[userId.uuidString] == approvedRequests else { throw Failure.invalidRecord }
            return
        }
        record.endingUserIds = (record.endingUserIds ?? []) + [userId]
        if let approvedRequests {
            var requests = record.endingPlans ?? [:]
            requests[userId.uuidString] = approvedRequests
            record.endingPlans = requests
        }
        try save(record)
    }

    /// Called after the coordinator finishes physical/cache and provider cleanup.
    /// Never clear another identity or forget this user's recovery directory early.
    func completeSessionEnding(_ userId: UUID) throws {
        var record = try load()
        guard (record.endingUserIds ?? []).contains(userId) else { throw Failure.invalidRecord }
        record.workspaces.removeAll { $0.authorization.authUserId == userId }
        record.endingUserIds?.removeAll { $0 == userId }
        record.endingPlans?.removeValue(forKey: userId.uuidString)
        if record.activeUserId == userId { record.activeUserId = nil }
        try save(record)
    }

    private func load() throws -> Record {
        guard let bytes = try read() else { return Record() }
        let record = try JSONDecoder().decode(Record.self, from: bytes)
        guard record.version == 1, record.workspaces.allSatisfy({ $0.account.id == $0.authorization.accountId }) else {
            throw Failure.invalidRecord
        }
        return record
    }

    private func save(_ record: Record) throws {
        try write(JSONEncoder().encode(record))
    }
}
