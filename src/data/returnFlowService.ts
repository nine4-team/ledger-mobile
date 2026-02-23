import { updateItem } from './itemsService';
import { createLineageEdge } from './lineageEdgesService';
import type { ItemLineageEdge } from './lineageEdgesService';

/**
 * Build the data for a 'returned' lineage edge.
 * Pure function — no side effects, fully testable.
 */
export function buildReturnEdgeData(params: {
  accountId: string;
  itemId: string;
  fromTransactionId: string | null;
  returnTransactionId: string;
  fromProjectId?: string | null;
  toProjectId?: string | null;
}): Omit<ItemLineageEdge, 'id' | 'createdAt'> {
  return {
    accountId: params.accountId,
    itemId: params.itemId,
    fromTransactionId: params.fromTransactionId,
    toTransactionId: params.returnTransactionId,
    movementKind: 'returned',
    source: 'app',
    fromProjectId: params.fromProjectId ?? null,
    toProjectId: params.toProjectId ?? null,
  };
}

/**
 * Move an item to a return transaction.
 * - Updates item: transactionId → returnTransactionId, status → 'returned'
 * - Creates a 'returned' lineage edge (app-side; cloud function also creates one as safety net)
 *
 * All writes are fire-and-forget per offline-first rules.
 */
export function moveItemToReturnTransaction(params: {
  accountId: string;
  itemId: string;
  fromTransactionId: string | null;
  returnTransactionId: string;
  fromProjectId?: string | null;
  toProjectId?: string | null;
}): void {
  const { accountId, itemId, returnTransactionId } = params;

  // Fire-and-forget: update item's transaction link and status
  updateItem(accountId, itemId, {
    transactionId: returnTransactionId,
    status: 'returned',
  });

  // Fire-and-forget: create lineage edge
  const edgeData = buildReturnEdgeData(params);
  createLineageEdge(accountId, edgeData);
}
