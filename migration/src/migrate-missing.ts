#!/usr/bin/env tsx
/**
 * Batch migrate missing transactions and items from Supabase to Firebase.
 *
 * Reads missing-records.json (output of pull-missing.ts) and:
 * 1. Creates transaction documents in Firestore
 * 2. Creates item documents in Firestore (with bidirectional transaction links)
 * 3. Downloads images from Supabase Storage and re-uploads to Firebase Storage
 *    (with sm/md thumbnails, same logic as MCP attach_transaction_file)
 *
 * Usage:
 *   npx tsx migration/src/migrate-missing.ts [--dry-run]
 */

import { readFileSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import admin from 'firebase-admin';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';

// ---------------------------------------------------------------------------
// Env loading
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const ACCOUNT_ID = '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
const PROJECT_ID = 'ledger-nine4';
const BUCKET_NAME = 'ledger-nine4.firebasestorage.app';
const DRY_RUN = process.argv.includes('--dry-run');

// ---------------------------------------------------------------------------
// Firebase init
// ---------------------------------------------------------------------------
admin.initializeApp({
  projectId: PROJECT_ID,
  credential: admin.credential.applicationDefault(),
  storageBucket: BUCKET_NAME,
});
const db = admin.firestore();
db.settings({ ignoreUndefinedProperties: true });
const bucket = admin.storage().bucket(BUCKET_NAME);
const FieldValue = admin.firestore.FieldValue;

function accountCol(collection: string) {
  return db.collection(`accounts/${ACCOUNT_ID}/${collection}`);
}

// ---------------------------------------------------------------------------
// Storage helpers (mirrors mcp-server/src/storage.ts)
// ---------------------------------------------------------------------------
async function uploadToStorage(path: string, data: Buffer, contentType: string): Promise<string> {
  const file = bucket.file(path);
  const token = randomUUID();
  await file.save(data, {
    metadata: { contentType, metadata: { firebaseStorageDownloadTokens: token } },
  });
  const encodedPath = encodeURIComponent(path);
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET_NAME}/o/${encodedPath}?alt=media&token=${token}`;
}

function thumbnailPath(originalPath: string, size: 'sm' | 'md'): string {
  const dotIdx = originalPath.lastIndexOf('.');
  const base = dotIdx > 0 ? originalPath.slice(0, dotIdx) : originalPath;
  return `${base}_${size}.jpg`;
}

async function generateThumbnails(data: Buffer, contentType: string) {
  if (!contentType.startsWith('image/')) return {};
  const [sm, md] = await Promise.all([
    sharp(data).resize(300, 300, { fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 100 }).toBuffer().catch(() => undefined),
    sharp(data).resize(800, 800, { fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 100 }).toBuffer().catch(() => undefined),
  ]);
  return { sm, md };
}

// ---------------------------------------------------------------------------
// Image migration (mirrors MCP attach_transaction_file / attach_item_image)
// ---------------------------------------------------------------------------
interface SupabaseImage {
  url: string;
  fileName: string;
  mimeType: string;
  size: number;
  alt?: string;
  isPrimary?: boolean;
}

async function migrateImage(
  entityType: 'transactions' | 'items',
  entityId: string,
  img: SupabaseImage,
  isPrimary: boolean,
): Promise<Record<string, unknown> | null> {
  try {
    const res = await fetch(img.url);
    if (!res.ok) {
      console.warn(`    WARN: failed to fetch ${img.url}: ${res.status}`);
      return null;
    }
    const data = Buffer.from(await res.arrayBuffer());
    const contentType = img.mimeType || 'application/octet-stream';
    // Extract just the filename part
    const parts = img.fileName.split('/');
    const shortName = parts[parts.length - 1];

    const storagePath = `accounts/${ACCOUNT_ID}/${entityType}/${entityId}/${shortName}`;
    const url = await uploadToStorage(storagePath, data, contentType);

    const entry: Record<string, unknown> = { url, kind: 'image', isPrimary };
    if (shortName) entry.fileName = shortName;
    if (contentType) entry.contentType = contentType;

    const thumbs = await generateThumbnails(data, contentType);
    if (thumbs.sm) {
      entry.thumbnailUrlSm = await uploadToStorage(thumbnailPath(storagePath, 'sm'), thumbs.sm, 'image/jpeg');
    }
    if (thumbs.md) {
      entry.thumbnailUrlMd = await uploadToStorage(thumbnailPath(storagePath, 'md'), thumbs.md, 'image/jpeg');
    }

    return entry;
  } catch (err) {
    console.warn(`    WARN: image migration failed for ${img.url}:`, err);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  const inputPath = join(root, 'migration/out', ACCOUNT_ID, 'missing-records.json');
  const data = JSON.parse(readFileSync(inputPath, 'utf8'));

  console.log(`\n=== Batch Migration ===`);
  console.log(`  Transactions: ${data.transactions.length}`);
  console.log(`  Items: ${data.items.length}`);
  console.log(`  Dry run: ${DRY_RUN}\n`);

  // Track new transaction IDs for item linking
  const txIdMap = new Map<string, string>(); // supabase docId → firebase docId

  // ── Create transactions ──────────────────────────────────────────────
  for (const tx of data.transactions) {
    console.log(`  Creating tx: ${tx.source} $${(tx.amountCents / 100).toFixed(2)} ${tx.type} ${tx.transactionDate}`);

    const doc: Record<string, unknown> = {
      budgetCategoryId: tx.categoryId,
      amountCents: tx.amountCents,
      type: tx.type,
      status: tx.status || 'completed',
      isCanceled: false,
      isComplete: false,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    if (tx.projectId) doc.projectId = tx.projectId;
    if (tx.source) doc.source = tx.source;
    if (tx.transactionDate) doc.transactionDate = tx.transactionDate;
    if (tx.notes) doc.notes = tx.notes;
    if (tx.subtotalCents != null) doc.subtotalCents = tx.subtotalCents;
    if (tx.taxRatePct != null && tx.taxRatePct !== 0) doc.taxRatePct = tx.taxRatePct;
    if (tx.paymentMethod) doc.paymentMethod = tx.paymentMethod;
    if (tx.receiptEmailed != null) doc.receiptEmailed = tx.receiptEmailed;
    // Map common purchasedBy values
    if (tx.paymentMethod === 'Client Card') doc.purchasedBy = 'client-card';

    if (DRY_RUN) {
      console.log(`    [dry-run] would create transaction`);
      txIdMap.set(tx.docId, `dry-run-${tx.docId}`);
      continue;
    }

    const ref = await accountCol('transactions').add(doc);
    txIdMap.set(tx.docId, ref.id);
    console.log(`    Created: ${ref.id}`);

    // Migrate receipt images
    const receiptEntries: Record<string, unknown>[] = [];
    for (let i = 0; i < tx.receiptImages.length; i++) {
      const img = tx.receiptImages[i];
      console.log(`    Uploading receipt image ${i + 1}/${tx.receiptImages.length}...`);
      const entry = await migrateImage('transactions', ref.id, img, i === 0);
      if (entry) receiptEntries.push(entry);
    }
    if (receiptEntries.length) {
      await accountCol('transactions').doc(ref.id).update({
        receiptImages: FieldValue.arrayUnion(...receiptEntries),
        updatedAt: new Date(),
      });
    }

    // Migrate other images
    const otherEntries: Record<string, unknown>[] = [];
    for (let i = 0; i < tx.otherImages.length; i++) {
      const img = tx.otherImages[i];
      console.log(`    Uploading other image ${i + 1}/${tx.otherImages.length}...`);
      const entry = await migrateImage('transactions', ref.id, img, false);
      if (entry) otherEntries.push(entry);
    }
    if (otherEntries.length) {
      await accountCol('transactions').doc(ref.id).update({
        otherImages: FieldValue.arrayUnion(...otherEntries),
        updatedAt: new Date(),
      });
    }
  }

  // ── Create items ─────────────────────────────────────────────────────
  for (const item of data.items) {
    const name = item.name || item.description || item.docId;
    console.log(`\n  Creating item: ${name} $${((item.purchasePriceCents ?? 0) / 100).toFixed(2)}`);

    // Find the transaction this item belongs to (from Supabase data)
    // We need to look through the transactions to find one whose itemIds includes this item's docId
    let firebaseTxId: string | undefined;
    for (const tx of data.transactions) {
      if (tx.itemIds?.includes(item.docId)) {
        firebaseTxId = txIdMap.get(tx.docId);
        break;
      }
    }

    const doc: Record<string, unknown> = {
      name,
      status: item.status || 'purchased',
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    if (item.projectId) doc.projectId = item.projectId;
    if (item.purchasePriceCents != null) doc.purchasePriceCents = item.purchasePriceCents;
    if (item.projectPriceCents != null) doc.projectPriceCents = item.projectPriceCents;
    if (item.source) doc.source = item.source;
    if (item.sku) doc.sku = item.sku;
    if (item.notes) doc.notes = item.notes;
    if (item.spaceId) doc.spaceId = item.spaceId;
    if (item.categoryId) doc.budgetCategoryId = item.categoryId;
    if (item.taxRatePct != null) doc.taxRatePct = item.taxRatePct;
    if (item.bookmark) doc.bookmark = item.bookmark;
    if (firebaseTxId) doc.transactionId = firebaseTxId;

    if (DRY_RUN) {
      console.log(`    [dry-run] would create item${firebaseTxId ? ` linked to tx ${firebaseTxId}` : ''}`);
      continue;
    }

    const ref = await accountCol('items').add(doc);
    console.log(`    Created: ${ref.id}${firebaseTxId ? ` (linked to tx ${firebaseTxId})` : ''}`);

    // Maintain bidirectional link: append item to transaction's itemIds
    if (firebaseTxId) {
      await accountCol('transactions').doc(firebaseTxId).update({
        itemIds: FieldValue.arrayUnion(ref.id),
        updatedAt: new Date(),
      });
    }

    // Migrate item images
    const imageEntries: Record<string, unknown>[] = [];
    for (let i = 0; i < item.images.length; i++) {
      const img = item.images[i];
      console.log(`    Uploading item image ${i + 1}/${item.images.length}...`);
      const entry = await migrateImage('items', ref.id, img, img.isPrimary ?? i === 0);
      if (entry) imageEntries.push(entry);
    }
    if (imageEntries.length) {
      await accountCol('items').doc(ref.id).update({
        images: FieldValue.arrayUnion(...imageEntries),
        updatedAt: new Date(),
      });
    }
  }

  console.log('\n=== Done ===');
  console.log(`  Transactions created: ${txIdMap.size}`);
  console.log(`  Items created: ${data.items.length}`);
}

main().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
