/**
 * Pure action handlers for item operations.
 *
 * Extracted from component callbacks so they can be unit tested.
 * Each function takes explicit params and calls service functions directly
 * (fire-and-forget per offline-first rules).
 */

import {
  resolveSourceCategories,
  resolveDestinationCategories,
  type ItemForCategoryResolution,
} from '../utils/bulkSaleUtils';
import {
  requestProjectToBusinessSale,
  requestBusinessToProjectPurchase,
  requestProjectToProjectMove,
} from '../data/inventoryOperations';
import {
  filterItemsForBulkReassign,
  reassignItemToInventory,
  reassignItemToProject,
} from '../data/reassignService';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type SellableItem = ItemForCategoryResolution & {
  projectId?: string | null;
  transactionId?: string | null;
};

type ReassignableItem = {
  id: string;
  transactionId?: string | null;
};

// ---------------------------------------------------------------------------
// Sell to Business (Project → Business)
// ---------------------------------------------------------------------------

/**
 * Resolve source categories and execute project-to-business sale.
 * Returns the number of items processed (0 if nothing could be resolved).
 */
export function executeSellToBusiness(params: {
  accountId: string;
  projectId: string;
  items: SellableItem[];
  sourceCategoryId: string | null;
}): number {
  const { accountId, projectId, items, sourceCategoryId } = params;
  const resolved = resolveSourceCategories(items, sourceCategoryId);
  if (resolved.length === 0) return 0;

  const itemsWithCategories = resolved.map((r) => {
    const original = items.find((i) => i.id === r.id)!;
    return { ...original, budgetCategoryId: r.resolvedCategoryId };
  });

  requestProjectToBusinessSale({ accountId, projectId, items: itemsWithCategories });
  return resolved.length;
}

// ---------------------------------------------------------------------------
// Sell to Project (Project → Project, or Business → Project)
// ---------------------------------------------------------------------------

/**
 * Branch on scope, resolve categories, and execute sell-to-project.
 * - Project scope: resolves both source and dest categories, calls requestProjectToProjectMove.
 * - Inventory scope: resolves dest categories, calls requestBusinessToProjectPurchase.
 * Returns the number of items processed.
 */
export function executeSellToProject(params: {
  accountId: string;
  scope: 'project' | 'inventory';
  sourceProjectId?: string;
  targetProjectId: string;
  items: SellableItem[];
  sourceCategoryId: string | null;
  destCategoryId: string | null;
  validDestCategoryIds: Set<string>;
}): number {
  const {
    accountId,
    scope,
    sourceProjectId,
    targetProjectId,
    items,
    sourceCategoryId,
    destCategoryId,
    validDestCategoryIds,
  } = params;

  if (scope === 'project' && sourceProjectId) {
    // Project → Project: resolve both source and dest categories
    const resolvedDest = resolveDestinationCategories(items, validDestCategoryIds, destCategoryId);
    const resolvedSource = resolveSourceCategories(items, sourceCategoryId);
    if (resolvedDest.length === 0) return 0;

    const destinationBudgetCategoryId = resolvedDest[0].resolvedCategoryId;
    const itemsWithCategories = resolvedSource.map((r) => {
      const original = items.find((i) => i.id === r.id)!;
      return { ...original, budgetCategoryId: r.resolvedCategoryId };
    });

    requestProjectToProjectMove({
      accountId,
      sourceProjectId,
      targetProjectId,
      destinationBudgetCategoryId,
      items: itemsWithCategories,
    });
    return resolvedSource.length;
  } else {
    // Business → Project: resolve dest categories only
    const resolvedDest = resolveDestinationCategories(items, validDestCategoryIds, destCategoryId);
    if (resolvedDest.length === 0) return 0;

    const budgetCategoryId = resolvedDest[0].resolvedCategoryId;
    requestBusinessToProjectPurchase({
      accountId,
      targetProjectId,
      budgetCategoryId,
      items,
    });
    return items.length;
  }
}

// ---------------------------------------------------------------------------
// Bulk Reassign
// ---------------------------------------------------------------------------

/**
 * Filter eligible items (no transactionId) and reassign each to inventory.
 * Returns counts of executed and blocked items.
 */
export function executeBulkReassignToInventory(params: {
  accountId: string;
  items: ReassignableItem[];
}): { executed: number; blocked: number } {
  const { accountId, items } = params;
  const { eligible, blockedCount } = filterItemsForBulkReassign(items);

  for (const itemId of eligible) {
    reassignItemToInventory(accountId, itemId);
  }

  return { executed: eligible.length, blocked: blockedCount };
}

/**
 * Filter eligible items (no transactionId) and reassign each to a target project.
 * Returns counts of executed and blocked items.
 */
export function executeBulkReassignToProject(params: {
  accountId: string;
  items: ReassignableItem[];
  targetProjectId: string;
}): { executed: number; blocked: number } {
  const { accountId, items, targetProjectId } = params;
  const { eligible, blockedCount } = filterItemsForBulkReassign(items);

  for (const itemId of eligible) {
    reassignItemToProject(accountId, itemId, targetProjectId);
  }

  return { executed: eligible.length, blocked: blockedCount };
}
