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

    func initializeDefaults(accountId: String) async throws {
        let snapshot = try await documentRef(accountId: accountId).getDocument()
        if !snapshot.exists {
            try save(accountId: accountId, vendors: Self.defaultVendors)
        }
    }
}
