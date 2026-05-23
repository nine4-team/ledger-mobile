#!/usr/bin/env node
/**
 * Collect candidate item-tag images for local OCR/barcode evaluation.
 *
 * Downloads images from item attachment refs into tmp/item-tag-fixtures and
 * writes a manifest for manual review. This is read-only against Firestore.
 *
 * Usage:
 *   node scripts/collect-item-tag-fixtures.mjs
 *   node scripts/collect-item-tag-fixtures.mjs --account <accountId>
 *   node scripts/collect-item-tag-fixtures.mjs --account-name "1584 Design" --max-items 300
 *
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS (service account JSON) or ADC.
 */

import admin from 'firebase-admin';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const STORAGE_BUCKET = process.env.FIREBASE_STORAGE_BUCKET || `${PROJECT_ID}.firebasestorage.app`;
const DEFAULT_ACCOUNT_ID = process.env.LEDGER_ACCOUNT_ID || '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
const DEFAULT_ACCOUNT_NAME = process.env.LEDGER_ACCOUNT_NAME || '1584 Design';
const OUT_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'tmp', 'item-tag-fixtures');
const DEFAULT_VENDORS = [
  'HomeGoods',
  'Home Goods',
  'Ross',
  'Hobby Lobby',
  'At Home',
  'TJ Maxx',
  'T.J. Maxx',
  'Marshalls',
];

function parseArgs(argv) {
  const args = {
    account: DEFAULT_ACCOUNT_ID,
    accountName: DEFAULT_ACCOUNT_NAME,
    outDir: OUT_DIR,
    maxItems: 300,
    maxImages: 600,
    vendors: DEFAULT_VENDORS,
    requireSku: false,
    dryRun: false,
    help: false,
  };

  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--account') args.account = argv[++i];
    else if (arg === '--account-name') args.accountName = argv[++i];
    else if (arg === '--out') args.outDir = argv[++i];
    else if (arg === '--max-items') args.maxItems = Number(argv[++i]);
    else if (arg === '--max-images') args.maxImages = Number(argv[++i]);
    else if (arg === '--vendor') args.vendors.push(argv[++i]);
    else if (arg === '--vendors') args.vendors = argv[++i].split(',').map(v => v.trim()).filter(Boolean);
    else if (arg === '--require-sku') args.requireSku = true;
    else if (arg === '--dry-run') args.dryRun = true;
    else if (arg === '--help' || arg === '-h') args.help = true;
    else {
      console.error(`Unknown arg: ${arg}`);
      process.exit(2);
    }
  }

  return args;
}

function printHelp() {
  console.log(`
Collect candidate item-tag images.

Options:
  --account <id>          Account id. Defaults to LEDGER_ACCOUNT_ID or 1584 account id.
  --account-name <name>   Account name fallback if --account is absent.
  --out <dir>             Output directory. Defaults to tmp/item-tag-fixtures.
  --max-items <n>         Max matching items to process. Default: 300.
  --max-images <n>        Max images to download. Default: 600.
  --vendors <csv>         Replace vendor list.
  --vendor <name>         Add one vendor to the list.
  --require-sku           Only collect items with an existing SKU ground truth.
  --dry-run               Write manifest only; do not download image bytes.
`);
}

function log(message) {
  console.log(`\x1b[36m[item-tags]\x1b[0m ${message}`);
}

function warn(message) {
  console.warn(`\x1b[33m[item-tags]\x1b[0m ${message}`);
}

function initFirestore() {
  if (admin.apps.length) return admin.firestore();
  const emulator = process.env.FIRESTORE_EMULATOR_HOST;
  if (emulator) {
    log(`Connecting to Firestore emulator at ${emulator}`);
    admin.initializeApp({ projectId: PROJECT_ID });
  } else {
    log(`Connecting to production Firestore (project=${PROJECT_ID})`);
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: PROJECT_ID,
      storageBucket: STORAGE_BUCKET,
    });
  }
  return admin.firestore();
}

async function resolveAccountId(db, args) {
  if (args.account) {
    const snap = await db.doc(`accounts/${args.account}`).get();
    if (snap.exists) return args.account;
    warn(`Account ${args.account} not found; trying account name "${args.accountName}"`);
  }

  const byName = await db.collection('accounts').where('name', '==', args.accountName).limit(2).get();
  if (byName.empty) throw new Error(`No account found for name "${args.accountName}"`);
  if (byName.size > 1) warn(`Multiple accounts named "${args.accountName}"; using first`);
  return byName.docs[0].id;
}

function vendorKey(vendor) {
  return vendor.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'unknown';
}

function normalized(text) {
  return String(text ?? '').toLowerCase();
}

function matchingVendor(item, vendors) {
  const haystack = [item.source, item.currentSource, item.notes, item.name, item.description]
    .map(normalized)
    .join('\n');
  return vendors.find(vendor => haystack.includes(normalized(vendor))) ?? null;
}

function imageAttachments(item) {
  return (item.images ?? [])
    .filter(ref => ref && (!ref.kind || ref.kind === 'image') && typeof ref.url === 'string' && ref.url.length > 0);
}

function extensionFor(ref, url) {
  const fromName = extname(ref.fileName ?? '').toLowerCase();
  if (fromName) return fromName;
  const fromUrl = extname(new URL(url).pathname).toLowerCase();
  if (['.jpg', '.jpeg', '.png', '.heic', '.webp'].includes(fromUrl)) return fromUrl;
  const contentType = ref.contentType ?? '';
  if (contentType.includes('png')) return '.png';
  if (contentType.includes('heic')) return '.heic';
  if (contentType.includes('webp')) return '.webp';
  return '.jpg';
}

function safeName(value) {
  return String(value ?? '')
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 80) || 'untitled';
}

async function download(sourceUrl, destinationPath) {
  if (sourceUrl.startsWith('gs://')) {
    const { bucketName, objectPath } = parseGsUrl(sourceUrl);
    await admin.storage().bucket(bucketName).file(objectPath).download({ destination: destinationPath });
    return null;
  }

  const response = await fetch(sourceUrl);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  writeFileSync(destinationPath, bytes);
  return bytes.length;
}

function parseGsUrl(sourceUrl) {
  const withoutScheme = sourceUrl.slice('gs://'.length);
  const slashIndex = withoutScheme.indexOf('/');
  if (slashIndex === -1) throw new Error(`Invalid gs:// URL: ${sourceUrl}`);
  return {
    bucketName: withoutScheme.slice(0, slashIndex),
    objectPath: withoutScheme.slice(slashIndex + 1),
  };
}

async function loadProjectNames(db, accountId) {
  const snap = await db.collection(`accounts/${accountId}/projects`).get();
  const names = new Map();
  for (const doc of snap.docs) {
    names.set(doc.id, doc.data().name ?? doc.id);
  }
  return names;
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    printHelp();
    return;
  }

  const db = initFirestore();
  const accountId = await resolveAccountId(db, args);
  const accountSnap = await db.doc(`accounts/${accountId}`).get();
  const account = accountSnap.data() ?? {};
  log(`Using account ${account.name ?? accountId} (${accountId})`);
  log(`Vendors: ${args.vendors.join(', ')}`);

  mkdirSync(args.outDir, { recursive: true });
  const projectNames = await loadProjectNames(db, accountId);

  const itemSnap = await db.collection(`accounts/${accountId}/items`).get();
  const candidates = [];

  for (const doc of itemSnap.docs) {
    const item = doc.data();
    const vendor = matchingVendor(item, args.vendors);
    const attachments = imageAttachments(item);
    const sku = String(item.sku ?? '').trim();
    if (!vendor || attachments.length === 0) continue;
    if (args.requireSku && !sku) continue;
    candidates.push({ id: doc.id, item, vendor, attachments, sku });
  }

  candidates.sort((a, b) => {
    const skuDelta = Number(Boolean(b.sku)) - Number(Boolean(a.sku));
    if (skuDelta !== 0) return skuDelta;
    return a.vendor.localeCompare(b.vendor) || a.id.localeCompare(b.id);
  });

  const selected = candidates.slice(0, args.maxItems);
  const manifest = {
    generatedAt: new Date().toISOString(),
    accountId,
    accountName: account.name ?? null,
    vendors: args.vendors,
    totalItemsScanned: itemSnap.size,
    totalCandidateItems: candidates.length,
    maxItems: args.maxItems,
    maxImages: args.maxImages,
    dryRun: args.dryRun,
    images: [],
    downloadErrors: [],
  };

  let imageCount = 0;
  for (const candidate of selected) {
    if (imageCount >= args.maxImages) break;

    const projectId = candidate.item.projectId ?? null;
    const vendorDir = vendorKey(candidate.vendor);
    const itemDir = safeName(`${candidate.id}-${candidate.item.name ?? candidate.item.description ?? 'item'}`);
    const relativeDir = join(vendorDir, itemDir);
    const absoluteDir = join(args.outDir, relativeDir);
    mkdirSync(absoluteDir, { recursive: true });

    for (const [index, attachment] of candidate.attachments.entries()) {
      if (imageCount >= args.maxImages) break;
      const ext = extensionFor(attachment, attachment.url);
      const fileName = `image-${String(index + 1).padStart(2, '0')}${ext}`;
      const relativePath = join(relativeDir, fileName);
      const destinationPath = join(args.outDir, relativePath);

      let bytes = null;
      let downloadStatus = args.dryRun ? 'dry-run' : 'downloaded';
      if (!args.dryRun) {
        try {
          bytes = await download(attachment.url, destinationPath);
        } catch (error) {
          downloadStatus = 'failed';
          manifest.downloadErrors.push({
            itemId: candidate.id,
            imageIndex: index,
            url: attachment.url,
            error: error.message,
          });
          warn(`Failed ${candidate.id} image ${index + 1}: ${error.message}`);
        }
      }

      manifest.images.push({
        itemId: candidate.id,
        itemName: candidate.item.name ?? candidate.item.description ?? null,
        vendor: candidate.vendor,
        source: candidate.item.source ?? null,
        currentSource: candidate.item.currentSource ?? null,
        expectedSku: candidate.sku || null,
        projectId,
        projectName: projectId ? projectNames.get(projectId) ?? null : null,
        imageIndex: index,
        isPrimary: attachment.isPrimary ?? null,
        contentType: attachment.contentType ?? null,
        fileName: attachment.fileName ?? null,
        localPath: relativePath,
        sourceUrl: attachment.url,
        downloadStatus,
        bytes,
        review: {
          tagVisible: null,
          expectedSkuFromImage: null,
          notes: null,
        },
      });
      imageCount++;
    }
  }

  const manifestPath = join(args.outDir, 'manifest.json');
  const reviewCsvPath = join(args.outDir, 'review.csv');
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
  writeFileSync(reviewCsvPath, toCsv(manifest.images));

  log(`Scanned ${itemSnap.size} items; matched ${candidates.length}; wrote ${manifest.images.length} image rows`);
  log(`Manifest: ${manifestPath}`);
  log(`Review CSV: ${reviewCsvPath}`);
  if (manifest.downloadErrors.length) warn(`Download errors: ${manifest.downloadErrors.length}`);
}

function csvValue(value) {
  const text = value == null ? '' : String(value);
  return `"${text.replaceAll('"', '""')}"`;
}

function toCsv(rows) {
  const headers = [
    'vendor',
    'expectedSku',
    'itemName',
    'projectName',
    'localPath',
    'tagVisible',
    'expectedSkuFromImage',
    'notes',
    'itemId',
    'sourceUrl',
  ];
  const lines = [headers.join(',')];
  for (const row of rows) {
    lines.push([
      row.vendor,
      row.expectedSku,
      row.itemName,
      row.projectName,
      row.localPath,
      '',
      '',
      '',
      row.itemId,
      row.sourceUrl,
    ].map(csvValue).join(','));
  }
  return `${lines.join('\n')}\n`;
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
