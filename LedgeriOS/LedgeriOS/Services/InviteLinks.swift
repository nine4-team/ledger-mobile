import FirebaseAuth
import FirebaseCore
import Foundation

enum InviteLinks {
    static let scheme = "ledger-nine4"

    static func link(token: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "invite"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    static func token(from url: URL) -> String? {
        if url.scheme == scheme, url.host == "invite" {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "token" }?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        if url.host == "ledger-nine4.web.app", url.path == "/invite" {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "token" }?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        return nil
    }
}

@MainActor
@Observable
final class InviteLinkRouter {
    var pendingToken: String?

    func handle(url: URL) -> Bool {
        guard let token = InviteLinks.token(from: url) else { return false }
        pendingToken = token
        return true
    }

    func clear() {
        pendingToken = nil
    }
}

struct InviteAcceptanceResult: Decodable {
    let accountId: String
    let role: String
}

struct InvitePreviewResult: Decodable {
    let email: String
    let role: String
    let companyFinancialAccess: CompanyFinancialAccess
}

struct InviteAcceptanceService {
    func previewInvite(token: String) async throws -> InvitePreviewResult {
        guard let url = functionURL(name: "previewInviteHttp") else {
            throw InviteAcceptanceError.missingFunctionURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": ["token": token]
        ])

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InviteAcceptanceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw InviteAcceptanceError.callFailed(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: responseData)
            )
        }

        return try JSONDecoder().decode(InviteCallableEnvelope<InvitePreviewResult>.self, from: responseData).result
    }

    func acceptInvite(token: String) async throws -> InviteAcceptanceResult {
        guard let url = functionURL(name: "acceptInviteHttp") else {
            throw InviteAcceptanceError.missingFunctionURL
        }
        guard let idToken = try await Auth.auth().currentUser?.getIDToken() else {
            throw InviteAcceptanceError.unauthenticated
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": ["token": token]
        ])

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InviteAcceptanceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw InviteAcceptanceError.callFailed(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: responseData)
            )
        }

        return try JSONDecoder().decode(InviteCallableEnvelope<InviteAcceptanceResult>.self, from: responseData).result
    }

    private static func errorMessage(from data: Data) -> String? {
        try? JSONDecoder().decode(InviteErrorEnvelope.self, from: data).error.message
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

enum InviteAcceptanceError: Error {
    case missingFunctionURL
    case unauthenticated
    case invalidResponse
    case callFailed(statusCode: Int, message: String?)

    var userMessage: String {
        switch self {
        case .missingFunctionURL:
            return "Invite service is not configured."
        case .unauthenticated:
            return "Create your password to accept this invite."
        case .invalidResponse:
            return "Invite service returned an invalid response."
        case .callFailed(_, let message):
            return message ?? "Could not accept this invite."
        }
    }
}

private struct InviteCallableEnvelope<Result: Decodable>: Decodable {
    let result: Result
}

private struct InviteErrorEnvelope: Decodable {
    struct InviteError: Decodable {
        let message: String
    }

    let error: InviteError
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
