import FirebaseFirestore

final class FirestoreRepository<T: Codable & Identifiable>: Repository {
    private let collectionPath: String
    private let db = Firestore.firestore()

    init(path: String) {
        self.collectionPath = path
    }

    private var collectionRef: CollectionReference {
        db.collection(collectionPath)
    }

    // MARK: - Read

    func get(id: String) async throws -> T? {
        let snapshot = try await collectionRef.document(id).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: T.self)
    }

    func list() async throws -> [T] {
        let snapshot = try await collectionRef.getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: T.self) }
    }

    func list(where field: String, isEqualTo value: Any) async throws -> [T] {
        let snapshot = try await collectionRef
            .whereField(field, isEqualTo: value)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: T.self) }
    }

    // MARK: - Write (fire-and-forget for offline-first)

    func create(_ item: T) throws -> String {
        let docRef = collectionRef.document()
        try docRef.setData(from: item)
        return docRef.documentID
    }

    func update(id: String, fields: [String: Any]) async throws {
        try await collectionRef.document(id).updateData(fields)
    }

    func delete(id: String) async throws {
        try await collectionRef.document(id).delete()
    }

    // MARK: - Subscribe (real-time, cache-first)

    func subscribe(onChange: @escaping ([T]) -> Void) -> ListenerRegistration {
        collectionRef.addSnapshotListener { snapshot, error in
            guard let docs = snapshot?.documents else { return }
            let items = docs.compactMap { try? $0.data(as: T.self) }
            onChange(items)
        }
    }

    func subscribe(where field: String, isEqualTo value: Any, onChange: @escaping ([T]) -> Void) -> ListenerRegistration {
        collectionRef
            .whereField(field, isEqualTo: value)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                let items = docs.compactMap { try? $0.data(as: T.self) }
                onChange(items)
            }
    }

    func subscribe(id: String, onChange: @escaping (T?) -> Void) -> ListenerRegistration {
        collectionRef.document(id).addSnapshotListener { snapshot, error in
            guard let snapshot, snapshot.exists else {
                onChange(nil)
                return
            }
            let item = try? snapshot.data(as: T.self)
            onChange(item)
        }
    }
}
