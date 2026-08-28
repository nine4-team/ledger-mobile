"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.transactionCategoryIdForCompleteness = transactionCategoryIdForCompleteness;
function realCategoryId(value) {
    if (typeof value !== 'string')
        return null;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
}
/**
 * Inventory resale acquisitions keep their project category as planning
 * metadata because their active project scope/category are both null. Their
 * completeness audit must still use that intended category so itemized
 * purchases remain in Needs Review until their receipt lines reconcile.
 */
function transactionCategoryIdForCompleteness(txData) {
    return realCategoryId(txData.budgetCategoryId)
        ?? realCategoryId(txData.intendedBudgetCategoryId);
}
//# sourceMappingURL=transactionCategory.js.map