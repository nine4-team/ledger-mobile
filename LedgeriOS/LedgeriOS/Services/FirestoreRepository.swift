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

}

enum FirestoreSnapshotChange<Document> {
    case upsert(documentID: String, document: Document)
    case remove(documentID: String)

    var requiresDecode: Bool {
        switch self {
        case .upsert: true
        case .remove: false
        }
    }
}

struct FirestoreSnapshotReduction<Value> {
    let values: [Value]
    let decodedDocumentCount: Int
    let droppedDocumentCount: Int
}

final class FirestoreIncrementalSnapshotState<Value>: @unchecked Sendable {
    private var valuesByDocumentID: [String: Value] = [:]
    private(set) var isInitialized = false

    func apply<Document>(
        orderedDocuments: [Document],
        documentID: (Document) -> String,
        changes: [FirestoreSnapshotChange<Document>],
        decode: (Document) -> Value?
    ) -> FirestoreSnapshotReduction<Value> {
        var decodedDocumentCount = 0

        if !isInitialized {
            valuesByDocumentID.removeAll(keepingCapacity: true)
            for document in orderedDocuments {
                decodedDocumentCount += 1
                let id = documentID(document)
                if let value = decode(document) {
                    valuesByDocumentID[id] = value
                }
            }
            isInitialized = true
        } else {
            for change in changes {
                switch change {
                case .upsert(let id, let document):
                    decodedDocumentCount += 1
                    valuesByDocumentID[id] = decode(document)
                case .remove(let id):
                    valuesByDocumentID.removeValue(forKey: id)
                }
            }
        }

        let values = orderedDocuments.compactMap { valuesByDocumentID[documentID($0)] }
        return FirestoreSnapshotReduction(
            values: values,
            decodedDocumentCount: decodedDocumentCount,
            droppedDocumentCount: orderedDocuments.count - values.count
        )
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
        let snapshotState = FirestoreIncrementalSnapshotState<T>()
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
            let documentChanges = snapshot?.documentChanges ?? []
            PerformanceDiagnostics.shared.event(
                "FirestoreSnapshotReceived",
                kind: kind,
                count: docs.count,
                value: documentChanges.count
            )
            let documents = FirestoreUncheckedSendable(value: docs)
            let changes = FirestoreUncheckedSendable(
                value: Self.incrementalChanges(documentChanges)
            )
            let snapshotFlags = Self.snapshotFlags(snapshot)
            decodeQueue.async {
                guard gate.isActive else { return }
                let decodeCount = snapshotState.isInitialized
                    ? changes.value.lazy.filter(\.requiresDecode).count
                    : documents.value.count
                let decodeInterval = PerformanceDiagnostics.shared.beginInterval(
                    "FirestoreDecode",
                    kind: kind,
                    count: decodeCount
                )
                let reduction = snapshotState.apply(
                    orderedDocuments: documents.value,
                    documentID: \QueryDocumentSnapshot.documentID,
                    changes: changes.value,
                    decode: documentDecoder.decode
                )
                PerformanceDiagnostics.shared.endInterval(
                    decodeInterval,
                    value: changes.value.count
                )
                if reduction.droppedDocumentCount > 0 {
                    print("[FirestoreRepo] \(collectionPath) decode dropped \(reduction.droppedDocumentCount)/\(documents.value.count) docs")
                }
                let decodedItems = FirestoreUncheckedSendable(value: reduction.values)
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
        let snapshotState = FirestoreIncrementalSnapshotState<T>()
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
                let documentChanges = snapshot?.documentChanges ?? []
                PerformanceDiagnostics.shared.event(
                    "FirestoreSnapshotReceived",
                    kind: kind,
                    count: docs.count,
                    value: documentChanges.count
                )
                let documents = FirestoreUncheckedSendable(value: docs)
                let changes = FirestoreUncheckedSendable(
                    value: Self.incrementalChanges(documentChanges)
                )
                let snapshotFlags = Self.snapshotFlags(snapshot)
                decodeQueue.async {
                    guard gate.isActive else { return }
                    let decodeCount = snapshotState.isInitialized
                        ? changes.value.lazy.filter(\.requiresDecode).count
                        : documents.value.count
                    let decodeInterval = PerformanceDiagnostics.shared.beginInterval(
                        "FirestoreDecode",
                        kind: kind,
                        count: decodeCount
                    )
                    let reduction = snapshotState.apply(
                        orderedDocuments: documents.value,
                        documentID: \QueryDocumentSnapshot.documentID,
                        changes: changes.value,
                        decode: documentDecoder.decode
                    )
                    PerformanceDiagnostics.shared.endInterval(
                        decodeInterval,
                        value: changes.value.count
                    )
                    if reduction.droppedDocumentCount > 0 {
                        print("[FirestoreRepo] \(collectionPath) WHERE \(field) decode dropped \(reduction.droppedDocumentCount)/\(documents.value.count) docs")
                    }
                    let decodedItems = FirestoreUncheckedSendable(value: reduction.values)
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

    private nonisolated static func incrementalChanges(
        _ changes: [DocumentChange]
    ) -> [FirestoreSnapshotChange<QueryDocumentSnapshot>] {
        changes.map { change in
            switch change.type {
            case .added, .modified:
                .upsert(documentID: change.document.documentID, document: change.document)
            case .removed:
                .remove(documentID: change.document.documentID)
            }
        }
    }

}
