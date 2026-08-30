/**
 * Focused legacy-emulator coverage for destructive transaction controls.
 *
 * Run with:
 *   firebase emulators:exec --only firestore --project demo-mcp-test \
 *     "cd mcp-server && npx vitest run test/transaction-deletion-safety.test.ts"
 */

import { beforeAll, beforeEach, describe, expect, test } from "vitest";
import {
  TEST_ACCOUNT_ID,
  TEST_USER_ID,
  getDocData,
  getTestDb,
  makeCapturedServer,
  seedItem,
  seedTransaction,
  wipeAccount,
  withContext,
} from "./helpers.js";
import { registerTransactionTools } from "../src/tools/transactions.js";

const db = getTestDb();
const server = makeCapturedServer();

beforeAll(() => {
  registerTransactionTools(server as any, db);
});

beforeEach(async () => {
  await wipeAccount(db);
  server.elicitations.splice(0);
  server.setElicitationHandler(async () => ({ action: "decline" }));
});

function callTool(name: string, args: Record<string, unknown>) {
  const handler = server.handlers.get(name);
  if (!handler) throw new Error(`Tool ${name} not registered`);
  return withContext(() => handler(args));
}

function payload(result: unknown): any {
  const text = (result as { content?: Array<{ text?: string }> }).content?.[0]?.text;
  if (!text) throw new Error("Tool response did not include text content");
  return JSON.parse(text);
}

async function seedDeletableTransaction(id = "tx_delete") {
  await db.doc(`accounts/${TEST_ACCOUNT_ID}/transactions/${id}`).set({
    type: "Purchase",
    status: "canceled",
    source: "Duplicate import",
    projectId: "project_1",
    budgetCategoryId: "category_1",
    amountCents: 12_345,
    subtotalCents: 12_345,
    itemIds: [],
    notes: "Original user prose must survive in the tombstone.",
    createdAt: new Date("2026-08-01T12:00:00Z"),
    updatedAt: new Date("2026-08-02T12:00:00Z"),
  });
}

function approveDeletion(_transactionId?: string) {
  server.setElicitationHandler(async () => ({
    action: "accept",
    content: { confirmation: "DELETE" },
  }));
}

describe("cancel_transaction", () => {
  test("requires a reason and leaves the transaction unchanged when missing", async () => {
    await seedTransaction(db, {
      id: "tx_cancel",
      type: "Purchase",
      amountCents: 5000,
      status: "completed",
    });

    const result = await callTool("cancel_transaction", {
      transactionId: "tx_cancel",
      note: " ",
    });

    expect(result.isError).toBe(true);
    expect(payload(result).error.code).toBe("VALIDATION");
    const transaction = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/tx_cancel`
    );
    expect(transaction?.status).toBe("completed");
    expect(transaction?.notes).toBeUndefined();
  });

  test("atomically cancels and durably appends the reason without replacing user prose", async () => {
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/transactions/tx_cancel`).set({
      type: "Purchase",
      status: "completed",
      amountCents: 5000,
      notes: "Home Goods receipt entered by Ben.",
    });

    const args = {
      transactionId: "tx_cancel",
      note: "Duplicate transaction superseded by tx_replacement.",
    };
    const result = await callTool("cancel_transaction", args);
    expect(result.isError).not.toBe(true);

    const transaction = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/tx_cancel`
    );
    expect(transaction?.status).toBe("canceled");
    expect(transaction?.notes).toContain("Home Goods receipt entered by Ben.");
    expect(transaction?.notes).toContain(
      "Canceled transaction — Duplicate transaction superseded by tx_replacement."
    );
    expect(transaction?.updatedBy).toBe(TEST_USER_ID);

    await callTool("cancel_transaction", args);
    const retried = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactions/tx_cancel`
    );
    expect(
      String(retried?.notes).match(/Canceled transaction — Duplicate transaction/g)
    ).toHaveLength(1);
  });
});

describe("delete_transaction", () => {
  test("publishes destructive metadata and requires a note in the schema", () => {
    expect(server.annotations.get("delete_transaction")).toMatchObject({
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
    });
    const schema = server.schemas.get("delete_transaction");
    const note = schema?.note as { safeParse(value: unknown): { success: boolean } };
    expect(note.safeParse("").success).toBe(false);
    expect(note.safeParse("Duplicate record").success).toBe(true);
  });

  test("returns a dry-run preflight without requesting approval", async () => {
    await seedDeletableTransaction();
    const result = await callTool("delete_transaction", {
      transactionId: "tx_delete",
      note: "Fully superseded duplicate.",
      dryRun: true,
    });

    expect(result.isError).not.toBe(true);
    expect(payload(result)).toMatchObject({
      dryRun: true,
      transactionId: "tx_delete",
      eligible: true,
      checks: {
        canceled: true,
        budgetNeutral: true,
        activeItemIds: [],
        invoiceReferenceIds: [],
        lineageFromEdgeIds: [],
        lineageToEdgeIds: [],
      },
    });
    expect(server.elicitations).toHaveLength(0);
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/tx_delete`)).not.toBeNull();
  });

  test("deletes an eligible transaction only after elicitation and preserves the full tombstone", async () => {
    await seedDeletableTransaction();
    approveDeletion("tx_delete");

    const result = await callTool("delete_transaction", {
      transactionId: "tx_delete",
      note: "Fully superseded duplicate from the Martinique cleanup.",
      dryRun: false,
    });

    expect(result.isError).not.toBe(true);
    expect(payload(result)).toMatchObject({
      deleted: true,
      alreadyDeleted: false,
      transactionId: "tx_delete",
      tombstoneId: "tx_delete",
      deletionNote: "Fully superseded duplicate from the Martinique cleanup.",
      actor: { uid: TEST_USER_ID, accountId: TEST_ACCOUNT_ID },
    });
    expect(server.elicitations).toHaveLength(1);
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/tx_delete`)).toBeNull();

    const tombstone = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactionDeletionTombstones/tx_delete`
    );
    expect(tombstone).toMatchObject({
      schemaVersion: 1,
      kind: "transaction-deletion",
      transactionId: "tx_delete",
      accountId: TEST_ACCOUNT_ID,
      deletionNote: "Fully superseded duplicate from the Martinique cleanup.",
      actor: { uid: TEST_USER_ID, accountId: TEST_ACCOUNT_ID },
      approval: {
        mechanism: "mcp-form-elicitation",
        scope: "single",
        confirmationPhrase: "DELETE",
        displayedTransactionIds: ["tx_delete"],
        approvedByUid: TEST_USER_ID,
      },
      checks: {
        canceled: true,
        budgetNeutral: true,
        invoiceReferenceIds: [],
        lineageFromEdgeIds: [],
        lineageToEdgeIds: [],
      },
      transactionSnapshot: {
        id: "tx_delete",
        type: "Purchase",
        status: "canceled",
        amountCents: 12_345,
        notes: "Original user prose must survive in the tombstone.",
      },
    });
    expect(tombstone?.deletedAt).toBeDefined();
    expect((tombstone?.approval as Record<string, unknown>)?.approvedAt).toBeDefined();
  });

  test("rejects missing notes before preflight or approval", async () => {
    await seedDeletableTransaction();
    approveDeletion("tx_delete");
    const result = await callTool("delete_transaction", {
      transactionId: "tx_delete",
      note: "",
      dryRun: false,
    });
    expect(payload(result).error.code).toBe("VALIDATION");
    expect(server.elicitations).toHaveLength(0);
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/tx_delete`)).not.toBeNull();
  });

  test("denies deletion when the user does not approve", async () => {
    await seedDeletableTransaction();
    const result = await callTool("delete_transaction", {
      transactionId: "tx_delete",
      note: "Fully superseded duplicate.",
      dryRun: false,
    });
    expect(payload(result).error.code).toBe("PERMISSION");
    expect(server.elicitations).toHaveLength(1);
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/tx_delete`)).not.toBeNull();
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactionDeletionTombstones/tx_delete`)).toBeNull();
  });

  test("fails closed when the MCP client cannot provide elicitation", async () => {
    await seedDeletableTransaction();
    server.setElicitationHandler(async () => {
      throw new Error("Client does not support elicitation");
    });

    const result = await callTool("delete_transaction", {
      transactionId: "tx_delete",
      note: "Fully superseded duplicate.",
      dryRun: false,
    });

    expect(payload(result).error).toMatchObject({
      code: "PERMISSION",
      details: { approvalMechanism: "mcp-form-elicitation" },
    });
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/tx_delete`)).not.toBeNull();
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactionDeletionTombstones/tx_delete`)).toBeNull();
  });

  test("blocks an active transaction even when its amount is zero", async () => {
    await seedTransaction(db, {
      id: "tx_active",
      type: "Purchase",
      status: "completed",
      amountCents: 0,
      itemIds: [],
    });
    approveDeletion("tx_active");
    const result = await callTool("delete_transaction", {
      transactionId: "tx_active",
      note: "Attempted cleanup.",
      dryRun: false,
    });
    const error = payload(result).error;
    expect(error.code).toBe("CONFLICT");
    expect(error.details.blockers).toEqual(
      expect.arrayContaining([expect.objectContaining({ code: "TRANSACTION_NOT_CANCELED" })])
    );
    expect(server.elicitations).toHaveLength(0);
  });

  test("blocks transactions with linked items or item back-references", async () => {
    await seedDeletableTransaction("tx_items");
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/transactions/tx_items`).update({ itemIds: ["item_1"] });
    await seedItem(db, { id: "item_1", transactionId: "tx_items" });

    const result = await callTool("delete_transaction", {
      transactionId: "tx_items",
      note: "Attempted cleanup.",
      dryRun: false,
    });
    const blockers = payload(result).error.details.blockers;
    expect(blockers).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "ACTIVE_ITEM_IDS" }),
      expect.objectContaining({ code: "ITEM_BACK_REFERENCES" }),
    ]));
  });

  test("blocks inventory-entry provenance even when the item is no longer attached", async () => {
    await seedDeletableTransaction("tx_provenance");
    await seedItem(db, {
      id: "item_historical",
      transactionId: "tx_current",
      inventoryEntryTransactionId: "tx_provenance",
    });

    const result = await callTool("delete_transaction", {
      transactionId: "tx_provenance",
      note: "Attempted cleanup.",
      dryRun: false,
    });

    expect(payload(result).error.details.blockers).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: "INVENTORY_PROVENANCE",
          referenceIds: ["item_historical"],
        }),
      ])
    );
  });

  test("blocks invoice source references", async () => {
    await seedDeletableTransaction("tx_invoice");
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/invoices/invoice_1`).set({
      status: "canceled",
      transactionIds: ["tx_invoice"],
      lines: [{
        id: "line_1",
        sourceType: "transaction",
        sourceId: "tx_invoice",
        amountCents: 12345,
        sign: 1,
      }],
    });

    const result = await callTool("delete_transaction", {
      transactionId: "tx_invoice",
      note: "Attempted cleanup.",
      dryRun: false,
    });
    expect(payload(result).error.details.blockers).toEqual(
      expect.arrayContaining([expect.objectContaining({ code: "INVOICE_REFERENCES", referenceIds: ["invoice_1"] })])
    );
  });

  test("blocks invoice settlement transactions", async () => {
    await seedDeletableTransaction("tx_settlement");
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/transactions/tx_settlement`).update({
      settlementInvoiceId: "invoice_paid",
      settlementInvoiceLineIds: ["line_paid"],
    });
    const result = await callTool("delete_transaction", {
      transactionId: "tx_settlement",
      note: "Attempted cleanup.",
      dryRun: false,
    });
    expect(payload(result).error.details.blockers).toEqual(
      expect.arrayContaining([expect.objectContaining({ code: "SETTLEMENT_REFERENCE", referenceIds: ["invoice_paid"] })])
    );
  });

  test("blocks settlement references stored on invoice lines", async () => {
    await seedDeletableTransaction("tx_line_settlement");
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/invoices/invoice_paid`).set({
      status: "paid",
      lines: [{
        id: "line_paid",
        sourceType: "manual",
        amountCents: 12345,
        sign: 1,
        settlementTransactionIds: ["tx_line_settlement"],
      }],
    });

    const result = await callTool("delete_transaction", {
      transactionId: "tx_line_settlement",
      note: "Attempted cleanup.",
      dryRun: false,
    });

    expect(payload(result).error.details.blockers).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: "INVOICE_REFERENCES", referenceIds: ["invoice_paid"] }),
      ])
    );
  });

  test("blocks movement lineage", async () => {
    await seedDeletableTransaction("tx_lineage");
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/lineageEdges/edge_1`).set({
      itemId: "historical_item",
      fromTransactionId: "tx_lineage",
      toTransactionId: "tx_other",
      movementKind: "sold",
    });
    const result = await callTool("delete_transaction", {
      transactionId: "tx_lineage",
      note: "Attempted cleanup.",
      dryRun: false,
    });
    expect(payload(result).error.details.blockers).toEqual(
      expect.arrayContaining([expect.objectContaining({ code: "MOVEMENT_LINEAGE", referenceIds: ["edge_1"] })])
    );
  });

  test("blocks attached files", async () => {
    await seedDeletableTransaction("tx_attachment");
    await db.doc(`accounts/${TEST_ACCOUNT_ID}/transactions/tx_attachment`).update({
      receiptImages: [{ url: "https://example.test/receipt.jpg" }],
    });
    const result = await callTool("delete_transaction", {
      transactionId: "tx_attachment",
      note: "Attempted cleanup.",
      dryRun: false,
    });
    expect(payload(result).error.details.blockers).toEqual(
      expect.arrayContaining([expect.objectContaining({ code: "ATTACHMENTS" })])
    );
  });

  test("retries are idempotent and return the original receipt without another approval", async () => {
    await seedDeletableTransaction("tx_retry");
    approveDeletion("tx_retry");
    const args = {
      transactionId: "tx_retry",
      note: "Fully superseded duplicate.",
      dryRun: false,
    };
    const first = payload(await callTool("delete_transaction", args));
    const firstTombstone = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactionDeletionTombstones/tx_retry`
    );
    const second = payload(await callTool("delete_transaction", args));
    const secondTombstone = await getDocData(
      db,
      `accounts/${TEST_ACCOUNT_ID}/transactionDeletionTombstones/tx_retry`
    );

    expect(first.alreadyDeleted).toBe(false);
    expect(second.alreadyDeleted).toBe(true);
    expect(server.elicitations).toHaveLength(1);
    expect(secondTombstone).toEqual(firstTombstone);
  });

  test("rechecks references atomically after approval and denies a stale preflight", async () => {
    await seedDeletableTransaction("tx_race");
    server.setElicitationHandler(async () => {
      await db.doc(`accounts/${TEST_ACCOUNT_ID}/lineageEdges/edge_after_preflight`).set({
        itemId: "historical_item",
        fromTransactionId: "tx_race",
        movementKind: "sold",
      });
      return {
        action: "accept",
        content: { confirmation: "DELETE" },
      };
    });

    const result = await callTool("delete_transaction", {
      transactionId: "tx_race",
      note: "Fully superseded duplicate.",
      dryRun: false,
    });

    expect(payload(result).error).toMatchObject({
      code: "CONFLICT",
      message: "Transaction changed after approval; deletion was not performed.",
    });
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/tx_race`)).not.toBeNull();
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactionDeletionTombstones/tx_race`)).toBeNull();
  });
});

describe("delete_transactions", () => {
  test("publishes destructive metadata and requires a bounded batch plus note", () => {
    expect(server.annotations.get("delete_transactions")).toMatchObject({
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
    });
    const schema = server.schemas.get("delete_transactions");
    const ids = schema?.transactionIds as { safeParse(value: unknown): { success: boolean } };
    const note = schema?.note as { safeParse(value: unknown): { success: boolean } };
    expect(ids.safeParse(["tx_one"]).success).toBe(false);
    expect(ids.safeParse(["tx_one", "tx_two"]).success).toBe(true);
    expect(ids.safeParse(Array.from({ length: 21 }, (_, index) => `tx_${index}`)).success).toBe(false);
    expect(note.safeParse("").success).toBe(false);
  });

  test("returns the exact dry-run batch without requesting approval", async () => {
    await seedDeletableTransaction("tx_batch_1");
    await seedDeletableTransaction("tx_batch_2");

    const result = await callTool("delete_transactions", {
      transactionIds: ["tx_batch_1", "tx_batch_2"],
      note: "Duplicate import batch superseded by the verified records.",
      dryRun: true,
    });

    expect(result.isError).not.toBe(true);
    expect(payload(result)).toMatchObject({
      dryRun: true,
      transactionIds: ["tx_batch_1", "tx_batch_2"],
      requestedCount: 2,
      eligibleCount: 2,
      alreadyDeletedCount: 0,
      allEligible: true,
      transactions: [
        { transactionId: "tx_batch_1", eligible: true },
        { transactionId: "tx_batch_2", eligible: true },
      ],
    });
    expect(server.elicitations).toHaveLength(0);
  });

  test("deletes an exact batch atomically after one DELETE approval", async () => {
    await seedDeletableTransaction("tx_batch_1");
    await seedDeletableTransaction("tx_batch_2");
    approveDeletion();

    const result = await callTool("delete_transactions", {
      transactionIds: ["tx_batch_1", "tx_batch_2"],
      note: "Duplicate import batch superseded by the verified records.",
      dryRun: false,
    });

    expect(result.isError).not.toBe(true);
    expect(payload(result)).toMatchObject({
      deleted: true,
      batch: true,
      transactionIds: ["tx_batch_1", "tx_batch_2"],
      requestedCount: 2,
      deletedCount: 2,
      alreadyDeletedCount: 0,
    });
    expect(server.elicitations).toHaveLength(1);
    expect(JSON.stringify(server.elicitations[0])).toContain("tx_batch_1");
    expect(JSON.stringify(server.elicitations[0])).toContain("tx_batch_2");
    expect(JSON.stringify(server.elicitations[0])).toContain("Type exactly: DELETE");

    for (const id of ["tx_batch_1", "tx_batch_2"]) {
      expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/${id}`)).toBeNull();
      const tombstone = await getDocData(
        db,
        `accounts/${TEST_ACCOUNT_ID}/transactionDeletionTombstones/${id}`
      );
      expect(tombstone).toMatchObject({
        transactionId: id,
        deletionNote: "Duplicate import batch superseded by the verified records.",
        approval: {
          mechanism: "mcp-form-elicitation",
          scope: "batch",
          confirmationPhrase: "DELETE",
          displayedTransactionIds: ["tx_batch_1", "tx_batch_2"],
          displayedTransactionCount: 2,
          approvedByUid: TEST_USER_ID,
        },
      });
    }
  });

  test("rejects a missing note and duplicate IDs before approval", async () => {
    await seedDeletableTransaction("tx_batch_1");
    await seedDeletableTransaction("tx_batch_2");
    approveDeletion();

    const missingNote = await callTool("delete_transactions", {
      transactionIds: ["tx_batch_1", "tx_batch_2"],
      note: " ",
      dryRun: false,
    });
    expect(payload(missingNote).error.code).toBe("VALIDATION");

    const duplicateIds = await callTool("delete_transactions", {
      transactionIds: ["tx_batch_1", "tx_batch_1"],
      note: "Attempted duplicate batch.",
      dryRun: false,
    });
    expect(payload(duplicateIds).error.code).toBe("VALIDATION");
    expect(server.elicitations).toHaveLength(0);
  });

  test("denies the entire batch when approval is declined", async () => {
    await seedDeletableTransaction("tx_batch_1");
    await seedDeletableTransaction("tx_batch_2");

    const result = await callTool("delete_transactions", {
      transactionIds: ["tx_batch_1", "tx_batch_2"],
      note: "Duplicate import batch.",
      dryRun: false,
    });

    expect(payload(result).error.code).toBe("PERMISSION");
    expect(server.elicitations).toHaveLength(1);
    for (const id of ["tx_batch_1", "tx_batch_2"]) {
      expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/${id}`)).not.toBeNull();
      expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactionDeletionTombstones/${id}`)).toBeNull();
    }
  });

  test("blocks the entire batch before approval when any transaction is unsafe", async () => {
    await seedDeletableTransaction("tx_batch_safe");
    await seedTransaction(db, {
      id: "tx_batch_active",
      type: "Purchase",
      status: "completed",
      amountCents: 0,
      itemIds: [],
    });
    approveDeletion();

    const result = await callTool("delete_transactions", {
      transactionIds: ["tx_batch_safe", "tx_batch_active"],
      note: "Attempted mixed cleanup batch.",
      dryRun: false,
    });

    expect(payload(result).error).toMatchObject({
      code: "CONFLICT",
      message: "Batch transaction deletion safety checks failed; nothing was deleted.",
    });
    expect(server.elicitations).toHaveLength(0);
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/tx_batch_safe`)).not.toBeNull();
    expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/tx_batch_active`)).not.toBeNull();
  });

  test("atomically rechecks every transaction after approval and deletes none on a race", async () => {
    await seedDeletableTransaction("tx_batch_1");
    await seedDeletableTransaction("tx_batch_2");
    server.setElicitationHandler(async () => {
      await db.doc(`accounts/${TEST_ACCOUNT_ID}/lineageEdges/edge_batch_race`).set({
        itemId: "historical_item",
        fromTransactionId: "tx_batch_2",
        movementKind: "sold",
      });
      return { action: "accept", content: { confirmation: "DELETE" } };
    });

    const result = await callTool("delete_transactions", {
      transactionIds: ["tx_batch_1", "tx_batch_2"],
      note: "Duplicate import batch.",
      dryRun: false,
    });

    expect(payload(result).error).toMatchObject({
      code: "CONFLICT",
      message: "The batch changed after approval; nothing was deleted.",
    });
    for (const id of ["tx_batch_1", "tx_batch_2"]) {
      expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactions/${id}`)).not.toBeNull();
      expect(await getDocData(db, `accounts/${TEST_ACCOUNT_ID}/transactionDeletionTombstones/${id}`)).toBeNull();
    }
  });

  test("retries return the original batch receipts without another approval", async () => {
    await seedDeletableTransaction("tx_batch_1");
    await seedDeletableTransaction("tx_batch_2");
    approveDeletion();
    const args = {
      transactionIds: ["tx_batch_1", "tx_batch_2"],
      note: "Duplicate import batch.",
      dryRun: false,
    };

    const first = payload(await callTool("delete_transactions", args));
    const second = payload(await callTool("delete_transactions", args));

    expect(first.deletedCount).toBe(2);
    expect(second).toMatchObject({
      deleted: true,
      deletedCount: 0,
      alreadyDeletedCount: 2,
    });
    expect(server.elicitations).toHaveLength(1);
  });
});
