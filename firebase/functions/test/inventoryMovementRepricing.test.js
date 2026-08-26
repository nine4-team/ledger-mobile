const test = require('node:test');
const assert = require('node:assert/strict');

const {
  adjustInventoryPurchaseTotals,
  hasStableProjectTransactionAssociation,
  isPaidInvoiceForItem,
  isProjectInventoryPurchase,
  itemProjectPriceContribution,
  projectPriceChange,
} = require('../lib/inventoryMovementRepricing.js');

test('paid invoice detection supports flat membership and legacy item lines', () => {
  assert.equal(isPaidInvoiceForItem({
    status: 'paid',
    projectId: 'project-1',
    itemIds: ['item-1'],
  }, 'project-1', 'item-1'), true);

  assert.equal(isPaidInvoiceForItem({
    status: 'paid',
    projectId: 'project-1',
    lines: [{ sourceType: 'item', sourceId: 'item-1' }],
  }, 'project-1', 'item-1'), true);

  assert.equal(isPaidInvoiceForItem({
    status: 'paid',
    projectId: 'old-project',
    itemIds: ['item-1'],
  }, 'new-project', 'item-1'), false);

  assert.equal(isPaidInvoiceForItem({
    status: 'sent',
    projectId: 'project-1',
    itemIds: ['item-1'],
  }, 'project-1', 'item-1'), false);
});

test('stable association excludes the sell event itself and later moves', () => {
  assert.equal(hasStableProjectTransactionAssociation(
    { projectId: 'project-1', transactionId: 'sale-tx' },
    { projectId: 'project-1', transactionId: 'sale-tx' }
  ), true);

  assert.equal(hasStableProjectTransactionAssociation(
    { projectId: null, transactionId: 'vendor-purchase' },
    { projectId: 'project-1', transactionId: 'sale-tx' }
  ), false);

  assert.equal(hasStableProjectTransactionAssociation(
    { projectId: 'project-1', transactionId: 'sale-tx' },
    { projectId: 'project-2', transactionId: 'next-sale-tx' }
  ), false);
});

test('projectPriceChange adjusts subtotal and tax-inclusive amount', () => {
  const change = projectPriceChange(
    { purchasePriceCents: 8_000, projectPriceCents: 10_000, taxRatePct: 8.25 },
    { purchasePriceCents: 8_000, projectPriceCents: 12_000, taxRatePct: 8.25 }
  );

  assert.deepEqual(change, {
    subtotalDeltaCents: 2_000,
    amountDeltaCents: 2_165,
  });
});

test('projectPriceChange follows the purchase-cost floor', () => {
  const change = projectPriceChange(
    { purchasePriceCents: 8_000, projectPriceCents: 10_000 },
    { purchasePriceCents: 11_000, projectPriceCents: 10_000 }
  );

  assert.deepEqual(change, {
    subtotalDeltaCents: 1_000,
    amountDeltaCents: 1_000,
  });
});

test('projectPriceChange includes tax-only corrections', () => {
  const change = projectPriceChange(
    { purchasePriceCents: 8_000, projectPriceCents: 10_000, taxRatePct: 0 },
    { purchasePriceCents: 8_000, projectPriceCents: 10_000, taxRatePct: 10 }
  );

  assert.deepEqual(change, {
    subtotalDeltaCents: 0,
    amountDeltaCents: 1_000,
  });
});

test('itemProjectPriceContribution treats missing and invalid tax as zero', () => {
  assert.deepEqual(
    itemProjectPriceContribution({ purchasePriceCents: 5_000, projectPriceCents: 6_000, taxRatePct: -5 }),
    { subtotalCents: 6_000, amountCents: 6_000 }
  );
});

test('isProjectInventoryPurchase accepts only the project-side transaction created by a sale', () => {
  assert.equal(isProjectInventoryPurchase({
    type: 'Purchase',
    source: '1584 Design Inventory',
    projectId: 'project-1',
    amountCents: 10_000,
  }), true);

  assert.equal(isProjectInventoryPurchase({
    type: 'Purchase',
    source: 'HomeGoods',
    projectId: null,
    amountCents: 10_000,
  }), false);

  assert.equal(isProjectInventoryPurchase({
    type: 'Sale',
    source: '1584 Design Inventory',
    projectId: 'project-1',
    amountCents: 10_000,
  }), false);

  assert.equal(isProjectInventoryPurchase({
    type: 'Purchase',
    source: '1584 Design Inventory',
    projectId: 'project-1',
    amountCents: 10_000,
    isCanonicalInventorySale: true,
  }), false);

  assert.equal(isProjectInventoryPurchase({
    type: 'Purchase',
    source: '1584 Design Inventory',
    projectId: 'project-1',
  }), false);
});

test('adjustInventoryPurchaseTotals changes only transaction amounts and matching audit sums', () => {
  const adjusted = adjustInventoryPurchaseTotals(
    {
      amountCents: 32_475,
      subtotalCents: 30_000,
      isComplete: true,
      audit: {
        resolvedSubtotalCents: 30_000,
        itemsSumCents: 30_000,
        linkedItemsSumCents: 20_000,
        returnedItemsSumCents: 10_000,
        varianceCents: 0,
        variancePercent: 0,
      },
    },
    { subtotalDeltaCents: 2_000, amountDeltaCents: 2_165 }
  );

  assert.equal(adjusted.amountCents, 34_640);
  assert.equal(adjusted.subtotalCents, 32_000);
  assert.deepEqual(adjusted.audit, {
    resolvedSubtotalCents: 32_000,
    itemsSumCents: 32_000,
    linkedItemsSumCents: 22_000,
    returnedItemsSumCents: 10_000,
    varianceCents: 0,
    variancePercent: 0,
  });
});

test('adjustInventoryPurchaseTotals preserves a missing legacy subtotal', () => {
  const adjusted = adjustInventoryPurchaseTotals(
    { amountCents: 10_000 },
    { subtotalDeltaCents: 2_000, amountDeltaCents: 2_000 }
  );

  assert.equal(adjusted.amountCents, 12_000);
  assert.equal(adjusted.subtotalCents, undefined);
});

test('delayed repricing does not add its delta to linked audit after the item left', () => {
  const adjusted = adjustInventoryPurchaseTotals(
    {
      amountCents: 10_000,
      subtotalCents: 10_000,
      audit: {
        resolvedSubtotalCents: 10_000,
        itemsSumCents: 10_000,
        linkedItemsSumCents: 0,
        soldItemsSumCents: 10_000,
      },
    },
    { subtotalDeltaCents: 2_000, amountDeltaCents: 2_000 },
    false
  );

  assert.equal(adjusted.audit.resolvedSubtotalCents, 12_000);
  assert.equal(adjusted.audit.itemsSumCents, 12_000);
  assert.equal(adjusted.audit.linkedItemsSumCents, 0);
  assert.equal(adjusted.audit.soldItemsSumCents, 10_000);
});

test('adjustInventoryPurchaseTotals rejects corrupt negative results', () => {
  assert.throws(
    () => adjustInventoryPurchaseTotals(
      { amountCents: 500, subtotalCents: 500 },
      { subtotalDeltaCents: -1_000, amountDeltaCents: -1_000 }
    ),
    /negative/i
  );
});

test('adjustInventoryPurchaseTotals rejects a missing current amount', () => {
  assert.throws(
    () => adjustInventoryPurchaseTotals(
      { subtotalCents: 500 },
      { subtotalDeltaCents: 100, amountDeltaCents: 100 }
    ),
    /numeric amount/i
  );
});
