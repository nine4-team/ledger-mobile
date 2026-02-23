import { updateItem } from './itemsService';
import { updateTransaction } from './transactionsService';
import { createLineageEdge } from './lineageEdgesService';
import { buildReassignCorrectionEdge } from '../utils/reassignEdgeBuilder';
import type { Item } from './itemsService';
import type { Transaction } from './transactionsService';

// ---------------------------------------------------------------------------
// Validation (pure, testable)
// ---------------------------------------------------------------------------

export type ReassignValidationResult =
  | { valid: true }
  | { valid: false; error: string };

/**
 * Validate whether an item can be reassigned to a different project or inventory.
 * @param targetProjectId - null means "reassign to inventory"
 */
export function validateItemReassign(
  item: Pick<Item, 'projectId' | 'transactionId'>,
  targetProjectId: string | null
): ReassignValidationResult {
  if (item.transactionId) {
    return {
      valid: false,
      error:
        'This item is linked to a transaction. Unlink it first, or reassign the transaction instead.',
    };
  }
  if (!item.projectId) {
    return { valid: false, error: 'This item is already in inventory.' };
  }
  if (targetProjectId !== null && item.projectId === targetProjectId) {
    return { valid: false, error: 'Item is already in this project.' };
  }
  return { valid: true };
}

/**
 * Validate whether a transaction can be reassigned to a different project or inventory.
 * @param targetProjectId - null means "reassign to inventory"
 */
export function validateTransactionReassign(
  transaction: Pick<Transaction, 'projectId' | 'isCanonicalInventory'>,
  targetProjectId: string | null
): ReassignValidationResult {
  if (transaction.isCanonicalInventory) {
    return {
      valid: false,
      error: 'Sale/purchase transactions cannot be reassigned.',
    };
  }
  if (targetProjectId === null && !transaction.projectId) {
    return {
      valid: false,
      error: 'This transaction is already in inventory.',
    };
  }
  if (targetProjectId !== null && transaction.projectId === targetProjectId) {
    return {
      valid: false,
      error: 'Transaction is already in this project.',
    };
  }
  return { valid: true };
}

// ---------------------------------------------------------------------------
// Execution (fire-and-forget, delegates to existing services)
// ---------------------------------------------------------------------------

/** Reassign an item to business inventory (clear project, transaction, space). */
export function reassignItemToInventory(
  accountId: string,
  itemId: string
): void {
  updateItem(accountId, itemId, {
    projectId: null,
    transactionId: null,
    spaceId: null,
  });
  createLineageEdge(accountId, buildReassignCorrectionEdge({
    accountId,
    itemId,
    transactionId: null,
    note: 'Reassigned to inventory',
  }));
}

/** Reassign an item to a different project (clear transaction and space). */
export function reassignItemToProject(
  accountId: string,
  itemId: string,
  targetProjectId: string
): void {
  updateItem(accountId, itemId, {
    projectId: targetProjectId,
    transactionId: null,
    spaceId: null,
  });
  createLineageEdge(accountId, buildReassignCorrectionEdge({
    accountId,
    itemId,
    transactionId: null,
    note: 'Reassigned to project',
  }));
}

/**
 * Reassign a transaction and all its items to a different project.
 * Items' spaceIds are cleared because spaces are project-scoped.
 */
export function reassignTransactionToProject(
  accountId: string,
  transactionId: string,
  targetProjectId: string,
  itemIds: string[]
): void {
  updateTransaction(accountId, transactionId, { projectId: targetProjectId });
  for (const itemId of itemIds) {
    updateItem(accountId, itemId, {
      projectId: targetProjectId,
      spaceId: null,
    });
    createLineageEdge(accountId, buildReassignCorrectionEdge({
      accountId,
      itemId,
      transactionId,
      note: 'Transaction reassigned to project',
    }));
  }
}

/**
 * Reassign a transaction and all its items to business inventory.
 * Items' spaceIds are cleared.
 */
export function reassignTransactionToInventory(
  accountId: string,
  transactionId: string,
  itemIds: string[]
): void {
  updateTransaction(accountId, transactionId, { projectId: null });
  for (const itemId of itemIds) {
    updateItem(accountId, itemId, { projectId: null, spaceId: null });
    createLineageEdge(accountId, buildReassignCorrectionEdge({
      accountId,
      itemId,
      transactionId,
      note: 'Transaction reassigned to inventory',
    }));
  }
}

// ---------------------------------------------------------------------------
// Bulk helpers (pure, testable)
// ---------------------------------------------------------------------------

export type BulkReassignFilterResult = {
  eligible: string[];
  blockedCount: number;
};

/**
 * Filter items for bulk reassign: exclude any with a transaction link.
 */
export function filterItemsForBulkReassign(
  items: Pick<Item, 'id' | 'transactionId'>[]
): BulkReassignFilterResult {
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
}
