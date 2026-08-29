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

    @Test("List context includes Make Copies")
    func listContextMakeCopies() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: allCallbacks()
        )
        #expect(ids(menu).contains("make-copies"))
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

    @Test("Space context opens Space picker directly")
    func spaceContextSpacePickerDirectAction() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .space, scope: .project, callbacks: allCallbacks()
        )
        let spaceItem = menu.first(where: { $0.id == "space" })
        #expect(spaceItem?.label == "Space")
        #expect(spaceItem?.subactions == nil)
        #expect(spaceItem?.onPress != nil)
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

    @Test("Project scope shows Return and Sell")
    func projectScopeSell() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: allCallbacks()
        )
        let menuIds = ids(menu)
        #expect(menuIds.contains("return-to-inventory"))
        #expect(menuIds.contains("sell"))
    }

    @Test("Project scope shows Correct / Move")
    func projectScopeReassign() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: allCallbacks()
        )
        #expect(ids(menu).contains("correct-move"))
    }

    // MARK: - Scope: Inventory

    @Test("Inventory scope shows Return to Project instead of Sell")
    func inventoryScopeReturnToProject() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list,
            scope: .inventory,
            callbacks: allCallbacks(),
            projectDestinationPresentation: .returnToProject
        )
        let menuIds = ids(menu)
        #expect(!menuIds.contains("return-to-inventory"))
        #expect(!menuIds.contains("sell"))
        #expect(menuIds.contains("return-to-project"))
        #expect(menu.first(where: { $0.id == "return-to-project" })?.label == "Return to Project")
    }

    @Test("Inventory scope keeps Sell when no return project is known")
    func inventoryScopeSellWithoutReturnProvenance() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .inventory, callbacks: allCallbacks()
        )
        #expect(ids(menu).contains("sell"))
        #expect(!ids(menu).contains("return-to-project"))
    }

    @Test("Return presentation requires active Sale-to-Inventory and an existing source project")
    func returnPresentationRequiresSaleToInventoryAndExistingProject() {
        var item = Item()
        item.id = "item-1"
        item.transactionId = "return-1"

        var transaction = Transaction()
        transaction.id = "return-1"
        transaction.projectId = "project-home"
        transaction.source = "Business Inventory"
        transaction.transactionType = .sale
        transaction.itemIds = ["item-1"]
        transaction.budgetCategoryId = "furnishings"
        transaction.subtotalCents = 0
        transaction.amountCents = 0

        var project = Project()
        project.id = "project-home"

        #expect(ProjectDestinationPresentation.resolve(
            for: [item],
            transactions: [transaction],
            projects: [project]
        ) == .returnToProject)
        #expect(ProjectDestinationPresentation.resolve(
            for: [item],
            transactions: [transaction],
            projects: []
        ) == .sell)

        transaction.transactionType = .return
        #expect(ProjectDestinationPresentation.resolve(
            for: [item],
            transactions: [transaction],
            projects: [project]
        ) == .sell)
    }

    @Test("Inventory scope still shows Correct / Move")
    func inventoryScopeReassign() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .inventory, callbacks: allCallbacks()
        )
        #expect(ids(menu).contains("correct-move"))
    }

    // MARK: - Scope: Search

    @Test("Search scope shows Return, Sell, and Correct / Move")
    func searchScopeAll() {
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .search, callbacks: allCallbacks()
        )
        let menuIds = ids(menu)
        #expect(menuIds.contains("return-to-inventory"))
        #expect(menuIds.contains("sell"))
        #expect(menuIds.contains("correct-move"))
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

    @Test("Missing sell and correction callbacks omit those actions")
    func noSellCallbacksNoSellMenu() {
        var cb = allCallbacks()
        cb.onReturnToInventory = nil
        cb.onSellToProject = nil
        cb.onReassignToProject = nil
        let menu = ItemMenuBuilder.buildSingleItemMenu(
            context: .list, scope: .project, callbacks: cb
        )
        let menuIds = ids(menu)
        #expect(!menuIds.contains("return-to-inventory"))
        #expect(!menuIds.contains("sell"))
        #expect(!menuIds.contains("correct-move"))
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
        #expect(menuIds.contains("correct-move"))
        #expect(menuIds.contains("delete"))
    }

    @Test("Bulk menu inventory scope shows Return to Project instead of Sell")
    func bulkMenuInventoryScope() {
        let menu = ItemMenuBuilder.buildBulkMenu(
            scope: .inventory,
            callbacks: allBulkCallbacks(),
            projectDestinationPresentation: .returnToProject
        )
        let menuIds = ids(menu)
        #expect(!menuIds.contains("return-to-inventory"))
        #expect(!menuIds.contains("sell"))
        #expect(menuIds.contains("return-to-project"))
        #expect(menu.first(where: { $0.id == "return-to-project" })?.label == "Return to Project")
        #expect(menuIds.contains("correct-move"))
    }

    @Test("Bulk menu opens Space picker directly")
    func bulkMenuSpacePickerDirectAction() {
        let menu = ItemMenuBuilder.buildBulkMenu(context: .space, scope: .project, callbacks: allBulkCallbacks())
        let spaceItem = menu.first(where: { $0.id == "space" })
        #expect(spaceItem?.label == "Space")
        #expect(spaceItem?.subactions == nil)
        #expect(spaceItem?.onPress != nil)
    }

    @Test("Bulk menu delete is last and destructive")
    func bulkMenuDeleteLast() {
        let menu = ItemMenuBuilder.buildBulkMenu(scope: .project, callbacks: allBulkCallbacks())
        #expect(menu.last?.id == "delete")
        #expect(menu.last?.isDestructive == true)
    }
}
