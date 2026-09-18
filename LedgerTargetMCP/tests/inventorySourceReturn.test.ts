import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { makeInventorySourceReturnRequest, validateInventorySourceReturnReview, validateInventorySourceReturnResult,
  inventorySourceReturnTool, type InventorySourceReturnInput } from "../src/inventorySourceReturn.js";
import { SupabaseInventorySaleService, makeInventorySaleRequest } from "../src/inventorySale.js";
const context = { accountId: "account", principalId: "member", accessToken: "user-token" };
const input: InventorySourceReturnInput = { operationUUID: "11111111-2222-3333-4444-555555555555",
  clientCreatedAtMilliseconds: 1000000, payload: { projectId: "project", items: [{ itemId: "item", placementId: "old",
    inventoryEntryId: "entry", projectPlacementId: "new", occurrenceId: "charge" }] } };
const request = makeInventorySourceReturnRequest(input, context);
test("Swift and MCP share exact source return identity and wire fingerprint", () => {
  const fixture = JSON.parse(readFileSync(new URL("./fixtures/inventory-source-return.json", import.meta.url), "utf8"));
  const actual = makeInventorySourceReturnRequest(fixture.input, { ...context, accountId: fixture.accountId, principalId: fixture.principalId });
  assert.equal(actual.operationId, fixture.operationId);
  assert.equal(actual.fingerprint, fixture.fingerprint);
});
const review = () => ({ accountId: "account", principalId: "member", projectId: "project", items: [{ itemId: "item",
  placementId: "old", inventoryEntryId: "entry", sourceProjectId: "project", sourceCategoryId: "category",
  amountMinorUnits: "9007199254740993", currency: "USD" }] });
const terminal = () => ({ operation_id: request.operationId, account_id: "account", actor_principal_id: "member",
  command_type: "return_inventory_to_source", contract_version: "return-inventory-to-source-v1", subject_id: "project",
  command_fingerprint: request.fingerprint, envelope_sha256: request.fingerprint, request_sha256: null,
  phase: "applied", result_code: "inventory_items_returned_to_source", error_code: null,
  client_created_at_ms: 1000000, server_received_at_ms: 2000000, completed_at_ms: 2000001 });
test("identity-only source return has stable canonical bytes; caller cannot reprice or replace category", () => {
  assert.deepEqual(makeInventorySourceReturnRequest(input, context), request);
  for (const key of ["amountMinorUnits", "categoryId", "sourceProjectId"]) {
    assert.throws(() => makeInventorySourceReturnRequest({ ...input, payload: { ...input.payload,
      items: [{ ...input.payload.items[0], [key]: "other" }] } } as InventorySourceReturnInput, context));
  }
  assert.throws(() => makeInventorySourceReturnRequest({ ...input, payload: { ...input.payload,
    items: [input.payload.items[0], input.payload.items[0]] } }, context));
});
test("review retains exact per-Item money and fails closed for substituted or mixed source", () => {
  assert.equal(validateInventorySourceReturnReview(review(), { itemIds: ["item"] }, context).items[0].amountMinorUnits, "9007199254740993");
  for (const value of [{ ...review(), accountId: "other" }, { ...review(), projectId: "other" },
    { ...review(), items: [{ ...review().items[0], amountMinorUnits: "0" }] },
    { ...review(), items: [{ ...review().items[0], currency: "usd" }] }]) {
    assert.throws(() => validateInventorySourceReturnReview(value, { itemIds: ["item"] }, context));
  }
  assert.throws(() => validateInventorySourceReturnReview(review(), { itemIds: ["other"] }, context));
  assert.throws(() => validateInventorySourceReturnReview({ ...review(), items: [review().items[0],
    { ...review().items[0], itemId: "second", placementId: "second-old", inventoryEntryId: "second-entry", sourceProjectId: "other" }] },
    { itemIds: ["item","second"] }, context));
});
test("terminal response verifies exact request binding and rejects forged success", async () => {
  assert.equal(validateInventorySourceReturnResult(terminal(), request).phase, "applied");
  assert.throws(() => validateInventorySourceReturnResult({ ...terminal(), command_fingerprint: "wrong" }, request));
  assert.equal((await inventorySourceReturnTool(input, context, { applySourceReturn: async () => terminal(),
    reviewSourceReturn: async () => review() })).phase, "applied");
});
test("existing authenticated transport uses same source-only RPC and ordinary Sell stays independent", async () => {
  const service = new SupabaseInventorySaleService(new URL("https://target.invalid"), "public-key", async (url, init) => {
    assert.equal(new URL(String(url)).pathname, "/rest/v1/rpc/spike_return_inventory_to_source");
    assert.equal(JSON.parse(String(init?.body)).p_command, request.commandJSON);
    assert.equal((init?.headers as Record<string,string>).Authorization, "Bearer user-token");
    return new Response(JSON.stringify(terminal()), { status: 200 });
  });
  assert.equal((await inventorySourceReturnTool(input, context, service)).phase, "applied");
  const sale = makeInventorySaleRequest({ operationUUID: input.operationUUID, clientCreatedAtMilliseconds: 1000000,
    payload: { projectId: "mason", currency: "USD", items: [{ itemId: "item", placementId: "old", priceRevision: "0",
      reviewedPriceMinorUnits: "500", newPlacementId: "sale-new", occurrenceId: "sale-charge" }] } }, context);
  assert.equal(JSON.parse(sale.commandJSON).projectId, "mason");
  assert.notEqual(sale.operationId, request.operationId);
});
test("MCP advertises separate source review/return and reports authoritative rejection", async () => {
  const args: Parameters<typeof createTargetServer> = [{ read: async () => { throw Error("unused"); } }, context];
  args[21] = { reviewSourceReturn: async () => review(), applySourceReturn: async () => ({ ...terminal(),
    phase: "rejected", result_code: null, error_code: "source_return_placement_stale" }) };
  const server = createTargetServer(...args), client = new Client({ name: "source-return-test", version: "1" });
  const [a,b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    assert.ok((await client.listTools()).tools.some(tool => tool.name === "return_inventory_to_source"));
    const reviewed = await client.callTool({ name: "review_inventory_source_return", arguments: { itemIds: ["item"] } });
    assert.notEqual(reviewed.isError, true); assert.match(JSON.stringify(reviewed.content), /9007199254740993/);
    const result = await client.callTool({ name: "return_inventory_to_source", arguments: input });
    assert.equal(result.isError, true); assert.match(JSON.stringify(result.content), /source_return_placement_stale/);
  } finally { await client.close(); await server.close(); }
});
