import Foundation
import PowerSync

enum LedgerPowerSyncDatabaseFailure: Error, Equatable, Sendable {
    case invalidDatabasePath
    case invalidEncryptionKey
}

struct LedgerPowerSyncEncryptionKey: Equatable, Sendable {
    let hexadecimal: String

    init(hexadecimal: String) throws {
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        guard hexadecimal.utf8.count == 64,
              hexadecimal.unicodeScalars.allSatisfy(allowed.contains) else {
            throw LedgerPowerSyncDatabaseFailure.invalidEncryptionKey
        }
        self.hexadecimal = hexadecimal
    }

    fileprivate var keyStatement: String {
        "PRAGMA key = \"x'\(hexadecimal)'\""
    }
}

enum LedgerPowerSyncDatabaseFactory {
    static func open(
        absolutePath: String,
        encryptionKey: LedgerPowerSyncEncryptionKey
    ) throws -> any PowerSyncDatabaseProtocol {
        guard absolutePath.hasPrefix("/"),
              URL(fileURLWithPath: absolutePath).lastPathComponent.hasSuffix(".sqlite") else {
            throw LedgerPowerSyncDatabaseFailure.invalidDatabasePath
        }

        return PowerSyncDatabase(
            schema: LedgerPowerSyncSchema.schema,
            dbFilename: absolutePath,
            initialStatements: [encryptionKey.keyStatement]
        )
    }
}
