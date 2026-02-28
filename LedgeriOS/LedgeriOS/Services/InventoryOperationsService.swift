import FirebaseFirestore

/// Multi-step atomic Firestore operations for inventory movements:
/// sell to business, sell to project, reassign, reassign to inventory.
struct InventoryOperationsService {
    private let db = Firestore.firestore()
    private let lineageService = LineageEdgesService()

    // MARK: - Sell to Business

    /// Moves items from a project into business inventory.
    /// Creates a sale transaction in the source project and marks items as purchased.
    func sellToBusiness(items: [Item], accountId: String) async throws {
        guard !items.isEmpty else { return }

        let batch = db.batch()
        let itemsCollection = db.collection("accounts/\(accountId)/items")
        let txCollection = db.collection("accounts/\(accountId)/transactions")

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
        }

        try await batch.commit()

        // Create lineage edges (fire-and-forget after batch)
        for item in items {
            guard let itemId = item.id else { continue }
            var edge = LineageEdge()
            edge.accountId = accountId
            edge.itemId = itemId
            edge.fromTransactionId = nil
            edge.toTransactionId = saleRef.documentID
            edge.movementKind = "sold"
            edge.source = "app"
            edge.fromProjectId = item.projectId
            edge.toProjectId = nil
            try? lineageService.createEdge(edge, accountId: accountId)
        }
    }

    // MARK: - Sell to Project

    /// Moves items between projects, creating sale + purchase transaction records.
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
        }

        try await batch.commit()

        // Create lineage edges
        for item in items {
            guard let itemId = item.id else { continue }
            var edge = LineageEdge()
            edge.accountId = accountId
            edge.itemId = itemId
            edge.fromTransactionId = saleRef.documentID
            edge.toTransactionId = purchaseRef.documentID
            edge.movementKind = "sold"
            edge.source = "app"
            edge.fromProjectId = item.projectId
            edge.toProjectId = destinationProjectId
            try? lineageService.createEdge(edge, accountId: accountId)
        }
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
