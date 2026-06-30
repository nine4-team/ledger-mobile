import Testing
@testable import LedgeriOS

@Suite("Transaction Creation Step Resolver Tests")
struct TransactionCreationStepResolverTests {
    @Test("Project-scoped purchase skips project selection")
    func projectPurchaseSkipsDestinationSelection() {
        let steps = TransactionCreationStepResolver.orderedSteps(
            type: .purchase,
            context: .project("project-123"),
            destinationProjectId: "project-123"
        )

        #expect(steps == [
            .typeSelection,
            .whoPaid,
            .budgetCategory,
            .vendor,
            .details,
        ])
    }

    @Test("Inventory purchase includes project selection")
    func inventoryPurchaseIncludesDestinationSelection() {
        let steps = TransactionCreationStepResolver.orderedSteps(
            type: .purchase,
            context: .inventory,
            destinationProjectId: nil
        )

        #expect(steps == [
            .typeSelection,
            .whoPaid,
            .destination,
            .vendor,
            .details,
        ])
    }

    @Test("Project-scoped return skips project selection and who paid")
    func projectReturnSkipsDestinationAndWhoPaidSelection() {
        let steps = TransactionCreationStepResolver.orderedSteps(
            type: .return,
            context: .project("project-123"),
            destinationProjectId: "project-123"
        )

        #expect(steps == [
            .typeSelection,
            .budgetCategory,
            .vendor,
            .details,
        ])
    }

    @Test("Project-scoped client payment skips who paid and vendor")
    func projectClientPaymentSkipsWhoPaidAndVendorSelection() {
        let steps = TransactionCreationStepResolver.orderedSteps(
            type: .paymentToBusiness,
            context: .project("project-123"),
            destinationProjectId: "project-123",
            skipVendor: true
        )

        #expect(steps == [
            .typeSelection,
            .budgetCategory,
            .details,
        ])
    }
}
