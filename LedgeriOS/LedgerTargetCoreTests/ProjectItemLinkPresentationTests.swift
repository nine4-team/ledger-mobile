import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Item Link Presentation Contracts")
struct ProjectItemLinkPresentationTests {
    @Test("Exact accounting labels and Link payer meanings project without ordering policy")
    func exactVocabularyAndChoiceMembership() throws {
        let fixture = try Self.fixture(isComplete: true)
        let sections = ProjectItemLinkPresentationProjector.sections(
            from: fixture.snapshot
        )

        #expect(sections.map(\.kind) == [.unaccountedFor, .accountedFor])
        #expect(sections.map(\.title) == [
            "Unaccounted For Items",
            "Accounted For Items"
        ])

        let descriptor = try ProjectItemLinkPresentationProjector.linkDescriptor(
            for: fixture.snapshot.rows[0]
        )
        #expect(descriptor.actionTitle == "Link")
        #expect(descriptor.question == "Who paid for this Item?")
        #expect(Set(ProjectItemLinkPayerChoice.allCases) == [
            .clientPaid,
            .businessPaid
        ])
        #expect(descriptor.payerChoices == [.clientPaid, .businessPaid])
        #expect(Set(descriptor.payerChoices.map(\.label)) == [
            "Client paid",
            "Business paid"
        ])
    }

    @Test("Accounted and incomplete relationship evidence fail closed")
    func unavailableStatesAndForbiddenVocabulary() throws {
        let complete = try Self.fixture(isComplete: true).snapshot
        #expect(Self.failure {
            try ProjectItemLinkPresentationProjector.linkDescriptor(
                for: complete.rows[1]
            )
        } == .unavailableForAccountedItem)

        let incomplete = try Self.fixture(isComplete: false).snapshot
        #expect(incomplete.rows[0].resolution == .relationshipEvidenceIncomplete)
        #expect(Self.failure {
            try ProjectItemLinkPresentationProjector.linkDescriptor(
                for: incomplete.rows[0]
            )
        } == .relationshipEvidenceIncomplete)

        let publicText = Set(
            ProjectItemLinkPresentationProjector.sections(from: complete).map(\.title) +
                ProjectItemLinkPayerChoice.all.map(\.label) +
                ["Link", "Who paid for this Item?"]
        )
        for forbidden in [
            "Not sure yet",
            "Sell from Business Inventory",
            "Assign Item",
            "Needs Assignment",
            "Linked Items",
            "Unlinked Items"
        ] {
            #expect(!publicText.contains(forbidden))
        }
        #expect(
            ProjectItemLinkPresentationFailure.unavailableForAccountedItem
                .diagnosticCode == "project_item_link_unavailable_accounted"
        )
        #expect(
            ProjectItemLinkPresentationFailure.relationshipEvidenceIncomplete
                .diagnosticCode == "project_item_link_relationship_evidence_incomplete"
        )
    }

    @Test("Dismissal and restart re-project without persisted presentation state")
    func dismissalAndRestartAreStateless() throws {
        let fixture = try Self.fixture(isComplete: true)
        let beforeBytes = try OperationContractCodec.encode(fixture.snapshot)
        let beforeDescriptor = try ProjectItemLinkPresentationProjector.linkDescriptor(
            for: fixture.snapshot.rows[0]
        )

        #expect(beforeDescriptor.dismiss() == .noAction)
        #expect(try OperationContractCodec.encode(fixture.snapshot) == beforeBytes)

        let restored = try OperationContractCodec.decode(
            ProjectItemAccountingSectionsSnapshot.self,
            from: beforeBytes
        )
        let afterDescriptor = try ProjectItemLinkPresentationProjector.linkDescriptor(
            for: restored.rows[0]
        )
        #expect(afterDescriptor == beforeDescriptor)
        #expect(
            ProjectItemLinkPresentationProjector.sections(from: restored) ==
                ProjectItemLinkPresentationProjector.sections(from: fixture.snapshot)
        )
        #expect(try OperationContractCodec.encode(restored) == beforeBytes)
    }

    @Test("The verified accounting query port feeds the stateless projector")
    func existingQueryBoundaryFeedsProjection() async throws {
        let fixture = try Self.fixture(isComplete: true)
        let port = InMemoryAccountingPort(snapshot: fixture.snapshot)
        let stream = port.watchProjectItemAccountingSections(
            accountId: fixture.snapshot.accountId,
            projectId: fixture.snapshot.projectId
        )

        var received: [ProjectItemAccountingSectionsSnapshot] = []
        for try await snapshot in stream {
            received.append(snapshot)
        }
        let snapshot = try #require(received.first)
        #expect(received.count == 1)
        #expect(
            ProjectItemLinkPresentationProjector.sections(from: snapshot).map(\.title) == [
                "Unaccounted For Items",
                "Accounted For Items"
            ]
        )
        #expect(
            try ProjectItemLinkPresentationProjector.linkDescriptor(
                for: snapshot.sections[0].rows[0]
            ).dismiss() == .noAction
        )
    }

    private struct Fixture {
        let snapshot: ProjectItemAccountingSectionsSnapshot
    }

    private struct InMemoryAccountingPort: ProjectItemAccountingQuerying {
        let snapshot: ProjectItemAccountingSectionsSnapshot

        func watchProjectItemAccountingSections(
            accountId: AccountID,
            projectId: ProjectID
        ) -> AsyncThrowingStream<ProjectItemAccountingSectionsSnapshot, Error> {
            AsyncThrowingStream { continuation in
                guard accountId == snapshot.accountId,
                      projectId == snapshot.projectId else {
                    continuation.finish(
                        throwing: ProjectItemAccountingSectionFailure.scopeMismatch
                    )
                    return
                }
                continuation.yield(snapshot)
                continuation.finish()
            }
        }
    }

    private static func fixture(isComplete: Bool) throws -> Fixture {
        let accountId = try AccountID(validating: "account-link-presentation")
        let projectId = try ProjectID(validating: "project-link-presentation")
        let clientId = try ClientID(validating: "client-link-presentation")
        let unaccountedItemId = try ItemID(validating: "item-unaccounted")
        let accountedItemId = try ItemID(validating: "item-accounted")
        let occurrence = BillableItemAccountingOccurrence(
            id: try BillableItemOccurrenceID(validating: "occurrence-accounted"),
            accountId: accountId,
            projectId: projectId,
            itemId: accountedItemId,
            polarity: .charge,
            phase: .availableToInvoice
        )
        let unaccounted = try ProjectItemAccountingEvidence(
            accountId: accountId,
            projectId: projectId,
            clientId: clientId,
            itemId: unaccountedItemId
        )
        let accounted = try ProjectItemAccountingEvidence(
            accountId: accountId,
            projectId: projectId,
            clientId: clientId,
            itemId: accountedItemId,
            billableOccurrences: [occurrence]
        )
        return try Fixture(
            snapshot: ProjectItemAccountingSectionsSnapshot(
                accountId: accountId,
                projectId: projectId,
                clientId: clientId,
                items: [unaccounted, accounted],
                isCompleteForAccounting: isComplete,
                quality: isComplete ? .ready : .partial,
                localDataVersion: try LocalDataVersion(
                    validating: isComplete
                        ? "item-link-presentation-complete-v1"
                        : "item-link-presentation-partial-v1"
                ),
                asOf: Date(timeIntervalSince1970: 1_788_300_000)
            )
        )
    }

    private static func failure(
        _ body: () throws -> ProjectItemLinkPresentationDescriptor
    ) -> ProjectItemLinkPresentationFailure? {
        do {
            _ = try body()
            return nil
        } catch let error as ProjectItemLinkPresentationFailure {
            return error
        } catch {
            return nil
        }
    }
}
