import assert from "node:assert/strict";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { SupabaseTransactionDetailReader } from "../src/transactionDetailRead.js";
import { makeTransactionDetailsEditRequest, transactionDetailsEditInputSchema, validateTransactionDetailsEditResult,
  type TransactionDetailsEditRequest } from "../src/transactionDetailsEdit.js";

const context = { accountId: "account", principalId: "member",
  accessToken: `e30.${Buffer.from(JSON.stringify({ role: "authenticated" })).toString("base64url")}.signature` };
const input = () => ({ operationUUID: "11111111-2222-3333-4444-555555555555", clientCreatedAtMilliseconds: 123000,
  payload: { transactionId: "transaction", scopeKind: "project" as const, projectId: "project", clientId: "client",
    expectedRevision: "9223372036854775806", changes: { source: null, notes: "", hasEmailReceipt: false } } });
function receipt(request: TransactionDetailsEditRequest) {
  return { operation_id: request.operationId, account_id: request.accountId, actor_principal_id: request.actorPrincipalId,
    command_type: "edit_transaction_details", contract_version: "transaction-details-edit-v1",
    command_fingerprint: request.fingerprint, envelope_sha256: request.fingerprint, request_sha256: null,
    subject_id: request.transactionId, phase: "applied", result_code: "transaction_details_updated", error_code: null,
    client_created_at_ms: request.createdAtMs, server_received_at_ms: 124000, completed_at_ms: 124000 };
}
test("encoded byte limit includes envelope, Unicode and JSON escaping", () => {
  const make = (notes: string) => makeTransactionDetailsEditRequest({ ...input(),
    payload: { ...input().payload, changes: { notes } } }, context);
  const remaining = 4 * 1024 * 1024 - Buffer.byteLength(make("").commandJSON);
  assert.equal(Buffer.byteLength(make("a".repeat(remaining)).commandJSON), 4 * 1024 * 1024);
  for (const notes of ["a".repeat(remaining + 1), "é".repeat(Math.floor(remaining / 2) + 1),
    "\n".repeat(Math.floor(remaining / 2) + 1)]) {
    assert.throws(() => make(notes), { code: "transaction_edit_payload_too_large" });
  }
});
test("sparse edit wire preserves scope, exact revision, null, empty text and false", () => {
  const request = makeTransactionDetailsEditRequest(input(), context), wire = JSON.parse(request.commandJSON);
  assert.equal(request.fingerprint, "928e65eaf35551d4dd2e406a1f8cb06aab28f135fca887101276bbd167358a1d");
  assert.equal(wire.expectedRevision, "9223372036854775806");
  assert.deepEqual(wire.changes, { source: null, notes: "", hasEmailReceipt: false });
  assert.equal(wire.accountId, context.accountId);
  assert.equal(wire.actorPrincipalId, context.principalId);
  assert.deepEqual(makeTransactionDetailsEditRequest(input(), context), request);
  assert.notEqual(makeTransactionDetailsEditRequest(input(), { ...context, accountId: "other" }).operationId, request.operationId);
  for (const payload of [{ ...input().payload, changes: {} }, { ...input().payload, changes: { amount: "1" } },
    { ...input().payload, changes: { notes: "bad\0text" } }, { ...input().payload, projectId: null },
    { ...input().payload, scopeKind: "business_inventory" }, { ...input().payload, changes: { hasEmailReceipt: null } }]) {
    assert.equal(transactionDetailsEditInputSchema.safeParse({ ...input(), payload }).success, false);
  }
  for (const expectedRevision of ["0", "-1", "01", "1\n", "9223372036854775807"]) {
    assert.equal(transactionDetailsEditInputSchema.safeParse({ ...input(), payload: { ...input().payload, expectedRevision } }).success, false);
  }
  assert.equal(transactionDetailsEditInputSchema.safeParse({ ...input(), accountId: "other" }).success, false);
});
test("receipt binds every identity, digest and terminal outcome", () => {
  const request = makeTransactionDetailsEditRequest(input(), context), valid = receipt(request);
  assert.equal(validateTransactionDetailsEditResult(valid, request).phase, "applied");
  for (const field of ["operation_id", "account_id", "actor_principal_id", "command_type", "contract_version",
    "command_fingerprint", "envelope_sha256", "request_sha256", "subject_id", "phase", "result_code", "error_code"]) {
    assert.throws(() => validateTransactionDetailsEditResult({ ...valid, [field]: "wrong" }, request),
      { code: "transaction_edit_result_mismatch" });
  }
  for (const [field, value] of [["client_created_at_ms", 123001], ["server_received_at_ms", -1], ["completed_at_ms", 123999]]) {
    assert.throws(() => validateTransactionDetailsEditResult({ ...valid, [field as string]: value }, request));
  }
  for (const error_code of ["transaction_edit_stale", "transaction_edit_integrity_conflict"]) {
    assert.equal(validateTransactionDetailsEditResult({ ...valid, phase: "rejected", result_code: null, error_code }, request).phase, "rejected");
  }
});
test("existing Transaction adapter sends authenticated edit and rejects foreign request", async () => {
  let calls = 0;
  const request = makeTransactionDetailsEditRequest(input(), context);
  const service = new SupabaseTransactionDetailReader(new URL("https://example.supabase.co"), "sb_publishable_test", async (url, init) => {
    calls++;
    assert.equal(new URL(String(url)).pathname, "/rest/v1/rpc/spike_edit_transaction_details");
    assert.equal(init?.redirect, "error");
    assert.equal(new Headers(init?.headers).get("Authorization"), `Bearer ${context.accessToken}`);
    assert.deepEqual(JSON.parse(String(init?.body)), { p_command: request.commandJSON });
    return Response.json(receipt(request));
  });
  await service.applyTransactionDetailsEdit(request, context);
  await assert.rejects(service.applyTransactionDetailsEdit(request, { ...context, accountId: "other" }), { code: "account_not_authorized" });
  assert.equal(calls, 1);
});
test("MCP exposes descriptive edit only when the adapter supports it", async () => {
  let calls = 0;
  const server = createTargetServer({ read: async () => assert.fail("wrong reader") }, context, undefined, undefined, undefined, {
    read: async () => assert.fail("wrong reader"),
    applyTransactionDetailsEdit: async request => { calls++; return receipt(request); },
  });
  const client = new Client({ name: "transaction-edit-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const tool = (await client.listTools()).tools.find(row => row.name === "edit_transaction_details");
    assert.equal(tool?.annotations?.readOnlyHint, false);
    assert.equal((await client.callTool({ name: tool!.name, arguments: input() })).isError, undefined);
    assert.equal((await client.callTool({ name: tool!.name, arguments: { ...input(), accountId: "other" } })).isError, true);
    assert.equal(calls, 1);
  } finally { await client.close(); await server.close(); }
});
