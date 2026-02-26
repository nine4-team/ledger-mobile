import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct FirestoreTestView: View {
    // Known account ID — matches EXPO_PUBLIC_DEFAULT_ACCOUNT_ID in .env.
    // Used only for this diagnostic view; real account discovery will use
    // collectionGroup queries in the service layer (Phase 2).
    private static let testAccountID = "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94"

    @State private var connectionResult: TestResult?
    @State private var cacheResult: TestResult?
    @State private var isTestingConnection = false
    @State private var isTestingCache = false

    var body: some View {
        List {
            Section("Server Connection") {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        if isTestingConnection {
                            ProgressView()
                        }
                    }
                }
                .disabled(isTestingConnection)

                if let result = connectionResult {
                    TestResultRow(result: result)
                }
            }

            Section("Offline Persistence") {
                Button {
                    testCachePersistence()
                } label: {
                    HStack {
                        Text("Test Cache Read")
                        Spacer()
                        if isTestingCache {
                            ProgressView()
                        }
                    }
                }
                .disabled(isTestingCache)

                if let result = cacheResult {
                    TestResultRow(result: result)
                }

                Text("Reads from local cache only (no network). Run the connection test first to populate the cache, then try this with airplane mode on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Firestore Test")
    }

    // Reads the user's own membership doc directly — no collectionGroup needed.
    // Path: accounts/{accountId}/users/{uid}
    // Security rules allow this because isAccountMember checks
    // exists(accounts/{accountId}/users/{request.auth.uid}).
    private func testConnection() {
        isTestingConnection = true
        connectionResult = nil

        Task {
            do {
                let user = Auth.auth().currentUser
                print("[FirestoreTest] currentUser: \(user?.uid ?? "nil")")
                print("[FirestoreTest] email: \(user?.email ?? "nil")")
                print("[FirestoreTest] isAnonymous: \(user?.isAnonymous ?? true)")
                print("[FirestoreTest] providerID: \(user?.providerID ?? "nil")")

                // Force-refresh the ID token to rule out stale/expired tokens
                if let user {
                    let token = try await user.getIDToken()
                    print("[FirestoreTest] ID token prefix: \(String(token.prefix(20)))...")
                }

                guard let uid = user?.uid else {
                    connectionResult = .failure("Not authenticated — currentUser is nil.")
                    isTestingConnection = false
                    return
                }

                let db = Firestore.firestore()
                let accountID = Self.testAccountID

                let path = "accounts/\(accountID)/users/\(uid)"
                print("[FirestoreTest] Reading: \(path)")

                // Read user's own membership doc
                let memberRef = db.document(path)
                let memberSnap = try await memberRef.getDocument()

                guard memberSnap.exists else {
                    connectionResult = .failure("No membership doc at accounts/\(accountID)/users/\(uid)")
                    isTestingConnection = false
                    return
                }

                // Now read the account doc itself
                let accountSnap = try await db.document("accounts/\(accountID)").getDocument()
                let name = accountSnap.data()?["name"] as? String ?? "(unnamed)"

                print("[FirestoreTest] Account: \(accountID) — \(name)")
                connectionResult = .success("Account: \(name)")
            } catch {
                print("[FirestoreTest] Error: \(error.localizedDescription)")
                connectionResult = .failure(error.localizedDescription)
            }

            isTestingConnection = false
        }
    }

    private func testCachePersistence() {
        isTestingCache = true
        cacheResult = nil

        Task {
            do {
                guard let uid = Auth.auth().currentUser?.uid else {
                    cacheResult = .failure("Not authenticated.")
                    isTestingCache = false
                    return
                }

                let db = Firestore.firestore()
                let accountID = Self.testAccountID

                // Read from cache only — no network
                let memberSnap = try await db.document("accounts/\(accountID)/users/\(uid)")
                    .getDocument(source: .cache)

                guard memberSnap.exists else {
                    cacheResult = .failure("Cache empty. Run connection test first.")
                    isTestingCache = false
                    return
                }

                let accountSnap = try await db.document("accounts/\(accountID)")
                    .getDocument(source: .cache)
                let name = accountSnap.data()?["name"] as? String ?? "(unnamed)"

                print("[FirestoreTest] Cache hit — Account: \(name)")
                cacheResult = .success("Cache hit: \(name)")
            } catch {
                print("[FirestoreTest] Cache error: \(error.localizedDescription)")
                cacheResult = .failure("Cache read failed: \(error.localizedDescription)")
            }

            isTestingCache = false
        }
    }
}

private enum TestResult {
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case .success(let msg), .failure(let msg): msg
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

private struct TestResultRow: View {
    let result: TestResult

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.isSuccess ? .green : .red)
            Text(result.message)
                .font(.subheadline)
                .foregroundStyle(result.isSuccess ? .green : .red)
        }
    }
}

#Preview {
    NavigationStack {
        FirestoreTestView()
    }
}
