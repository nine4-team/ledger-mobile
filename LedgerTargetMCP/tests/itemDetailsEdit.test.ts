import assert from "node:assert/strict";
import test from "node:test";
import { SupabaseInventorySaleService } from "../src/inventorySale.js";
import { createTargetServer } from "../src/server.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { itemDetailsEditInputSchema, makeItemDetailsEditRequest, validateItemDetailsEditResult } from "../src/itemDetailsEdit.js";

const context = { accountId: "account", principalId: "member", accessToken: "user-token" };
const input = { operationUUID: "11111111-2222-3333-4444-555555555555", clientCreatedAtMilliseconds: 123000,
  payload: { items: [{ itemId: "item", expectedRevision: "9223372036854775806" }],
    changes: { sku: null, notes: "", bookmark: false } } };
test("registered tool uses bound user transport and surfaces rejection", async () => {
  const request = makeItemDetailsEditRequest(input, context);
  let calls = 0;
  const service = new SupabaseInventorySaleService(new URL("https://target.invalid"), "public-key", async (url, init) => {
    calls++;
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_edit_item_details");
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    assert.equal(init?.redirect, "error");
    assert.deepEqual(JSON.parse(init?.body as string), { p_command: request.commandJSON });
    return Response.json({ operation_id: request.operationId, account_id: "account", actor_principal_id: "member",
      subject_id: "item", command_type: "edit_item_details", contract_version: "item-details-edit-v1",
      command_fingerprint: request.fingerprint, envelope_sha256: request.fingerprint, request_sha256: null,
      client_created_at_ms: 123000, server_received_at_ms: 124000, completed_at_ms: 124000,
      phase: "rejected", result_code: null, error_code: "item_edit_stale" });
  });
  const server = createTargetServer({ async read() { throw new Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, undefined, undefined, undefined,
    undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, service);
  const client = new Client({ name: "details-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    assert.ok((await client.listTools()).tools.some(tool => tool.name === "edit_item_details"));
    const result = await client.callTool({ name: "edit_item_details", arguments: input });
    assert.equal(result.isError, true);
    assert.match(JSON.stringify(result.content), /item_edit_stale/);
    await assert.rejects(service.applyItemDetailsEdit(request, { ...context, accountId: "other" }));
    await assert.rejects(service.applyItemDetailsEdit(request, { ...context, accessToken: "" }));
    assert.equal(calls, 1, "Denied scope/credentials must not reach transport");
  } finally { await client.close(); await server.close(); }
});
test("details wire distinguishes omitted, cleared, empty and false", () => {
  const request = makeItemDetailsEditRequest(input, context), wire = JSON.parse(request.commandJSON);
  assert.deepEqual(wire.changes, input.payload.changes);
  // Shared with native sharedMCPDigest: same identity, exact revision and null/false wire.
  assert.equal(request.fingerprint, "95f10367ab70297bf29a4ad499b22836f7d3cb1dca37624a74cca08382fde647");
  assert.equal(wire.items[0].expectedRevision, "9223372036854775806");
  assert.equal(makeItemDetailsEditRequest(structuredClone(input), context).fingerprint, request.fingerprint);
  assert.notEqual(makeItemDetailsEditRequest(input, { ...context, accountId: "other" }).operationId, request.operationId);
});
test("details refuses money, empty edits, malformed revisions and bulk rename", () => {
  for (const changes of [{}, { amount: 1 }, { name: "bad\0text" }])
    assert.equal(itemDetailsEditInputSchema.safeParse({ ...input, payload: { ...input.payload, changes } }).success, false);
  for (const expectedRevision of ["0", "-1", "9223372036854775807", "1.0"])
    assert.equal(itemDetailsEditInputSchema.safeParse({ ...input, payload: { ...input.payload, items: [{ itemId: "item", expectedRevision }] } }).success, false);
  const items = [{ itemId: "a", expectedRevision: "1" }, { itemId: "b", expectedRevision: "1" }];
  assert.equal(itemDetailsEditInputSchema.safeParse({ ...input, payload: { items, changes: { name: "x" } } }).success, false);
  assert.equal(itemDetailsEditInputSchema.safeParse({ ...input, payload: { items, changes: { status: null } } }).success, true);
});
test("details receipt binds exact identity and known terminal outcome", () => {
  const request = makeItemDetailsEditRequest(input, context);
  const valid = { operation_id: request.operationId, account_id: "account", actor_principal_id: "member",
    subject_id: "item", command_type: "edit_item_details", contract_version: "item-details-edit-v1",
    command_fingerprint: request.fingerprint, envelope_sha256: request.fingerprint, request_sha256: null,
    client_created_at_ms: 123000, server_received_at_ms: 124000, completed_at_ms: 124000,
    phase: "applied", result_code: "item_details_updated", error_code: null };
  assert.equal(validateItemDetailsEditResult(valid, request).phase, "applied");
  for (const key of ["account_id", "actor_principal_id", "subject_id", "operation_id", "command_fingerprint", "result_code"])
    assert.throws(() => validateItemDetailsEditResult({ ...valid, [key]: "wrong" }, request));
  assert.equal(validateItemDetailsEditResult({ ...valid, phase: "rejected", result_code: null, error_code: "item_edit_stale" }, request).phase, "rejected");
});
