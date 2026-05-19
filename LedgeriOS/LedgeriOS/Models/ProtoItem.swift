import FirebaseFirestore

enum ProtoItemStatus: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case open
    case inReview = "in_review"
    case resolved
    case dismissed

    var displayLabel: String {
        switch self {
        case .open: "Open"
        case .inReview: "In Review"
        case .resolved: "Resolved"
        case .dismissed: "Dismissed"
        }
    }
}

enum ProtoItemCaptureContext: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case project
    case inventory
    case transaction
}

enum ProtoItemSourceHint: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case purchasedByClient = "purchased_by_client"
    case purchasedByBusiness = "purchased_by_business"
    case fromInventory = "from_inventory"
    case unknown
}

struct ProtoItemExtraction: Codable, Hashable, Sendable {
    var rawText: String?
    var skuCandidates: [String]?
    var confidence: Double?
    var extractedAt: Date?
}

/// Photo-first capture object for "this will become an item later".
///
/// Proto items intentionally stay separate from `Item` so fast field capture can
/// happen before the financial record is known or resolved.
struct ProtoItem: Codable, Identifiable, Hashable, @unchecked Sendable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var intendedProjectId: String?
    var transactionId: String?
    var captureContext: ProtoItemCaptureContext?
    var status: ProtoItemStatus?
    var sourceHint: ProtoItemSourceHint?
    var photos: [AttachmentRef]?
    var notes: String?
    var extracted: ProtoItemExtraction?
    var candidateTransactionId: String?
    var candidateItemId: String?
    var resolvedItemId: String?
    var resolvedAt: Date?
    var dismissedAt: Date?
    var createdBy: String?
    var updatedBy: String?
    var resolvedBy: String?
    var dismissedBy: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, projectId, intendedProjectId, transactionId,
             captureContext, status, sourceHint, photos, notes, extracted,
             candidateTransactionId, candidateItemId, resolvedItemId,
             resolvedAt, dismissedAt, createdBy, updatedBy, resolvedBy,
             dismissedBy, createdAt, updatedAt
    }
}
