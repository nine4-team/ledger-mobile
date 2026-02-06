import { updateItem, subscribeToItem } from './itemsService';
import type { ItemWrite } from './itemsService';
import { requestBusinessToProjectPurchase, requestProjectToBusinessSale, requestProjectToProjectMove } from './inventoryOperations';

type MovableItem = {
  id: string;
  projectId?: string | null;
  transactionId?: string | null;
  inheritedBudgetCategoryId?: string | null;
};

export type ResolveItemMoveOptions = {
  accountId: string;
  itemId: string;
  targetProjectId: string | null;
  targetSpaceId?: string | null;
  targetTransactionId?: string | null;
  inheritedBudgetCategoryId?: string | null;
  sourceBudgetCategoryId?: string | null;
  destinationBudgetCategoryId?: string | null;
};

export type ResolveItemMoveResult = {
  success: boolean;
  error?: string;
};

/**
 * Resolves item move/re-home logic before linking or space assignment.
 * Handles:
 * - Moving items from inventory to a project (using request-doc)
 * - Moving items between projects (using request-doc)
 * - Simple project/space assignment when already in the correct project
 * - Waiting for scope changes before applying final assignment
 */
export async function resolveItemMove(
  item: MovableItem,
  options: ResolveItemMoveOptions
): Promise<ResolveItemMoveResult> {
  const {
    accountId,
    itemId,
    targetProjectId,
    targetSpaceId,
    targetTransactionId,
    inheritedBudgetCategoryId,
    sourceBudgetCategoryId,
    destinationBudgetCategoryId,
  } = options;
  const currentProjectId = item.projectId ?? null;

  // If item is already in the target project, just update space/transaction
  if (currentProjectId === targetProjectId) {
    const update: ItemWrite = {};
    if (targetSpaceId !== undefined) {
      update.spaceId = targetSpaceId;
    }
    if (targetTransactionId !== undefined) {
      update.transactionId = targetTransactionId;
    }
    if (inheritedBudgetCategoryId !== undefined) {
      update.inheritedBudgetCategoryId = inheritedBudgetCategoryId;
    }
    if (Object.keys(update).length > 0) {
      await updateItem(accountId, itemId, update);
    }
    return { success: true };
  }

  // If item is in inventory (projectId is null), move to project
  if (currentProjectId == null && targetProjectId != null) {
    const budgetCategoryId = destinationBudgetCategoryId ?? inheritedBudgetCategoryId;
    if (!budgetCategoryId) {
      return {
        success: false,
        error: 'Items from inventory require a budget category when moving to a project.',
      };
    }

    await requestBusinessToProjectPurchase({
      accountId,
      targetProjectId,
      budgetCategoryId,
      items: [{ id: itemId, projectId: null, transactionId: item.transactionId ?? null }],
    });

    // Wait for the item to be in the target project before assigning space/transaction
    await waitForScopeThenAssign(accountId, itemId, targetProjectId, targetSpaceId, targetTransactionId);
    return { success: true };
  }

  // If item is in a project and target is inventory, move to business inventory
  if (currentProjectId != null && targetProjectId == null) {
    const budgetCategoryId = sourceBudgetCategoryId ?? item.inheritedBudgetCategoryId ?? inheritedBudgetCategoryId;
    if (!budgetCategoryId) {
      return {
        success: false,
        error: 'Items moving to business inventory require a budget category.',
      };
    }

    await requestProjectToBusinessSale({
      accountId,
      projectId: currentProjectId,
      budgetCategoryId,
      items: [
        {
          id: itemId,
          projectId: currentProjectId,
          transactionId: item.transactionId ?? null,
          inheritedBudgetCategoryId: item.inheritedBudgetCategoryId ?? null,
        },
      ],
    });

    // Wait for the item to be in inventory scope before assigning transaction/space
    await waitForScopeThenAssign(accountId, itemId, null, targetSpaceId, targetTransactionId);
    return { success: true };
  }

  // If item is in a different project, move between projects
  if (currentProjectId != null && targetProjectId != null && currentProjectId !== targetProjectId) {
    const resolvedSourceCategoryId = sourceBudgetCategoryId ?? item.inheritedBudgetCategoryId ?? inheritedBudgetCategoryId;
    const resolvedDestinationCategoryId = destinationBudgetCategoryId ?? inheritedBudgetCategoryId;
    if (!resolvedSourceCategoryId || !resolvedDestinationCategoryId) {
      return {
        success: false,
        error: 'Items moving between projects require source and destination budget categories.',
      };
    }

    await requestProjectToProjectMove({
      accountId,
      sourceProjectId: currentProjectId,
      targetProjectId,
      sourceBudgetCategoryId: resolvedSourceCategoryId,
      destinationBudgetCategoryId: resolvedDestinationCategoryId,
      items: [
        {
          id: itemId,
          projectId: currentProjectId,
          transactionId: item.transactionId ?? null,
          inheritedBudgetCategoryId: item.inheritedBudgetCategoryId ?? null,
        },
      ],
    });

    // Wait for the item to be in the target project before assigning space/transaction
    await waitForScopeThenAssign(accountId, itemId, targetProjectId, targetSpaceId, targetTransactionId);
    return { success: true };
  }

  return { success: true };
}

/**
 * Waits for an item to be in the target project scope, then assigns space/transaction.
 * Has a timeout to prevent infinite waiting.
 */
async function waitForScopeThenAssign(
  accountId: string,
  itemId: string,
  targetProjectId: string | null,
  targetSpaceId: string | null | undefined,
  targetTransactionId: string | null | undefined
): Promise<void> {
  return new Promise<void>((resolve) => {
    let resolved = false;
    let unsubscribe: () => void = () => {};
    const timeoutId = setTimeout(() => {
      if (resolved) return;
      resolved = true;
      unsubscribe();
      resolve();
    }, 20000); // 20 second timeout

    unsubscribe = subscribeToItem(accountId, itemId, (item) => {
      if (!item || resolved) return;
      const matchesScope = targetProjectId ? item.projectId === targetProjectId : item.projectId == null;
      if (!matchesScope) return;
      resolved = true;
      clearTimeout(timeoutId);
      unsubscribe();

      const update: ItemWrite = {};
      if (targetSpaceId !== undefined) {
        update.spaceId = targetSpaceId;
      }
      if (targetTransactionId !== undefined) {
        update.transactionId = targetTransactionId;
      }
      void updateItem(accountId, itemId, update);
      resolve();
    });
  });
}
