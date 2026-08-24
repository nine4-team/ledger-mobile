import Foundation
import Testing
import FirebaseFirestore
@testable import LedgeriOS

private final class CountingListenerRegistration: NSObject, ListenerRegistration, @unchecked Sendable {
    private let onRemove: @Sendable () -> Void

    init(onRemove: @escaping @Sendable () -> Void = {}) {
        self.onRemove = onRemove
    }

    func remove() {
        onRemove()
    }
}

private final class ListenerCounter: @unchecked Sendable {
    var accountSubscriptions = 0
    var memberSubscriptions = 0
    var projectListSubscriptions = 0
    var projectDetailSubscriptions = 0
    var itemSubscriptions = 0
    var transactionSubscriptions = 0
    var spaceSubscriptions = 0
    var budgetCategorySubscriptions = 0
    var projectBudgetCategorySubscriptions = 0
    var feeInstallmentSubscriptions = 0
    var noteSubscriptions = 0
    var removeCalls = 0
}

private struct LifecycleAccountsService: AccountsServiceProtocol {
    let counter: ListenerCounter

    func getAccount(accountId: String) async throws -> Account? { nil }
    func createAccount(name: String) async throws -> String { "account" }
    func updateAccount(accountId: String, fields: [String: Any]) async throws {}

    func subscribeToAccount(accountId: String, onChange: @escaping (Account?) -> Void) -> ListenerRegistration {
        counter.accountSubscriptions += 1
        onChange(Account())
        return CountingListenerRegistration { counter.removeCalls += 1 }
    }
}

private struct LifecycleMembersService: AccountMembersServiceProtocol {
    let counter: ListenerCounter

    func subscribeToMember(accountId: String, userId: String, onChange: @escaping (AccountMember?) -> Void) -> ListenerRegistration {
        counter.memberSubscriptions += 1
        onChange(AccountMember())
        return CountingListenerRegistration { counter.removeCalls += 1 }
    }

    func listMembershipsForUser(userId: String) async throws -> [AccountMember] { [] }
    func updateAccess(
        accountId: String,
        userId: String,
        role: MemberRole,
        companyFinancialAccess: CompanyFinancialAccess,
        allowedFeeCategoryIds: [String]
    ) async throws {}
}

private struct LifecycleProjectService: ProjectServiceProtocol {
    let counter: ListenerCounter

    func getProject(accountId: String, projectId: String) async throws -> Project? { nil }
    func createProject(accountId: String, name: String, clientName: String, description: String?, notes: String?) throws -> String { "project" }
    func updateProject(accountId: String, projectId: String, fields: [String: Any]) async throws {}
    func deleteProject(accountId: String, projectId: String) async throws {}

    func subscribeToProjects(accountId: String, onChange: @escaping ([Project]) -> Void) -> ListenerRegistration {
        counter.projectListSubscriptions += 1
        onChange([])
        return CountingListenerRegistration { counter.removeCalls += 1 }
    }

    func subscribeToProject(accountId: String, projectId: String, onChange: @escaping (Project?) -> Void) -> ListenerRegistration {
        counter.projectDetailSubscriptions += 1
        onChange(Project())
        return CountingListenerRegistration { counter.removeCalls += 1 }
    }
}

private struct LifecycleItemsService: ItemsServiceProtocol {
    let counter: ListenerCounter

    func getItem(accountId: String, itemId: String) async throws -> Item? { nil }
    func createItem(accountId: String, item: Item) throws -> String { "item" }
    func createItemsForTransaction(
        accountId: String,
        transactionId: String,
        budgetCategoryId: String,
        items: [Item],
        onCommitError: @escaping @Sendable ([String], Error) -> Void
    ) throws -> [Item] { [] }
    func updateItem(accountId: String, itemId: String, fields: [String: Any]) async throws {}
    func deleteItem(accountId: String, item: Item) async throws {}
    func deleteItems(accountId: String, items: [Item]) async throws {}

    func subscribeToItems(accountId: String, scope: ListScope, onChange: @escaping ([Item]) -> Void) -> ListenerRegistration {
        counter.itemSubscriptions += 1
        onChange([])
        return CountingListenerRegistration { counter.removeCalls += 1 }
    }

    func subscribeToItem(accountId: String, itemId: String, onChange: @escaping (Item?) -> Void) -> ListenerRegistration {
        CountingListenerRegistration()
    }
}

private struct LifecycleTransactionsService: TransactionsServiceProtocol {
    let counter: ListenerCounter

    func getTransaction(accountId: String, transactionId: String) async throws -> LedgeriOS.Transaction? { nil }
    func createTransaction(accountId: String, transaction: LedgeriOS.Transaction) throws -> String { "transaction" }
    func updateTransaction(accountId: String, transactionId: String, fields: [String: Any]) async throws {}
    func deleteTransaction(accountId: String, transactionId: String) async throws {}

    func subscribeToTransactions(accountId: String, scope: ListScope, onChange: @escaping ([LedgeriOS.Transaction]) -> Void) -> ListenerRegistration {
        counter.transactionSubscriptions += 1
        onChange([])
        return CountingListenerRegistration { counter.removeCalls += 1 }
    }

    func subscribeToTransaction(accountId: String, transactionId: String, onChange: @escaping (LedgeriOS.Transaction?) -> Void) -> ListenerRegistration {
        CountingListenerRegistration()
    }
}

private struct LifecycleSpacesService: SpacesServiceProtocol {
    let counter: ListenerCounter

    func getSpace(accountId: String, spaceId: String) async throws -> Space? { nil }
    func createSpace(accountId: String, space: Space) throws -> String { "space" }
    func updateSpace(accountId: String, spaceId: String, fields: [String: Any]) async throws {}
    func deleteSpace(accountId: String, spaceId: String) async throws {}

    func subscribeToSpaces(accountId: String, scope: ListScope, onChange: @escaping ([Space]) -> Void) -> ListenerRegistration {
        counter.spaceSubscriptions += 1
        onChange([])
        return CountingListenerRegistration { counter.removeCalls += 1 }
    }

    func subscribeToSpace(accountId: String, spaceId: String, onChange: @escaping (Space?) -> Void) -> ListenerRegistration {
        CountingListenerRegistration()
    }
}

private struct LifecycleBudgetCategoriesService: BudgetCategoriesServiceProtocol {
    let counter: ListenerCounter

    func subscribeToBudgetCategories(accountId: String, onChange: @escaping ([BudgetCategory]) -> Void) -> ListenerRegistration {
        counter.budgetCategorySubscriptions += 1
        onChange([])
        return CountingListenerRegistration { counter.removeCalls += 1 }
    }

    func createBudgetCategory(accountId: String, category: BudgetCategory) throws -> String { "category" }
    func updateBudgetCategory(accountId: String, categoryId: String, fields: [String: Any]) async throws {}
    func deleteBudgetCategory(accountId: String, categoryId: String) async throws {}
}

private struct LifecycleProjectBudgetCategoriesService: ProjectBudgetCategoriesServiceProtocol {
    let counter: ListenerCounter

    func subscribeToProjectBudgetCategories(accountId: String, projectId: String, onChange: @escaping ([ProjectBudgetCategory]) -> Void) -> ListenerRegistration {
        counter.projectBudgetCategorySubscriptions += 1
        onChange([])
        return CountingListenerRegistration { counter.removeCalls += 1 }
    }

    func setProjectBudgetCategory(accountId: String, projectId: String, categoryId: String, budgetCents: Int, userId: String?) async throws {}
    func deleteProjectBudgetCategory(accountId: String, projectId: String, categoryId: String) async throws {}
}

private struct LifecycleFeeInstallmentsService: FeeInstallmentsServiceProtocol {
    let counter: ListenerCounter

    func subscribeToFeeInstallments(accountId: String, projectId: String, onChange: @escaping ([FeeInstallment]) -> Void) -> ListenerRegistration {
        counter.feeInstallmentSubscriptions += 1
        onChange([])
        return CountingListenerRegistration { counter.removeCalls += 1 }
    }

    func createFeeInstallment(
        accountId: String,
        projectId: String,
        budgetCategoryId: String,
        label: String,
        amountCents: Int,
        sortOrder: Int?,
        projectBudgetCategory: ProjectBudgetCategory?,
        existingInstallments: [FeeInstallment],
        userId: String?
    ) async throws -> String { "fee-installment" }

    func updateFeeInstallment(
        accountId: String,
        projectId: String,
        installmentId: String,
        budgetCategoryId: String,
        label: String,
        amountCents: Int,
        sortOrder: Int?,
        projectBudgetCategory: ProjectBudgetCategory?,
        existingInstallments: [FeeInstallment],
        userId: String?
    ) async throws {}

    func deleteFeeInstallment(accountId: String, projectId: String, installmentId: String) async throws {}
}

private struct LifecycleProjectNotesService: ProjectNotesServiceProtocol {
    let counter: ListenerCounter

    func subscribeToProjectNotes(accountId: String, projectId: String, onChange: @escaping ([ProjectNote]) -> Void) -> ListenerRegistration {
        counter.noteSubscriptions += 1
        onChange([])
        return CountingListenerRegistration { counter.removeCalls += 1 }
    }

    func addProjectNote(accountId: String, projectId: String, note: ProjectNote) async throws {}
    func updateProjectNote(accountId: String, projectId: String, noteId: String, fields: [String: Any]) async throws {}
    func deleteProjectNote(accountId: String, projectId: String, noteId: String) async throws {}
}

@MainActor
private func makeAccountContext(counter: ListenerCounter) -> AccountContext {
    AccountContext(
        accountsService: LifecycleAccountsService(counter: counter),
        membersService: LifecycleMembersService(counter: counter),
        itemsService: LifecycleItemsService(counter: counter),
        transactionsService: LifecycleTransactionsService(counter: counter),
        spacesService: LifecycleSpacesService(counter: counter),
        budgetCategoriesService: LifecycleBudgetCategoriesService(counter: counter),
        projectService: LifecycleProjectService(counter: counter)
    )
}

@MainActor
private func makeProjectContext(counter: ListenerCounter) -> ProjectContext {
    ProjectContext(
        projectService: LifecycleProjectService(counter: counter),
        transactionsService: LifecycleTransactionsService(counter: counter),
        itemsService: LifecycleItemsService(counter: counter),
        spacesService: LifecycleSpacesService(counter: counter),
        budgetCategoriesService: LifecycleBudgetCategoriesService(counter: counter),
        projectBudgetCategoriesService: LifecycleProjectBudgetCategoriesService(counter: counter),
        feeInstallmentsService: LifecycleFeeInstallmentsService(counter: counter),
        projectNotesService: LifecycleProjectNotesService(counter: counter)
    )
}

@MainActor
private func makeInventoryContext(counter: ListenerCounter) -> InventoryContext {
    InventoryContext(
        itemsService: LifecycleItemsService(counter: counter),
        transactionsService: LifecycleTransactionsService(counter: counter),
        spacesService: LifecycleSpacesService(counter: counter)
    )
}

@Suite("Loading Lifecycle Tests", .serialized)
struct LoadingLifecycleTests {
    @Test("Account lookup indexes track published collection replacement")
    @MainActor
    func accountLookupIndexesStayFresh() {
        let context = makeAccountContext(counter: ListenerCounter())
        var space = Space()
        space.id = "space-1"
        space.name = "Living Room"
        var category = BudgetCategory()
        category.id = "category-1"
        category.name = "Furniture"
        var invoice = Invoice()
        invoice.status = .sent
        invoice.itemIds = ["item-1"]

        context.allSpaces = [space]
        context.allBudgetCategories = [category]
        context.allInvoices = [invoice]

        #expect(context.spaceName(for: "space-1") == "Living Room")
        #expect(context.budgetCategoryName(for: "category-1") == "Furniture")
        #expect(context.invoiceStatus(forItemId: "item-1") == .sent)

        context.allSpaces = []
        context.allBudgetCategories = []
        context.allInvoices = []

        #expect(context.spaceName(for: "space-1") == nil)
        #expect(context.budgetCategoryName(for: "category-1") == nil)
        #expect(context.invoiceStatus(forItemId: "item-1") == nil)
    }

    @Test("AccountContext re-activating same account and user keeps existing listeners")
    @MainActor
    func accountActivationIsIdempotentForSameAccountAndUser() {
        let counter = ListenerCounter()
        let context = makeAccountContext(counter: counter)

        context.activate(accountId: "account-1", userId: "user-1")
        context.activate(accountId: "account-1", userId: "user-1")

        #expect(counter.accountSubscriptions == 1)
        #expect(counter.memberSubscriptions == 1)
        #expect(counter.projectListSubscriptions == 1)
        #expect(counter.itemSubscriptions == 1)
        #expect(counter.transactionSubscriptions == 1)
        #expect(counter.spaceSubscriptions == 1)
        #expect(counter.budgetCategorySubscriptions == 1)
        #expect(counter.removeCalls == 0)
    }

    @Test("AccountContext switching account tears down old listeners and starts new ones")
    @MainActor
    func accountSwitchRestartsListeners() {
        let counter = ListenerCounter()
        let context = makeAccountContext(counter: counter)

        context.activate(accountId: "account-1", userId: "user-1")
        context.activate(accountId: "account-2", userId: "user-1")

        #expect(counter.accountSubscriptions == 2)
        #expect(counter.memberSubscriptions == 2)
        #expect(counter.projectListSubscriptions == 2)
        #expect(counter.removeCalls == 7)
    }

    @Test("ProjectContext re-activating same project keeps project listeners and cached data")
    @MainActor
    func projectActivationIsIdempotentForSameProject() {
        let counter = ListenerCounter()
        let context = makeProjectContext(counter: counter)

        context.activate(accountId: "account-1", projectId: "project-1")
        context.items = [Item()]
        context.activate(accountId: "account-1", projectId: "project-1")

        #expect(counter.projectDetailSubscriptions == 1)
        #expect(counter.projectListSubscriptions == 1)
        #expect(counter.itemSubscriptions == 1)
        #expect(counter.transactionSubscriptions == 1)
        #expect(counter.spaceSubscriptions == 1)
        #expect(counter.budgetCategorySubscriptions == 1)
        #expect(counter.projectBudgetCategorySubscriptions == 1)
        #expect(counter.feeInstallmentSubscriptions == 1)
        #expect(counter.noteSubscriptions == 1)
        #expect(counter.removeCalls == 0)
        #expect(context.items.count == 1)
    }

    @Test("ProjectContext switching project tears down old listeners and clears project state")
    @MainActor
    func projectSwitchRestartsListenersAndClearsState() {
        let counter = ListenerCounter()
        let context = makeProjectContext(counter: counter)

        context.activate(accountId: "account-1", projectId: "project-1")
        context.items = [Item()]
        context.activate(accountId: "account-1", projectId: "project-2")

        #expect(counter.projectDetailSubscriptions == 2)
        #expect(counter.projectListSubscriptions == 2)
        #expect(counter.itemSubscriptions == 2)
        #expect(counter.transactionSubscriptions == 2)
        #expect(counter.spaceSubscriptions == 2)
        #expect(counter.budgetCategorySubscriptions == 2)
        #expect(counter.projectBudgetCategorySubscriptions == 2)
        #expect(counter.feeInstallmentSubscriptions == 2)
        #expect(counter.noteSubscriptions == 2)
        #expect(counter.removeCalls == 9)
        #expect(context.currentProjectId == "project-2")
        #expect(context.items.isEmpty)
    }

    @Test("Separate ProjectContext instances keep independent active projects")
    @MainActor
    func separateProjectContextsDoNotClearEachOther() {
        let counter = ListenerCounter()
        let first = makeProjectContext(counter: counter)
        let second = makeProjectContext(counter: counter)

        first.activate(accountId: "account-1", projectId: "project-1")
        first.items = [Item()]

        second.activate(accountId: "account-1", projectId: "project-2")

        #expect(first.currentProjectId == "project-1")
        #expect(second.currentProjectId == "project-2")
        #expect(first.items.count == 1)
        #expect(counter.projectDetailSubscriptions == 2)
        #expect(counter.projectBudgetCategorySubscriptions == 2)
        #expect(counter.feeInstallmentSubscriptions == 2)
        #expect(counter.removeCalls == 0)
    }

    @Test("Destroying ProjectContext tears down every active listener")
    @MainActor
    func projectContextDestructionStopsListeners() {
        let counter = ListenerCounter()
        weak var releasedContext: ProjectContext?

        do {
            let context = makeProjectContext(counter: counter)
            releasedContext = context
            context.activate(accountId: "account-1", projectId: "project-1")
            #expect(counter.removeCalls == 0)
        }

        #expect(releasedContext == nil)
        #expect(counter.removeCalls == 9)
    }

    @Test("InventoryContext re-activating same account keeps existing listeners")
    @MainActor
    func inventoryActivationIsIdempotentForSameAccount() {
        let counter = ListenerCounter()
        let context = makeInventoryContext(counter: counter)

        context.activate(accountId: "account-1")
        context.items = [Item()]
        context.activate(accountId: "account-1")

        #expect(counter.itemSubscriptions == 1)
        #expect(counter.transactionSubscriptions == 1)
        #expect(counter.spaceSubscriptions == 1)
        #expect(counter.removeCalls == 0)
        #expect(context.items.count == 1)
    }

    @Test("InventoryContext switching account tears down old listeners and clears state")
    @MainActor
    func inventorySwitchRestartsListenersAndClearsState() {
        let counter = ListenerCounter()
        let context = makeInventoryContext(counter: counter)

        context.activate(accountId: "account-1")
        context.items = [Item()]
        context.activate(accountId: "account-2")

        #expect(counter.itemSubscriptions == 2)
        #expect(counter.transactionSubscriptions == 2)
        #expect(counter.spaceSubscriptions == 2)
        #expect(counter.removeCalls == 3)
        #expect(context.items.isEmpty)
    }
}
