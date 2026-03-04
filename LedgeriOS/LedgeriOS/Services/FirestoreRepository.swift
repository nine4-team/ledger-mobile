import FirebaseFirestore
import os.log

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
        return snapshot.documents.compactMap { doc in Self.decodeDocument(doc) }
    }

    func list(where field: String, isEqualTo value: Any) async throws -> [T] {
        let snapshot = try await collectionRef
            .whereField(field, isEqualTo: value)
            .getDocuments()
        return snapshot.documents.compactMap { doc in Self.decodeDocument(doc) }
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
        collectionRef.addSnapshotListener { [collectionPath] snapshot, error in
            if let error {
                print("[FirestoreRepo] \(collectionPath) snapshot error: \(error)")
            }
            guard let docs = snapshot?.documents else {
                print("[FirestoreRepo] \(collectionPath) snapshot nil")
                return
            }
            let items = docs.compactMap { doc in Self.decodeDocument(doc) }
            if items.count != docs.count {
                print("[FirestoreRepo] \(collectionPath) decode dropped \(docs.count - items.count)/\(docs.count) docs")
            }
            onChange(items)
        }
    }

    func subscribe(where field: String, isEqualTo value: Any, onChange: @escaping ([T]) -> Void) -> ListenerRegistration {
        collectionRef
            .whereField(field, isEqualTo: value)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                let items = docs.compactMap { doc in Self.decodeDocument(doc) }
                onChange(items)
            }
    }

    func subscribe(id: String, onChange: @escaping (T?) -> Void) -> ListenerRegistration {
        collectionRef.document(id).addSnapshotListener { snapshot, error in
            guard let snapshot, snapshot.exists else {
                onChange(nil)
                return
            }
            let item = Self.decodeDocument(snapshot)
            onChange(item)
        }
    }

    // MARK: - Decode helper

    private nonisolated static var logger: Logger { Logger(subsystem: "apps.nine4.ledger", category: "FirestoreRepository") }

    private static func decodeDocument(_ doc: DocumentSnapshot) -> T? {
        do {
            return try doc.data(as: T.self)
        } catch let decodingError as DecodingError {
            let detail: String
            switch decodingError {
            case .typeMismatch(let type, let ctx):
                detail = "typeMismatch(\(type)) at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")) — \(ctx.debugDescription)"
            case .valueNotFound(let type, let ctx):
                detail = "valueNotFound(\(type)) at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")) — \(ctx.debugDescription)"
            case .keyNotFound(let key, let ctx):
                detail = "keyNotFound(\(key.stringValue)) at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")) — \(ctx.debugDescription)"
            case .dataCorrupted(let ctx):
                detail = "dataCorrupted at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")) — \(ctx.debugDescription)"
            @unknown default:
                detail = "\(decodingError)"
            }
            logger.error("Failed to decode \(String(describing: T.self)) from doc \(doc.documentID): \(detail)")
            return nil
        } catch {
            logger.error("Failed to decode \(String(describing: T.self)) from doc \(doc.documentID): \(error)")
            return nil
        }
    }
}
