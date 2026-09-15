const test = require('node:test');
const assert = require('node:assert/strict');
const { collectDocumentReferences } = require('../export-authorized-project-readonly.cjs');
const account = 'projects/source/databases/(default)/documents/accounts/account';
const string = stringValue => ({ stringValue });
const array = values => ({ arrayValue: { values } });
const map = fields => ({ mapValue: { fields } });
const document = fields => ({ name: account + '/invoices/invoice', fields });

test('follows Invoice indices, typed sources and settlement references without inventing line documents', () => {
  const refs = collectDocumentReferences(account, document({ projectId: string('project'),
    transactionIds: array([string('cost')]), lines: array([
      map({ id: string('line1'), sourceType: string('transaction'), sourceId: string('cost'),
        settlementTransactionIds: array([string('payment')]) }),
      map({ id: string('line2'), sourceType: string('item'), sourceId: string('item') }),
      map({ id: string('line3'), sourceType: string('feeInstallment'), sourceId: string('fee') }),
      map({ id: string('line4'), sourceType: string('manual'), sourceId: string('not-a-document') }),
    ]) }));
  assert.deepEqual(refs.sort(), ['projects/project', 'transactions/cost', 'transactions/payment',
    'items/item', 'projects/project/feeInstallments/fee'].map(path => account + '/' + path).sort());
  const payment = { name: account + '/transactions/payment', fields: {
    settlementInvoiceId: string('invoice'), settlementInvoiceLineIds: array([string('line1')]) } };
  assert.deepEqual(collectDocumentReferences(account, payment), [account + '/invoices/invoice']);
});
test('preserves previous Item/lineage/category reference discovery and deduplicates', () => {
  const refs = collectDocumentReferences(account, document({ itemIds: array([string('item'), string('item')]),
    nested: map({ fromTransactionId: string('old'), budgetCategoryId: string('category') }),
    existingSaleMovementEdgeIds: array([string('edge')]) }));
  assert.deepEqual(refs.sort(), ['items/item', 'transactions/old', 'presets/default/budgetCategories/category',
    'lineageEdges/edge'].map(path => account + '/' + path).sort());
});
test('never expands outside Account or guesses an unscoped fee source', () => {
  assert.throws(() => collectDocumentReferences(account, { name: account + '-other/invoices/invoice', fields: {} }));
  assert.throws(() => collectDocumentReferences(account, document({ lines: array([
    map({ sourceType: string('feeInstallment'), sourceId: string('fee') })]) })));
  assert.deepEqual(collectDocumentReferences(account, document({ transactionIds: array([
    string('../other'), string('..'), string('a/b'), string('')]),
    settlementInvoiceLineIds: array([string('line')]) })), []);
});
