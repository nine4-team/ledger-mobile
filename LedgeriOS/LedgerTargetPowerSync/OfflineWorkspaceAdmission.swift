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
    enum Failure: Error, Equatable { case invalidRecord, identityMismatch, unavailable }
    private struct Record: Codable {
        var version = 1
        var activeUserId: UUID?
        var workspaces: [OfflineWorkspaceAdmission] = []
    }
    private let read: () throws -> Data?
    private let write: (Data) throws -> Void
    private let requireNotRemoved: (WorkspaceMembershipAuthorization) throws -> Void

    init(read: @escaping () throws -> Data?, write: @escaping (Data) throws -> Void,
         requireNotRemoved: @escaping (WorkspaceMembershipAuthorization) throws -> Void = {
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
        record.activeUserId = userId
        try save(record)
    }

    func remember(_ authorization: WorkspaceMembershipAuthorization, account: AccountSummary) throws {
        var record = try load()
        guard record.activeUserId == authorization.authUserId else { throw Failure.identityMismatch }
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
        // A new online identity cannot inherit an old user's offline working set.
        guard currentUserId == nil || currentUserId == active else { throw Failure.identityMismatch }
        return try record.workspaces.filter {
            guard $0.authorization.authUserId == active, $0.authorization.environment == environment else { return false }
            do { try requireNotRemoved($0.authorization); return true }
            catch LedgerWorkspaceRemovalFailure.removed { return false }
        }
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
