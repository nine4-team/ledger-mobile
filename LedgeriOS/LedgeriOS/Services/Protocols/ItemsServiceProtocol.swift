import FirebaseFirestore

protocol ItemsServiceProtocol: Sendable {
    func getItem(accountId: String, itemId: String) async throws -> Item?
    func createItem(accountId: String, item: Item) throws -> String
    func createItemsForTransaction(accountId: String, transactionId: String, items: [Item]) async throws -> [String]
    func updateItem(accountId: String, itemId: String, fields: [String: Any]) async throws
    func deleteItem(accountId: String, item: Item) async throws
    func deleteItems(accountId: String, items: [Item]) async throws
    func subscribeToItems(accountId: String, scope: ListScope, onChange: @escaping ([Item]) -> Void) -> ListenerRegistration
    func subscribeToItem(accountId: String, itemId: String, onChange: @escaping (Item?) -> Void) -> ListenerRegistration
}
