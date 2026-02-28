import Foundation
import Testing
@testable import LedgeriOS

@Suite("Transaction Form Validation Tests")
struct TransactionFormValidationTests {

    // MARK: - validateTransactionStep1

    @Test("Nil type fails step 1 validation")
    func nilTypeFails() {
        let errors = TransactionFormValidation.validateTransactionStep1(type: nil)
        #expect(errors.contains(ValidationError(
            field: "transactionType",
            message: "Transaction type is required"
        )))
    }

    @Test("Empty type fails step 1 validation")
    func emptyTypeFails() {
        let errors = TransactionFormValidation.validateTransactionStep1(type: "")
        #expect(errors.contains(ValidationError(
            field: "transactionType",
            message: "Transaction type is required"
        )))
    }

    @Test("Valid type passes step 1")
    func validTypePasses() {
        let errors = TransactionFormValidation.validateTransactionStep1(type: "purchase")
        #expect(errors.isEmpty)
    }

    @Test("All transaction types pass step 1")
    func allTypesPass() {
        for type in ["purchase", "sale", "return", "to-inventory"] {
            let errors = TransactionFormValidation.validateTransactionStep1(type: type)
            #expect(errors.isEmpty, "Type '\(type)' should pass step 1")
        }
    }

    // MARK: - validateTransactionStep2

    @Test("Purchase without destination fails step 2")
    func purchaseNoDestinationFails() {
        let errors = TransactionFormValidation.validateTransactionStep2(
            type: "purchase",
            destination: nil
        )
        #expect(errors.contains(ValidationError(
            field: "destination",
            message: "Destination is required"
        )))
    }

    @Test("Sale without destination fails step 2")
    func saleNoDestinationFails() {
        let errors = TransactionFormValidation.validateTransactionStep2(
            type: "sale",
            destination: nil
        )
        #expect(errors.contains(ValidationError(
            field: "destination",
            message: "Destination is required"
        )))
    }

    @Test("Return without destination fails step 2")
    func returnNoDestinationFails() {
        let errors = TransactionFormValidation.validateTransactionStep2(
            type: "return",
            destination: nil
        )
        #expect(errors.contains(ValidationError(
            field: "destination",
            message: "Destination is required"
        )))
    }

    @Test("to-inventory does not require destination")
    func toInventoryNoDestinationPasses() {
        let errors = TransactionFormValidation.validateTransactionStep2(
            type: "to-inventory",
            destination: nil
        )
        #expect(errors.isEmpty)
    }

    @Test("Purchase with destination passes step 2")
    func purchaseWithDestinationPasses() {
        let errors = TransactionFormValidation.validateTransactionStep2(
            type: "purchase",
            destination: "project-123"
        )
        #expect(errors.isEmpty)
    }

    // MARK: - validateTransactionDetail

    @Test("Detail validation returns empty for all optional fields")
    func detailValidationEmpty() {
        let errors = TransactionFormValidation.validateTransactionDetail(
            type: "purchase",
            source: nil,
            amountCents: nil,
            date: nil
        )
        #expect(errors.isEmpty)
    }

    @Test("Detail validation with values returns empty")
    func detailValidationWithValues() {
        let errors = TransactionFormValidation.validateTransactionDetail(
            type: "purchase",
            source: "Home Depot",
            amountCents: 5000,
            date: Date()
        )
        #expect(errors.isEmpty)
    }

    // MARK: - isTransactionReadyToSubmit

    @Test("Ready to submit with valid type")
    func readyWithType() {
        #expect(TransactionFormValidation.isTransactionReadyToSubmit(type: "purchase"))
    }

    @Test("Not ready with nil type")
    func notReadyNilType() {
        #expect(!TransactionFormValidation.isTransactionReadyToSubmit(type: nil))
    }

    @Test("Not ready with empty type")
    func notReadyEmptyType() {
        #expect(!TransactionFormValidation.isTransactionReadyToSubmit(type: ""))
    }
}
