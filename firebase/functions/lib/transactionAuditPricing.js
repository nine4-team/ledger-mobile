"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.auditPriceBasis = auditPriceBasis;
exports.auditItemPriceCents = auditItemPriceCents;
/**
 * Project-destination Purchases from business inventory are charged at the
 * client-facing project price. Vendor Purchases and Returns reconcile to cost.
 * The Inventory suffix is the repository-wide discriminator for inventory
 * movement sources, including historical branded labels.
 */
function auditPriceBasis(txData) {
    const rawType = txData.type ?? txData.transactionType;
    const type = typeof rawType === 'string' ? rawType.trim().toLowerCase() : '';
    const source = typeof txData.source === 'string' ? txData.source.trim() : '';
    const hasProject = typeof txData.projectId === 'string' && txData.projectId.trim().length > 0;
    return type === 'purchase' && hasProject && source.endsWith(' Inventory')
        ? 'project'
        : 'purchase';
}
function auditItemPriceCents(basis, itemData) {
    const purchasePrice = typeof itemData.purchasePriceCents === 'number' &&
        Number.isFinite(itemData.purchasePriceCents)
        ? itemData.purchasePriceCents
        : 0;
    if (basis === 'purchase')
        return purchasePrice;
    const projectPrice = typeof itemData.projectPriceCents === 'number' &&
        Number.isFinite(itemData.projectPriceCents)
        ? itemData.projectPriceCents
        : 0;
    return Math.max(purchasePrice, projectPrice);
}
//# sourceMappingURL=transactionAuditPricing.js.map