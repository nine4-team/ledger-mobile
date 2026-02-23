import { buildReassignCorrectionEdge } from '../reassignEdgeBuilder';

describe('buildReassignCorrectionEdge', () => {
  const baseParams = {
    accountId: 'acc-1',
    itemId: 'item-1',
    transactionId: 'tx-1',
    note: 'Reassigned to correct space',
  };

  it('builds edge with movementKind correction', () => {
    const edge = buildReassignCorrectionEdge(baseParams);
    expect(edge.movementKind).toBe('correction');
  });

  it('sets source to app', () => {
    const edge = buildReassignCorrectionEdge(baseParams);
    expect(edge.source).toBe('app');
  });

  it('uses provided note', () => {
    const edge = buildReassignCorrectionEdge({
      ...baseParams,
      note: 'Moved item to correct category',
    });
    expect(edge.note).toBe('Moved item to correct category');
  });

  it('sets fromTransactionId and toTransactionId to same value when transactionId provided', () => {
    const edge = buildReassignCorrectionEdge(baseParams);
    expect(edge.fromTransactionId).toBe('tx-1');
    expect(edge.toTransactionId).toBe('tx-1');
    expect(edge.fromTransactionId).toBe(edge.toTransactionId);
  });

  it('handles null transactionId for item-level reassign', () => {
    const edge = buildReassignCorrectionEdge({
      ...baseParams,
      transactionId: null,
    });
    expect(edge.fromTransactionId).toBeNull();
    expect(edge.toTransactionId).toBeNull();
  });

  it('includes accountId and itemId from params', () => {
    const edge = buildReassignCorrectionEdge({
      accountId: 'acc-42',
      itemId: 'item-99',
      transactionId: null,
      note: 'test',
    });
    expect(edge.accountId).toBe('acc-42');
    expect(edge.itemId).toBe('item-99');
  });
});
