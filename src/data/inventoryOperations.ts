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
  expected: InventoryOperationExpected;
  note?: string | null;
};

export type BusinessToProjectPayload = {
  itemId: string;
  targetProjectId: string;
  inheritedBudgetCategoryId: string | null;
  expected: InventoryOperationExpected;
  note?: string | null;
};

export type ProjectToProjectPayload = {
  itemId: string;
  sourceProjectId: string;
  targetProjectId: string;
  inheritedBudgetCategoryId: string | null;
  expected: InventoryOperationExpected;
  note?: string | null;
};

export function isCanonicalTransactionId(id: string | null | undefined): boolean {
  if (!id) return false;
  return id.startsWith('INV_PURCHASE_') || id.startsWith('INV_SALE_');
}

export async function requestProjectToBusinessSale(params: {
  accountId: string;
  projectId: string;
  items: Array<{ id: string; projectId?: string | null; transactionId?: string | null }>;
  opId?: string;
  note?: string;
}): Promise<string[]> {
  const results: string[] = [];
  for (const item of params.items) {
    const payload: ProjectToBusinessPayload = {
      itemId: item.id,
      sourceProjectId: params.projectId,
      expected: {
        itemProjectId: item.projectId ?? null,
        itemTransactionId: item.transactionId ?? null,
      },
      note: params.note ?? null,
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
  inheritedBudgetCategoryId: string | null;
  items: Array<{ id: string; projectId?: string | null; transactionId?: string | null }>;
  opId?: string;
  note?: string;
}): Promise<string[]> {
  const results: string[] = [];
  for (const item of params.items) {
    const payload: BusinessToProjectPayload = {
      itemId: item.id,
      targetProjectId: params.targetProjectId,
      inheritedBudgetCategoryId: params.inheritedBudgetCategoryId,
      expected: {
        itemProjectId: item.projectId ?? null,
        itemTransactionId: item.transactionId ?? null,
      },
      note: params.note ?? null,
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
  inheritedBudgetCategoryId: string | null;
  items: Array<{ id: string; projectId?: string | null; transactionId?: string | null }>;
  opId?: string;
  note?: string;
}): Promise<string[]> {
  const results: string[] = [];
  for (const item of params.items) {
    const payload: ProjectToProjectPayload = {
      itemId: item.id,
      sourceProjectId: params.sourceProjectId,
      targetProjectId: params.targetProjectId,
      inheritedBudgetCategoryId: params.inheritedBudgetCategoryId,
      expected: {
        itemProjectId: item.projectId ?? null,
        itemTransactionId: item.transactionId ?? null,
      },
      note: params.note ?? null,
    };
    const opId = params.opId ?? generateRequestOpId();
    const requestId = await createRequestDoc('ITEM_SALE_PROJECT_TO_PROJECT', payload, { accountId: params.accountId, scope: 'account' }, opId);
    results.push(requestId);
  }
  return results;
}
