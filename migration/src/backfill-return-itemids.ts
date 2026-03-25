#!/usr/bin/env tsx
/**
 * Backfill: Fix orphaned itemIds for items moved to return transactions
 *
 * The ReturnTransactionPickerModal used a raw updateItem(transactionId) call
 * that skipped itemIds array management. This script finds items that:
 *   - Have transactionId pointing to a return-type transaction
 *   - Are NOT in that return transaction's itemIds
 *   - Are still in another transaction's itemIds (the source)
 *
 * Fixes: arrayRemove from source, arrayUnion to return transaction.
 *
 * Usage:
 *   npx tsx migration/src/backfill-return-itemids.ts --account <UUID> --target emulator --dry-run
 *   npx tsx migration/src/backfill-return-itemids.ts --all --target production --dry-run
 */

import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

// Load .env.local and .env before anything else
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

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

interface Args {
  accountId?: string;
  all: boolean;
  target: WriteTarget;
  dryRun: boolean;
}

function parseArgs(argv: string[]): Args {
  const args: Args = { all: false, target: 'emulator', dryRun: true };

  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--account' && argv[i + 1]) {
      args.accountId = argv[++i];
    } else if (arg === '--all') {
      args.all = true;
    } else if (arg === '--target' && argv[i + 1]) {
      args.target = argv[++i] as WriteTarget;
    } else if (arg === '--dry-run') {
      args.dryRun = true;
    } else if (arg === '--no-dry-run') {
      args.dryRun = false;
    }
  }

  if (!args.accountId && !args.all) {
    console.error('Error: provide --account <UUID> or --all');
    process.exit(1);
  }

  return args;
}

// ---------------------------------------------------------------------------
// Core logic
// ---------------------------------------------------------------------------

interface FixResult {
  itemsFixed: number;
  sourceTransactionsCleaned: number;
  returnTransactionsUpdated: number;
}

async function backfillAccount(
  db: admin.firestore.Firestore,
  accountId: string,
  dryRun: boolean
): Promise<FixResult> {
  const result: FixResult = {
    itemsFixed: 0,
    sourceTransactionsCleaned: 0,
    returnTransactionsUpdated: 0,
  };

  const txCol = db.collection(`accounts/${accountId}/transactions`);
  const itemCol = db.collection(`accounts/${accountId}/items`);

  // 1. Find all return-type transactions
  // Transaction type field can be "type" or "transactionType" (legacy)
  const allTxSnap = await txCol.get();
  const returnTxs: Array<{ id: string; itemIds: string[]; projectId?: string }> = [];

  for (const doc of allTxSnap.docs) {
    const data = doc.data();
    const rawType = (data.transactionType ?? data.type ?? '') as string;
    if (rawType.trim().toLowerCase() !== 'return') continue;
    returnTxs.push({
      id: doc.id,
      itemIds: (data.itemIds ?? []) as string[],
      projectId: data.projectId as string | undefined,
    });
  }

  if (returnTxs.length === 0) {
    console.log(`  [${accountId}] No return transactions found.`);
    return result;
  }
  console.log(`  [${accountId}] Found ${returnTxs.length} return transaction(s).`);

  // Build a lookup of all transaction itemIds for finding orphaned references
  const txItemIdsMap = new Map<string, string[]>();
  for (const doc of allTxSnap.docs) {
    const ids = (doc.data().itemIds ?? []) as string[];
    if (ids.length > 0) txItemIdsMap.set(doc.id, ids);
  }

  // 2. For each return transaction, find items that should be in it
  const writer = dryRun ? null : db.bulkWriter();

  for (const returnTx of returnTxs) {
    const returnItemIdSet = new Set(returnTx.itemIds);

    // Query items where transactionId == this return transaction
    const itemSnap = await itemCol
      .where('transactionId', '==', returnTx.id)
      .get();

    for (const itemDoc of itemSnap.docs) {
      const itemId = itemDoc.id;

      // Check if item is missing from the return transaction's itemIds
      if (returnItemIdSet.has(itemId)) continue; // Already correct

      // This item needs fixing
      result.itemsFixed++;
      console.log(`  [${accountId}] Fix: item ${itemId} → add to return tx ${returnTx.id}`);

      // Find source transactions that still have this item in their itemIds
      for (const [txId, ids] of txItemIdsMap) {
        if (txId === returnTx.id) continue;
        if (!ids.includes(itemId)) continue;

        result.sourceTransactionsCleaned++;
        console.log(`  [${accountId}]   Remove from source tx ${txId}`);

        if (writer) {
          writer.update(txCol.doc(txId), {
            itemIds: admin.firestore.FieldValue.arrayRemove(itemId),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      // Add to return transaction's itemIds
      if (writer) {
        writer.update(txCol.doc(returnTx.id), {
          itemIds: admin.firestore.FieldValue.arrayUnion(itemId),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      result.returnTransactionsUpdated++;
    }
  }

  if (writer) {
    await writer.close();
  }

  return result;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv);
  const projectId = process.env.FIREBASE_PROJECT_ID ?? 'ledger-nine4';
  const db = initFirestore(args.target, projectId);

  console.log(`\nBackfill: return transaction itemIds`);
  console.log(`Target: ${args.target}${args.dryRun ? ' (DRY RUN)' : ''}\n`);

  let accounts: string[];
  if (args.all) {
    // Discover all accounts
    const snap = await db.collection('accounts').get();
    accounts = snap.docs.map((d) => d.id);
    console.log(`Discovered ${accounts.length} account(s).\n`);
  } else {
    accounts = [args.accountId!];
  }

  let totalFixed = 0;
  let totalSourceCleaned = 0;
  let totalReturnUpdated = 0;

  for (const accountId of accounts) {
    try {
      const result = await backfillAccount(db, accountId, args.dryRun);
      totalFixed += result.itemsFixed;
      totalSourceCleaned += result.sourceTransactionsCleaned;
      totalReturnUpdated += result.returnTransactionsUpdated;
    } catch (err) {
      console.error(`  [${accountId}] ERROR: ${err}`);
    }
  }

  console.log(`\n--- Summary ---`);
  console.log(`Items fixed: ${totalFixed}`);
  console.log(`Source transactions cleaned: ${totalSourceCleaned}`);
  console.log(`Return transactions updated: ${totalReturnUpdated}`);
  if (args.dryRun) console.log(`(DRY RUN — no writes performed)`);
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
