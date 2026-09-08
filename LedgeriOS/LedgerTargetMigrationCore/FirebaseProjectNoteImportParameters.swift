import Foundation
import LedgerTargetCore

package enum FirebaseProjectNoteImportFailure: Error {
    case inconsistentSource, unsupportedTargetRepresentation
}

/// Private import values, not SQL or load authorization. Principal reconciliation
/// is caller-owned; an original creator identifier never becomes an Auth identity.
package struct FirebaseProjectNoteImportParameters: Encodable, Sendable {
    package let p_account_id: String
    package let p_project_id: String
    package let p_note_id: String
    package let p_note_text: String
    package let p_source: String
    package let p_original_creator_id: String?
    package let p_creator_display_name: String?
    package let p_created_by_principal_id: String?
    package let p_created_at_ms: Int64?
    package let p_created_at_submillis: Int32?
    package let p_last_edited_at_ms: Int64?
    package let p_last_edited_at_submillis: Int32?
    package let p_source_account: String
    package let p_source_project: String
    package let p_source_note: String
    package let p_source_bytes: String

    package static func make(_ result: FirebaseProjectNoteResult,
        reconciledCreatorPrincipalId: PrincipalID? = nil) throws -> Self {
        guard case .mapped(let source, let account, let project, let note, let fields) = result,
              source.documentPathSegments.count == 6,
              case .mapped(_, _, _, _, let original) = FirebaseProjectNoteConversion.convert(source,
                sourceAccountID: source.accountScopeID, sourceProjectID: source.documentPathSegments[3],
                sourceNoteID: source.documentPathSegments[5], targetAccountID: account,
                targetProjectID: project, targetNoteID: note),
              sameBytes(fields.text, original.text), sameBytes(fields.source, original.source),
              sameBytes(fields.createdBy, original.createdBy), sameBytes(fields.createdByName, original.createdByName),
              fields.createdAt == original.createdAt, fields.updatedAt == original.updatedAt else {
            throw FirebaseProjectNoteImportFailure.inconsistentSource
        }
        guard let text = fields.text, let channel = fields.source else {
            throw FirebaseProjectNoteImportFailure.unsupportedTargetRepresentation
        }
        let created = try timestamp(fields.createdAt)
        let edited = try timestamp(fields.updatedAt)
        do {
            // Read/import constraints only. Never trim or repair source to fit them.
            _ = try ProjectNoteSnapshot(id: note, accountId: account, projectId: project,
                content: .visible(ProjectNoteText(validating: text)),
                source: ProjectNoteSource(validating: channel),
                createdByPrincipalId: reconciledCreatorPrincipalId,
                creatorDisplayName: fields.createdByName.map(ProjectNoteCreatorDisplayName.init(validating:)),
                createdTimestamp: created, revision: 0, lastEditedTimestamp: edited,
                originalCreatorId: fields.createdBy)
        } catch {
            throw FirebaseProjectNoteImportFailure.unsupportedTargetRepresentation
        }
        let bytes = try source.canonicalEvidenceData()
        return Self(p_account_id: account.rawValue, p_project_id: project.rawValue,
            p_note_id: note.rawValue, p_note_text: text, p_source: channel,
            p_original_creator_id: fields.createdBy, p_creator_display_name: fields.createdByName,
            p_created_by_principal_id: reconciledCreatorPrincipalId?.rawValue,
            p_created_at_ms: created.map(milliseconds), p_created_at_submillis: created.map { $0.nanoseconds % 1_000_000 },
            p_last_edited_at_ms: edited.map(milliseconds), p_last_edited_at_submillis: edited.map { $0.nanoseconds % 1_000_000 },
            p_source_account: source.accountScopeID, p_source_project: source.documentPathSegments[3],
            p_source_note: source.documentPathSegments[5],
            p_source_bytes: "\\x" + bytes.map { String(format: "%02x", $0) }.joined())
    }

    private static func sameBytes(_ lhs: String?, _ rhs: String?) -> Bool {
        lhs.map { Array($0.utf8) } == rhs.map { Array($0.utf8) }
    }

    private static func timestamp(_ value: FirebaseSourceValue?) throws -> ProjectNoteTimestamp? {
        guard let value else { return nil }
        guard case .timestamp(let seconds, let nanos) = value, let seconds = Int64(seconds),
              let nanos = Int32(exactly: nanos) else { throw FirebaseProjectNoteImportFailure.inconsistentSource }
        return try ProjectNoteTimestamp(secondsSince1970: seconds, nanoseconds: nanos)
    }

    private static func milliseconds(_ time: ProjectNoteTimestamp) -> Int64 {
        time.secondsSince1970 * 1_000 + Int64(time.nanoseconds / 1_000_000)
    }

    private enum CodingKeys: String, CodingKey {
        case p_account_id, p_project_id, p_note_id, p_note_text, p_source,
             p_original_creator_id, p_creator_display_name, p_created_by_principal_id,
             p_created_at_ms, p_created_at_submillis, p_last_edited_at_ms, p_last_edited_at_submillis,
             p_source_account, p_source_project, p_source_note, p_source_bytes
    }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_account_id, forKey: .p_account_id)
        try c.encode(p_project_id, forKey: .p_project_id)
        try c.encode(p_note_id, forKey: .p_note_id)
        try c.encode(p_note_text, forKey: .p_note_text)
        try c.encode(p_source, forKey: .p_source)
        try c.encode(p_original_creator_id, forKey: .p_original_creator_id)
        try c.encode(p_creator_display_name, forKey: .p_creator_display_name)
        try c.encode(p_created_by_principal_id, forKey: .p_created_by_principal_id)
        try c.encode(p_created_at_ms, forKey: .p_created_at_ms)
        try c.encode(p_created_at_submillis, forKey: .p_created_at_submillis)
        try c.encode(p_last_edited_at_ms, forKey: .p_last_edited_at_ms)
        try c.encode(p_last_edited_at_submillis, forKey: .p_last_edited_at_submillis)
        try c.encode(p_source_account, forKey: .p_source_account)
        try c.encode(p_source_project, forKey: .p_source_project)
        try c.encode(p_source_note, forKey: .p_source_note)
        try c.encode(p_source_bytes, forKey: .p_source_bytes)
    }
}
