#!/usr/bin/env node
/**
 * Seed Firestore emulator from a migrator bundle.json.
 *
 * Usage:
 *   node firebase/functions/scripts/seed-firestore-emulator.mjs docs/data_migrator/out/v1/bundle.json
 *
 * Optional flags:
 *   --project <id>         Firebase project id (default: env or "demo-ledger")
 *   --firestore-host <host>
 *   --firestore-port <port>
 */

import fs from 'node:fs/promises';
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
    bundlePath: positional[0],
    projectId:
      flags.get('project') ||
      process.env.FIREBASE_PROJECT_ID ||
      process.env.GCLOUD_PROJECT ||
      'demo-ledger',
    firestoreHost: flags.get('firestore-host') || null,
    firestorePort: flags.get('firestore-port') || null,
  };
}

function parseHostAndPort(value) {
  if (!value || typeof value !== 'string') return { host: null, port: null };
  const [host, port] = value.split(':');
  return { host: host || null, port: port || null };
}

async function main() {
  const { bundlePath, projectId, firestoreHost, firestorePort } = parseArgs(process.argv);

  if (!bundlePath) {
    console.error('Missing bundle path.\n');
    console.error(
      'Usage: node firebase/functions/scripts/seed-firestore-emulator.mjs <bundle.json> [--project id]'
    );
    process.exitCode = 2;
    return;
  }

  const envHost = parseHostAndPort(process.env.FIRESTORE_EMULATOR_HOST);
  const host = firestoreHost || envHost.host || 'localhost';
  const port = firestorePort || envHost.port || '8081';
  process.env.FIRESTORE_EMULATOR_HOST = `${host}:${port}`;

  admin.initializeApp({ projectId });
  const db = admin.firestore();
  db.settings({ ignoreUndefinedProperties: true });

  const raw = await fs.readFile(bundlePath, 'utf8');
  const bundle = JSON.parse(raw);
  const documents = Array.isArray(bundle?.documents) ? bundle.documents : [];

  if (documents.length === 0) {
    console.log('[seed] No documents found in bundle.');
    return;
  }

  console.log(`[seed] Project: ${projectId}`);
  console.log(`[seed] Emulator: ${host}:${port}`);
  if (bundle?.meta?.migrationVersion) {
    console.log(`[seed] Bundle version: ${bundle.meta.migrationVersion}`);
  }

  const writer = db.bulkWriter({
    throttling: { maxOpsPerSecond: 200 },
  });
  writer.onWriteError((error) => {
    if (error.code === 10 && error.failedAttempts < 5) {
      return true;
    }
    console.error(`[seed] Write failed for ${error.documentRef.path}`, error);
    return false;
  });

  let written = 0;
  for (const doc of documents) {
    if (!doc?.path || !doc?.data) continue;
    writer.set(db.doc(doc.path), doc.data);
    written += 1;
    if (written % 500 === 0) {
      console.log(`[seed] Queued ${written} docs...`);
    }
  }

  await writer.close();
  console.log(`[seed] Done. Wrote ${written} docs.`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
