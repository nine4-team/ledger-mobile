import GoogleSignIn

enum AuthError: Error, LocalizedError {
    case noPresentingContext

    var errorDescription: String? {
        switch self {
        case .noPresentingContext:
            return "Unable to find a presenting context for sign-in."
        }
    }
}

#if canImport(UIKit)
import UIKit

@MainActor
func platformSignIn() async throws -> GIDSignInResult {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let rootVC = windowScene.windows.first?.rootViewController else {
        throw AuthError.noPresentingContext
    }
    return try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
}
#elseif canImport(AppKit)
import AppKit

@MainActor
func platformSignIn() async throws -> GIDSignInResult {
    guard let window = NSApplication.shared.keyWindow else {
        throw AuthError.noPresentingContext
    }
    return try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
}
#endif
