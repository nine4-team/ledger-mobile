import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

/// Workspace binding around original controls/cards/detail sections. The reader
/// owns authorization and local readiness; this view does not cache backend rows.
struct TargetTransactionBrowserView: View {
    let scope: TransactionScope
    let scopeName: String
    let reader: any TransactionBrowsing
    var itemReader: (any DownloadedItemPlacementHistoryReading)? = nil
    var spaceNavigation: ItemSpaceNavigation? = nil
    private struct Identity: Hashable { let reader: ObjectIdentifier; let scope: [String?] }
    var body: some View {
        BoundTransactionBrowserView(session: TransactionBrowserSession(scope: scope,
            watch: { reader.watchTransactions(scope: scope) }), scopeName: scopeName,
            browser: reader,
            itemReader: itemReader ?? (reader as? any DownloadedItemPlacementHistoryReading), spaceNavigation: spaceNavigation)
            .id(Identity(reader: ObjectIdentifier(reader), scope: [scope.accountId.rawValue,
                scope.ownerKind.rawValue, scope.projectId?.rawValue, scope.clientId?.rawValue]))
    }
}

private struct BoundTransactionBrowserView: View {
    @State var session: TransactionBrowserSession
    let scopeName: String
    let browser: any TransactionBrowsing
    let itemReader: (any DownloadedItemPlacementHistoryReading)?
    let spaceNavigation: ItemSpaceNavigation?
    @State private var find = FindStateManager()
    @State private var filtersPresented = false
    @State private var bulkPresented = false
    @State private var selectedDetailId: TransactionID?

    var body: some View {
        VStack(spacing: Spacing.md) {
            if session.scope.ownerKind == .project {
                HStack {
                    Spacer()
                    ProjectTransactionExportButton(scope: session.scope, reader: browser,
                        orderedTransactionIDs: session.processed.map(\.transactionId), processedSourceRows: session.rows,
                        canOpen: session.state == .partial || session.state == .ready)
                }
            }
            NativeListControlBar(searchText: $session.search, searchPlaceholder: "Search transactions...", style: .plain) {
                if session.scope.ownerKind == .project && !session.processed.isEmpty {
                    Button { session.selectAllVisible() } label: {
                        SelectorCircle(isSelected: session.selectedIds == Set(session.processed.map(\.transactionId)), indicator: .check)
                    }.buttonStyle(.plain).accessibilityLabel("Select all")
                }
            } sortMenu: {
                Menu {
                    Picker("Sort", selection: $session.sort) {
                        ForEach(TransactionBrowserSession.Sort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                .accessibilityLabel("Sort Transactions")
            } filterMenu: {
                Button { filtersPresented = true } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .accessibilityLabel("Filter Transactions")
            }
            .accessibilityIdentifier("target-transaction-browser-controls")
            status
            if !session.rows.isEmpty && session.processed.isEmpty {
                Text("No matching Transactions in downloaded data.")
                    .accessibilityIdentifier("target-transactions-no-match")
            }
            LazyVGrid(columns: Dimensions.listColumns, alignment: .leading, spacing: Spacing.cardListGap) {
                ForEach(session.processed, id: \.transactionId) { row in
                    TransactionCardPresentation(id: row.transactionId.rawValue, title: TransactionBrowserSession.title(row),
                        source: row.source ?? row.transactionId.rawValue, amountText: TransactionBrowserSession.amountText(row),
                        dateText: row.transactionDate ?? "Unknown", itemCount: row.linkedItemCount, budgetCategoryName: row.category?.name,
                        projectName: scopeName, matchingTransactionID: row.transactionId.rawValue, notesPreview: row.notes,
                        badges: badges(row),
                        isSelected: Binding(get: { session.selectedIds.contains(row.transactionId) },
                            set: { selected in
                                if selected != session.selectedIds.contains(row.transactionId) { session.toggleSelection(row.transactionId) }
                            }),
                        menuItems: [ActionMenuItem(id: "copy-id", label: "Copy ID", icon: "doc.on.doc",
                            onPress: { Clipboard.copy(row.transactionId.rawValue) })],
                        onPress: {
                            selectedDetailId = row.transactionId
                            session.suspendForDetailNavigation()
                        })
                        .accessibilityIdentifier("target-transaction-\(row.transactionId.rawValue)")
                }
            }
            if !session.selectedIds.isEmpty {
                BulkSelectionBar(selectedCount: session.selected.count,
                    totalText: selectedTotalText,
                    onBulkActions: { bulkPresented = true }, onClear: { session.clearSelection() })
            }
            TransactionFilterMenuPresentation(isPresented: $filtersPresented, items: filterItems)
        }
        .environment(find)
        .navigationTitle("Transactions")
        .task { await session.observe() }
        .onDisappear { if selectedDetailId == nil { session.invalidate() } }
        .adaptivePresentation(isPresented: $bulkPresented, style: .quickMenu) {
            ActionMenuSheet(title: "\(session.selected.count) selected", items: [
                ActionMenuItem(id: "copy-ids", label: "Copy IDs", icon: "doc.on.doc", onPress: { Clipboard.copy(session.selectedIDText) }),
                ActionMenuItem(id: "clear", label: "Clear Selection", icon: "xmark.circle", onPress: { session.clearSelection() })])
        }
        .navigationDestination(isPresented: Binding(get: { selectedDetailId != nil }, set: { if !$0 { selectedDetailId = nil } })) {
            if let selectedDetailId {
                TransactionNavigationDetail(
                    session: TransactionBrowserSession(scope: session.scope,
                        watch: { [browser, scope = session.scope] in browser.watchTransactions(scope: scope) }),
                    transactionId: selectedDetailId, scopeName: scopeName, itemReader: itemReader,
                    spaceNavigation: spaceNavigation,
                    attachmentReader: browser as? any DownloadedTransactionAttachmentReading,
                    editor: browser as? any TransactionDetailsEditing)
                    .environment(find)
                    .navigationTitle("Transaction")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { self.selectedDetailId = nil } } }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch session.state {
        case .loading: ProgressView("Loading Transactions")
        case .incomplete: Text("Transaction data has not finished downloading.")
        case .partial:
            Text("Partial Transaction list: vendor Purchases, Returns and imported client payments are connected. New Invoice collection, Transfers and remaining actions are still being connected.")
                .accessibilityIdentifier("target-transactions-partial")
        case .ready:
            if session.rows.isEmpty { Text("No Transactions yet.") }
        case .unavailable: Text("Transactions are unavailable.")
        case .failed: Text("Transactions could not be loaded.")
        }
    }

    private var selectedTotalText: String? {
        do {
            guard let total = try session.selectedTotal() else { return nil }
            return (Decimal(total.minorUnits) / 100).formatted(.currency(code: total.currency.rawValue))
        } catch { return "Selected total unavailable" }
    }

    private func badges(_ row: TransactionDetailSnapshot) -> [CardBadge] {
        var result = [CardBadge(text: row.classification.type.rawValue.capitalized, color: BrandColors.primary)]
        switch session.value(row, group: .audit) {
        case "balanced": result.append(CardBadge(text: "Receipt balanced", color: .green))
        case "mismatch": result.append(CardBadge(text: "Receipt mismatch", color: .orange))
        case "incompleteEvidence": result.append(CardBadge(text: "Missing Item prices", color: .orange))
        case "unknown": result.append(CardBadge(text: "Receipt not downloaded", color: .secondary))
        default: break
        }
        return result
    }

    private var filterItems: [ActionMenuItem] {
        let groups: [(TransactionBrowserSession.Filter, String, [(String, String)])] = [
            (.type, "Transaction Type", [("purchase", "Purchase"), ("return", "Return"), ("transfer", "Transfer")]),
            (.emailReceipt, "Email Receipt", [("yes", "Yes"), ("no", "No"), ("unknown", "Unknown")]),
            (.audit, "Receipt Audit", [("balanced", "Balanced"), ("mismatch", "Mismatch"),
                ("incompleteEvidence", "Missing Item prices"), ("notApplicable", "Not applicable"), ("unknown", "Not downloaded")]),
            (.payer, "Purchased By", [("client", "Client"), ("1584", "1584")]),
            (.category, "Budget Category", Dictionary(session.rows.compactMap { row in row.category.map { ($0.id.rawValue, $0.name) } },
                uniquingKeysWith: { first, _ in first }).sorted { $0.value < $1.value }.map { ($0.key, $0.value) }),
            (.source, "Source", Set(session.rows.compactMap(\.source)).sorted().map { ($0, $0) })]
        return groups.map { group, label, options in
            let selected = session.filters[group] ?? []
            let all = Set(options.map(\.0))
            return ActionMenuItem(id: group.rawValue, label: label, subactions:
                [ActionMenuSubitem(id: "all", label: "All", icon: selected.isEmpty ? "checkmark.circle.fill" : "circle",
                    onPress: { session.toggleFilter(group, value: nil) })] + options.map { value, title in
                        ActionMenuSubitem(id: value, label: title, icon: selected.contains(value) ? "checkmark.circle.fill" : "circle",
                            onPress: { session.toggleFilter(group, value: value, allOptionValues: all) })
                    }, selectedSubactionKey: selected.count == 1 ? selected.first : nil)
        } + [ActionMenuItem(id: "reset", label: "Reset Filters", icon: "arrow.counterclockwise", onPress: { session.resetFilters() })]
    }
}

/// Like the original detail container, the destination owns its live read while
/// the list is offscreen. It never relies on a stale row captured at navigation.
private struct TransactionNavigationDetail: View {
    @State var session: TransactionBrowserSession
    let transactionId: TransactionID
    let scopeName: String
    let itemReader: (any DownloadedItemPlacementHistoryReading)?
    let spaceNavigation: ItemSpaceNavigation?
    let attachmentReader: (any DownloadedTransactionAttachmentReading)?
    let editor: (any TransactionDetailsEditing)?

    var body: some View {
        Group {
            if let row = session.rows.first(where: { $0.transactionId == transactionId }) {
                TransactionReadDetail(row: row, scopeName: scopeName, itemReader: itemReader,
                    spaceNavigation: spaceNavigation, attachmentReader: attachmentReader, editor: editor)
                    .id(row.transactionId)
            } else if session.state == .loading {
                ProgressView("Loading Transaction…")
            } else {
                ContentUnavailableView("Transaction Unavailable", systemImage: "creditcard")
            }
        }
        .task { await session.observe() }
        .onDisappear { session.invalidate() }
    }
}

private struct TransactionReadDetail: View {
    let row: TransactionDetailSnapshot
    let scopeName: String
    let itemReader: (any DownloadedItemPlacementHistoryReading)?
    let spaceNavigation: ItemSpaceNavigation?
    let attachmentReader: (any DownloadedTransactionAttachmentReading)?
    let editor: (any TransactionDetailsEditing)?
    @State private var editSelection: EditSelection?
    private struct EditSelection: Identifiable {
        let id = UUID()
        let row: TransactionDetailSnapshot
        let notesOnly: Bool
    }
    private var canEdit: Bool { editor != nil && row.origin == .vendorPayment && row.detailsRevision != nil }
    @State private var notesExpanded = true
    @State private var detailsExpanded = true
    @State private var expandedItemSections: Set<String> = ["linked", "payment"]
    @State private var invoiceExpanded = true
    @State private var expandedItemGroups: Set<RelatedGroupID> = []
    private struct RelatedGroupID: Hashable {
        let membership: String
        let key: ItemGrouping.Key
    }
    @State private var selectedItem: RelatedItemSelection?
    @State private var pinnedAttachment: TransactionPinnedAttachment?
    private struct RelatedItemSelection: Identifiable { let id: ItemID; let transactionId: TransactionID }
    var body: some View {
        PinnedImageLayoutPresentation(pinIdentity: pinnedAttachment.map { AnyHashable($0.id) }) {
            if let pinnedAttachment, let attachmentReader {
                TransactionPinnedAttachmentView(pin: pinnedAttachment, reader: attachmentReader,
                    onClose: { self.pinnedAttachment = nil })
            }
        } content: {
            ScrollView { detailContent }
                .itemThumbnailViewport()
                .accessibilityIdentifier("target-transaction-detail-scroll")
        }
        .sheet(item: $editSelection) { selection in
            if let editor {
                TransactionDetailsEditForm(session: .init(original: selection.row, service: editor), notesOnly: selection.notesOnly)
            }
        }
        #if DEBUG
        .toolbar {
            if ProcessInfo.processInfo.arguments.contains("--ledger-ui-test-transaction-attachments"),
               let fixture = attachmentReader as? TransactionBrowserFixtureReader {
                Button("Withdraw attachment access") { fixture.withdraw() }
            }
        }
        #endif
    }

    private var detailContent: some View {
        AdaptiveContentWidth {
            VStack(spacing: Spacing.md) {
                TransactionHeroPresentation(title: TransactionBrowserSession.title(row),
                    amount: TransactionBrowserSession.amountText(row), date: row.transactionDate ?? "Unknown",
                    project: scopeName, category: row.category?.name)
                if let attachmentReader {
                    ForEach(TransactionAttachmentSection.allCases, id: \.rawValue) { section in
                        TransactionAttachmentsSection(scope: row.classification.scope, transactionId: row.transactionId,
                            section: section, reader: attachmentReader, onPin: { pinnedAttachment = $0 })
                    }
                }
                CollapsibleSection(title: "Notes", isExpanded: $notesExpanded,
                    onEdit: canEdit ? { editSelection = .init(row: row, notesOnly: true) } : nil) {
                    NotesContent(notes: row.notes).padding(.top, Spacing.xs)
                }
                CollapsibleSection(title: "Details", isExpanded: $detailsExpanded,
                    onEdit: canEdit ? { editSelection = .init(row: row, notesOnly: false) } : nil) {
                    VStack(spacing: 0) {
                        DetailRow(label: "Vendor / Source", value: row.source ?? "Unknown")
                        DetailRow(label: "Amount", value: TransactionBrowserSession.amountText(row))
                        DetailRow(label: "Date", value: row.transactionDate ?? "Unknown")
                        DetailRow(label: "Created", value: row.createdAtMilliseconds.map {
                            Date(timeIntervalSince1970: Double($0) / 1000).formatted(date: .abbreviated, time: .shortened)
                        } ?? "Unknown")
                        DetailRow(label: "Purchased By", value: row.classification.scope.ownerKind == .project ? "Client" : "1584")
                        DetailRow(label: "Transaction Type", value: row.classification.type.rawValue.capitalized)
                        DetailRow(label: "Budget Category", value: row.category?.name ?? "—")
                        DetailRow(label: "Payment Method", value: row.paymentMethod ?? "Unknown")
                        DetailRow(label: "Email Receipt", value: row.hasEmailReceipt.map { $0 ? "Yes" : "No" } ?? "Unknown",
                            showDivider: row.origin == .vendorPayment && row.category?.kind == .itemized)
                        if row.origin == .vendorPayment && row.category?.kind == .itemized {
                            DetailRow(label: "Subtotal", value: row.legacySubtotal.map {
                                (Decimal($0.minorUnits) / 100).formatted(.currency(code: $0.currency.rawValue))
                            } ?? "—")
                            DetailRow(label: "Tax Rate", value: row.legacyTaxRatePct.map { "\($0)%" } ?? "—",
                                showDivider: false)
                        }
                    }.padding(.top, Spacing.xs)
                }
                if let receipt = row.receipt {
                    if let presentation = try? TransactionReceiptAuditPresentation(receipt: receipt) {
                        TargetTransactionAuditPanel(presentation: presentation)
                            .accessibilityIdentifier("target-vendor-receipt-audit")
                    } else { Text("Receipt audit unavailable.") }
                } else if row.origin == .vendorPayment && row.category?.kind == .itemized {
                    Text("Receipt details have not finished downloading.")
                }
                if let receipt = row.receipt {
                    ForEach([TransactionReceiptSnapshot.Membership.linked, .returned, .sold], id: \.rawValue) { membership in
                        let items = receipt.items.filter { $0.membership == membership }
                        relatedItems(items.map(\.metadata), section: membership.rawValue,
                            title: membership == .linked ? "Items" : membership == .returned ? "Returned Items" : "Sold Items",
                            amounts: Dictionary(uniqueKeysWithValues: items.compactMap { item in item.amount.map { (item.id, $0) } }),
                            priceFallback: "Purchase price unavailable",
                            badge: membership == .linked ? nil : membership == .returned ? "Returned" : "Sold")
                    }
                }
                if let contents = row.paymentContents {
                    if let items = contents.items {
                        relatedItems(items, section: "payment", title: "Items", amounts: [:], priceFallback: nil)
                    } else { Text("Item details have not finished downloading.").font(.caption) }
                    if let invoice = contents.invoice {
                        CollapsibleSection(title: "Collected Invoice", isExpanded: $invoiceExpanded) {
                            VStack(spacing: Spacing.xs) {
                                Text("Recorded at collection; later Item changes do not change these amounts.").font(.caption)
                                ForEach(invoice.lines, id: \.id) { line in
                                    DetailRow(label: line.description, value: priceLabel(line.signedAmount))
                                }
                                DetailRow(label: "Invoice Total", value: priceLabel(invoice.total), showDivider: false)
                            }.padding(.top, Spacing.xs)
                        }.accessibilityIdentifier("target-transaction-collected-invoice")
                    }
                }
                Text("Accounting, attachment mutation and Item mutation actions are still being connected.").font(.caption)
            }.padding(Spacing.screenPadding)
        }.findEntity(id: row.transactionId.rawValue)
        .sheet(item: $selectedItem) { selected in
            if selected.transactionId == row.transactionId,
               (row.receipt?.items.contains(where: { $0.id == selected.id }) == true
                || row.paymentContents?.itemIDs.contains(selected.id) == true), let itemReader {
                DownloadedItemDetailView(accountId: row.accountId, itemId: selected.id,
                    reader: itemReader, spaceNavigation: spaceNavigation)
            } else { ContentUnavailableView("Item link unavailable", systemImage: "cube") }
        }
    }

    @ViewBuilder private func relatedItems(_ items: [TransactionItemMetadata], section: String, title: String,
        amounts: [ItemID: Money], priceFallback: String?, badge: String? = nil) -> some View {
        if !items.isEmpty || section == "linked" || section == "payment" {
            CollapsibleSection(title: title, isExpanded: Binding(
                get: { expandedItemSections.contains(section) },
                set: { if $0 { expandedItemSections.insert(section) } else { expandedItemSections.remove(section) } }),
                badge: String(items.count), badgeColor: BrandColors.primary) {
                VStack(spacing: Spacing.sm) {
                    if items.isEmpty { Text("No linked Items.").font(.caption) }
                    ForEach(ItemGrouping.groups(in: items, selectedIDs: items.map(\.id),
                        id: { $0.id }, name: { $0.name }, sku: { $0.sku }, source: { $0.source })) { group in
                        if group.rows.count > 1 {
                            let item = group.representative
                            let groupID = RelatedGroupID(membership: section, key: group.id)
                            let thumbnail = group.rows.first { ($0.imageCount ?? 0) > 0 } ?? item
                            let spaces = Set(group.rows.compactMap(\.currentSpaceName).filter { !$0.isEmpty })
                            let total = recordedTotal(group.rows, amounts: amounts).map(priceLabel)
                            GroupedItemCard(name: itemName(item),
                                thumbnailContent: AnyView(itemThumbnail(thumbnail)),
                                countLabel: "×\(group.rows.count)", totalLabel: total, sku: item.sku,
                                sourceLabel: thumbnail.currentSource ?? thumbnail.source,
                                spaceName: spaces.count > 1 ? "Multiple spaces" : spaces.first,
                                priceLabel: total ?? priceFallback,
                                isExpanded: Binding(get: { expandedItemGroups.contains(groupID) },
                                    set: { if $0 { expandedItemGroups.insert(groupID) } else { expandedItemGroups.remove(groupID) } }),
                                itemCount: group.rows.count) {
                                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, member in
                                    itemCard(member, amount: amounts[member.id], priceFallback: priceFallback,
                                        badge: badge, indexLabel: "\(index + 1)/\(group.rows.count)")
                                }
                            }
                            .accessibilityIdentifier("target-transaction-group-\(section)-\(item.id.rawValue)")
                        } else if let item = group.rows.first {
                            itemCard(item, amount: amounts[item.id], priceFallback: priceFallback, badge: badge)
                        }
                    }
                    if itemReader == nil && !items.isEmpty { Text("Item details are unavailable in this workspace.").font(.caption) }
                }.padding(.top, Spacing.xs)
            }
        }
    }

    private func itemName(_ item: TransactionItemMetadata) -> String {
        item.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Item \(item.id.rawValue)"
    }

    private func priceLabel(_ amount: Money) -> String {
        (Decimal(amount.minorUnits) / 100).formatted(.currency(code: amount.currency.rawValue))
    }

    private func recordedTotal(_ items: [TransactionItemMetadata], amounts: [ItemID: Money]) -> Money? {
        guard let first = items.first.flatMap({ amounts[$0.id] }) else { return nil }
        return try? items.dropFirst().reduce(first) { total, item in
            guard let amount = amounts[item.id] else { throw TransactionReceiptSnapshot.Failure.invalidEvidence }
            return try total.adding(amount)
        }
    }

    private func itemCard(_ item: TransactionItemMetadata, amount: Money?, priceFallback: String?,
        badge: String?, indexLabel: String? = nil) -> some View {
        ItemCardPresentation(id: item.id.rawValue, displayName: itemName(item),
            metadata: [amount.map(priceLabel) ?? priceFallback,
                item.currentSource ?? item.source, item.sku,
                item.currentSpaceName.map { "Space: \($0)" }, indexLabel].compactMap { $0 },
            thumbnail: itemThumbnail(item),
            badges: badge.map { [CardBadge(text: $0, color: BrandColors.primary)] } ?? [],
            onPress: itemReader == nil ? nil : { selectedItem = RelatedItemSelection(id: item.id, transactionId: row.transactionId) },
            menuItems: [ActionMenuItem(id: "copy-id", label: "Copy ID", icon: "doc.on.doc",
                onPress: { Clipboard.copy(item.id.rawValue) })])
            .accessibilityIdentifier("target-transaction-item-\(item.id.rawValue)")
    }

    @ViewBuilder private func itemThumbnail(_ item: TransactionItemMetadata) -> some View {
        if let images = itemReader as? any DownloadedItemImageReading {
            DownloadedItemThumbnailView(accountId: row.accountId, itemId: item.id, reader: images)
        } else { ItemCardPlaceholder() }
    }
}
