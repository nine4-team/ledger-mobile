#!/usr/bin/env tsx
/**
 * Attach images to already-created transactions and items.
 * Run after migrate-missing.ts when image uploads failed due to auth.
 *
 * Usage: npx tsx migration/src/migrate-images-only.ts
 */

import { readFileSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import admin from 'firebase-admin';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';

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
const PROJECT_ID = 'ledger-nine4';
const BUCKET_NAME = 'ledger-nine4.firebasestorage.app';

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

interface SupabaseImage {
  url: string;
  fileName: string;
  mimeType: string;
  size: number;
}

async function migrateImage(
  entityType: 'transactions' | 'items',
  entityId: string,
  img: SupabaseImage,
  isPrimary: boolean,
): Promise<Record<string, unknown> | null> {
  const res = await fetch(img.url);
  if (!res.ok) {
    console.warn(`    WARN: failed to fetch ${img.url}: ${res.status}`);
    return null;
  }
  const data = Buffer.from(await res.arrayBuffer());
  const contentType = img.mimeType || 'application/octet-stream';
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
}

// Maps from supabase docId → firebase docId
const TX_MAP: Record<string, string> = {
  '56dd193b-2d19-471b-911c-44a4f7e5e3b0': 'eYSXsVTAeghkD1kNCu78',
  '6492c330-73b6-4c82-a2be-dadfe3a63731': 'IdOCIoF3NQwn4RcX3j06',
  '5f89661c-9878-482e-96f0-5df7c57edd3c': 'xEjSxje2Gvka5XN11ZPn',
  '82273b13-c99c-4c4a-b8b7-b5a8dc087266': 'ocl6cJ1a7MiiJF0llK6j',
  '039dce48-7ff6-4b67-a2f8-51ae794e189f': 'WTmdG1Cqt5qySd8mLRSj',
  'e4364732-4f3c-4ff9-9561-7c75e89df3e5': 'TI5YXPwfocHJSw2lfmBi',
  '9fd15a13-2df3-46ad-b86e-7bf80b7f2ca5': 'o6gU3YFtgya9ueBMWnyr',
  '5a86c742-7a3b-4061-b4e1-f15023bd8992': 'OP9V10gxMnbC1FNqT9Ef',
  '570020e2-8dab-4271-9db3-24e2bcdcdc61': '66obnQxwKYUNexHN3d4Z',
  '9404492c-d2f0-4133-817f-465d825cd47c': 'vODyfJGKpFrU2W4b9jMo',
  '9efb8265-2f25-4e92-8f34-7a474e18c9e6': 'Ps6CwZBMx1IBcn3GkuFe',
  '565283b5-5ddf-40c5-971f-936641dfb2b8': 'YALCz1xF1LuPsPRlaASn',
  'fb71ae72-2f70-490c-aa78-92b6f0d4fbe9': 'CInhrKVY7TNg6dpsg3r2',
  'd53f45bf-d29d-402e-9b96-bf880c81f923': 'kWgB9xzo1g0ppnmDWNI7',
  'bd50641b-74ac-409b-bdb9-9d694066a6bb': 'LIRlybaM6vHaLm1QhAJH',
  '723d9f70-d8f8-4d7a-afe3-8cb0ae6389ad': 'DpILfefx3D9kgesbuvuB',
  '59318e00-7782-4925-8aef-c22c9bcd5849': 'jQ2eRbjxlmixUKyP04OP',
};

const ITEM_MAP: Record<string, string> = {
  'I-1774472750816-olw0': '9A5FF1nRTjmsHM3QjgaU',
  'I-1774389806960-cyad': 'mBuFurMBrrdbdydfbMlL',
  'I-1774389835114-egeo': '2tOn32m4xSF66q7PioGu',
  'I-1774389835410-orc3': 'Lv0xWRm9VWKbIBvBhXL1',
  'I-1774389835763-ikyv': 'NhOiCHzI9f4kwDrDVulC',
  'I-1774389836053-98mi': 'c3d8CKK2TWZxDUx4zVER',
  'I-1774389836359-ykim': 'vNfVcTmkjtjM6z1NUMC9',
};

async function main() {
  const inputPath = join(root, 'migration/out', ACCOUNT_ID, 'missing-records.json');
  const data = JSON.parse(readFileSync(inputPath, 'utf8'));

  let uploaded = 0;
  let failed = 0;

  // Transaction images
  for (const tx of data.transactions) {
    const fbId = TX_MAP[tx.docId];
    if (!fbId) { console.warn(`  No Firebase ID for tx ${tx.docId}`); continue; }

    // Check if images already attached
    const doc = await accountCol('transactions').doc(fbId).get();
    const existing = doc.data();
    const hasReceipts = existing?.receiptImages?.length > 0;
    const hasOther = existing?.otherImages?.length > 0;

    if (hasReceipts && hasOther) {
      console.log(`  Skipping tx ${fbId} (${tx.source}) — images already attached`);
      continue;
    }

    console.log(`  Attaching images to tx ${fbId} (${tx.source} $${(tx.amountCents / 100).toFixed(2)})`);

    if (!hasReceipts && tx.receiptImages.length) {
      const entries: Record<string, unknown>[] = [];
      for (let i = 0; i < tx.receiptImages.length; i++) {
        console.log(`    Receipt ${i + 1}/${tx.receiptImages.length}...`);
        try {
          const entry = await migrateImage('transactions', fbId, tx.receiptImages[i], i === 0);
          if (entry) { entries.push(entry); uploaded++; }
          else failed++;
        } catch (err) {
          console.warn(`    ERROR:`, (err as Error).message?.slice(0, 100));
          failed++;
        }
      }
      if (entries.length) {
        await accountCol('transactions').doc(fbId).update({
          receiptImages: FieldValue.arrayUnion(...entries),
          updatedAt: new Date(),
        });
      }
    }

    if (!hasOther && tx.otherImages.length) {
      const entries: Record<string, unknown>[] = [];
      for (let i = 0; i < tx.otherImages.length; i++) {
        console.log(`    Other ${i + 1}/${tx.otherImages.length}...`);
        try {
          const entry = await migrateImage('transactions', fbId, tx.otherImages[i], false);
          if (entry) { entries.push(entry); uploaded++; }
          else failed++;
        } catch (err) {
          console.warn(`    ERROR:`, (err as Error).message?.slice(0, 100));
          failed++;
        }
      }
      if (entries.length) {
        await accountCol('transactions').doc(fbId).update({
          otherImages: FieldValue.arrayUnion(...entries),
          updatedAt: new Date(),
        });
      }
    }
  }

  // Item images
  for (const item of data.items) {
    const fbId = ITEM_MAP[item.docId];
    if (!fbId) { console.warn(`  No Firebase ID for item ${item.docId}`); continue; }

    const doc = await accountCol('items').doc(fbId).get();
    const existing = doc.data();
    if (existing?.images?.length > 0) {
      console.log(`  Skipping item ${fbId} — images already attached`);
      continue;
    }

    const name = item.name || item.description || item.docId;
    console.log(`  Attaching images to item ${fbId} (${name})`);

    const entries: Record<string, unknown>[] = [];
    for (let i = 0; i < item.images.length; i++) {
      console.log(`    Image ${i + 1}/${item.images.length}...`);
      try {
        const entry = await migrateImage('items', fbId, item.images[i], item.images[i].isPrimary ?? i === 0);
        if (entry) { entries.push(entry); uploaded++; }
        else failed++;
      } catch (err) {
        console.warn(`    ERROR:`, (err as Error).message?.slice(0, 100));
        failed++;
      }
    }
    if (entries.length) {
      await accountCol('items').doc(fbId).update({
        images: FieldValue.arrayUnion(...entries),
        updatedAt: new Date(),
      });
    }
  }

  console.log(`\n=== Done ===`);
  console.log(`  Uploaded: ${uploaded}`);
  console.log(`  Failed: ${failed}`);
}

main().catch((err) => {
  console.error('Failed:', err);
  process.exit(1);
});
