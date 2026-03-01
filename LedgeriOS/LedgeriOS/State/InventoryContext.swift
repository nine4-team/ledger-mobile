import FirebaseFirestore

@MainActor
@Observable
final class InventoryContext {
    var items: [Item] = []
    var transactions: [Transaction] = []
    var spaces: [Space] = []

    var lastSelectedTab: Int {
        get { UserDefaults.standard.integer(forKey: "inventorySelectedTab") }
        set { UserDefaults.standard.set(newValue, forKey: "inventorySelectedTab") }
    }

    private var listeners: [ListenerRegistration] = []
    private let itemsService: ItemsServiceProtocol
    private let transactionsService: TransactionsServiceProtocol
    private let spacesService: SpacesServiceProtocol

    init(
        itemsService: ItemsServiceProtocol,
        transactionsService: TransactionsServiceProtocol,
        spacesService: SpacesServiceProtocol
    ) {
        self.itemsService = itemsService
        self.transactionsService = transactionsService
        self.spacesService = spacesService
    }

    /// Activate inventory-scoped subscriptions. Call from `.task` on InventoryView.
    func activate(accountId: String) {
        deactivate()

        // 1. Items scoped to inventory (projectId == nil)
        listeners.append(
            itemsService.subscribeToItems(accountId: accountId, scope: .inventory) { [weak self] items in
                Task { @MainActor in self?.items = items }
            }
        )

        // 2. Transactions scoped to inventory
        listeners.append(
            transactionsService.subscribeToTransactions(accountId: accountId, scope: .inventory) { [weak self] transactions in
                Task { @MainActor in self?.transactions = transactions }
            }
        )

        // 3. Spaces scoped to inventory
        listeners.append(
            spacesService.subscribeToSpaces(accountId: accountId, scope: .inventory) { [weak self] spaces in
                Task { @MainActor in self?.spaces = spaces }
            }
        )
    }

    func deactivate() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        items = []
        transactions = []
        spaces = []
    }
}
