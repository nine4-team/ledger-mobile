import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { makePaidReturnRequest, paidReturnTool, validatePaidReturnReview, SupabasePaidReturnService,
  type PaidReturnInput } from "../src/paidReturn.js";

const context = { accountId: "account", principalId: "member", accessToken: "user-token" };
const input: PaidReturnInput = { operationUUID: "11111111-2222-3333-4444-555555555555",
  clientCreatedAtMilliseconds: 1800000000123, payload: { projectId: "project", items: [{
    itemId: "item", placementId: "old", chargeId: "charge", paidInvoiceLineId: "line",
    inventoryPlacementId: "new", returnOccurrenceId: "return", creditId: "credit" }] } };
const request = makePaidReturnRequest(input, context);
test("Swift and MCP use the same paid-return operation identity and wire fingerprint", () => {
  const fixture = JSON.parse(readFileSync(new URL("./fixtures/paid-return.json", import.meta.url), "utf8"));
  const actual = makePaidReturnRequest(fixture.input, { ...context, accountId: fixture.accountId, principalId: fixture.principalId });
  assert.equal(actual.operationId, fixture.operationId);
  assert.equal(actual.fingerprint, fixture.fingerprint);
});
const terminal = () => ({ operation_id: request.operationId, account_id: context.accountId,
  actor_principal_id: context.principalId, subject_id: "project", command_type: "return_paid_items",
  contract_version: "return-paid-items-v1", command_fingerprint: request.fingerprint,
  envelope_sha256: request.fingerprint, request_sha256: null, client_created_at_ms: request.createdAtMs,
  server_received_at_ms: 1800000001000, completed_at_ms: 1800000001001,
  phase: "applied", result_code: "paid_items_returned", error_code: null });
const reviewInput = { projectId: "project", itemIds: ["item"] };
const review = { accountId: "account", principalId: "member", projectId: "project", items: [{
  itemId: "item", placementId: "old", chargeId: "charge", paidInvoiceLineId: "line",
  paidAmountMinorUnits: "9223372036854775807", currency: "USD", categoryId: "category" }] };

test("registered MCP paid-return tools preserve review, replay and authoritative rejection", async () => {
  for (const enabled of [false, true]) {
    let calls = 0, reject = false;
    const args: Parameters<typeof createTargetServer> = [{ read: async () => { throw Error("unused"); } }, context];
    if (enabled) args[18] = {
      review: async (selected, identity) => {
        assert.deepEqual(selected, reviewInput); assert.deepEqual(identity, context); return review;
      },
      apply: async (sent, identity) => {
        calls++; assert.deepEqual(sent, request); assert.deepEqual(identity, context);
        return reject ? { ...terminal(), phase: "rejected", result_code: null, error_code: "return_placement_stale" } : terminal();
      },
    };
    const server = createTargetServer(...args), client = new Client({ name: "paid-return-test", version: "1" });
    const [a, b] = InMemoryTransport.createLinkedPair();
    await server.connect(a); await client.connect(b);
    try {
      const tools = (await client.listTools()).tools;
      assert.equal(tools.some(tool => tool.name === "review_paid_return"), enabled);
      assert.equal(tools.some(tool => tool.name === "return_paid_items"), enabled);
      if (!enabled) continue;
      const reviewed = await client.callTool({ name: "review_paid_return", arguments: reviewInput });
      assert.notEqual(reviewed.isError, true);
      assert.match(JSON.stringify(reviewed.content), /9223372036854775807/);
      const first = await client.callTool({ name: "return_paid_items", arguments: input });
      assert.notEqual(first.isError, true);
      const replay = await client.callTool({ name: "return_paid_items", arguments: input });
      assert.deepEqual(replay, first);
      const invalid = await client.callTool({ name: "return_paid_items", arguments: { ...input,
        payload: { ...input.payload, items: [{ ...input.payload.items[0], amountMinorUnits: "1" }] } } });
      assert.equal(invalid.isError, true); assert.equal(calls, 2);
      reject = true;
      const rejected = await client.callTool({ name: "return_paid_items", arguments: input });
      assert.equal(rejected.isError, true);
      assert.match(JSON.stringify(rejected.content), /return_placement_stale/);
    } finally { await client.close(); await server.close(); }
  }
});

test("stable request retains frozen identities and rejects invented monetary fields or duplicate selection", () => {
  assert.deepEqual(makePaidReturnRequest(structuredClone(input), context), request);
  assert.equal(JSON.parse(request.commandJSON).items[0].paidInvoiceLineId, "line");
  const duplicate = structuredClone(input); duplicate.payload.items.push(duplicate.payload.items[0]);
  assert.throws(() => makePaidReturnRequest(duplicate, context));
  const extra = structuredClone(input); Object.assign(extra.payload.items[0], { amount: "100" });
  assert.throws(() => makePaidReturnRequest(extra, context));
  const collision = structuredClone(input); collision.payload.items[0].inventoryPlacementId = "old";
  assert.throws(() => makePaidReturnRequest(collision, context));
});

test("review preserves exact Int64 cents and refuses wrong scope, missing and duplicate Items", () => {
  assert.deepEqual(validatePaidReturnReview(review, reviewInput, context), review);
  for (const invalid of [{ ...review, accountId: "other" }, { ...review, principalId: "other" },
    { ...review, items: [] }, { ...review, items: [review.items[0], review.items[0]] },
    { ...review, items: [{ ...review.items[0], paidAmountMinorUnits: "9223372036854775808" }] }]) {
    assert.throws(() => validatePaidReturnReview(invalid, reviewInput, context));
  }
});

test("authenticated service sends exact review and command bodies; mismatched receipt is refused", async () => {
  let calls = 0;
  const service = new SupabasePaidReturnService(new URL("https://target.invalid"), "public-key", async (url, init) => {
    calls++;
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    assert.equal(init?.redirect, "error");
    if (String(url).endsWith("spike_read_paid_return_review")) {
      assert.deepEqual(JSON.parse(init?.body as string), { p_account_id: "account", p_project_id: "project", p_item_ids: ["item"] });
      return Response.json(review);
    }
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_return_paid_items");
    assert.deepEqual(JSON.parse(init?.body as string), { p_command: request.commandJSON });
    return Response.json(terminal());
  });
  assert.deepEqual(await service.review(reviewInput, context), review);
  assert.equal((await paidReturnTool(input, context, service)).phase, "applied");
  await assert.rejects(service.apply(request, { ...context, accountId: "foreign" }));
  assert.equal(calls, 2);
  await assert.rejects(paidReturnTool(input, context, {
    review: async () => review, apply: async () => ({ ...terminal(), account_id: "foreign" }),
  }));
});
