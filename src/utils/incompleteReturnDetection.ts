import type { Item } from '../data/itemsService';
import type { Transaction } from '../data/transactionsService';
import type { ItemLineageEdge } from '../data/lineageEdgesService';

/**
 * An item has an incomplete return when ALL of the following are true:
 * 1. item.status === 'returned'
 * 2. The transaction is not a return transaction
 * 3. No lineage edge with movementKind 'returned' exists for this item from this transaction
 */
export function isIncompleteReturn(
  item: Pick<Item, 'id' | 'status' | 'transactionId'>,
  transaction: Pick<Transaction, 'transactionType'> | null,
  edgesFromTransaction: Pick<ItemLineageEdge, 'itemId' | 'movementKind'>[],
): boolean {
  if (item.status !== 'returned') return false;
  if (!transaction) return false;

  const txType = transaction.transactionType?.trim().toLowerCase();
  if (txType === 'return') return false;

  const hasReturnedEdge = edgesFromTransaction.some(
    (edge) => edge.itemId === item.id && edge.movementKind === 'returned',
  );
  if (hasReturnedEdge) return false;

  return true;
}

/**
 * Filter active items to find those with incomplete returns.
 * Returns array of item IDs.
 */
export function findIncompleteReturns(
  activeItems: Pick<Item, 'id' | 'status' | 'transactionId'>[],
  transaction: Pick<Transaction, 'transactionType'> | null,
  edgesFromTransaction: Pick<ItemLineageEdge, 'itemId' | 'movementKind'>[],
): string[] {
  return activeItems
    .filter((item) => isIncompleteReturn(item, transaction, edgesFromTransaction))
    .map((item) => item.id);
}
