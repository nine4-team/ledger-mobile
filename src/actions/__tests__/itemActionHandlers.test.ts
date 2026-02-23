// Mock Firebase dependencies so importing service modules doesn't fail
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

jest.mock('../../data/inventoryOperations');
jest.mock('../../data/reassignService');

import {
  executeSellToBusiness,
  executeSellToProject,
  executeBulkReassignToInventory,
  executeBulkReassignToProject,
} from '../itemActionHandlers';

import {
  requestProjectToBusinessSale,
  requestBusinessToProjectPurchase,
  requestProjectToProjectMove,
} from '../../data/inventoryOperations';

import {
  reassignItemToInventory,
  reassignItemToProject,
  filterItemsForBulkReassign,
} from '../../data/reassignService';

beforeEach(() => {
  jest.clearAllMocks();

  // Replicate real filterItemsForBulkReassign behavior since the module is mocked
  (filterItemsForBulkReassign as jest.Mock).mockImplementation((items: any[]) => {
    const eligible: string[] = [];
    let blockedCount = 0;
    for (const item of items) {
      if (item.transactionId) {
        blockedCount++;
      } else {
        eligible.push(item.id);
      }
    }
    return { eligible, blockedCount };
  });
});

// ---------------------------------------------------------------------------
// executeSellToBusiness
// ---------------------------------------------------------------------------

describe('executeSellToBusiness', () => {
  const accountId = 'acc-1';
  const projectId = 'proj-1';

  it('calls requestProjectToBusinessSale with existing budgetCategoryIds and returns item count', () => {
    const items = [
      { id: 'item-1', budgetCategoryId: 'cat-A' },
      { id: 'item-2', budgetCategoryId: 'cat-B' },
    ];

    const result = executeSellToBusiness({
      accountId,
      projectId,
      items,
      sourceCategoryId: null,
    });

    expect(result).toBe(2);
    expect(requestProjectToBusinessSale).toHaveBeenCalledTimes(1);
    expect(requestProjectToBusinessSale).toHaveBeenCalledWith({
      accountId,
      projectId,
      items: [
        expect.objectContaining({ id: 'item-1', budgetCategoryId: 'cat-A' }),
        expect.objectContaining({ id: 'item-2', budgetCategoryId: 'cat-B' }),
      ],
    });
  });

  it('assigns fallback sourceCategoryId to items without budgetCategoryId', () => {
    const items = [
      { id: 'item-1', budgetCategoryId: null },
      { id: 'item-2' },
    ];

    const result = executeSellToBusiness({
      accountId,
      projectId,
      items,
      sourceCategoryId: 'fallback-cat',
    });

    expect(result).toBe(2);
    expect(requestProjectToBusinessSale).toHaveBeenCalledTimes(1);
    expect(requestProjectToBusinessSale).toHaveBeenCalledWith({
      accountId,
      projectId,
      items: [
        expect.objectContaining({ id: 'item-1', budgetCategoryId: 'fallback-cat' }),
        expect.objectContaining({ id: 'item-2', budgetCategoryId: 'fallback-cat' }),
      ],
    });
  });

  it('returns 0 and makes no service call when items lack categories and no fallback is provided', () => {
    const items = [
      { id: 'item-1', budgetCategoryId: null },
      { id: 'item-2' },
    ];

    const result = executeSellToBusiness({
      accountId,
      projectId,
      items,
      sourceCategoryId: null,
    });

    expect(result).toBe(0);
    expect(requestProjectToBusinessSale).not.toHaveBeenCalled();
  });

  it('resolves mixed items: keeps existing categories and assigns fallback to missing ones', () => {
    const items = [
      { id: 'item-1', budgetCategoryId: 'cat-A' },
      { id: 'item-2', budgetCategoryId: null },
      { id: 'item-3' },
    ];

    const result = executeSellToBusiness({
      accountId,
      projectId,
      items,
      sourceCategoryId: 'fallback-cat',
    });

    expect(result).toBe(3);
    expect(requestProjectToBusinessSale).toHaveBeenCalledTimes(1);
    const callArgs = (requestProjectToBusinessSale as jest.Mock).mock.calls[0][0];
    const passedItems = callArgs.items;

    // item-1 keeps its existing category
    expect(passedItems.find((i: any) => i.id === 'item-1').budgetCategoryId).toBe('cat-A');
    // item-2 and item-3 get the fallback
    expect(passedItems.find((i: any) => i.id === 'item-2').budgetCategoryId).toBe('fallback-cat');
    expect(passedItems.find((i: any) => i.id === 'item-3').budgetCategoryId).toBe('fallback-cat');
  });
});

// ---------------------------------------------------------------------------
// executeSellToProject
// ---------------------------------------------------------------------------

describe('executeSellToProject', () => {
  const accountId = 'acc-1';
  const targetProjectId = 'proj-dest';

  describe('project scope (Project -> Project)', () => {
    it('calls requestProjectToProjectMove with resolved source and dest categories', () => {
      const sourceProjectId = 'proj-src';
      const items = [
        { id: 'item-1', budgetCategoryId: 'cat-A' },
        { id: 'item-2', budgetCategoryId: 'cat-B' },
      ];
      const validDestCategoryIds = new Set(['cat-A', 'cat-B']);

      const result = executeSellToProject({
        accountId,
        scope: 'project',
        sourceProjectId,
        targetProjectId,
        items,
        sourceCategoryId: null,
        destCategoryId: null,
        validDestCategoryIds,
      });

      expect(result).toBe(2);
      expect(requestProjectToProjectMove).toHaveBeenCalledTimes(1);
      expect(requestProjectToProjectMove).toHaveBeenCalledWith(
        expect.objectContaining({
          accountId,
          sourceProjectId,
          targetProjectId,
          destinationBudgetCategoryId: 'cat-A', // first resolved dest category
        }),
      );
    });
  });

  describe('inventory scope (Business -> Project)', () => {
    it('calls requestBusinessToProjectPurchase with resolved dest categories', () => {
      const items = [
        { id: 'item-1', budgetCategoryId: 'cat-X' },
        { id: 'item-2', budgetCategoryId: 'cat-Y' },
      ];
      const validDestCategoryIds = new Set(['cat-X', 'cat-Y']);

      const result = executeSellToProject({
        accountId,
        scope: 'inventory',
        targetProjectId,
        items,
        sourceCategoryId: null,
        destCategoryId: null,
        validDestCategoryIds,
      });

      expect(result).toBe(2);
      expect(requestBusinessToProjectPurchase).toHaveBeenCalledTimes(1);
      expect(requestBusinessToProjectPurchase).toHaveBeenCalledWith(
        expect.objectContaining({
          accountId,
          targetProjectId,
          budgetCategoryId: 'cat-X', // first resolved dest category
          items,
        }),
      );
    });
  });

  describe('empty destination resolution', () => {
    it('returns 0 and makes no service calls when no valid dest categories resolve', () => {
      const items = [
        { id: 'item-1', budgetCategoryId: 'cat-INVALID' },
      ];
      // validDestCategoryIds does not include cat-INVALID, and no fallback
      const validDestCategoryIds = new Set(['cat-X']);

      const result = executeSellToProject({
        accountId,
        scope: 'inventory',
        targetProjectId,
        items,
        sourceCategoryId: null,
        destCategoryId: null,
        validDestCategoryIds,
      });

      expect(result).toBe(0);
      expect(requestBusinessToProjectPurchase).not.toHaveBeenCalled();
      expect(requestProjectToProjectMove).not.toHaveBeenCalled();
    });

    it('returns 0 for project scope when no valid dest categories resolve', () => {
      const items = [
        { id: 'item-1', budgetCategoryId: 'cat-INVALID' },
      ];
      const validDestCategoryIds = new Set(['cat-X']);

      const result = executeSellToProject({
        accountId,
        scope: 'project',
        sourceProjectId: 'proj-src',
        targetProjectId,
        items,
        sourceCategoryId: null,
        destCategoryId: null,
        validDestCategoryIds,
      });

      expect(result).toBe(0);
      expect(requestProjectToProjectMove).not.toHaveBeenCalled();
    });
  });
});

// ---------------------------------------------------------------------------
// executeBulkReassignToInventory
// ---------------------------------------------------------------------------

describe('executeBulkReassignToInventory', () => {
  const accountId = 'acc-1';

  it('calls reassignItemToInventory for all eligible items (no transactionId)', () => {
    const items = [
      { id: 'item-1' },
      { id: 'item-2' },
      { id: 'item-3' },
    ];

    const result = executeBulkReassignToInventory({ accountId, items });

    expect(result).toEqual({ executed: 3, blocked: 0 });
    expect(reassignItemToInventory).toHaveBeenCalledTimes(3);
    expect(reassignItemToInventory).toHaveBeenCalledWith(accountId, 'item-1');
    expect(reassignItemToInventory).toHaveBeenCalledWith(accountId, 'item-2');
    expect(reassignItemToInventory).toHaveBeenCalledWith(accountId, 'item-3');
  });

  it('only calls for eligible items when some are blocked by transactionId', () => {
    const items = [
      { id: 'item-1' },
      { id: 'item-2', transactionId: 'txn-1' },
      { id: 'item-3' },
      { id: 'item-4', transactionId: 'txn-2' },
    ];

    const result = executeBulkReassignToInventory({ accountId, items });

    expect(result).toEqual({ executed: 2, blocked: 2 });
    expect(reassignItemToInventory).toHaveBeenCalledTimes(2);
    expect(reassignItemToInventory).toHaveBeenCalledWith(accountId, 'item-1');
    expect(reassignItemToInventory).toHaveBeenCalledWith(accountId, 'item-3');
  });

  it('returns all blocked when every item has a transactionId', () => {
    const items = [
      { id: 'item-1', transactionId: 'txn-1' },
      { id: 'item-2', transactionId: 'txn-2' },
    ];

    const result = executeBulkReassignToInventory({ accountId, items });

    expect(result).toEqual({ executed: 0, blocked: 2 });
    expect(reassignItemToInventory).not.toHaveBeenCalled();
  });

  it('returns zeros for an empty items array', () => {
    const result = executeBulkReassignToInventory({ accountId, items: [] });

    expect(result).toEqual({ executed: 0, blocked: 0 });
    expect(reassignItemToInventory).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// executeBulkReassignToProject
// ---------------------------------------------------------------------------

describe('executeBulkReassignToProject', () => {
  const accountId = 'acc-1';
  const targetProjectId = 'proj-target';

  it('calls reassignItemToProject for all eligible items with targetProjectId', () => {
    const items = [
      { id: 'item-1' },
      { id: 'item-2' },
    ];

    const result = executeBulkReassignToProject({ accountId, items, targetProjectId });

    expect(result).toEqual({ executed: 2, blocked: 0 });
    expect(reassignItemToProject).toHaveBeenCalledTimes(2);
    expect(reassignItemToProject).toHaveBeenCalledWith(accountId, 'item-1', targetProjectId);
    expect(reassignItemToProject).toHaveBeenCalledWith(accountId, 'item-2', targetProjectId);
  });

  it('only calls for eligible items when some are blocked by transactionId', () => {
    const items = [
      { id: 'item-1' },
      { id: 'item-2', transactionId: 'txn-1' },
      { id: 'item-3' },
    ];

    const result = executeBulkReassignToProject({ accountId, items, targetProjectId });

    expect(result).toEqual({ executed: 2, blocked: 1 });
    expect(reassignItemToProject).toHaveBeenCalledTimes(2);
    expect(reassignItemToProject).toHaveBeenCalledWith(accountId, 'item-1', targetProjectId);
    expect(reassignItemToProject).toHaveBeenCalledWith(accountId, 'item-3', targetProjectId);
  });

  it('returns all blocked when every item has a transactionId', () => {
    const items = [
      { id: 'item-1', transactionId: 'txn-1' },
      { id: 'item-2', transactionId: 'txn-2' },
      { id: 'item-3', transactionId: 'txn-3' },
    ];

    const result = executeBulkReassignToProject({ accountId, items, targetProjectId });

    expect(result).toEqual({ executed: 0, blocked: 3 });
    expect(reassignItemToProject).not.toHaveBeenCalled();
  });

  it('returns zeros for an empty items array', () => {
    const result = executeBulkReassignToProject({ accountId, items: [], targetProjectId });

    expect(result).toEqual({ executed: 0, blocked: 0 });
    expect(reassignItemToProject).not.toHaveBeenCalled();
  });
});
