import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Rejected operation recovery contracts")
struct RejectedOperationRecoveryTests {
    @Test("Exact request scope and contract bind every candidate")
    func exactScopeAndContract() throws {
        let command = try Self.command(id: "operation-rejected")
        let candidate = try Self.candidate(command: command)
        let request = try Self.request()
        #expect(try candidate.validating(request: request) == candidate)

        let wrongContract = try Self.request(contract: "space-checklist-revision-v2")
        #expect(throws: RejectedOperationRecoveryFailure.invalidCandidate) {
            _ = try candidate.validating(request: wrongContract)
        }
        let wrongPrincipal = try RejectedOperationRecoveryRequest(
            accountId: Self.accountId,
            actorPrincipalId: PrincipalID(validating: "another-principal"),
            family: .reviseSpaceChecklists,
            expectedContractVersion: Self.contractVersion,
            subject: command.subject
        )
        #expect(throws: RejectedOperationRecoveryFailure.invalidCandidate) {
            _ = try candidate.validating(request: wrongPrincipal)
        }
    }

    @Test("Multiple recoveries are unique and deterministically newest first")
    func deterministicOrdering() throws {
        let older = try Self.candidate(
            command: Self.command(id: "operation-older"),
            acceptedAt: Self.t0,
            rejectedAt: Self.t2
        )
        let newerA = try Self.candidate(
            command: Self.command(id: "operation-a"),
            acceptedAt: Self.t1,
            rejectedAt: Self.t3
        )
        let newerB = try Self.candidate(
            command: Self.command(id: "operation-b"),
            acceptedAt: Self.t1,
            rejectedAt: Self.t3
        )
        let snapshot = try RejectedOperationRecoverySnapshot(
            request: Self.request(),
            candidates: [older, newerB, newerA]
        )
        #expect(snapshot.candidates.map(\.operationId.rawValue) == [
            "operation-a", "operation-b", "operation-older"
        ])
        #expect(throws: RejectedOperationRecoveryFailure.duplicateCandidate) {
            _ = try RejectedOperationRecoverySnapshot(
                request: Self.request(),
                candidates: [older, older]
            )
        }
    }

    @Test("Family-specific subject and terminal clocks fail closed")
    func invalidRequestAndCandidate() throws {
        #expect(throws: RejectedOperationRecoveryFailure.invalidRequest) {
            _ = try RejectedOperationRecoveryRequest(
                accountId: Self.accountId,
                actorPrincipalId: Self.principalId,
                family: .reviseSpaceChecklists,
                expectedContractVersion: Self.contractVersion,
                subject: LedgerEntityReference(
                    kind: .project,
                    id: try EntityID(validating: "project-one")
                )
            )
        }
        #expect(throws: RejectedOperationRecoveryFailure.invalidCandidate) {
            _ = try Self.candidate(
                command: Self.command(id: "operation-invalid-time"),
                acceptedAt: Self.t2,
                rejectedAt: Self.t1
            )
        }
    }

    private static let accountId = try! AccountID(validating: "account-one")
    private static let principalId = try! PrincipalID(validating: "principal-one")
    private static let spaceId = try! SpaceID(validating: "space-one")
    private static let contractVersion = try! OperationContractVersion(
        validating: "space-checklist-revision-v1"
    )
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let t1 = t0.addingTimeInterval(1)
    private static let t2 = t0.addingTimeInterval(2)
    private static let t3 = t0.addingTimeInterval(3)

    private static func request(
        contract: String = "space-checklist-revision-v1"
    ) throws -> RejectedOperationRecoveryRequest {
        try RejectedOperationRecoveryRequest(
            accountId: accountId,
            actorPrincipalId: principalId,
            family: .reviseSpaceChecklists,
            expectedContractVersion: OperationContractVersion(validating: contract),
            subject: LedgerEntityReference(
                kind: .space,
                id: EntityID(validating: spaceId.rawValue)
            )
        )
    }

    private static func command(id: String) throws -> ReviseSpaceChecklistsCommand {
        try ReviseSpaceChecklistsCommand(
            operationId: OperationID(validating: id),
            draft: SpaceChecklistRevisionDraft(
                accountId: accountId,
                actorPrincipalId: principalId,
                operationContractVersion: contractVersion,
                spaceId: spaceId,
                collection: SpaceChecklistCollection(checklists: []),
                expectedRevision: ExpectedSpaceRevision(7),
                capturedAt: t0
            )
        )
    }

    private static func candidate(
        command: ReviseSpaceChecklistsCommand,
        acceptedAt: Date = t0,
        rejectedAt: Date = t2
    ) throws -> RejectedOperationRecoveryCandidate {
        try RejectedOperationRecoveryCandidate(
            command: .reviseSpaceChecklists(command),
            acceptedAt: acceptedAt,
            updatedAt: rejectedAt,
            rejection: OperationRejection(
                error: ApplicationErrorSummary(
                    code: ApplicationErrorCode(
                        validating: "space_checklist_revision_conflict"
                    ),
                    category: .conflict,
                    retryDisposition: .afterUserCorrection
                ),
                rejectedAt: rejectedAt,
                conflictingEntities: [command.subject]
            )
        )
    }
}
