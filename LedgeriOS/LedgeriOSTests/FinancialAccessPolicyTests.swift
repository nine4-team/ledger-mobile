import Foundation
import Testing
@testable import LedgeriOS

@Suite("Financial Access Policy Tests")
struct FinancialAccessPolicyTests {
    @Test("Owner/admin default to full access and employees default to none")
    func roleDefaults() {
        var owner = AccountMember()
        owner.role = .owner
        #expect(owner.resolvedCompanyFinancialAccess == .full)

        var admin = AccountMember()
        admin.role = .admin
        #expect(admin.resolvedCompanyFinancialAccess == .full)

        var employee = AccountMember()
        employee.role = .user
        #expect(employee.resolvedCompanyFinancialAccess == .none)
    }

    @Test("Limited access sees Kitchen fees but not Design fees")
    func limitedFeeCategoryAccess() {
        let kitchen = feeCategory(id: "kitchen", name: "Kitchen Fees")
        let design = feeCategory(id: "design", name: "Design Fees")
        let categories = [kitchen, design]

        let policy = FinancialAccessPolicy(access: .limited, allowedFeeCategoryIds: ["kitchen"])

        #expect(policy.canSeeTransaction(feeTransaction(id: "tx1", categoryId: "kitchen"), categories: categories))
        #expect(!policy.canSeeTransaction(feeTransaction(id: "tx2", categoryId: "design"), categories: categories))
        #expect(!policy.canSeeTransaction(feeTransaction(id: "tx3", categoryId: nil), categories: categories))
        #expect(policy.canSeeTransaction(expenseTransaction(id: "tx4"), categories: categories))
    }

    @Test("Limited invoice access requires every fee category to be allowed")
    func limitedInvoiceAccess() {
        let kitchen = feeCategory(id: "kitchen", name: "Kitchen Fees")
        let design = feeCategory(id: "design", name: "Design Fees")
        let categories = [kitchen, design]
        let policy = FinancialAccessPolicy(access: .limited, allowedFeeCategoryIds: ["kitchen"])

        var kitchenInvoice = Invoice()
        kitchenInvoice.containsCompanyRevenue = true
        kitchenInvoice.feeCategoryIds = ["kitchen"]

        var mixedInvoice = Invoice()
        mixedInvoice.containsCompanyRevenue = true
        mixedInvoice.feeCategoryIds = ["kitchen", "design"]

        var ambiguousRevenueInvoice = Invoice()
        ambiguousRevenueInvoice.containsCompanyRevenue = true

        #expect(policy.canSeeInvoice(kitchenInvoice, transactions: [], categories: categories))
        #expect(!policy.canSeeInvoice(mixedInvoice, transactions: [], categories: categories))
        #expect(!policy.canSeeInvoice(ambiguousRevenueInvoice, transactions: [], categories: categories))
    }

    @Test("Manual charge invoices without metadata fail closed")
    func manualChargeFailsClosed() {
        let policy = FinancialAccessPolicy(access: .limited, allowedFeeCategoryIds: ["kitchen"])

        var invoice = Invoice()
        invoice.lines = [
            InvoiceLine(sourceType: .manual, amountCents: 10000, sign: .charge, snapshotName: "Design Fee")
        ]

        #expect(!policy.canSeeInvoice(invoice, transactions: [], categories: []))
    }

    @Test("Invite links round-trip token through the custom URL scheme")
    func inviteLinkRoundTrip() throws {
        let token = "abc-123"
        let url = try #require(InviteLinks.link(token: token))

        #expect(url.absoluteString == "ledger-nine4://invite?token=abc-123")
        #expect(InviteLinks.token(from: url) == token)
    }

    @Test("Invite links parse web fallback tokens")
    func inviteWebFallbackParsing() throws {
        let url = try #require(URL(string: "https://ledger-nine4.web.app/invite?token=abc-123"))

        #expect(InviteLinks.token(from: url) == "abc-123")
    }

    private func feeCategory(id: String, name: String) -> BudgetCategory {
        var category = BudgetCategory()
        category.id = id
        category.name = name
        category.supportedTypes = [.fee]
        return category
    }

    private func feeTransaction(id: String, categoryId: String?) -> Transaction {
        var transaction = Transaction()
        transaction.id = id
        transaction.transactionType = .fee
        transaction.budgetCategoryId = categoryId
        return transaction
    }

    private func expenseTransaction(id: String) -> Transaction {
        var transaction = Transaction()
        transaction.id = id
        transaction.transactionType = .expense
        return transaction
    }
}
