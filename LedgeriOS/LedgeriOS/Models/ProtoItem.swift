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
    var barcodePayloads: [String]?
    var skuCandidates: [String]?
    var confidence: Double?
    var extractedAt: Date?
    var rawTextByEngine: [String: String]? = nil
    var skuEvidence: [ProtoItemSkuEvidence]? = nil
    var rejectedSkuEvidence: [ProtoItemSkuEvidence]? = nil
    var reviewFlags: [String]? = nil
    var engineEvents: [String]? = nil
}

struct ProtoItemSkuEvidence: Codable, Hashable, Sendable {
    var value: String
    var sourceEngine: String
    var sourceImage: String
    var extractionMethod: String
    var confidence: Double
    var department: String?
    var priceCents: Int?
    var rejectionReason: String?
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
    var sku: String?
    var quantity: Int?
    var notes: String?
    var extracted: ProtoItemExtraction?
    /// Legacy suggestion metadata. Read-only for migration/audit; new flows
    /// write confirmed associations to `transactionId` instead.
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
             name, captureContext, status, sourceHint, photos, sku, quantity, notes, extracted,
             candidateTransactionId, candidateItemId, convertedItemId,
             convertedAt, createdBy, updatedBy, convertedBy,
             createdAt, updatedAt
    }
}
