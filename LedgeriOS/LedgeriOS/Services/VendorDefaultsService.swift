import FirebaseFirestore

struct VendorDefaultsService: VendorDefaultsServiceProtocol {
    static let defaultVendors: [String] = [
        "Homegoods", "Amazon", "Wayfair", "Target", "Ross",
        "Arhaus", "Pottery Barn", "Crate & Barrel", "West Elm",
        "Living Spaces", "Home Depot", "Lowes", "Movers", "Gas", "Inventory"
    ]

    private func documentRef(accountId: String) -> DocumentReference {
        Firestore.firestore().document("accounts/\(accountId)/presets/default/vendors/default")
    }

    func subscribe(accountId: String, onChange: @escaping (VendorDefaults?) -> Void) -> ListenerRegistration {
        documentRef(accountId: accountId).addSnapshotListener { snapshot, error in
            guard let snapshot, snapshot.exists else {
                onChange(nil)
                return
            }
            let defaults = try? snapshot.data(as: VendorDefaults.self)
            onChange(defaults)
        }
    }

    func save(accountId: String, vendors: [String]) throws {
        let data: [String: Any] = [
            "vendors": vendors,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        documentRef(accountId: accountId).setData(data, merge: true)
    }

    func addVendorIfMissing(accountId: String, name: String) async throws {
        let cleaned = Self.cleanedVendorName(name)
        guard !cleaned.isEmpty else { return }

        let snapshot = try await documentRef(accountId: accountId).getDocument()
        var vendors = (try? snapshot.data(as: VendorDefaults.self).vendors) ?? []
        let normalized = Self.normalizedVendorName(cleaned)
        guard !vendors.contains(where: { Self.normalizedVendorName($0) == normalized }) else { return }

        vendors.append(cleaned)
        try save(accountId: accountId, vendors: vendors)
    }

    func initializeDefaults(accountId: String) async throws {
        let snapshot = try await documentRef(accountId: accountId).getDocument()
        if !snapshot.exists {
            try save(accountId: accountId, vendors: Self.defaultVendors)
        }
    }

    static func cleanedVendorName(_ name: String) -> String {
        name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func normalizedVendorName(_ name: String) -> String {
        cleanedVendorName(name).lowercased()
    }

    /// Builds the source picker list while allowing a flow to hide choices
    /// that would be invalid in its current context.
    static func displayVendorOptions(
        fixedOptions: [String],
        vendors: [String],
        excluding excludedOptions: Set<String> = []
    ) -> [String] {
        let excluded = Set(excludedOptions.map(normalizedVendorName))
        var seen = Set<String>()

        return (fixedOptions + vendors).filter { vendor in
            let normalized = normalizedVendorName(vendor)
            guard !normalized.isEmpty,
                  !excluded.contains(normalized),
                  !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }
}
