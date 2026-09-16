import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { validateItemPriceEditReview, makeItemPriceEditRequest, validateItemPriceEditResult,
  itemPriceEditTool, type ItemPriceEditInput } from "../src/itemPriceEdit.js";
import { SupabaseInventorySaleService } from "../src/inventorySale.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";

const context = { accountId: "account", principalId: "member", accessToken: "user-token" };
const input = { projectId: "project", itemId: "item" };
const review = () => ({ ...input, accountId: "account", principalId: "member",
  placementId: "placement", occurrenceId: "charge", currency: "USD",
  priceRevision: "1", chargeRevision: "2",
  currentPrice: { amountMinorUnits: "9223372036854775807", currency: "USD" },
  purchaseCost: { state: "known", amountMinorUnits: "200", currency: "USD" } });
const edit: ItemPriceEditInput = { operationUUID: "11111111-2222-3333-4444-555555555555",
  clientCreatedAtMilliseconds: 123000, payload: { ...input, placementId: "placement", occurrenceId: "charge",
    expectedPriceRevision: "1", expectedChargeRevision: "2", requestedPriceMinorUnits: "0",
    reviewedPriceMinorUnits: "200", currency: "USD" } };
const request = makeItemPriceEditRequest(edit, context);
const terminal = () => ({ operation_id: request.operationId, account_id: "account", actor_principal_id: "member",
  subject_id: "item", command_type: "edit_uncollected_item_price", contract_version: "item-uncollected-price-edit-v1",
  command_fingerprint: request.fingerprint, envelope_sha256: request.fingerprint, request_sha256: null,
  client_created_at_ms: 123000, server_received_at_ms: 124000, completed_at_ms: 124000,
  phase: "applied", result_code: "item_price_updated", error_code: null });

test("Swift and MCP share price-edit identity and exact wire digest", () => {
  const fixture = JSON.parse(readFileSync(new URL("./fixtures/item-price-edit.json", import.meta.url), "utf8"));
  const actual = makeItemPriceEditRequest(fixture.input, { ...context,
    accountId: fixture.accountId, principalId: fixture.principalId });
  assert.equal(actual.operationId, fixture.operationId);
  assert.equal(actual.fingerprint, fixture.fingerprint);
});

test("price commands preserve all fourteen exact fields and retry bytes", () => {
  assert.deepEqual(makeItemPriceEditRequest(edit, context), request);
  const fields = JSON.parse(request.commandJSON);
  assert.equal(Object.keys(fields).length, 14);
  assert.ok(Object.values(fields).every(value => typeof value === "string"));
  assert.notEqual(makeItemPriceEditRequest(edit, { ...context, accountId: "other" }).operationId, request.operationId);
  const max = makeItemPriceEditRequest({ ...edit, payload: { ...edit.payload,
    requestedPriceMinorUnits: "9223372036854775807", reviewedPriceMinorUnits: "9223372036854775807" } }, context);
  assert.equal(JSON.parse(max.commandJSON).requestedPriceMinorUnits, "9223372036854775807");
  for (const patch of [{ reviewedPriceMinorUnits: "0" }, { requestedPriceMinorUnits: "201" },
    { expectedChargeRevision: "0" }, { expectedPriceRevision: "9223372036854775807" },
    { requestedPriceMinorUnits: "01" }, { requestedPriceMinorUnits: "-1" },
    { reviewedPriceMinorUnits: "9223372036854775808" }]) {
    assert.throws(() => makeItemPriceEditRequest({ ...edit, payload: { ...edit.payload, ...patch } }, context));
  }
});
test("price receipts are bound to operation, actor, Item, digest and outcome", () => {
  assert.equal(validateItemPriceEditResult(terminal(), request).phase, "applied");
  assert.equal(validateItemPriceEditResult({ ...terminal(), phase: "rejected", result_code: null,
    error_code: "price_charge_collected" }, request).phase, "rejected");
  for (const patch of [{ operation_id: "other" }, { account_id: "other" }, { actor_principal_id: "other" },
    { subject_id: "other" }, { command_type: "sell_inventory_items" }, { command_fingerprint: "other" },
    { envelope_sha256: "other" }, { request_sha256: "other" }, { client_created_at_ms: 123001 },
    { server_received_at_ms: -1 }, { completed_at_ms: 123999 },
    { phase: "rejected", result_code: null, error_code: "unknown" }]) {
    assert.throws(() => validateItemPriceEditResult({ ...terminal(), ...patch }, request));
  }
});
test("price edit transport sends identical retries, rejects scope before sending", async () => {
  const bodies: unknown[] = [];
  const service = new SupabaseInventorySaleService(new URL("https://target.invalid"), "public-key", async (url, init) => {
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_edit_uncollected_item_price");
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    bodies.push(JSON.parse(init?.body as string));
    return Response.json(terminal());
  });
  await itemPriceEditTool(edit, context, service);
  await itemPriceEditTool(edit, context, service);
  assert.deepEqual(bodies, [{ p_command: request.commandJSON }, { p_command: request.commandJSON }]);
  await assert.rejects(service.applyItemPriceEdit(request, { ...context, accountId: "other" }));
  assert.equal(bodies.length, 2);
});
test("MCP exposes price review/edit and preserves rejection semantics", async () => {
  const service = { reviewItemPriceEdit: async () => review(), applyItemPriceEdit: async () => ({
    ...terminal(), phase: "rejected", result_code: null, error_code: "price_charge_collected" }) };
  const server = createTargetServer({ read: async () => { throw new Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined,
    undefined, undefined, undefined, undefined, undefined, service);
  const client = new Client({ name: "price-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const tools = await client.listTools();
    assert.ok(tools.tools.some(tool => tool.name === "edit_uncollected_item_price"));
    const reviewed = await client.callTool({ name: "review_item_price_edit", arguments: input });
    assert.notEqual(reviewed.isError, true);
    const result = await client.callTool({ name: "edit_uncollected_item_price", arguments: edit });
    assert.equal(result.isError, true);
    assert.match(JSON.stringify(result.content), /price_charge_collected/);
  } finally { await client.close(); await server.close(); }
});

test("price review preserves exact Int64 and distinguishes absent price/cost", () => {
  assert.equal(validateItemPriceEditReview(review(), input, context).currentPrice?.amountMinorUnits,
    "9223372036854775807");
  const absent = validateItemPriceEditReview({ ...review(), currentPrice: null,
    priceRevision: "0", purchaseCost: { state: "absent" } }, input, context);
  assert.equal(absent.currentPrice, null);
  assert.equal(absent.purchaseCost.state, "absent");
});
test("price review rejects foreign, exhausted, ambiguous and malformed evidence", () => {
  for (const patch of [
    { accountId: "other" }, { principalId: "other" }, { projectId: "other" }, { itemId: "other" },
    { chargeRevision: "0" }, { priceRevision: "9223372036854775807" },
    { chargeRevision: "9223372036854775807" }, { priceRevision: "0" }, { currentPrice: null },
    { purchaseCost: { state: "unavailable" } },
    { purchaseCost: { state: "absent", amountMinorUnits: "0" } },
    { purchaseCost: { state: "known", amountMinorUnits: "-1", currency: "USD" } },
    { currentPrice: { amountMinorUnits: "9223372036854775808", currency: "USD" } },
    { currentPrice: { amountMinorUnits: "1", currency: "EUR" } },
    { purchaseCost: { state: "known", amountMinorUnits: "200", currency: "EUR" } },
  ]) assert.throws(() => validateItemPriceEditReview({ ...review(), ...patch }, input, context));
});

test("price review uses existing scoped user transport and validates before publishing", async () => {
  let calls = 0;
  let foreign = false;
  const service = new SupabaseInventorySaleService(new URL("https://target.invalid"), "public-key", async (url, init) => {
    calls++;
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_read_item_price_edit");
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    assert.equal(init?.redirect, "error");
    assert.deepEqual(JSON.parse(init?.body as string), {
      p_account_id: "account", p_project_id: "project", p_item_id: "item",
    });
    return Response.json({ ...review(), accountId: foreign ? "other" : "account" });
  });
  assert.equal((await service.reviewItemPriceEdit(input, context)).itemId, "item");
  foreign = true;
  await assert.rejects(service.reviewItemPriceEdit(input, context));
  await assert.rejects(service.reviewItemPriceEdit({ ...input, itemId: "" }, context));
  await assert.rejects(service.reviewItemPriceEdit(input, { ...context, accessToken: "" }));
  assert.equal(calls, 2);
});
