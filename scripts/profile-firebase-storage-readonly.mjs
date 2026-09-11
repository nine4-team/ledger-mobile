#!/usr/bin/env node

import process from "node:process";
import {
  increment,
  initializeReadOnlyFirebase,
  parseArgs,
  printPreflight,
  sortedObject,
  writeProfileArtifact,
} from "./lib/firebase-readonly-profile.mjs";

const KIND = "firebase-storage-readonly";
const PAGE_SIZE = 500;
const NESTED_COLLECTIONS = {
  projects: ["budgetCategories", "feeInstallments", "notes", "requests"],
  spaces: ["reviewNotes"],
  users: ["projectPreferences"],
  presets: ["budgetCategories", "vendors", "spaceTemplates"],
};
const KNOWN_NAMESPACES = new Set([
  "items", "projects", "protoItems", "quickDraftItems", "spaces", "transactions",
]);

function usage() {
  console.log(`Usage:
  node scripts/profile-firebase-storage-readonly.mjs \\
    --project ledger-nine4 \\
    --account 1dd4fd75-8eea-4f7a-98e7-bf45b987ae94 \\
    --bucket ledger-nine4.firebasestorage.app \\
    --credential-file /absolute/path/to/service-account.json \\
    --output-dir migration/out/source-profiles

The default is local preflight only. Remote reads additionally require:
  --execute-read-only --confirm READ_ONLY:ledger-nine4:1dd4fd75-8eea-4f7a-98e7-bf45b987ae94`);
}

function parseStorageReference(value, expectedBucket, accountPrefix) {
  if (value.startsWith(accountPrefix)) {
    return { scheme: "raw_account_path", bucket: expectedBucket, objectName: value };
  }
  if (value.startsWith("gs://")) {
    const remainder = value.slice(5);
    const separator = remainder.indexOf("/");
    if (separator < 1) return { error: "invalid_gs_url" };
    return {
      scheme: "gs",
      bucket: remainder.slice(0, separator),
      objectName: remainder.slice(separator + 1),
    };
  }
  if (!value.startsWith("https://") && !value.startsWith("http://")) return null;
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    return { error: "invalid_http_url" };
  }
  const firebaseMatch = parsed.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
  if (firebaseMatch) {
    try {
      return {
        scheme: "firebase_download_url",
        bucket: decodeURIComponent(firebaseMatch[1]),
        objectName: decodeURIComponent(firebaseMatch[2]),
      };
    } catch {
      return { error: "invalid_percent_encoding" };
    }
  }
  if (parsed.hostname === "storage.googleapis.com") {
    const match = parsed.pathname.match(/^\/([^/]+)\/(.+)$/);
    if (!match) return { error: "invalid_google_storage_url" };
    return {
      scheme: "google_storage_url",
      bucket: decodeURIComponent(match[1]),
      objectName: decodeURIComponent(match[2]),
    };
  }
  return null;
}

function collectReferenceStrings(value, sourceCollection, fieldPath, output) {
  if (typeof value === "string") {
    if (
      value.startsWith("gs://") ||
      value.startsWith("https://") ||
      value.startsWith("http://") ||
      value.startsWith("accounts/")
    ) {
      output.push({ sourceCollection, fieldPath, value });
    }
    return;
  }
  if (Array.isArray(value)) {
    for (const entry of value) collectReferenceStrings(entry, sourceCollection, fieldPath, output);
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, fieldValue] of Object.entries(value)) {
    collectReferenceStrings(
      fieldValue,
      sourceCollection,
      fieldPath ? `${fieldPath}.${key}` : key,
      output,
    );
  }
}

async function scanCollectionReferences(admin, collectionRefs, sourceCollection, output) {
  const documentRefs = [];
  let documentsScanned = 0;
  for (const collectionRef of collectionRefs) {
    let lastDocument = null;
    do {
      let query = collectionRef.orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE_SIZE);
      if (lastDocument) query = query.startAfter(lastDocument);
      const snapshot = await query.get();
      for (const document of snapshot.docs) {
        documentsScanned += 1;
        collectReferenceStrings(document.data(), sourceCollection, "", output);
        documentRefs.push(document.ref);
      }
      lastDocument = snapshot.docs.at(-1) ?? null;
      if (snapshot.size < PAGE_SIZE) lastDocument = null;
    } while (lastDocument);
  }
  return { documentsScanned, documentRefs };
}

function namespaceFor(objectName, accountPrefix) {
  const relative = objectName.slice(accountPrefix.length);
  const first = relative.split("/")[0];
  return KNOWN_NAMESPACES.has(first) ? first : "_other";
}

async function run(args) {
  const { admin, db, bucket } = initializeReadOnlyFirebase(args);
  const accountPrefix = `accounts/${args.account}/`;
  const accountRef = db.doc(`accounts/${args.account}`);
  const accountSnapshot = await accountRef.get();
  if (!accountSnapshot.exists) throw new Error("Expected 1584 Design account document does not exist");

  const referenceStrings = [];
  collectReferenceStrings(accountSnapshot.data(), "account", "", referenceStrings);
  const sourceDocumentsScanned = { account: 1 };
  const topLevelDocumentRefs = {};
  const accountCollections = (await accountRef.listCollections()).sort((a, b) => a.id.localeCompare(b.id));
  for (const collectionRef of accountCollections) {
    const scanned = await scanCollectionReferences(
      admin,
      [collectionRef],
      collectionRef.id,
      referenceStrings,
    );
    sourceDocumentsScanned[collectionRef.id] = scanned.documentsScanned;
    topLevelDocumentRefs[collectionRef.id] = scanned.documentRefs;
  }
  for (const [parentCollection, childNames] of Object.entries(NESTED_COLLECTIONS)) {
    const parentRefs = topLevelDocumentRefs[parentCollection] ?? [];
    for (const childName of childNames) {
      const sourceCollection = `${parentCollection}/*/${childName}`;
      const scanned = await scanCollectionReferences(
        admin,
        parentRefs.map((parentRef) => parentRef.collection(childName)),
        sourceCollection,
        referenceStrings,
      );
      sourceDocumentsScanned[sourceCollection] = scanned.documentsScanned;
    }
  }

  const [files] = await bucket.getFiles({ prefix: accountPrefix });
  const objectNames = new Set();
  const namespaces = {};
  const contentTypes = {};
  const md5Groups = new Map();
  let totalBytes = 0;
  let thumbnailObjects = 0;
  let objectsWithDownloadToken = 0;
  for (const file of files) {
    const metadata = file.metadata ?? {};
    const size = Number(metadata.size ?? 0);
    objectNames.add(file.name);
    totalBytes += Number.isFinite(size) ? size : 0;
    increment(namespaces, namespaceFor(file.name, accountPrefix));
    increment(contentTypes, metadata.contentType || "<missing>");
    if (/\/thumbs\/|_(?:sm|md)\.[^/]+$/i.test(file.name)) thumbnailObjects += 1;
    if (metadata.metadata?.firebaseStorageDownloadTokens) objectsWithDownloadToken += 1;
    if (metadata.md5Hash) {
      const group = md5Groups.get(metadata.md5Hash) ?? { objects: 0, bytes: 0 };
      group.objects += 1;
      group.bytes += Number.isFinite(size) ? size : 0;
      md5Groups.set(metadata.md5Hash, group);
    }
  }

  const referencedObjectCounts = new Map();
  const referenceSchemes = {};
  const referenceFields = {};
  let storageReferences = 0;
  let invalidStorageReferences = 0;
  let referencesToOtherBuckets = 0;
  let referencesOutsideAccountNamespace = 0;
  for (const reference of referenceStrings) {
    const parsed = parseStorageReference(reference.value, args.bucket, accountPrefix);
    if (!parsed) continue;
    storageReferences += 1;
    const fieldKey = `${reference.sourceCollection}.${reference.fieldPath || "<root>"}`;
    increment(referenceFields, fieldKey);
    if (parsed.error) {
      invalidStorageReferences += 1;
      continue;
    }
    increment(referenceSchemes, parsed.scheme);
    if (parsed.bucket !== args.bucket) {
      referencesToOtherBuckets += 1;
      continue;
    }
    if (!parsed.objectName.startsWith(accountPrefix)) {
      referencesOutsideAccountNamespace += 1;
      continue;
    }
    referencedObjectCounts.set(
      parsed.objectName,
      (referencedObjectCounts.get(parsed.objectName) ?? 0) + 1,
    );
  }

  let danglingReferences = 0;
  let multiplyReferencedObjects = 0;
  for (const [objectName, count] of referencedObjectCounts) {
    if (!objectNames.has(objectName)) danglingReferences += count;
    if (count > 1) multiplyReferencedObjects += 1;
  }
  let unreferencedObjects = 0;
  for (const objectName of objectNames) {
    if (!referencedObjectCounts.has(objectName)) unreferencedObjects += 1;
  }
  let duplicateContentGroups = 0;
  let duplicateContentObjects = 0;
  let duplicateContentBytes = 0;
  for (const group of md5Groups.values()) {
    if (group.objects < 2) continue;
    duplicateContentGroups += 1;
    duplicateContentObjects += group.objects;
    duplicateContentBytes += group.bytes;
  }

  return {
    sourceDocumentsScanned: sortedObject(sourceDocumentsScanned),
    objects: {
      count: files.length,
      totalBytes,
      namespaces: sortedObject(namespaces),
      contentTypes: sortedObject(contentTypes),
      thumbnailObjects,
      objectsWithDownloadToken,
    },
    references: {
      candidateUrlOrPathStrings: referenceStrings.length,
      recognizedStorageReferences: storageReferences,
      schemes: sortedObject(referenceSchemes),
      fields: sortedObject(referenceFields),
      invalidStorageReferences,
      referencesToOtherBuckets,
      referencesOutsideAccountNamespace,
      distinctReferencedAccountObjects: referencedObjectCounts.size,
      danglingReferences,
      multiplyReferencedObjects,
      unreferencedObjects,
    },
    contentDuplication: {
      duplicateContentGroups,
      objectsInDuplicateGroups: duplicateContentObjects,
      bytesInDuplicateGroups: duplicateContentBytes,
      note: "Duplicate groups use in-memory provider MD5 metadata; no hashes or object names are emitted.",
    },
    coverageLimits: [
      "No object bytes are downloaded; counts and duplication use listing metadata only.",
      "Firestore references are scanned in the account document, every top-level account collection, and known project/space/user/preset child collections.",
      "Objects referenced only from unknown nested collections, deleted documents, local pending-upload queues, or external systems can appear unreferenced.",
      "Unrecognized HTTP URLs are ignored rather than treated as Firebase Storage references.",
    ],
  };
}

try {
  const args = parseArgs(process.argv.slice(2), { requireBucket: true });
  if (args.help) {
    usage();
  } else if (!args.executeReadOnly) {
    printPreflight(KIND, args);
  } else {
    const result = await run(args);
    const written = writeProfileArtifact(KIND, args, result);
    console.log(JSON.stringify({ result: "read_only_profile_written", ...written }, null, 2));
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
