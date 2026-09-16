import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { makeFeeCreationRequest, validateFeeCreationResult, feeCreationTool, SupabaseFeeCreationService,
  type FeeCreationInput, type FeeCreationRequest } from "../src/feeCreation.js";
const context = { accountId: "account", principalId: "actor", accessToken: "user-token" };
const input: FeeCreationInput = { operationUUID: "00000000-0000-0000-0000-000000000001", clientCreatedAtMilliseconds: 100000,
  payload: { projectId: "project", installmentId: "fee", categoryId: "category", label: "Design fee",
    amountMinorUnits: "9007199254740993", currency: "USD" } };
const result = (r: FeeCreationRequest) => ({ operation_id: r.operationId, account_id: r.accountId,
  actor_principal_id: r.actorPrincipalId, subject_id: r.installmentId, command_type: "create_fee_installment",
  contract_version: "fee-installment-create-v1", command_fingerprint: r.fingerprint, envelope_sha256: r.fingerprint,
  request_sha256: null, client_created_at_ms: r.createdAtMs, server_received_at_ms: r.createdAtMs,
  completed_at_ms: r.createdAtMs, phase: "applied", result_code: "fee_installment_created", error_code: null });
test("Fee exact string wire, absent versus zero order and stable scoped retries", () => {
  const request = makeFeeCreationRequest(input, context);
  assert.deepEqual(makeFeeCreationRequest(structuredClone(input), context), request);
  assert.equal(request.operationId, `fee-create-${createHash("sha256").update("account").digest("hex")}-${input.operationUUID}`);
  const wire = JSON.parse(request.commandJSON);
  assert.ok(Object.values(wire).every(value => typeof value === "string"));
  assert.equal(wire.amountMinorUnits, "9007199254740993"); assert.equal(wire.sortOrder, "");
  assert.equal(JSON.parse(makeFeeCreationRequest({ ...input, payload: { ...input.payload, sortOrder: 0 } }, context).commandJSON).sortOrder, "0");
  assert.notEqual(makeFeeCreationRequest(input, { ...context, accountId: "other" }).operationId, request.operationId);
  for (const amount of ["0", "-1", "01", "1.1", "9223372036854775808"]) {
    assert.throws(() => makeFeeCreationRequest({ ...input, payload: { ...input.payload, amountMinorUnits: amount } }, context));
  }
  for (const sortOrder of [-2147483649, 2147483648, 1.5]) {
    assert.throws(() => makeFeeCreationRequest({ ...input, payload: { ...input.payload, sortOrder } }, context));
  }
  assert.throws(() => makeFeeCreationRequest({ ...input, payload: { ...input.payload, label: " \n" } }, context));
});
test("Fee results bind every identity, digest and outcome", () => {
  const request = makeFeeCreationRequest(input, context), valid = result(request);
  assert.equal(validateFeeCreationResult(valid, request).phase, "applied");
  for (const field of ["operation_id", "account_id", "actor_principal_id", "subject_id", "command_type",
    "contract_version", "command_fingerprint", "envelope_sha256", "request_sha256", "phase", "result_code", "error_code"]) {
    assert.throws(() => validateFeeCreationResult({ ...valid, [field]: "wrong" }, request));
  }
  for (const changes of [{ client_created_at_ms: 0 }, { server_received_at_ms: -1 }, { completed_at_ms: 0 }]) {
    assert.throws(() => validateFeeCreationResult({ ...valid, ...changes }, request));
  }
  for (const error_code of ["fee_invalid_draft", "fee_project_unavailable", "fee_category_unavailable",
    "fee_currency_mismatch", "fee_total_overflow", "fee_total_exceeded", "fee_integrity_conflict"]) {
    assert.equal(validateFeeCreationResult({ ...valid, phase: "rejected", result_code: null, error_code }, request).phase, "rejected");
  }
});
test("Fee transport uses user credentials, exact endpoint/body and blocks mismatched scope", async () => {
  const request = makeFeeCreationRequest(input, context);
  let calls = 0;
  const service = new SupabaseFeeCreationService(new URL("http://127.0.0.1:54321"), "publishable", async (url, init) => {
    calls++; assert.equal(String(url), "http://127.0.0.1:54321/rest/v1/rpc/spike_create_fee_installment");
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    assert.deepEqual(JSON.parse(String(init?.body)), { p_command: request.commandJSON });
    assert.equal(init?.redirect, "error");
    return new Response(JSON.stringify(result(request)));
  });
  assert.equal((await feeCreationTool(input, context, service)).phase, "applied");
  await assert.rejects(service.apply(request, { ...context, accountId: "other" }));
  assert.equal(calls, 1);
});
test("Fee MCP tool is advertised, callable and reports domain rejection", async () => {
  const server = createTargetServer({ read: async () => { throw new Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined,
    { apply: async request => ({ ...result(request), phase: "rejected", result_code: null, error_code: "fee_total_exceeded" }) });
  const client = new Client({ name: "fee-test", version: "1" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport); await client.connect(clientTransport);
  try {
    assert.ok((await client.listTools()).tools.some(tool => tool.name === "create_fee_installment"));
    const response = await client.callTool({ name: "create_fee_installment", arguments: input });
    assert.equal(response.isError, true);
    assert.match(JSON.stringify(response.content), /fee_total_exceeded/);
  } finally { await client.close(); await server.close(); }
});
