import FirebaseFirestore

protocol SpacesServiceProtocol {
    func getSpace(accountId: String, spaceId: String) async throws -> Space?
    func createSpace(accountId: String, space: Space) throws -> String
    func updateSpace(accountId: String, spaceId: String, fields: [String: Any]) async throws
    func deleteSpace(accountId: String, spaceId: String) async throws
    func subscribeToSpaces(accountId: String, scope: ListScope, onChange: @escaping ([Space]) -> Void) -> ListenerRegistration
    func subscribeToSpace(accountId: String, spaceId: String, onChange: @escaping (Space?) -> Void) -> ListenerRegistration
}
