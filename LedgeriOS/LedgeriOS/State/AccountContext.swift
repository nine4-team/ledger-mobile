import FirebaseFirestore

@MainActor
@Observable
final class AccountContext {
    var currentAccountId: String?
    var account: Account?
    var member: AccountMember?

    private var listeners: [ListenerRegistration] = []
    private let accountsService: AccountsServiceProtocol
    private let membersService: AccountMembersServiceProtocol

    init(
        accountsService: AccountsServiceProtocol,
        membersService: AccountMembersServiceProtocol
    ) {
        self.accountsService = accountsService
        self.membersService = membersService
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
    }
}
