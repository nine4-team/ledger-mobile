import Foundation
@testable import LedgeriOS

// MARK: - Item

func makeItem(
    id: String? = nil,
    accountId: String? = nil,
    projectId: String? = nil,
    spaceId: String? = nil,
    name: String? = nil,
    description: String? = nil,
    notes: String? = nil,
    status: String? = nil,
    source: String? = nil,
    sku: String? = nil,
    transactionId: String? = nil,
    purchasePriceCents: Int? = nil,
    projectPriceCents: Int? = nil,
    marketValueCents: Int? = nil,
    purchasedBy: String? = nil,
    bookmark: Bool? = nil,
    budgetCategoryId: String? = nil,
    quantity: Int? = nil,
    taxRatePct: Double? = nil,
    taxAmountPurchasePriceCents: Int? = nil,
    taxAmountProjectPriceCents: Int? = nil,
    images: [AttachmentRef]? = nil,
    createdBy: String? = nil,
    updatedBy: String? = nil
) -> Item {
    var item = Item()
    item.id = id ?? UUID().uuidString
    item.accountId = accountId
    item.projectId = projectId
    item.spaceId = spaceId
    item.name = name
    item.description = description
    item.notes = notes
    item.status = status
    item.source = source
    item.sku = sku
    item.transactionId = transactionId
    item.purchasePriceCents = purchasePriceCents
    item.projectPriceCents = projectPriceCents
    item.marketValueCents = marketValueCents
    item.purchasedBy = purchasedBy
    item.bookmark = bookmark
    item.budgetCategoryId = budgetCategoryId
    item.quantity = quantity
    item.taxRatePct = taxRatePct
    item.taxAmountPurchasePriceCents = taxAmountPurchasePriceCents
    item.taxAmountProjectPriceCents = taxAmountProjectPriceCents
    item.images = images
    item.createdBy = createdBy
    item.updatedBy = updatedBy
    return item
}

// MARK: - Transaction

func makeTransaction(
    id: String? = nil,
    projectId: String? = nil,
    transactionDate: String? = nil,
    amountCents: Int? = nil,
    source: String? = nil,
    isCanonicalInventory: Bool? = nil,
    canonicalKind: String? = nil,
    isCanonicalInventorySale: Bool? = nil,
    inventorySaleDirection: InventorySaleDirection? = nil,
    itemIds: [String]? = nil,
    status: String? = nil,
    purchasedBy: String? = nil,
    reimbursementType: String? = nil,
    notes: String? = nil,
    transactionType: String? = nil,
    isCanceled: Bool? = nil,
    budgetCategoryId: String? = nil,
    paymentMethod: String? = nil,
    hasEmailReceipt: Bool? = nil,
    receiptImages: [AttachmentRef]? = nil,
    otherImages: [AttachmentRef]? = nil,
    transactionImages: [AttachmentRef]? = nil,
    needsReview: Bool? = nil,
    taxRatePct: Double? = nil,
    subtotalCents: Int? = nil,
    triggerEvent: String? = nil
) -> Transaction {
    var tx = Transaction()
    tx.id = id ?? UUID().uuidString
    tx.projectId = projectId
    tx.transactionDate = transactionDate
    tx.amountCents = amountCents
    tx.source = source
    tx.isCanonicalInventory = isCanonicalInventory
    tx.canonicalKind = canonicalKind
    tx.isCanonicalInventorySale = isCanonicalInventorySale
    tx.inventorySaleDirection = inventorySaleDirection
    tx.itemIds = itemIds
    tx.status = status
    tx.purchasedBy = purchasedBy
    tx.reimbursementType = reimbursementType
    tx.notes = notes
    tx.transactionType = transactionType
    tx.isCanceled = isCanceled
    tx.budgetCategoryId = budgetCategoryId
    tx.paymentMethod = paymentMethod
    tx.hasEmailReceipt = hasEmailReceipt
    tx.receiptImages = receiptImages
    tx.otherImages = otherImages
    tx.transactionImages = transactionImages
    tx.needsReview = needsReview
    tx.taxRatePct = taxRatePct
    tx.subtotalCents = subtotalCents
    tx.triggerEvent = triggerEvent
    return tx
}

// MARK: - Space

func makeSpace(
    id: String? = nil,
    accountId: String? = nil,
    projectId: String? = nil,
    name: String = "",
    notes: String? = nil,
    images: [AttachmentRef]? = nil,
    checklists: [Checklist]? = nil,
    isArchived: Bool? = nil
) -> Space {
    var space = Space()
    space.id = id ?? UUID().uuidString
    space.accountId = accountId
    space.projectId = projectId
    space.name = name
    space.notes = notes
    space.images = images
    space.checklists = checklists
    space.isArchived = isArchived
    return space
}

// MARK: - Project

func makeProject(
    id: String? = nil,
    accountId: String? = nil,
    name: String = "",
    clientName: String = "",
    description: String? = nil,
    isArchived: Bool? = nil,
    budgetSummary: ProjectBudgetSummary? = nil
) -> Project {
    var project = Project()
    project.id = id ?? UUID().uuidString
    project.accountId = accountId
    project.name = name
    project.clientName = clientName
    project.description = description
    project.isArchived = isArchived
    project.budgetSummary = budgetSummary
    return project
}
