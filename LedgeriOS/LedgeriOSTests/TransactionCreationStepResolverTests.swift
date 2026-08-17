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

    @Test("Business-paid purchase asks how the purchase should be handled")
    func businessPurchaseIncludesHandlingDecision() {
        let steps = TransactionCreationStepResolver.orderedSteps(
            type: .purchase,
            context: .project("project-123"),
            destinationProjectId: "project-123",
            purchasedBy: "design-business"
        )

        #expect(steps == [
            .typeSelection,
            .whoPaid,
            .purchaseHandling,
            .budgetCategory,
            .vendor,
            .details,
        ])
    }

    @Test("Client-paid purchase does not ask for business purchase handling")
    func clientPurchaseSkipsHandlingDecision() {
        let steps = TransactionCreationStepResolver.orderedSteps(
            type: .purchase,
            context: .project("project-123"),
            destinationProjectId: "project-123",
            purchasedBy: "client-card"
        )

        #expect(!steps.contains(.purchaseHandling))
    }

    @Test("Only explicit resale handling routes through inventory")
    func explicitHandlingControlsInventoryRouting() {
        #expect(TransactionFormValidation.shouldRouteThroughInventory(
            type: .purchase,
            purchasedBy: "design-business",
            purchaseHandling: .inventoryResale
        ))
        #expect(!TransactionFormValidation.shouldRouteThroughInventory(
            type: .purchase,
            purchasedBy: "design-business",
            purchaseHandling: .projectReimbursement
        ))
        #expect(!TransactionFormValidation.shouldRouteThroughInventory(
            type: .purchase,
            purchasedBy: "client-card",
            purchaseHandling: .inventoryResale
        ))
    }

    @Test("Planned inventory purchase waits when no items have been entered")
    func plannedPurchaseWaitsForItems() {
        var transaction = Transaction()
        transaction.intendedBudgetCategoryId = "furnishings"

        #expect(InventoryPurchaseIntentCalculations.state(
            transaction: transaction,
            activeItems: [],
            projectExists: true,
            categoryExists: true
        ) == .waitingForItems)
    }

    @Test("Planned inventory purchase requires a client-facing price")
    func plannedPurchaseRequiresProjectPrice() {
        var transaction = Transaction()
        transaction.intendedBudgetCategoryId = "furnishings"
        var item = Item()
        item.purchasePriceCents = 10_000

        #expect(InventoryPurchaseIntentCalculations.state(
            transaction: transaction,
            activeItems: [item],
            projectExists: true,
            categoryExists: true
        ) == .missingProjectPrices)
    }

    @Test("Planned inventory purchase is ready after destination and pricing validation")
    func plannedPurchaseIsReadyToSell() {
        var transaction = Transaction()
        transaction.intendedBudgetCategoryId = "furnishings"
        var item = Item()
        item.projectPriceCents = 15_000

        #expect(InventoryPurchaseIntentCalculations.state(
            transaction: transaction,
            activeItems: [item],
            projectExists: true,
            categoryExists: true
        ) == .readyToSell)
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

    @Test("Added items must continue to the inventory destination decision")
    func addedItemsCannotExitBeforeDestinationDecision() {
        #expect(ItemEntryFlowFooterResolver.addItems(itemCount: 2) == .continueToDestination)
    }

    @Test("Project-origin item entry defaults to adding all items to that project")
    func projectOriginDefaultsToProject() {
        #expect(ItemEntryFlowFooterResolver.sellPrompt(originProjectId: "project-123") == .addAllToOriginProject)
    }

    @Test("Inventory-origin item entry can keep items in inventory")
    func inventoryOriginDefaultsToInventory() {
        #expect(ItemEntryFlowFooterResolver.sellPrompt(originProjectId: nil) == .keepInInventory)
    }
}
