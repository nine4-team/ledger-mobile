const test = require('node:test');
const assert = require('node:assert/strict');

const {
  needsProjectPriceRepair,
  normalizedProjectPriceCents,
} = require('../lib/itemPricing');

test('missing project price inherits purchase price', () => {
  const item = { purchasePriceCents: 12500 };
  assert.equal(normalizedProjectPriceCents(item), 12500);
  assert.equal(needsProjectPriceRepair(item), true);
});

test('project price below purchase price is raised', () => {
  const item = { purchasePriceCents: 12500, projectPriceCents: 0 };
  assert.equal(normalizedProjectPriceCents(item), 12500);
  assert.equal(needsProjectPriceRepair(item), true);
});

test('higher project price is preserved', () => {
  const item = { purchasePriceCents: 12500, projectPriceCents: 15000 };
  assert.equal(normalizedProjectPriceCents(item), 15000);
  assert.equal(needsProjectPriceRepair(item), false);
});

test('price-less item does not gain a synthetic price', () => {
  assert.equal(normalizedProjectPriceCents({}), null);
  assert.equal(needsProjectPriceRepair({}), false);
});
