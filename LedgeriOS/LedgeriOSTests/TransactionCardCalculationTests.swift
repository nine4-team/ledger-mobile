import Foundation
import Testing
@testable import LedgeriOS

@Suite("Transaction Card Calculation Tests")
struct TransactionCardCalculationTests {

    // MARK: - badgeItems

    @Test("Purchase produces subtle brand-primary badge")
    func badgeItemsPurchase() {
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
        #expect(badges[0].color == BrandColors.primary)
        #expect(badges[0].backgroundOpacity == 0.10)
        #expect(badges[0].borderOpacity == 0.20)
    }

    @Test("Return produces subtle brand-primary badge")
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
        #expect(badges[0].color == BrandColors.primary)
        #expect(badges[0].backgroundOpacity == 0.10)
        #expect(badges[0].borderOpacity == 0.20)
    }

    @Test("Sale produces no badge")
    func badgeItemsSaleRemoved() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: "sale",
            reimbursementType: nil,
            hasEmailReceipt: false,
            needsReview: false,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.isEmpty)
    }

    @Test("To-inventory produces no badge")
    func badgeItemsToInventoryRemoved() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: "to-inventory",
            reimbursementType: nil,
            hasEmailReceipt: false,
            needsReview: false,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.isEmpty)
    }

    @Test("Reimbursement produces no badge")
    func badgeItemsReimbursementRemoved() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: nil,
            reimbursementType: "owed-to-client",
            hasEmailReceipt: false,
            needsReview: false,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.isEmpty)
    }

    @Test("Needs review badge has extra-subtle opacity")
    func badgeItemsNeedsReview() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: nil,
            reimbursementType: nil,
            hasEmailReceipt: false,
            needsReview: true,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.count == 1)
        #expect(badges[0].text == "Needs Review")
        #expect(badges[0].color == StatusColors.badgeNeedsReview)
        #expect(badges[0].backgroundOpacity == 0.08)
        #expect(badges[0].borderOpacity == 0.20)
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
        #expect(badges[0].backgroundOpacity == 0.10)
        #expect(badges[0].borderOpacity == 0.20)
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

    @Test("Badge order: needs review first, then type, then category")
    func badgeItemsOrder() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: "purchase",
            reimbursementType: "owed-to-client",
            hasEmailReceipt: true,
            needsReview: true,
            budgetCategoryName: "Furnishings",
            status: nil
        )
        #expect(badges.count == 3)
        #expect(badges[0].text == "Needs Review")
        #expect(badges[1].text == "Purchase")
        #expect(badges[2].text == "Furnishings")
    }

    @Test("Multiple badges: purchase + review (reimbursement excluded)")
    func badgeItemsMultiple() {
        let badges = TransactionCardCalculations.badgeItems(
            transactionType: "purchase",
            reimbursementType: "owed-to-client",
            hasEmailReceipt: true,
            needsReview: true,
            budgetCategoryName: nil,
            status: nil
        )
        #expect(badges.count == 2)
        #expect(badges[0].text == "Needs Review")
        #expect(badges[1].text == "Purchase")
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
