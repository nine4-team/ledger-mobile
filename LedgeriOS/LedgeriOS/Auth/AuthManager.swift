import UIKit
import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift

@MainActor
@Observable
final class AuthManager {
    var currentUser: FirebaseAuth.User?
    var isAuthenticated: Bool { currentUser != nil }
    var errorMessage: String?

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

    func signInWithGoogle(presentingViewController: UIViewController) async throws {
        errorMessage = nil

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

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
    }

    func signOut() {
        errorMessage = nil
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
