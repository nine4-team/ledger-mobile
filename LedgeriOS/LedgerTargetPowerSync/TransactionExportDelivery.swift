import Foundation
import LedgerTargetCore

public enum TransactionExportDeliveryFailure: Error, Equatable { case snapshotChanged }

/// Reuses report scratch ownership and system-completion cleanup. The bound
/// reader must recheck current authorization and the entire captured source set.
public enum TransactionExportDelivery {
    @MainActor public static func deliver(data: Data, snapshot: TransactionExportSnapshot,
        reader: any TransactionExportReading, scratchRoot: URL? = nil,
        handoff: @MainActor (URL) async throws -> Void) async throws {
        try await ProtectedReportDelivery.deliver(data: data, format: .csv, reference: snapshot.reference,
            scratchRoot: scratchRoot, revalidate: {
                let current = try await reader.readTransactionExport(scope: snapshot.scope,
                    orderedTransactionIDs: snapshot.orderedTransactionIDs, asOf: snapshot.asOf)
                guard current.reference == snapshot.reference else { throw TransactionExportDeliveryFailure.snapshotChanged }
            }, handoff: handoff)
    }
}

/// PDFs use the existing protected scratch store and native completion lifetime.
/// The snapshot reference identifies this copy; current Transaction access is
/// re-read after file creation and remains mandatory at the UI handoff boundary.
public enum TransactionAttachmentPDFDelivery {
    @MainActor public static func deliver(data: Data, catalog: DownloadedTransactionAttachments,
        attachment: DownloadedTransactionAttachment, reader: any DownloadedTransactionAttachmentReading,
        scratchRoot: URL? = nil, handoff: @MainActor (URL) async throws -> Void) async throws {
        let hash = try ProtectedArtifactSHA256.make(bytes: data)
        guard attachment.object.mediaType == "application/pdf", catalog.retains(attachment, from: catalog),
              hash.rawValue == attachment.object.contentSHA256.rawValue,
              Int64(data.count) == attachment.object.byteCount else {
            throw DownloadedTransactionAttachments.Failure.invalidEvidence
        }
        let scopeBytes = try JSONSerialization.data(withJSONObject: [catalog.scope.accountId.rawValue,
            catalog.scope.projectId?.rawValue ?? "", catalog.scope.clientId?.rawValue ?? "",
            catalog.transactionId.rawValue, catalog.section.rawValue, String(catalog.revision!), attachment.id.rawValue])
        let reference = try ProtectedArtifactSnapshotReference(
            snapshotID: .init(validating: String(hash.rawValue.prefix(32))), snapshotHash: hash,
            visibilityScopeID: .make(bytes: scopeBytes), profileVersion: .init(validating: "transaction-pdf-v1"),
            authorityVersion: .init(validating: "transaction-attachment-v1"))
        try await ProtectedReportDelivery.deliver(data: data, format: .pdf, reference: reference,
            scratchRoot: scratchRoot, revalidate: {
                let current = try await reader.readDownloadedTransactionAttachments(scope: catalog.scope,
                    transactionId: catalog.transactionId, section: catalog.section)
                guard current.retains(attachment, from: catalog) else {
                    throw DownloadedTransactionAttachments.Failure.unavailable
                }
            }, handoff: handoff)
    }
}
