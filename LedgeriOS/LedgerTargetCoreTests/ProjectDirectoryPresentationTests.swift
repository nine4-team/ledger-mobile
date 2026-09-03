import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Directory Presentation Contracts")
struct ProjectDirectoryPresentationTests {
    @Test("Segments use only Project lifecycle and preserve exact upstream identity and order")
    func lifecycleProjectionAndOrder() throws {
        let projects = try [
            Self.project("archived-z", name: "Same", lifecycle: .archived),
            Self.project(
                "active-b",
                name: "Same",
                client: "client-b",
                clientName: "  Current Client  ",
                clientLifecycle: .archived
            ),
            Self.project("active-a", name: "Same", client: "client-a"),
            Self.project("archived-a", name: "Archived", lifecycle: .archived)
        ]
        let source = try Self.snapshot(projects, visibleCount: 6)
        let active = try ProjectDirectoryPresentationProjector.project(source, segment: .active)
        let archived = try ProjectDirectoryPresentationProjector.project(source, segment: .archived)

        #expect(active.rows.map(\.projectId) == [projects[1].id, projects[2].id])
        #expect(archived.rows.map(\.projectId) == [projects[0].id, projects[3].id])
        #expect(active.rows[0].projectDisplayName.rawValue == "Same")
        #expect(active.rows[0].clientId == projects[1].clientId)
        #expect(active.rows[0].clientDisplayName.rawValue == "  Current Client  ")
        #expect(active.rows[0].projectLifecycle == .active)
        #expect(active.rows[0].clientLifecycle == .archived)
        #expect(active.sourceDirectoryRowCount == 4)
        #expect(active.visibleRowCountBeforeFiltering == 6)
        #expect(!active.isSourceExhaustive)
        #expect(!active.isAuthoritativeEmpty)
        #expect(active.readiness == .ready)
        #expect(active.rows[0].projectId != active.rows[1].projectId)
    }

    @Test("Empty authority requires ready complete source-exhaustive evidence")
    func emptyAndOfflineTruth() throws {
        let archived = try Self.project("archived", lifecycle: .archived)
        let authoritative = try Self.presentation([archived], segment: .active)
        let nonexhaustive = try Self.presentation(
            [archived], segment: .active, visibleCount: 2
        )
        let incomplete = try Self.presentation(
            [archived], segment: .active, complete: false
        )
        let partialEmpty = try Self.presentation(
            [archived], segment: .active, complete: false, quality: .partial
        )
        let staleEmpty = try Self.presentation(
            [archived], segment: .active, complete: false, quality: .stale
        )

        #expect(authoritative.rows.isEmpty && authoritative.isAuthoritativeEmpty)
        #expect(authoritative.isSourceExhaustive)
        #expect(!nonexhaustive.isAuthoritativeEmpty && !nonexhaustive.isSourceExhaustive)
        #expect(!incomplete.isAuthoritativeEmpty)
        #expect(!partialEmpty.isAuthoritativeEmpty && partialEmpty.readiness == .partial)
        #expect(!staleEmpty.isAuthoritativeEmpty && staleEmpty.readiness == .stale)

        let active = try Self.project("active")
        let partialFound = try Self.presentation(
            [active], segment: .active, complete: false, quality: .partial
        )
        let staleFound = try Self.presentation(
            [active], segment: .active, complete: false, quality: .stale
        )
        #expect(try partialFound.selection(projectId: active.id).row.projectId == active.id)
        #expect(try staleFound.selection(projectId: active.id).row.projectId == active.id)
        #expect(!partialFound.isAuthoritativeEmpty && !staleFound.isAuthoritativeEmpty)

        #expect(throws: ListQueryContractFailure.incompleteAuthoritativeEmpty) {
            try Self.snapshot([active], complete: true, quality: .partial)
        }
        #expect(Self.failure {
            try Self.presentation(
                [active],
                segment: .active,
                asOf: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidAsOf)
    }

    @Test("Directory and selection restart canonically while every frozen field is bound")
    func restartAndTamperRefusal() throws {
        let projects = try [
            Self.project("active-a", name: "  Project A  ", clientName: "Client A"),
            Self.project("active-b", name: "Project B", client: "client-b")
        ]
        let presentation = try Self.presentation(
            projects,
            segment: .active,
            visibleCount: 3,
            complete: false,
            quality: .stale,
            version: "project-directory-v9",
            asOf: Self.t2,
            sourceHash: String(repeating: "2", count: 64)
        )
        let selection = try presentation.selection(projectId: projects[1].id)
        let fixture = RestartFixture(presentation: presentation, selection: selection)
        let bytes = try OperationContractCodec.encode(fixture)
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)

        #expect(restored == fixture)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.presentation.rows.map(\.projectId) == projects.map(\.id))
        #expect(restored.presentation.sourceDirectoryRowCount == 2)
        #expect(restored.presentation.visibleRowCountBeforeFiltering == 3)
        #expect(restored.presentation.localDataVersion.rawValue == "project-directory-v9")
        #expect(restored.presentation.asOf == Self.t2)
        #expect(restored.selection.directoryEvidenceFingerprint == presentation.evidenceFingerprint)

        let presentationBytes = try OperationContractCodec.encode(presentation)
        let account = try Self.mutate(presentationBytes) { $0["accountId"] = "other-account" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, account) == .evidenceFingerprintMismatch)
        let segment = try Self.mutate(presentationBytes) { $0["segment"] = "archived" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, segment) == .segmentLifecycleMismatch)
        let source = try Self.mutate(presentationBytes) {
            $0["sourceDirectoryFingerprint"] = String(repeating: "3", count: 64)
        }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, source) == .evidenceFingerprintMismatch)
        let sourceCount = try Self.mutate(presentationBytes) { $0["sourceDirectoryRowCount"] = 3 }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, sourceCount) == .evidenceFingerprintMismatch)
        let visibleCount = try Self.mutate(presentationBytes) { $0["visibleRowCountBeforeFiltering"] = 4 }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, visibleCount) == .evidenceFingerprintMismatch)
        let completeness = try Self.mutate(presentationBytes) { $0["isCompleteForQuery"] = true }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, completeness) == .invalidCompleteness)
        let quality = try Self.mutate(presentationBytes) { $0["quality"] = "partial" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, quality) == .evidenceFingerprintMismatch)
        let version = try Self.mutate(presentationBytes) { $0["localDataVersion"] = "changed" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, version) == .evidenceFingerprintMismatch)
        let time = try Self.mutate(presentationBytes) {
            $0["asOf"] = ($0["asOf"] as! NSNumber).doubleValue + 1_000
        }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, time) == .evidenceFingerprintMismatch)
        let order = try Self.mutateRows(presentationBytes) { $0.swapAt(0, 1) }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, order) == .evidenceFingerprintMismatch)
        let projectId = try Self.mutateRow(presentationBytes, at: 0) { $0["projectId"] = "changed" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, projectId) == .evidenceFingerprintMismatch)
        let projectName = try Self.mutateRow(presentationBytes, at: 0) { $0["projectDisplayName"] = "Changed" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, projectName) == .evidenceFingerprintMismatch)
        let clientId = try Self.mutateRow(presentationBytes, at: 0) { $0["clientId"] = "changed-client" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, clientId) == .evidenceFingerprintMismatch)
        let clientName = try Self.mutateRow(presentationBytes, at: 0) { $0["clientDisplayName"] = "Changed" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, clientName) == .evidenceFingerprintMismatch)
        let clientLifecycle = try Self.mutateRow(presentationBytes, at: 0) { $0["clientLifecycle"] = "archived" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, clientLifecycle) == .evidenceFingerprintMismatch)
        let projectLifecycle = try Self.mutateRow(presentationBytes, at: 0) { $0["projectLifecycle"] = "archived" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, projectLifecycle) == .segmentLifecycleMismatch)
        let fingerprint = try Self.mutate(presentationBytes) {
            $0["evidenceFingerprint"] = String(repeating: "a", count: 64)
        }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, fingerprint) == .evidenceFingerprintMismatch)
        let malformedFingerprint = try Self.mutate(presentationBytes) { $0["evidenceFingerprint"] = "bad" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, malformedFingerprint) == .invalidEvidenceFingerprint)
        let missing = try Self.mutate(presentationBytes) { $0.removeValue(forKey: "rows") }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, missing) == .invalidEncodedPresentation)
        let unknown = try Self.mutate(presentationBytes) { $0["route"] = "project" }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, unknown) == .invalidEncodedPresentation)
        let unknownRow = try Self.mutateRow(presentationBytes, at: 0) { $0["budget"] = 1 }
        #expect(Self.decodeFailure(ProjectDirectoryPresentation.self, unknownRow) == .invalidEncodedRow)

        let selectionBytes = try OperationContractCodec.encode(selection)
        let selectionAccount = try Self.mutate(selectionBytes) { $0["accountId"] = "other-account" }
        let reboundAccount = try OperationContractCodec.decode(
            ProjectBrowsingSelection.self,
            from: selectionAccount
        )
        #expect(Self.failure {
            try reboundAccount.detailRequest(validating: presentation)
        } == .selectionSnapshotMismatch)
        let selectionRow = try Self.mutate(selectionBytes) { root in
            var row = root["row"] as! [String: Any]
            row["clientDisplayName"] = "Different"
            root["row"] = row
        }
        let reboundRow = try OperationContractCodec.decode(
            ProjectBrowsingSelection.self,
            from: selectionRow
        )
        #expect(Self.failure {
            try reboundRow.detailRequest(validating: presentation)
        } == .selectionSnapshotMismatch)
        let selectionEvidence = try Self.mutate(selectionBytes) {
            $0["directoryEvidenceFingerprint"] = String(repeating: "b", count: 64)
        }
        let reboundEvidence = try OperationContractCodec.decode(
            ProjectBrowsingSelection.self,
            from: selectionEvidence
        )
        #expect(Self.failure {
            try reboundEvidence.detailRequest(validating: presentation)
        } == .selectionSnapshotMismatch)
        let selectionSegment = try Self.mutate(selectionBytes) { $0["segment"] = "archived" }
        #expect(Self.decodeFailure(ProjectBrowsingSelection.self, selectionSegment) == .segmentLifecycleMismatch)
        let selectionMissing = try Self.mutate(selectionBytes) { $0.removeValue(forKey: "row") }
        #expect(Self.decodeFailure(ProjectBrowsingSelection.self, selectionMissing) == .invalidEncodedSelection)
        let selectionUnknown = try Self.mutate(selectionBytes) { $0["route"] = "project" }
        #expect(Self.decodeFailure(ProjectBrowsingSelection.self, selectionUnknown) == .invalidEncodedSelection)
        let malformedSelection = Data("{".utf8)
        #expect(throws: (any Error).self) {
            try OperationContractCodec.decode(ProjectBrowsingSelection.self, from: malformedSelection)
        }
    }

    @Test("Selection derives only an exact request after validating current evidence")
    func exactSelectionAndRequestDerivation() throws {
        let first = try Self.project("project-a", name: "Same", clientName: "Same Client")
        let second = try Self.project(
            "project-b", name: "Same", client: "client-b", clientName: "Same Client"
        )
        let archived = try Self.project("project-c", lifecycle: .archived)
        let current = try Self.presentation([first, second, archived], segment: .active)
        let archivedPresentation = try Self.presentation(
            [first, second, archived], segment: .archived
        )
        let selection = try current.selection(projectId: second.id)
        let request = try selection.detailRequest(validating: current)

        #expect(selection.row.projectId == second.id)
        #expect(selection.row.clientId == second.clientId)
        #expect(request.accountId == current.accountId)
        #expect(request.projectId == second.id)
        #expect(Self.failure {
            try current.selection(projectId: archived.id)
        } == .projectNotSelectable)
        #expect(Self.failure {
            try archivedPresentation.selection(projectId: second.id)
        } == .projectNotSelectable)
        #expect(Self.failure {
            try current.selection(projectId: ProjectID(validating: "unknown"))
        } == .projectNotSelectable)

        let wrongAccount = try Self.presentation(
            [Self.project("project-b", account: "other-account", client: "client-b")],
            account: "other-account",
            segment: .active
        )
        let changedName = try Self.presentation([
            first,
            Self.project("project-b", name: "Changed", client: "client-b"),
            archived
        ], segment: .active, version: "changed-name")
        let changedOrder = try Self.presentation(
            [second, first, archived], segment: .active, version: "changed-order"
        )
        let removed = try Self.presentation([first, archived], segment: .active, version: "removed")
        for changed in [wrongAccount, changedName, changedOrder, removed, archivedPresentation] {
            #expect(Self.failure {
                try selection.detailRequest(validating: changed)
            } == .selectionSnapshotMismatch)
        }

        let root = try #require(JSONSerialization.jsonObject(
            with: OperationContractCodec.encode(selection)
        ) as? [String: Any])
        #expect(Set(root.keys) == [
            "accountId", "segment", "row", "directoryEvidenceFingerprint"
        ])
        let text = String(decoding: try OperationContractCodec.encode(selection), as: UTF8.self)
            .lowercased()
        for forbidden in [
            "route", "principal", "authorized", "permission", "tab", "budget",
            "hero", "image", "firebase", "supabase", "powersync", "sql", "path"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_300_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_300_001)
    private static let t2 = Date(timeIntervalSince1970: 1_802_300_002)

    private struct RestartFixture: Codable, Equatable, Sendable {
        let presentation: ProjectDirectoryPresentation
        let selection: ProjectBrowsingSelection
    }

    private static func project(
        _ id: String,
        account: String = "project-account",
        name: String = "Project",
        client: String = "client",
        clientName: String = "Client",
        lifecycle: DirectoryLifecycleState = .active,
        clientLifecycle: DirectoryLifecycleState = .active
    ) throws -> ProjectSummary {
        let accountId = try AccountID(validating: account)
        let clientId = try ClientID(validating: client)
        let client = try ClientSummary(
            id: clientId,
            accountId: accountId,
            displayName: ClientDisplayName(validating: clientName),
            lifecycle: clientLifecycle,
            createdAt: t0,
            updatedAt: t1
        )
        return try ProjectSummary(
            id: ProjectID(validating: id),
            accountId: accountId,
            clientId: clientId,
            client: client,
            displayName: ProjectDisplayName(validating: name),
            description: nil,
            lifecycle: lifecycle
        )
    }

    private static func snapshot(
        _ rows: [ProjectSummary],
        account: String = "project-account",
        visibleCount: Int? = nil,
        complete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        version: String = "project-directory-v1",
        asOf: Date = t1,
        sourceHash: String = String(repeating: "1", count: 64)
    ) throws -> ProjectListSnapshot {
        let local = try ListLocalSnapshot(
            queryFingerprint: ListQueryFingerprint(validating: sourceHash),
            rows: rows,
            visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: asOf
        )
        return try ProjectListSnapshot(
            accountId: AccountID(validating: account),
            local: local
        )
    }

    private static func presentation(
        _ rows: [ProjectSummary],
        account: String = "project-account",
        segment: ProjectDirectorySegment,
        visibleCount: Int? = nil,
        complete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        version: String = "project-directory-v1",
        asOf: Date = t1,
        sourceHash: String = String(repeating: "1", count: 64)
    ) throws -> ProjectDirectoryPresentation {
        try ProjectDirectoryPresentationProjector.project(
            snapshot(
                rows,
                account: account,
                visibleCount: visibleCount,
                complete: complete,
                quality: quality,
                version: version,
                asOf: asOf,
                sourceHash: sourceHash
            ),
            segment: segment
        )
    }

    private static func failure<Value>(
        _ body: () throws -> Value
    ) -> ProjectDirectoryPresentationFailure? {
        do { _ = try body(); return nil }
        catch let failure as ProjectDirectoryPresentationFailure { return failure }
        catch { return nil }
    }

    private static func decodeFailure<Value: Decodable>(
        _ type: Value.Type,
        _ bytes: Data
    ) -> ProjectDirectoryPresentationFailure? {
        failure { try OperationContractCodec.decode(type, from: bytes) }
    }

    private static func mutate(
        _ bytes: Data,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        body(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func mutateRows(
        _ bytes: Data,
        _ body: (inout [[String: Any]]) -> Void
    ) throws -> Data {
        try mutate(bytes) { root in
            var rows = root["rows"] as! [[String: Any]]
            body(&rows)
            root["rows"] = rows
        }
    }

    private static func mutateRow(
        _ bytes: Data,
        at index: Int,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        try mutateRows(bytes) { rows in body(&rows[index]) }
    }
}
