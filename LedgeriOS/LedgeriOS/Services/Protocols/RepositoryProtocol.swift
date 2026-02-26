import FirebaseFirestore

protocol Repository<T> {
    associatedtype T: Codable & Identifiable

    func get(id: String) async throws -> T?
    func list() async throws -> [T]
    func list(where field: String, isEqualTo value: Any) async throws -> [T]
    func create(_ item: T) throws -> String
    func update(id: String, fields: [String: Any]) async throws
    func delete(id: String) async throws
    func subscribe(onChange: @escaping ([T]) -> Void) -> ListenerRegistration
    func subscribe(where field: String, isEqualTo value: Any, onChange: @escaping ([T]) -> Void) -> ListenerRegistration
    func subscribe(id: String, onChange: @escaping (T?) -> Void) -> ListenerRegistration
}
