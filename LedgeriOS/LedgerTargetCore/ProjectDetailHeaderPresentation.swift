import Foundation

public enum ProjectDetailHeaderPresentationFailure: Error, Equatable, Sendable {
    case updateRequestMismatch
    case invalidEncodedPresentation

    public var diagnosticCode: String {
        switch self {
        case .updateRequestMismatch: "project_detail_header_update_request_mismatch"
        case .invalidEncodedPresentation: "project_detail_header_encoding_invalid"
        }
    }
}

public struct ProjectDetailHeaderContent: Equatable, Sendable {
    public let projectId: ProjectID
    public let projectDisplayName: ProjectDisplayName
    public let clientId: ClientID
    public let clientDisplayName: ClientDisplayName
    public let projectLifecycle: DirectoryLifecycleState
    public let clientLifecycle: DirectoryLifecycleState
    public let sourceQuality: ListSnapshotQuality
    public let readiness: ListReadiness
    public let localDataVersion: LocalDataVersion
    public let asOf: Date

    fileprivate init(
        snapshot: ProjectCoreDetailsLocalSnapshot,
        row: ProjectCoreDetailsSnapshot,
        displayedReadiness: ListReadiness
    ) {
        let project = row.project
        projectId = project.id
        projectDisplayName = project.displayName
        clientId = project.clientId
        clientDisplayName = project.client.displayName
        projectLifecycle = project.lifecycle
        clientLifecycle = project.client.lifecycle
        sourceQuality = snapshot.local.quality
        readiness = displayedReadiness
        localDataVersion = snapshot.local.localDataVersion
        asOf = snapshot.local.asOf
    }
}

public enum ProjectDetailHeaderPresentationState: Equatable, Sendable {
    case waiting(ListReadiness)
    case found(ProjectDetailHeaderContent)
    case incomplete(ListReadiness)
    case authoritativeAbsence
    case unavailable
    case retryable(cached: ProjectDetailHeaderContent?)
    case requiredUpdate(cached: ProjectDetailHeaderContent?)

    public var content: ProjectDetailHeaderContent? {
        switch self {
        case .found(let content), .retryable(cached: .some(let content)),
             .requiredUpdate(cached: .some(let content)):
            content
        case .waiting, .incomplete, .authoritativeAbsence, .unavailable,
             .retryable(cached: .none), .requiredUpdate(cached: .none):
            nil
        }
    }

    public var isBlocked: Bool {
        switch self {
        case .waiting(.blocked), .unavailable,
             .retryable(cached: .none), .requiredUpdate(cached: .none):
            true
        case .waiting, .found, .incomplete, .authoritativeAbsence,
             .retryable(cached: .some), .requiredUpdate(cached: .some):
            false
        }
    }
}

public struct ProjectDetailHeaderPresentation: Equatable, Sendable {
    public let request: ProjectCoreDetailsRequest
    public let state: ProjectDetailHeaderPresentationState

    fileprivate init(
        request: ProjectCoreDetailsRequest,
        state: ProjectDetailHeaderPresentationState
    ) {
        self.request = request
        self.state = state
    }
}

public enum ProjectDetailHeaderPresentationProjector {
    public static func project(
        _ update: ProjectCoreDetailsUpdate,
        validating request: ProjectCoreDetailsRequest
    ) throws -> ProjectDetailHeaderPresentation {
        do {
            let validated = try update.validating(request: request)
            let state: ProjectDetailHeaderPresentationState
            switch validated.state {
            case .waiting(let readiness):
                state = .waiting(readiness)
            case .snapshot(let snapshot):
                if let row = snapshot.row {
                    state = .found(ProjectDetailHeaderContent(
                        snapshot: snapshot,
                        row: row,
                        displayedReadiness: snapshot.local.quality.readiness
                    ))
                } else if snapshot.isAuthoritativeAbsence {
                    state = .authoritativeAbsence
                } else {
                    state = .incomplete(snapshot.local.quality.readiness)
                }
            case .failed(.unavailable, _):
                state = .unavailable
            case .failed(.retryable, let cached):
                state = .retryable(cached: staleContent(cached))
            case .failed(.requiredUpdate, let cached):
                state = .requiredUpdate(cached: staleContent(cached))
            }
            return ProjectDetailHeaderPresentation(request: request, state: state)
        } catch ProjectCoreDetailsFailure.updateRequestMismatch {
            throw ProjectDetailHeaderPresentationFailure.updateRequestMismatch
        } catch let failure as ProjectCoreDetailsFailure {
            throw failure
        } catch {
            throw ProjectDetailHeaderPresentationFailure.invalidEncodedPresentation
        }
    }

    private static func staleContent(
        _ cached: ProjectCoreDetailsLocalSnapshot?
    ) -> ProjectDetailHeaderContent? {
        guard let cached, let row = cached.row else { return nil }
        return ProjectDetailHeaderContent(
            snapshot: cached,
            row: row,
            displayedReadiness: .stale
        )
    }
}
