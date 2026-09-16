import Foundation
import LedgerTargetCore

public enum ExpenseExportDelivery {
    public enum Failure: Error { case unavailable, changed }

    public static func read(accountId: AccountID, projectId: ProjectID, expenseId: ExpenseID,
        reader: any ProjectInvoicingReading) async throws -> ExpenseExportSnapshot {
        let rows = try await reader.readExpenses(accountId: accountId, projectId: projectId)
        guard rows.accountId == accountId, rows.projectId == projectId,
              let expense = rows.expenses.first(where: { $0.id == expenseId }) else { throw Failure.unavailable }
        return try .init(expense: expense)
    }

    @MainActor public static func deliver(data: Data, snapshot: ExpenseExportSnapshot,
        reader: any ProjectInvoicingReading, scratchRoot: URL? = nil,
        handoff: @MainActor (URL) async throws -> Void) async throws {
        let entry = snapshot.expense.entry
        try await ProtectedReportDelivery.deliver(data: data, format: .csv, reference: snapshot.reference,
            scratchRoot: scratchRoot, revalidate: {
                let current = try await read(accountId: entry.accountId, projectId: entry.projectId,
                    expenseId: entry.expenseId, reader: reader)
                guard current == snapshot else { throw Failure.changed }
            }, handoff: handoff)
    }
}
