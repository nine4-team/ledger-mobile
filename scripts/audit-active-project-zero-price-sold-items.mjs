#!/usr/bin/env node
/**
 * Audit current project items on active projects whose project price is zero
 * or missing, with a focus on items sold from Business Inventory.
 *
 * Read-only.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/audit-active-project-zero-price-sold-items.mjs
 *
 * Optional:
 *   FIREBASE_PROJECT_ID=ledger-nine4
 */

import fs from 'node:fs';
import path from 'node:path';
import admin from 'firebase-admin';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const OUT_DIR = path.join('docs', 'plans', 'zero-project-price-audit-runs');

function initFirestore() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  return admin.firestore();
}

function accountIdFromPath(pathValue) {
  return pathValue.split('/')[1] ?? null;
}

function compactDate(value) {
  return value?.toDate?.()?.toISOString?.() ?? value ?? null;
}

function normalize(value) {
  return String(value ?? '').trim().toLowerCase();
}

function cents(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function isZeroOrMissingProjectPrice(item) {
  const price = cents(item.projectPriceCents);
  return price == null || price <= 0;
}

function isInventorySource(value) {
  const text = normalize(value);
  return text === 'inventory' || text === 'business inventory' || text.endsWith(' inventory');
}

async function fetchActiveProjects(db) {
  const snap = await db.collectionGroup('projects').get();

  return new Map(snap.docs.filter((doc) => doc.data()?.isArchived !== true).map((doc) => {
    const data = doc.data() ?? {};
    return [doc.id, {
      id: doc.id,
      path: doc.ref.path,
      accountId: accountIdFromPath(doc.ref.path),
      name: data.name ?? '',
      clientName: data.clientName ?? '',
      isArchived: data.isArchived ?? null,
    }];
  }));
}

async function fetchSoldEdgesByItem(db) {
  const snap = await db.collectionGroup('lineageEdges').get();

  const byItem = new Map();
  for (const doc of snap.docs) {
    const data = doc.data() ?? {};
    if (data.movementKind !== 'sold') continue;
    if (!data.itemId) continue;
    const entry = {
      id: doc.id,
      path: doc.ref.path,
      accountId: accountIdFromPath(doc.ref.path),
      itemId: data.itemId,
      fromProjectId: data.fromProjectId ?? null,
      toProjectId: data.toProjectId ?? null,
      fromTransactionId: data.fromTransactionId ?? null,
      toTransactionId: data.toTransactionId ?? null,
      createdAt: compactDate(data.createdAt),
    };
    const edges = byItem.get(data.itemId) ?? [];
    edges.push(entry);
    byItem.set(data.itemId, edges);
  }
  return byItem;
}

async function fetchTransactionsForRefs(db, refs) {
  const paths = [...refs].filter(Boolean);
  const byPath = new Map();
  for (let i = 0; i < paths.length; i += 400) {
    const chunk = paths.slice(i, i + 400);
    const snaps = await db.getAll(...chunk.map((p) => db.doc(p)));
    for (const snap of snaps) {
      if (snap.exists) byPath.set(snap.ref.path, { id: snap.id, path: snap.ref.path, ...(snap.data() ?? {}) });
    }
  }
  return byPath;
}

async function main() {
  const db = initFirestore();
  const activeProjects = await fetchActiveProjects(db);
  const soldEdgesByItem = await fetchSoldEdgesByItem(db);

  const itemsSnap = await db.collectionGroup('items').get();
  const candidates = [];
  const transactionPaths = new Set();

  for (const doc of itemsSnap.docs) {
    const item = doc.data() ?? {};
    const accountId = accountIdFromPath(doc.ref.path);
    const projectId = item.projectId ?? null;
    if (!projectId || !activeProjects.has(projectId)) continue;
    if (!isZeroOrMissingProjectPrice(item)) continue;

    const soldEdges = (soldEdgesByItem.get(doc.id) ?? [])
      .filter((edge) => edge.accountId === accountId && edge.toProjectId === projectId);
    const currentTxPath = item.transactionId
      ? `accounts/${accountId}/transactions/${item.transactionId}`
      : null;
    if (currentTxPath) transactionPaths.add(currentTxPath);
    for (const edge of soldEdges) {
      if (edge.toTransactionId) transactionPaths.add(`accounts/${accountId}/transactions/${edge.toTransactionId}`);
    }

    candidates.push({
      itemPath: doc.ref.path,
      itemId: doc.id,
      accountId,
      projectId,
      projectName: activeProjects.get(projectId)?.name ?? '',
      clientName: activeProjects.get(projectId)?.clientName ?? '',
      name: item.name ?? item.description ?? '',
      source: item.source ?? null,
      currentSource: item.currentSource ?? null,
      status: item.status ?? null,
      budgetCategoryId: item.budgetCategoryId ?? null,
      purchasePriceCents: cents(item.purchasePriceCents),
      projectPriceCents: cents(item.projectPriceCents),
      transactionId: item.transactionId ?? null,
      soldEdgeCount: soldEdges.length,
      soldEdges,
      likelySoldFromInventory: soldEdges.length > 0 || isInventorySource(item.currentSource),
    });
  }

  const transactions = await fetchTransactionsForRefs(db, transactionPaths);
  for (const item of candidates) {
    const related = [];
    if (item.transactionId) {
      const tx = transactions.get(`accounts/${item.accountId}/transactions/${item.transactionId}`);
      if (tx) related.push(tx);
    }
    for (const edge of item.soldEdges) {
      const tx = transactions.get(`accounts/${item.accountId}/transactions/${edge.toTransactionId}`);
      if (tx && !related.some((existing) => existing.path === tx.path)) related.push(tx);
    }
    item.relatedTransactions = related.map((tx) => ({
      transactionPath: tx.path,
      transactionId: tx.id,
      type: tx.type ?? tx.transactionType ?? null,
      source: tx.source ?? null,
      amountCents: cents(tx.amountCents),
      subtotalCents: cents(tx.subtotalCents),
      itemIdsCount: Array.isArray(tx.itemIds) ? tx.itemIds.length : null,
      status: tx.status ?? null,
      createdAt: compactDate(tx.createdAt),
    }));
    item.zeroDollarInventorySaleTransactions = item.relatedTransactions.filter((tx) =>
      (normalize(tx.type) === 'purchase' || normalize(tx.type) === 'sale') &&
      isInventorySource(tx.source) &&
      (tx.amountCents == null || tx.amountCents <= 0)
    );
  }

  const likelySold = candidates.filter((item) => item.likelySoldFromInventory);
  const confirmedSoldByEdge = candidates.filter((item) => item.soldEdgeCount > 0);
  const withZeroDollarTx = candidates.filter((item) => item.zeroDollarInventorySaleTransactions.length > 0);
  const byProject = new Map();
  for (const item of candidates) {
    const row = byProject.get(item.projectId) ?? {
      projectId: item.projectId,
      projectName: item.projectName,
      clientName: item.clientName,
      zeroOrMissingProjectPriceCurrentItems: 0,
      likelySoldFromInventory: 0,
      confirmedSoldByEdge: 0,
      zeroDollarInventorySaleTransactions: 0,
    };
    row.zeroOrMissingProjectPriceCurrentItems += 1;
    if (item.likelySoldFromInventory) row.likelySoldFromInventory += 1;
    if (item.soldEdgeCount > 0) row.confirmedSoldByEdge += 1;
    if (item.zeroDollarInventorySaleTransactions.length > 0) row.zeroDollarInventorySaleTransactions += 1;
    byProject.set(item.projectId, row);
  }

  const report = {
    firestoreProjectId: PROJECT_ID,
    generatedAt: new Date().toISOString(),
    activeProjectsScanned: activeProjects.size,
    currentProjectItemsScanned: itemsSnap.size,
    summary: {
      zeroOrMissingProjectPriceCurrentItemsOnActiveProjects: candidates.length,
      likelySoldFromInventory: likelySold.length,
      confirmedSoldFromInventoryBySoldLineageEdge: confirmedSoldByEdge.length,
      withZeroDollarInventorySaleTransaction: withZeroDollarTx.length,
    },
    byProject: [...byProject.values()].sort((a, b) =>
      b.likelySoldFromInventory - a.likelySoldFromInventory || a.projectName.localeCompare(b.projectName)
    ),
    candidates: candidates.sort((a, b) =>
      a.projectName.localeCompare(b.projectName) || a.name.localeCompare(b.name)
    ),
  };

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const outPath = path.join(OUT_DIR, `${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(outPath, JSON.stringify(report, null, 2));

  console.log(JSON.stringify({
    reportPath: outPath,
    ...report.summary,
    activeProjectsScanned: report.activeProjectsScanned,
    byProject: report.byProject,
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
