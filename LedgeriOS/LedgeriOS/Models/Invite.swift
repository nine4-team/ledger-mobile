import FirebaseFirestore

struct Invite: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var email: String = ""
    var role: String = ""
    var companyFinancialAccess: CompanyFinancialAccess?
    var allowedFeeCategoryIds: [String]?
    var token: String?
    var createdByUid: String?
    var createdAt: Date?
    var acceptedAt: Date?
    var revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, email, role, companyFinancialAccess, allowedFeeCategoryIds, token, createdByUid, createdAt, acceptedAt, revokedAt
    }

    var resolvedCompanyFinancialAccess: CompanyFinancialAccess {
        if let companyFinancialAccess { return companyFinancialAccess }
        switch role {
        case MemberRole.owner.rawValue, MemberRole.admin.rawValue:
            return .full
        default:
            return .none
        }
    }

    var resolvedAllowedFeeCategoryIds: Set<String> {
        Set(allowedFeeCategoryIds ?? [])
    }

    var inviteLink: URL? {
        guard let token else { return nil }
        return InviteLinks.link(token: token)
    }
}
