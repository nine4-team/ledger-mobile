/**
 * Legacy test helpers for the MCP server per-batch sale tests.
 *
 * Normal MCP validation should use real Firestore with a Firebase Admin
 * service-account key. This emulator harness exists only for the older
 * inventory movement Vitest coverage.
 *
 * Strategy:
 * - Firestore emulator provides the backing store (set FIRESTORE_EMULATOR_HOST
 *   before importing firebase-admin).
 * - A lightweight mock MCP server captures registered tool handlers so tests
 *   can invoke them directly without going through the SDK transport layer.
 * - requestContext is wrapped around each call so getAccountId() / getUid()
 *   resolve inside the tool handlers.
 *
 * Seed-then-act-then-assert: each test wipes the account's collections first,
 * seeds fixtures, calls the tool, and asserts Firestore state + response.
 */

import admin from "firebase-admin";
import type { Firestore } from "firebase-admin/firestore";
import { requestContext } from "../src/context.js";

export const TEST_PROJECT_ID = "demo-mcp-test";
export const TEST_ACCOUNT_ID = "acc_mcp_test";
export const TEST_USER_ID = "user_mcp_test";

// Ensure the admin SDK talks to the emulator. Must run BEFORE firebase-admin
// is imported by any downstream module.
process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8181";
process.env.FIREBASE_PROJECT_ID = TEST_PROJECT_ID;

let _db: Firestore | null = null;

export function getTestDb(): Firestore {
  if (_db) return _db;
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: TEST_PROJECT_ID });
  }
  _db = admin.firestore();
  return _db;
}

/**
 * Capture tool handlers registered via server.tool(name, desc, schema, handler).
 * The MCP SDK treats `handler` as an async (args) => Promise<ToolResponse>.
 */
export interface CapturedServer {
  tool: (
    name: string,
    desc: string,
    schema: Record<string, unknown>,
    handler: (args: any) => Promise<any>
  ) => void;
  resource?: (...args: unknown[]) => void;
  handlers: Map<string, (args: any) => Promise<any>>;
  schemas: Map<string, Record<string, unknown>>;
}

export function makeCapturedServer(): CapturedServer {
  const handlers = new Map<string, (args: any) => Promise<any>>();
  const schemas = new Map<string, Record<string, unknown>>();
  return {
    tool(name, _desc, schema, handler) {
      handlers.set(name, handler);
      schemas.set(name, schema);
    },
    resource() {
      /* no-op for tests */
    },
    handlers,
    schemas,
  };
}

/** Wipe all docs we care about under the test account. */
export async function wipeAccount(db: Firestore): Promise<void> {
  const collections = [
    "items",
    "transactions",
    "lineageEdges",
    "projects",
    "spaces",
  ];
  for (const col of collections) {
    const snap = await db.collection(`accounts/${TEST_ACCOUNT_ID}/${col}`).get();
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    if (!snap.empty) await batch.commit();
  }
  // Also clear project subcollections (budgetCategories).
  const projectsSnap = await db.collection(`accounts/${TEST_ACCOUNT_ID}/projects`).get();
  for (const proj of projectsSnap.docs) {
    const catsSnap = await proj.ref.collection("budgetCategories").get();
    if (catsSnap.empty) continue;
    const batch = db.batch();
    for (const cat of catsSnap.docs) batch.delete(cat.ref);
    await batch.commit();
  }
}

export interface SeedProjectOptions {
  id: string;
  name?: string;
  budgetCategories?: Array<{ id: string; budgetCents?: number }>;
}

export async function seedProject(
  db: Firestore,
  options: SeedProjectOptions
): Promise<void> {
  const projRef = db.doc(
    `accounts/${TEST_ACCOUNT_ID}/projects/${options.id}`
  );
  await projRef.set({
    name: options.name ?? options.id,
    clientName: "Test Client",
    isArchived: false,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  if (options.budgetCategories) {
    for (const cat of options.budgetCategories) {
      await projRef.collection("budgetCategories").doc(cat.id).set({
        budgetCents: cat.budgetCents ?? 0,
        updatedAt: new Date(),
      });
    }
  }
}

export interface SeedItemOptions {
  id: string;
  name?: string;
  projectId?: string | null;
  budgetCategoryId?: string | null;
  purchasePriceCents?: number;
  projectPriceCents?: number;
  taxRatePct?: number;
  transactionId?: string | null;
  status?: string;
  source?: string;
  currentSource?: string;
}

export async function seedItem(db: Firestore, opts: SeedItemOptions): Promise<void> {
  const ref = db.doc(`accounts/${TEST_ACCOUNT_ID}/items/${opts.id}`);
  const data: Record<string, unknown> = {
    name: opts.name ?? opts.id,
    status: opts.status ?? "purchased",
    createdAt: new Date(),
    updatedAt: new Date(),
  };
  if (opts.projectId !== undefined) data.projectId = opts.projectId;
  if (opts.budgetCategoryId !== undefined) data.budgetCategoryId = opts.budgetCategoryId;
  if (opts.purchasePriceCents !== undefined) data.purchasePriceCents = opts.purchasePriceCents;
  if (opts.projectPriceCents !== undefined) data.projectPriceCents = opts.projectPriceCents;
  if (opts.taxRatePct !== undefined) data.taxRatePct = opts.taxRatePct;
  if (opts.transactionId !== undefined) data.transactionId = opts.transactionId;
  if (opts.source !== undefined) data.source = opts.source;
  if (opts.currentSource !== undefined) data.currentSource = opts.currentSource;
  await ref.set(data);
}

export interface SeedTransactionOptions {
  id: string;
  type: string;
  source?: string;
  projectId?: string | null;
  budgetCategoryId?: string | null;
  amountCents?: number;
  itemIds?: string[];
  isCanonicalInventorySale?: boolean;
  inventorySaleDirection?: string;
  status?: string;
  purchaseHandling?: "inventory_resale" | "project_reimbursement";
  reimbursementType?: string;
}

export async function seedTransaction(
  db: Firestore,
  opts: SeedTransactionOptions
): Promise<void> {
  const ref = db.doc(`accounts/${TEST_ACCOUNT_ID}/transactions/${opts.id}`);
  const data: Record<string, unknown> = {
    type: opts.type,
    status: opts.status ?? "completed",
    createdAt: new Date(),
    updatedAt: new Date(),
  };
  if (opts.source !== undefined) data.source = opts.source;
  if (opts.projectId !== undefined) data.projectId = opts.projectId;
  if (opts.budgetCategoryId !== undefined) data.budgetCategoryId = opts.budgetCategoryId;
  if (opts.amountCents !== undefined) data.amountCents = opts.amountCents;
  if (opts.itemIds !== undefined) data.itemIds = opts.itemIds;
  if (opts.isCanonicalInventorySale !== undefined) {
    data.isCanonicalInventorySale = opts.isCanonicalInventorySale;
  }
  if (opts.inventorySaleDirection !== undefined) {
    data.inventorySaleDirection = opts.inventorySaleDirection;
  }
  if (opts.purchaseHandling !== undefined) data.purchaseHandling = opts.purchaseHandling;
  if (opts.reimbursementType !== undefined) data.reimbursementType = opts.reimbursementType;
  await ref.set(data);
}

/** Run a function inside a mocked request context so getAccountId/getUid resolve. */
export async function withContext<T>(fn: () => Promise<T>): Promise<T> {
  return requestContext.run(
    { accountId: TEST_ACCOUNT_ID, uid: TEST_USER_ID },
    fn
  );
}

/** Fetch a doc by path, returning null if missing. */
export async function getDocData(
  db: Firestore,
  path: string
): Promise<Record<string, unknown> | null> {
  const snap = await db.doc(path).get();
  if (!snap.exists) return null;
  return snap.data() ?? null;
}

/** Fetch all transactions in the test account matching type. */
export async function listTransactionsOfType(
  db: Firestore,
  type: string
): Promise<Array<{ id: string; data: Record<string, unknown> }>> {
  const snap = await db
    .collection(`accounts/${TEST_ACCOUNT_ID}/transactions`)
    .where("type", "==", type)
    .get();
  return snap.docs.map((d) => ({ id: d.id, data: d.data() }));
}

/** Fetch all lineage edges in the test account. */
export async function listLineageEdges(
  db: Firestore
): Promise<Array<{ id: string; data: Record<string, unknown> }>> {
  const snap = await db.collection(`accounts/${TEST_ACCOUNT_ID}/lineageEdges`).get();
  return snap.docs.map((d) => ({ id: d.id, data: d.data() }));
}
