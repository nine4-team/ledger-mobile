/**
 * Recalculates project.budgetSummary for all projects in the migrated account.
 * Ported from firebase/functions/scripts/backfill-budget-summaries.mjs.
 *
 * This is necessary because bulkWriter bypasses Cloud Function triggers,
 * so the denormalized budget rollup must be computed manually after writing.
 */
import admin from 'firebase-admin';

interface TxData {
  amountCents?: number;
  budgetCategoryId?: string;
  isCanceled?: boolean;
  transactionType?: string;
  isCanonicalInventorySale?: boolean;
  inventorySaleDirection?: string;
}

interface CatMeta {
  name: string;
  categoryType: string | null;
  excludeFromOverallBudget: boolean;
  isArchived: boolean;
}

function normalizeSpendAmount(tx: TxData): number {
  if (tx.isCanceled === true) return 0;
  if (typeof tx.amountCents !== 'number') return 0;
  const amount = tx.amountCents;
  const txType = typeof tx.transactionType === 'string'
    ? tx.transactionType.trim().toLowerCase()
    : null;
  if (txType === 'return') return -Math.abs(amount);
  if (tx.isCanonicalInventorySale && tx.inventorySaleDirection) {
    return tx.inventorySaleDirection === 'project_to_business'
      ? -Math.abs(amount)
      : Math.abs(amount);
  }
  return amount;
}

async function recalculateProjectBudgetSummary(
  db: admin.firestore.Firestore,
  accountId: string,
  projectId: string
): Promise<void> {
  // 1. Account-level budget categories
  const budgetCatsSnap = await db
    .collection(`accounts/${accountId}/presets/default/budgetCategories`)
    .get();
  const budgetCategories: Record<string, CatMeta> = {};
  for (const doc of budgetCatsSnap.docs) {
    const d = doc.data();
    const metadata = d.metadata ?? {};
    budgetCategories[doc.id] = {
      name: typeof d.name === 'string' ? d.name : '',
      categoryType: typeof metadata.categoryType === 'string' ? metadata.categoryType : null,
      excludeFromOverallBudget: metadata.excludeFromOverallBudget === true,
      isArchived: d.isArchived === true,
    };
  }

  // 2. Per-project budget allocations
  const projectBudgetCatsSnap = await db
    .collection(`accounts/${accountId}/projects/${projectId}/budgetCategories`)
    .get();
  const projectBudgetCents: Record<string, number> = {};
  for (const doc of projectBudgetCatsSnap.docs) {
    const d = doc.data();
    projectBudgetCents[doc.id] = typeof d.budgetCents === 'number' ? d.budgetCents : 0;
  }

  // 3. Transactions for this project
  const txSnap = await db
    .collection(`accounts/${accountId}/transactions`)
    .where('projectId', '==', projectId)
    .get();

  // 4. Compute spend per category
  const spentByCategory: Record<string, number> = {};
  for (const doc of txSnap.docs) {
    const tx = doc.data() as TxData;
    if (tx.isCanceled === true) continue;
    if (typeof tx.amountCents !== 'number') continue;
    const categoryId = typeof tx.budgetCategoryId === 'string'
      ? tx.budgetCategoryId.trim()
      : null;
    if (!categoryId) continue;
    const amount = normalizeSpendAmount(tx);
    spentByCategory[categoryId] = (spentByCategory[categoryId] ?? 0) + amount;
  }

  // 5. Build summary
  const categories: Record<string, {
    budgetCents: number; spentCents: number; name: string;
    categoryType: string | null; excludeFromOverallBudget: boolean; isArchived: boolean;
  }> = {};
  let overallSpentCents = 0;
  let overallBudgetCents = 0;

  const allCategoryIds = new Set([
    ...Object.keys(budgetCategories),
    ...Object.keys(projectBudgetCents),
    ...Object.keys(spentByCategory),
  ]);

  for (const catId of allCategoryIds) {
    const catMeta = budgetCategories[catId];
    const budgetCents = projectBudgetCents[catId] ?? 0;
    const spentCents = spentByCategory[catId] ?? 0;
    if (budgetCents === 0 && spentCents === 0) continue;
    categories[catId] = {
      budgetCents,
      spentCents,
      name: catMeta?.name ?? '',
      categoryType: catMeta?.categoryType ?? null,
      excludeFromOverallBudget: catMeta?.excludeFromOverallBudget ?? false,
      isArchived: catMeta?.isArchived ?? false,
    };
    if (!catMeta?.excludeFromOverallBudget) {
      overallSpentCents += spentCents;
      overallBudgetCents += budgetCents;
    }
  }

  // 6. Write merged into project doc
  await db.doc(`accounts/${accountId}/projects/${projectId}`).set(
    {
      budgetSummary: {
        spentCents: overallSpentCents,
        totalBudgetCents: overallBudgetCents,
        categories,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    },
    { merge: true }
  );
}

export async function backfillBudgetSummaries(
  db: admin.firestore.Firestore,
  accountId: string,
  projectIds: string[],
  options: { dryRun?: boolean } = {}
): Promise<{ backfilled: number; failed: number }> {
  if (options.dryRun) {
    console.log(`  [dry-run] Would backfill budget summaries for ${projectIds.length} project(s).`);
    return { backfilled: projectIds.length, failed: 0 };
  }

  let backfilled = 0;
  let failed = 0;

  for (const projectId of projectIds) {
    try {
      // eslint-disable-next-line no-await-in-loop
      await recalculateProjectBudgetSummary(db, accountId, projectId);
      backfilled++;
    } catch (err) {
      console.error(`  Failed to backfill budgetSummary for project ${projectId}: ${err}`);
      failed++;
    }
  }

  return { backfilled, failed };
}
