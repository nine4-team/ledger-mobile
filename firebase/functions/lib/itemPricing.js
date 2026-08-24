"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizedProjectPriceCents = normalizedProjectPriceCents;
exports.needsProjectPriceRepair = needsProjectPriceRepair;
function cents(value) {
    return typeof value === 'number' && Number.isFinite(value) ? value : null;
}
function normalizedProjectPriceCents(data) {
    const purchasePrice = cents(data.purchasePriceCents);
    const projectPrice = cents(data.projectPriceCents);
    if (purchasePrice == null && projectPrice == null)
        return null;
    return Math.max(purchasePrice ?? 0, projectPrice ?? 0);
}
function needsProjectPriceRepair(data) {
    const normalized = normalizedProjectPriceCents(data);
    return normalized != null && cents(data.projectPriceCents) !== normalized;
}
//# sourceMappingURL=itemPricing.js.map