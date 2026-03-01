import FirebaseFirestore

// MARK: - SpaceTemplatesService

protocol SpaceTemplatesServiceProtocol: Sendable {
    func subscribe(accountId: String, onChange: @escaping ([SpaceTemplate]) -> Void) -> ListenerRegistration
    func create(accountId: String, template: SpaceTemplate) throws -> String
    func update(accountId: String, templateId: String, fields: [String: Any]) async throws
    func delete(accountId: String, templateId: String) async throws
    func createFromSpace(accountId: String, space: Space) throws -> String
}

// MARK: - VendorDefaultsService

protocol VendorDefaultsServiceProtocol: Sendable {
    func subscribe(accountId: String, onChange: @escaping (VendorDefaults?) -> Void) -> ListenerRegistration
    func save(accountId: String, vendors: [String]) throws
    func initializeDefaults(accountId: String) async throws
}

// MARK: - InvitesService

protocol InvitesServiceProtocol: Sendable {
    func subscribe(accountId: String, onChange: @escaping ([Invite]) -> Void) -> ListenerRegistration
    func create(accountId: String, email: String, role: String, createdByUid: String) throws -> String
    func revoke(accountId: String, inviteId: String) async throws
}

// MARK: - BusinessProfileService

protocol BusinessProfileServiceProtocol: Sendable {
    func fetch(accountId: String) async throws -> BusinessProfile?
    func update(accountId: String, profile: BusinessProfile) async throws
}

// MARK: - AccountPresetsService

protocol AccountPresetsServiceProtocol: Sendable {
    func initializeDefaults(accountId: String) async throws
}
