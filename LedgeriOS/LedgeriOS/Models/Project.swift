import FirebaseFirestore

struct Project: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var name: String = ""
    var clientName: String = ""
    var description: String?
    var mainImageUrl: String?
    var mainImageThumbUrlSm: String?
    var mainImageThumbUrlMd: String?
    var isArchived: Bool?
    var notes: String?
    var budgetSummary: ProjectBudgetSummary?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, name, clientName, description, mainImageUrl, mainImageThumbUrlSm, mainImageThumbUrlMd, isArchived, notes, budgetSummary
    }
}

struct ProjectBudgetSummary: Codable, Hashable {
    var totalBudgetCents: Int?
    var spentCents: Int?
    var categories: [String: BudgetSummaryCategory]?
}

struct BudgetSummaryCategory: Codable, Hashable {
    var budgetCents: Int?
    var spentCents: Int?
    var name: String?
    /// Legacy — Phase 4 stops writing this. Use `supportedTypes` going forward.
    var categoryType: String?
    /// Transaction kinds this category accepts, denormalized from the source
    /// category document. See `docs/specs/transaction-type.md`.
    var supportedTypes: [String]?
    var isArchived: Bool?
    var excludeFromOverallBudget: Bool?

    /// Derive `[TransactionType]` from the raw `supportedTypes` strings, falling
    /// back to the legacy `categoryType` for pre-migration summaries.
    var resolvedSupportedTypes: [TransactionType] {
        if let explicit = supportedTypes {
            let decoded = explicit.compactMap { TransactionType(rawValue: $0.lowercased()) }
            if !decoded.isEmpty { return decoded }
        }
        switch categoryType?.lowercased() {
        case "fee":      return [.fee]
        case "expense":  return [.expense]
        case "general":  return [.expense]
        case "itemized": return [.purchase, .return]
        default:         return [.purchase, .return, .expense]
        }
    }
}
