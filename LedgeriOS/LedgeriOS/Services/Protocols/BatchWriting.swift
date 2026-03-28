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
}
