import LedgerTargetCore

public enum FirebaseProjectNoteFailure: Equatable, Sendable {
    case invalidSourceDocument, sourceScopeMismatch
    case unsupportedField(String)
}

/// Source facts, not a target note snapshot or a new-note submission. Optional
/// values never imply defaults; the retained document distinguishes absent/null.
public struct FirebaseProjectNoteSourceFields: Equatable, Sendable {
    public let text: String?
    public let source: String?
    public let createdBy: String?
    public let createdByName: String?
    /// Validated Firebase timestamps retain integer seconds and nanoseconds.
    public let createdAt: FirebaseSourceValue?
    public let updatedAt: FirebaseSourceValue?
}

public enum FirebaseProjectNoteResult: Equatable, Sendable {
    case mapped(source: FirebaseSourceDocument, accountId: AccountID,
                projectId: ProjectID, noteId: ProjectNoteID, fields: FirebaseProjectNoteSourceFields)
    case unresolved(source: FirebaseSourceDocument, reason: FirebaseProjectNoteFailure)
}

public enum FirebaseProjectNoteConversion {
    /// Caller supplies independently reconciled source-to-target identities.
    /// No persistence authority, principal inference, time rounding, history
    /// reconstruction, or pending new-submission normalization occurs here.
    package static func convert(_ document: FirebaseSourceDocument,
        sourceAccountID: String, sourceProjectID: String, sourceNoteID: String,
        targetAccountID: AccountID, targetProjectID: ProjectID,
        targetNoteID: ProjectNoteID) -> FirebaseProjectNoteResult {
        func unresolved(_ reason: FirebaseProjectNoteFailure) -> FirebaseProjectNoteResult {
            .unresolved(source: document, reason: reason)
        }
        let path = document.documentPathSegments
        guard document.evidenceKind == .record, path.count == 6,
              path[0] == "accounts", path[2] == "projects", path[4] == "notes",
              (try? FirebaseSourceValue.reference(segments: path).validated()) != nil,
              case .map(let entries) = document.fields,
              (try? document.fields.validated()) != nil else {
            return unresolved(.invalidSourceDocument)
        }
        func value(_ key: String) -> FirebaseSourceValue? {
            entries.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
        }
        guard document.accountScopeID.utf8.elementsEqual(sourceAccountID.utf8),
              path[1].utf8.elementsEqual(sourceAccountID.utf8),
              path[3].utf8.elementsEqual(sourceProjectID.utf8),
              path[5].utf8.elementsEqual(sourceNoteID.utf8) else {
            return unresolved(.sourceScopeMismatch)
        }
        for (key, expected) in [("accountId", sourceAccountID), ("projectId", sourceProjectID)] {
            if let embedded = value(key) {
                guard case .string(let actual) = embedded,
                      actual.utf8.elementsEqual(expected.utf8) else {
                    return unresolved(.sourceScopeMismatch)
                }
            }
        }
        // This is intentionally broader than target submission/read validators.
        // PostgreSQL-inexpressible NUL remains unresolved, never stripped.
        for key in ["text", "source", "createdBy", "createdByName"] {
            switch value(key) {
            case nil, .null?: break
            case .string(let text)? where !text.unicodeScalars.contains(where: { $0.value == 0 }): break
            default: return unresolved(.unsupportedField(key))
            }
        }
        for key in ["createdAt", "updatedAt"] {
            switch value(key) {
            case nil, .null?, .timestamp?: break
            default: return unresolved(.unsupportedField(key))
            }
        }
        func string(_ key: String) -> String? {
            if case .string(let text)? = value(key) { return text }
            return nil
        }
        func timestamp(_ key: String) -> FirebaseSourceValue? {
            if case .timestamp? = value(key) { return value(key) }
            return nil
        }
        return .mapped(source: document, accountId: targetAccountID,
            projectId: targetProjectID, noteId: targetNoteID,
            fields: FirebaseProjectNoteSourceFields(text: string("text"), source: string("source"),
                createdBy: string("createdBy"), createdByName: string("createdByName"),
                createdAt: timestamp("createdAt"), updatedAt: timestamp("updatedAt")))
    }
}
