import { createRequestDoc, generateRequestOpId } from './requestDocs';

export type InventoryOperationType =
  | 'ITEM_SALE_PROJECT_TO_BUSINESS'
  | 'ITEM_SALE_BUSINESS_TO_PROJECT'
  | 'ITEM_SALE_PROJECT_TO_PROJECT';

export type InventoryOperationExpected = {
  itemProjectId: string | null;
  itemTransactionId?: string | null;
};

export type ProjectToBusinessPayload = {
  itemId: string;
  sourceProjectId: string;
  budgetCategoryId: string;
  expected: InventoryOperationExpected;
};

export type BusinessToProjectPayload = {
  itemId: string;
  targetProjectId: string;
  budgetCategoryId: string;
  expected: InventoryOperationExpected;
};

export type ProjectToProjectPayload = {
  itemId: string;
  sourceProjectId: string;
  targetProjectId: string;
  sourceBudgetCategoryId: string;
  destinationBudgetCategoryId: string;
  expected: InventoryOperationExpected;
};

export function isCanonicalInventorySaleTransaction(
  transaction?: {
    id?: string | null;
    isCanonicalInventorySale?: boolean | null;
    inventorySaleDirection?: string | null;
  } | null
): boolean {
  if (!transaction) return false;
  if (transaction.isCanonicalInventorySale === true) return true;
  if (transaction.inventorySaleDirection) return true;
  if (transaction.id) return transaction.id.startsWith('SALE_');
  return false;
}

export async function requestProjectToBusinessSale(params: {
  accountId: string;
  projectId: string;
  items: Array<{
    id: string;
    projectId?: string | null;
    transactionId?: string | null;
    budgetCategoryId?: string | null;
  }>;
  budgetCategoryId?: string;
  opId?: string;
}): Promise<string[]> {
  const results: string[] = [];
  for (const item of params.items) {
    const budgetCategoryId = item.budgetCategoryId ?? params.budgetCategoryId ?? null;
    if (!budgetCategoryId) {
      throw new Error('Missing budgetCategoryId for project-to-business sale request.');
    }
    const payload: ProjectToBusinessPayload = {
      itemId: item.id,
      sourceProjectId: params.projectId,
      budgetCategoryId,
      expected: {
        itemProjectId: item.projectId ?? null,
        itemTransactionId: item.transactionId ?? null,
      },
    };
    const opId = params.opId ?? generateRequestOpId();
    const requestId = await createRequestDoc('ITEM_SALE_PROJECT_TO_BUSINESS', payload, { accountId: params.accountId, scope: 'account' }, opId);
    results.push(requestId);
  }
  return results;
}

export async function requestBusinessToProjectPurchase(params: {
  accountId: string;
  targetProjectId: string;
  budgetCategoryId: string;
  items: Array<{ id: string; projectId?: string | null; transactionId?: string | null }>;
  opId?: string;
}): Promise<string[]> {
  const results: string[] = [];
  for (const item of params.items) {
    const payload: BusinessToProjectPayload = {
      itemId: item.id,
      targetProjectId: params.targetProjectId,
      budgetCategoryId: params.budgetCategoryId,
      expected: {
        itemProjectId: item.projectId ?? null,
        itemTransactionId: item.transactionId ?? null,
      },
    };
    const opId = params.opId ?? generateRequestOpId();
    const requestId = await createRequestDoc('ITEM_SALE_BUSINESS_TO_PROJECT', payload, { accountId: params.accountId, scope: 'account' }, opId);
    results.push(requestId);
  }
  return results;
}

export async function requestProjectToProjectMove(params: {
  accountId: string;
  sourceProjectId: string;
  targetProjectId: string;
  sourceBudgetCategoryId?: string | null;
  destinationBudgetCategoryId: string;
  items: Array<{
    id: string;
    projectId?: string | null;
    transactionId?: string | null;
    budgetCategoryId?: string | null;
  }>;
  opId?: string;
}): Promise<string[]> {
  const results: string[] = [];
  for (const item of params.items) {
    const sourceBudgetCategoryId = item.budgetCategoryId ?? params.sourceBudgetCategoryId ?? null;
    if (!sourceBudgetCategoryId) {
      throw new Error('Missing sourceBudgetCategoryId for project-to-project sale request.');
    }
    const payload: ProjectToProjectPayload = {
      itemId: item.id,
      sourceProjectId: params.sourceProjectId,
      targetProjectId: params.targetProjectId,
      sourceBudgetCategoryId,
      destinationBudgetCategoryId: params.destinationBudgetCategoryId,
      expected: {
        itemProjectId: item.projectId ?? null,
        itemTransactionId: item.transactionId ?? null,
      },
    };
    const opId = params.opId ?? generateRequestOpId();
    const requestId = await createRequestDoc('ITEM_SALE_PROJECT_TO_PROJECT', payload, { accountId: params.accountId, scope: 'account' }, opId);
    results.push(requestId);
  }
  return results;
}
