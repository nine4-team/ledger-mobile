import FirebaseFirestore

protocol TransactionsServiceProtocol: Sendable {
    func getTransaction(accountId: String, transactionId: String) async throws -> Transaction?
    func createTransaction(accountId: String, transaction: Transaction) throws -> String
    func updateTransaction(accountId: String, transactionId: String, fields: [String: Any]) async throws
    func deleteTransaction(accountId: String, transactionId: String) async throws
    func subscribeToTransactions(accountId: String, scope: ListScope, onChange: @escaping ([Transaction]) -> Void) -> ListenerRegistration
    func subscribeToTransaction(accountId: String, transactionId: String, onChange: @escaping (Transaction?) -> Void) -> ListenerRegistration
}
