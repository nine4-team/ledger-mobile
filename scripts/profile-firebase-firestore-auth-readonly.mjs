#!/usr/bin/env node

import crypto from "node:crypto";
import process from "node:process";
import {
  increment,
  initializeReadOnlyFirebase,
  parseArgs,
  printPreflight,
  sortedObject,
  typeSignature,
  writeProfileArtifact,
} from "./lib/firebase-readonly-profile.mjs";

const KIND = "firebase-firestore-auth-readonly";
const PAGE_SIZE = 500;
const ENUM_FIELDS = new Set([
  "type", "status", "role", "source", "kind", "captureContext",
  "companyFinancialAccess", "purchaseHandling", "reimbursementType",
  "ingestionStatus", "paymentMethod", "transactionType", "invoiceStatus",
]);
const REFERENCE_TARGETS = {
  projectId: "projects",
  intendedProjectId: "projects",
  fromProjectId: "projects",
  toProjectId: "projects",
  spaceId: "spaces",
  itemId: "items",
  itemIds: "items",
  transactionId: "transactions",
  fromTransactionId: "transactions",
  toTransactionId: "transactions",
  candidateTransactionId: "transactions",
  inventoryEntryTransactionId: "transactions",
  settlementTransactionId: "transactions",
  invoiceId: "invoices",
  settlementInvoiceId: "invoices",
  budgetCategoryId: "budgetCategories",
  vendorId: "vendors",
  clientId: "clients",
};
const NESTED_COLLECTIONS = {
  projects: ["budgetCategories", "feeInstallments", "notes", "requests"],
  spaces: ["reviewNotes"],
  users: ["projectPreferences"],
  presets: ["budgetCategories", "vendors", "spaceTemplates"],
};

function usage() {
  console.log(`Usage:
  node scripts/profile-firebase-firestore-auth-readonly.mjs \\
    --project ledger-nine4 \\
    --account 1dd4fd75-8eea-4f7a-98e7-bf45b987ae94 \\
    --credential-file /absolute/path/to/service-account.json \\
    --output-dir migration/out/source-profiles

The default is local preflight only. Remote reads additionally require:
  --execute-read-only --confirm READ_ONLY:ledger-nine4:1dd4fd75-8eea-4f7a-98e7-bf45b987ae94`);
}

function fieldProfile() {
  return { documentsContaining: 0, types: {}, enumValues: {} };
}

function observeFields(shape, value, admin, prefix = "") {
  if (!value || typeof value !== "object" || Array.isArray(value)) return;
  for (const [key, fieldValue] of Object.entries(value)) {
    const fieldPath = prefix ? `${prefix}.${key}` : key;
    const profile = shape.fields[fieldPath] ?? fieldProfile();
    profile.documentsContaining += 1;
    increment(profile.types, typeSignature(fieldValue, admin));
    if (ENUM_FIELDS.has(key) && typeof fieldValue === "string") {
      const safeValue = /^[a-z][a-z0-9_-]{0,63}$/i.test(fieldValue)
        ? fieldValue
        : "<redacted-non-enum-shape>";
      increment(profile.enumValues, safeValue);
    }
    shape.fields[fieldPath] = profile;
    if (
      fieldValue &&
      typeof fieldValue === "object" &&
      !Array.isArray(fieldValue) &&
      typeSignature(fieldValue, admin) === "map" &&
      fieldPath.split(".").length < 6
    ) {
      observeFields(shape, fieldValue, admin, fieldPath);
    }
  }
}

function collectReferences(referenceChecks, source, value, prefix = "") {
  if (!value || typeof value !== "object" || Array.isArray(value)) return;
  for (const [key, fieldValue] of Object.entries(value)) {
    const fieldPath = prefix ? `${prefix}.${key}` : key;
    const target = REFERENCE_TARGETS[key];
    if (target) {
      const candidates = Array.isArray(fieldValue) ? fieldValue : [fieldValue];
      for (const candidate of candidates) {
        if (typeof candidate !== "string" || candidate.length === 0) continue;
        referenceChecks.push({ source, fieldPath, target, candidate });
      }
    }
    if (fieldValue && typeof fieldValue === "object" && !Array.isArray(fieldValue)) {
      collectReferences(referenceChecks, source, fieldValue, fieldPath);
    }
  }
}

function finalizeShape(shape) {
  const fields = {};
  for (const [fieldPath, profile] of Object.entries(shape.fields).sort(([a], [b]) => a.localeCompare(b))) {
    fields[fieldPath] = {
      documentsContaining: profile.documentsContaining,
      types: sortedObject(profile.types),
      ...(Object.keys(profile.enumValues).length > 0
        ? { enumValues: sortedObject(profile.enumValues) }
        : {}),
    };
  }
  return {
    documents: shape.documents,
    documentIdFieldMismatches: shape.documentIdFieldMismatches,
    sourceFingerprintSha256: shape.fingerprint.digest("hex"),
    fields,
  };
}

async function scanCollection({ admin, collectionRefs, template, identifiers, referenceChecks, membershipUids }) {
  const shape = {
    documents: 0,
    documentIdFieldMismatches: 0,
    fingerprint: crypto.createHash("sha256"),
    fields: {},
  };
  const documentRefs = [];
  for (const collectionRef of collectionRefs) {
    let lastDocument = null;
    do {
      let query = collectionRef.orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE_SIZE);
      if (lastDocument) query = query.startAfter(lastDocument);
      const snapshot = await query.get();
      for (const document of snapshot.docs) {
        const data = document.data();
        shape.documents += 1;
        shape.fingerprint.update(document.ref.path);
        shape.fingerprint.update(String(document.updateTime?.toMillis() ?? 0));
        if (typeof data.id === "string" && data.id !== document.id) {
          shape.documentIdFieldMismatches += 1;
        }
        identifiers[template] ??= new Set();
        identifiers[template].add(document.id);
        observeFields(shape, data, admin);
        collectReferences(referenceChecks, template, data);
        if (template === "users") {
          const membershipUid = typeof data.uid === "string" ? data.uid : document.id;
          membershipUids.add(membershipUid);
        }
        documentRefs.push(document.ref);
      }
      lastDocument = snapshot.docs.at(-1) ?? null;
      if (snapshot.size < PAGE_SIZE) lastDocument = null;
    } while (lastDocument);
  }
  return { profile: finalizeShape(shape), documentRefs };
}

async function authProfile(auth, membershipUids) {
  const result = {
    totalUsers: 0,
    disabled: 0,
    emailVerified: 0,
    providerUsers: {},
    customClaimKeys: {},
    thisAccountMemberships: membershipUids.size,
    thisAccountMembershipsWithoutAuthUser: 0,
    authUsersMatchingThisAccountMembership: 0,
  };
  const authUids = new Set();
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      result.totalUsers += 1;
      authUids.add(user.uid);
      if (user.disabled) result.disabled += 1;
      if (user.emailVerified) result.emailVerified += 1;
      for (const provider of user.providerData) increment(result.providerUsers, provider.providerId);
      for (const claimKey of Object.keys(user.customClaims ?? {})) increment(result.customClaimKeys, claimKey);
    }
    pageToken = page.pageToken;
  } while (pageToken);
  for (const uid of membershipUids) {
    if (authUids.has(uid)) result.authUsersMatchingThisAccountMembership += 1;
    else result.thisAccountMembershipsWithoutAuthUser += 1;
  }
  result.providerUsers = sortedObject(result.providerUsers);
  result.customClaimKeys = sortedObject(result.customClaimKeys);
  return result;
}

async function run(args) {
  const { admin, db, auth } = initializeReadOnlyFirebase(args);
  const accountRef = db.doc(`accounts/${args.account}`);
  const accountSnapshot = await accountRef.get();
  if (!accountSnapshot.exists) throw new Error("Expected 1584 Design account document does not exist");

  const rootCollections = (await db.listCollections()).map((ref) => ref.id).sort();
  const accountCollections = (await accountRef.listCollections()).sort((a, b) => a.id.localeCompare(b.id));
  const identifiers = {};
  const referenceChecks = [];
  const membershipUids = new Set();
  const collectionProfiles = {};
  const topLevelDocumentRefs = {};

  const accountShape = {
    documents: 1,
    documentIdFieldMismatches: 0,
    fingerprint: crypto.createHash("sha256"),
    fields: {},
  };
  accountShape.fingerprint.update(accountRef.path);
  accountShape.fingerprint.update(String(accountSnapshot.updateTime?.toMillis() ?? 0));
  observeFields(accountShape, accountSnapshot.data(), admin);

  for (const collectionRef of accountCollections) {
    const scanned = await scanCollection({
      admin,
      collectionRefs: [collectionRef],
      template: collectionRef.id,
      identifiers,
      referenceChecks,
      membershipUids,
    });
    collectionProfiles[`accounts/{accountId}/${collectionRef.id}`] = scanned.profile;
    topLevelDocumentRefs[collectionRef.id] = scanned.documentRefs;
  }

  const observedNestedCollections = {};
  for (const [parentCollection, expectedChildren] of Object.entries(NESTED_COLLECTIONS)) {
    const parentRefs = topLevelDocumentRefs[parentCollection] ?? [];
    const observed = {};
    for (const parentRef of parentRefs) {
      for (const childRef of await parentRef.listCollections()) increment(observed, childRef.id);
    }
    observedNestedCollections[`accounts/{accountId}/${parentCollection}/{parentId}`] = sortedObject(observed);
    for (const childName of expectedChildren) {
      const collectionRefs = parentRefs.map((parentRef) => parentRef.collection(childName));
      const template = childName;
      const scanned = await scanCollection({
        admin,
        collectionRefs,
        template,
        identifiers,
        referenceChecks,
        membershipUids,
      });
      collectionProfiles[`accounts/{accountId}/${parentCollection}/{parentId}/${childName}`] = scanned.profile;
    }
  }

  const integrity = {};
  for (const check of referenceChecks) {
    const key = `${check.source}.${check.fieldPath}->${check.target}`;
    integrity[key] ??= { checked: 0, missing: 0 };
    integrity[key].checked += 1;
    if (!identifiers[check.target]?.has(check.candidate)) integrity[key].missing += 1;
  }

  const rootCounts = {};
  for (const rootName of ["accounts", "_mcp_auth_codes"]) {
    if (!rootCollections.includes(rootName)) continue;
    const countSnapshot = await db.collection(rootName).count().get();
    rootCounts[rootName] = countSnapshot.data().count;
  }

  return {
    accountDocument: finalizeShape(accountShape),
    discoveredRootCollections: rootCollections,
    rootCollectionCounts: sortedObject(rootCounts),
    discoveredAccountCollections: accountCollections.map((ref) => ref.id),
    observedNestedCollections,
    collectionProfiles,
    referenceIntegrity: Object.fromEntries(Object.entries(integrity).sort(([a], [b]) => a.localeCompare(b))),
    auth: await authProfile(auth, membershipUids),
    coverageLimits: [
      "Unknown nested collections are discovered beneath projects, spaces, users, and presets; arbitrary nesting beneath every bulk document is not enumerated.",
      "Deleted Auth users are not listable; membership-to-Auth orphan counts are the available evidence.",
      "Reference integrity covers the explicit field-to-collection map embedded in this profiler, not arbitrary string fields.",
      "Deployed Firestore index definitions and query frequency require separate deployment evidence.",
    ],
  };
}

try {
  const args = parseArgs(process.argv.slice(2));
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
