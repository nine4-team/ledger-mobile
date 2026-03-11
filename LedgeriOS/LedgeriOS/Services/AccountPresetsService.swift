import FirebaseFirestore

struct AccountPresetsService: AccountPresetsServiceProtocol {
    let vendorDefaultsService: VendorDefaultsServiceProtocol

    func initializeDefaults(accountId: String) async throws {
        try await vendorDefaultsService.initializeDefaults(accountId: accountId)
    }
}
