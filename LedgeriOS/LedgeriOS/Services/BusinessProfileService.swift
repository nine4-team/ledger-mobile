import FirebaseFirestore

struct BusinessProfileService: BusinessProfileServiceProtocol {
    let syncTracker: SyncTracking

    private func documentRef(accountId: String) -> DocumentReference {
        Firestore.firestore().document("accounts/\(accountId)")
    }

    func fetch(accountId: String) async throws -> BusinessProfile? {
        let snapshot = try await documentRef(accountId: accountId).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }

        // BusinessProfile fields live directly on the account document
        let name = data["businessName"] as? String
        let logoUrl = data["businessLogoUrl"] as? String

        guard name != nil || logoUrl != nil else { return nil }

        var profile = BusinessProfile()
        profile.name = name
        profile.logoUrl = logoUrl
        return profile
    }

    func update(accountId: String, profile: BusinessProfile) async throws {
        var fields: [String: Any] = [
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let name = profile.name {
            fields["businessName"] = name
        }
        if let logoUrl = profile.logoUrl {
            fields["businessLogoUrl"] = logoUrl
        }

        try await documentRef(accountId: accountId).updateData(fields)
        syncTracker.trackPendingWrite()
    }
}
