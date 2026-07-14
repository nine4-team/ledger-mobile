import Testing
@testable import LedgeriOS

@Suite("Transaction Creation Step Resolver Tests")
struct TransactionCreationStepResolverTests {
    @Test("Inventory is available as a transaction destination")
    func inventoryIsAvailableAsDestination() {
        var project = Project()
        project.id = "project-123"
        project.name = "Vegas Project"

        let options = TransactionDestinationResolver.options(projects: [project])

        #expect(options.map(\.id) == [.inventory, .project("project-123")])
        #expect(options.map(\.label) == ["Inventory", "Vegas Project"])
    }

    @Test("Archived projects are excluded from transaction destinations")
    func archivedProjectsAreExcludedFromDestinations() {
        var project = Project()
        project.id = "archived-project"
        project.name = "Archived Project"
        project.isArchived = true

        let options = TransactionDestinationResolver.options(projects: [project])

        #expect(options.map(\.id) == [.inventory])
    }

    @Test("Inventory source aliases can be excluded for inventory-bound transactions")
    func inventorySourceAliasesCanBeExcluded() {
        let options = VendorDefaultsService.displayVendorOptions(
            fixedOptions: ["Assiist Biz Inventory"],
            vendors: ["Homegoods", "Inventory", "Amazon"],
            excluding: ["Inventory", "Assiist Biz Inventory"]
        )

        #expect(options == ["Homegoods", "Amazon"])
    }

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
