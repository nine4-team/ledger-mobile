"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isPaidInvoiceForItem = isPaidInvoiceForItem;
exports.hasStableProjectTransactionAssociation = hasStableProjectTransactionAssociation;
exports.itemProjectPriceContribution = itemProjectPriceContribution;
exports.projectPriceChange = projectPriceChange;
exports.isProjectInventoryPurchase = isProjectInventoryPurchase;
exports.adjustInventoryPurchaseTotals = adjustInventoryPurchaseTotals;
function isPaidInvoiceForItem(invoice, projectId, itemId) {
    const status = typeof invoice.status === 'string' ? invoice.status.trim().toLowerCase() : '';
    if (status !== 'paid' || invoice.projectId !== projectId)
        return false;
    const flatItemIds = Array.isArray(invoice.itemIds) ? invoice.itemIds : [];
    if (flatItemIds.includes(itemId))
        return true;
    const legacyLines = Array.isArray(invoice.lines) ? invoice.lines : [];
    return legacyLines.some((line) => line != null &&
        typeof line === 'object' &&
        line.sourceType === 'item' &&
        line.sourceId === itemId);
}
function hasStableProjectTransactionAssociation(before, after) {
    const beforeProjectId = typeof before.projectId === 'string' ? before.projectId.trim() : '';
    const afterProjectId = typeof after.projectId === 'string' ? after.projectId.trim() : '';
    const beforeTransactionId = typeof before.transactionId === 'string' ? before.transactionId.trim() : '';
    const afterTransactionId = typeof after.transactionId === 'string' ? after.transactionId.trim() : '';
    return beforeProjectId.length > 0 &&
        beforeProjectId === afterProjectId &&
        beforeTransactionId.length > 0 &&
        beforeTransactionId === afterTransactionId;
}
function nonnegativeCents(value) {
    if (typeof value !== 'number' || !Number.isFinite(value))
        return 0;
    return Math.max(0, Math.round(value));
}
function nonnegativeTaxRate(value) {
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0)
        return 0;
    return value;
}
function itemProjectPriceContribution(data) {
    const priceCents = Math.max(nonnegativeCents(data.purchasePriceCents), nonnegativeCents(data.projectPriceCents));
    const taxRatePct = nonnegativeTaxRate(data.taxRatePct);
    const amountCents = taxRatePct > 0
        ? Math.round(priceCents * (1 + taxRatePct / 100))
        : priceCents;
    return { subtotalCents: priceCents, amountCents };
}
function projectPriceChange(before, after) {
    const previous = itemProjectPriceContribution(before);
    const next = itemProjectPriceContribution(after);
    return {
        subtotalDeltaCents: next.subtotalCents - previous.subtotalCents,
        amountDeltaCents: next.amountCents - previous.amountCents,
    };
}
/**
 * True only for the project-side Purchase-from-Inventory transaction created
 * by an inventory sale. Vendor purchases, inventory-scope acquisitions,
 * project egress Sales/Returns, and legacy canonical sales are excluded.
 */
function isProjectInventoryPurchase(data) {
    const rawType = data.type ?? data.transactionType;
    const type = typeof rawType === 'string' ? rawType.trim().toLowerCase() : '';
    const source = typeof data.source === 'string' ? data.source.trim() : '';
    const projectId = typeof data.projectId === 'string' ? data.projectId.trim() : '';
    return type === 'purchase' &&
        source.endsWith(' Inventory') &&
        projectId.length > 0 &&
        typeof data.amountCents === 'number' &&
        Number.isFinite(data.amountCents) &&
        data.amountCents >= 0 &&
        data.isCanonicalInventorySale !== true;
}
function adjustedNumber(value, delta) {
    if (typeof value !== 'number' || !Number.isFinite(value))
        return undefined;
    return Math.round(value) + delta;
}
/**
 * Apply one item's project-price delta to a multi-item movement total. This
 * intentionally does not recompute from transaction.itemIds: itemIds is active
 * membership and may no longer include items that were later returned or sold.
 */
function adjustInventoryPurchaseTotals(transaction, change, itemIsActiveMember = true) {
    const currentAmount = adjustedNumber(transaction.amountCents, 0);
    if (currentAmount == null || currentAmount < 0) {
        throw new Error('Inventory Purchase repricing requires a nonnegative numeric amount.');
    }
    const nextAmount = currentAmount + change.amountDeltaCents;
    const currentSubtotal = adjustedNumber(transaction.subtotalCents, 0);
    const nextSubtotal = currentSubtotal == null
        ? undefined
        : currentSubtotal + change.subtotalDeltaCents;
    if (nextAmount < 0 || (nextSubtotal != null && nextSubtotal < 0)) {
        throw new Error('Inventory Purchase repricing would produce a negative transaction total.');
    }
    const result = {
        amountCents: nextAmount,
    };
    if (nextSubtotal != null)
        result.subtotalCents = nextSubtotal;
    if ('isComplete' in transaction)
        result.isComplete = transaction.isComplete;
    if (transaction.audit && typeof transaction.audit === 'object' && !Array.isArray(transaction.audit)) {
        const audit = { ...transaction.audit };
        const resolvedSubtotal = adjustedNumber(audit.resolvedSubtotalCents, change.subtotalDeltaCents);
        const itemsSum = adjustedNumber(audit.itemsSumCents, change.subtotalDeltaCents);
        const linkedItemsSum = itemIsActiveMember
            ? adjustedNumber(audit.linkedItemsSumCents, change.subtotalDeltaCents)
            : adjustedNumber(audit.linkedItemsSumCents, 0);
        if (resolvedSubtotal != null)
            audit.resolvedSubtotalCents = resolvedSubtotal;
        if (itemsSum != null)
            audit.itemsSumCents = itemsSum;
        if (linkedItemsSum != null)
            audit.linkedItemsSumCents = linkedItemsSum;
        if (resolvedSubtotal != null && resolvedSubtotal > 0 && itemsSum != null) {
            const discount = nonnegativeCents(audit.discountCents);
            const variance = Math.max(0, itemsSum - discount) - resolvedSubtotal;
            audit.varianceCents = variance;
            audit.variancePercent = Math.round((variance / resolvedSubtotal) * 10000) / 100;
            result.isComplete = Math.abs(audit.variancePercent) <= 1;
        }
        result.audit = audit;
    }
    return result;
}
//# sourceMappingURL=inventoryMovementRepricing.js.map