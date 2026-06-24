/**
 * One-off migration: relabel legacy Sale-typed transactions that actually
 * record an inventory→project (business_to_project) movement.
 *
 * Background:
 *   Per current doctrine, inventory→project = Purchase, project→inventory = Sale.
 *   Some early data has type="Sale" but the txn ID encodes `business_to_project`,
 *   so the UI groups them under "Sold to Business Inventory" — backwards.
 *
 * What this does:
 *   For each account, find transactions where:
 *     - type === "Sale"
 *     - id matches /SALE_[^_]+_business_to_project_/
 *   and flip type → "Purchase", set source → resolved inventory label for that
 *   account ("Business Inventory" or "<AccountName> Inventory"), and append an
 *   AI audit line documenting the flip.
 *
 * Safety:
 *   - Dry-run by default. Pass `--commit` to actually write.
 *   - Pass `--account <accountId>` to scope to one account.
 *   - Pass `--txn <txnId>` to scope to one transaction (overrides --account).
 *
 * Run:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa.json \
 *     npx tsx scripts/migrate-misnamed-sales.ts --account <accountId> [--commit]
 */

import admin from "firebase-admin";
import { readFileSync } from "node:fs";

type TxnDoc = {
  id: string;
  type?: string;
  source?: string;
  notes?: string;
  projectId?: string;
  budgetCategoryId?: string;
};

const args = new Map<string, string | true>();
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a.startsWith("--")) {
    const key = a.slice(2);
    const next = process.argv[i + 1];
    if (next && !next.startsWith("--")) {
      args.set(key, next);
      i++;
    } else {
      args.set(key, true);
    }
  }
}

const COMMIT = args.get("commit") === true;
const ONLY_ACCOUNT = typeof args.get("account") === "string" ? (args.get("account") as string) : null;
const ONLY_TXN = typeof args.get("txn") === "string" ? (args.get("txn") as string) : null;

const ID_PATTERN = /^SALE_[^_]+_business_to_project_/;

function initFirebase() {
  if (admin.apps.length) return admin.firestore();
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const projectId = process.env.FIREBASE_PROJECT_ID || "ledger-nine4";
  if (!credPath) {
    console.error("GOOGLE_APPLICATION_CREDENTIALS not set.");
    process.exit(1);
  }
  const sa = JSON.parse(readFileSync(credPath, "utf8"));
  admin.initializeApp({ credential: admin.credential.cert(sa), projectId });
  return admin.firestore();
}

function inventoryLabelForAccountName(name?: string | null): string {
  const trimmed = (name ?? "").trim();
  return trimmed ? `${trimmed} Inventory` : "Business Inventory";
}

function todayMdY(): string {
  const d = new Date();
  return `${d.getMonth() + 1}/${d.getDate()}/${d.getFullYear()}`;
}

function appendAudit(existing: string | undefined, line: string): string {
  const tagged = `[AI ${todayMdY()}] ${line}`;
  const prev = (existing ?? "").trimEnd();
  if (!prev) return tagged;
  return `${prev}\n\n${tagged}`;
}

async function migrateAccount(
  db: FirebaseFirestore.Firestore,
  accountId: string
): Promise<{ scanned: number; matched: number; flipped: number; skipped: { id: string; reason: string }[] }> {
  const accountSnap = await db.doc(`accounts/${accountId}`).get();
  const accountName = (accountSnap.data()?.name ?? accountSnap.data()?.companyName) as string | undefined;
  const inventoryLabel = inventoryLabelForAccountName(accountName);

  const txCol = db.collection(`accounts/${accountId}/transactions`);
  const query = ONLY_TXN
    ? txCol.where(admin.firestore.FieldPath.documentId(), "==", ONLY_TXN)
    : txCol.where("type", "==", "Sale");

  const snap = await query.get();
  let matched = 0;
  let flipped = 0;
  const skipped: { id: string; reason: string }[] = [];

  for (const doc of snap.docs) {
    const data = doc.data() as TxnDoc;
    const id = doc.id;

    if (!ID_PATTERN.test(id)) continue;
    matched++;

    if (data.type !== "Sale") {
      skipped.push({ id, reason: `already type=${data.type}` });
      continue;
    }

    const newSource = inventoryLabel;
    const auditLine = `Migration: flipped legacy type="Sale" → "Purchase" and set source="${newSource}". ID encodes business→project direction; original mislabel grouped this txn under "Sold to Business Inventory" in the UI.`;

    const update: Record<string, unknown> = {
      type: "Purchase",
      source: newSource,
      notes: appendAudit(data.notes, auditLine),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    console.log(`  ${COMMIT ? "FLIP" : "DRY"} ${id}  source: ${data.source ?? "(none)"} → ${newSource}`);

    if (COMMIT) {
      await doc.ref.update(update);
    }
    flipped++;
  }

  return { scanned: snap.size, matched, flipped, skipped };
}

async function main() {
  const db = initFirebase();

  let accountIds: string[];
  if (ONLY_ACCOUNT) {
    accountIds = [ONLY_ACCOUNT];
  } else {
    const accounts = await db.collection("accounts").get();
    accountIds = accounts.docs.map((d) => d.id);
  }

  console.log(`Mode: ${COMMIT ? "COMMIT" : "DRY-RUN"}`);
  console.log(`Accounts: ${accountIds.length}`);
  console.log("");

  let totalMatched = 0;
  let totalFlipped = 0;
  const allSkipped: { accountId: string; id: string; reason: string }[] = [];

  for (const accountId of accountIds) {
    console.log(`Account ${accountId}:`);
    const res = await migrateAccount(db, accountId);
    console.log(`  scanned=${res.scanned}  matched=${res.matched}  flipped=${res.flipped}  skipped=${res.skipped.length}`);
    totalMatched += res.matched;
    totalFlipped += res.flipped;
    res.skipped.forEach((s) => allSkipped.push({ accountId, ...s }));
    console.log("");
  }

  console.log("---");
  console.log(`Total matched: ${totalMatched}`);
  console.log(`Total ${COMMIT ? "flipped" : "would flip"}: ${totalFlipped}`);
  if (allSkipped.length) {
    console.log(`Skipped:`);
    allSkipped.forEach((s) => console.log(`  ${s.accountId}/${s.id} — ${s.reason}`));
  }
  if (!COMMIT) console.log(`\nDry-run — no writes. Re-run with --commit to apply.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
