import {
  isIncompleteReturn,
  findIncompleteReturns,
} from '../incompleteReturnDetection';
import type { ItemLineageMovementKind } from '../../data/lineageEdgesService';

function makeItem(
  overrides: Partial<{ id: string; status: string | null; transactionId: string | null }> = {},
) {
  return { id: 'item-1', status: 'returned' as string | null | undefined, transactionId: 'txn-1' as string | null | undefined, ...overrides };
}

function makeTransaction(
  overrides: Partial<{ transactionType: string | null }> = {},
) {
  return { transactionType: 'purchase' as string | null | undefined, ...overrides };
}

function makeEdge(
  overrides: Partial<{ itemId: string; movementKind: ItemLineageMovementKind }> = {},
) {
  return { itemId: 'item-1', movementKind: 'association' as ItemLineageMovementKind, ...overrides };
}

describe('isIncompleteReturn', () => {
  it('returns true when status is returned, purchase tx, and no returned edges', () => {
    const result = isIncompleteReturn(
      makeItem({ status: 'returned' }),
      makeTransaction({ transactionType: 'purchase' }),
      [],
    );
    expect(result).toBe(true);
  });

  it('returns false when status is not returned', () => {
    const result = isIncompleteReturn(
      makeItem({ status: 'purchased' }),
      makeTransaction({ transactionType: 'purchase' }),
      [],
    );
    expect(result).toBe(false);
  });

  it('returns false when item is in a return transaction', () => {
    const result = isIncompleteReturn(
      makeItem({ status: 'returned' }),
      makeTransaction({ transactionType: 'return' }),
      [],
    );
    expect(result).toBe(false);
  });

  it('returns false when a returned edge exists for this item', () => {
    const result = isIncompleteReturn(
      makeItem({ id: 'item-1', status: 'returned' }),
      makeTransaction({ transactionType: 'purchase' }),
      [makeEdge({ itemId: 'item-1', movementKind: 'returned' })],
    );
    expect(result).toBe(false);
  });

  it('returns true when only association edges exist (no returned edge)', () => {
    const result = isIncompleteReturn(
      makeItem({ id: 'item-1', status: 'returned' }),
      makeTransaction({ transactionType: 'purchase' }),
      [makeEdge({ itemId: 'item-1', movementKind: 'association' })],
    );
    expect(result).toBe(true);
  });

  it('returns false when transaction is null', () => {
    const result = isIncompleteReturn(
      makeItem({ status: 'returned' }),
      null,
      [],
    );
    expect(result).toBe(false);
  });

  it('returns false when status is undefined or null', () => {
    expect(
      isIncompleteReturn(
        makeItem({ status: undefined }),
        makeTransaction(),
        [],
      ),
    ).toBe(false);

    expect(
      isIncompleteReturn(
        makeItem({ status: null }),
        makeTransaction(),
        [],
      ),
    ).toBe(false);
  });

  it('returns false when transactionType is return with leading/trailing spaces', () => {
    const result = isIncompleteReturn(
      makeItem({ status: 'returned' }),
      makeTransaction({ transactionType: ' return ' }),
      [],
    );
    expect(result).toBe(false);
  });
});

describe('findIncompleteReturns', () => {
  it('returns empty array when items list is empty', () => {
    const result = findIncompleteReturns(
      [],
      makeTransaction(),
      [],
    );
    expect(result).toEqual([]);
  });

  it('returns only IDs of items with incomplete returns', () => {
    const items = [
      makeItem({ id: 'item-1', status: 'returned' }),
      makeItem({ id: 'item-2', status: 'purchased' }),
      makeItem({ id: 'item-3', status: 'returned' }),
    ];
    const edges = [
      makeEdge({ itemId: 'item-3', movementKind: 'returned' }),
    ];
    const result = findIncompleteReturns(items, makeTransaction(), edges);
    expect(result).toEqual(['item-1']);
  });

  it('returns empty array when all items have complete returns', () => {
    const items = [
      makeItem({ id: 'item-1', status: 'returned' }),
      makeItem({ id: 'item-2', status: 'returned' }),
    ];
    const edges = [
      makeEdge({ itemId: 'item-1', movementKind: 'returned' }),
      makeEdge({ itemId: 'item-2', movementKind: 'returned' }),
    ];
    const result = findIncompleteReturns(items, makeTransaction(), edges);
    expect(result).toEqual([]);
  });

  it('returns all IDs when multiple items have incomplete returns', () => {
    const items = [
      makeItem({ id: 'item-1', status: 'returned' }),
      makeItem({ id: 'item-2', status: 'returned' }),
      makeItem({ id: 'item-3', status: 'returned' }),
    ];
    const result = findIncompleteReturns(items, makeTransaction(), []);
    expect(result).toEqual(['item-1', 'item-2', 'item-3']);
  });

  it('returns single ID when one item has incomplete return', () => {
    const items = [
      makeItem({ id: 'item-5', status: 'returned' }),
    ];
    const result = findIncompleteReturns(items, makeTransaction(), []);
    expect(result).toEqual(['item-5']);
  });
});
