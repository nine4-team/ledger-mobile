import Foundation
import LedgerTargetCore

public enum ClientSummaryPhysicalReportDeliveryFailure: Error, Equatable {
    case incompleteReport, snapshotChanged
}

public enum ClientSummaryPhysicalReportDelivery {
    @MainActor public static func deliver(data: Data, snapshot: ClientSummaryPhysicalReportSnapshot,
        reader: any ClientSummaryPhysicalReportReading, scratchRoot: URL? = nil,
        handoff: @MainActor (URL) async throws -> Void) async throws {
        guard snapshot.isComplete else { throw ClientSummaryPhysicalReportDeliveryFailure.incompleteReport }
        try await ProtectedReportDelivery.deliver(data: data, format: .pdf, reference: snapshot.reference,
            scratchRoot: scratchRoot, revalidate: {
                // Fixed as-of avoids confusing elapsed time with changed data.
                let current = try await reader.readDownloadedClientSummaryPhysicalReport(
                    accountId: snapshot.project.accountId, projectId: snapshot.project.projectId,
                    asOf: snapshot.provenance.asOf)
                guard current.isComplete, current.reference == snapshot.reference else {
                    throw ClientSummaryPhysicalReportDeliveryFailure.snapshotChanged
                }
            }, handoff: handoff)
    }
}
