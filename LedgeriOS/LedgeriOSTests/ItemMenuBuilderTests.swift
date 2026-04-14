import Foundation
import Testing
@testable import LedgeriOS

@Suite("ItemMenuBuilder Tests")
struct ItemMenuBuilderTests {

    // MARK: - Helpers

    /// Build a full callbacks struct where every callback is wired (so all possible items appear).
    private func allCallbacks() -> SingleItemMenuCallbacks {
        SingleItemMenuCallbacks(
            onOpen: {},
            onSelect: {},
            onStatusChange: { _ in },
            onClearStatus: {},
            onSetTransaction: {},
            onClearTransaction: {},
            onMoveToReturnTransaction: {},
            onSetSpace: {},
            onClearSpace: {},
            onReturnToInventory: {},
            onSellToProject: {},
            onMoveToProject: {},
            onReassignToProject: {},
            onMakeCopies: {},
            onDelete: {}
        )
    }

    private func allBulkCallbacks() -> BulkItemMenuCallbacks {
        BulkItemMenuCallbacks(
            onStatusChange: { _ in },
            onSetTransaction: {},
            onClearTransaction: {},
            onMoveToReturnTransaction: {},
            onSetSpace: {},
            onClearSpace: {},
            onReturnToInventory: {},
            onSellToProject: {},
            onMoveToProject: {},
            onReassignToProject: {},
            onDelete: {}
        )
    }

    private func ids(_ items: [ActionMenuItem]) -> [String] {
        items.map(\.id)
    }

    private func subIds(of items: [ActionMenuItem], parent: String) -> [String]? {
        items.first(where: { $0.id == parent })?.subactions?.map(\.id)
    }

    // MARK: - List Context

    @Test("List context includes Open and Select first")
    func listContextOpenSelect() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: allCallbacks()
        )
        #expect(ids(menu).prefix(2) == ["open", "select"])
    }

    @Test("List context ends with Delete")
    func listContextDeleteLast() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: allCallbacks()
        )
        #expect(menu.last?.id == "delete")
        #expect(menu.last?.isDestructive == true)
    }

    @Test("List context does not include Clear Status in status submenu")
    func listContextNoClearStatus() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: allCallbacks()
        )
        let statusSubs = subIds(of: menu, parent: "status")
        #expect(statusSubs?.contains("clear-status") == false)
    }

    // MARK: - Detail Context

    @Test("Detail context omits Open and Select")
    func detailContextNoOpenSelect() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .detail, scope: .project, callbacks: allCallbacks()
        )
        #expect(!ids(menu).contains("open"))
        #expect(!ids(menu).contains("select"))
    }

    @Test("Detail context includes Make Copies")
    func detailContextMakeCopies() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .detail, scope: .project, callbacks: allCallbacks()
        )
        #expect(ids(menu).contains("make-copies"))
    }

    @Test("Detail context omits Status submenu (dedicated toolbar capsule handles status)")
    func detailContextNoStatusSubmenu() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .detail, scope: .project, callbacks: allCallbacks()
        )
        #expect(!ids(menu).contains("status"))
    }

    @Test("Detail context includes Set and Clear Transaction")
    func detailContextTransactions() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .detail, scope: .project, callbacks: allCallbacks()
        )
        let txnSubs = subIds(of: menu, parent: "transaction")
        #expect(txnSubs?.contains("set-transaction") == true)
        #expect(txnSubs?.contains("clear-transaction") == true)
    }

    // MARK: - Space Context

    @Test("Space context uses 'Move to Space' / 'Remove from Space' labels")
    func spaceContextLabels() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .space, scope: .project, callbacks: allCallbacks()
        )
        let spaceSubs = menu.first(where: { $0.id == "space" })?.subactions
        #expect(spaceSubs?.first(where: { $0.id == "set-space" })?.label == "Move to Space")
        #expect(spaceSubs?.first(where: { $0.id == "clear-space" })?.label == "Remove from Space")
    }

    @Test("Space context includes Open but not Select")
    func spaceContextOpenNoSelect() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .space, scope: .project, callbacks: allCallbacks()
        )
        #expect(ids(menu).contains("open"))
        #expect(!ids(menu).contains("select"))
    }

    // MARK: - Transaction Context

    @Test("Transaction context uses 'Open Item' label")
    func transactionContextOpenLabel() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .transaction, scope: .project, callbacks: allCallbacks()
        )
        let openItem = menu.first(where: { $0.id == "open" })
        #expect(openItem?.label == "Open Item")
    }

    @Test("Transaction context shows Clear Transaction and Move to Return, not Set Transaction")
    func transactionContextTxnSubactions() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .transaction, scope: .project, callbacks: allCallbacks()
        )
        let txnSubs = subIds(of: menu, parent: "transaction")
        #expect(txnSubs?.contains("clear-transaction") == true)
        #expect(txnSubs?.contains("move-return-tx") == true)
        #expect(txnSubs?.contains("set-transaction") != true)
    }

    @Test("Transaction context includes Make Copies")
    func transactionContextMakeCopies() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .transaction, scope: .project, callbacks: allCallbacks()
        )
        #expect(ids(menu).contains("make-copies"))
    }

    // MARK: - Scope: Project

    @Test("Project scope shows Sell to Business and Sell to Project")
    func projectScopeSell() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: allCallbacks()
        )
        let sellSubs = subIds(of: menu, parent: "sell")
        #expect(sellSubs?.contains("move-to-inventory") == true)
        #expect(sellSubs?.contains("sell-to-project") == true)
    }

    @Test("Project scope shows Reassign to Project")
    func projectScopeReassign() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: allCallbacks()
        )
        let reassignSubs = subIds(of: menu, parent: "reassign")
        #expect(reassignSubs?.contains("reassign-to-project") == true)
    }

    // MARK: - Scope: Inventory

    @Test("Inventory scope hides Move to Inventory and Move to Project")
    func inventoryScopeNoReturnOrMove() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .inventory, callbacks: allCallbacks()
        )
        let sellSubs = subIds(of: menu, parent: "sell")
        #expect(sellSubs?.contains("move-to-inventory") == false)
        #expect(sellSubs?.contains("move-to-project") == false)
        #expect(sellSubs?.contains("sell-to-project") == true)
    }

    @Test("Inventory scope still shows Reassign to Project")
    func inventoryScopeReassign() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .inventory, callbacks: allCallbacks()
        )
        let reassignSubs = subIds(of: menu, parent: "reassign")
        #expect(reassignSubs?.contains("reassign-to-project") == true)
    }

    // MARK: - Scope: Search

    @Test("Search scope shows all sell/move and reassign options")
    func searchScopeAll() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .search, callbacks: allCallbacks()
        )
        let sellSubs = subIds(of: menu, parent: "sell")
        #expect(sellSubs?.contains("move-to-inventory") == true)
        #expect(sellSubs?.contains("sell-to-project") == true)
        #expect(sellSubs?.contains("move-to-project") == true)
        let reassignSubs = subIds(of: menu, parent: "reassign")
        #expect(reassignSubs?.contains("reassign-to-project") == true)
    }

    // MARK: - Status Submenu

    @Test("Status submenu contains 4 statuses")
    func statusSubmenuCount() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: allCallbacks()
        )
        let statusSubs = menu.first(where: { $0.id == "status" })?.subactions
        // 4 statuses (no Clear Status in list context)
        #expect(statusSubs?.count == 4)
    }

    @Test("Status submenu passes currentStatus as selectedSubactionKey")
    func statusSubmenuSelectedKey() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: allCallbacks(), currentStatus: "purchased"
        )
        let statusItem = menu.first(where: { $0.id == "status" })
        #expect(statusItem?.selectedSubactionKey == "purchased")
    }

    // MARK: - Nil Callbacks Omit Items

    @Test("Missing delete callback omits delete item")
    func noDeleteCallbackNoItem() {
        var cb = allCallbacks()
        cb.onDelete = nil
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: cb
        )
        #expect(!ids(menu).contains("delete"))
    }

    @Test("Missing sell callbacks omit sell submenu entirely")
    func noSellCallbacksNoSellMenu() {
        var cb = allCallbacks()
        cb.onReturnToInventory = nil
        cb.onSellToProject = nil
        cb.onMoveToProject = nil
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: cb
        )
        #expect(!ids(menu).contains("sell"))
    }

    // MARK: - Bulk Menu

    @Test("Bulk menu contains expected categories for project scope")
    func bulkMenuProjectScope() {
        let menu = ItemMenuBuilder.buildBulkMenu(scope: .project, callbacks: allBulkCallbacks())
        let menuIds = ids(menu)
        #expect(menuIds.contains("status"))
        #expect(menuIds.contains("transaction"))
        #expect(menuIds.contains("space"))
        #expect(menuIds.contains("sell"))
        #expect(menuIds.contains("reassign"))
        #expect(menuIds.contains("delete"))
    }

    @Test("Bulk menu inventory scope hides Return to Inventory and Move to Project")
    func bulkMenuInventoryScope() {
        let menu = ItemMenuBuilder.buildBulkMenu(scope: .inventory, callbacks: allBulkCallbacks())
        let sellSubs = subIds(of: menu, parent: "sell")
        #expect(sellSubs?.contains("move-to-inventory") == false)
        #expect(sellSubs?.contains("move-to-project") == false)
        #expect(sellSubs?.contains("sell-to-project") == true)
        // Reassign is still available
        let reassignSubs = subIds(of: menu, parent: "reassign")
        #expect(reassignSubs?.contains("reassign-to-project") == true)
    }

    @Test("Bulk menu space context uses 'Move to Another Space' label")
    func bulkMenuSpaceLabels() {
        let menu = ItemMenuBuilder.buildBulkMenu(context: .space, scope: .project, callbacks: allBulkCallbacks())
        let spaceSubs = menu.first(where: { $0.id == "space" })?.subactions
        #expect(spaceSubs?.first(where: { $0.id == "set-space" })?.label == "Move to Another Space")
        #expect(spaceSubs?.first(where: { $0.id == "clear-space" })?.label == "Remove from Space")
    }

    @Test("Bulk menu delete is last and destructive")
    func bulkMenuDeleteLast() {
        let menu = ItemMenuBuilder.buildBulkMenu(scope: .project, callbacks: allBulkCallbacks())
        #expect(menu.last?.id == "delete")
        #expect(menu.last?.isDestructive == true)
    }
}
