import FirebaseFirestore

struct SpaceTemplatesService: SpaceTemplatesServiceProtocol {
    private func repo(accountId: String) -> FirestoreRepository<SpaceTemplate> {
        FirestoreRepository<SpaceTemplate>(path: "accounts/\(accountId)/presets/default/spaceTemplates")
    }

    func subscribe(accountId: String, onChange: @escaping ([SpaceTemplate]) -> Void) -> ListenerRegistration {
        repo(accountId: accountId).subscribe(onChange: onChange)
    }

    func create(accountId: String, template: SpaceTemplate) throws -> String {
        let id = try repo(accountId: accountId).create(template)
        return id
    }

    func update(accountId: String, templateId: String, fields: [String: Any]) async throws {
        try await repo(accountId: accountId).update(id: templateId, fields: fields)
    }

    func delete(accountId: String, templateId: String) async throws {
        try await repo(accountId: accountId).delete(id: templateId)
    }

    func createFromSpace(accountId: String, space: Space) throws -> String {
        var template = SpaceTemplate()
        template.name = space.name
        template.notes = space.notes
        template.checklists = space.checklists
        let id = try repo(accountId: accountId).create(template)
        return id
    }
}
