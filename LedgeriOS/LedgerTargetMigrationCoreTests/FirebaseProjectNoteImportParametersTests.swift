import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetMigrationCore

@Suite("Individual note private import parameters")
struct FirebaseProjectNoteImportParametersTests {
    @Test("Missing metadata stays explicit null; a raw MCP creator is not a principal")
    func nullMetadata() throws {
        let values = try FirebaseProjectNoteImportParameters.make(mapped([
            .init(key: "createdBy", value: .string("mcp-agent"))
        ]))
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(values)) as? [String: Any])
        #expect(json.count == 16)
        #expect(values.p_original_creator_id == "mcp-agent")
        for key in ["p_created_by_principal_id", "p_creator_display_name", "p_created_at_ms",
                    "p_created_at_submillis", "p_last_edited_at_ms", "p_last_edited_at_submillis"] {
            #expect(json[key] is NSNull)
        }
    }

    @Test("Exact text and full source evidence survive parameter encoding")
    func exactBytes() throws {
        let text = "  e\u{0301}\r\n第二行\t "
        let result = try mapped([.init(key: "unknown", value: .integer("9007199254740993"))], text: text)
        let values = try FirebaseProjectNoteImportParameters.make(result)
        guard case .mapped(let source, _, _, _, _) = result else { Issue.record("Expected mapping"); return }
        #expect(values.p_note_text.utf8.elementsEqual(text.utf8))
        #expect(values.p_source_bytes == "\\x" + (try source.canonicalEvidenceData()).map { String(format: "%02x", $0) }.joined())
    }

    @Test("Negative and submillisecond timestamps never round through Date")
    func exactTimes() throws {
        let values = try FirebaseProjectNoteImportParameters.make(mapped([
            .init(key: "createdAt", value: .timestamp(seconds: "-1", nanoseconds: 999_999_999)),
            .init(key: "updatedAt", value: .timestamp(seconds: "1700000000", nanoseconds: 123_456_789))
        ]))
        #expect(values.p_created_at_ms == -1 && values.p_created_at_submillis == 999_999)
        #expect(values.p_last_edited_at_ms == 1_700_000_000_123 && values.p_last_edited_at_submillis == 456_789)
        let updateOnly = try FirebaseProjectNoteImportParameters.make(mapped([
            .init(key: "updatedAt", value: .timestamp(seconds: "0", nanoseconds: 1))
        ]))
        #expect(updateOnly.p_created_at_ms == nil && updateOnly.p_created_at_submillis == nil)
        #expect(updateOnly.p_last_edited_at_ms == 0 && updateOnly.p_last_edited_at_submillis == 1)
    }

    @Test("Principal mapping is explicit and never replaces original provenance")
    func principalMapping() throws {
        let result = try mapped([.init(key: "createdBy", value: .string("firebase-user"))])
        let values = try FirebaseProjectNoteImportParameters.make(result,
            reconciledCreatorPrincipalId: PrincipalID(validating: "target-principal"))
        #expect(values.p_original_creator_id == "firebase-user")
        #expect(values.p_created_by_principal_id == "target-principal")
        #expect(try FirebaseProjectNoteImportParameters.make(result).p_created_by_principal_id == nil)
    }

    @Test("Canonical Unicode equivalence cannot conceal altered source text")
    func forgedProjection() throws {
        let result = try mapped([], text: "e\u{0301}")
        guard case .mapped(let source, let account, let project, let note, let fields) = result else {
            Issue.record("Expected mapping"); return
        }
        let forged = FirebaseProjectNoteResult.mapped(source: source, accountId: account,
            projectId: project, noteId: note, fields: .init(text: "\u{00e9}", source: fields.source,
                createdBy: fields.createdBy, createdByName: fields.createdByName,
                createdAt: fields.createdAt, updatedAt: fields.updatedAt))
        #expect(throws: FirebaseProjectNoteImportFailure.self) {
            try FirebaseProjectNoteImportParameters.make(forged)
        }
    }

    @Test("Unsupported historical values are not silently repaired to fit target reads")
    func unsupportedValues() throws {
        for result in [try mapped([], text: " \n"), try mapped([], channel: "MCP-original/channel"),
                       try mapped([.init(key: "createdByName", value: .string(" "))])] {
            #expect(throws: FirebaseProjectNoteImportFailure.self) {
                try FirebaseProjectNoteImportParameters.make(result)
            }
        }
    }

    private func mapped(_ extra: [FirebaseSourceMapEntry], text: String = "original note",
                        channel: String = "mcp") throws -> FirebaseProjectNoteResult {
        let fields = extra + [.init(key: "text", value: .string(text)), .init(key: "source", value: .string(channel))]
        let source = FirebaseSourceDocument(accountScopeID: "source-account",
            documentPathSegments: ["accounts", "source-account", "projects", "source-project", "notes", "source-note"],
            entityCode: "project_note", evidenceKind: .record,
            fields: .map(fields.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }),
            sourceRecordID: "source-evidence")
        return try FirebaseProjectNoteConversion.convert(source,
            sourceAccountID: "source-account", sourceProjectID: "source-project", sourceNoteID: "source-note",
            targetAccountID: AccountID(validating: "target-account"), targetProjectID: ProjectID(validating: "target-project"),
            targetNoteID: ProjectNoteID(validating: "target-note"))
    }
}
