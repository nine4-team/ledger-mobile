import Foundation
import Testing
@testable import LedgeriOS

@Suite("TransactionMenuBuilder Tests")
struct TransactionMenuBuilderTests {

    // MARK: - Helpers

    private func allCallbacks() -> SingleTransactionMenuCallbacks {
        SingleTransactionMenuCallbacks(
            onReassignToInventory: {},
            onReassignToProject: {},
            onDelete: {}
        )
    }

    private func ids(_ items: [ActionMenuItem]) -> [String] {
        items.map(\.id)
    }

    private func subIds(of menu: [ActionMenuItem], parent: String) -> [String]? {
        menu.first(where: { $0.id == parent })?.subactions?.map(\.id)
    }

    private func normalTransaction() -> Transaction {
        var tx = Transaction()
        tx.id = "tx-1"
        tx.isCanonicalInventorySale = false
        return tx
    }

    private func canonicalTransaction() -> Transaction {
        var tx = Transaction()
        tx.id = "tx-canonical"
        tx.isCanonicalInventorySale = true
        return tx
    }

    // MARK: - Card Menu

    @Test("Card menu for normal transaction includes Delete")
    func cardMenuNormal() {
        let menu = TransactionMenuBuilder.buildCardMenu(
            transaction: normalTransaction(),
            callbacks: allCallbacks()
        )
        #expect(ids(menu).contains("delete"))
    }

    @Test("Card menu has no Select action")
    func cardMenuNoSelect() {
        let menu = TransactionMenuBuilder.buildCardMenu(
            transaction: normalTransaction(),
            callbacks: allCallbacks()
        )
        #expect(!ids(menu).contains("select"))
    }

    @Test("Card menu for canonical sale is empty")
    func cardMenuCanonical() {
        let menu = TransactionMenuBuilder.buildCardMenu(
            transaction: canonicalTransaction(),
            callbacks: allCallbacks()
        )
        #expect(menu.isEmpty)
    }

    @Test("Card menu with nil onDelete is empty")
    func cardMenuNilDelete() {
        let menu = TransactionMenuBuilder.buildCardMenu(
            transaction: normalTransaction(),
            callbacks: SingleTransactionMenuCallbacks()
        )
        #expect(menu.isEmpty)
    }

    // MARK: - Detail Menu

    @Test("Detail menu for normal transaction includes Correct / Move and Delete")
    func detailMenuNormal() {
        let menu = TransactionMenuBuilder.buildDetailMenu(
            transaction: normalTransaction(),
            callbacks: allCallbacks()
        )
        let menuIds = ids(menu)
        #expect(menuIds.contains("correct-move"))
        #expect(menuIds.contains("delete"))
    }

    @Test("Detail menu Correct / Move subactions include both options")
    func detailMenuReassignSubactions() {
        let menu = TransactionMenuBuilder.buildDetailMenu(
            transaction: normalTransaction(),
            callbacks: allCallbacks()
        )
        let subs = subIds(of: menu, parent: "correct-move")
        #expect(subs?.contains("reassign-to-inventory") == true)
        #expect(subs?.contains("reassign-to-project") == true)
    }

    @Test("Detail menu for canonical sale has only Delete")
    func detailMenuCanonical() {
        let menu = TransactionMenuBuilder.buildDetailMenu(
            transaction: canonicalTransaction(),
            callbacks: allCallbacks()
        )
        let menuIds = ids(menu)
        #expect(!menuIds.contains("correct-move"))
        #expect(menuIds.contains("delete"))
    }

    @Test("Detail menu Delete is always present regardless of nil Correct / Move callbacks")
    func detailMenuDeleteAlwaysPresent() {
        let menu = TransactionMenuBuilder.buildDetailMenu(
            transaction: normalTransaction(),
            callbacks: SingleTransactionMenuCallbacks(onDelete: {})
        )
        #expect(ids(menu).contains("delete"))
        #expect(!ids(menu).contains("correct-move"))
    }

    // MARK: - Bulk Menu

    @Test("Bulk menu includes Delete")
    func bulkMenuDelete() {
        let menu = TransactionMenuBuilder.buildBulkMenu(
            callbacks: BulkTransactionMenuCallbacks(onDelete: {})
        )
        #expect(ids(menu).contains("delete"))
    }

    @Test("Bulk menu has no Mark as Reviewed")
    func bulkMenuNoReview() {
        let menu = TransactionMenuBuilder.buildBulkMenu(
            callbacks: BulkTransactionMenuCallbacks(onDelete: {})
        )
        #expect(!ids(menu).contains("mark-reviewed"))
    }

    @Test("Bulk menu with nil callbacks is empty")
    func bulkMenuEmpty() {
        let menu = TransactionMenuBuilder.buildBulkMenu(
            callbacks: BulkTransactionMenuCallbacks()
        )
        #expect(menu.isEmpty)
    }
}
