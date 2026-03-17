@preconcurrency import FirebaseFirestore
import FirebaseAuth
import Testing
@testable import LedgeriOS

/// Integration tag — filter with `-only-testing` or `-skip-testing`.
extension Tag {
    @Tag static var integration: Self
}

/// Utilities for integration tests that read/write against the Firebase emulator.
///
/// Firebase is already configured by `LedgerApp.init()` (the test host).
/// Tests use the seeded test account to satisfy security rules.
enum FirestoreTestHelper {
    nonisolated(unsafe) private static let db = Firestore.firestore()

    /// The seeded test account ID — has a user document for the auth user.
    static let testAccountId = "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94"

    nonisolated(unsafe) private static var didSetUp = false

    /// Signs in and ensures the auth user has a membership doc for the test account.
    /// The auth emulator may assign a different uid than the seeded data, so we
    /// create/update the membership doc to match whatever uid we get.
    static func signIn() async throws {
        if didSetUp { return }

        // Sign out any stale session from the test host app launch, then sign in fresh.
        try? Auth.auth().signOut()
        let result = try await Auth.auth().signIn(withEmail: "team@nine4.co", password: "password123")
        let uid = result.user.uid

        // Ensure this uid has a membership doc in the test account.
        // Uses the admin bypass header equivalent: Firestore emulator allows writes
        // to user docs if auth is present, but our rules say `allow create: if false`.
        // So we write via the REST API with the "owner" token to bypass rules.
        let memberPath = "accounts/\(testAccountId)/users/\(uid)"
        let projectId = db.app.options.projectID ?? "ledger-nine4"
        let url = URL(string: "http://127.0.0.1:8181/v1/projects/\(projectId)/databases/(default)/documents/\(memberPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "fields": [
                "uid": ["stringValue": uid],
                "role": ["stringValue": "owner"],
                "email": ["stringValue": "team@nine4.co"],
                "accountId": ["stringValue": testAccountId]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        precondition(statusCode == 200, "Failed to create membership doc: HTTP \(statusCode)")
        didSetUp = true
    }

    // MARK: - Write

    /// Writes a Codable value to Firestore with a specific document ID.
    /// Uses `setData(from:)` — the same path as `FirestoreRepository.create()`.
    static func write<T: Encodable>(_ value: T, toCollection collectionPath: String, id: String) throws {
        try db.collection(collectionPath).document(id).setData(from: value)
    }

    /// Writes raw fields to a Firestore document (for seeding non-Codable test data).
    static func writeFields(_ fields: [String: Any], toDocument documentPath: String) async throws {
        try await db.document(documentPath).setData(fields)
    }

    // MARK: - Read

    /// Reads a typed document back from Firestore.
    static func read<T: Decodable>(_ type: T.Type, fromCollection collectionPath: String, id: String) async throws -> T? {
        let snapshot = try await db.collection(collectionPath).document(id).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: T.self)
    }

    /// Reads the raw field dictionary from a Firestore document.
    /// Use this to verify CodingKey mappings (e.g., "type" vs "transactionType").
    static func readRaw(documentPath: String) async throws -> [String: Any]? {
        let snapshot = try await db.document(documentPath).getDocument()
        return snapshot.data()
    }

    /// Updates specific fields on a document (mirrors `FirestoreRepository.update()`).
    static func update(documentPath: String, fields: [String: Any]) async throws {
        try await db.document(documentPath).updateData(fields)
    }

    /// Deletes a document.
    static func delete(documentPath: String) async throws {
        try await db.document(documentPath).delete()
    }

    // MARK: - Collection Paths

    static func itemsPath(accountId: String) -> String {
        "accounts/\(accountId)/items"
    }

    static func transactionsPath(accountId: String) -> String {
        "accounts/\(accountId)/transactions"
    }

    static func spacesPath(accountId: String) -> String {
        "accounts/\(accountId)/spaces"
    }

    static func projectsPath(accountId: String) -> String {
        "accounts/\(accountId)/projects"
    }

    static func lineageEdgesPath(accountId: String) -> String {
        "accounts/\(accountId)/lineageEdges"
    }
}
