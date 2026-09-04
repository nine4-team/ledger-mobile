import Foundation
import PowerSync

public enum LedgerPowerSyncDatabaseFailure: Error, Equatable, Sendable {
    case invalidDatabasePath
    case invalidEncryptionKey
}

public struct LedgerPowerSyncEncryptionKey: Equatable, Sendable {
    public let hexadecimal: String

    public init(hexadecimal: String) throws {
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

public enum LedgerPowerSyncDatabaseFactory {
    public static func open(
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
