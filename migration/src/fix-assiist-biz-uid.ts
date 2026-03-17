#!/usr/bin/env tsx
/**
 * One-off fix: ensure team@nine4.co has a user doc in every account.
 *
 * The migration wrote user docs keyed by Supabase UIDs with Supabase emails.
 * The team@nine4.co Google Sign-In user needs a membership doc in Assiist Biz
 * so the collectionGroup("users").whereField("uid", ...) query discovers it.
 *
 * Usage:
 *   npx tsx migration/src/fix-assiist-biz-uid.ts [--dry-run] [--target production|emulator]
 */

import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

// Load .env.local and .env
for (const envFile of ['.env.local', '.env']) {
  const envFilePath = resolve(process.cwd(), envFile);
  if (!existsSync(envFilePath)) continue;
  const lines = readFileSync(envFilePath, 'utf8').split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim().replace(/^["']|["']$/g, '');
    if (!(key in process.env)) process.env[key] = value;
  }
}

import admin from 'firebase-admin';
import { initFirestore, type WriteTarget } from './firestore-writer.js';

const EMAIL = 'team@nine4.co';

const ACCOUNT_IDS = [
  '2d612868-852e-4a80-9d02-9d10383898d4', // Assiist Biz
  '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94', // 1584 Design
];

function parseArgs(argv: string[]) {
  const args = argv.slice(2);
  const flags = new Set(args.filter(a => a.startsWith('--')).map(a => a.slice(2)));
  const targetIdx = args.indexOf('--target');
  const target: WriteTarget = targetIdx !== -1 && args[targetIdx + 1] === 'production'
    ? 'production' : 'emulator';
  return { dryRun: flags.has('dry-run'), target };
}

async function main() {
  const { dryRun, target } = parseArgs(process.argv);
  const projectId = process.env.FIREBASE_PROJECT_ID ?? 'ledger-nine4';

  if (target === 'emulator') {
    process.env.FIRESTORE_EMULATOR_HOST ??= 'localhost:8181';
    process.env.FIREBASE_AUTH_EMULATOR_HOST ??= 'localhost:9099';
  }

  const db = initFirestore(target, projectId);

  console.log(`\n=== Fix User Doc UIDs ===`);
  console.log(`Target: ${target}${dryRun ? ' (dry-run)' : ''}`);

  // 1. Look up Firebase Auth UID for team@nine4.co
  console.log(`\n1. Looking up Firebase Auth UID for ${EMAIL}...`);
  let firebaseUid: string;
  let displayName: string | undefined;
  try {
    const userRecord = await admin.auth().getUserByEmail(EMAIL);
    firebaseUid = userRecord.uid;
    displayName = userRecord.displayName;
    console.log(`   UID: ${firebaseUid}`);
    console.log(`   Name: ${displayName ?? '(none)'}`);
  } catch (err) {
    console.error(`   Failed:`, err instanceof Error ? err.message : err);
    process.exit(1);
  }

  // 2. For each account, ensure a user doc exists at users/{firebaseUid}
  for (const accountId of ACCOUNT_IDS) {
    const basePath = `accounts/${accountId}/users`;
    const docRef = db.doc(`${basePath}/${firebaseUid}`);

    console.log(`\n--- Account: ${accountId} ---`);

    const snap = await docRef.get();
    if (snap.exists) {
      const data = snap.data()!;
      console.log(`   ✓ User doc already exists (role=${data.role}, email=${data.email})`);
      continue;
    }

    console.log(`   ✗ No user doc at ${docRef.path}`);
    console.log(`   Creating owner membership for ${EMAIL}...`);

    const now = new Date().toISOString();
    const userData = {
      id: firebaseUid,
      accountId,
      uid: firebaseUid,
      role: 'owner',
      email: EMAIL,
      name: displayName ?? null,
      isDisabled: false,
      createdAt: now,
      updatedAt: now,
      createdBy: firebaseUid,
      updatedBy: firebaseUid,
    };

    if (dryRun) {
      console.log(`   [dry-run] Would create ${docRef.path}:`);
      console.log(`   ${JSON.stringify(userData, null, 2).split('\n').join('\n   ')}`);
    } else {
      await docRef.set(userData);
      console.log(`   Created ${docRef.path}`);
    }
  }

  console.log(`\n=== Done ===\n`);
}

main().catch((err) => {
  console.error('Fix failed:', err);
  process.exit(1);
});
