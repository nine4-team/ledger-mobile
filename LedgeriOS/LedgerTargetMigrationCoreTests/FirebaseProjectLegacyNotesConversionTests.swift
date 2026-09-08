import Testing
import LedgerTargetCore
@testable import LedgerTargetMigrationCore

@Suite("Legacy Project note source preservation")
struct FirebaseProjectLegacyNotesConversionTests {
    @Test("Exact legacy text and full source evidence remain separate from description and individual notes")
    func exactSource() throws {
        for value: FirebaseSourceValue? in [nil, .null, .string(""), .string("  First\r\n第二行\t ")] {
            let source = Self.source(notes: value)
            let result = try Self.convert(source)
            guard case .mapped(let retained, let account, let project, let notes) = result else {
                Issue.record("Expected mapping"); continue
            }
            #expect(retained == source)
            #expect(account.rawValue == "target-account")
            #expect(project.rawValue == "target-project")
            if case .string(let expected)? = value { #expect(notes == expected) }
            else { #expect(notes == nil) }
            #expect(try Self.convert(source) == result) // deterministic replay, no note allocation
        }
    }

    @Test("Wrong scope, nontext and NUL remain unresolved with original evidence intact")
    func refusesLossyConversion() throws {
        for value: FirebaseSourceValue in [.integer("1"), .string("before\0after"), .array([])] {
            let source = Self.source(notes: value)
            #expect(try Self.convert(source) == .unresolved(source: source, reason: .unsupportedNotesValue))
        }
        let source = Self.source(notes: .string("Notes"))
        #expect(try FirebaseProjectLegacyNotesConversion.convert(source,
            sourceAccountID: "foreign", sourceProjectID: "source-project",
            targetAccountID: AccountID(validating: "target-account"),
            targetProjectID: ProjectID(validating: "target-project"))
            == .unresolved(source: source, reason: .sourceScopeMismatch))
    }

    private static func convert(_ source: FirebaseSourceDocument) throws -> FirebaseProjectLegacyNotesResult {
        try FirebaseProjectLegacyNotesConversion.convert(source,
            sourceAccountID: "source-account", sourceProjectID: "source-project",
            targetAccountID: AccountID(validating: "target-account"),
            targetProjectID: ProjectID(validating: "target-project"))
    }

    private static func source(notes: FirebaseSourceValue?) -> FirebaseSourceDocument {
        var fields = [FirebaseSourceMapEntry(key: "description", value: .string("Distinct description"))]
        if let notes { fields.append(FirebaseSourceMapEntry(key: "notes", value: notes)) }
        return FirebaseSourceDocument(accountScopeID: "source-account",
            documentPathSegments: ["accounts", "source-account", "projects", "source-project"],
            entityCode: "project", evidenceKind: .record, fields: .map(fields), sourceRecordID: "project-source")
    }
}
