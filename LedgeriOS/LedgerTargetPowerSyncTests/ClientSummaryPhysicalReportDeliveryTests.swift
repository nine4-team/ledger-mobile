import Foundation
import LedgerTargetCore
import LedgerTargetPowerSync
import Testing

@Suite("Client Summary authorized handoff") @MainActor
struct ClientSummaryPhysicalReportDeliveryTests {
    private enum Failure: Error { case denied, system }
    private struct Reader: ClientSummaryPhysicalReportReading {
        let snapshot: ClientSummaryPhysicalReportSnapshot
        var denied = false
        func readDownloadedClientSummaryPhysicalReport(accountId: AccountID, projectId: ProjectID,
            asOf: ProtectedArtifactEpochMilliseconds) async throws -> ClientSummaryPhysicalReportSnapshot {
            #expect(accountId == snapshot.project.accountId)
            #expect(projectId == snapshot.project.projectId)
            #expect(asOf == snapshot.provenance.asOf)
            if denied { throw Failure.denied }
            return snapshot
        }
    }

    @Test func incompletePreviewCannotReachHandoff() async throws {
        let report = try fixture(knownClient: false)
        await #expect(throws: ClientSummaryPhysicalReportDeliveryFailure.incompleteReport) {
            try await ClientSummaryPhysicalReportDelivery.deliver(data: Data("%PDF-test".utf8),
                snapshot: report, reader: Reader(snapshot: report)) { _ in
                    Issue.record("Incomplete report reached handoff")
                }
        }
    }

    @Test(arguments: ["denied", "client", "incomplete"])
    func revalidatesImmediatelyBeforeHandoff(change: String) async throws {
        let report = try fixture()
        let current = try fixture(name: change == "client" ? "Renamed" : "Client",
                                  knownClient: change != "incomplete")
        do {
            try await ClientSummaryPhysicalReportDelivery.deliver(data: Data("%PDF-test".utf8),
                snapshot: report, reader: Reader(snapshot: current, denied: change == "denied")) { _ in
                    Issue.record("Changed or denied report reached handoff")
                }
            Issue.record("Expected rejection")
        } catch Failure.denied { #expect(change == "denied") }
        catch ClientSummaryPhysicalReportDeliveryFailure.snapshotChanged { #expect(change != "denied") }
    }

    @Test(arguments: [false, true])
    func cleansBytesAfterSystemCompletion(fails: Bool) async throws {
        let report = try fixture(), bytes = Data("%PDF-client-summary".utf8)
        var handedOff: URL?
        do {
            try await ClientSummaryPhysicalReportDelivery.deliver(data: bytes, snapshot: report,
                reader: Reader(snapshot: report)) { url in
                    handedOff = url
                    #expect(try Data(contentsOf: url) == bytes)
                    #expect(url.pathExtension == "pdf")
                    if fails { throw Failure.system }
                }
            #expect(!fails)
        } catch Failure.system { #expect(fails) }
        let url = try #require(handedOff)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    private func fixture(name: String = "Client", knownClient: Bool = true) throws -> ClientSummaryPhysicalReportSnapshot {
        let account = try AccountID(validating: "delivery-account"), project = try ProjectID(validating: "delivery-project")
        let client = try ClientID(validating: "delivery-client")
        return try .build(project: .init(accountId: account, projectId: project, name: "Property", address: nil, revision: 1),
            client: knownClient ? .known(clientId: client, name: name, revision: 1) : .unavailable(clientId: client),
            spaces: [], items: [], provenance: .init(accountId: account, projectId: project,
                principalId: PrincipalID(validating: "delivery-user"), visibilityScopeID: .make(bytes: Data("scope".utf8)),
                localDataVersion: .init(validating: "delivery-1"), authorityVersion: .init(validating: "client-summary-v1"),
                asOf: .init(validating: 1_800_000_000_000), readiness: .ready,
                lastSyncedAt: .init(validating: 1_800_000_000_000)))
    }
}
