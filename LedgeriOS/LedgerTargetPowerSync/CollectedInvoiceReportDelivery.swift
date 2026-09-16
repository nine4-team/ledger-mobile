import Foundation
import LedgerTargetCore

public enum CollectedInvoiceReportDeliveryFailure: Error { case snapshotChanged }

/// Reuses the report scratch lifetime; frozen Invoice data still needs a fresh
/// authorized read before handing financial bytes to an external destination.
public enum CollectedInvoiceReportDelivery {
    /// Live reports use the same protected handoff lifetime, but compare every
    /// current source fact, not just the header revision (source edits are live).
    @MainActor public static func deliver(data: Data, invoice: LiveInvoiceContents,
        reader: any ProjectLiveInvoiceReading, scratchRoot: URL? = nil,
        handoff: @MainActor (URL) async throws -> Void) async throws {
        let hash = try ProtectedArtifactSHA256.make(bytes: data)
        let reference = try ProtectedArtifactSnapshotReference(
            snapshotID: .init(validating: String(hash.rawValue.prefix(32))), snapshotHash: hash,
            visibilityScopeID: .make(bytes: Data(invoice.selection.scope.accountId.rawValue.utf8)),
            profileVersion: .init(validating: "invoice-report-v1"),
            authorityVersion: .init(validating: "live-invoice-v1"))
        try await ProtectedReportDelivery.deliver(data: data, format: .pdf, reference: reference,
            scratchRoot: scratchRoot, nameHint: "Invoice-" + invoice.invoiceId.rawValue, revalidate: {
                guard let project = invoice.selection.scope.projectId,
                      try await reader.readLiveInvoices(accountId: invoice.selection.scope.accountId, projectId: project)
                        .first(where: { $0.invoiceId == invoice.invoiceId }) == invoice else {
                    throw CollectedInvoiceReportDeliveryFailure.snapshotChanged
                }
            }, handoff: handoff)
    }

    @MainActor public static func deliver(data: Data, invoice: FrozenInvoiceContents,
        reader: any ProjectInvoicingReading, scratchRoot: URL? = nil,
        handoff: @MainActor (URL) async throws -> Void) async throws {
        let hash = try ProtectedArtifactSHA256.make(bytes: data)
        let reference = try ProtectedArtifactSnapshotReference(
            snapshotID: .init(validating: String(hash.rawValue.prefix(32))), snapshotHash: hash,
            visibilityScopeID: .make(bytes: Data(invoice.scope.accountId.rawValue.utf8)),
            profileVersion: .init(validating: "invoice-report-v1"),
            authorityVersion: .init(validating: "collected-invoice-v1"))
        try await ProtectedReportDelivery.deliver(data: data, format: .pdf, reference: reference,
            scratchRoot: scratchRoot, nameHint: "Invoice-" + (invoice.displayMetadata?.invoiceNumber ?? invoice.invoiceId.rawValue), revalidate: {
                guard let project = invoice.scope.projectId,
                      try await reader.readCollectedInvoiceReport(accountId: invoice.scope.accountId,
                        projectId: project, invoiceId: invoice.invoiceId,
                        asOf: .init(validating: Int64(Date().timeIntervalSince1970 * 1000))).invoice == invoice
                else { throw CollectedInvoiceReportDeliveryFailure.snapshotChanged }
            }, handoff: handoff)
    }
}
