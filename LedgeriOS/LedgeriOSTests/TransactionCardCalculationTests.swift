import Foundation
import Testing
@testable import LedgeriOS

@Suite("Transaction Card Calculation Tests")
struct TransactionCardCalculationTests {

    // MARK: - badgeItems

    @Test("Purchase only produces one green badge")
    func badgeItemsPurchaseOnly() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: "purchase",
            reimbursementType: nil,
            hasEmailReceipt: false,
            needsReview: false,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.count == 1)
        #expect(badges[0].text == "Purchase")
        #expect(badges[0].color == StatusColors.badgeSuccess)
    }

    @Test("Sale produces blue badge")
    func badgeItemsSale() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: "sale",
            reimbursementType: nil,
            hasEmailReceipt: false,
            needsReview: false,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.count == 1)
        #expect(badges[0].text == "Sale")
        #expect(badges[0].color == StatusColors.badgeInfo)
    }

    @Test("Return produces red badge")
    func badgeItemsReturn() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: "return",
            reimbursementType: nil,
            hasEmailReceipt: false,
            needsReview: false,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.count == 1)
        #expect(badges[0].text == "Return")
        #expect(badges[0].color == StatusColors.badgeError)
    }

    @Test("To-inventory produces primary badge")
    func badgeItemsToInventory() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: "to-inventory",
            reimbursementType: nil,
            hasEmailReceipt: false,
            needsReview: false,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.count == 1)
        #expect(badges[0].text == "To Inventory")
        #expect(badges[0].color == BrandColors.primary)
    }

    @Test("Multiple badges: purchase + reimbursement + receipt + review")
    func badgeItemsMultiple() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: "purchase",
            reimbursementType: "owed-to-client",
            hasEmailReceipt: true,
            needsReview: true,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.count == 4)
        #expect(badges[0].text == "Purchase")
        #expect(badges[1].text == "Owed to Client")
        #expect(badges[2].text == "Receipt")
        #expect(badges[3].text == "Needs Review")
    }

    @Test("Reimbursement owed to company shows Owed to Business")
    func badgeItemsOwedToCompany() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: nil,
            reimbursementType: "owed-to-company",
            hasEmailReceipt: false,
            needsReview: false,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.count == 1)
        #expect(badges[0].text == "Owed to Business")
        #expect(badges[0].color == StatusColors.badgeWarning)
    }

    @Test("Budget category adds primary-colored badge")
    func badgeItemsWithCategory() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: nil,
            reimbursementType: nil,
            hasEmailReceipt: false,
            needsReview: false,
            budgetCategoryName: "Furnishings",
            status: nil
        )
        #expect(badges.count == 1)
        #expect(badges[0].text == "Furnishings")
        #expect(badges[0].color == BrandColors.primary)
    }

    @Test("All nil/false produces empty badges")
    func badgeItemsAllNil() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: nil,
            reimbursementType: nil,
            hasEmailReceipt: false,
            needsReview: false,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.isEmpty)
    }

    @Test("Badge order: type, reimbursement, receipt, review, category")
    func badgeItemsOrder() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: "purchase",
            reimbursementType: "owed-to-client",
            hasEmailReceipt: true,
            needsReview: true,
            budgetCategoryName: "Furnishings",
            status: nil
        )
        #expect(badges.count == 5)
        #expect(badges[0].text == "Purchase")
        #expect(badges[1].text == "Owed to Client")
        #expect(badges[2].text == "Receipt")
        #expect(badges[3].text == "Needs Review")
        #expect(badges[4].text == "Furnishings")
    }

    @Test("Empty budget category name is ignored")
    func badgeItemsEmptyCategory() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: nil,
            reimbursementType: nil,
            hasEmailReceipt: false,
            needsReview: false,
            budgetCategoryName: "",
            status: nil
        )
        #expect(badges.isEmpty)
    }

    // MARK: - formattedAmount

    @Test("Formats positive cents with decimals")
    func formattedAmountPositive() {
        let result = TransactionCardCalculations.formattedAmount(amountCents: 10012, transactionType: "purchase")
        #expect(result == "$100.12")
    }

    @Test("Formats zero cents")
    func formattedAmountZero() {
        let result = TransactionCardCalculations.formattedAmount(amountCents: 0, transactionType: nil)
        #expect(result == "$0.00")
    }

    @Test("Nil amount returns em dash")
    func formattedAmountNil() {
        let result = TransactionCardCalculations.formattedAmount(amountCents: nil, transactionType: nil)
        #expect(result == "—")
    }

    // MARK: - formattedDate

    @Test("Valid ISO date formats to MMM d, yyyy")
    func formattedDateValid() {
        let result = TransactionCardCalculations.formattedDate("2026-02-25T10:30:00Z")
        #expect(result == "Feb 25, 2026")
    }

    @Test("Date-only string formats correctly")
    func formattedDateOnly() {
        let result = TransactionCardCalculations.formattedDate("2026-02-25")
        #expect(result == "Feb 25, 2026")
    }

    @Test("Nil date returns em dash")
    func formattedDateNil() {
        let result = TransactionCardCalculations.formattedDate(nil)
        #expect(result == "—")
    }

    @Test("Empty date returns em dash")
    func formattedDateEmpty() {
        let result = TransactionCardCalculations.formattedDate("")
        #expect(result == "—")
    }

    @Test("Invalid date returns em dash")
    func formattedDateInvalid() {
        let result = TransactionCardCalculations.formattedDate("not-a-date")
        #expect(result == "—")
    }

    // MARK: - truncatedNotes

    @Test("Short notes returned as-is")
    func truncatedNotesShort() {
        let result = TransactionCardCalculations.truncatedNotes("A short note")
        #expect(result == "A short note")
    }

    @Test("Long notes truncated with ellipsis")
    func truncatedNotesLong() {
        let long = String(repeating: "a", count: 120)
        let result = TransactionCardCalculations.truncatedNotes(long, maxLength: 100)
        #expect(result?.count == 103) // 100 chars + "..."
        #expect(result?.hasSuffix("...") == true)
    }

    @Test("Nil notes returns nil")
    func truncatedNotesNil() {
        let result = TransactionCardCalculations.truncatedNotes(nil)
        #expect(result == nil)
    }

    @Test("Empty notes returns nil")
    func truncatedNotesEmpty() {
        let result = TransactionCardCalculations.truncatedNotes("")
        #expect(result == nil)
    }

    @Test("Exact max length not truncated")
    func truncatedNotesExactLength() {
        let exact = String(repeating: "b", count: 100)
        let result = TransactionCardCalculations.truncatedNotes(exact, maxLength: 100)
        #expect(result == exact)
    }
}
