import LedgerTargetAppModel
import LedgerTargetCore
import LedgerTargetPowerSync
import SwiftUI

/// Thin target binding; layout stays in the original Transaction audit panel.
/// Item labels travel with the authorized receipt read.
struct TargetTransactionAuditPanel: View {
    let presentation: TransactionReceiptAuditPresentation

    var body: some View {
        if presentation.isApplicable {
            TransactionAuditPanelPresentation(progressPercentage: presentation.progressPercentage,
                isComplete: presentation.isComplete, itemCount: presentation.itemCount,
                statusLabel: presentation.statusLabel, details: presentation.details,
                missingPriceTitle: "Missing Purchase Price",
                missingPriceSummary: "\(presentation.missingItemIds.count) items missing purchase price",
                missingItems: presentation.missingItems, itemName: { $0.name }, itemSKU: { $0.sku })
        }
    }
}

/// Reader-to-panel binding for the existing detail-screen owner to embed.
/// Incomplete, withdrawn and failed reads remove previous financial values.
struct TargetLiveTransactionAuditPanel: View {
    let scope: TransactionScope
    let principalId: PrincipalID
    let transactionId: TransactionID
    let runtime: LedgerOfflineClientRuntime

    private struct BindingIdentity: Hashable {
        let runtime: ObjectIdentifier
        let scopeAndIdentity: [String?]
    }

    var body: some View {
        BoundTransactionAuditPanel(session: TransactionReceiptAuditSession(scope: scope,
            principalId: principalId, transactionId: transactionId,
            watch: { runtime.watchTransactionReceipt(scope: scope, transactionId: transactionId) }))
            // SwiftUI otherwise retains @State when a detail view changes its
            // input Transaction, Account, principal or workspace runtime.
            .id(BindingIdentity(runtime: ObjectIdentifier(runtime), scopeAndIdentity: [
                scope.accountId.rawValue, scope.ownerKind.rawValue, scope.projectId?.rawValue,
                scope.clientId?.rawValue, principalId.rawValue, transactionId.rawValue]))
    }
}

struct BoundTransactionAuditPanel: View {
    @State private var session: TransactionReceiptAuditSession

    init(session: TransactionReceiptAuditSession) {
        _session = State(initialValue: session)
    }

    var body: some View {
        // Keep observation on a stable container, not Group's conditional
        // children: General/Fee may hide the panel without ending the watch.
        VStack(alignment: .leading, spacing: 0) {
            if let presentation = session.presentation {
                TargetTransactionAuditPanel(presentation: presentation)
            } else {
                switch session.state {
                case .loading: ProgressView("Loading receipt details")
                case .incomplete: Text("Receipt details have not finished downloading.")
                case .unavailable: Text("This Transaction is not available.")
                case .failed: Text("Receipt details could not be loaded.")
                case .ready: EmptyView()
                }
            }
        }
        .task { await session.observe() }
        .onDisappear { session.invalidate() }
    }
}

#if DEBUG
/// Component interaction fixture only. The production Transaction detail route
/// and real command/read integration are not replaced by this test host.
struct TransactionAuditPanelUITestFixture: View {
    @State private var kind = CategoryFormPresentation.Kind.itemized
    @State private var editing = false
    @State private var matched = false
    @State private var missing = false
    @State private var updates = AsyncThrowingStream<TransactionReceiptUpdate, Error>.makeStream()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button("Edit Category") { editing = true }
                    Button("Use exact total") { matched = true }
                    Button(missing ? "Restore Item price" : "Remove Item price") { missing.toggle() }
                    Text("Current category: \(kind.rawValue)")
                    if let receipt = try? snapshot() {
                        let stream = updates.stream
                        BoundTransactionAuditPanel(session: TransactionReceiptAuditSession(
                            scope: receipt.classification.scope, principalId: receipt.principalId,
                            transactionId: receipt.transactionId, locale: Locale(identifier: "en_US"),
                            watch: { stream }))
                    } else { Text("Receipt fixture invalid") }
                }
                .padding()
            }
            .navigationTitle("Receipt audit")
        }
        .adaptivePresentation(isPresented: $editing, style: .form) {
            CategoryFormPresentation(mode: .edit(name: "Items", kind: kind, excluded: false), existingNames: []) {
                _, selected, _ in kind = selected
            }
        }
        .onAppear { publishReceipt() }
        .onChange(of: kind) { publishReceipt() }
        .onChange(of: matched) { publishReceipt() }
        .onChange(of: missing) { publishReceipt() }
    }

    private func publishReceipt() {
        guard let receipt = try? snapshot() else { return }
        updates.continuation.yield(.ready(receipt))
    }

    private func snapshot() throws -> TransactionReceiptSnapshot {
        let wire: [String: Any] = ["accountId": "fixture", "principalId": "member", "transactionId": "receipt",
            "scopeKind": "business_inventory", "projectId": NSNull(), "clientId": NSNull(), "type": "purchase",
            "currency": "USD", "amountMinorUnits": matched ? "3050" : "3051",
            "category": ["id": "category", "name": "Items", "kind": kind.rawValue, "revision": "1"],
            "nonItemReceiptLines": [
                ["id": "tax", "description": "Tax", "amountMinorUnits": "100", "effect": "increase"],
                ["id": "discount", "description": "Discount", "amountMinorUnits": "50", "effect": "decrease"]],
            "items": [["itemId": "a", "amountMinorUnits": "1000", "membershipKind": "linked"],
                ["itemId": "b", "amountMinorUnits": missing ? NSNull() : "2000" as Any,
                 "membershipKind": "sold", "name": "Historical chair", "sku": "CHAIR-2"]]]
        return try JSONDecoder().decode(TransactionReceiptSnapshot.self, from: JSONSerialization.data(withJSONObject: wire))
    }
}
#endif
