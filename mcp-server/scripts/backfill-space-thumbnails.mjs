#!/usr/bin/env node
/**
 * Backfill missing sm/md thumbnail URLs for existing Space image attachments.
 *
 * Dry-run by default. Pass --commit to upload thumbnails and patch Firestore.
 *
 * Examples:
 *   node mcp-server/scripts/backfill-space-thumbnails.mjs --account <accountId>
 *   node mcp-server/scripts/backfill-space-thumbnails.mjs --account <accountId> --commit
 *   node mcp-server/scripts/backfill-space-thumbnails.mjs --account <accountId> --space <spaceId> --force --commit
 */

import admin from "firebase-admin";
import { getStorage } from "firebase-admin/storage";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const DEFAULT_PROJECT_ID = "ledger-nine4";
const DEFAULT_BUCKET = "ledger-nine4.firebasestorage.app";
const USAGE = `
Usage:
  node ${path.relative(process.cwd(), fileURLToPath(import.meta.url))} --account <accountId> [options]

Options:
  --account <id>       Account id containing the spaces collection. Required unless ACCOUNT_ID is set.
  --space <id>         Only backfill one space.
  --limit <n>          Stop after scanning n spaces.
  --commit             Upload thumbnails and patch Firestore. Default is dry-run.
  --force              Regenerate thumbnails even when thumbnail URLs already exist.
  --credentials <path> Service account JSON. Defaults to GOOGLE_APPLICATION_CREDENTIALS / ADC.
  --project <id>       Firebase project id. Defaults to FIREBASE_PROJECT_ID or ${DEFAULT_PROJECT_ID}.
  --bucket <name>      Storage bucket. Defaults to FIREBASE_STORAGE_BUCKET or ${DEFAULT_BUCKET}.
  --help               Show this help.
`;

function parseArgs(argv) {
  const options = {
    accountId: process.env.ACCOUNT_ID,
    bucket: process.env.FIREBASE_STORAGE_BUCKET || DEFAULT_BUCKET,
    commit: false,
    credentialsPath: process.env.GOOGLE_APPLICATION_CREDENTIALS,
    force: false,
    limit: undefined,
    projectId: process.env.FIREBASE_PROJECT_ID || DEFAULT_PROJECT_ID,
    spaceId: undefined,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = () => {
      const value = argv[++i];
      if (!value || value.startsWith("--")) {
        throw new Error(`${arg} requires a value`);
      }
      return value;
    };

    switch (arg) {
      case "--account":
        options.accountId = next();
        break;
      case "--bucket":
        options.bucket = next();
        break;
      case "--commit":
        options.commit = true;
        break;
      case "--credentials":
        options.credentialsPath = next();
        break;
      case "--force":
        options.force = true;
        break;
      case "--help":
        console.log(USAGE.trim());
        process.exit(0);
      case "--limit": {
        const value = Number.parseInt(next(), 10);
        if (!Number.isFinite(value) || value <= 0) throw new Error("--limit must be a positive integer");
        options.limit = value;
        break;
      }
      case "--project":
        options.projectId = next();
        break;
      case "--space":
        options.spaceId = next();
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }

  if (!options.accountId) {
    throw new Error("Missing --account <accountId> or ACCOUNT_ID");
  }

  return options;
}

function isUsageError(error) {
  return [
    "Missing --account",
    "Unknown option:",
    "--limit must be",
  ].some((prefix) => error.message.startsWith(prefix))
    || error.message.includes(" requires a value");
}

function initFirebase({ credentialsPath, projectId }) {
  if (admin.apps.length) return;

  if (credentialsPath) {
    const serviceAccount = JSON.parse(readFileSync(credentialsPath, "utf8"));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId,
    });
    return;
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId,
  });
}

function parseStoragePath(url) {
  if (!url || typeof url !== "string") return undefined;

  if (url.startsWith("gs://")) {
    const withoutScheme = url.slice("gs://".length);
    const slashIndex = withoutScheme.indexOf("/");
    return slashIndex >= 0 ? withoutScheme.slice(slashIndex + 1) : undefined;
  }

  const match = url.match(/\/o\/([^?]+)/);
  if (!match) return undefined;
  return decodeURIComponent(match[1]);
}

function fallbackOriginalPath(accountId, spaceId, attachment, index) {
  const fileName = attachment.fileName || `image-${index}.jpg`;
  return `accounts/${accountId}/spaces/${spaceId}/${fileName}`;
}

function thumbnailPath(originalPath, size) {
  const dotIndex = originalPath.lastIndexOf(".");
  const base = dotIndex > 0 ? originalPath.slice(0, dotIndex) : originalPath;
  return `${base}_${size}.jpg`;
}

async function downloadOriginal(bucket, attachment, originalPath) {
  if (attachment.url?.startsWith("gs://")) {
    const [data] = await bucket.file(originalPath).download();
    return data;
  }

  const response = await fetch(attachment.url);
  if (!response.ok) {
    throw new Error(`download failed: ${response.status} ${response.statusText}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

async function generateThumbnail(data, maxDimension) {
  return sharp(data)
    .resize(maxDimension, maxDimension, { fit: "inside", withoutEnlargement: true })
    .jpeg({ quality: 100 })
    .toBuffer();
}

async function uploadToStorage(bucket, storagePath, data) {
  const token = randomUUID();
  await bucket.file(storagePath).save(data, {
    metadata: {
      contentType: "image/jpeg",
      metadata: { firebaseStorageDownloadTokens: token },
    },
  });

  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(storagePath)}?alt=media&token=${token}`;
}

function needsBackfill(attachment, force) {
  if (!attachment || attachment.kind === "pdf" || attachment.kind === "file") return false;
  if (!attachment.url || typeof attachment.url !== "string") return false;
  if (attachment.isUploading === true || attachment.url.trim() === "") return false;
  if (force) return true;
  return !attachment.thumbnailUrlSm || !attachment.thumbnailUrlMd;
}

async function listSpaceDocs(db, { accountId, limit, spaceId }) {
  if (spaceId) {
    const snap = await db.doc(`accounts/${accountId}/spaces/${spaceId}`).get();
    return snap.exists ? [snap] : [];
  }

  let query = db.collection(`accounts/${accountId}/spaces`).orderBy(admin.firestore.FieldPath.documentId());
  if (limit) query = query.limit(limit);
  return (await query.get()).docs;
}

async function processAttachment({ accountId, attachment, bucket, commit, force, index, spaceId }) {
  if (!needsBackfill(attachment, force)) return { changed: false, skipped: true };

  const originalPath = parseStoragePath(attachment.url) || fallbackOriginalPath(accountId, spaceId, attachment, index);
  const nextAttachment = { ...attachment };

  if (!commit) {
    return {
      changed: true,
      dryRun: true,
      originalPath,
      smPath: thumbnailPath(originalPath, "sm"),
      mdPath: thumbnailPath(originalPath, "md"),
    };
  }

  const data = await downloadOriginal(bucket, attachment, originalPath);
  const [sm, md] = await Promise.all([
    !attachment.thumbnailUrlSm || force ? generateThumbnail(data, 300) : undefined,
    !attachment.thumbnailUrlMd || force ? generateThumbnail(data, 800) : undefined,
  ]);

  if (sm) {
    nextAttachment.thumbnailUrlSm = await uploadToStorage(bucket, thumbnailPath(originalPath, "sm"), sm);
  }
  if (md) {
    nextAttachment.thumbnailUrlMd = await uploadToStorage(bucket, thumbnailPath(originalPath, "md"), md);
  }

  return { changed: true, attachment: nextAttachment, originalPath };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  initFirebase(options);

  const db = admin.firestore();
  const bucket = getStorage().bucket(options.bucket);
  const spaceDocs = await listSpaceDocs(db, options);
  const totals = {
    attachmentsBackfilled: 0,
    attachmentsFailed: 0,
    attachmentsScanned: 0,
    spacesPatched: 0,
    spacesScanned: spaceDocs.length,
  };

  console.log(`[space-thumbs] project=${options.projectId} bucket=${options.bucket} account=${options.accountId}`);
  console.log(`[space-thumbs] mode=${options.commit ? "commit" : "dry-run"} force=${options.force}`);

  for (const doc of spaceDocs) {
    const data = doc.data();
    const images = Array.isArray(data.images) ? data.images : [];
    let changed = false;
    const nextImages = [...images];

    for (const [index, attachment] of images.entries()) {
      totals.attachmentsScanned += 1;
      try {
        const result = await processAttachment({
          accountId: options.accountId,
          attachment,
          bucket,
          commit: options.commit,
          force: options.force,
          index,
          spaceId: doc.id,
        });

        if (!result.changed) continue;

        changed = true;
        totals.attachmentsBackfilled += 1;
        if (result.attachment) nextImages[index] = result.attachment;
        console.log(`[space-thumbs] ${options.commit ? "backfilled" : "would backfill"} ${doc.id} image[${index}] ${result.originalPath}`);
      } catch (error) {
        totals.attachmentsFailed += 1;
        console.error(`[space-thumbs] failed ${doc.id} image[${index}]: ${error.message}`);
      }
    }

    if (changed && options.commit) {
      await doc.ref.update({
        images: nextImages,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      totals.spacesPatched += 1;
    } else if (changed) {
      totals.spacesPatched += 1;
    }
  }

  console.log(`[space-thumbs] scanned ${totals.spacesScanned} spaces / ${totals.attachmentsScanned} attachments`);
  console.log(`[space-thumbs] ${options.commit ? "patched" : "would patch"} ${totals.spacesPatched} spaces / ${totals.attachmentsBackfilled} attachments`);
  if (totals.attachmentsFailed) {
    console.log(`[space-thumbs] failed ${totals.attachmentsFailed} attachments`);
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(`[space-thumbs] ${error.message}`);
  if (isUsageError(error)) {
    console.error(USAGE.trim());
  }
  process.exit(1);
});
