/// Current custody evidence only. Source edit/creation times are deliberately
/// not exposed as movement times; historical placement requires its own proof.
package enum FirebaseCurrentItemPlacement {
    package struct Result: Sendable {
        package let source: FirebaseSourceDocument
        package let projectID: String?
        package let spaceID: String?
        package let issues: Set<String>
        package var isResolved: Bool { issues.isEmpty }
    }
    package static func read(_ item: FirebaseSourceDocument, accountID: String,
                             documents: [FirebaseSourceDocument]) -> Result {
        var issues = Set<String>()
        guard exact(item.accountScopeID, accountID), item.documentPathSegments.count == 4,
              item.documentPathSegments[0] == "accounts", exact(item.documentPathSegments[1], accountID),
              item.documentPathSegments[2] == "items", item.evidenceKind == .record,
              (try? item.fields.validated()) != nil, case .map(let fields) = item.fields else {
            return .init(source: item, projectID: nil, spaceID: nil, issues: ["invalid_item"])
        }
        func field(_ key: String) -> FirebaseSourceValue? { fields.first { $0.key == key }?.value }
        if let embedded = field("accountId"), !matchesIdentifier(embedded, accountID) { issues.insert("account_conflict") }
        let project: String?
        switch field("projectId") {
        case .null: project = nil
        case .string(let id) where !id.isEmpty && !id.contains("/"): project = id
        default: project = nil; issues.insert("unknown_project_scope")
        }
        let space: String?
        switch field("spaceId") {
        case nil, .null: space = nil
        case .string(let id) where !id.isEmpty && !id.contains("/"): space = id
        default: space = nil; issues.insert("invalid_space")
        }
        func matches(_ path: [String]) -> [FirebaseSourceDocument] {
            documents.filter {
                guard $0.documentPathSegments.elementsEqual(path, by: exact), exact($0.accountScopeID, accountID), $0.evidenceKind == .record,
                      (try? $0.fields.validated()) != nil, case .map(let values) = $0.fields else { return false }
                return !values.contains(where: { $0.key == "accountId" && !matchesIdentifier($0.value, accountID) })
            }
        }
        if let project, matches(["accounts", accountID, "projects", project]).count != 1 { issues.insert("unresolved_project") }
        if let space {
            let candidates = matches(["accounts", accountID, "spaces", space])
            if candidates.count != 1 { issues.insert("unresolved_space") }
            else if case .map(let spaceFields) = candidates[0].fields,
                    (try? candidates[0].fields.validated()) != nil {
                let scope = spaceFields.first(where: { $0.key == "projectId" })?.value
                let scopeMatches = project.map { matchesIdentifier(scope, $0) } ?? (scope == .null)
                if !scopeMatches { issues.insert("space_scope_conflict") }
                if let embedded = spaceFields.first(where: { $0.key == "accountId" })?.value,
                   !matchesIdentifier(embedded, accountID) { issues.insert("space_account_conflict") }
            } else { issues.insert("invalid_space") }
        }
        return .init(source: item, projectID: project, spaceID: space, issues: issues)
    }

    private static func exact(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    private static func matchesIdentifier(_ value: FirebaseSourceValue?, _ expected: String) -> Bool {
        guard case .string(let actual) = value else { return false }
        return exact(actual, expected)
    }
}
