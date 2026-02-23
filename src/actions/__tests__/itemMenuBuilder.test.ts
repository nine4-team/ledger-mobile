import {
  buildSingleItemMenu,
  buildBulkMenu,
  type SingleItemCallbacks,
  type BulkCallbacks,
} from '../itemMenuBuilder';
import { createProjectScopeConfig, createInventoryScopeConfig } from '../../data/scopeConfig';
import { ITEM_STATUSES } from '../../constants/itemStatuses';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function mockSingleCallbacks(): SingleItemCallbacks {
  return {
    onEditOrOpen: jest.fn(),
    onStatusChange: jest.fn(),
    onSetTransaction: jest.fn(),
    onClearTransaction: jest.fn(),
    onSetSpace: jest.fn(),
    onClearSpace: jest.fn(),
    onSellToBusiness: jest.fn(),
    onSellToProject: jest.fn(),
    onReassignToInventory: jest.fn(),
    onReassignToProject: jest.fn(),
    onMoveToReturnTransaction: jest.fn(),
    onDelete: jest.fn(),
  };
}

function mockBulkCallbacks(): BulkCallbacks {
  return {
    onStatusChange: jest.fn(),
    onSetTransaction: jest.fn(),
    onClearTransaction: jest.fn(),
    onSetSpace: jest.fn(),
    onClearSpace: jest.fn(),
    onSellToBusiness: jest.fn(),
    onSellToProject: jest.fn(),
    onReassignToInventory: jest.fn(),
    onReassignToProject: jest.fn(),
    onDelete: jest.fn(),
  };
}

// ---------------------------------------------------------------------------
// buildSingleItemMenu
// ---------------------------------------------------------------------------

describe('buildSingleItemMenu', () => {
  it('project scope, list context — returns 7 items in correct order', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'list',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const keys = items.map((i) => i.key);
    expect(keys).toEqual(['edit', 'status', 'transaction', 'space', 'sell', 'reassign', 'delete']);

    expect(items[0].label).toBe('Edit Details');
    expect(items[0].icon).toBe('edit');

    expect(items[items.length - 1].label).toBe('Delete');
    expect(items[items.length - 1].icon).toBe('delete');
  });

  it('project scope — Sell submenu has both options', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'list',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const sell = items.find((i) => i.key === 'sell');
    const sellKeys = sell!.subactions!.map((s) => s.key);
    expect(sellKeys).toEqual(['sell-to-business', 'sell-to-project']);
  });

  it('project scope — Reassign submenu has both options', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'list',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const reassign = items.find((i) => i.key === 'reassign');
    const reassignKeys = reassign!.subactions!.map((s) => s.key);
    expect(reassignKeys).toEqual(['reassign-to-inventory', 'reassign-to-project']);
  });

  it('inventory scope, list context — Sell and Reassign have only project options', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'list',
      scopeConfig: createInventoryScopeConfig(),
      callbacks,
    });

    const sell = items.find((i) => i.key === 'sell');
    expect(sell!.subactions!.map((s) => s.key)).toEqual(['sell-to-project']);

    const reassign = items.find((i) => i.key === 'reassign');
    expect(reassign!.subactions!.map((s) => s.key)).toEqual(['reassign-to-project']);
  });

  it('space context — first item is "Open" with icon "open-in-new"', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'space',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    expect(items[0].key).toBe('open');
    expect(items[0].label).toBe('Open');
    expect(items[0].icon).toBe('open-in-new');
  });

  it('space context — Space subaction labels are "Move to Space" and "Remove from Space"', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'space',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const space = items.find((i) => i.key === 'space');
    const labels = space!.subactions!.map((s) => s.label);
    expect(labels).toEqual(['Move to Space', 'Remove from Space']);
  });

  it('detail context — Status includes Clear Status', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'detail',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const status = items.find((i) => i.key === 'status');
    expect(status!.subactions!).toHaveLength(ITEM_STATUSES.length + 1);

    const last = status!.subactions![status!.subactions!.length - 1];
    expect(last.key).toBe('clear-status');
  });

  it('list context — Status does NOT include Clear Status', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'list',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const status = items.find((i) => i.key === 'status');
    expect(status!.subactions!).toHaveLength(ITEM_STATUSES.length);
  });

  it('Sell and Reassign have info tooltips', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'list',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const sell = items.find((i) => i.key === 'sell');
    expect(sell!.info).toBeDefined();
    expect(sell!.info).toHaveProperty('title');
    expect(sell!.info).toHaveProperty('message');

    const reassign = items.find((i) => i.key === 'reassign');
    expect(reassign!.info).toBeDefined();
    expect(reassign!.info).toHaveProperty('title');
    expect(reassign!.info).toHaveProperty('message');
  });

  it('callback wiring — onPress invokes the correct callback', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'detail',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    // Edit calls onEditOrOpen
    const edit = items.find((i) => i.key === 'edit');
    edit!.onPress!();
    expect(callbacks.onEditOrOpen).toHaveBeenCalledTimes(1);

    // Status subaction calls onStatusChange with key
    const status = items.find((i) => i.key === 'status');
    const firstStatus = status!.subactions![0];
    firstStatus.onPress();
    expect(callbacks.onStatusChange).toHaveBeenCalledWith(ITEM_STATUSES[0].key);

    // Sell to business calls onSellToBusiness
    const sell = items.find((i) => i.key === 'sell');
    const sellToBusiness = sell!.subactions!.find((s) => s.key === 'sell-to-business');
    sellToBusiness!.onPress();
    expect(callbacks.onSellToBusiness).toHaveBeenCalledTimes(1);

    // Delete calls onDelete
    const del = items.find((i) => i.key === 'delete');
    del!.onPress!();
    expect(callbacks.onDelete).toHaveBeenCalledTimes(1);
  });

  it('transaction context with onMoveToReturnTransaction — shows return subaction', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'transaction',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const txn = items.find((i) => i.key === 'transaction');
    const returnAction = txn!.subactions!.find((s) => s.key === 'move-to-return-transaction');
    expect(returnAction).toBeDefined();
    expect(returnAction!.label).toBe('Move to Return Transaction');
  });

  it('transaction context without onMoveToReturnTransaction — no return subaction', () => {
    const callbacks = mockSingleCallbacks();
    delete callbacks.onMoveToReturnTransaction;
    const items = buildSingleItemMenu({
      context: 'transaction',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const txn = items.find((i) => i.key === 'transaction');
    const returnAction = txn!.subactions!.find((s) => s.key === 'move-to-return-transaction');
    expect(returnAction).toBeUndefined();
  });

  it('non-transaction context — no return subaction regardless of callback', () => {
    const callbacks = mockSingleCallbacks();
    const items = buildSingleItemMenu({
      context: 'list',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const txn = items.find((i) => i.key === 'transaction');
    const returnAction = txn!.subactions!.find((s) => s.key === 'move-to-return-transaction');
    expect(returnAction).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// buildBulkMenu
// ---------------------------------------------------------------------------

describe('buildBulkMenu', () => {
  it('project scope, list context — returns 6 items (no Edit/Open)', () => {
    const callbacks = mockBulkCallbacks();
    const items = buildBulkMenu({
      context: 'list',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const keys = items.map((i) => i.key);
    expect(keys).toEqual(['status', 'transaction', 'space', 'sell', 'reassign', 'delete']);
  });

  it('project scope, space context — Space labels are "Move to Another Space" and "Remove from Space"', () => {
    const callbacks = mockBulkCallbacks();
    const items = buildBulkMenu({
      context: 'space',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const space = items.find((i) => i.key === 'space');
    const labels = space!.subactions!.map((s) => s.label);
    expect(labels).toEqual(['Move to Another Space', 'Remove from Space']);
  });

  it('list context — Space labels are "Set Space" and "Clear Space"', () => {
    const callbacks = mockBulkCallbacks();
    const items = buildBulkMenu({
      context: 'list',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const space = items.find((i) => i.key === 'space');
    const labels = space!.subactions!.map((s) => s.label);
    expect(labels).toEqual(['Set Space', 'Clear Space']);
  });

  it('inventory scope — Sell has only "Sell to Project"; Reassign has only "Reassign to Project"', () => {
    const callbacks = mockBulkCallbacks();
    const items = buildBulkMenu({
      context: 'list',
      scopeConfig: createInventoryScopeConfig(),
      callbacks,
    });

    const sell = items.find((i) => i.key === 'sell');
    expect(sell!.subactions!).toHaveLength(1);
    expect(sell!.subactions![0].label).toBe('Sell to Project');

    const reassign = items.find((i) => i.key === 'reassign');
    expect(reassign!.subactions!).toHaveLength(1);
    expect(reassign!.subactions![0].label).toBe('Reassign to Project');
  });

  it('callback wiring — status subaction calls onStatusChange with key', () => {
    const callbacks = mockBulkCallbacks();
    const items = buildBulkMenu({
      context: 'list',
      scopeConfig: createProjectScopeConfig('proj-1'),
      callbacks,
    });

    const status = items.find((i) => i.key === 'status');
    const secondStatus = status!.subactions![1];
    secondStatus.onPress();
    expect(callbacks.onStatusChange).toHaveBeenCalledWith(ITEM_STATUSES[1].key);
  });
});
