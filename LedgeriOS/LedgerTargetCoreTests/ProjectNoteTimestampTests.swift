import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Exact note timestamps")
struct ProjectNoteTimestampTests {
    @Test("Exact timestamps survive encoding at nanosecond and calendar boundaries")
    func exactValues() throws {
        for (seconds, nanos): (Int64, Int32) in [(-62_135_596_800, 0), (-1, 999_999_999),
            (0, 0), (1_700_000_000, 123_456_789), (253_402_300_799, 999_999_999)] {
            let value = try ProjectNoteTimestamp(secondsSince1970: seconds, nanoseconds: nanos)
            #expect(try OperationContractCodec.decode(ProjectNoteTimestamp.self,
                from: OperationContractCodec.encode(value)) == value)
        }
        for (seconds, nanos): (Int64, Int32) in [(-62_135_596_801, 0), (253_402_300_800, 0), (0, -1), (0, 1_000_000_000)] {
            #expect(throws: ProjectNoteDataFailure.invalidAuditTime) {
                try ProjectNoteTimestamp(secondsSince1970: seconds, nanoseconds: nanos)
            }
        }
        let preEpoch = try ProjectNoteTimestamp(legacyMillisecondsDate: Date(timeIntervalSince1970: -0.001))
        #expect(preEpoch.secondsSince1970 == -1 && preEpoch.nanoseconds == 999_000_000)
        for date in [Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: 1_700_000_000.000123)] {
            #expect(throws: ProjectNoteDataFailure.invalidAuditTime) {
                try ProjectNoteTimestamp(legacyMillisecondsDate: date)
            }
        }
    }

    @Test("Date-equal projections cannot collapse chronology or cursor boundaries")
    func exactOrdering() throws {
        let early = try ProjectNoteTimestamp(secondsSince1970: 1_700_000_000, nanoseconds: 1)
        let late = try ProjectNoteTimestamp(secondsSince1970: 1_700_000_000, nanoseconds: 2)
        #expect(early.date == late.date)
        #expect(early < late)
        let first = try note("a", created: late)
        let second = try note("z", created: early)
        let unknown = try note("unknown", created: nil)
        _ = try page([first, second, unknown])
        #expect(throws: ProjectNoteDataFailure.invalidNoteOrder) { try page([second, first]) }
        #expect(throws: ProjectNoteDataFailure.invalidAuditOrder) {
            try note("wrong-edit", created: late, edited: early)
        }
        let wrong = ProjectNoteCursor(accountId: first.accountId, projectId: first.projectId,
            createdTimestamp: early, noteId: first.id)
        #expect(throws: ProjectNoteDataFailure.continuationBoundaryMismatch) {
            try page([first], next: wrong)
        }
        let boundary = ProjectNoteCursor(accountId: first.accountId, projectId: first.projectId,
            createdTimestamp: late, noteId: first.id)
        #expect(wrong != boundary)
        let result = try page([second, unknown], after: boundary)
        #expect(try OperationContractCodec.decode(ProjectNotePage.self, from: OperationContractCodec.encode(result)) == result)
        let deletion = ProjectNoteDeletionAudit(deletedByPrincipalId: try PrincipalID(validating: "actor"), deletedTimestamp: early)
        #expect(throws: ProjectNoteDataFailure.invalidAuditOrder) {
            try note("wrong-delete", created: late, content: .tombstone(deletion))
        }
    }

    @Test("Legacy Date JSON decodes explicitly and dual timestamp authorities are rejected")
    func legacyAndConflicts() throws {
        let legacy = Data(#"{"id":"note","accountId":"account","projectId":"project","content":{"kind":"visible","text":"Original"},"source":"text","createdAt":1700000000123,"lastEditedAt":1700000001123,"revision":0}"#.utf8)
        let decoded = try OperationContractCodec.decode(ProjectNoteSnapshot.self, from: legacy)
        #expect(try decoded.createdTimestamp == ProjectNoteTimestamp(secondsSince1970: 1_700_000_000, nanoseconds: 123_000_000))
        let encoded = try OperationContractCodec.encode(decoded)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(json["createdAt"] == nil && json["lastEditedAt"] == nil)
        #expect(json["createdTimestamp"] != nil && json["lastEditedTimestamp"] != nil)
        for key in ["createdAt", "lastEditedAt"] {
            var dual = json
            dual[key] = NSNull()
            #expect(throws: ProjectNoteDataFailure.invalidAuditTime) {
                try OperationContractCodec.decode(ProjectNoteSnapshot.self, from: JSONSerialization.data(withJSONObject: dual))
            }
        }
        let cursor = Data(#"{"accountId":"account","projectId":"project","noteId":"note","createdAt":-1}"#.utf8)
        let decodedCursor = try OperationContractCodec.decode(ProjectNoteCursor.self, from: cursor)
        #expect(try decodedCursor.createdTimestamp == ProjectNoteTimestamp(secondsSince1970: -1, nanoseconds: 999_000_000))
        let deletion = Data(#"{"deletedByPrincipalId":"actor","deletedAt":1000}"#.utf8)
        #expect(try OperationContractCodec.decode(ProjectNoteDeletionAudit.self, from: deletion).deletedTimestamp
            == ProjectNoteTimestamp(secondsSince1970: 1, nanoseconds: 0))
        for dual in [
            #"{"accountId":"account","projectId":"project","noteId":"note","createdAt":null,"createdTimestamp":null}"#,
            #"{"deletedByPrincipalId":"actor","deletedAt":1000,"deletedTimestamp":{"secondsSince1970":1,"nanoseconds":0}}"#
        ] {
            if dual.contains("deleted") {
                #expect(throws: ProjectNoteDataFailure.invalidAuditTime) { try OperationContractCodec.decode(ProjectNoteDeletionAudit.self, from: Data(dual.utf8)) }
            } else {
                #expect(throws: ProjectNoteDataFailure.invalidAuditTime) { try OperationContractCodec.decode(ProjectNoteCursor.self, from: Data(dual.utf8)) }
            }
        }
    }

    private func note(_ id: String, created: ProjectNoteTimestamp?, edited: ProjectNoteTimestamp? = nil,
        content: ProjectNoteContentState? = nil) throws -> ProjectNoteSnapshot {
        try ProjectNoteSnapshot(id: ProjectNoteID(validating: id), accountId: AccountID(validating: "account"),
            projectId: ProjectID(validating: "project"), content: content ?? .visible(ProjectNoteText(validating: "Original")),
            source: ProjectNoteSource(validating: "text"), createdByPrincipalId: nil, creatorDisplayName: nil,
            createdTimestamp: created, revision: 0, lastEditedTimestamp: edited)
    }

    private func page(_ rows: [ProjectNoteSnapshot], after: ProjectNoteCursor? = nil,
        next: ProjectNoteCursor? = nil) throws -> ProjectNotePage {
        let request = try ProjectNotePageRequest(accountId: AccountID(validating: "account"),
            projectId: ProjectID(validating: "project"), pageSize: 20, after: after)
        let local = try ListLocalSnapshot(queryFingerprint: request.queryFingerprint, rows: rows,
            visibleRowCountBeforeFiltering: rows.count, isCompleteForQuery: true, quality: .ready,
            localDataVersion: LocalDataVersion(validating: "exact-notes"), asOf: Date(timeIntervalSince1970: 1_700_000_001))
        return try ProjectNotePage(request: request, local: local, isCompleteForProjectHistory: false, nextCursor: next)
    }
}
