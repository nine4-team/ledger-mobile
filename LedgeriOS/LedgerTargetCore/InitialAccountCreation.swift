import Foundation

/// Online first-Account setup. The caller persists this request identity before
/// sending and reuses it after an uncertain response; the server chooses ownership.
public struct InitialAccountCreationRequest: Equatable, Sendable {
    public let requestId: UUID
    public let displayName: AccountDisplayName

    public init(requestId: UUID, displayName: AccountDisplayName) throws {
        guard displayName.rawValue.unicodeScalars.count <= 80 else {
            throw AccountDiscoverySelectionFailure.invalidDisplayName
        }
        self.requestId = requestId
        self.displayName = displayName
    }
}

public protocol InitialAccountCreating: Sendable {
    func createInitialAccount(_ request: InitialAccountCreationRequest) async throws -> AccountSummary
}
