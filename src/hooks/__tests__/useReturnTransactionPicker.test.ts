// Mock expo-router (contains JSX that Jest can't parse in node environment)
jest.mock('expo-router', () => ({
  useRouter: jest.fn(() => ({ push: jest.fn(), replace: jest.fn() })),
}));

// Mock Firebase dependencies (transitive via returnFlowService)
jest.mock('../../firebase/firebase', () => ({
  db: null,
  auth: null,
  isFirebaseConfigured: false,
}));
jest.mock('@react-native-firebase/firestore', () => ({
  collection: jest.fn(),
  doc: jest.fn(),
  setDoc: jest.fn(),
  serverTimestamp: jest.fn(),
}));
jest.mock('../../sync/pendingWrites', () => ({
  trackPendingWrite: jest.fn(),
}));
jest.mock('../../components/toastStore', () => ({
  showToast: jest.fn(),
}));

import {
  computeSubtitle,
  resolveSourceTransactionId,
  buildCreateNewParams,
} from '../useReturnTransactionPicker';
import { createProjectScopeConfig, createInventoryScopeConfig } from '../../data/scopeConfig';

// ---------------------------------------------------------------------------
// computeSubtitle
// ---------------------------------------------------------------------------

describe('computeSubtitle', () => {
  it('returns undefined for 0 items', () => {
    expect(computeSubtitle(0)).toBeUndefined();
  });

  it('returns singular for 1 item', () => {
    expect(computeSubtitle(1)).toBe('Moving 1 item');
  });

  it('returns plural for multiple items', () => {
    expect(computeSubtitle(3)).toBe('Moving 3 items');
  });

  it('returns plural for 2 items', () => {
    expect(computeSubtitle(2)).toBe('Moving 2 items');
  });
});

// ---------------------------------------------------------------------------
// resolveSourceTransactionId
// ---------------------------------------------------------------------------

describe('resolveSourceTransactionId', () => {
  it('uses fixed fromTransactionId when provided (transaction context)', () => {
    const result = resolveSourceTransactionId('item-1', 'txn-1');
    expect(result).toBe('txn-1');
  });

  it('uses fixed fromTransactionId even when null (transaction context, item not on any tx)', () => {
    const result = resolveSourceTransactionId('item-1', null);
    expect(result).toBeNull();
  });

  it('calls getItemTransactionId when fromTransactionId is undefined (non-transaction context)', () => {
    const lookup = jest.fn().mockReturnValue('txn-from-lookup');
    const result = resolveSourceTransactionId('item-1', undefined, lookup);
    expect(result).toBe('txn-from-lookup');
    expect(lookup).toHaveBeenCalledWith('item-1');
  });

  it('returns null when fromTransactionId is undefined and no lookup provided', () => {
    const result = resolveSourceTransactionId('item-1', undefined);
    expect(result).toBeNull();
  });

  it('returns null when fromTransactionId is undefined and lookup returns null', () => {
    const lookup = jest.fn().mockReturnValue(null);
    const result = resolveSourceTransactionId('item-1', undefined, lookup);
    expect(result).toBeNull();
  });

  it('prefers fixed fromTransactionId over lookup function', () => {
    const lookup = jest.fn().mockReturnValue('txn-from-lookup');
    const result = resolveSourceTransactionId('item-1', 'txn-fixed', lookup);
    expect(result).toBe('txn-fixed');
    expect(lookup).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// buildCreateNewParams
// ---------------------------------------------------------------------------

describe('buildCreateNewParams', () => {
  it('builds params for project scope with single item', () => {
    const scopeConfig = createProjectScopeConfig('proj-1');
    const result = buildCreateNewParams(scopeConfig, ['item-1'], 'txn-1');

    expect(result.pathname).toBe('/transactions/new');
    expect(result.params.scope).toBe('project');
    expect(result.params.projectId).toBe('proj-1');
    expect(result.params.transactionType).toBe('return');
    expect(result.params.linkItemIds).toBe('item-1');
    expect(result.params.linkItemFromTransactionId).toBe('txn-1');
  });

  it('builds params for inventory scope', () => {
    const scopeConfig = createInventoryScopeConfig();
    const result = buildCreateNewParams(scopeConfig, ['item-1'], null);

    expect(result.params.scope).toBe('inventory');
    expect(result.params.projectId).toBe('');
    expect(result.params.linkItemFromTransactionId).toBe('');
  });

  it('joins multiple item IDs with commas', () => {
    const scopeConfig = createProjectScopeConfig('proj-1');
    const result = buildCreateNewParams(
      scopeConfig,
      ['item-1', 'item-2', 'item-3'],
      'txn-1',
    );

    expect(result.params.linkItemIds).toBe('item-1,item-2,item-3');
  });

  it('handles empty item IDs array', () => {
    const scopeConfig = createProjectScopeConfig('proj-1');
    const result = buildCreateNewParams(scopeConfig, [], 'txn-1');

    expect(result.params.linkItemIds).toBe('');
  });

  it('handles undefined fromTransactionId', () => {
    const scopeConfig = createProjectScopeConfig('proj-1');
    const result = buildCreateNewParams(scopeConfig, ['item-1']);

    expect(result.params.linkItemFromTransactionId).toBe('');
  });

  it('always sets transactionType to return', () => {
    const scopeConfig = createProjectScopeConfig('proj-1');
    const result = buildCreateNewParams(scopeConfig, ['item-1']);

    expect(result.params.transactionType).toBe('return');
  });
});
