import Foundation
import Testing
import FirebaseFirestore
@testable import LedgeriOS

// MARK: - Mocks

private final class MockListenerRegistration: NSObject, ListenerRegistration {
    var removeCalled = false
    func remove() { removeCalled = true }
}

private struct MockAccountMembersService: AccountMembersServiceProtocol {
    var memberships: [AccountMember] = []
    var listError: Error?

    func subscribeToMember(accountId: String, userId: String, onChange: @escaping (AccountMember?) -> Void) -> ListenerRegistration {
        MockListenerRegistration()
    }

    func listMembershipsForUser(userId: String) async throws -> [AccountMember] {
        if let error = listError { throw error }
        return memberships.filter { $0.uid == userId }
    }
}

private struct MockAccountsService: AccountsServiceProtocol {
    var accounts: [String: Account] = [:]

    func getAccount(accountId: String) async throws -> Account? {
        accounts[accountId]
    }

    func subscribeToAccount(accountId: String, onChange: @escaping (Account?) -> Void) -> ListenerRegistration {
        onChange(accounts[accountId])
        return MockListenerRegistration()
    }
}

// MARK: - Tests

@Suite("Account Discovery Tests", .serialized)
struct AccountDiscoveryTests {

    private func makeMember(uid: String, accountId: String) -> AccountMember {
        var m = AccountMember()
        m.uid = uid
        m.accountId = accountId
        return m
    }

    private func makeAccount(id: String, name: String) -> Account {
        var a = Account()
        a.name = name
        return a
    }

    // MARK: - Discovery

    @Test("Single account found populates discoveredAccounts")
    @MainActor
    func singleAccountDiscovery() async {
        let membersService = MockAccountMembersService(
            memberships: [makeMember(uid: "user1", accountId: "acc1")]
        )
        var acct = makeAccount(id: "acc1", name: "My Business")
        let accountsService = MockAccountsService(
            accounts: ["acc1": acct]
        )

        let context = AccountContext(
            accountsService: accountsService,
            membersService: membersService
        )

        await context.discoverAccounts(userId: "user1")

        #expect(context.discoveredAccounts.count == 1)
        #expect(context.discoveredAccounts.first?.id == "acc1")
        #expect(context.discoveredAccounts.first?.name == "My Business")
        #expect(context.isDiscovering == false)
    }

    @Test("Zero accounts found results in empty discoveredAccounts")
    @MainActor
    func noAccountsDiscovery() async {
        let membersService = MockAccountMembersService(memberships: [])
        let accountsService = MockAccountsService(accounts: [:])

        let context = AccountContext(
            accountsService: accountsService,
            membersService: membersService
        )

        await context.discoverAccounts(userId: "user1")

        #expect(context.discoveredAccounts.isEmpty)
        #expect(context.isDiscovering == false)
    }

    @Test("Multiple accounts sorted with last-selected first")
    @MainActor
    func multipleAccountsSorted() async {
        let membersService = MockAccountMembersService(
            memberships: [
                makeMember(uid: "user1", accountId: "acc-a"),
                makeMember(uid: "user1", accountId: "acc-b"),
                makeMember(uid: "user1", accountId: "acc-c"),
            ]
        )
        let accountsService = MockAccountsService(
            accounts: [
                "acc-a": makeAccount(id: "acc-a", name: "Alpha Co"),
                "acc-b": makeAccount(id: "acc-b", name: "Beta Inc"),
                "acc-c": makeAccount(id: "acc-c", name: "Charlie LLC"),
            ]
        )

        let context = AccountContext(
            accountsService: accountsService,
            membersService: membersService
        )

        // Simulate last-selected being "acc-c"
        UserDefaults.standard.set("acc-c", forKey: "lastSelectedAccountId")
        defer { UserDefaults.standard.removeObject(forKey: "lastSelectedAccountId") }

        await context.discoverAccounts(userId: "user1")

        #expect(context.discoveredAccounts.count == 3)
        // Last-selected comes first
        #expect(context.discoveredAccounts[0].id == "acc-c")
        // Remaining sorted alphabetically
        #expect(context.discoveredAccounts[1].id == "acc-a")
        #expect(context.discoveredAccounts[2].id == "acc-b")
    }

    @Test("Discovery error results in empty discoveredAccounts")
    @MainActor
    func discoveryError() async {
        let membersService = MockAccountMembersService(
            listError: NSError(domain: "test", code: -1)
        )
        let accountsService = MockAccountsService(accounts: [:])

        let context = AccountContext(
            accountsService: accountsService,
            membersService: membersService
        )

        await context.discoverAccounts(userId: "user1")

        #expect(context.discoveredAccounts.isEmpty)
        #expect(context.isDiscovering == false)
    }

    // MARK: - Selection

    @Test("selectAccount sets currentAccountId and persists to UserDefaults")
    @MainActor
    func selectAccountPersists() {
        let accountsService = MockAccountsService(accounts: [:])
        let membersService = MockAccountMembersService(memberships: [])

        let context = AccountContext(
            accountsService: accountsService,
            membersService: membersService
        )

        defer { UserDefaults.standard.removeObject(forKey: "lastSelectedAccountId") }

        context.selectAccount(accountId: "acc-xyz", userId: "user1")

        #expect(context.currentAccountId == "acc-xyz")
        #expect(UserDefaults.standard.string(forKey: "lastSelectedAccountId") == "acc-xyz")
    }

    // MARK: - Deactivate

    @Test("deactivate clears all state including discoveredAccounts")
    @MainActor
    func deactivateClearsAll() async {
        let membersService = MockAccountMembersService(
            memberships: [makeMember(uid: "user1", accountId: "acc1")]
        )
        let accountsService = MockAccountsService(
            accounts: ["acc1": makeAccount(id: "acc1", name: "Biz")]
        )

        let context = AccountContext(
            accountsService: accountsService,
            membersService: membersService
        )

        await context.discoverAccounts(userId: "user1")

        #expect(!context.discoveredAccounts.isEmpty)

        context.selectAccount(accountId: "acc1", userId: "user1")

        #expect(context.currentAccountId == "acc1")

        context.deactivate()

        #expect(context.currentAccountId == nil)
        #expect(context.account == nil)
        #expect(context.member == nil)
        #expect(context.discoveredAccounts.isEmpty)
    }
}
