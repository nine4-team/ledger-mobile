#!/usr/bin/env tsx
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
for (const envFile of ['.env.local', '.env']) {
  const p = resolve(process.cwd(), envFile);
  if (!existsSync(p)) continue;
  for (const line of readFileSync(p, 'utf8').split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq === -1) continue;
    const k = t.slice(0, eq).trim();
    const v = t.slice(eq + 1).trim().replace(/^["']|["']$/g, '');
    if (!(k in process.env)) process.env[k] = v;
  }
}
import admin from 'firebase-admin';
import { initFirestore } from './firestore-writer.js';

async function main() {
  const db = initFirestore('production', 'ledger-nine4');
  const uid = 'sHuIe2M85WVOf3yzC0t61s3l10e2';

  // Check specific doc
  console.log('=== Direct doc lookup ===');
  const snap = await db.doc(`accounts/2d612868-852e-4a80-9d02-9d10383898d4/users/${uid}`).get();
  console.log('Exists:', snap.exists);
  if (snap.exists) console.log('Data:', JSON.stringify(snap.data(), null, 2));

  // Run the same collectionGroup query the app uses
  console.log('\n=== collectionGroup query (uid = ' + uid + ') ===');
  const querySnap = await db.collectionGroup('users').where('uid', '==', uid).get();
  console.log(`Found ${querySnap.docs.length} doc(s):`);
  for (const doc of querySnap.docs) {
    console.log(`  ${doc.ref.path} → role=${doc.data().role}, email=${doc.data().email}`);
  }
}

main().catch(console.error);
