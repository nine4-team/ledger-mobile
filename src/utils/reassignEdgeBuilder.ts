import type { ItemLineageEdge } from '../data/lineageEdgesService';

/**
 * Build the data for a correction lineage edge created during a reassign operation.
 * Reassigns are data fixes (not sales or returns), so they use movementKind: 'correction'.
 *
 * For item-level reassigns (no transaction), both fromTransactionId and toTransactionId are null.
 * For transaction-level reassigns, both point to the same transaction (the item stays in the tx, but the tx moves).
 */
export function buildReassignCorrectionEdge(params: {
  accountId: string;
  itemId: string;
  transactionId: string | null;
  note: string;
}): Omit<ItemLineageEdge, 'id' | 'createdAt'> {
  return {
    accountId: params.accountId,
    itemId: params.itemId,
    fromTransactionId: params.transactionId,
    toTransactionId: params.transactionId,
    movementKind: 'correction',
    source: 'app',
    note: params.note,
  };
}
