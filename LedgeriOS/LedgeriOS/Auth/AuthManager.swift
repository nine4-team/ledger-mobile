import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift
import os.log

private let authLog = Logger(subsystem: "apps.nine4.ledger", category: "Auth")

@MainActor
@Observable
final class AuthManager {
    var currentUser: FirebaseAuth.User?
    var isAuthenticated: Bool { currentUser != nil }
    var errorMessage: String?
    var errorDetail: String?

    @ObservationIgnored
    nonisolated(unsafe) private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signIn(email: String, password: String) async throws {
        errorMessage = nil
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        errorMessage = nil
        try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func signInWithGoogle() async throws {
        errorMessage = nil
        errorDetail = nil

        do {
            let result = try await platformSignIn()

            guard let idToken = result.user.idToken?.tokenString else {
                throw NSError(
                    domain: "AuthManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token."]
                )
            }

            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: accessToken
            )

            try await Auth.auth().signIn(with: credential)
        } catch {
            let detail = Self.diagnoseError(error)
            authLog.error("Google sign-in failed: \(detail, privacy: .public)")
            errorDetail = detail
            throw error
        }
    }

    func signOut() {
        errorMessage = nil
        errorDetail = nil
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Error Diagnostics

    private static func diagnoseError(_ error: Error) -> String {
        var lines: [String] = []
        var current: NSError? = error as NSError
        var depth = 0
        while let err = current {
            let prefix = depth == 0 ? "Error" : "Underlying[\(depth)]"
            lines.append("\(prefix): \(err.domain) / \(err.code) — \(err.localizedDescription)")
            for (key, value) in err.userInfo where key != NSUnderlyingErrorKey {
                lines.append("  [\(key)]: \(String(describing: value).prefix(200))")
            }
            current = err.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return lines.joined(separator: "\n")
    }
}
