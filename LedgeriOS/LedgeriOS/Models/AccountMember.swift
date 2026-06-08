import FirebaseFirestore

struct AccountMember: Codable, Identifiable, Hashable, @unchecked Sendable {
    @DocumentID var id: String?
    var accountId: String?
    var uid: String?
    var role: MemberRole?
    var companyFinancialAccess: CompanyFinancialAccess?
    var allowedFeeCategoryIds: [String]?
    var email: String?
    var name: String?
    var createdAt: Date?
    var updatedAt: Date?

    // Exclude timestamps from decoding — emulator data stores these as ISO strings
    // but Firestore Codable expects native Timestamp objects. The fields aren't
    // needed for discovery or current UI. Can add a flexible decoder later.
    enum CodingKeys: String, CodingKey {
        case id, accountId, uid, role, companyFinancialAccess, allowedFeeCategoryIds, email, name
    }

    var resolvedCompanyFinancialAccess: CompanyFinancialAccess {
        if let companyFinancialAccess { return companyFinancialAccess }
        switch role {
        case .owner, .admin:
            return .full
        case .user, nil:
            return .none
        }
    }

    var resolvedAllowedFeeCategoryIds: Set<String> {
        Set(allowedFeeCategoryIds ?? [])
    }
}
