import FirebaseFirestore
import FirebaseAuth
import FirebaseCore
import Foundation

struct AccountsService: AccountsServiceProtocol {
    func getAccount(accountId: String) async throws -> Account? {
        let repo = FirestoreRepository<Account>(path: "accounts")
        return try await repo.get(id: accountId)
    }

    func subscribeToAccount(accountId: String, onChange: @escaping (Account?) -> Void) -> ListenerRegistration {
        let repo = FirestoreRepository<Account>(path: "accounts")
        return repo.subscribe(id: accountId, onChange: onChange)
    }

    func createAccount(name: String) async throws -> String {
        let result: CreateAccountCallableResult = try await callFunction(
            name: "createAccountHttp",
            data: ["name": name]
        )
        return result.accountId
    }

    func updateAccount(accountId: String, fields: [String: Any]) async throws {
        let repo = FirestoreRepository<Account>(path: "accounts")
        try await repo.update(id: accountId, fields: fields)
    }

    private func callFunction<Result: Decodable>(name: String, data: [String: Any]) async throws -> Result {
        guard let url = functionURL(name: name) else {
            throw AccountServiceError.missingFunctionURL
        }
        guard let token = try await Auth.auth().currentUser?.getIDToken() else {
            throw AccountServiceError.unauthenticated
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": data])

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AccountServiceError.callFailed(statusCode: httpResponse.statusCode)
        }

        let envelope = try JSONDecoder().decode(CallableEnvelope<Result>.self, from: responseData)
        return envelope.result
    }

    private func functionURL(name: String) -> URL? {
        #if DEBUG
        if FirebaseEmulatorConfig.isEnabled {
            return URL(string: "http://\(FirebaseEmulatorConfig.host):\(FirebaseEmulatorConfig.functionsPort)/ledger-nine4/us-central1/\(name)")
        }
        #endif

        let projectId = FirebaseApp.app()?.options.projectID ?? "ledger-nine4"
        return URL(string: "https://us-central1-\(projectId).cloudfunctions.net/\(name)")
    }
}

private struct CallableEnvelope<Result: Decodable>: Decodable {
    let result: Result
}

private struct CreateAccountCallableResult: Decodable {
    let accountId: String
}

private enum AccountServiceError: Error {
    case missingFunctionURL
    case unauthenticated
    case invalidResponse
    case callFailed(statusCode: Int)
}
