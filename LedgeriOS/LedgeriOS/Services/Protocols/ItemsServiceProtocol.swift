import FirebaseFirestore

protocol ItemsServiceProtocol {
    func getItem(accountId: String, itemId: String) async throws -> Item?
    func createItem(accountId: String, item: Item) throws -> String
    func updateItem(accountId: String, itemId: String, fields: [String: Any]) async throws
    func deleteItem(accountId: String, itemId: String) async throws
    func subscribeToItems(accountId: String, scope: ListScope, onChange: @escaping ([Item]) -> Void) -> ListenerRegistration
    func subscribeToItem(accountId: String, itemId: String, onChange: @escaping (Item?) -> Void) -> ListenerRegistration
}
