#if DEBUG
import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

enum FirebaseEmulatorConfig {
    static let host = "localhost"
    static let authPort = 9099
    static let firestorePort = 8181
    static let storagePort = 9199

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATORS"] == "1"
    }

    /// Call once, immediately after `FirebaseApp.configure()` and before any Auth/Firestore/Storage usage.
    static func configureIfEnabled() {
        guard isEnabled else { return }

        print("[Firebase] Connecting to emulators (Auth:\(authPort), Firestore:\(firestorePort), Storage:\(storagePort))")

        Auth.auth().useEmulator(withHost: host, port: authPort)
        if let settings = Auth.auth().settings {
            settings.isAppVerificationDisabledForTesting = true
            print("[Firebase] Auth settings configured (appVerificationDisabled=true)")
        } else {
            print("⚠️ [Firebase] Auth.auth().settings is nil — isAppVerificationDisabledForTesting was NOT set")
        }
        print("[Firebase] Auth currentUser on startup: \(Auth.auth().currentUser?.uid ?? "nil")")

        let firestore = Firestore.firestore()
        firestore.useEmulator(withHost: host, port: firestorePort)
        let settings = firestore.settings
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings
        print("[Firebase] Firestore emulator configured — host: \(firestore.settings.host), ssl: \(firestore.settings.isSSLEnabled)")

        Storage.storage().useEmulator(withHost: host, port: storagePort)
    }
}
#endif
