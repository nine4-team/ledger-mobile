import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { makeUninvoicedReturnRequest, validateUninvoicedReturnResult, validateUninvoicedReturnReview, uninvoicedReturnTool,
  SupabaseUninvoicedReturnService, type UninvoicedReturnInput } from "../src/uninvoicedReturn.js";

const context = { accountId: "account", principalId: "member", accessToken: "user-token" };
const input: UninvoicedReturnInput = { operationUUID: "11111111-2222-3333-4444-555555555555",
  clientCreatedAtMilliseconds: 1800000000123, payload: { projectId: "project", items: [{
    itemId: "item", placementId: "old", chargeId: "charge", expectedChargeRevision: "9223372036854775806",
    inventoryPlacementId: "new", returnOccurrenceId: "return" }] } };
const request = makeUninvoicedReturnRequest(input, context);
test("Swift and MCP share the return wire fingerprint and operation identity", () => {
  const fixture = JSON.parse(readFileSync(new URL("./fixtures/uninvoiced-return.json", import.meta.url), "utf8"));
  const actual = makeUninvoicedReturnRequest(fixture.input, { ...context, accountId: fixture.accountId, principalId: fixture.principalId });
  assert.equal(actual.operationId, fixture.operationId);
  assert.equal(actual.fingerprint, fixture.fingerprint);
});
const reviewInput = { projectId: "project", itemIds: ["item"] };
const review = () => ({ accountId: "account", principalId: "member", projectId: "project",
  items: [{ itemId: "item", placementId: "old", chargeId: "charge", revision: "1" }] });
test("review validates complete scope and refuses financial fields or substituted Items", async () => {
  assert.deepEqual(validateUninvoicedReturnReview(review(), reviewInput, context), review());
  for (const invalid of [{ ...review(), accountId: "other" }, { ...review(), projectId: "other" },
    { ...review(), items: [] }, { ...review(), items: [{ ...review().items[0], amount: "100" }] },
    { ...review(), items: [{ ...review().items[0], itemId: "other" }] }]) {
    assert.throws(() => validateUninvoicedReturnReview(invalid, reviewInput, context));
  }
  const service = new SupabaseUninvoicedReturnService(new URL("https://target.invalid"), "public-key", async (url, init) => {
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_read_uninvoiced_return_review");
    assert.deepEqual(JSON.parse(init?.body as string), { p_account_id: "account", p_project_id: "project", p_item_ids: ["item"] });
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    return Response.json(review());
  });
  assert.deepEqual(await service.review(reviewInput, context), review());
});
const terminal = () => ({ operation_id: request.operationId, account_id: context.accountId,
  actor_principal_id: context.principalId, subject_id: "project", command_type: "return_uninvoiced_items",
  contract_version: "return-uninvoiced-items-v1", command_fingerprint: request.fingerprint,
  envelope_sha256: request.fingerprint, request_sha256: null, client_created_at_ms: request.createdAtMs,
  server_received_at_ms: 1800000001000, completed_at_ms: 1800000001001,
  phase: "applied", result_code: "uninvoiced_items_returned", error_code: null });

test("return preserves exact revisions and retry identity and rejects ambiguous selection", () => {
  assert.deepEqual(makeUninvoicedReturnRequest(input, context), request);
  assert.equal(JSON.parse(request.commandJSON).items[0].expectedChargeRevision, "9223372036854775806");
  for (const revision of ["0", "01", "9223372036854775807", "1.0", "-1"]) {
    const invalid = structuredClone(input); invalid.payload.items[0].expectedChargeRevision = revision;
    assert.throws(() => makeUninvoicedReturnRequest(invalid, context));
  }
  const duplicate = structuredClone(input); duplicate.payload.items.push(duplicate.payload.items[0]);
  assert.throws(() => makeUninvoicedReturnRequest(duplicate, context));
  const reusedPlacement = structuredClone(input); reusedPlacement.payload.items[0].inventoryPlacementId = "old";
  assert.throws(() => makeUninvoicedReturnRequest(reusedPlacement, context));
});
test("return receipt binds scope, exact request and known terminal outcome", () => {
  assert.equal(validateUninvoicedReturnResult(terminal(), request).phase, "applied");
  for (const [key, value] of Object.entries({ account_id: "foreign", actor_principal_id: "other",
    subject_id: "other", operation_id: "other", command_type: "sell_inventory_items",
    contract_version: "wrong", command_fingerprint: "wrong", envelope_sha256: "wrong",
    request_sha256: "wrong", client_created_at_ms: 0, completed_at_ms: 0, error_code: "unexpected" })) {
    assert.throws(() => validateUninvoicedReturnResult({ ...terminal(), [key]: value }, request));
  }
  assert.equal(validateUninvoicedReturnResult({ ...terminal(), phase: "rejected", result_code: null,
    error_code: "return_charge_invoiced" }, request).phase, "rejected");
});
test("return HTTP adapter uses the shared endpoint and user credentials; invalid scope never sends", async () => {
  let calls = 0;
  const service = new SupabaseUninvoicedReturnService(new URL("https://target.invalid"), "public-key", async (url, init) => {
    calls++;
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_return_uninvoiced_items");
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    assert.equal(init?.redirect, "error");
    assert.deepEqual(JSON.parse(init?.body as string), { p_command: request.commandJSON });
    return Response.json(terminal());
  });
  assert.equal((await uninvoicedReturnTool(input, context, service)).phase, "applied");
  await assert.rejects(service.apply(request, { ...context, accountId: "foreign" }));
  await assert.rejects(uninvoicedReturnTool(input, { ...context, accessToken: "sb_secret_privileged" }, service));
  assert.equal(calls, 1);
});
test("MCP advertises return only with its service and reports authoritative rejection", async () => {
  const server = createTargetServer({ read: async () => { throw Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined,
    undefined, undefined, undefined, undefined, {
      review: async () => review(),
      apply: async () => ({ ...terminal(), phase: "rejected", result_code: null, error_code: "return_charge_invoiced" }),
    });
  const client = new Client({ name: "return-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    assert.ok((await client.listTools()).tools.some(tool => tool.name === "return_uninvoiced_items"));
    const reviewed = await client.callTool({ name: "review_uninvoiced_return", arguments: reviewInput });
    assert.notEqual(reviewed.isError, true);
    assert.match(JSON.stringify(reviewed.content), /charge/);
    const result = await client.callTool({ name: "return_uninvoiced_items", arguments: input });
    assert.equal(result.isError, true);
    assert.match(JSON.stringify(result.content), /return_charge_invoiced/);
  } finally { await client.close(); await server.close(); }
});
