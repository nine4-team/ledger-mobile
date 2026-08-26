const test = require('node:test');
const assert = require('node:assert/strict');

const {
  auditItemPriceCents,
  auditPriceBasis,
} = require('../lib/transactionAuditPricing.js');

test('inventory-sourced project Purchase uses project prices', () => {
  const basis = auditPriceBasis({
    type: 'Purchase',
    projectId: 'project-1',
    source: '1584 Design Inventory',
  });

  assert.equal(basis, 'project');
  assert.equal(auditItemPriceCents(basis, {
    purchasePriceCents: 37698,
    projectPriceCents: 47123,
  }), 47123);
});

test('ordinary vendor Purchase remains purchase-price based', () => {
  const basis = auditPriceBasis({
    type: 'Purchase',
    projectId: 'project-1',
    source: 'Wayfair',
  });

  assert.equal(basis, 'purchase');
  assert.equal(auditItemPriceCents(basis, {
    purchasePriceCents: 37698,
    projectPriceCents: 47123,
  }), 37698);
});

test('inventory Returns use project prices', () => {
  const basis = auditPriceBasis({
    type: 'Return',
    projectId: 'project-1',
    source: '1584 Design Inventory',
  });

  assert.equal(basis, 'project');
});

test('inventory Sales remain purchase-price based acquisitions', () => {
  const basis = auditPriceBasis({
    type: 'Sale',
    projectId: 'project-1',
    source: '1584 Design Inventory',
  });

  assert.equal(basis, 'purchase');
});

test('vendor Returns remain purchase-price based', () => {
  const basis = auditPriceBasis({
    type: 'Return',
    projectId: 'project-1',
    source: 'Wayfair',
  });

  assert.equal(basis, 'purchase');
});

test('inventory-scope Purchases do not use project prices', () => {
  const basis = auditPriceBasis({
    type: 'Purchase',
    source: 'Business Inventory',
  });

  assert.equal(basis, 'purchase');
});

test('project basis defensively applies the purchase-cost floor', () => {
  assert.equal(auditItemPriceCents('project', { purchasePriceCents: 10000 }), 10000);
  assert.equal(auditItemPriceCents('project', {
    purchasePriceCents: 10000,
    projectPriceCents: 0,
  }), 10000);
  assert.equal(auditItemPriceCents('purchase', { projectPriceCents: 12000 }), 0);
});
