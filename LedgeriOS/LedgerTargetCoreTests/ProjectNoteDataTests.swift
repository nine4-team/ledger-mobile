import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Note Read Contracts")
struct ProjectNoteDataTests {
    @Test("Stable notes preserve visible, edited, tombstone, and ordered page truth")
    func noteAndPageShapeIsExact() throws {
        let fixture = try Self.fixture()
        let rows = fixture.complete.local.rows

        #expect(fixture.complete.request.accountId == fixture.accountId)
        #expect(fixture.complete.request.projectId == fixture.projectId)
        #expect(fixture.complete.request.pageSize == 3)
        #expect(fixture.complete.local.queryFingerprint == fixture.complete.request.queryFingerprint)
        #expect(fixture.complete.local.visibleRowCountBeforeFiltering == 3)
        #expect(fixture.complete.isCompleteForProjectHistory)
        #expect(fixture.complete.nextCursor == nil)
        #expect(rows.map(\.id.rawValue) == ["note-z", "note-b", "note-a"])

        if case .tombstone(let deletion) = rows[0].content {
            #expect(deletion.deletedByPrincipalId == fixture.editorId)
            #expect(deletion.deletedAt == Self.t4)
        } else {
            Issue.record("Expected explicit tombstone evidence")
        }
        if case .visible(let text) = rows[1].content {
            #expect(text.rawValue == "Confirm the revised delivery window.")
            #expect(rows[1].lastEditedByPrincipalId == fixture.editorId)
            #expect(rows[1].lastEditedAt == Self.t3)
            #expect(rows[1].revision == 8)
        } else {
            Issue.record("Expected visible note content")
        }

        let bounded = try Self.page(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            rows: Array(rows.prefix(2)),
            pageSize: 2,
            localComplete: true,
            quality: .ready,
            historyComplete: false,
            includeNextCursor: true,
            version: "project-note-bounded",
            asOf: Self.t5
        )
        #expect(bounded.local.isCompleteForQuery)
        #expect(!bounded.isCompleteForProjectHistory)
        #expect(bounded.nextCursor?.noteId == rows[1].id)
        #expect(bounded.nextCursor?.createdAt == rows[1].createdAt)

        let tombstoneBytes = try OperationContractCodec.encode(rows[0])
        let tombstoneText = String(decoding: tombstoneBytes, as: UTF8.self).lowercased()
        #expect(!tombstoneText.contains("removed private prose"))
        for forbidden in [
            "firebase", "firestore", "supabase", "powersync", "https://", "file://",
            "bearer", "secret", "service_account", "collection/", "select *"
        ] {
            #expect(!tombstoneText.contains(forbidden))
        }
    }

    @Test("Complete, partial, stale, cursor, and tombstone evidence survives restart")
    func localHistoryEvidenceSurvivesRestart() throws {
        let fixture = try Self.fixture()
        let rows = fixture.complete.local.rows
        let firstBoundary = try ProjectNoteCursor(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            createdAt: rows[0].createdAt,
            noteId: rows[0].id
        )
        let partial = try Self.page(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            rows: Array(rows.dropFirst()),
            pageSize: 2,
            after: firstBoundary,
            localComplete: false,
            quality: .partial,
            historyComplete: false,
            includeNextCursor: false,
            version: "project-note-partial",
            asOf: Self.t5
        )
        let stale = try Self.page(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            rows: [rows[1]],
            pageSize: 2,
            localComplete: false,
            quality: .stale,
            historyComplete: false,
            includeNextCursor: false,
            version: "project-note-stale",
            asOf: Self.t6
        )
        let authoritativeEmpty = try Self.page(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            rows: [],
            pageSize: 20,
            localComplete: true,
            quality: .ready,
            historyComplete: true,
            includeNextCursor: false,
            version: "project-note-empty",
            asOf: Self.t6
        )
        let restart = RestartFixture(
            complete: fixture.complete,
            partial: partial,
            stale: stale,
            authoritativeEmpty: authoritativeEmpty
        )

        let bytes = try OperationContractCodec.encode(restart)
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)

        #expect(restored == restart)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.complete.isCompleteForProjectHistory)
        #expect(restored.partial.local.quality == .partial)
        #expect(!restored.partial.local.isCompleteForQuery)
        #expect(!restored.partial.isCompleteForProjectHistory)
        #expect(restored.partial.request.after == firstBoundary)
        #expect(restored.stale.local.quality == .stale)
        #expect(restored.authoritativeEmpty.local.rows.isEmpty)
        #expect(restored.authoritativeEmpty.isCompleteForProjectHistory)
    }

    @Test("Malformed audit, scope, order, cursor, and readiness fail atomically")
    func invalidEvidenceFailsClosed() throws {
        let fixture = try Self.fixture()
        let rows = fixture.complete.local.rows

        #expect(Self.noteFailure { try ProjectNoteText(validating: " \n ") } == .invalidText)
        #expect(Self.noteFailure {
            try ProjectNoteCreatorDisplayName(validating: "   ")
        } == .invalidCreatorDisplayName)
        #expect(Self.noteFailure {
            try ProjectNoteSource(validating: "MCP-Agent")
        } == .invalidSource)
        #expect(Self.noteFailure {
            try ProjectNoteDeletionAudit(
                deletedByPrincipalId: fixture.editorId,
                deletedAt: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidAuditTime)
        #expect(Self.noteFailure {
            try Self.note(
                id: "note-unpaired-edit",
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                createdBy: fixture.creatorId,
                createdAt: Self.t1,
                text: "Unpaired edit",
                lastEditedBy: fixture.editorId,
                lastEditedAt: nil
            )
        } == .incompleteEditAudit)
        #expect(Self.noteFailure {
            try Self.note(
                id: "note-reversed-edit",
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                createdBy: fixture.creatorId,
                createdAt: Self.t2,
                text: "Reversed edit",
                lastEditedBy: fixture.editorId,
                lastEditedAt: Self.t1
            )
        } == .invalidAuditOrder)
        #expect(Self.noteFailure {
            try Self.note(
                id: "note-reversed-delete",
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                createdBy: fixture.creatorId,
                createdAt: Self.t2,
                text: nil,
                deletedBy: fixture.editorId,
                deletedAt: Self.t1
            )
        } == .invalidAuditOrder)
        #expect(Self.noteFailure {
            try ProjectNotePageRequest(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                pageSize: 0
            )
        } == .invalidPageSize)
        #expect(Self.noteFailure {
            try ProjectNotePageRequest(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                pageSize: 201
            )
        } == .invalidPageSize)

        let otherAccount = try AccountID(validating: "account-other")
        let otherProject = try ProjectID(validating: "project-other")
        let wrongCursor = try ProjectNoteCursor(
            accountId: otherAccount,
            projectId: fixture.projectId,
            createdAt: Self.t2,
            noteId: rows[0].id
        )
        #expect(Self.noteFailure {
            try ProjectNotePageRequest(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                pageSize: 20,
                after: wrongCursor
            )
        } == .cursorScopeMismatch)

        let crossScope = try Self.note(
            id: "note-cross-scope",
            accountId: otherAccount,
            projectId: otherProject,
            createdBy: fixture.creatorId,
            createdAt: Self.t0,
            text: "Wrong scope"
        )
        #expect(Self.noteFailure {
            try Self.page(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: [crossScope]
            )
        } == .noteScopeMismatch)
        #expect(Self.noteFailure {
            try Self.page(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: [rows[0], rows[0]]
            )
        } == .duplicateNoteIdentity)
        #expect(Self.noteFailure {
            try Self.page(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: [rows[2], rows[1]]
            )
        } == .invalidNoteOrder)
        #expect(Self.noteFailure {
            try Self.page(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: Array(rows.prefix(2)),
                pageSize: 1
            )
        } == .pageLimitExceeded)
        #expect(Self.noteFailure {
            try Self.page(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: Array(rows.prefix(2)),
                visibleCount: 3
            )
        } == .visibleCountMismatch)

        let request = try ProjectNotePageRequest(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            pageSize: 3
        )
        let otherRequest = try ProjectNotePageRequest(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            pageSize: 2
        )
        let mismatchedLocal = try ListLocalSnapshot(
            queryFingerprint: otherRequest.queryFingerprint,
            rows: Array(rows.prefix(2)),
            visibleRowCountBeforeFiltering: 2,
            isCompleteForQuery: true,
            quality: .ready,
            localDataVersion: try LocalDataVersion(validating: "project-note-mismatch"),
            asOf: Self.t5
        )
        #expect(Self.noteFailure {
            try ProjectNotePage(
                request: request,
                local: mismatchedLocal,
                isCompleteForProjectHistory: false,
                nextCursor: nil
            )
        } == .queryFingerprintMismatch)

        let incompleteLocal = try ListLocalSnapshot(
            queryFingerprint: request.queryFingerprint,
            rows: [rows[0]],
            visibleRowCountBeforeFiltering: 1,
            isCompleteForQuery: false,
            quality: .partial,
            localDataVersion: try LocalDataVersion(validating: "project-note-incomplete"),
            asOf: Self.t5
        )
        #expect(Self.noteFailure {
            try ProjectNotePage(
                request: request,
                local: incompleteLocal,
                isCompleteForProjectHistory: true,
                nextCursor: nil
            )
        } == .historyCompletenessMismatch)

        let wrongBoundary = try ProjectNoteCursor(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            createdAt: rows[0].createdAt,
            noteId: rows[0].id
        )
        #expect(Self.noteFailure {
            try Self.page(
                accountId: fixture.accountId,
                projectId: fixture.projectId,
                rows: Array(rows.prefix(2)),
                pageSize: 2,
                localComplete: true,
                quality: .ready,
                historyComplete: false,
                explicitNextCursor: wrongBoundary
            )
        } == .continuationBoundaryMismatch)

        #expect(Self.noteFailure {
            try OperationContractCodec.decode(
                ProjectNoteContentState.self,
                from: Data(#"{"kind":"visible","deletion":{"deletedAt":0,"deletedByPrincipalId":"principal"}}"#.utf8)
            )
        } == .invalidEncodedContentState)
        #expect(Self.noteFailure {
            try OperationContractCodec.decode(ProjectNoteSnapshot.self, from: Data("{}".utf8))
        } == .invalidEncodedNote)
        #expect(Self.noteFailure {
            try OperationContractCodec.decode(ProjectNoteCursor.self, from: Data("{}".utf8))
        } == .invalidEncodedCursor)
        #expect(Self.noteFailure {
            try OperationContractCodec.decode(ProjectNotePageRequest.self, from: Data("{}".utf8))
        } == .invalidEncodedRequest)
        #expect(Self.noteFailure {
            try OperationContractCodec.decode(ProjectNotePage.self, from: Data("{}".utf8))
        } == .invalidEncodedPage)

        let diagnostics: [(ProjectNoteDataFailure, String)] = [
            (.invalidText, "project_note_text_invalid"),
            (.invalidCreatorDisplayName, "project_note_creator_display_name_invalid"),
            (.invalidSource, "project_note_source_invalid"),
            (.invalidAuditTime, "project_note_audit_time_invalid"),
            (.incompleteEditAudit, "project_note_edit_audit_incomplete"),
            (.invalidAuditOrder, "project_note_audit_order_invalid"),
            (.invalidPageSize, "project_note_page_size_invalid"),
            (.cursorScopeMismatch, "project_note_cursor_scope_mismatch"),
            (.queryFingerprintMismatch, "project_note_query_fingerprint_mismatch"),
            (.noteScopeMismatch, "project_note_scope_mismatch"),
            (.duplicateNoteIdentity, "project_note_identity_duplicate"),
            (.invalidNoteOrder, "project_note_order_invalid"),
            (.pageLimitExceeded, "project_note_page_limit_exceeded"),
            (.visibleCountMismatch, "project_note_visible_count_mismatch"),
            (.historyCompletenessMismatch, "project_note_history_completeness_mismatch"),
            (.continuationBoundaryMismatch, "project_note_continuation_boundary_mismatch"),
            (.requestMismatch, "project_note_request_mismatch"),
            (.localReadFailed, "project_note_local_read_failed"),
            (.invalidEncodedContentState, "project_note_content_state_encoding_invalid"),
            (.invalidEncodedNote, "project_note_encoding_invalid"),
            (.invalidEncodedCursor, "project_note_cursor_encoding_invalid"),
            (.invalidEncodedRequest, "project_note_request_encoding_invalid"),
            (.invalidEncodedPage, "project_note_page_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
        }
    }

    @Test("The read port returns only the exact typed Project-note request")
    func readPortIsScopeExactAndFailureSafe() async throws {
        let fixture = try Self.fixture()
        let port = FixtureProjectNotePort(page: fixture.complete)
        var received: [ProjectNotePage] = []
        for try await page in port.watchNotes(fixture.complete.request) {
            received.append(page)
        }
        #expect(received == [fixture.complete])

        let mismatched = try ProjectNotePageRequest(
            accountId: fixture.accountId,
            projectId: fixture.projectId,
            pageSize: 2
        )
        var mismatchedPages: [ProjectNotePage] = []
        var requestFailure: ProjectNoteDataFailure?
        do {
            for try await page in port.watchNotes(mismatched) {
                mismatchedPages.append(page)
            }
        } catch let failure as ProjectNoteDataFailure {
            requestFailure = failure
        }
        #expect(mismatchedPages.isEmpty)
        #expect(requestFailure == .requestMismatch)

        var falsePages: [ProjectNotePage] = []
        var localFailure: ProjectNoteDataFailure?
        do {
            for try await page in FailingProjectNotePort().watchNotes(
                fixture.complete.request
            ) {
                falsePages.append(page)
            }
        } catch let failure as ProjectNoteDataFailure {
            localFailure = failure
        }
        #expect(falsePages.isEmpty)
        #expect(localFailure == .localReadFailed)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_801_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_801_000_001)
    private static let t2 = Date(timeIntervalSince1970: 1_801_000_002)
    private static let t3 = Date(timeIntervalSince1970: 1_801_000_003)
    private static let t4 = Date(timeIntervalSince1970: 1_801_000_004)
    private static let t5 = Date(timeIntervalSince1970: 1_801_000_005)
    private static let t6 = Date(timeIntervalSince1970: 1_801_000_006)

    private struct Fixture {
        let accountId: AccountID
        let projectId: ProjectID
        let creatorId: PrincipalID
        let editorId: PrincipalID
        let complete: ProjectNotePage
    }

    private struct RestartFixture: Codable, Equatable, Sendable {
        let complete: ProjectNotePage
        let partial: ProjectNotePage
        let stale: ProjectNotePage
        let authoritativeEmpty: ProjectNotePage
    }

    private static func fixture() throws -> Fixture {
        let accountId = try AccountID(validating: "account-project-note-test")
        let projectId = try ProjectID(validating: "project-note-test")
        let creatorId = try PrincipalID(validating: "principal-note-creator")
        let editorId = try PrincipalID(validating: "principal-note-editor")
        let rows = [
            try note(
                id: "note-z",
                accountId: accountId,
                projectId: projectId,
                createdBy: creatorId,
                createdAt: t2,
                text: nil,
                source: "mcp",
                revision: 3,
                lastEditedBy: editorId,
                lastEditedAt: t3,
                deletedBy: editorId,
                deletedAt: t4
            ),
            try note(
                id: "note-b",
                accountId: accountId,
                projectId: projectId,
                createdBy: creatorId,
                createdAt: t1,
                text: "Confirm the revised delivery window.",
                revision: 8,
                lastEditedBy: editorId,
                lastEditedAt: t3
            ),
            try note(
                id: "note-a",
                accountId: accountId,
                projectId: projectId,
                createdBy: creatorId,
                createdAt: t1,
                text: "Record the original hardware selection."
            )
        ]
        return Fixture(
            accountId: accountId,
            projectId: projectId,
            creatorId: creatorId,
            editorId: editorId,
            complete: try page(
                accountId: accountId,
                projectId: projectId,
                rows: rows,
                pageSize: 3,
                localComplete: true,
                quality: .ready,
                historyComplete: true,
                includeNextCursor: false,
                version: "project-note-complete",
                asOf: t5
            )
        )
    }

    private static func note(
        id: String,
        accountId: AccountID,
        projectId: ProjectID,
        createdBy: PrincipalID,
        createdAt: Date,
        text: String?,
        source: String = "text",
        revision: UInt64 = 1,
        lastEditedBy: PrincipalID? = nil,
        lastEditedAt: Date? = nil,
        deletedBy: PrincipalID? = nil,
        deletedAt: Date? = nil
    ) throws -> ProjectNoteSnapshot {
        let content: ProjectNoteContentState
        if let text {
            content = .visible(try ProjectNoteText(validating: text))
        } else {
            content = .tombstone(try ProjectNoteDeletionAudit(
                deletedByPrincipalId: deletedBy ?? createdBy,
                deletedAt: deletedAt ?? createdAt
            ))
        }
        return try ProjectNoteSnapshot(
            id: ProjectNoteID(validating: id),
            accountId: accountId,
            projectId: projectId,
            content: content,
            source: ProjectNoteSource(validating: source),
            createdByPrincipalId: createdBy,
            creatorDisplayName: try ProjectNoteCreatorDisplayName(validating: "Jordan Lee"),
            createdAt: createdAt,
            revision: revision,
            lastEditedByPrincipalId: lastEditedBy,
            lastEditedAt: lastEditedAt
        )
    }

    private static func page(
        accountId: AccountID,
        projectId: ProjectID,
        rows: [ProjectNoteSnapshot],
        pageSize: UInt16 = 20,
        after: ProjectNoteCursor? = nil,
        localComplete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        historyComplete: Bool = false,
        includeNextCursor: Bool = false,
        explicitNextCursor: ProjectNoteCursor? = nil,
        visibleCount: Int? = nil,
        version: String = "project-note-test",
        asOf: Date = t5
    ) throws -> ProjectNotePage {
        let request = try ProjectNotePageRequest(
            accountId: accountId,
            projectId: projectId,
            pageSize: pageSize,
            after: after
        )
        let local = try ListLocalSnapshot(
            queryFingerprint: request.queryFingerprint,
            rows: rows,
            visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
            isCompleteForQuery: localComplete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: asOf
        )
        let derivedNext: ProjectNoteCursor?
        if includeNextCursor, let last = rows.last {
            derivedNext = try ProjectNoteCursor(
                accountId: accountId,
                projectId: projectId,
                createdAt: last.createdAt,
                noteId: last.id
            )
        } else {
            derivedNext = explicitNextCursor
        }
        return try ProjectNotePage(
            request: request,
            local: local,
            isCompleteForProjectHistory: historyComplete,
            nextCursor: derivedNext
        )
    }

    private static func noteFailure<T>(_ operation: () throws -> T) -> ProjectNoteDataFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as ProjectNoteDataFailure {
            return failure
        } catch {
            return nil
        }
    }
}

private struct FixtureProjectNotePort: ProjectNoteQuerying {
    let page: ProjectNotePage

    func watchNotes(
        _ request: ProjectNotePageRequest
    ) -> AsyncThrowingStream<ProjectNotePage, Error> {
        AsyncThrowingStream { continuation in
            guard request == page.request else {
                continuation.finish(throwing: ProjectNoteDataFailure.requestMismatch)
                return
            }
            continuation.yield(page)
            continuation.finish()
        }
    }
}

private struct FailingProjectNotePort: ProjectNoteQuerying {
    func watchNotes(
        _: ProjectNotePageRequest
    ) -> AsyncThrowingStream<ProjectNotePage, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ProjectNoteDataFailure.localReadFailed)
        }
    }
}
