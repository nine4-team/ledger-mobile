import Foundation
import LedgerTargetCore

/// Current server authorization for an explicitly selected Account. This is
/// not a bearer credential and never permits writes without server rechecking.
public struct WorkspaceMembershipAuthorization: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case owner, admin, employee }
    public enum FinancialAccess: String, Codable, Sendable { case full, limited, none }
    public let environment: LedgerEnvironmentKind
    public let authUserId: UUID
    public let principalId: PrincipalID
    public let accountId: AccountID
    public let role: Role
    public let financialAccess: FinancialAccess
}

public struct SupabaseWorkspaceAuthorization: Sendable {
    public enum Failure: Error, Equatable { case accessDenied, scopeChanged, invalidResponse, rejected(Int) }
    private let endpoint: URL
    private let key: String
    private let identity: SupabaseAuthenticatedSession
    private let http: URLSession

    public init(supabaseURL: URL, publishableKey: String,
                identity: SupabaseAuthenticatedSession, http: URLSession = .shared) throws {
        try SupabaseAuthenticatedAccountLookup.validateConfiguration(
            supabaseURL: supabaseURL, publishableKey: publishableKey)
        endpoint = supabaseURL.appendingPathComponent("rest/v1/rpc/spike_authorize_workspace")
        key = publishableKey
        self.identity = identity
        self.http = http
    }

    public func authorize(_ selection: WorkspaceSelectionIntent) async throws -> WorkspaceMembershipAuthorization {
        try await authorize(environment: selection.environment, principalId: selection.principalId,
                            accountId: selection.accountId)
    }

    /// Recheck the existing workspace, not an invented Account-picker selection.
    /// A changed financial scope withholds new sync credentials; its local-data
    /// disposition remains O-058 and must not be treated as Account removal.
    func requireCurrentAccess(_ authorization: WorkspaceMembershipAuthorization,
                              onDenied: @Sendable () async throws -> Void) async throws {
        guard identity.userId == authorization.authUserId else { throw Failure.invalidResponse }
        do {
            let current = try await authorize(environment: authorization.environment,
                principalId: authorization.principalId, accountId: authorization.accountId)
            guard current == authorization else { throw Failure.scopeChanged }
        } catch Failure.accessDenied {
            try await onDenied()
            throw Failure.accessDenied
        }
    }

    private func authorize(environment: LedgerEnvironmentKind, principalId: PrincipalID,
                           accountId: AccountID) async throws -> WorkspaceMembershipAuthorization {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await identity.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["p_account_id": accountId.rawValue])
        let (data, response) = try await http.data(for: request)
        try Task.checkCancellation()
        try identity.requireCurrentIdentity()
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        if response.statusCode == 403 {
            struct Denial: Decodable { let code: String; let message: String }
            if let denial = try? JSONDecoder().decode(Denial.self, from: data),
               denial.code == "42501", denial.message == "workspace_access_denied" {
                throw Failure.accessDenied
            }
        }
        guard response.statusCode == 200 else { throw Failure.rejected(response.statusCode) }
        struct Payload: Decodable {
            let principalId: PrincipalID
            let accountId: AccountID
            let role: WorkspaceMembershipAuthorization.Role
            let financialAccess: WorkspaceMembershipAuthorization.FinancialAccess
        }
        guard let value = try? JSONDecoder().decode(Payload.self, from: data),
              value.principalId == principalId, value.accountId == accountId else {
            throw Failure.invalidResponse
        }
        return WorkspaceMembershipAuthorization(environment: environment, authUserId: identity.userId,
            principalId: value.principalId, accountId: value.accountId,
            role: value.role, financialAccess: value.financialAccess)
    }
}
