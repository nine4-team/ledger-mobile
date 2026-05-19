import FirebaseFirestore

struct ProtoItemsService: ProtoItemsServiceProtocol {
    static let entityType = "protoItems"
    static let photosField = "photos"

    private func repo(accountId: String) -> FirestoreRepository<ProtoItem> {
        FirestoreRepository<ProtoItem>(path: "accounts/\(accountId)/protoItems")
    }

    private func collection(accountId: String) -> CollectionReference {
        Firestore.firestore().collection("accounts/\(accountId)/protoItems")
    }

    func newProtoItemId(accountId: String) -> String {
        repo(accountId: accountId).newDocumentId()
    }

    func createProtoItem(accountId: String, protoItem: ProtoItem) throws -> String {
        try repo(accountId: accountId).create(protoItem, additionalFields: extraFields(for: protoItem, accountId: accountId))
    }

    func createProtoItem(accountId: String, id: String, protoItem: ProtoItem) throws {
        try repo(accountId: accountId).create(id: id, protoItem, additionalFields: extraFields(for: protoItem, accountId: accountId))
    }

    private func extraFields(for protoItem: ProtoItem, accountId: String) -> [String: Any] {
        var fields: [String: Any] = [
            "accountId": accountId,
            "status": (protoItem.status ?? .open).rawValue,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]

        if protoItem.projectId == nil {
            fields["projectId"] = NSNull()
        }
        if protoItem.intendedProjectId == nil {
            fields["intendedProjectId"] = NSNull()
        }
        if protoItem.captureContext == nil {
            fields["captureContext"] = defaultCaptureContext(for: protoItem).rawValue
        }
        return fields
    }

    private func defaultCaptureContext(for protoItem: ProtoItem) -> ProtoItemCaptureContext {
        if protoItem.transactionId != nil { return .transaction }
        if protoItem.projectId != nil { return .project }
        return .inventory
    }

    func updateProtoItem(accountId: String, protoItemId: String, fields: [String: Any]) async throws {
        var updateFields = fields
        updateFields["updatedAt"] = FieldValue.serverTimestamp()
        try await repo(accountId: accountId).update(id: protoItemId, fields: updateFields)
    }

    func markProtoItemInReview(accountId: String, protoItemId: String, userId: String?) async throws {
        var fields: [String: Any] = [
            "status": ProtoItemStatus.inReview.rawValue,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let userId { fields["updatedBy"] = userId }
        try await repo(accountId: accountId).update(id: protoItemId, fields: fields)
    }

    func resolveProtoItem(accountId: String, protoItemId: String, resolvedItemId: String, userId: String?) async throws {
        var fields: [String: Any] = [
            "status": ProtoItemStatus.resolved.rawValue,
            "resolvedItemId": resolvedItemId,
            "resolvedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let userId {
            fields["resolvedBy"] = userId
            fields["updatedBy"] = userId
        }
        try await repo(accountId: accountId).update(id: protoItemId, fields: fields)
    }

    func dismissProtoItem(accountId: String, protoItemId: String, userId: String?) async throws {
        var fields: [String: Any] = [
            "status": ProtoItemStatus.dismissed.rawValue,
            "dismissedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let userId {
            fields["dismissedBy"] = userId
            fields["updatedBy"] = userId
        }
        try await repo(accountId: accountId).update(id: protoItemId, fields: fields)
    }

    func subscribeToActiveProtoItems(accountId: String, onChange: @escaping ([ProtoItem]) -> Void) -> ListenerRegistration {
        collection(accountId: accountId)
            .whereField("status", in: [ProtoItemStatus.open.rawValue, ProtoItemStatus.inReview.rawValue])
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("[ProtoItemsService] active snapshot error: \(error)")
                }
                let items = snapshot?.documents.compactMap { try? $0.data(as: ProtoItem.self) } ?? []
                onChange(items)
            }
    }

    func subscribeToProtoItems(accountId: String, scope: ListScope, onChange: @escaping ([ProtoItem]) -> Void) -> ListenerRegistration {
        let r = repo(accountId: accountId)
        switch scope {
        case .project(let projectId):
            return r.subscribe(where: "projectId", isEqualTo: projectId, onChange: onChange)
        case .inventory:
            return r.subscribe(where: "captureContext", isEqualTo: ProtoItemCaptureContext.inventory.rawValue, onChange: onChange)
        case .all:
            return r.subscribe(onChange: onChange)
        }
    }

    func subscribeToProtoItemsForTransaction(accountId: String, transactionId: String, onChange: @escaping ([ProtoItem]) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(where: "transactionId", isEqualTo: transactionId, onChange: onChange)
    }

    func subscribeToProtoItem(accountId: String, protoItemId: String, onChange: @escaping (ProtoItem?) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(id: protoItemId, onChange: onChange)
    }

    static func photoUploadMetadata(
        accountId: String,
        protoItemId: String,
        filename: String,
        contentType: String = "image/jpeg",
        isPrimary: Bool = false
    ) -> UploadMetadata {
        var metadata = UploadMetadata(
            accountId: accountId,
            entityType: entityType,
            entityId: protoItemId,
            storagePath: "accounts/\(accountId)/\(entityType)/\(protoItemId)/\(filename)",
            contentType: contentType,
            updateType: .appendToArray(field: photosField, kind: AttachmentKind.image.rawValue, isPrimary: isPrimary),
            fileName: filename
        )

        let thumbnailBase = "accounts/\(accountId)/\(entityType)/\(protoItemId)/thumbs/\(filename)"
        metadata.thumbnailStoragePathSm = thumbnailBase.replacingOccurrences(of: ".", with: "_sm.")
        metadata.thumbnailStoragePathMd = thumbnailBase.replacingOccurrences(of: ".", with: "_md.")
        return metadata
    }
}
