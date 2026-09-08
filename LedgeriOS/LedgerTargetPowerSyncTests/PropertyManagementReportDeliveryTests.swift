import Foundation
import LedgerTargetCore
import LedgerTargetPowerSync
import Testing

@Suite("Property report authorized handoff") @MainActor
struct PropertyManagementReportDeliveryTests {
    private enum Failure: Error { case denied, system }
    private struct Reader: PropertyManagementReportReading {
        let snapshot: PropertyManagementReportSnapshot
        var denied = false
        func readDownloadedPropertyManagementReport(accountId: AccountID, projectId: ProjectID,
            currency: CurrencyCode, asOf: ProtectedArtifactEpochMilliseconds) async throws -> PropertyManagementReportSnapshot {
            #expect(accountId == snapshot.project.accountId)
            #expect(projectId == snapshot.project.projectId)
            #expect(currency == snapshot.currency)
            #expect(asOf == snapshot.provenance.asOf)
            if denied { throw Failure.denied }
            return snapshot
        }
    }

    @Test("Denied access or changed source cannot reach system handoff", arguments: [false, true])
    func revalidation(changed: Bool) async throws {
        let report = try fixture()
        let reader = Reader(snapshot: try fixture(name: changed ? "Changed" : "Property"), denied: !changed)
        do {
            try await PropertyManagementReportDelivery.deliver(data: Data("%PDF-test".utf8), snapshot: report, reader: reader) { _ in
                Issue.record("Unauthorized/stale report reached handoff")
            }
            Issue.record("Expected validation failure")
        } catch PropertyManagementReportDeliveryFailure.snapshotChanged { #expect(changed) }
        catch Failure.denied { #expect(!changed) }
    }

    @Test("System success, cancellation and failure clean only after callback", arguments: [false, true], [ReportScratchFormat.pdf, .csv])
    func lifetime(fails: Bool, format: ReportScratchFormat) async throws {
        let report = try fixture()
        let bytes = Data((format == .pdf ? "%PDF-test" : "row,value\r\nitem,1\r\n").utf8)
        let entered = AsyncStream<URL>.makeStream()
        let finish = AsyncStream<Void>.makeStream()
        let task = Task {
            try await PropertyManagementReportDelivery.deliver(data: bytes, format: format, snapshot: report,
                reader: Reader(snapshot: report)) { url in
                entered.continuation.yield(url)
                // System completion isn't the parent task's cancellation. This
                // uncanceled task stands in for the external delegate callback.
                await Task.detached { for await _ in finish.stream { break } }.value
                #expect(FileManager.default.fileExists(atPath: url.path))
                if fails { throw Failure.system }
            }
        }
        var iterator = entered.stream.makeAsyncIterator()
        let url = try #require(await iterator.next())
        #expect(try Data(contentsOf: url) == bytes)
        #expect(url.pathExtension == format.rawValue)
        task.cancel()
        #expect(FileManager.default.fileExists(atPath: url.path))
        finish.continuation.yield(())
        finish.continuation.finish()
        do { try await task.value; #expect(!fails) }
        catch Failure.system { #expect(fails) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        entered.continuation.finish()
    }

    private func fixture(name: String = "Property") throws -> PropertyManagementReportSnapshot {
        let account = try AccountID(validating: "delivery-account"), project = try ProjectID(validating: "delivery-project")
        return try .build(project: .init(accountId: account, projectId: project, name: name, address: nil, revision: 1),
            spaces: [], items: [], currency: CurrencyCode(validating: "USD"),
            provenance: .init(accountId: account, projectId: project, principalId: PrincipalID(validating: "delivery-user"),
                visibilityScopeID: .make(bytes: Data("delivery-scope".utf8)), localDataVersion: .init(validating: "delivery-1"),
                authorityVersion: .init(validating: "property-management-v1"), asOf: .init(validating: 1_800_000_000_000),
                readiness: .ready, lastSyncedAt: .init(validating: 1_799_999_000_000)))
    }
}
