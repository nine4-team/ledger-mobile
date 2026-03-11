import admin from 'firebase-admin';
import type { FirestoreDoc } from './types.js';

export type WriteTarget = 'emulator' | 'production';

export function initFirestore(target: WriteTarget, projectId: string): admin.firestore.Firestore {
  if (admin.apps.length > 0) return admin.app().firestore();

  if (target === 'emulator') {
    // FIRESTORE_EMULATOR_HOST must already be set in the environment before this call.
    admin.initializeApp({ projectId });
  } else {
    // Production: requires GOOGLE_APPLICATION_CREDENTIALS or Application Default Credentials.
    admin.initializeApp({ projectId, credential: admin.credential.applicationDefault() });
  }

  const db = admin.firestore();
  db.settings({ ignoreUndefinedProperties: true });
  return db;
}

/**
 * Convert ISO date strings in known timestamp fields to Firestore Timestamps.
 * Fields listed here are converted; all others are passed through unchanged.
 */
const TIMESTAMP_FIELDS = new Set([
  'createdAt', 'updatedAt', 'deletedAt', 'appliedAt',
]);

function convertTimestamps(data: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(data)) {
    if (TIMESTAMP_FIELDS.has(key) && typeof value === 'string') {
      try {
        out[key] = admin.firestore.Timestamp.fromDate(new Date(value));
      } catch {
        out[key] = value;
      }
    } else {
      out[key] = value;
    }
  }
  return out;
}

/**
 * Write documents to Firestore using BulkWriter (idempotent .set()).
 * Returns counts of written/failed documents.
 */
export async function writeDocs(
  db: admin.firestore.Firestore,
  documents: FirestoreDoc[],
  options: { dryRun?: boolean; opsPerSecond?: number } = {}
): Promise<{ written: number; failed: number }> {
  if (options.dryRun) {
    console.log(`  [dry-run] Would write ${documents.length} documents.`);
    return { written: documents.length, failed: 0 };
  }

  const writer = db.bulkWriter();

  let written = 0;
  let failed = 0;

  writer.onWriteError((error) => {
    console.error(`  Write error at ${error.documentRef.path}: ${error.message}`);
    failed++;
    return false; // Do not retry
  });

  writer.onWriteResult(() => {
    written++;
  });

  for (const doc of documents) {
    const ref = db.doc(doc.path);
    writer.set(ref, convertTimestamps(doc.data));
  }

  await writer.close();
  return { written, failed };
}
