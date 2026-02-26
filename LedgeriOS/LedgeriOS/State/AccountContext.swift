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

    private var listeners: [ListenerRegistration] = []
    private let accountsService: AccountsServiceProtocol
    private let membersService: AccountMembersServiceProtocol

    private static let lastAccountKey = "lastSelectedAccountId"

    var lastSelectedAccountId: String? {
        get { UserDefaults.standard.string(forKey: Self.lastAccountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastAccountKey) }
    }

    init(
        accountsService: AccountsServiceProtocol,
        membersService: AccountMembersServiceProtocol
    ) {
        self.accountsService = accountsService
        self.membersService = membersService
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
    }

    func deactivate() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        currentAccountId = nil
        account = nil
        member = nil
        discoveredAccounts = []
    }
}
