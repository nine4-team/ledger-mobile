import FirebaseFirestore

@MainActor
@Observable
final class InventoryContext {
    var items: [Item] = []
    var protoItems: [ProtoItem] = []
    var transactions: [Transaction] = []
    var spaces: [Space] = []

    var lastSelectedTab: Int {
        get { UserDefaults.standard.integer(forKey: "inventorySelectedTab") }
        set { UserDefaults.standard.set(newValue, forKey: "inventorySelectedTab") }
    }

    private var listeners: [ListenerRegistration] = []
    private var activeAccountId: String?
    private let itemsService: ItemsServiceProtocol
    private let protoItemsService: ProtoItemsServiceProtocol?
    private let transactionsService: TransactionsServiceProtocol
    private let spacesService: SpacesServiceProtocol

    init(
        itemsService: ItemsServiceProtocol,
        protoItemsService: ProtoItemsServiceProtocol? = nil,
        transactionsService: TransactionsServiceProtocol,
        spacesService: SpacesServiceProtocol
    ) {
        self.itemsService = itemsService
        self.protoItemsService = protoItemsService
        self.transactionsService = transactionsService
        self.spacesService = spacesService
    }

    /// Activate inventory-scoped subscriptions. Call from `.task` on InventoryView.
    func activate(accountId: String) {
        if activeAccountId == accountId, !listeners.isEmpty {
            return
        }

        deactivate()
        activeAccountId = accountId

        // 1. Items scoped to inventory (projectId == nil)
        listeners.append(
            itemsService.subscribeToItems(accountId: accountId, scope: .inventory) { [weak self] items in
                Task { @MainActor in self?.items = items }
            }
        )

        if let protoItemsService {
            listeners.append(
                protoItemsService.subscribeToProtoItems(accountId: accountId, scope: .inventory) { [weak self] protoItems in
                    Task { @MainActor in self?.protoItems = protoItems }
                }
            )
        }

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
        activeAccountId = nil
        items = []
        protoItems = []
        transactions = []
        spaces = []
    }
}
