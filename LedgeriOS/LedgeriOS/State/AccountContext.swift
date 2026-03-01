import FirebaseFirestore

struct DiscoveredAccount: Identifiable {
    let id: String
    let name: String
}

@MainActor
@Observable
final class AccountContext {
    var currentAccountId: String?
    var account: Account?
    var member: AccountMember?

    var discoveredAccounts: [DiscoveredAccount] = []
    var isDiscovering = false

    // Cross-project data for universal search
    var allItems: [Item] = []
    var allTransactions: [Transaction] = []
    var allSpaces: [Space] = []
    var allBudgetCategories: [BudgetCategory] = []

    private var listeners: [ListenerRegistration] = []
    private let accountsService: AccountsServiceProtocol
    private let membersService: AccountMembersServiceProtocol
    private let itemsService: ItemsServiceProtocol?
    private let transactionsService: TransactionsServiceProtocol?
    private let spacesService: SpacesServiceProtocol?
    private let budgetCategoriesService: BudgetCategoriesServiceProtocol?

    private static let lastAccountKey = "lastSelectedAccountId"

    var lastSelectedAccountId: String? {
        get { UserDefaults.standard.string(forKey: Self.lastAccountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastAccountKey) }
    }

    init(
        accountsService: AccountsServiceProtocol,
        membersService: AccountMembersServiceProtocol,
        itemsService: ItemsServiceProtocol? = nil,
        transactionsService: TransactionsServiceProtocol? = nil,
        spacesService: SpacesServiceProtocol? = nil,
        budgetCategoriesService: BudgetCategoriesServiceProtocol? = nil
    ) {
        self.accountsService = accountsService
        self.membersService = membersService
        self.itemsService = itemsService
        self.transactionsService = transactionsService
        self.spacesService = spacesService
        self.budgetCategoriesService = budgetCategoriesService
    }

    // MARK: - Discovery

    func discoverAccounts(userId: String) async {
        isDiscovering = true
        defer { isDiscovering = false }

        do {
            let memberships = try await membersService.listMembershipsForUser(userId: userId)

            var accounts: [DiscoveredAccount] = []
            for membership in memberships {
                guard let accountId = membership.accountId else { continue }
                let account = try await accountsService.getAccount(accountId: accountId)
                let name = account?.name ?? "(unnamed)"
                accounts.append(DiscoveredAccount(id: accountId, name: name))
            }

            // Sort: last-selected first, then alphabetical
            let lastId = lastSelectedAccountId
            accounts.sort { lhs, rhs in
                if lhs.id == lastId { return true }
                if rhs.id == lastId { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            discoveredAccounts = accounts
        } catch {
            discoveredAccounts = []
        }
    }

    // MARK: - Selection

    func selectAccount(accountId: String, userId: String) {
        lastSelectedAccountId = accountId
        activate(accountId: accountId, userId: userId)
    }

    func activate(accountId: String, userId: String) {
        deactivate()
        currentAccountId = accountId

        let accountListener = accountsService.subscribeToAccount(accountId: accountId) { [weak self] account in
            Task { @MainActor in
                self?.account = account
            }
        }
        listeners.append(accountListener)

        let memberListener = membersService.subscribeToMember(accountId: accountId, userId: userId) { [weak self] member in
            Task { @MainActor in
                self?.member = member
            }
        }
        listeners.append(memberListener)

        // Cross-project subscriptions for universal search
        if let itemsService {
            let itemsListener = itemsService.subscribeToItems(accountId: accountId, scope: .all) { [weak self] items in
                Task { @MainActor in self?.allItems = items }
            }
            listeners.append(itemsListener)
        }

        if let transactionsService {
            let txListener = transactionsService.subscribeToTransactions(accountId: accountId, scope: .all) { [weak self] transactions in
                Task { @MainActor in self?.allTransactions = transactions }
            }
            listeners.append(txListener)
        }

        if let spacesService {
            let spacesListener = spacesService.subscribeToSpaces(accountId: accountId, scope: .all) { [weak self] spaces in
                Task { @MainActor in self?.allSpaces = spaces }
            }
            listeners.append(spacesListener)
        }

        if let budgetCategoriesService {
            let categoriesListener = budgetCategoriesService.subscribeToBudgetCategories(accountId: accountId) { [weak self] categories in
                Task { @MainActor in self?.allBudgetCategories = categories }
            }
            listeners.append(categoriesListener)
        }
    }

    func deactivate() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        currentAccountId = nil
        account = nil
        member = nil
        discoveredAccounts = []
        allItems = []
        allTransactions = []
        allSpaces = []
        allBudgetCategories = []
    }
}
