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
    const value = basis === 'project'
        ? itemData.projectPriceCents
        : itemData.purchasePriceCents;
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}
//# sourceMappingURL=transactionAuditPricing.js.map