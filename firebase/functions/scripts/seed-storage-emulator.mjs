#!/usr/bin/env node
/**
 * Seed Storage emulator from a migrator media-manifest.json.
 *
 * Usage:
 *   node firebase/functions/scripts/seed-storage-emulator.mjs docs/data_migrator/out/v1/media-manifest.json
 *
 * Optional flags:
 *   --project <id>         Firebase project id (default: env or "demo-ledger")
 *   --storage-host <host>  Storage emulator host (default: localhost)
 *   --storage-port <port>  Storage emulator port (default: 9199)
 *   --bucket <name>        Storage bucket name (default: <project-id>.appspot.com)
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import admin from 'firebase-admin';

function parseArgs(argv) {
  const args = argv.slice(2);
  const positional = [];
  const flags = new Map();

  for (let i = 0; i < args.length; i += 1) {
    const a = args[i];
    if (!a.startsWith('--')) {
      positional.push(a);
      continue;
    }
    const key = a.slice(2);
    const next = args[i + 1];
    if (!next || next.startsWith('--')) {
      flags.set(key, true);
    } else {
      flags.set(key, next);
      i += 1;
    }
  }

  return {
    manifestPath: positional[0],
    projectId:
      flags.get('project') ||
      process.env.FIREBASE_PROJECT_ID ||
      process.env.GCLOUD_PROJECT ||
      'demo-ledger',
    storageHost: flags.get('storage-host') || 'localhost',
    storagePort: flags.get('storage-port') || '9199',
    bucketName: flags.get('bucket') || null,
  };
}

async function fileExists(p) {
  try {
    await fs.access(p);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const { manifestPath, projectId, storageHost, storagePort, bucketName } = parseArgs(process.argv);

  if (!manifestPath) {
    console.error('Missing manifest path.\n');
    console.error(
      'Usage: node firebase/functions/scripts/seed-storage-emulator.mjs <media-manifest.json>'
    );
    process.exitCode = 2;
    return;
  }

  // Set emulator env vars
  process.env.FIREBASE_STORAGE_EMULATOR_HOST = `${storageHost}:${storagePort}`;
  process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || 'localhost:8080';

  admin.initializeApp({
    projectId,
    storageBucket: bucketName || `${projectId}.appspot.com`,
  });

  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  console.log(`[seed] Project: ${projectId}`);
  console.log(`[seed] Storage Emulator: ${storageHost}:${storagePort}`);
  console.log(`[seed] Bucket: ${bucket.name}`);

  const raw = await fs.readFile(manifestPath, 'utf8');
  const json = JSON.parse(raw);
  const mediaList = Array.isArray(json?.media) ? json.media : [];

  if (mediaList.length === 0) {
    console.log('[seed] No media found in manifest.');
    return;
  }

  let successCount = 0;
  let skippedCount = 0;
  let errorCount = 0;

  for (const item of mediaList) {
    const { mediaId, kind, contentType, storage, owner } = item;
    
    if (!storage?.localPath) {
      console.warn(`[skip] No local path for ${mediaId}`);
      skippedCount++;
      continue;
    }

    if (!(await fileExists(storage.localPath))) {
      console.warn(`[skip] File not found: ${storage.localPath}`);
      skippedCount++;
      continue;
    }

    const destination = `migrated/${mediaId}`; // Simple flat structure or mimic original
    // Use original key if available to preserve structure, or just mediaId
    const remotePath = storage.key ? storage.key : `migrated/${mediaId}`;

    try {
      await bucket.upload(storage.localPath, {
        destination: remotePath,
        metadata: {
          contentType: contentType || undefined,
          metadata: {
            originalMediaId: mediaId,
            kind,
          },
        },
      });

      // Construct public URL for emulator
      // http://<host>:<port>/v0/b/<bucket>/o/<encoded-path>?alt=media
      const encodedPath = encodeURIComponent(remotePath);
      const publicUrl = `http://${storageHost}:${storagePort}/v0/b/${bucket.name}/o/${encodedPath}?alt=media`;

      // Update Firestore doc
      if (owner?.path && owner?.field) {
        const docRef = db.doc(owner.path);
        const docSnap = await docRef.get();
        
        if (docSnap.exists) {
          const data = docSnap.data();
          let updated = false;
          
          // Handle array fields (images, receiptImages, etc.)
          if (Array.isArray(data[owner.field])) {
            const nextArray = data[owner.field].map((attachment) => {
              if (attachment.url === `offline://${mediaId}`) {
                updated = true;
                return { ...attachment, url: publicUrl };
              }
              return attachment;
            });
            if (updated) {
              await docRef.update({ [owner.field]: nextArray });
            }
          } 
          // Handle single fields (logo)
          else if (data[owner.field]?.url === `offline://${mediaId}`) {
            await docRef.update({
              [owner.field]: { ...data[owner.field], url: publicUrl },
            });
            updated = true;
          }

          if (updated) {
            // console.log(`[update] Updated ${owner.path} with ${publicUrl}`);
          } else {
            // console.log(`[warn] Could not find offline://${mediaId} in ${owner.path}`);
          }
        }
      }

      successCount++;
      if (successCount % 50 === 0) {
        console.log(`[seed] Processed ${successCount} files...`);
      }
    } catch (err) {
      console.error(`[error] Failed to upload ${mediaId}:`, err.message);
      errorCount++;
    }
  }

  console.log(`[seed] Done. Uploaded: ${successCount}, Skipped: ${skippedCount}, Errors: ${errorCount}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
