import FirebaseFirestore

struct DiscoveredAccount: Identifiable {
    let id: String
    let name: String
}

enum AccountLookupIndex {
    static func spaceNames(_ spaces: [Space]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: spaces.compactMap { space in
            space.id.map { ($0, space.name) }
        })
    }

    static func categoryNames(_ categories: [BudgetCategory]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: categories.compactMap { category in
            category.id.map { ($0, category.name) }
        })
    }

    static func invoiceStatusesByItemId(_ invoices: [Invoice]) -> [String: InvoiceStatus] {
        var result: [String: InvoiceStatus] = [:]
        for invoice in invoices where invoice.status != .canceled {
            let status = invoice.status ?? .created
            for itemId in invoice.itemIds ?? [] {
                let existing = result[itemId]
                if status == .paid || existing == nil || (existing == .created && status == .sent) {
                    result[itemId] = status
                }
            }
        }
        return result
    }
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
    var allProtoItems: [ProtoItem] = []
    var allTransactions: [Transaction] = []
    var allSpaces: [Space] = [] {
        didSet { spaceNameById = AccountLookupIndex.spaceNames(allSpaces) }
    }
    var allBudgetCategories: [BudgetCategory] = [] {
        didSet { budgetCategoryNameById = AccountLookupIndex.categoryNames(allBudgetCategories) }
    }
    var allProjects: [Project] = []
    var allInvoices: [Invoice] = [] {
        didSet { invoiceStatusByItemId = AccountLookupIndex.invoiceStatusesByItemId(allInvoices) }
    }

    private var spaceNameById: [String: String] = [:]
    private var budgetCategoryNameById: [String: String] = [:]
    private var invoiceStatusByItemId: [String: InvoiceStatus] = [:]

    private var rawAllTransactions: [Transaction] = []
    private var rawAllBudgetCategories: [BudgetCategory] = []
    private var rawAllInvoices: [Invoice] = []
    private var activeUserId: String?
    private var listeners: [ListenerRegistration] = []
    private let accountsService: AccountsServiceProtocol
    private let membersService: AccountMembersServiceProtocol
    private let itemsService: ItemsServiceProtocol?
    private let protoItemsService: ProtoItemsServiceProtocol?
    private let transactionsService: TransactionsServiceProtocol?
    private let spacesService: SpacesServiceProtocol?
    private let budgetCategoriesService: BudgetCategoriesServiceProtocol?
    private let projectService: ProjectServiceProtocol?
    private let invoicesService: InvoiceServiceProtocol?

    private static let lastAccountKey = "lastSelectedAccountId"

    func spaceName(for id: String) -> String? {
        spaceNameById[id]
    }

    func budgetCategoryName(for id: String) -> String? {
        budgetCategoryNameById[id]
    }

    func invoiceStatus(forItemId id: String) -> InvoiceStatus? {
        invoiceStatusByItemId[id]
    }

    var lastSelectedAccountId: String? {
        get { UserDefaults.standard.string(forKey: Self.lastAccountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastAccountKey) }
    }

    init(
        accountsService: AccountsServiceProtocol,
        membersService: AccountMembersServiceProtocol,
        itemsService: ItemsServiceProtocol? = nil,
        protoItemsService: ProtoItemsServiceProtocol? = nil,
        transactionsService: TransactionsServiceProtocol? = nil,
        spacesService: SpacesServiceProtocol? = nil,
        budgetCategoriesService: BudgetCategoriesServiceProtocol? = nil,
        projectService: ProjectServiceProtocol? = nil,
        invoicesService: InvoiceServiceProtocol? = nil
    ) {
        self.accountsService = accountsService
        self.membersService = membersService
        self.itemsService = itemsService
        self.protoItemsService = protoItemsService
        self.transactionsService = transactionsService
        self.spacesService = spacesService
        self.budgetCategoriesService = budgetCategoriesService
        self.projectService = projectService
        self.invoicesService = invoicesService
    }

    // MARK: - Discovery

    func discoverAccounts(userId: String) async {
        print("🟡 discoverAccounts called for userId: \(userId)")
        isDiscovering = true
        defer { isDiscovering = false }

        do {
            let memberships = try await membersService.listMembershipsForUser(userId: userId)
            print("🟡 memberships returned: \(memberships.count)")

            var accounts: [DiscoveredAccount] = []
            for membership in memberships {
                guard let accountId = membership.accountId else {
                    print("🟡 membership skipped — nil accountId: \(membership)")
                    continue
                }
                let account = try await accountsService.getAccount(accountId: accountId)
                let name = account?.name ?? "(unnamed)"
                print("🟡 resolved account: \(accountId) → \(name)")
                accounts.append(DiscoveredAccount(id: accountId, name: name))
            }

            // Sort: last-selected first, then alphabetical
            let lastId = lastSelectedAccountId
            accounts.sort { lhs, rhs in
                if lhs.id == lastId { return true }
                if rhs.id == lastId { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            print("🟡 discoverAccounts result: \(accounts.count) accounts")
            discoveredAccounts = accounts
        } catch {
            print("🔴 discoverAccounts failed: \(error)")
            discoveredAccounts = []
        }
    }

    // MARK: - Selection

    func selectAccount(accountId: String, userId: String) {
        lastSelectedAccountId = accountId
        activate(accountId: accountId, userId: userId)
    }

    func createAccount(name: String, userId: String) async throws {
        let accountId = try await accountsService.createAccount(name: name)
        await discoverAccounts(userId: userId)
        selectAccount(accountId: accountId, userId: userId)
    }

    func activate(accountId: String, userId: String) {
        if currentAccountId == accountId, activeUserId == userId, !listeners.isEmpty {
            PerformanceDiagnostics.shared.event("ContextActivationEarlyReturn", kind: "account", count: listeners.count)
            return
        }

        PerformanceDiagnostics.shared.event("ContextActivationStart", kind: "account", count: listeners.count)

        // Stop listeners and clear data without touching currentAccountId/discoveredAccounts
        // to avoid triggering a RootView re-render back to AccountGateView.
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        account = nil
        member = nil
        allItems = []
        allProtoItems = []
        allTransactions = []
        allSpaces = []
        allBudgetCategories = []
        allProjects = []
        allInvoices = []
        rawAllTransactions = []
        rawAllBudgetCategories = []
        rawAllInvoices = []

        currentAccountId = accountId
        activeUserId = userId

        let accountListener = accountsService.subscribeToAccount(accountId: accountId) { [weak self] account in
            let receivedAt = DispatchTime.now().uptimeNanoseconds
            Task { @MainActor in
                guard let self else { return }
                self.publish(kind: "account.account", receivedAt: receivedAt, count: account == nil ? 0 : 1) {
                    self.account = account
                }
            }
        }
        listeners.append(accountListener)

        let memberListener = membersService.subscribeToMember(accountId: accountId, userId: userId) { [weak self] member in
            let receivedAt = DispatchTime.now().uptimeNanoseconds
            Task { @MainActor in
                guard let self else { return }
                self.publish(kind: "account.member", receivedAt: receivedAt, count: member == nil ? 0 : 1) {
                    self.member = member
                    self.applyFinancialAccess()
                }
            }
        }
        listeners.append(memberListener)

        // Cross-project subscriptions for universal search
        if let itemsService {
            let itemsListener = itemsService.subscribeToItems(accountId: accountId, scope: .all) { [weak self] items in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "account.items", receivedAt: receivedAt, count: items.count) {
                        self.allItems = items
                    }
                }
            }
            listeners.append(itemsListener)
        }

        if let protoItemsService {
            let protoItemsListener = protoItemsService.subscribeToProtoItems(accountId: accountId, scope: .all) { [weak self] protoItems in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "account.proto-items", receivedAt: receivedAt, count: protoItems.count) {
                        self.allProtoItems = protoItems
                    }
                }
            }
            listeners.append(protoItemsListener)
        }

        if let transactionsService {
            let txListener = transactionsService.subscribeToTransactions(accountId: accountId, scope: .all) { [weak self] transactions in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "account.transactions", receivedAt: receivedAt, count: transactions.count) {
                        self.rawAllTransactions = transactions
                        self.applyFinancialAccess()
                    }
                }
            }
            listeners.append(txListener)
        }

        if let spacesService {
            let spacesListener = spacesService.subscribeToSpaces(accountId: accountId, scope: .all) { [weak self] spaces in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "account.spaces", receivedAt: receivedAt, count: spaces.count) {
                        self.allSpaces = spaces
                    }
                }
            }
            listeners.append(spacesListener)
        }

        if let budgetCategoriesService {
            let categoriesListener = budgetCategoriesService.subscribeToBudgetCategories(accountId: accountId) { [weak self] categories in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "account.categories", receivedAt: receivedAt, count: categories.count) {
                        self.rawAllBudgetCategories = categories
                        self.applyFinancialAccess()
                    }
                }
            }
            listeners.append(categoriesListener)
        }

        if let projectService {
            let projectsListener = projectService.subscribeToProjects(accountId: accountId) { [weak self] projects in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "account.projects", receivedAt: receivedAt, count: projects.count) {
                        self.allProjects = projects
                    }
                }
            }
            listeners.append(projectsListener)
        }

        if let invoicesService {
            let invoicesListener = invoicesService.subscribeToInvoices(accountId: accountId) { [weak self] invoices in
                let receivedAt = DispatchTime.now().uptimeNanoseconds
                Task { @MainActor in
                    guard let self else { return }
                    self.publish(kind: "account.invoices", receivedAt: receivedAt, count: invoices.count) {
                        self.rawAllInvoices = invoices
                        self.applyFinancialAccess()
                    }
                }
            }
            listeners.append(invoicesListener)
        }
        PerformanceDiagnostics.shared.event("ContextActivationComplete", kind: "account", count: listeners.count)
    }

    func deactivate() {
        PerformanceDiagnostics.shared.event("ContextDeactivated", kind: "account", count: listeners.count)
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        lastSelectedAccountId = nil
        currentAccountId = nil
        activeUserId = nil
        account = nil
        member = nil
        discoveredAccounts = []
        allItems = []
        allProtoItems = []
        allTransactions = []
        allSpaces = []
        allBudgetCategories = []
        allProjects = []
        allInvoices = []
        rawAllTransactions = []
        rawAllBudgetCategories = []
        rawAllInvoices = []
    }

    private func applyFinancialAccess() {
        let interval = PerformanceDiagnostics.shared.beginInterval(
            "FinancialAccess",
            kind: "account",
            count: rawAllTransactions.count + rawAllBudgetCategories.count + rawAllInvoices.count
        )
        let policy = FinancialAccessPolicy(member: member)
        allBudgetCategories = policy.visibleCategories(rawAllBudgetCategories)
        allTransactions = policy.visibleTransactions(rawAllTransactions, categories: rawAllBudgetCategories)
        allInvoices = policy.visibleInvoices(
            rawAllInvoices,
            transactions: rawAllTransactions,
            categories: rawAllBudgetCategories
        )
        PerformanceDiagnostics.shared.endInterval(
            interval,
            value: allTransactions.count + allBudgetCategories.count + allInvoices.count
        )
    }

    private func publish(kind: String, receivedAt: UInt64, count: Int, update: () -> Void) {
        let queueDelayMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - receivedAt) / 1_000_000
        PerformanceDiagnostics.shared.duration(
            "MainActorDelivery",
            kind: kind,
            milliseconds: queueDelayMilliseconds,
            count: count
        )
        let interval = PerformanceDiagnostics.shared.beginInterval("ContextPublish", kind: kind, count: count)
        update()
        PerformanceDiagnostics.shared.endInterval(interval)
    }
}
