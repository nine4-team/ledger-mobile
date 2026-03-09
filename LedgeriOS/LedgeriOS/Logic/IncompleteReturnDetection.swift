/// Detects items whose status is "returned" but haven't been properly processed
/// through the return flow (no "returned" lineage edge from their current transaction).
enum IncompleteReturnDetection {

    /// An item has an incomplete return when ALL of the following are true:
    /// 1. item.status == "returned"
    /// 2. The transaction is not a Return transaction
    /// 3. No lineage edge with movementKind "returned" exists for this item
    static func isIncompleteReturn(
        itemId: String,
        itemStatus: String?,
        transactionType: String?,
        edgesFromTransaction: [LineageEdge]
    ) -> Bool {
        guard itemStatus == "returned" else { return false }

        // If no transaction context, can't determine completeness
        guard let txType = transactionType else { return false }

        // Item is already in a return transaction — return is complete
        if txType.trimmingCharacters(in: .whitespaces).lowercased() == "return" {
            return false
        }

        // Check if a "returned" edge exists for this item
        let hasReturnedEdge = edgesFromTransaction.contains {
            $0.itemId == itemId && $0.movementKind == "returned"
        }

        return !hasReturnedEdge
    }

    /// Filters items to find those with incomplete returns. Returns their IDs.
    static func findIncompleteReturns(
        items: [(id: String, status: String?)],
        transactionType: String?,
        edgesFromTransaction: [LineageEdge]
    ) -> [String] {
        items.compactMap { item in
            isIncompleteReturn(
                itemId: item.id,
                itemStatus: item.status,
                transactionType: transactionType,
                edgesFromTransaction: edgesFromTransaction
            ) ? item.id : nil
        }
    }
}
