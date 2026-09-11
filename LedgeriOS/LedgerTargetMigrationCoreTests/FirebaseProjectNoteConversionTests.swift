import Testing
import LedgerTargetCore
@testable import LedgerTargetMigrationCore

@Suite("Individual Project note source preservation")
struct FirebaseProjectNoteConversionTests {
    @Test("Preserves exact source metadata, submillisecond times and unknown evidence")
    func exactFacts() throws {
        let text = "  e\u{0301}\r\n第二行\t\u{0001} " + String(repeating: "x", count: 16_385)
        let entries: [FirebaseSourceMapEntry] = [
            .init(key: "text", value: .string(text)),
            .init(key: "source", value: .string("MCP-original/channel")),
            .init(key: "createdBy", value: .string("mcp-agent")),
            .init(key: "createdByName", value: .string("  AI Assistant  ")),
            .init(key: "createdAt", value: .timestamp(seconds: "1700000000", nanoseconds: 123_456_789)),
            .init(key: "updatedAt", value: .timestamp(seconds: "1700000001", nanoseconds: 987_654_321)),
            .init(key: "extra", value: .map([.init(key: "unknown", value: .integer("42"))]))
        ]
        let source = Self.document(entries)
        let result = try Self.convert(source)
        guard case .mapped(let retained, let account, let project, let note, let fields) = result else {
            Issue.record("Expected source facts"); return
        }
        #expect(try retained.canonicalEvidenceData() == source.canonicalEvidenceData())
        #expect(account.rawValue == "target-account" && project.rawValue == "target-project")
        #expect(note.rawValue == "target-note")
        #expect(fields.text?.utf8.elementsEqual(text.utf8) == true)
        #expect(fields.source == "MCP-original/channel")
        #expect(fields.createdBy == "mcp-agent")
        #expect(fields.createdByName == "  AI Assistant  ")
        #expect(fields.createdAt == .timestamp(seconds: "1700000000", nanoseconds: 123_456_789))
        #expect(fields.updatedAt == .timestamp(seconds: "1700000001", nanoseconds: 987_654_321))
        #expect(try Self.convert(source) == result)
    }

    @Test("Missing, null and empty values gain no creator, source or date defaults")
    func optionalFacts() throws {
        let absent = Self.document([])
        let null = Self.document(["text", "source", "createdBy", "createdByName", "createdAt", "updatedAt"]
            .map { .init(key: $0, value: .null) })
        #expect(try absent.canonicalEvidenceData() != null.canonicalEvidenceData())
        for source in [absent, null] {
            guard case .mapped(let retained, _, _, _, let fields) = try Self.convert(source) else {
                Issue.record("Expected optional facts"); continue
            }
            #expect(try retained.canonicalEvidenceData() == source.canonicalEvidenceData())
            #expect(fields.text == nil && fields.source == nil && fields.createdBy == nil)
            #expect(fields.createdByName == nil && fields.createdAt == nil && fields.updatedAt == nil)
        }
        let empty = Self.document(["text", "source", "createdBy", "createdByName"]
            .map { .init(key: $0, value: .string("")) })
        guard case .mapped(_, _, _, _, let fields) = try Self.convert(empty) else {
            Issue.record("Expected empty source strings"); return
        }
        #expect(fields.text == "" && fields.source == "" && fields.createdBy == "" && fields.createdByName == "")
    }

    @Test("An update timestamp does not invent a creation time or editor")
    func updateOnly() throws {
        let source = Self.document([.init(key: "updatedAt", value: .timestamp(seconds: "-1", nanoseconds: 999_999_999))])
        guard case .mapped(_, _, _, _, let fields) = try Self.convert(source) else {
            Issue.record("Expected historical timestamp"); return
        }
        #expect(fields.createdAt == nil && fields.createdBy == nil)
        #expect(fields.updatedAt == .timestamp(seconds: "-1", nanoseconds: 999_999_999))
    }

    @Test("Wrongly typed known values remain unresolved with complete evidence")
    func typedFailures() throws {
        for key in ["text", "source", "createdBy", "createdByName", "createdAt", "updatedAt"] {
            let source = Self.document([.init(key: key, value: .integer("1"))])
            #expect(try Self.convert(source) == .unresolved(source: source, reason: .unsupportedField(key)))
        }
        for key in ["text", "source", "createdBy", "createdByName"] {
            let source = Self.document([.init(key: key, value: .string("before\0after"))])
            #expect(try Self.convert(source) == .unresolved(source: source, reason: .unsupportedField(key)))
        }
        let malformed = Self.document([.init(key: "createdAt", value: .timestamp(seconds: "1", nanoseconds: 1_000_000_000))])
        #expect(try Self.convert(malformed) == .unresolved(source: malformed, reason: .invalidSourceDocument))
    }

    @Test("Only the exact six-segment reconciled scope can map")
    func scopeFailures() throws {
        for path in [
            ["accounts", "source-account", "projects", "source-project"],
            ["accounts", "source-account", "projects", "source-project", "other", "source-note"],
            ["accounts", "source-account", "projects", "source-project", "notes", ".."]
        ] {
            let source = Self.document([], path: path)
            #expect(try Self.convert(source) == .unresolved(source: source, reason: .invalidSourceDocument))
        }
        for index in [1, 3, 5] {
            var path = Self.path
            path[index] = "foreign"
            let source = Self.document([], path: path)
            #expect(try Self.convert(source) == .unresolved(source: source, reason: .sourceScopeMismatch))
        }
        for key in ["accountId", "projectId"] {
            for value: FirebaseSourceValue in [.null, .string("foreign")] {
                let source = Self.document([.init(key: key, value: value)])
                #expect(try Self.convert(source) == .unresolved(source: source, reason: .sourceScopeMismatch))
            }
        }
        let source = Self.document([], account: "foreign")
        #expect(try Self.convert(source) == .unresolved(source: source, reason: .sourceScopeMismatch))
    }

    @Test("Canonically equivalent source identities must not cross the byte-exact scope boundary")
    func unicodeScope() throws {
        var path = Self.path
        path[5] = "e\u{0301}"
        let source = Self.document([], path: path)
        let result = try FirebaseProjectNoteConversion.convert(source,
            sourceAccountID: "source-account", sourceProjectID: "source-project", sourceNoteID: "\u{00e9}",
            targetAccountID: AccountID(validating: "target-account"), targetProjectID: ProjectID(validating: "target-project"),
            targetNoteID: ProjectNoteID(validating: "target-note"))
        #expect(result == .unresolved(source: source, reason: .sourceScopeMismatch))
    }

    private static let path = ["accounts", "source-account", "projects", "source-project", "notes", "source-note"]

    private static func document(_ fields: [FirebaseSourceMapEntry], path: [String] = path,
                                 account: String = "source-account") -> FirebaseSourceDocument {
        FirebaseSourceDocument(accountScopeID: account, documentPathSegments: path,
            entityCode: "project_note", evidenceKind: .record,
            fields: .map(fields.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }),
            sourceRecordID: "source-note-evidence")
    }

    private static func convert(_ source: FirebaseSourceDocument) throws -> FirebaseProjectNoteResult {
        try FirebaseProjectNoteConversion.convert(source,
            sourceAccountID: "source-account", sourceProjectID: "source-project", sourceNoteID: "source-note",
            targetAccountID: AccountID(validating: "target-account"), targetProjectID: ProjectID(validating: "target-project"),
            targetNoteID: ProjectNoteID(validating: "target-note"))
    }
}
