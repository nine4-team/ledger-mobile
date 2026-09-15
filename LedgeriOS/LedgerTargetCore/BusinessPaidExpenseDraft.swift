import Foundation

/// Business-paid non-itemized cost (D-009), not a client payment Transaction.
/// Creation eligibility and authorization belong to the command provider; this
/// value preserves entry data without inventing Invoice-edit or collection policy.
public struct BusinessPaidExpenseDraft: Codable, Equatable, Sendable {
    public let accountId: AccountID
    public let projectId: ProjectID
    public let expenseId: ExpenseID
    public let vendor: String
    /// Gregorian YYYY-MM-DD, independent of the device's time zone.
    public let date: String
    public let finalAmount: Money
    public let categoryId: BudgetCategoryID
    public let notes: String
    public let receiptAttachmentIds: [AttachmentID]
    public let receiptLines: [NonItemReceiptLine]

    public init(accountId: AccountID, projectId: ProjectID, expenseId: ExpenseID,
                vendor: String, date: String, finalAmount: Money,
                categoryId: BudgetCategoryID, notes: String,
                receiptAttachmentIds: [AttachmentID] = [],
                receiptLines: [NonItemReceiptLine] = []) throws {
        do { try TransactionDetailSnapshot.validateDate(date) }
        catch { throw Failure.invalidDate }
        guard Set(receiptAttachmentIds).count == receiptAttachmentIds.count else {
            throw Failure.duplicateAttachment
        }
        guard Set(receiptLines.map(\.id)).count == receiptLines.count else {
            throw Failure.duplicateReceiptLine
        }
        guard receiptLines.allSatisfy({ $0.magnitude.currency == finalAmount.currency }) else {
            throw Failure.currencyMismatch
        }
        self.accountId = accountId; self.projectId = projectId; self.expenseId = expenseId
        self.vendor = vendor; self.date = date; self.finalAmount = finalAmount
        self.categoryId = categoryId; self.notes = notes
        self.receiptAttachmentIds = receiptAttachmentIds; self.receiptLines = receiptLines
    }

    public enum Failure: Error, Equatable, Sendable {
        case invalidDate, duplicateAttachment, duplicateReceiptLine, currencyMismatch
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(accountId: c.decode(AccountID.self, forKey: .accountId),
            projectId: c.decode(ProjectID.self, forKey: .projectId),
            expenseId: c.decode(ExpenseID.self, forKey: .expenseId),
            vendor: c.decode(String.self, forKey: .vendor), date: c.decode(String.self, forKey: .date),
            finalAmount: c.decode(Money.self, forKey: .finalAmount),
            categoryId: c.decode(BudgetCategoryID.self, forKey: .categoryId), notes: c.decode(String.self, forKey: .notes),
            receiptAttachmentIds: c.decode([AttachmentID].self, forKey: .receiptAttachmentIds),
            receiptLines: c.decode([NonItemReceiptLine].self, forKey: .receiptLines))
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, projectId, expenseId, vendor, date, finalAmount, categoryId, notes, receiptAttachmentIds, receiptLines
    }
}
