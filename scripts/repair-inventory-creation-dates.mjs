#!/usr/bin/env node
// Dry run: node scripts/repair-inventory-creation-dates.mjs --account ACCOUNT_ID
// Add --active-projects to include items in non-archived projects.
// Add --apply to restore missing dates from Firestore document creation metadata.
import admin from 'firebase-admin';
import { mkdir, writeFile } from 'node:fs/promises';

const accountIndex = process.argv.indexOf('--account');
const accountId = accountIndex >= 0 ? process.argv[accountIndex + 1] : null;
if (!accountId || accountId.startsWith('--') || accountId.includes('/')) {
  throw new Error('Provide --account ACCOUNT_ID');
}
if (process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Remove FIRESTORE_EMULATOR_HOST for this production repair.');
admin.initializeApp({ projectId: process.env.FIREBASE_PROJECT_ID || 'ledger-nine4' });
const db = admin.firestore();
const snapshot = await db.collection(`accounts/${accountId}/items`).get();
const projects = await db.collection(`accounts/${accountId}/projects`).get();
const activeProjects = new Map(projects.docs.filter(doc => doc.get('isArchived') !== true).map(doc => [doc.id, doc.get('name')]));
const inScope = doc => doc.get('projectId') == null || (process.argv.includes('--active-projects') && activeProjects.has(doc.get('projectId')));
const scoped = snapshot.docs.filter(inScope);
const summaries = new Map([['inventory', { name: 'Business Inventory', total: 0, missing: 0, invalid: 0 }]]);
if (process.argv.includes('--active-projects')) {
  for (const [id, name] of activeProjects) summaries.set(id, { name, total: 0, missing: 0, invalid: 0 });
}
for (const doc of scoped) {
  const summary = summaries.get(doc.get('projectId') ?? 'inventory');
  summary.total++;
  if (doc.get('createdAt') == null) summary.missing++;
  else if (!(doc.get('createdAt') instanceof admin.firestore.Timestamp)) summary.invalid++;
}
const targets = scoped.filter(doc => doc.get('createdAt') == null);
const report = targets.map(doc => ({
  path: doc.ref.path,
  name: doc.get('name') ?? doc.get('description') ?? '',
  projectId: doc.get('projectId') ?? null,
  hadCreatedAt: Object.hasOwn(doc.data(), 'createdAt'),
  originalCreatedAt: doc.get('createdAt') ?? null,
  restoredCreatedAt: doc.createTime.toDate().toISOString(),
}));
const audit = { accountId, scopes: Object.fromEntries(summaries), missingDates: targets.length, items: report };
const directory = new URL('./migration-logs/', import.meta.url);
await mkdir(directory, { recursive: true });
const reportPath = new URL(`item-creation-dates-${Date.now()}.json`, directory);
await writeFile(reportPath, JSON.stringify(audit, null, 2));
console.log(JSON.stringify({ accountId, scopes: audit.scopes, missingDates: targets.length, reportPath: reportPath.pathname }, null, 2));
if (process.argv.includes('--apply') && targets.length) {
  for (let offset = 0; offset < targets.length; offset += 400) {
    const batch = db.batch();
    for (const doc of targets.slice(offset, offset + 400)) {
      // Fail safely if an item changes after the audit. Never replace an existing date.
      batch.update(doc.ref, { createdAt: doc.createTime }, { lastUpdateTime: doc.updateTime });
    }
    await batch.commit();
  }
  const repaired = await db.getAll(...targets.map(doc => doc.ref));
  if (repaired.some((doc, index) => !doc.get('createdAt')?.isEqual(targets[index].createTime))) {
    throw new Error('Creation date verification failed');
  }
  console.log(`Verified ${repaired.length} restored creation dates.`);
}
