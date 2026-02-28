import FirebaseFirestore

/// Multi-step atomic Firestore operations for inventory movements:
/// sell to business, sell to project, reassign, reassign to inventory.
struct InventoryOperationsService {
    private let db = Firestore.firestore()

    // MARK: - Sell to Business

    /// Moves items from a project into business inventory.
    /// Creates a sale transaction in the source project and marks items as purchased.
    /// Lineage edges are written atomically in the same batch.
    func sellToBusiness(items: [Item], accountId: String) async throws {
        guard !items.isEmpty else { return }

        let batch = db.batch()
        let itemsCollection = db.collection("accounts/\(accountId)/items")
        let txCollection = db.collection("accounts/\(accountId)/transactions")
        let edgesCollection = db.collection("accounts/\(accountId)/lineageEdges")

        // Create one sale transaction record
        let saleRef = txCollection.document()
        let saleData: [String: Any] = [
            "projectId": items.first?.projectId as Any,
            "transactionType": "sale",
            "isCanonicalInventorySale": true,
            "inventorySaleDirection": "project_to_business",
            "itemIds": items.compactMap(\.id),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        batch.setData(saleData, forDocument: saleRef)

        // Update each item: remove projectId, spaceId, set status to purchased
        for item in items {
            guard let itemId = item.id else { continue }
            let itemRef = itemsCollection.document(itemId)
            batch.updateData([
                "projectId": NSNull(),
                "spaceId": NSNull(),
                "status": "purchased",
                "transactionId": saleRef.documentID,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: itemRef)

            // Lineage edge — atomic with item update
            let edgeRef = edgesCollection.document()
            let edgeData: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "toTransactionId": saleRef.documentID,
                "movementKind": "sold",
                "source": "app",
                "fromProjectId": item.projectId as Any,
                "createdAt": FieldValue.serverTimestamp(),
            ]
            batch.setData(edgeData, forDocument: edgeRef)
        }

        try await batch.commit()
    }

    // MARK: - Sell to Project

    /// Moves items between projects, creating sale + purchase transaction records.
    /// Lineage edges are written atomically in the same batch.
    func sellToProject(
        items: [Item],
        destinationProjectId: String,
        accountId: String,
        sourceCategoryId: String? = nil,
        destinationCategoryId: String? = nil
    ) async throws {
        guard !items.isEmpty else { return }

        let batch = db.batch()
        let itemsCollection = db.collection("accounts/\(accountId)/items")
        let txCollection = db.collection("accounts/\(accountId)/transactions")
        let edgesCollection = db.collection("accounts/\(accountId)/lineageEdges")

        // Sale transaction in source project
        let saleRef = txCollection.document()
        var saleData: [String: Any] = [
            "projectId": items.first?.projectId as Any,
            "transactionType": "sale",
            "isCanonicalInventorySale": true,
            "inventorySaleDirection": "project_to_project",
            "itemIds": items.compactMap(\.id),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let categoryId = sourceCategoryId {
            saleData["budgetCategoryId"] = categoryId
        }
        batch.setData(saleData, forDocument: saleRef)

        // Purchase transaction in destination project
        let purchaseRef = txCollection.document()
        var purchaseData: [String: Any] = [
            "projectId": destinationProjectId,
            "transactionType": "purchase",
            "isCanonicalInventorySale": true,
            "inventorySaleDirection": "project_to_project",
            "itemIds": items.compactMap(\.id),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let categoryId = destinationCategoryId {
            purchaseData["budgetCategoryId"] = categoryId
        }
        batch.setData(purchaseData, forDocument: purchaseRef)

        // Move each item to destination project
        for item in items {
            guard let itemId = item.id else { continue }
            let itemRef = itemsCollection.document(itemId)
            batch.updateData([
                "projectId": destinationProjectId,
                "spaceId": NSNull(),
                "transactionId": purchaseRef.documentID,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: itemRef)

            // Lineage edge — atomic with item update
            let edgeRef = edgesCollection.document()
            let edgeData: [String: Any] = [
                "accountId": accountId,
                "itemId": itemId,
                "fromTransactionId": saleRef.documentID,
                "toTransactionId": purchaseRef.documentID,
                "movementKind": "sold",
                "source": "app",
                "fromProjectId": item.projectId as Any,
                "toProjectId": destinationProjectId,
                "createdAt": FieldValue.serverTimestamp(),
            ]
            batch.setData(edgeData, forDocument: edgeRef)
        }

        try await batch.commit()
    }

    // MARK: - Reassign to Project

    /// Moves items to a different project without creating financial records.
    /// Used to correct misallocations.
    func reassignToProject(items: [Item], destinationProjectId: String, accountId: String) async throws {
        guard !items.isEmpty else { return }

        let batch = db.batch()
        let itemsCollection = db.collection("accounts/\(accountId)/items")

        for item in items {
            guard let itemId = item.id else { continue }
            let itemRef = itemsCollection.document(itemId)
            batch.updateData([
                "projectId": destinationProjectId,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: itemRef)
        }

        try await batch.commit()
    }

    // MARK: - Reassign to Inventory

    /// Moves items back to business inventory without financial records.
    func reassignToInventory(items: [Item], accountId: String) async throws {
        guard !items.isEmpty else { return }

        let batch = db.batch()
        let itemsCollection = db.collection("accounts/\(accountId)/items")

        for item in items {
            guard let itemId = item.id else { continue }
            let itemRef = itemsCollection.document(itemId)
            batch.updateData([
                "projectId": NSNull(),
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: itemRef)
        }

        try await batch.commit()
    }
}
