#!/usr/bin/env node
/**
 * Download receipt attachments for specific transactions without printing
 * Firebase download tokens. Read-only against Firestore and Storage URLs.
 *
 * Required:
 *   LEDGER_ACCOUNT_ID=... GOOGLE_APPLICATION_CREDENTIALS=... \
 *     node scripts/export-transaction-receipt-attachments.mjs \
 *       --output /absolute/path --transaction TX_ID [--transaction TX_ID]
 */

import fs from 'node:fs';
import path from 'node:path';
import admin from 'firebase-admin';

const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const ACCOUNT_ID = process.env.LEDGER_ACCOUNT_ID;

function valuesForFlag(flag) {
  const values = [];
  for (let index = 0; index < process.argv.length; index += 1) {
    if (process.argv[index] === flag && process.argv[index + 1]) {
      values.push(process.argv[index + 1]);
    }
  }
  return values;
}

function oneValueForFlag(flag) {
  return valuesForFlag(flag)[0] ?? null;
}

function extensionFor(attachment, contentType) {
  const originalExtension = path.extname(attachment.fileName ?? '').toLowerCase();
  if (/^\.[a-z0-9]{1,8}$/.test(originalExtension)) return originalExtension;
  if (contentType.includes('pdf')) return '.pdf';
  if (contentType.includes('png')) return '.png';
  if (contentType.includes('webp')) return '.webp';
  if (contentType.includes('heic')) return '.heic';
  return '.jpg';
}

async function downloadAttachment(attachment) {
  if (attachment.url.startsWith('gs://')) {
    const storagePath = attachment.url.slice('gs://'.length);
    const separatorIndex = storagePath.indexOf('/');
    if (separatorIndex < 1 || separatorIndex === storagePath.length - 1) {
      throw new Error('Malformed Firebase Storage attachment URL.');
    }
    const bucketName = storagePath.slice(0, separatorIndex);
    const objectName = storagePath.slice(separatorIndex + 1);
    const file = admin.storage().bucket(bucketName).file(objectName);
    const [[bytes], [metadata]] = await Promise.all([
      file.download(),
      file.getMetadata(),
    ]);
    return {
      bytes,
      contentType: metadata.contentType || attachment.contentType || '',
    };
  }

  const response = await fetch(attachment.url);
  if (!response.ok) {
    throw new Error(`Could not download attachment: HTTP ${response.status}`);
  }
  return {
    bytes: Buffer.from(await response.arrayBuffer()),
    contentType: response.headers.get('content-type') || attachment.contentType || '',
  };
}

if (!ACCOUNT_ID) throw new Error('LEDGER_ACCOUNT_ID is required.');
const outputDir = oneValueForFlag('--output');
const transactionIds = [...new Set(valuesForFlag('--transaction'))];
if (!outputDir || !path.isAbsolute(outputDir)) {
  throw new Error('--output must be an absolute directory path.');
}
if (transactionIds.length === 0) {
  throw new Error('At least one --transaction ID is required.');
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: FIREBASE_PROJECT_ID,
});
const db = admin.firestore();

async function main() {
  fs.mkdirSync(outputDir, { recursive: true });
  const manifest = {
    generatedAt: new Date().toISOString(),
    accountId: ACCOUNT_ID,
    transactions: [],
  };

  for (const transactionId of transactionIds) {
    const snap = await db.doc(`accounts/${ACCOUNT_ID}/transactions/${transactionId}`).get();
    if (!snap.exists) throw new Error(`Transaction ${transactionId} does not exist.`);
    const data = snap.data() ?? {};
    const attachments = [
      ...(Array.isArray(data.receiptImages) ? data.receiptImages : []),
      ...(Array.isArray(data.transactionImages) ? data.transactionImages : []),
    ];
    const transactionManifest = {
      transactionId,
      source: data.source ?? null,
      transactionDate: data.transactionDate ?? null,
      files: [],
    };

    for (let index = 0; index < attachments.length; index += 1) {
      const attachment = attachments[index];
      if (!attachment?.url) continue;
      const { bytes, contentType } = await downloadAttachment(attachment);
      const extension = extensionFor(attachment, contentType);
      const fileName = `${transactionId}-${String(index + 1).padStart(2, '0')}${extension}`;
      fs.writeFileSync(path.join(outputDir, fileName), bytes);
      transactionManifest.files.push({
        fileName,
        sourceFileName: attachment.fileName ?? null,
        contentType: contentType || null,
        byteCount: bytes.length,
      });
    }
    manifest.transactions.push(transactionManifest);
  }

  const manifestPath = path.join(outputDir, 'manifest.json');
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(JSON.stringify({
    outputDir,
    transactionCount: manifest.transactions.length,
    fileCount: manifest.transactions.reduce((sum, transaction) => sum + transaction.files.length, 0),
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
