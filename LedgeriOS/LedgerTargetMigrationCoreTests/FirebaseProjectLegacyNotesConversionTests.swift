import Foundation
import Testing
import LedgerTargetCore
@testable import LedgerTargetMigrationCore

@Suite("Legacy Project note source preservation")
struct FirebaseProjectLegacyNotesConversionTests {
    @Test("Import parameters retain source bytes and encode SQL null explicitly")
    func importParameters() throws {
        let absent = try FirebaseProjectLegacyNotesImportParameters.make(Self.convert(Self.source(notes: nil)))
        let explicitNull = try FirebaseProjectLegacyNotesImportParameters.make(Self.convert(Self.source(notes: .null)))
        #expect(absent.p_notes == nil && explicitNull.p_notes == nil)
        #expect(absent.p_source_bytes != explicitNull.p_source_bytes)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(absent)) as! [String: Any]
        #expect(encoded["p_notes"] is NSNull)
        #expect(encoded["p_account_id"] as? String == "target-account")
        #expect(encoded["p_project_id"] as? String == "target-project")
        #expect(encoded.count == 6)

        let text = "  Original\n第二行\r\n"
        let source = Self.source(notes: .string(text))
        let params = try FirebaseProjectLegacyNotesImportParameters.make(Self.convert(source))
        #expect(params.p_notes == text)
        #expect(params.p_source_account == "source-account")
        #expect(params.p_source_document == "source-project")
        #expect(params.p_source_bytes == "\\x" + (try source.canonicalEvidenceData()).map { String(format: "%02x", $0) }.joined())
        #expect(try FirebaseProjectLegacyNotesImportParameters.make(Self.convert(source)) == params)
    }

    @Test("Unresolved or forged mapped text cannot become import parameters")
    func invalidImportParameters() throws {
        let source = Self.source(notes: .integer("1"))
        #expect(throws: FirebaseProjectLegacyNotesImportFailure.self) {
            try FirebaseProjectLegacyNotesImportParameters.make(Self.convert(source))
        }
        let valid = Self.source(notes: .string("Original"))
        let forged = try FirebaseProjectLegacyNotesResult.mapped(source: valid,
            accountId: AccountID(validating: "target-account"),
            projectId: ProjectID(validating: "target-project"), notes: "Changed")
        #expect(throws: FirebaseProjectLegacyNotesImportFailure.self) {
            try FirebaseProjectLegacyNotesImportParameters.make(forged)
        }
        let unicodeForged = try FirebaseProjectLegacyNotesResult.mapped(source: Self.source(notes: .string("\u{00e9}")),
            accountId: AccountID(validating: "target-account"),
            projectId: ProjectID(validating: "target-project"), notes: "e\u{0301}")
        #expect(throws: FirebaseProjectLegacyNotesImportFailure.self) {
            try FirebaseProjectLegacyNotesImportParameters.make(unicodeForged)
        }
    }

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
