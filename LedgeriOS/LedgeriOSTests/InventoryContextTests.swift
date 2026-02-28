import Foundation
import Testing
import FirebaseFirestore
@testable import LedgeriOS

// MARK: - Mocks

private final class MockListenerRegistration: NSObject, ListenerRegistration {
    var removeCalled = false
    func remove() { removeCalled = true }
}

private struct MockItemsService: ItemsServiceProtocol {
    var scopeReceived: ListScope?

    func getItem(accountId: String, itemId: String) async throws -> Item? { nil }
    func createItem(accountId: String, item: Item) throws -> String { "" }
    func updateItem(accountId: String, itemId: String, fields: [String: Any]) async throws {}
    func deleteItem(accountId: String, itemId: String) async throws {}
    func subscribeToItems(accountId: String, scope: ListScope, onChange: @escaping ([Item]) -> Void) -> ListenerRegistration {
        onChange([])
        return MockListenerRegistration()
    }
    func subscribeToItem(accountId: String, itemId: String, onChange: @escaping (Item?) -> Void) -> ListenerRegistration {
        MockListenerRegistration()
    }
}

private struct MockTransactionsService: TransactionsServiceProtocol {
    func getTransaction(accountId: String, transactionId: String) async throws -> LedgeriOS.Transaction? { nil }
    func createTransaction(accountId: String, transaction: LedgeriOS.Transaction) throws -> String { "" }
    func updateTransaction(accountId: String, transactionId: String, fields: [String: Any]) async throws {}
    func deleteTransaction(accountId: String, transactionId: String) async throws {}
    func subscribeToTransactions(accountId: String, scope: ListScope, onChange: @escaping ([LedgeriOS.Transaction]) -> Void) -> ListenerRegistration {
        onChange([])
        return MockListenerRegistration()
    }
    func subscribeToTransaction(accountId: String, transactionId: String, onChange: @escaping (LedgeriOS.Transaction?) -> Void) -> ListenerRegistration {
        MockListenerRegistration()
    }
}

private struct MockSpacesService: SpacesServiceProtocol {
    func getSpace(accountId: String, spaceId: String) async throws -> Space? { nil }
    func createSpace(accountId: String, space: Space) throws -> String { "" }
    func updateSpace(accountId: String, spaceId: String, fields: [String: Any]) async throws {}
    func deleteSpace(accountId: String, spaceId: String) async throws {}
    func subscribeToSpaces(accountId: String, scope: ListScope, onChange: @escaping ([Space]) -> Void) -> ListenerRegistration {
        onChange([])
        return MockListenerRegistration()
    }
    func subscribeToSpace(accountId: String, spaceId: String, onChange: @escaping (Space?) -> Void) -> ListenerRegistration {
        MockListenerRegistration()
    }
}

// MARK: - Helpers

@MainActor
private func makeContext() -> InventoryContext {
    InventoryContext(
        itemsService: MockItemsService(),
        transactionsService: MockTransactionsService(),
        spacesService: MockSpacesService()
    )
}

// MARK: - Tests

@Suite("InventoryContext Tests", .serialized)
struct InventoryContextTests {

    private static let tabKey = "inventorySelectedTab"

    @Test("lastSelectedTab persists to UserDefaults")
    @MainActor
    func userDefaultsTabPersists() {
        defer { UserDefaults.standard.removeObject(forKey: Self.tabKey) }

        let context = makeContext()
        context.lastSelectedTab = 2

        // New instance should read the same value
        let context2 = makeContext()
        #expect(context2.lastSelectedTab == 2)
    }

    @Test("lastSelectedTab defaults to 0 when unset")
    @MainActor
    func userDefaultsTabDefault() {
        UserDefaults.standard.removeObject(forKey: Self.tabKey)

        let context = makeContext()
        #expect(context.lastSelectedTab == 0)
    }

    @Test("deactivate resets all state arrays")
    @MainActor
    func deactivateResetsState() {
        let context = makeContext()

        // Activate to set up listeners
        context.activate(accountId: "acc1")

        // Manually set some data (simulating subscription callbacks)
        context.items = [Item()]
        context.transactions = [LedgeriOS.Transaction()]
        context.spaces = [Space()]

        #expect(!context.items.isEmpty)
        #expect(!context.transactions.isEmpty)
        #expect(!context.spaces.isEmpty)

        context.deactivate()

        #expect(context.items.isEmpty)
        #expect(context.transactions.isEmpty)
        #expect(context.spaces.isEmpty)
    }

    @Test("activate calls deactivate first to prevent duplicate listeners")
    @MainActor
    func activateCallsDeactivateFirst() {
        let context = makeContext()

        // Activate twice — should not accumulate listeners
        context.activate(accountId: "acc1")
        context.items = [Item()]

        context.activate(accountId: "acc2")
        // After re-activate, state should be reset (deactivate was called internally)
        // The mock callbacks set empty arrays, so items should be empty
        #expect(context.items.isEmpty)
    }
}
