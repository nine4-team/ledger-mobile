import { Item, updateItem, subscribeToItem } from './itemsService';
import { requestBusinessToProjectPurchase, requestProjectToBusinessSale, requestProjectToProjectMove } from './inventoryOperations';

export type ResolveItemMoveOptions = {
  accountId: string;
  itemId: string;
  targetProjectId: string | null;
  targetSpaceId?: string | null;
  targetTransactionId?: string | null;
  inheritedBudgetCategoryId?: string | null;
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
  item: Item,
  options: ResolveItemMoveOptions
): Promise<ResolveItemMoveResult> {
  const { accountId, itemId, targetProjectId, targetSpaceId, targetTransactionId, inheritedBudgetCategoryId } = options;

  // If item is already in the target project, just update space/transaction
  if (item.projectId === targetProjectId) {
    const update: Partial<Item> = {};
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
  if (item.projectId == null && targetProjectId != null) {
    if (!inheritedBudgetCategoryId) {
      return {
        success: false,
        error: 'Items from inventory require a budget category when moving to a project.',
      };
    }

    await requestBusinessToProjectPurchase({
      accountId,
      targetProjectId,
      inheritedBudgetCategoryId,
      items: [{ id: itemId, projectId: null, transactionId: item.transactionId ?? null }],
    });

    // Wait for the item to be in the target project before assigning space/transaction
    await waitForScopeThenAssign(accountId, itemId, targetProjectId, targetSpaceId, targetTransactionId);
    return { success: true };
  }

  // If item is in a project and target is inventory, move to business inventory
  if (item.projectId != null && targetProjectId == null) {
    if (!inheritedBudgetCategoryId) {
      return {
        success: false,
        error: 'Items moving to business inventory require a budget category.',
      };
    }

    await requestProjectToBusinessSale({
      accountId,
      projectId: item.projectId,
      items: [{ id: itemId, projectId: item.projectId, transactionId: item.transactionId ?? null }],
    });

    // Wait for the item to be in inventory scope before assigning transaction/space
    await waitForScopeThenAssign(accountId, itemId, null, targetSpaceId, targetTransactionId);
    return { success: true };
  }

  // If item is in a different project, move between projects
  if (item.projectId != null && targetProjectId != null && item.projectId !== targetProjectId) {
    if (!inheritedBudgetCategoryId) {
      return {
        success: false,
        error: 'Items moving between projects require a budget category.',
      };
    }

    await requestProjectToProjectMove({
      accountId,
      sourceProjectId: item.projectId,
      targetProjectId,
      inheritedBudgetCategoryId,
      items: [{ id: itemId, projectId: item.projectId, transactionId: item.transactionId ?? null }],
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

      const update: Partial<Item> = {};
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
