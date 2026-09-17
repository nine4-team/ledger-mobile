import FirebaseFirestore

/// Shared persisted note for projects and spaces. Existing collections stay in place.
struct LedgerNote: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var text: String = ""
    var createdBy: String = ""
    var createdByName: String = ""
    var source: String? = "text"
    var createdAt: Date?
    var updatedAt: Date?
    var visualReference: NoteVisualReference?
}

// Compatibility names for existing context/service contracts; one underlying model.
typealias ProjectNote = LedgerNote
typealias SpaceReviewNote = LedgerNote
