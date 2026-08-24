import FirebaseFirestore
import os.log

private struct FirestoreUncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

final class FirestoreListenerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    var isActive: Bool {
        lock.withLock { active }
    }

    func cancel() {
        lock.withLock { active = false }
    }
}

private final class FirestoreDecodedListenerRegistration: NSObject, ListenerRegistration, @unchecked Sendable {
    private let lock = NSLock()
    private let gate: FirestoreListenerGate
    private var registration: ListenerRegistration?

    init(registration: ListenerRegistration, gate: FirestoreListenerGate) {
        self.registration = registration
        self.gate = gate
    }

    func remove() {
        gate.cancel()
        let registration = lock.withLock {
            defer { self.registration = nil }
            return self.registration
        }
        registration?.remove()
    }
}

final class FirestoreSnapshotDecodeQueue: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "apps.nine4.ledger.firestore-snapshot-decode",
        qos: .userInitiated
    )
    private let specificKey = DispatchSpecificKey<UInt8>()

    init() {
        queue.setSpecific(key: specificKey, value: 1)
    }

    func async(_ work: @escaping () -> Void) {
        let work = FirestoreUncheckedSendable(value: work)
        queue.async {
            work.value()
        }
    }

    var isCurrent: Bool {
        DispatchQueue.getSpecific(key: specificKey) != nil
    }
}

private final class FirestoreDocumentDecoder<Value: Codable>: @unchecked Sendable {
    private static var logger: Logger {
        Logger(subsystem: "apps.nine4.ledger", category: "FirestoreRepository")
    }

    func decode(_ document: DocumentSnapshot) -> Value? {
        do {
            return try document.data(as: Value.self)
        } catch let decodingError as DecodingError {
            let detail: String
            switch decodingError {
            case .typeMismatch(let type, let context):
                detail = "typeMismatch(\(type)) at \(context.codingPath.map(\.stringValue).joined(separator: ".")) — \(context.debugDescription)"
            case .valueNotFound(let type, let context):
                detail = "valueNotFound(\(type)) at \(context.codingPath.map(\.stringValue).joined(separator: ".")) — \(context.debugDescription)"
            case .keyNotFound(let key, let context):
                detail = "keyNotFound(\(key.stringValue)) at \(context.codingPath.map(\.stringValue).joined(separator: ".")) — \(context.debugDescription)"
            case .dataCorrupted(let context):
                detail = "dataCorrupted at \(context.codingPath.map(\.stringValue).joined(separator: ".")) — \(context.debugDescription)"
            @unknown default:
                detail = "\(decodingError)"
            }
            Self.logger.error("Failed to decode \(String(describing: Value.self)) from doc \(document.documentID): \(detail)")
            return nil
        } catch {
            Self.logger.error("Failed to decode \(String(describing: Value.self)) from doc \(document.documentID): \(error)")
            return nil
        }
    }

    func decodeAll(_ documents: [QueryDocumentSnapshot]) -> [Value] {
        documents.compactMap { decode($0) }
    }
}

final class FirestoreRepository<T: Codable & Identifiable>: Repository {
    private let collectionPath: String
    private let db = Firestore.firestore()
    private let documentDecoder = FirestoreDocumentDecoder<T>()
    private let snapshotDecodeQueue = FirestoreSnapshotDecodeQueue()

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
        return snapshot.documents.compactMap { documentDecoder.decode($0) }
    }

    func list(where field: String, isEqualTo value: Any) async throws -> [T] {
        let snapshot = try await collectionRef
            .whereField(field, isEqualTo: value)
            .getDocuments()
        return snapshot.documents.compactMap { documentDecoder.decode($0) }
    }

    // MARK: - Write (fire-and-forget for offline-first)

    func create(_ item: T) throws -> String {
        let docRef = collectionRef.document()
        try docRef.setData(from: item)
        return docRef.documentID
    }

    /// Create with additional fields merged into the encoded document in a single write.
    /// Use when a field needs an explicit value (e.g. `NSNull`) that the Codable encoder
    /// would otherwise omit. A separate follow-up `updateData` would open a race where
    /// snapshot listeners can fire on the partial document.
    func create(_ item: T, additionalFields: [String: Any]) throws -> String {
        let docRef = collectionRef.document()
        try writeMerged(docRef: docRef, item: item, additionalFields: additionalFields)
        return docRef.documentID
    }

    /// Pre-allocate a fresh document ID without writing. Use when the caller needs
    /// the ID upfront (e.g. for storage paths) before composing the document body.
    func newDocumentId() -> String {
        collectionRef.document().documentID
    }

    func create(id: String, _ item: T) throws {
        try collectionRef.document(id).setData(from: item)
    }

    func create(id: String, _ item: T, additionalFields: [String: Any]) throws {
        try writeMerged(docRef: collectionRef.document(id), item: item, additionalFields: additionalFields)
    }

    private func writeMerged(docRef: DocumentReference, item: T, additionalFields: [String: Any]) throws {
        if additionalFields.isEmpty {
            try docRef.setData(from: item)
        } else {
            var data = try Firestore.Encoder().encode(item)
            for (key, value) in additionalFields {
                data[key] = value
            }
            docRef.setData(data)
        }
    }

    func update(id: String, fields: [String: Any]) async throws {
        try await collectionRef.document(id).updateData(fields)
    }

    func delete(id: String) async throws {
        try await collectionRef.document(id).delete()
    }

    // MARK: - Subscribe (real-time, cache-first)

    func subscribe(onChange: @escaping ([T]) -> Void) -> ListenerRegistration {
        let kind = diagnosticKind
        PerformanceDiagnostics.shared.event("ListenerRegistered", kind: kind)
        let callback = FirestoreUncheckedSendable(value: onChange)
        let documentDecoder = documentDecoder
        let decodeQueue = snapshotDecodeQueue
        let gate = FirestoreListenerGate()
        let registration = collectionRef.addSnapshotListener { [collectionPath] snapshot, error in
            guard gate.isActive else { return }
            if let error {
                print("[FirestoreRepo] \(collectionPath) snapshot error: \(error)")
            }
            guard let docs = snapshot?.documents else {
                print("[FirestoreRepo] \(collectionPath) snapshot nil")
                return
            }
            let documents = FirestoreUncheckedSendable(value: docs)
            let changeCount = snapshot?.documentChanges.count ?? 0
            let snapshotFlags = Self.snapshotFlags(snapshot)
            decodeQueue.async {
                guard gate.isActive else { return }
                let decodeInterval = PerformanceDiagnostics.shared.beginInterval(
                    "FirestoreDecode",
                    kind: kind,
                    count: documents.value.count
                )
                let items = documentDecoder.decodeAll(documents.value)
                PerformanceDiagnostics.shared.endInterval(decodeInterval, value: changeCount)
                if items.count != documents.value.count {
                    print("[FirestoreRepo] \(collectionPath) decode dropped \(documents.value.count - items.count)/\(documents.value.count) docs")
                }
                let decodedItems = FirestoreUncheckedSendable(value: items)
                DispatchQueue.main.async {
                    guard gate.isActive else { return }
                    let callbackInterval = PerformanceDiagnostics.shared.beginInterval(
                        "FirestoreCallback",
                        kind: kind,
                        count: decodedItems.value.count
                    )
                    callback.value(decodedItems.value)
                    PerformanceDiagnostics.shared.endInterval(
                        callbackInterval,
                        value: snapshotFlags
                    )
                }
            }
        }
        return FirestoreDecodedListenerRegistration(registration: registration, gate: gate)
    }

    func subscribe(where field: String, isEqualTo value: Any, onChange: @escaping ([T]) -> Void) -> ListenerRegistration {
        let kind = "\(diagnosticKind).query"
        PerformanceDiagnostics.shared.event("ListenerRegistered", kind: kind)
        let callback = FirestoreUncheckedSendable(value: onChange)
        let documentDecoder = documentDecoder
        let decodeQueue = snapshotDecodeQueue
        let gate = FirestoreListenerGate()
        let registration = collectionRef
            .whereField(field, isEqualTo: value)
            .addSnapshotListener { [collectionPath] snapshot, error in
                guard gate.isActive else { return }
                if let error {
                    print("[FirestoreRepo] \(collectionPath) WHERE \(field)==\(value) snapshot error: \(error)")
                }
                guard let docs = snapshot?.documents else {
                    print("[FirestoreRepo] \(collectionPath) WHERE \(field)==\(value) snapshot nil")
                    return
                }
                let documents = FirestoreUncheckedSendable(value: docs)
                let changeCount = snapshot?.documentChanges.count ?? 0
                let snapshotFlags = Self.snapshotFlags(snapshot)
                decodeQueue.async {
                    guard gate.isActive else { return }
                    let decodeInterval = PerformanceDiagnostics.shared.beginInterval(
                        "FirestoreDecode",
                        kind: kind,
                        count: documents.value.count
                    )
                    let items = documentDecoder.decodeAll(documents.value)
                    PerformanceDiagnostics.shared.endInterval(decodeInterval, value: changeCount)
                    if items.count != documents.value.count {
                        print("[FirestoreRepo] \(collectionPath) WHERE \(field) decode dropped \(documents.value.count - items.count)/\(documents.value.count) docs")
                    }
                    let decodedItems = FirestoreUncheckedSendable(value: items)
                    DispatchQueue.main.async {
                        guard gate.isActive else { return }
                        let callbackInterval = PerformanceDiagnostics.shared.beginInterval(
                            "FirestoreCallback",
                            kind: kind,
                            count: decodedItems.value.count
                        )
                        callback.value(decodedItems.value)
                        PerformanceDiagnostics.shared.endInterval(
                            callbackInterval,
                            value: snapshotFlags
                        )
                    }
                }
            }
        return FirestoreDecodedListenerRegistration(registration: registration, gate: gate)
    }

    func subscribe(id: String, onChange: @escaping (T?) -> Void) -> ListenerRegistration {
        let kind = "\(diagnosticKind).document"
        PerformanceDiagnostics.shared.event("ListenerRegistered", kind: kind)
        let documentDecoder = documentDecoder
        return collectionRef.document(id).addSnapshotListener { snapshot, error in
            guard let snapshot, snapshot.exists else {
                onChange(nil)
                return
            }
            let decodeInterval = PerformanceDiagnostics.shared.beginInterval(
                "FirestoreDecodeDocument",
                kind: kind,
                count: 1
            )
            let item = documentDecoder.decode(snapshot)
            PerformanceDiagnostics.shared.endInterval(decodeInterval, value: item == nil ? 0 : 1)
            onChange(item)
        }
    }

    // MARK: - Decode helper

    private var diagnosticKind: String {
        Self.diagnosticKind(for: collectionPath)
    }

    private nonisolated static func diagnosticKind(for collectionPath: String) -> String {
        collectionPath.split(separator: "/").last.map(String.init) ?? "unknown"
    }

    private nonisolated static func snapshotFlags(_ snapshot: QuerySnapshot?) -> Int {
        guard let snapshot else { return 0 }
        var flags = 0
        if snapshot.metadata.isFromCache { flags |= 1 }
        if snapshot.metadata.hasPendingWrites { flags |= 2 }
        return flags
    }

}
