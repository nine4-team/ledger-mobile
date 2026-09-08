import Foundation
import LedgerTargetCore

package enum FirebaseProjectLegacyNotesImportFailure: Error {
    case unresolvedOrInconsistentSource
}

/// Values for the private SQL primitive, not executable SQL or load authorization.
package struct FirebaseProjectLegacyNotesImportParameters: Encodable, Equatable, Sendable {
    package let p_account_id: String
    package let p_project_id: String
    package let p_notes: String?
    package let p_source_account: String
    package let p_source_document: String
    package let p_source_bytes: String

    package static func make(_ result: FirebaseProjectLegacyNotesResult) throws -> Self {
        guard case .mapped(let source, let account, let project, let notes) = result,
              source.documentPathSegments.count == 4,
              case .mapped(_, _, _, let originalNotes) = FirebaseProjectLegacyNotesConversion.convert(source,
                sourceAccountID: source.accountScopeID,
                sourceProjectID: source.documentPathSegments[3],
                targetAccountID: account, targetProjectID: project),
              notes.map({ Array($0.utf8) }) == originalNotes.map({ Array($0.utf8) }) else {
            throw FirebaseProjectLegacyNotesImportFailure.unresolvedOrInconsistentSource
        }
        let bytes = try source.canonicalEvidenceData()
        return Self(p_account_id: account.rawValue, p_project_id: project.rawValue,
            p_notes: notes, p_source_account: source.accountScopeID,
            p_source_document: source.documentPathSegments[3],
            p_source_bytes: "\\x" + bytes.map { String(format: "%02x", $0) }.joined())
    }

    private enum CodingKeys: String, CodingKey {
        case p_account_id, p_project_id, p_notes, p_source_account, p_source_document, p_source_bytes
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_account_id, forKey: .p_account_id)
        try c.encode(p_project_id, forKey: .p_project_id)
        try c.encode(p_notes, forKey: .p_notes) // SQL NULL is explicit, not a missing argument.
        try c.encode(p_source_account, forKey: .p_source_account)
        try c.encode(p_source_document, forKey: .p_source_document)
        try c.encode(p_source_bytes, forKey: .p_source_bytes)
    }
}
