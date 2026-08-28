const test = require('node:test');
const assert = require('node:assert/strict');

const {
  transactionCategoryIdForCompleteness,
} = require('../lib/transactionCategory.js');

test('completeness uses the active project category first', () => {
  assert.equal(transactionCategoryIdForCompleteness({
    budgetCategoryId: 'active',
    intendedBudgetCategoryId: 'intended',
  }), 'active');
});

test('inventory acquisitions use intended category for completeness', () => {
  assert.equal(transactionCategoryIdForCompleteness({
    budgetCategoryId: null,
    intendedBudgetCategoryId: 'furnishings',
  }), 'furnishings');
});

test('blank category values do not make a transaction itemized', () => {
  assert.equal(transactionCategoryIdForCompleteness({
    budgetCategoryId: '  ',
    intendedBudgetCategoryId: null,
  }), null);
});
