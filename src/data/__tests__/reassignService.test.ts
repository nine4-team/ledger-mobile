// Mock Firebase dependencies so importing reassignService doesn't fail
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

import {
  validateItemReassign,
  validateTransactionReassign,
  filterItemsForBulkReassign,
} from '../reassignService';

// ---------------------------------------------------------------------------
// validateItemReassign
// ---------------------------------------------------------------------------

describe('validateItemReassign', () => {
  // Happy paths
  it('allows reassign to inventory when item is in a project with no transaction', () => {
    const result = validateItemReassign(
      { projectId: 'project-1', transactionId: null },
      null
    );
    expect(result).toEqual({ valid: true });
  });

  it('allows reassign to a different project', () => {
    const result = validateItemReassign(
      { projectId: 'project-1', transactionId: null },
      'project-2'
    );
    expect(result).toEqual({ valid: true });
  });

  // Blocked states
  it('rejects when item has a transactionId', () => {
    const result = validateItemReassign(
      { projectId: 'project-1', transactionId: 'txn-1' },
      null
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toMatch(/linked to a transaction/);
    }
  });

  it('rejects when item is already in inventory (no projectId)', () => {
    const result = validateItemReassign(
      { projectId: null, transactionId: null },
      null
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toMatch(/already in inventory/);
    }
  });

  it('rejects when item is already in inventory (undefined projectId)', () => {
    const result = validateItemReassign(
      { projectId: undefined, transactionId: null },
      null
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toMatch(/already in inventory/);
    }
  });

  it('rejects when target project matches current project', () => {
    const result = validateItemReassign(
      { projectId: 'project-1', transactionId: null },
      'project-1'
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toMatch(/already in this project/);
    }
  });

  // Edge cases
  it('allows reassign to inventory even if target is null and item is in a project', () => {
    const result = validateItemReassign(
      { projectId: 'project-1', transactionId: undefined },
      null
    );
    expect(result).toEqual({ valid: true });
  });

  it('rejects item with transactionId even when targeting a different project', () => {
    const result = validateItemReassign(
      { projectId: 'project-1', transactionId: 'txn-1' },
      'project-2'
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toMatch(/linked to a transaction/);
    }
  });
});

// ---------------------------------------------------------------------------
// validateTransactionReassign
// ---------------------------------------------------------------------------

describe('validateTransactionReassign', () => {
  // Happy paths
  it('allows reassign for non-canonical transaction to a different project', () => {
    const result = validateTransactionReassign(
      { projectId: 'project-1', isCanonicalInventory: false },
      'project-2'
    );
    expect(result).toEqual({ valid: true });
  });

  it('allows reassign to inventory when transaction is in a project', () => {
    const result = validateTransactionReassign(
      { projectId: 'project-1', isCanonicalInventory: false },
      null
    );
    expect(result).toEqual({ valid: true });
  });

  it('allows reassign when isCanonicalInventory is null', () => {
    const result = validateTransactionReassign(
      { projectId: 'project-1', isCanonicalInventory: null },
      'project-2'
    );
    expect(result).toEqual({ valid: true });
  });

  it('allows reassign when isCanonicalInventory is undefined', () => {
    const result = validateTransactionReassign(
      { projectId: 'project-1', isCanonicalInventory: undefined },
      'project-2'
    );
    expect(result).toEqual({ valid: true });
  });

  // Blocked states
  it('rejects when transaction is canonical inventory', () => {
    const result = validateTransactionReassign(
      { projectId: 'project-1', isCanonicalInventory: true },
      'project-2'
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toMatch(/cannot be reassigned/);
    }
  });

  it('rejects when transaction is already in target project', () => {
    const result = validateTransactionReassign(
      { projectId: 'project-1', isCanonicalInventory: false },
      'project-1'
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toMatch(/already in this project/);
    }
  });

  it('rejects reassign-to-inventory when already in inventory', () => {
    const result = validateTransactionReassign(
      { projectId: null, isCanonicalInventory: false },
      null
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toMatch(/already in inventory/);
    }
  });

  it('rejects canonical even when targeting inventory', () => {
    const result = validateTransactionReassign(
      { projectId: 'project-1', isCanonicalInventory: true },
      null
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toMatch(/cannot be reassigned/);
    }
  });
});

// ---------------------------------------------------------------------------
// filterItemsForBulkReassign
// ---------------------------------------------------------------------------

describe('filterItemsForBulkReassign', () => {
  it('returns all items as eligible when none have transactionId', () => {
    const items = [
      { id: '1', transactionId: null },
      { id: '2', transactionId: undefined },
      { id: '3', transactionId: null },
    ];
    const result = filterItemsForBulkReassign(items);
    expect(result).toEqual({ eligible: ['1', '2', '3'], blockedCount: 0 });
  });

  it('excludes items with transactionId', () => {
    const items = [
      { id: '1', transactionId: 'txn-1' },
      { id: '2', transactionId: null },
      { id: '3', transactionId: 'txn-2' },
    ];
    const result = filterItemsForBulkReassign(items);
    expect(result).toEqual({ eligible: ['2'], blockedCount: 2 });
  });

  it('returns all blocked when all have transactionId', () => {
    const items = [
      { id: '1', transactionId: 'txn-1' },
      { id: '2', transactionId: 'txn-2' },
    ];
    const result = filterItemsForBulkReassign(items);
    expect(result).toEqual({ eligible: [], blockedCount: 2 });
  });

  it('handles empty array', () => {
    const result = filterItemsForBulkReassign([]);
    expect(result).toEqual({ eligible: [], blockedCount: 0 });
  });

  it('handles single eligible item', () => {
    const result = filterItemsForBulkReassign([{ id: '1', transactionId: null }]);
    expect(result).toEqual({ eligible: ['1'], blockedCount: 0 });
  });

  it('handles single blocked item', () => {
    const result = filterItemsForBulkReassign([{ id: '1', transactionId: 'txn-1' }]);
    expect(result).toEqual({ eligible: [], blockedCount: 1 });
  });
});
