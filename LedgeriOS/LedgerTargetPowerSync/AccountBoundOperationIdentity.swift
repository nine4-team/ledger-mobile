import CryptoKit
import Foundation
import LedgerTargetCore

/// Closed command-family namespaces prevent a caller from minting an identity
/// in another command's immutable-result namespace.
enum AccountBoundOperationFamily: String, Sendable {
    case projectArchive = "project-archive"
    case clientArchive = "client-archive"
}

enum AccountBoundOperationIdentity {
    static func make(
        family: AccountBoundOperationFamily,
        accountId: AccountID,
        uuid: UUID
    ) throws -> OperationID {
        try OperationID(
            validating: prefix(family: family, accountId: accountId)
                + uuid.uuidString.lowercased()
        )
    }

    static func isValid(
        _ operationId: OperationID,
        family: AccountBoundOperationFamily,
        accountId: AccountID
    ) -> Bool {
        let expectedPrefix = prefix(family: family, accountId: accountId)
        guard operationId.rawValue.hasPrefix(expectedPrefix) else { return false }
        let uuidText = String(operationId.rawValue.dropFirst(expectedPrefix.count))
        guard let uuid = UUID(uuidString: uuidText),
              uuidText == uuid.uuidString.lowercased(),
              let rebuilt = try? make(
                  family: family,
                  accountId: accountId,
                  uuid: uuid
              ) else {
            return false
        }
        return rebuilt == operationId
    }

    private static func prefix(
        family: AccountBoundOperationFamily,
        accountId: AccountID
    ) -> String {
        let digest = SHA256.hash(data: Data(accountId.rawValue.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(family.rawValue)-\(digest)-"
    }
}
