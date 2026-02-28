import FirebaseFirestore

struct LineageEdge: Codable, Identifiable {
    @DocumentID var id: String?
    var accountId: String?
    var itemId: String?
    var fromTransactionId: String?
    var toTransactionId: String?
    var movementKind: String?   // "sold" | "returned" | "correction" | "association"
    var source: String?         // "app" | "server" | "migration"
    var fromProjectId: String?
    var toProjectId: String?
    var note: String?
    var createdBy: String?

    @ServerTimestamp var createdAt: Date?
}

struct LineageEdgesService {
    private let db = Firestore.firestore()

    private func collection(accountId: String) -> CollectionReference {
        db.collection("accounts/\(accountId)/lineageEdges")
    }

    /// Fetches edges where the given transaction is either the source or destination.
    func edges(forTransaction transactionId: String, accountId: String) async throws -> [LineageEdge] {
        let col = collection(accountId: accountId)
        async let fromEdges = col
            .whereField("fromTransactionId", isEqualTo: transactionId)
            .getDocuments()
        async let toEdges = col
            .whereField("toTransactionId", isEqualTo: transactionId)
            .getDocuments()

        let (fromSnapshot, toSnapshot) = try await (fromEdges, toEdges)
        let fromParsed = fromSnapshot.documents.compactMap { try? $0.data(as: LineageEdge.self) }
        let toParsed = toSnapshot.documents.compactMap { try? $0.data(as: LineageEdge.self) }

        var seen = Set<String>()
        return (fromParsed + toParsed).filter { edge in
            guard let id = edge.id else { return false }
            return seen.insert(id).inserted
        }
    }

    /// Creates a new lineage edge document.
    func createEdge(_ edge: LineageEdge, accountId: String) throws {
        let ref = collection(accountId: accountId).document()
        try ref.setData(from: edge)
    }
}
