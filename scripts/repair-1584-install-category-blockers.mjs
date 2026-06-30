#!/usr/bin/env node
/**
 * Repair missing 1584 category targets needed by the transaction taxonomy cleanup.
 *
 * The migration needs concrete targets for rows the user classified as install
 * supplies or install services. This script creates those account preset
 * categories when absent and enables them on affected projects.
 *
 * Defaults to dry-run and writes JSONL decisions to stdout.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/repair-1584-install-category-blockers.mjs
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/repair-1584-install-category-blockers.mjs --commit --backup <backup.json>
 *
 * Optional:
 *   FIREBASE_PROJECT_ID=ledger-nine4
 *   ACCOUNT_ID=<accountId>
 */

import { randomUUID } from 'node:crypto';
import admin from 'firebase-admin';
import fs from 'node:fs';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const ACCOUNT_ID = process.env.ACCOUNT_ID || '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
const COMMIT = process.argv.includes('--commit');
const BACKUP_PATH = (() => {
  const index = process.argv.indexOf('--backup');
  return index === -1 ? null : process.argv[index + 1] ?? null;
})();

if (COMMIT && (!BACKUP_PATH || !fs.existsSync(BACKUP_PATH))) {
  throw new Error('--commit requires --backup <existing-backup.json>');
}

const REQUIRED_CATEGORIES = [
  {
    name: 'Install Supplies',
    slug: 'install-supplies',
    supportedTypes: ['purchase', 'return'],
    metadata: { categoryType: null, excludeFromOverallBudget: false },
  },
  {
    name: 'Install Services',
    slug: 'install-services',
    supportedTypes: ['expense'],
    metadata: { categoryType: null, excludeFromOverallBudget: false },
  },
];

function initFirestore() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  return admin.firestore();
}

function normalize(value) {
  return String(value ?? '').trim().toLowerCase();
}

function sameSet(values, target) {
  if (!Array.isArray(values)) return false;
  const actual = [...new Set(values.map(normalize))].sort();
  const expected = [...target].sort();
  return actual.length === expected.length && actual.every((value, index) => value === expected[index]);
}

function targetCategoryNameForTransaction(tx, projectCategoryNames = new Set()) {
  const source = normalize(tx.source);
  const notes = normalize(tx.notes);
  const combined = `${source} ${notes}`;

  if (combined.includes('cinema works')) return 'Install Services';
  if (combined.includes('home depot')) return 'Install Supplies';
  if (combined.includes("lowe's") || combined.includes('lowe’s') || combined.includes('lowes')) return 'Install Supplies';
  if (combined.includes('ace hardware')) return 'Install Supplies';
  if (combined.includes('dean berryessa')) return 'Install Services';
  if (combined.includes('install expenses')) return 'Install Services';
  if (combined.includes('fedex')) {
    return projectCategoryNames.has('storage & receiving') ? 'Storage & Receiving' : 'Install Services';
  }
  return null;
}

async function loadPresetCategories(db) {
  const snap = await db.collection(`accounts/${ACCOUNT_ID}/presets/default/budgetCategories`).get();
  const categories = [];
  const byName = new Map();
  const nameById = new Map();
  for (const doc of snap.docs) {
    const data = doc.data() ?? {};
    categories.push({ id: doc.id, ref: doc.ref, data });
    if (data.name) byName.set(normalize(data.name), { id: doc.id, ref: doc.ref, data });
    if (data.name) nameById.set(doc.id, normalize(data.name));
  }
  return { categories, byName, nameById };
}

async function loadProjectCategoryNames(db, nameById) {
  const projectsSnap = await db.collection(`accounts/${ACCOUNT_ID}/projects`).get();
  const namesByProjectId = new Map();
  const markerIdsByProjectId = new Map();
  for (const projectDoc of projectsSnap.docs) {
    const markersSnap = await projectDoc.ref.collection('budgetCategories').get();
    const names = new Set();
    const markerIds = new Set();
    for (const marker of markersSnap.docs) {
      markerIds.add(marker.id);
      const markerName = marker.data()?.name;
      const name = nameById.get(marker.id) ?? normalize(markerName);
      if (name) names.add(name);
    }
    namesByProjectId.set(projectDoc.id, names);
    markerIdsByProjectId.set(projectDoc.id, markerIds);
  }
  return { namesByProjectId, markerIdsByProjectId };
}

async function main() {
  const db = initFirestore();
  const FieldValue = admin.firestore.FieldValue;
  const { categories, byName, nameById } = await loadPresetCategories(db);
  const { namesByProjectId, markerIdsByProjectId } = await loadProjectCategoryNames(db, nameById);
  const numericOrders = categories
    .filter((category) => category.data.order != null)
    .map((category) => Number(category.data.order))
    .filter(Number.isFinite);
  const maxOrder = numericOrders.length > 0 ? Math.max(...numericOrders) : null;

  const requiredByName = new Map(REQUIRED_CATEGORIES.map((category) => [normalize(category.name), category]));
  const resolvedRequired = new Map();
  let nextOrder = maxOrder == null ? null : maxOrder + 1;

  for (const required of REQUIRED_CATEGORIES) {
    const existing = byName.get(normalize(required.name));
    if (existing) {
      resolvedRequired.set(required.name, existing);
      console.log(JSON.stringify({
        mode: COMMIT ? 'commit' : 'dry-run',
        action: 'category-exists',
        accountId: ACCOUNT_ID,
        name: required.name,
        path: existing.ref.path,
        supportedTypes: existing.data.supportedTypes ?? null,
      }));
      continue;
    }

    const ref = db.collection(`accounts/${ACCOUNT_ID}/presets/default/budgetCategories`).doc(randomUUID());
    const data = {
      accountId: ACCOUNT_ID,
      name: required.name,
      slug: required.slug,
      metadata: required.metadata,
      supportedTypes: required.supportedTypes,
      isArchived: false,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (nextOrder != null) {
      data.order = nextOrder;
      nextOrder += 1;
    }
    resolvedRequired.set(required.name, { id: ref.id, ref, data });
    console.log(JSON.stringify({
      mode: COMMIT ? 'commit' : 'dry-run',
      action: 'create-category',
      accountId: ACCOUNT_ID,
      name: required.name,
      path: ref.path,
      data: {
        ...data,
        createdAt: '(serverTimestamp)',
        updatedAt: '(serverTimestamp)',
      },
    }));
    if (COMMIT) await ref.set(data);
  }

  const mixedCategoryIds = new Set(
    categories
      .filter((category) => sameSet(category.data.supportedTypes, ['purchase', 'return', 'expense']))
      .map((category) => category.id)
  );

  const projectTargets = new Map();
  const txSnap = await db.collection(`accounts/${ACCOUNT_ID}/transactions`).get();
  for (const txDoc of txSnap.docs) {
    const tx = txDoc.data() ?? {};
    if (!mixedCategoryIds.has(tx.budgetCategoryId)) continue;
    const projectNames = namesByProjectId.get(tx.projectId) ?? new Set();
    const targetName = targetCategoryNameForTransaction(tx, projectNames);
    if (!targetName || !requiredByName.has(normalize(targetName)) || !tx.projectId) continue;

    const target = resolvedRequired.get(targetName);
    if (!target) continue;
    const key = `${tx.projectId}:${target.id}`;
    if (!projectTargets.has(key)) {
      projectTargets.set(key, {
        projectId: tx.projectId,
        targetName,
        targetId: target.id,
        txExamples: [],
      });
    }
    const entry = projectTargets.get(key);
    if (entry.txExamples.length < 5) {
      entry.txExamples.push({
        id: txDoc.id,
        source: tx.source ?? null,
        notes: tx.notes ?? null,
        currentBudgetCategoryId: tx.budgetCategoryId ?? null,
      });
    }
  }

  for (const target of projectTargets.values()) {
    const existingMarkerIds = markerIdsByProjectId.get(target.projectId) ?? new Set();
    const ref = db.doc(`accounts/${ACCOUNT_ID}/projects/${target.projectId}/budgetCategories/${target.targetId}`);
    if (existingMarkerIds.has(target.targetId)) {
      console.log(JSON.stringify({
        mode: COMMIT ? 'commit' : 'dry-run',
        action: 'project-category-exists',
        accountId: ACCOUNT_ID,
        projectId: target.projectId,
        categoryName: target.targetName,
        path: ref.path,
        txExamples: target.txExamples,
      }));
      continue;
    }

    const data = {
      budgetCents: 0,
      updatedAt: FieldValue.serverTimestamp(),
    };
    console.log(JSON.stringify({
      mode: COMMIT ? 'commit' : 'dry-run',
      action: 'enable-project-category',
      accountId: ACCOUNT_ID,
      projectId: target.projectId,
      categoryName: target.targetName,
      path: ref.path,
      data: {
        budgetCents: 0,
        updatedAt: '(serverTimestamp)',
      },
      txExamples: target.txExamples,
    }));
    if (COMMIT) await ref.set(data, { merge: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
