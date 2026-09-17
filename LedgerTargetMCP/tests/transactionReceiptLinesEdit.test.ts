import assert from "node:assert/strict";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { makeTransactionReceiptLinesEditRequest, transactionReceiptLinesEditInputSchema,
  validateTransactionReceiptLinesEditResult } from "../src/transactionReceiptLinesEdit.js";

const context = { accountId: "account", principalId: "principal", accessToken: "unused" };
const line = { id: "source-tax", description: "  Tax refund 🪑  ", magnitudeMinorUnits: "9007199254740993",
  currency: "USD", effect: "decrease" as const, quantity: "-9223372036854775808" };
const input = () => ({ operationUUID: "11111111-2222-3333-4444-555555555555", clientCreatedAtMilliseconds: 123000,
  payload: { transactionId: "transaction", scopeKind: "business_inventory" as const, projectId: null, clientId: null,
    currency: "USD", expectedLines: [line], lines: [] as typeof line[] } });

test("MCP receipt edit invokes the bound adapter and rejects extra authority fields", async () => {
  const authenticated = { ...context,
    accessToken: `e30.${Buffer.from(JSON.stringify({ role: "authenticated" })).toString("base64url")}.signature` };
  let calls = 0;
  const server = createTargetServer({ read: async () => assert.fail("wrong reader") }, authenticated,
    undefined, undefined, undefined, {
      read: async () => assert.fail("wrong reader"),
      applyTransactionReceiptLinesEdit: async (request, boundContext) => {
        calls++;
        assert.deepEqual(boundContext, authenticated);
        assert.deepEqual(request, makeTransactionReceiptLinesEditRequest(input(), authenticated));
        return { operation_id: request.operationId, account_id: request.accountId,
          actor_principal_id: request.actorPrincipalId, subject_id: request.transactionId,
          command_type: "edit_transaction_receipt_lines", contract_version: "transaction-receipt-lines-edit-v1",
          command_fingerprint: request.fingerprint, envelope_sha256: request.fingerprint, request_sha256: null,
          client_created_at_ms: request.createdAtMs, server_received_at_ms: 124000, completed_at_ms: 124000,
          phase: "applied", result_code: "transaction_receipt_lines_updated", error_code: null, receipt_lines_revision: "2" };
      },
    });
  const client = new Client({ name: "receipt-edit-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const tool = (await client.listTools()).tools.find(row => row.name === "edit_transaction_receipt_lines");
    assert.equal(tool?.annotations?.readOnlyHint, false);
    assert.equal(tool?.annotations?.idempotentHint, true);
    const result = await client.callTool({ name: tool!.name, arguments: input() });
    assert.equal(result.isError, undefined);
    assert.equal(JSON.parse((result.content as { text: string }[])[0].text).phase, "applied");
    assert.equal((await client.callTool({ name: tool!.name,
      arguments: { ...input(), accountId: "other" } })).isError, true);
    assert.equal(calls, 1);
  } finally { await client.close(); await server.close(); }
});

test("receipt wire preserves exact source values and retry fingerprint", () => {
  const a = makeTransactionReceiptLinesEditRequest(input(), context);
  assert.equal(a.fingerprint, "4cca4f266dd41bd787736998a3f500a155dfc4cf7667b9fd18939a1733224772");
  assert.deepEqual(a, makeTransactionReceiptLinesEditRequest(input(), context));
  const wire = JSON.parse(a.commandJSON);
  assert.equal(Object.keys(wire).length, 12);
  assert.deepEqual(wire.expectedLines, [{ id: line.id, description: line.description,
    amountMinorUnits: line.magnitudeMinorUnits, effect: line.effect, quantity: line.quantity }]);
  assert.deepEqual(wire.lines, []);
  assert.notEqual(a.fingerprint, makeTransactionReceiptLinesEditRequest(input(), { ...context, accountId: "other" }).fingerprint);
});
test("duplicate identity, cross-currency, NUL and extra money fields are rejected", () => {
  for (const patch of [{ lines: [line, line] }, { currency: "EUR" },
    { lines: [{ ...line, description: "bad\0text" }] }, { amountMinorUnits: "0" }]) {
    assert.equal(transactionReceiptLinesEditInputSchema.safeParse({ ...input(), payload: { ...input().payload, ...patch } }).success, false);
  }
});
test("receipt array byte limit includes Postgres spaces and UTF8", () => {
  const request = (description: string) => makeTransactionReceiptLinesEditRequest({ ...input(),
    payload: { ...input().payload, expectedLines: [], lines: [{ ...line, description }] } }, context);
  const one = JSON.parse(request("x").commandJSON).lines;
  const overhead = Buffer.byteLength(JSON.stringify(one), "utf8") + 9 - 1;
  assert.doesNotThrow(() => request("x".repeat(262144 - overhead)));
  assert.throws(() => request("x".repeat(262145 - overhead)));
  assert.throws(() => request("🪑".repeat(70000)));
});
test("terminal receipt binds identity, digest, phase and timestamps", () => {
  const r = makeTransactionReceiptLinesEditRequest(input(), context);
  const receipt = { operation_id: r.operationId, account_id: r.accountId, actor_principal_id: r.actorPrincipalId,
    subject_id: r.transactionId, command_type: "edit_transaction_receipt_lines", contract_version: "transaction-receipt-lines-edit-v1",
    command_fingerprint: r.fingerprint, envelope_sha256: r.fingerprint, request_sha256: null,
    client_created_at_ms: r.createdAtMs, server_received_at_ms: 124000, completed_at_ms: 124000,
    phase: "applied", result_code: "transaction_receipt_lines_updated", error_code: null, receipt_lines_revision: "9007199254740993" };
  assert.equal(validateTransactionReceiptLinesEditResult(receipt, r).phase, "applied");
  for (const patch of [{ account_id: "other" }, { command_fingerprint: "wrong" }, { phase: "queued" },
    { completed_at_ms: 1 }, { result_code: "wrong" }, ...[null, "0", "01", "9223372036854775808", 2].map(
      receipt_lines_revision => ({ receipt_lines_revision }))]) assert.throws(() => validateTransactionReceiptLinesEditResult({ ...receipt, ...patch }, r));
});
