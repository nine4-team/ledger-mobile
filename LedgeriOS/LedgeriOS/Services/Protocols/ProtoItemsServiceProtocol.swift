import FirebaseFirestore

protocol ProtoItemsServiceProtocol {
    func newProtoItemId(accountId: String) -> String
    func createProtoItem(accountId: String, protoItem: ProtoItem) throws -> String
    func createProtoItem(accountId: String, id: String, protoItem: ProtoItem) throws
    func updateProtoItem(accountId: String, protoItemId: String, fields: [String: Any]) async throws
    func deleteProtoItem(accountId: String, protoItemId: String) async throws
    func markProtoItemInReview(accountId: String, protoItemId: String, userId: String?) async throws
    func convertProtoItem(accountId: String, protoItemId: String, convertedItemId: String, userId: String?) async throws
    func subscribeToActiveProtoItems(accountId: String, onChange: @escaping ([ProtoItem]) -> Void) -> ListenerRegistration
    func subscribeToProtoItems(accountId: String, scope: ListScope, onChange: @escaping ([ProtoItem]) -> Void) -> ListenerRegistration
    func subscribeToProtoItemsForTransaction(accountId: String, transactionId: String, onChange: @escaping ([ProtoItem]) -> Void) -> ListenerRegistration
    func subscribeToProtoItem(accountId: String, protoItemId: String, onChange: @escaping (ProtoItem?) -> Void) -> ListenerRegistration
}
