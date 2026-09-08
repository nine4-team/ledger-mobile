import Foundation
import LedgerTargetCore

public enum PropertyManagementReportDeliveryFailure: Error, Equatable {
    case snapshotChanged
}

/// Owns one export's scratch lifetime. The system adapter must return only when
/// sharing/printing completes, fails, or is canceled—not when its picker opens.
public enum PropertyManagementReportDelivery {
    /// Startup recovery is independent of opening or exporting a report.
    /// Store locks preserve any other window/process's active handoff.
    public static func recoverStartupScratch(scratchRoot: URL? = nil) async throws {
        let store = try ReportScratchStore(rootDirectory: scratchRoot)
        do {
            try await store.recoverAbandonedSessions()
            try await store.close()
        } catch {
            try? await store.close()
            throw error
        }
    }

    @MainActor public static func deliver(
        data: Data, format: ReportScratchFormat = .pdf, snapshot: PropertyManagementReportSnapshot,
        reader: any PropertyManagementReportReading,
        scratchRoot: URL? = nil,
        handoff: @MainActor (URL) async throws -> Void
    ) async throws {
        let store = try ReportScratchStore(rootDirectory: scratchRoot)
        let artifact: ReportScratchArtifact
        do {
            try await store.recoverAbandonedSessions()
            try Task.checkCancellation()
            artifact = try await store.create(data: data, format: format, snapshotReference: snapshot.reference)
        } catch {
            try? await store.close()
            throw error
        }
        let result: Result<Void, Error>
        do {
            // Re-read with the displayed as-of value, so the reference changes
            // only with source/access evidence, not merely elapsed wall time.
            let current = try await reader.readDownloadedPropertyManagementReport(
                accountId: snapshot.project.accountId, projectId: snapshot.project.projectId,
                currency: snapshot.currency, asOf: snapshot.provenance.asOf)
            guard current.reference == snapshot.reference else {
                throw PropertyManagementReportDeliveryFailure.snapshotChanged
            }
            try Task.checkCancellation()
            try await handoff(artifact.url)
            result = .success(())
        } catch { result = .failure(error) }
        // Do not tie cleanup to view disappearance or task cancellation: the OS
        // can still be reading the file. Its completion above owns this boundary.
        try await store.remove(artifact)
        try await store.close()
        try result.get()
    }
}
