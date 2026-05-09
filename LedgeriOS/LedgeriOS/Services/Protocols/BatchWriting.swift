import FirebaseFirestore

// MARK: - Protocol

/// Abstracts Firestore's `WriteBatch` for testability.
/// Production code uses `FirestoreBatchWriter`; tests use `RecordingBatch`.
protocol BatchWriting {
    func setData(_ fields: [String: Any], forDocumentAt path: String, merge: Bool)
    func updateData(_ fields: [String: Any], forDocumentAt path: String)
    func setDataAutoId(_ fields: [String: Any], inCollection collectionPath: String)
    func deleteDocument(atPath path: String)
    func commit() async throws
    func commit(onError: @escaping @Sendable (Error) -> Void)

    /// Returns `true` if the document exists at `path`. Used by writers that need
    /// set-if-missing semantics (e.g., `createdAt` on canonical sale transactions —
    /// only written on first insert, preserved by subsequent merges).
    func documentExists(atPath path: String) async throws -> Bool

    /// Returns the value of a single string field on a document, or nil if the
    /// document or field is missing. Used to classify source transactions before
    /// writes (e.g., "don't arrayRemove from a Sale's itemIds").
    func stringField(_ field: String, atPath path: String) async throws -> String?
}

// MARK: - Production Implementation

struct FirestoreBatchWriter: BatchWriting, @unchecked Sendable {
    private let batch: WriteBatch
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
        self.batch = db.batch()
    }

    func setData(_ fields: [String: Any], forDocumentAt path: String, merge: Bool) {
        batch.setData(fields, forDocument: db.document(path), merge: merge)
    }

    func updateData(_ fields: [String: Any], forDocumentAt path: String) {
        batch.updateData(fields, forDocument: db.document(path))
    }

    func setDataAutoId(_ fields: [String: Any], inCollection collectionPath: String) {
        batch.setData(fields, forDocument: db.collection(collectionPath).document())
    }

    func deleteDocument(atPath path: String) {
        batch.deleteDocument(db.document(path))
    }

    func commit() async throws {
        try await batch.commit()
    }

    func commit(onError: @escaping @Sendable (Error) -> Void) {
        batch.commit { error in
            if let error {
                onError(error)
            }
        }
    }

    func documentExists(atPath path: String) async throws -> Bool {
        let snap = try await db.document(path).getDocument()
        return snap.exists
    }

    func stringField(_ field: String, atPath path: String) async throws -> String? {
        let snap = try await db.document(path).getDocument()
        guard snap.exists else { return nil }
        return snap.data()?[field] as? String
    }
}
