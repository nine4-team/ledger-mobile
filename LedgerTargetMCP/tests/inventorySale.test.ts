import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { makeInventorySaleRequest, validateInventorySaleResult, validateInventorySaleReview,
  inventorySaleTool, SupabaseInventorySaleService, type InventorySaleInput } from "../src/inventorySale.js";
const context = { accountId: "sale-account", principalId: "sale-member", accessToken: "user-token" };
const input: InventorySaleInput = { operationUUID: "11111111-2222-3333-4444-555555555555",
  clientCreatedAtMilliseconds: 1800000000123, payload: { projectId: "destination", currency: "USD", items: [
    { itemId: "item", placementId: "old", priceRevision: "0", reviewedPriceMinorUnits: "9223372036854775807",
      newPlacementId: "new", occurrenceId: "charge" }] } };
const request = makeInventorySaleRequest(input, context);
test("Swift and MCP share the exact sale wire digest and identity", () => {
  const fixture = JSON.parse(readFileSync(new URL("./fixtures/inventory-sale.json", import.meta.url), "utf8"));
  const actual = makeInventorySaleRequest(fixture.input, { ...context, accountId: fixture.accountId, principalId: fixture.principalId });
  assert.equal(actual.operationId, fixture.operationId);
  assert.equal(actual.fingerprint, fixture.fingerprint);
});
const terminal = () => ({ operation_id: request.operationId, account_id: context.accountId,
  actor_principal_id: context.principalId, subject_id: "destination", command_type: "sell_inventory_items",
  contract_version: "inventory-sale-v1", command_fingerprint: request.fingerprint, envelope_sha256: request.fingerprint,
  request_sha256: null, client_created_at_ms: input.clientCreatedAtMilliseconds,
  server_received_at_ms: 1800000001000, completed_at_ms: 1800000001001,
  phase: "applied", result_code: "inventory_items_sold", error_code: null });
const review = () => ({ accountId: context.accountId, principalId: context.principalId, items: [{ itemId: "item",
  placementId: "old", priceRevision: "0", projectPrice: { state: "absent" }, purchaseCost: { state: "unavailable" } }] });

test("sale retains exact Int64 and stable retry identity; rejects malformed and duplicate selections", () => {
  assert.deepEqual(makeInventorySaleRequest(input, context), request);
  assert.equal(JSON.parse(request.commandJSON).items[0].reviewedPriceMinorUnits, "9223372036854775807");
  for (const price of ["0", "01", "9223372036854775808", "1.00"]) {
    const invalid = structuredClone(input); invalid.payload.items[0].reviewedPriceMinorUnits = price;
    assert.throws(() => makeInventorySaleRequest(invalid, context));
  }
  const duplicate = structuredClone(input); duplicate.payload.items.push(duplicate.payload.items[0]);
  assert.throws(() => makeInventorySaleRequest(duplicate, context));
});
test("review preserves unavailable evidence without leaking hidden cost and denies foreign selections", () => {
  assert.equal(validateInventorySaleReview(review(), ["item"], context).items[0].purchaseCost.state, "unavailable");
  assert.throws(() => validateInventorySaleReview({ ...review(), accountId: "foreign" }, ["item"], context));
  assert.throws(() => validateInventorySaleReview(review(), ["other"], context));
  const hidden = review(); Object.assign(hidden.items[0].purchaseCost, { amountMinorUnits: "100", currency: "USD" });
  assert.throws(() => validateInventorySaleReview(hidden, ["item"], context));
});
test("terminal receipts require exact scope, digest, family, timestamp and outcome", () => {
  assert.equal(validateInventorySaleResult(terminal(), request).phase, "applied");
  for (const [key, value] of Object.entries({ account_id: "foreign", actor_principal_id: "other", subject_id: "other",
    command_fingerprint: "wrong", request_sha256: "wrong", command_type: "manage_categories", completed_at_ms: 0,
    error_code: "unexpected" })) assert.throws(() => validateInventorySaleResult({ ...terminal(), [key]: value }, request));
});
test("HTTP adapter uses user scope and exact command; privileged credentials and foreign requests never send", async () => {
  let calls = 0;
  const service = new SupabaseInventorySaleService(new URL("https://target.invalid"), "public-key", async (url, init) => {
    calls++;
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    assert.equal(init?.redirect, "error");
    if (String(url).endsWith("spike_read_inventory_sale_review")) {
      assert.deepEqual(JSON.parse(init?.body as string), { p_account_id: context.accountId, p_item_ids: ["item"] });
      return Response.json(review());
    }
    assert.deepEqual(JSON.parse(init?.body as string), { p_command: request.commandJSON });
    return Response.json(terminal());
  });
  assert.equal((await inventorySaleTool(input, context, service)).phase, "applied");
  await service.review(["item"], context);
  await assert.rejects(service.apply(request, { ...context, accountId: "foreign" }));
  await assert.rejects(inventorySaleTool(input, { ...context, accessToken: "sb_secret_privileged" }, service));
  assert.equal(calls, 2);
});
test("MCP advertises review and sale; rejected accounting command remains an error", async () => {
  const server = createTargetServer({ read: async () => { throw Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, {
      review: async () => review(), apply: async () => ({ ...terminal(), phase: "rejected", result_code: null, error_code: "sale_placement_stale" }),
    });
  const client = new Client({ name: "sale-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const tools = await client.listTools();
    assert.ok(tools.tools.some(tool => tool.name === "review_inventory_sale"));
    const result = await client.callTool({ name: "sell_inventory_items", arguments: input });
    assert.equal(result.isError, true);
    assert.match(JSON.stringify(result.content), /sale_placement_stale/);
  } finally { await client.close(); await server.close(); }
});
