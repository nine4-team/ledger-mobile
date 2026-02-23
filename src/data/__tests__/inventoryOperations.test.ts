// Mock Firebase dependencies so importing inventoryOperations doesn't fail
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
jest.mock('../../sync/requestDocTracker', () => ({
  trackRequestDocPath: jest.fn(),
}));

jest.mock('../requestDocs', () => ({
  createRequestDoc: jest.fn(() => 'mock-request-id'),
  generateRequestOpId: jest.fn(() => 'mock-op-id'),
}));

import {
  isCanonicalInventorySaleTransaction,
  requestProjectToBusinessSale,
  requestBusinessToProjectPurchase,
  requestProjectToProjectMove,
} from '../inventoryOperations';

import { createRequestDoc, generateRequestOpId } from '../requestDocs';

beforeEach(() => {
  jest.clearAllMocks();
  (createRequestDoc as jest.Mock).mockReturnValue('mock-request-id');
  (generateRequestOpId as jest.Mock).mockReturnValue('mock-op-id');
});

// ---------------------------------------------------------------------------
// isCanonicalInventorySaleTransaction
// ---------------------------------------------------------------------------

describe('isCanonicalInventorySaleTransaction', () => {
  it('returns false for null/undefined', () => {
    expect(isCanonicalInventorySaleTransaction(null)).toBe(false);
    expect(isCanonicalInventorySaleTransaction(undefined)).toBe(false);
  });

  it('returns true when isCanonicalInventorySale is true', () => {
    expect(isCanonicalInventorySaleTransaction({ isCanonicalInventorySale: true })).toBe(true);
  });

  it('returns false when isCanonicalInventorySale is false with no other indicators', () => {
    expect(isCanonicalInventorySaleTransaction({ isCanonicalInventorySale: false })).toBe(false);
  });

  it('returns true when inventorySaleDirection is set', () => {
    expect(isCanonicalInventorySaleTransaction({ inventorySaleDirection: 'project_to_business' })).toBe(true);
    expect(isCanonicalInventorySaleTransaction({ inventorySaleDirection: 'business_to_project' })).toBe(true);
  });

  it('returns true when id starts with SALE_', () => {
    expect(isCanonicalInventorySaleTransaction({ id: 'SALE_abc123' })).toBe(true);
  });

  it('returns false when id does not start with SALE_', () => {
    expect(isCanonicalInventorySaleTransaction({ id: 'txn-123' })).toBe(false);
  });

  it('returns false for empty object', () => {
    expect(isCanonicalInventorySaleTransaction({})).toBe(false);
  });

  it('checks fields in priority order: isCanonicalInventorySale > direction > id prefix', () => {
    // isCanonicalInventorySale takes priority even with a non-SALE id
    expect(isCanonicalInventorySaleTransaction({ id: 'txn-123', isCanonicalInventorySale: true })).toBe(true);
    // direction takes priority over id
    expect(isCanonicalInventorySaleTransaction({ id: 'txn-123', inventorySaleDirection: 'project_to_business' })).toBe(true);
  });

  it('handles null values for individual fields', () => {
    expect(isCanonicalInventorySaleTransaction({ id: null, isCanonicalInventorySale: null, inventorySaleDirection: null })).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// requestProjectToBusinessSale
// ---------------------------------------------------------------------------

describe('requestProjectToBusinessSale', () => {
  const accountId = 'acc-1';
  const projectId = 'proj-1';

  it('creates one request doc per item with correct payload', () => {
    const items = [
      { id: 'item-1', projectId: 'proj-1', transactionId: 'txn-1', budgetCategoryId: 'cat-A' },
      { id: 'item-2', projectId: 'proj-1', transactionId: null, budgetCategoryId: 'cat-B' },
    ];

    const result = requestProjectToBusinessSale({ accountId, projectId, items });

    expect(result).toEqual(['mock-request-id', 'mock-request-id']);
    expect(createRequestDoc).toHaveBeenCalledTimes(2);

    expect(createRequestDoc).toHaveBeenCalledWith(
      'ITEM_SALE_PROJECT_TO_BUSINESS',
      {
        itemId: 'item-1',
        sourceProjectId: 'proj-1',
        budgetCategoryId: 'cat-A',
        expected: { itemProjectId: 'proj-1', itemTransactionId: 'txn-1' },
      },
      { accountId: 'acc-1', scope: 'account' },
      'mock-op-id',
    );

    expect(createRequestDoc).toHaveBeenCalledWith(
      'ITEM_SALE_PROJECT_TO_BUSINESS',
      {
        itemId: 'item-2',
        sourceProjectId: 'proj-1',
        budgetCategoryId: 'cat-B',
        expected: { itemProjectId: 'proj-1', itemTransactionId: null },
      },
      { accountId: 'acc-1', scope: 'account' },
      'mock-op-id',
    );
  });

  it('falls back to params.budgetCategoryId when item has no category', () => {
    const items = [{ id: 'item-1', budgetCategoryId: null }];

    requestProjectToBusinessSale({ accountId, projectId, items, budgetCategoryId: 'fallback-cat' });

    expect(createRequestDoc).toHaveBeenCalledWith(
      'ITEM_SALE_PROJECT_TO_BUSINESS',
      expect.objectContaining({ budgetCategoryId: 'fallback-cat' }),
      expect.any(Object),
      expect.any(String),
    );
  });

  it('throws when item has no category and no fallback is provided', () => {
    const items = [{ id: 'item-1', budgetCategoryId: null }];

    expect(() => requestProjectToBusinessSale({ accountId, projectId, items }))
      .toThrow('Missing budgetCategoryId');
  });

  it('uses provided opId instead of generating one', () => {
    const items = [{ id: 'item-1', budgetCategoryId: 'cat-A' }];

    requestProjectToBusinessSale({ accountId, projectId, items, opId: 'custom-op' });

    expect(generateRequestOpId).not.toHaveBeenCalled();
    expect(createRequestDoc).toHaveBeenCalledWith(
      expect.any(String),
      expect.any(Object),
      expect.any(Object),
      'custom-op',
    );
  });

  it('generates opId when none provided', () => {
    const items = [{ id: 'item-1', budgetCategoryId: 'cat-A' }];

    requestProjectToBusinessSale({ accountId, projectId, items });

    expect(generateRequestOpId).toHaveBeenCalled();
  });

  it('defaults missing projectId and transactionId to null in expected', () => {
    const items = [{ id: 'item-1', budgetCategoryId: 'cat-A' }];

    requestProjectToBusinessSale({ accountId, projectId, items });

    expect(createRequestDoc).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        expected: { itemProjectId: null, itemTransactionId: null },
      }),
      expect.any(Object),
      expect.any(String),
    );
  });

  it('returns empty array for empty items', () => {
    const result = requestProjectToBusinessSale({ accountId, projectId, items: [] });

    expect(result).toEqual([]);
    expect(createRequestDoc).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// requestBusinessToProjectPurchase
// ---------------------------------------------------------------------------

describe('requestBusinessToProjectPurchase', () => {
  const accountId = 'acc-1';
  const targetProjectId = 'proj-dest';
  const budgetCategoryId = 'cat-X';

  it('creates one request doc per item with correct payload', () => {
    const items = [
      { id: 'item-1', projectId: null, transactionId: 'txn-1' },
      { id: 'item-2' },
    ];

    const result = requestBusinessToProjectPurchase({ accountId, targetProjectId, budgetCategoryId, items });

    expect(result).toEqual(['mock-request-id', 'mock-request-id']);
    expect(createRequestDoc).toHaveBeenCalledTimes(2);

    expect(createRequestDoc).toHaveBeenCalledWith(
      'ITEM_SALE_BUSINESS_TO_PROJECT',
      {
        itemId: 'item-1',
        targetProjectId: 'proj-dest',
        budgetCategoryId: 'cat-X',
        expected: { itemProjectId: null, itemTransactionId: 'txn-1' },
      },
      { accountId: 'acc-1', scope: 'account' },
      'mock-op-id',
    );

    expect(createRequestDoc).toHaveBeenCalledWith(
      'ITEM_SALE_BUSINESS_TO_PROJECT',
      {
        itemId: 'item-2',
        targetProjectId: 'proj-dest',
        budgetCategoryId: 'cat-X',
        expected: { itemProjectId: null, itemTransactionId: null },
      },
      { accountId: 'acc-1', scope: 'account' },
      'mock-op-id',
    );
  });

  it('uses params.budgetCategoryId for all items (no per-item override)', () => {
    const items = [{ id: 'item-1' }, { id: 'item-2' }];

    requestBusinessToProjectPurchase({ accountId, targetProjectId, budgetCategoryId: 'shared-cat', items });

    const calls = (createRequestDoc as jest.Mock).mock.calls;
    expect(calls[0][1].budgetCategoryId).toBe('shared-cat');
    expect(calls[1][1].budgetCategoryId).toBe('shared-cat');
  });

  it('uses provided opId', () => {
    const items = [{ id: 'item-1' }];

    requestBusinessToProjectPurchase({ accountId, targetProjectId, budgetCategoryId, items, opId: 'my-op' });

    expect(createRequestDoc).toHaveBeenCalledWith(
      expect.any(String),
      expect.any(Object),
      expect.any(Object),
      'my-op',
    );
  });

  it('returns empty array for empty items', () => {
    const result = requestBusinessToProjectPurchase({ accountId, targetProjectId, budgetCategoryId, items: [] });

    expect(result).toEqual([]);
    expect(createRequestDoc).not.toHaveBeenCalled();
  });

  it('scopes all requests to account level', () => {
    const items = [{ id: 'item-1' }];

    requestBusinessToProjectPurchase({ accountId: 'acc-99', targetProjectId, budgetCategoryId, items });

    expect(createRequestDoc).toHaveBeenCalledWith(
      expect.any(String),
      expect.any(Object),
      { accountId: 'acc-99', scope: 'account' },
      expect.any(String),
    );
  });
});

// ---------------------------------------------------------------------------
// requestProjectToProjectMove
// ---------------------------------------------------------------------------

describe('requestProjectToProjectMove', () => {
  const accountId = 'acc-1';
  const sourceProjectId = 'proj-src';
  const targetProjectId = 'proj-dest';
  const destinationBudgetCategoryId = 'dest-cat';

  it('creates one request doc per item with correct payload', () => {
    const items = [
      { id: 'item-1', projectId: 'proj-src', transactionId: 'txn-1', budgetCategoryId: 'cat-A' },
      { id: 'item-2', projectId: 'proj-src', budgetCategoryId: 'cat-B' },
    ];

    const result = requestProjectToProjectMove({
      accountId, sourceProjectId, targetProjectId, destinationBudgetCategoryId, items,
    });

    expect(result).toEqual(['mock-request-id', 'mock-request-id']);
    expect(createRequestDoc).toHaveBeenCalledTimes(2);

    expect(createRequestDoc).toHaveBeenCalledWith(
      'ITEM_SALE_PROJECT_TO_PROJECT',
      {
        itemId: 'item-1',
        sourceProjectId: 'proj-src',
        targetProjectId: 'proj-dest',
        sourceBudgetCategoryId: 'cat-A',
        destinationBudgetCategoryId: 'dest-cat',
        expected: { itemProjectId: 'proj-src', itemTransactionId: 'txn-1' },
      },
      { accountId: 'acc-1', scope: 'account' },
      'mock-op-id',
    );
  });

  it('falls back to params.sourceBudgetCategoryId when item has no category', () => {
    const items = [{ id: 'item-1', budgetCategoryId: null }];

    requestProjectToProjectMove({
      accountId, sourceProjectId, targetProjectId, destinationBudgetCategoryId,
      items, sourceBudgetCategoryId: 'fallback-src',
    });

    expect(createRequestDoc).toHaveBeenCalledWith(
      'ITEM_SALE_PROJECT_TO_PROJECT',
      expect.objectContaining({ sourceBudgetCategoryId: 'fallback-src' }),
      expect.any(Object),
      expect.any(String),
    );
  });

  it('throws when item has no category and no fallback is provided', () => {
    const items = [{ id: 'item-1', budgetCategoryId: null }];

    expect(() => requestProjectToProjectMove({
      accountId, sourceProjectId, targetProjectId, destinationBudgetCategoryId, items,
    })).toThrow('Missing sourceBudgetCategoryId');
  });

  it('item-level category takes precedence over params-level fallback', () => {
    const items = [{ id: 'item-1', budgetCategoryId: 'item-cat' }];

    requestProjectToProjectMove({
      accountId, sourceProjectId, targetProjectId, destinationBudgetCategoryId,
      items, sourceBudgetCategoryId: 'fallback-cat',
    });

    expect(createRequestDoc).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ sourceBudgetCategoryId: 'item-cat' }),
      expect.any(Object),
      expect.any(String),
    );
  });

  it('uses provided opId', () => {
    const items = [{ id: 'item-1', budgetCategoryId: 'cat-A' }];

    requestProjectToProjectMove({
      accountId, sourceProjectId, targetProjectId, destinationBudgetCategoryId,
      items, opId: 'custom-op',
    });

    expect(createRequestDoc).toHaveBeenCalledWith(
      expect.any(String),
      expect.any(Object),
      expect.any(Object),
      'custom-op',
    );
  });

  it('returns empty array for empty items', () => {
    const result = requestProjectToProjectMove({
      accountId, sourceProjectId, targetProjectId, destinationBudgetCategoryId, items: [],
    });

    expect(result).toEqual([]);
    expect(createRequestDoc).not.toHaveBeenCalled();
  });

  it('passes destinationBudgetCategoryId uniformly to all items', () => {
    const items = [
      { id: 'item-1', budgetCategoryId: 'cat-A' },
      { id: 'item-2', budgetCategoryId: 'cat-B' },
    ];

    requestProjectToProjectMove({
      accountId, sourceProjectId, targetProjectId,
      destinationBudgetCategoryId: 'uniform-dest', items,
    });

    const calls = (createRequestDoc as jest.Mock).mock.calls;
    expect(calls[0][1].destinationBudgetCategoryId).toBe('uniform-dest');
    expect(calls[1][1].destinationBudgetCategoryId).toBe('uniform-dest');
  });
});
