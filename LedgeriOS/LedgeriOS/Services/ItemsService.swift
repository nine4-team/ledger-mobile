import FirebaseFirestore

struct ItemsService: ItemsServiceProtocol {
    private let makeBatch: @Sendable () -> any BatchWriting

    init(makeBatch: @escaping @Sendable () -> any BatchWriting = { FirestoreBatchWriter() }) {
        self.makeBatch = makeBatch
    }

    private func repo(accountId: String) -> FirestoreRepository<Item> {
        FirestoreRepository<Item>(path: "accounts/\(accountId)/items")
    }

    func getItem(accountId: String, itemId: String) async throws -> Item? {
        try await repo(accountId: accountId).get(id: itemId)
    }

    func createItem(accountId: String, item: Item) throws -> String {
        let priceNormalized = ItemPricePolicy.normalizedForPersistence(item)
        let id = try repo(accountId: accountId).create(AttachmentPrimaryPolicy.normalized(priceNormalized))
        return id
    }

    func createItemsForTransaction(
        accountId: String,
        transactionId: String,
        items: [Item],
        onCommitError: @escaping @Sendable ([String], Error) -> Void = { _, error in
            print("🔴 createItemsForTransaction failed: \(error)")
        }
    ) throws -> [Item] {
        guard !items.isEmpty else { return [] }

        let batch = makeBatch()
        let itemRepo = repo(accountId: accountId)
        let itemIds = items.map { _ in itemRepo.newDocumentId() }
        var createdItems: [Item] = []
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions/\(transactionId)"

        for (itemId, sourceItem) in zip(itemIds, items) {
            let priceNormalized = ItemPricePolicy.normalizedForPersistence(sourceItem)
            var item = AttachmentPrimaryPolicy.normalized(priceNormalized)
            item.id = itemId
            item.accountId = accountId
            item.transactionId = transactionId
            createdItems.append(item)

            var fields = try Firestore.Encoder().encode(item)
            fields["accountId"] = accountId
            fields["transactionId"] = transactionId

            batch.setData(fields, forDocumentAt: "\(itemsPath)/\(itemId)", merge: false)
        }

        batch.updateData(
            ["itemIds": FieldValue.arrayUnion(itemIds),
             "updatedAt": FieldValue.serverTimestamp()],
            forDocumentAt: txPath
        )

        batch.commit { error in
            onCommitError(itemIds, error)
        }
        return createdItems
    }

    func updateItem(accountId: String, itemId: String, fields: [String: Any]) async throws {
        let itemRepo = repo(accountId: accountId)
        guard let existing = try await itemRepo.get(id: itemId) else {
            try await itemRepo.update(id: itemId, fields: fields)
            return
        }
        let normalizedFields = ItemPricePolicy.normalizedUpdateFields(
            existing: existing,
            fields: fields
        )
        let attachmentNormalizedFields = AttachmentPrimaryPolicy.normalizedFields(
            normalizedFields,
            attachmentFieldNames: ["images"]
        )
        try await itemRepo.update(id: itemId, fields: attachmentNormalizedFields)
    }

    func deleteItem(accountId: String, item: Item) async throws {
        try await deleteItems(accountId: accountId, items: [item])
    }

    func deleteItems(accountId: String, items: [Item]) async throws {
        guard !items.isEmpty else { return }

        let batch = makeBatch()
        let itemsPath = "accounts/\(accountId)/items"
        let txPath = "accounts/\(accountId)/transactions"

        for item in items {
            guard let itemId = item.id else { continue }

            batch.deleteDocument(atPath: "\(itemsPath)/\(itemId)")

            if let transactionId = item.transactionId {
                batch.updateData(
                    ["itemIds": FieldValue.arrayRemove([itemId]),
                     "updatedAt": FieldValue.serverTimestamp()],
                    forDocumentAt: "\(txPath)/\(transactionId)"
                )
            }
        }

        try await batch.commit()
    }

    func subscribeToItems(accountId: String, scope: ListScope, onChange: @escaping ([Item]) -> Void) -> ListenerRegistration {
        let r = repo(accountId: accountId)
        switch scope {
        case .project(let projectId):
            return r.subscribe(where: "projectId", isEqualTo: projectId, onChange: onChange)
        case .inventory:
            return r.subscribe(where: "projectId", isEqualTo: NSNull(), onChange: onChange)
        case .all:
            return r.subscribe(onChange: onChange)
        }
    }

    func subscribeToItem(accountId: String, itemId: String, onChange: @escaping (Item?) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(id: itemId, onChange: onChange)
    }
}
