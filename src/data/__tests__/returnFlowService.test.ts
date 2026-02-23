jest.mock('../../firebase/firebase', () => ({
  db: null,
  auth: null,
  isFirebaseConfigured: false,
}));
jest.mock('@react-native-firebase/firestore', () => ({
  collection: jest.fn(),
  deleteDoc: jest.fn(),
  doc: jest.fn(),
  getDoc: jest.fn(),
  getDocFromCache: jest.fn(),
  getDocFromServer: jest.fn(),
  getDocs: jest.fn(),
  getDocsFromCache: jest.fn(),
  getDocsFromServer: jest.fn(),
  limit: jest.fn(),
  onSnapshot: jest.fn(),
  orderBy: jest.fn(),
  query: jest.fn(),
  serverTimestamp: jest.fn(),
  setDoc: jest.fn(),
  where: jest.fn(),
}));
jest.mock('../../sync/pendingWrites', () => ({
  trackPendingWrite: jest.fn(),
}));

import { buildReturnEdgeData } from '../returnFlowService';

describe('buildReturnEdgeData', () => {
  it('sets movementKind to returned', () => {
    const result = buildReturnEdgeData({
      accountId: 'acct-1',
      itemId: 'item-1',
      fromTransactionId: 'txn-1',
      returnTransactionId: 'txn-return-1',
    });
    expect(result.movementKind).toBe('returned');
  });

  it('sets source to app', () => {
    const result = buildReturnEdgeData({
      accountId: 'acct-1',
      itemId: 'item-1',
      fromTransactionId: 'txn-1',
      returnTransactionId: 'txn-return-1',
    });
    expect(result.source).toBe('app');
  });

  it('uses fromTransactionId and returnTransactionId correctly', () => {
    const result = buildReturnEdgeData({
      accountId: 'acct-1',
      itemId: 'item-1',
      fromTransactionId: 'txn-purchase',
      returnTransactionId: 'txn-return',
    });
    expect(result.fromTransactionId).toBe('txn-purchase');
    expect(result.toTransactionId).toBe('txn-return');
  });

  it('includes fromProjectId and toProjectId when provided', () => {
    const result = buildReturnEdgeData({
      accountId: 'acct-1',
      itemId: 'item-1',
      fromTransactionId: 'txn-1',
      returnTransactionId: 'txn-return-1',
      fromProjectId: 'proj-1',
      toProjectId: 'proj-2',
    });
    expect(result.fromProjectId).toBe('proj-1');
    expect(result.toProjectId).toBe('proj-2');
  });

  it('defaults fromProjectId and toProjectId to null when omitted', () => {
    const result = buildReturnEdgeData({
      accountId: 'acct-1',
      itemId: 'item-1',
      fromTransactionId: 'txn-1',
      returnTransactionId: 'txn-return-1',
    });
    expect(result.fromProjectId).toBeNull();
    expect(result.toProjectId).toBeNull();
  });

  it('handles null fromTransactionId (item was unlinked)', () => {
    const result = buildReturnEdgeData({
      accountId: 'acct-1',
      itemId: 'item-1',
      fromTransactionId: null,
      returnTransactionId: 'txn-return-1',
    });
    expect(result.fromTransactionId).toBeNull();
    expect(result.toTransactionId).toBe('txn-return-1');
  });

  it('includes accountId and itemId', () => {
    const result = buildReturnEdgeData({
      accountId: 'acct-1',
      itemId: 'item-1',
      fromTransactionId: 'txn-1',
      returnTransactionId: 'txn-return-1',
    });
    expect(result.accountId).toBe('acct-1');
    expect(result.itemId).toBe('item-1');
  });
});
