#!/usr/bin/env node
/**
 * Backfill budget summaries for all projects in the emulator.
 *
 * Runs the same recalculation logic as the Cloud Function triggers
 * but directly via Admin SDK — necessary because the seed script
 * uses bulkWriter which bypasses Cloud Function triggers.
 *
 * Usage:
 *   node firebase/functions/scripts/backfill-budget-summaries.mjs
 *
 * Expects env vars:
 *   FIRESTORE_EMULATOR_HOST  (e.g. "localhost:8181")
 *   FIREBASE_PROJECT_ID      (e.g. "ledger-nine4")
 */

import admin from 'firebase-admin';

const projectId = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

/**
 * Mirrors normalizeSpendAmount from budgetProgressService.ts
 */
function normalizeSpendAmount(tx) {
  if (tx.isCanceled === true) return 0;
  if (typeof tx.amountCents !== 'number') return 0;

  let amount = tx.amountCents;
  const txType =
    typeof tx.transactionType === 'string'
      ? tx.transactionType.trim().toLowerCase()
      : null;

  if (txType === 'return') {
    return -Math.abs(amount);
  }
  if (tx.isCanonicalInventorySale && tx.inventorySaleDirection) {
    return tx.inventorySaleDirection === 'project_to_business'
      ? -Math.abs(amount)
      : Math.abs(amount);
  }
  return amount;
}

async function recalculateProjectBudgetSummary(accountId, projectId) {
  // 1. Fetch account-level budget categories
  const budgetCatsSnapshot = await db
    .collection(`accounts/${accountId}/presets/default/budgetCategories`)
    .get();
  const budgetCategories = {};
  for (const doc of budgetCatsSnapshot.docs) {
    const data = doc.data() ?? {};
    const metadata = data.metadata ?? {};
    budgetCategories[doc.id] = {
      name: typeof data.name === 'string' ? data.name : '',
      categoryType:
        typeof metadata.categoryType === 'string' ? metadata.categoryType : null,
      excludeFromOverallBudget: metadata.excludeFromOverallBudget === true,
      isArchived: data.isArchived === true,
    };
  }

  // 2. Fetch project budget categories
  const projectBudgetCatsSnapshot = await db
    .collection(`accounts/${accountId}/projects/${projectId}/budgetCategories`)
    .get();
  const projectBudgetCents = {};
  for (const doc of projectBudgetCatsSnapshot.docs) {
    const data = doc.data() ?? {};
    projectBudgetCents[doc.id] =
      typeof data.budgetCents === 'number' ? data.budgetCents : 0;
  }

  // 3. Fetch transactions
  const txSnapshot = await db
    .collection(`accounts/${accountId}/transactions`)
    .where('projectId', '==', projectId)
    .get();

  // 4. Compute spend per category
  const spentByCategory = {};
  for (const doc of txSnapshot.docs) {
    const tx = doc.data() ?? {};
    if (tx.isCanceled === true) continue;
    if (typeof tx.amountCents !== 'number') continue;

    const categoryId =
      typeof tx.budgetCategoryId === 'string'
        ? tx.budgetCategoryId.trim()
        : null;
    if (!categoryId) continue;

    const amount = normalizeSpendAmount(tx);
    spentByCategory[categoryId] = (spentByCategory[categoryId] ?? 0) + amount;
  }

  // 5. Build summary
  const categories = {};
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

  // 6. Write to project doc
  await db.doc(`accounts/${accountId}/projects/${projectId}`).set(
    {
      budgetSummary: {
        spentCents: overallSpentCents,
        totalBudgetCents: overallBudgetCents,
        categories,
        updatedAt: FieldValue.serverTimestamp(),
      },
    },
    { merge: true }
  );
}

async function main() {
  // Discover all accounts
  const accountsSnapshot = await db.collectionGroup('projects').select().get();
  const accountProjects = new Map();

  for (const doc of accountsSnapshot.docs) {
    // Path: accounts/{accountId}/projects/{projectId}
    const parts = doc.ref.path.split('/');
    const accountId = parts[1];
    const projectId = parts[3];
    if (!accountProjects.has(accountId)) {
      accountProjects.set(accountId, []);
    }
    accountProjects.get(accountId).push(projectId);
  }

  let total = 0;
  for (const [accountId, projectIds] of accountProjects) {
    console.log(
      `Backfilling ${projectIds.length} projects for account ${accountId}...`
    );
    for (const pid of projectIds) {
      await recalculateProjectBudgetSummary(accountId, pid);
      total++;
    }
  }

  console.log(`Done. Backfilled ${total} project(s).`);
}

main().catch((err) => {
  console.error('Backfill failed:', err);
  process.exit(1);
});
