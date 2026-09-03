import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Detail Header Presentation Contracts")
struct ProjectDetailHeaderPresentationTests {
    @Test("Waiting, found, incomplete, and authoritative absence preserve exact local truth")
    func localTruthProjection() throws {
        let request = try Self.request()
        for readiness in [ListReadiness.notRequested, .loading, .blocked] {
            let presentation = try Self.project(
                ProjectCoreDetailsUpdate(request: request, state: .waiting(readiness)),
                request: request
            )
            #expect(presentation.state == .waiting(readiness))
            #expect(presentation.state.content == nil)
            #expect(presentation.state.isBlocked == (readiness == .blocked))
        }

        let ready = try Self.local([Self.row()])
        let partial = try Self.local(
            [Self.row(clientLifecycle: .archived)],
            complete: false,
            quality: .partial,
            version: "partial"
        )
        let stale = try Self.local(
            [Self.row(projectLifecycle: .archived)],
            complete: false,
            quality: .stale,
            version: "stale"
        )
        let found = try [ready, partial, stale].map { local in
            try Self.project(
                ProjectCoreDetailsUpdate(request: request, state: .snapshot(local)),
                request: request
            )
        }
        #expect(found.map(\.state.content?.readiness) == [.ready, .partial, .stale])
        #expect(found.map(\.state.content?.sourceQuality) == [.ready, .partial, .stale])
        #expect(found[0].state.content?.projectDisplayName.rawValue == "Project")
        #expect(found[0].state.content?.clientDisplayName.rawValue == "Client")
        #expect(found[1].state.content?.projectLifecycle == .active)
        #expect(found[1].state.content?.clientLifecycle == .archived)
        #expect(found[2].state.content?.projectLifecycle == .archived)
        #expect(found[2].state.content?.clientLifecycle == .active)
        #expect(found.map(\.state.content?.localDataVersion.rawValue) == ["ready", "partial", "stale"])

        let absence = try Self.project(
            ProjectCoreDetailsUpdate(
                request: request,
                state: .snapshot(Self.local([], version: "absent"))
            ),
            request: request
        )
        #expect(absence.state == .authoritativeAbsence)
        #expect(absence.state.content == nil)

        let emptyStates = try [
            Self.local([], complete: false, quality: .ready, version: "ready-incomplete"),
            Self.local([], complete: false, quality: .partial, version: "partial-empty"),
            Self.local([], complete: false, quality: .stale, version: "stale-empty")
        ].map {
            try Self.project(
                ProjectCoreDetailsUpdate(request: request, state: .snapshot($0)),
                request: request
            ).state
        }
        #expect(emptyStates == [.incomplete(.ready), .incomplete(.partial), .incomplete(.stale)])
        #expect(emptyStates.allSatisfy { $0.content == nil })
    }

    @Test("Unavailable, retryable, and required-update failures remain distinct and safe")
    func failureTruthAndCachedStaleness() throws {
        let request = try Self.request()
        let cachedReady = try Self.local([Self.row()], version: "cached-ready")
        let cachedPartial = try Self.local(
            [Self.row(clientLifecycle: .archived)],
            complete: false,
            quality: .partial,
            version: "cached-partial"
        )
        let unavailable = try Self.project(
            ProjectCoreDetailsUpdate(
                request: request,
                state: .failed(failure: .unavailable, cached: nil)
            ),
            request: request
        )
        let retryableCached = try Self.project(
            ProjectCoreDetailsUpdate(
                request: request,
                state: .failed(failure: .retryable, cached: cachedReady)
            ),
            request: request
        )
        let requiredCached = try Self.project(
            ProjectCoreDetailsUpdate(
                request: request,
                state: .failed(failure: .requiredUpdate, cached: cachedPartial)
            ),
            request: request
        )
        let retryableNoCache = try Self.project(
            ProjectCoreDetailsUpdate(
                request: request,
                state: .failed(failure: .retryable, cached: nil)
            ),
            request: request
        )
        let requiredNoCache = try Self.project(
            ProjectCoreDetailsUpdate(
                request: request,
                state: .failed(failure: .requiredUpdate, cached: nil)
            ),
            request: request
        )

        #expect(unavailable.state == .unavailable)
        #expect(unavailable.state.content == nil && unavailable.state.isBlocked)
        #expect(retryableCached.state.content?.readiness == .stale)
        #expect(retryableCached.state.content?.sourceQuality == .ready)
        #expect(retryableCached.state.content?.localDataVersion.rawValue == "cached-ready")
        #expect(requiredCached.state.content?.readiness == .stale)
        #expect(requiredCached.state.content?.sourceQuality == .partial)
        #expect(requiredCached.state.content?.clientLifecycle == .archived)
        #expect(retryableCached.state != requiredCached.state)
        #expect(!retryableCached.state.isBlocked && !requiredCached.state.isBlocked)
        #expect(retryableNoCache.state == .retryable(cached: nil))
        #expect(requiredNoCache.state == .requiredUpdate(cached: nil))
        #expect(retryableNoCache.state.content == nil && retryableNoCache.state.isBlocked)
        #expect(requiredNoCache.state.content == nil && requiredNoCache.state.isBlocked)

        let cachedEmpty = try Self.local([], complete: false, version: "cached-empty")
        let retryableEmpty = try Self.project(
            ProjectCoreDetailsUpdate(
                request: request,
                state: .failed(failure: .retryable, cached: cachedEmpty)
            ),
            request: request
        )
        #expect(retryableEmpty.state == .retryable(cached: nil))
        #expect(retryableEmpty.state.isBlocked)
    }

    @Test("Directory selection validates current evidence before exact detail projection")
    func endToEndSelectionAndMalformedRefusal() throws {
        let project = try Self.projectSummary(
            project: "project-one",
            projectName: "Selected Project",
            client: "client-one",
            clientName: "Selected Client",
            clientLifecycle: .archived
        )
        let directory = try Self.directory([project])
        let selection = try directory.selection(projectId: project.id)
        let request = try selection.detailRequest(validating: directory)
        let local = try Self.local(
            [Self.row(
                projectName: "Selected Project",
                clientName: "Selected Client",
                clientLifecycle: .archived
            )],
            request: request
        )
        let update = try ProjectCoreDetailsUpdate(request: request, state: .snapshot(local))
        let header = try Self.project(update, request: request)

        #expect(header.request == request)
        #expect(header.state.content?.projectId == selection.row.projectId)
        #expect(header.state.content?.clientId == selection.row.clientId)
        #expect(header.state.content?.projectDisplayName == selection.row.projectDisplayName)
        #expect(header.state.content?.clientDisplayName == selection.row.clientDisplayName)
        #expect(header.state.content?.clientLifecycle == .archived)

        let changedDirectory = try Self.directory([
            Self.projectSummary(
                project: "project-one",
                projectName: "Renamed Project",
                client: "client-one",
                clientName: "Selected Client",
                clientLifecycle: .archived
            )
        ], version: "changed")
        #expect(Self.directoryFailure {
            try selection.detailRequest(validating: changedDirectory)
        } == .selectionSnapshotMismatch)

        let otherRequest = try Self.request(project: "other-project")
        #expect(Self.headerFailure {
            try Self.project(update, request: otherRequest)
        } == .updateRequestMismatch)
        #expect(throws: ProjectCoreDetailsFailure.updateRequestMismatch) {
            try ProjectCoreDetailsUpdate(request: otherRequest, state: .snapshot(local))
        }
        #expect(throws: ProjectCoreDetailsFailure.updateRequestMismatch) {
            try ProjectCoreDetailsUpdate(
                request: otherRequest,
                state: .failed(failure: .retryable, cached: local)
            )
        }

        let bytes = try OperationContractCodec.encode(update)
        let rebound = try Self.mutate(bytes) { root in
            var request = root["request"] as! [String: Any]
            request["projectId"] = "other-project"
            root["request"] = request
        }
        #expect(Self.coreFailure(rebound) == .requestFingerprintMismatch)
        let malformed = Data("{".utf8)
        #expect(throws: (any Error).self) {
            try OperationContractCodec.decode(ProjectCoreDetailsUpdate.self, from: malformed)
        }

        let diagnostics: [(ProjectDetailHeaderPresentationFailure, String)] = [
            (.updateRequestMismatch, "project_detail_header_update_request_mismatch"),
            (.invalidEncodedPresentation, "project_detail_header_encoding_invalid")
        ]
        for (failure, code) in diagnostics {
            #expect(failure.diagnosticCode == code)
            #expect(code.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" })
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_802_400_000)
    private static let t1 = Date(timeIntervalSince1970: 1_802_400_001)

    private static func request(
        account: String = "project-account",
        project: String = "project-one"
    ) throws -> ProjectCoreDetailsRequest {
        try ProjectCoreDetailsRequest(
            accountId: AccountID(validating: account),
            projectId: ProjectID(validating: project)
        )
    }

    private static func projectSummary(
        account: String = "project-account",
        project: String = "project-one",
        projectName: String = "Project",
        client: String = "client-one",
        clientName: String = "Client",
        projectLifecycle: DirectoryLifecycleState = .active,
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
            id: ProjectID(validating: project),
            accountId: accountId,
            clientId: clientId,
            client: client,
            displayName: ProjectDisplayName(validating: projectName),
            description: nil,
            lifecycle: projectLifecycle
        )
    }

    private static func row(
        projectName: String = "Project",
        clientName: String = "Client",
        projectLifecycle: DirectoryLifecycleState = .active,
        clientLifecycle: DirectoryLifecycleState = .active
    ) throws -> ProjectCoreDetailsSnapshot {
        try ProjectCoreDetailsSnapshot(
            project: projectSummary(
                projectName: projectName,
                clientName: clientName,
                projectLifecycle: projectLifecycle,
                clientLifecycle: clientLifecycle
            ),
            locallyObservedRevision: ExpectedProjectRevision(7)
        )
    }

    private static func local(
        _ rows: [ProjectCoreDetailsSnapshot],
        request: ProjectCoreDetailsRequest? = nil,
        complete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        version: String = "ready"
    ) throws -> ProjectCoreDetailsLocalSnapshot {
        let request = try request ?? Self.request()
        return try ProjectCoreDetailsLocalSnapshot(
            request: request,
            rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: t1
        )
    }

    private static func directory(
        _ rows: [ProjectSummary],
        version: String = "directory"
    ) throws -> ProjectDirectoryPresentation {
        let local = try ListLocalSnapshot(
            queryFingerprint: ListQueryFingerprint(validating: String(repeating: "1", count: 64)),
            rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: true,
            quality: ListSnapshotQuality.ready,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: t1
        )
        let snapshot = try ProjectListSnapshot(
            accountId: AccountID(validating: "project-account"),
            local: local
        )
        return try ProjectDirectoryPresentationProjector.project(snapshot, segment: .active)
    }

    private static func project(
        _ update: ProjectCoreDetailsUpdate,
        request: ProjectCoreDetailsRequest
    ) throws -> ProjectDetailHeaderPresentation {
        try ProjectDetailHeaderPresentationProjector.project(update, validating: request)
    }

    private static func directoryFailure<Value>(
        _ body: () throws -> Value
    ) -> ProjectDirectoryPresentationFailure? {
        do { _ = try body(); return nil }
        catch let failure as ProjectDirectoryPresentationFailure { return failure }
        catch { return nil }
    }

    private static func headerFailure<Value>(
        _ body: () throws -> Value
    ) -> ProjectDetailHeaderPresentationFailure? {
        do { _ = try body(); return nil }
        catch let failure as ProjectDetailHeaderPresentationFailure { return failure }
        catch { return nil }
    }

    private static func coreFailure(_ bytes: Data) -> ProjectCoreDetailsFailure? {
        do {
            _ = try OperationContractCodec.decode(ProjectCoreDetailsUpdate.self, from: bytes)
            return nil
        } catch let failure as ProjectCoreDetailsFailure {
            return failure
        } catch {
            return nil
        }
    }

    private static func mutate(
        _ bytes: Data,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        body(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}
