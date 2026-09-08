import LedgerTargetCore

public enum FirebaseProjectLegacyNotesFailure: Equatable, Sendable {
    case invalidSourceDocument, sourceScopeMismatch, unsupportedNotesValue
}

public enum FirebaseProjectLegacyNotesResult: Equatable, Sendable {
    case mapped(source: FirebaseSourceDocument, accountId: AccountID, projectId: ProjectID, notes: String?)
    case unresolved(source: FirebaseSourceDocument, reason: FirebaseProjectLegacyNotesFailure)
}

/// Retains the complete source document, including absent-versus-null evidence.
/// Does not create individual notes, infer metadata, or authorize a database load.
public enum FirebaseProjectLegacyNotesConversion {
    /// Caller supplies an independently reconciled source-to-target Project mapping.
    /// This transform does not establish that mapping or permit a persistence write.
    package static func convert(_ document: FirebaseSourceDocument,
        sourceAccountID: String, sourceProjectID: String,
        targetAccountID: AccountID, targetProjectID: ProjectID) -> FirebaseProjectLegacyNotesResult {
        func unresolved(_ reason: FirebaseProjectLegacyNotesFailure) -> FirebaseProjectLegacyNotesResult {
            .unresolved(source: document, reason: reason)
        }
        let path = document.documentPathSegments
        guard document.evidenceKind == .record, path.count == 4,
              path[0] == "accounts", path[2] == "projects",
              (try? FirebaseSourceValue.reference(segments: path).validated()) != nil,
              case .map(let fields) = document.fields,
              (try? document.fields.validated()) != nil else { return unresolved(.invalidSourceDocument) }
        guard document.accountScopeID.utf8.elementsEqual(sourceAccountID.utf8),
              path[1].utf8.elementsEqual(sourceAccountID.utf8),
              path[3].utf8.elementsEqual(sourceProjectID.utf8) else { return unresolved(.sourceScopeMismatch) }
        if let account = fields.first(where: { $0.key == "accountId" })?.value {
            guard case .string(let embedded) = account,
                  embedded.utf8.elementsEqual(sourceAccountID.utf8) else { return unresolved(.sourceScopeMismatch) }
        }
        let notes: String?
        switch fields.first(where: { $0.key == "notes" })?.value {
        case nil, .null?: notes = nil
        case .string(let text)?:
            // PostgreSQL text cannot store NUL; retain/quarantine, never strip it.
            guard !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
                return unresolved(.unsupportedNotesValue)
            }
            notes = text
        default: return unresolved(.unsupportedNotesValue)
        }
        return .mapped(source: document, accountId: targetAccountID, projectId: targetProjectID, notes: notes)
    }
}
