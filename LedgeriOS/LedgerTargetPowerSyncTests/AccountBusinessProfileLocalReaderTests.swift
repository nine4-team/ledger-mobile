import Foundation
import LedgerTargetCore
import PowerSync
import Testing
@testable import LedgerTargetPowerSync

@Suite("Downloaded Account business profile", .serialized)
struct AccountBusinessProfileLocalReaderTests {
    private let account = try! AccountID(validating: "profile-account")
    private let principal = try! PrincipalID(validating: "profile-principal")

    @Test("Missing profile differs from explicit absent logo and removal denies reading")
    func absenceAndAccess() async throws {
        try await withDatabase { db in
            let reader = AccountBusinessProfileLocalReader(database: db)
            await #expect(throws: AccountBusinessProfileReadFailure.self) {
                try await reader.read(accountId: account, principalId: principal)
            }
            _ = try await db.execute(sql: "INSERT INTO spike_account_business_profiles(id,account_id) VALUES('profile-account','profile-account')", parameters: nil)
            let row = try await reader.read(accountId: account, principalId: principal)
            #expect(row.name.rawValue == "1584 Design" && row.logo == nil)
            await #expect(throws: AccountBusinessProfileReadFailure.self) {
                try await reader.read(accountId: AccountID(validating: "other"), principalId: principal)
            }
            _ = try await db.execute(sql: "UPDATE spike_account_memberships SET state='removed'", parameters: nil)
            await #expect(throws: AccountBusinessProfileReadFailure.self) {
                try await reader.read(accountId: account, principalId: principal)
            }
        }
    }

    @Test("Complete logo reference preserves exact byte count; inconsistent evidence is rejected")
    func logo() async throws {
        try await withDatabase { db in
            let reader = AccountBusinessProfileLocalReader(database: db)
            let hash = String(repeating: "a", count: 64)
            let path = "accounts/profile-account/attachments/logo/\(hash)"
            _ = try await db.execute(sql: """
                INSERT INTO spike_account_business_profiles(id,account_id,logo_attachment_id,
                logo_content_sha256,logo_byte_count,logo_media_type,logo_storage_path)
                VALUES('profile-account','profile-account','logo',?,'9007199254740993','image/png',?)
                """, parameters: [hash, path])
            let row = try await reader.read(accountId: account, principalId: principal)
            #expect(row.logo?.byteCount == 9_007_199_254_740_993)
            #expect(row.logo?.storagePath == path)
            for sql in [
                "UPDATE spike_account_business_profiles SET logo_storage_path='accounts/other/logo'",
                "UPDATE spike_account_business_profiles SET logo_attachment_id=NULL"
            ] {
                _ = try await db.execute(sql: sql, parameters: nil)
                await #expect(throws: AccountBusinessProfileReadFailure.self) {
                    try await reader.read(accountId: account, principalId: principal)
                }
            }
        }
    }

    private func withDatabase(_ body: (any PowerSyncDatabaseProtocol) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("profile-reader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try LedgerPowerSyncDatabaseFactory.open(absolutePath: root.appendingPathComponent("ledger.sqlite").path,
            encryptionKey: LedgerPowerSyncEncryptionKey(hexadecimal: String(repeating: "4a", count: 32)))
        do {
            _ = try await db.execute(sql: "INSERT INTO spike_accounts(id,display_name) VALUES('profile-account','1584 Design')", parameters: nil)
            _ = try await db.execute(sql: "INSERT INTO spike_account_memberships(id,account_id,principal_id,state) VALUES('member','profile-account','profile-principal','active')", parameters: nil)
            try await body(db)
            try await db.close()
        } catch { try? await db.close(); throw error }
    }
}
