import FirebaseFirestore

enum ProtoItemStatus: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case open
    case inReview = "in_review"
    case converted

    var displayLabel: String {
        switch self {
        case .open: "Open"
        case .inReview: "In Review"
        case .converted: "Converted"
        }
    }
}

enum ProtoItemCaptureContext: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case project
    case inventory
    case transaction
}

enum ProtoItemSourceHint: String, Codable, CaseIterable, CaseInsensitiveStringEnum {
    case clientPurchase = "client_purchase"
    case businessPurchase = "business_purchase"
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
/// happen before the financial record is known or converted.
struct ProtoItem: Codable, Identifiable, Hashable, @unchecked Sendable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var intendedProjectId: String?
    var transactionId: String?
    var name: String?
    var captureContext: ProtoItemCaptureContext?
    var status: ProtoItemStatus?
    var sourceHint: ProtoItemSourceHint?
    var photos: [AttachmentRef]?
    var notes: String?
    var extracted: ProtoItemExtraction?
    var candidateTransactionId: String?
    var candidateItemId: String?
    var convertedItemId: String?
    var convertedAt: Date?
    var createdBy: String?
    var updatedBy: String?
    var convertedBy: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, projectId, intendedProjectId, transactionId,
             name, captureContext, status, sourceHint, photos, notes, extracted,
             candidateTransactionId, candidateItemId, convertedItemId,
             convertedAt, createdBy, updatedBy, convertedBy,
             createdAt, updatedAt
    }
}
