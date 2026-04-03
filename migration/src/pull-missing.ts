#!/usr/bin/env tsx
/**
 * Pull full Supabase records for missing transactions and items
 * identified by the parity audit. Outputs MCP-ready JSON.
 */

import { readFileSync, existsSync } from 'node:fs';
import { writeFile, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

// Load env from project root
const root = resolve(import.meta.dirname, '../..');
for (const envFile of ['.env.local', '.env']) {
  const p = join(root, envFile);
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

const ACCOUNT_ID = '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';

// Projects to migrate
const PROJECTS = {
  '5abd46c9-9886-4b3e-b2b1-19f6cf995a44': "Witzenman's 2nd Home",
  'fc4e8569-75f6-46b4-97ae-c4bc57f615d0': 'Sandra- BAHAMA Unit',
};

// Missing transaction IDs from parity audit (domain IDs or UUIDs used as doc IDs)
const MISSING_TX_DOC_IDS = [
  // Witzenman
  '56dd193b-2d19-471b-911c-44a4f7e5e3b0',
  '6492c330-73b6-4c82-a2be-dadfe3a63731',
  '5f89661c-9878-482e-96f0-5df7c57edd3c',
  '82273b13-c99c-4c4a-b8b7-b5a8dc087266',
  '039dce48-7ff6-4b67-a2f8-51ae794e189f',
  'e4364732-4f3c-4ff9-9561-7c75e89df3e5',
  '9fd15a13-2df3-46ad-b86e-7bf80b7f2ca5',
  '5a86c742-7a3b-4061-b4e1-f15023bd8992',
  '570020e2-8dab-4271-9db3-24e2bcdcdc61',
  '9404492c-d2f0-4133-817f-465d825cd47c',
  '9efb8265-2f25-4e92-8f34-7a474e18c9e6',
  '565283b5-5ddf-40c5-971f-936641dfb2b8',
  'fb71ae72-2f70-490c-aa78-92b6f0d4fbe9',
  'd53f45bf-d29d-402e-9b96-bf880c81f923',
  'bd50641b-74ac-409b-bdb9-9d694066a6bb',
  '723d9f70-d8f8-4d7a-afe3-8cb0ae6389ad',
  '59318e00-7782-4925-8aef-c22c9bcd5849',
  // Sandra-BAHAMA
  '5f89661c-9878-482e-96f0-5df7c57edd3c',
  '82273b13-c99c-4c4a-b8b7-b5a8dc087266',
  '039dce48-7ff6-4b67-a2f8-51ae794e189f',
  '5a86c742-7a3b-4061-b4e1-f15023bd8992',
  '570020e2-8dab-4271-9db3-24e2bcdcdc61',
  '565283b5-5ddf-40c5-971f-936641dfb2b8',
];

// Missing item doc IDs from parity audit
const MISSING_ITEM_DOC_IDS = [
  // Witzenman
  'I-1774472750816-olw0',
  // Sandra-BAHAMA
  'I-1774389806960-cyad',
  'I-1774389835114-egeo',
  'I-1774389835410-orc3',
  'I-1774389835763-ikyv',
  'I-1774389836053-98mi',
  'I-1774389836359-ykim',
];

function dollarsToCents(amount: string | null): number | null {
  if (!amount) return null;
  const n = parseFloat(amount);
  if (isNaN(n)) return null;
  return Math.round(n * 100);
}

async function main() {
  const sb = createClient(process.env.VITE_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
    auth: { persistSession: false },
  });

  // Fetch all transactions for the account in the target projects
  const projectIds = Object.keys(PROJECTS);
  const { data: allTxs, error: txErr } = await sb
    .from('transactions')
    .select('*')
    .eq('account_id', ACCOUNT_ID)
    .in('project_id', projectIds);

  if (txErr) throw new Error(`Failed reading transactions: ${txErr.message}`);

  // Build lookup by transaction_id (domain ID) and by id (row UUID)
  const txByDocId = new Map<string, typeof allTxs[0]>();
  for (const tx of allTxs) {
    if (tx.transaction_id) txByDocId.set(tx.transaction_id, tx);
    txByDocId.set(tx.id, tx);
  }

  // Fetch all items for the account in the target projects
  const { data: allItems, error: itemErr } = await sb
    .from('items')
    .select('*')
    .eq('account_id', ACCOUNT_ID)
    .in('project_id', projectIds);

  if (itemErr) throw new Error(`Failed reading items: ${itemErr.message}`);

  const itemByDocId = new Map<string, typeof allItems[0]>();
  for (const item of allItems) {
    if (item.item_id) itemByDocId.set(item.item_id, item);
    itemByDocId.set(item.id, item);
  }

  // Resolve missing transactions
  const uniqueTxIds = [...new Set(MISSING_TX_DOC_IDS)];
  const missingTxs = [];
  for (const docId of uniqueTxIds) {
    const tx = txByDocId.get(docId);
    if (!tx) {
      console.warn(`  WARNING: transaction ${docId} not found in Supabase`);
      continue;
    }
    missingTxs.push({
      supabaseRowId: tx.id,
      docId: tx.transaction_id ?? tx.id,
      projectId: tx.project_id,
      projectName: PROJECTS[tx.project_id as keyof typeof PROJECTS] ?? 'unknown',
      amountCents: dollarsToCents(tx.amount),
      subtotalCents: dollarsToCents(tx.subtotal),
      taxRatePct: tx.tax_rate_pct,
      type: tx.transaction_type ?? 'Purchase',
      source: tx.source,
      transactionDate: tx.transaction_date,
      notes: tx.notes,
      status: tx.status ?? 'completed',
      paymentMethod: tx.payment_method,
      reimbursementType: tx.reimbursement_type,
      receiptEmailed: tx.receipt_emailed,
      categoryId: tx.category_id,
      itemIds: tx.item_ids ?? [],
      receiptImages: tx.receipt_images ?? [],
      otherImages: tx.other_images ?? [],
      createdAt: tx.created_at,
    });
  }

  // Resolve missing items
  const uniqueItemIds = [...new Set(MISSING_ITEM_DOC_IDS)];
  const missingItems = [];
  for (const docId of uniqueItemIds) {
    const item = itemByDocId.get(docId);
    if (!item) {
      console.warn(`  WARNING: item ${docId} not found in Supabase`);
      continue;
    }
    missingItems.push({
      supabaseRowId: item.id,
      docId: item.item_id ?? item.id,
      projectId: item.project_id,
      projectName: PROJECTS[item.project_id as keyof typeof PROJECTS] ?? 'unknown',
      name: item.name,
      description: item.description,
      purchasePriceCents: dollarsToCents(item.purchase_price),
      projectPriceCents: dollarsToCents(item.project_price),
      marketValueCents: dollarsToCents(item.market_value),
      status: item.disposition ?? 'purchased',
      source: item.source,
      sku: item.sku,
      notes: item.notes,
      spaceId: item.space_id,
      categoryId: item.category_id,
      taxRatePct: item.tax_rate_pct,
      bookmark: item.bookmark,
      images: item.images ?? [],
      createdAt: item.created_at,
    });
  }

  // Output
  const output = {
    meta: {
      accountId: ACCOUNT_ID,
      pulledAt: new Date().toISOString(),
    },
    transactions: missingTxs,
    items: missingItems,
  };

  console.log(`\nFound ${missingTxs.length} transactions and ${missingItems.length} items\n`);

  // Group by project for readability
  for (const projId of projectIds) {
    const name = PROJECTS[projId as keyof typeof PROJECTS];
    const txs = missingTxs.filter(t => t.projectId === projId);
    const items = missingItems.filter(i => i.projectId === projId);
    console.log(`${name}:`);
    console.log(`  ${txs.length} transactions, ${items.length} items`);
    for (const tx of txs) {
      const imgs = tx.receiptImages.length + tx.otherImages.length;
      console.log(`    tx: ${tx.source} $${(tx.amountCents! / 100).toFixed(2)} ${tx.type} ${tx.transactionDate} (${imgs} images) cat:${tx.categoryId}`);
    }
    for (const item of items) {
      const imgs = item.images.length;
      console.log(`    item: ${item.name ?? item.docId} $${((item.purchasePriceCents ?? 0) / 100).toFixed(2)} ${item.status} (${imgs} images)`);
    }
    console.log('');
  }

  const outDir = join('migration', 'out', ACCOUNT_ID);
  await mkdir(outDir, { recursive: true });
  const outPath = join(outDir, 'missing-records.json');
  await writeFile(outPath, JSON.stringify(output, null, 2));
  console.log(`Written to ${outPath}`);
}

main().catch((err) => {
  console.error('Failed:', err);
  process.exit(1);
});
