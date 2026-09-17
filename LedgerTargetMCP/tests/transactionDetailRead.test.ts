import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { SupabaseTransactionDetailReader, transactionDetail, transactionList } from "../src/transactionDetailRead.js";

const context = { accountId: "account-primary", principalId: "principal-restricted",
  accessToken: `e30.${Buffer.from(JSON.stringify({ role: "authenticated" })).toString("base64url")}.signature` };
const fixture = () => JSON.parse(readFileSync(new URL("./fixtures/transaction-detail.json", import.meta.url), "utf8"));
test("descriptive revision is exact and older downloads do not invent an edit token", () => {
  const input = fixture();
  assert.equal(transactionDetail(input, input.transactionId, context).detailsRevision, undefined);
  for (const value of [null, "1", "9007199254740993", "9223372036854775807"]) {
    assert.equal(transactionDetail({ ...input, detailsRevision: value }, input.transactionId, context).detailsRevision, value);
  }
  for (const value of [0, 1, "0", "-1", "01", "1.0", "1\n", "9223372036854775808"]) {
    assert.throws(() => transactionDetail({ ...input, detailsRevision: value }, input.transactionId, context),
      { code: "transaction_detail_server_result_mismatch" });
  }
});
test("current Item categories are explicit Project evidence, not receipt-category inference", () => {
  const item = { itemId: "item", placementId: "placement", categoryId: "different-category" };
  const input = { ...fixture(), scopeKind: "project", projectId: "project", clientId: "client",
    currentItemCategories: [item] };
  assert.deepEqual(transactionDetail(input, input.transactionId, context), input);
  assert.equal(transactionDetail({ ...input, currentItemCategories: [{ ...item, categoryId: null }] },
    input.transactionId, context).currentItemCategories?.[0].categoryId, null);
  for (const items of [[item, item], [item, { ...item, itemId: "other" }], [{ ...item, categoryId: "bad id" }]]) {
    assert.throws(() => transactionDetail({ ...input, currentItemCategories: items }, input.transactionId, context),
      { code: "transaction_detail_server_result_mismatch" });
  }
  assert.throws(() => transactionDetail({ ...fixture(), currentItemCategories: [item] }, input.transactionId, context),
    { code: "transaction_detail_server_result_mismatch" });
  assert.deepEqual(transactionDetail({ ...fixture(), currentItemCategories: [] }, input.transactionId, context).currentItemCategories, []);
});
test("legacy tax/subtotal metadata retains exact strings and rejects malformed input", () => {
  const input = { ...fixture(), legacySubtotalMinorUnits: "9007199254740993",
    legacyTaxRatePct: "8.1234567890123456789012345678901234567890" };
  assert.deepEqual(transactionDetail(input, input.transactionId, context), input);
  for (const rate of ["NaN", "Infinity", "1e2", " 8", "8\n", "8.", ".5", "01", "", "-", "8.5.2"]) {
    assert.throws(() => transactionDetail({ ...input, legacyTaxRatePct: rate }, input.transactionId, context),
      { code: "transaction_detail_server_result_mismatch" });
  }
  assert.throws(() => transactionDetail({ ...input, legacySubtotalMinorUnits: "9223372036854775808" }, input.transactionId, context),
    { code: "transaction_detail_server_result_mismatch" });
  assert.equal(transactionDetail({ ...input, legacyTaxRatePct: "0.0000", legacySubtotalMinorUnits: "0" }, input.transactionId, context)
    .legacyTaxRatePct, "0.0000");
  assert.equal(transactionDetail(fixture(), input.transactionId, context).legacySubtotalMinorUnits, undefined);
});
const listFixture = () => ({ accountId: context.accountId, principalId: context.principalId,
  scopeKind: "business_inventory", projectId: null, clientId: null, coverage: "partial", transactions: [fixture()] });
test("list shares detail evidence and retains partial empty versus complete coverage", () => {
  const input = { scopeKind: "business_inventory" } as const;
  assert.deepEqual(transactionList(listFixture(), input, context), listFixture());
  assert.equal(transactionList({ ...listFixture(), transactions: [] }, input, context).coverage, "partial");
  for (const patch of [{ coverage: "complete" }, { accountId: "foreign" }, { principalId: "foreign" },
    { projectId: "invented" }, { clientId: "invented" }, { transactions: [fixture(), fixture()] },
    { transactions: [{ ...fixture(), accountId: "foreign" }] }]) {
    assert.throws(() => transactionList({ ...listFixture(), ...patch }, input, context),
      { code: "transaction_list_server_result_mismatch" });
  }
});
test("Project list retains standalone client payments and rejects mismatched row Project/Client", () => {
  const row = { ...fixture(), origin: "firebase_client_payment", type: "purchase", category: null, scopeKind: "project",
    projectId: "project", clientId: "client" };
  const value = { ...listFixture(), scopeKind: "project", projectId: "project", clientId: "client", transactions: [row] };
  const input = { scopeKind: "project", projectId: "project" } as const;
  assert.deepEqual(transactionList(value, input, context), value);
  for (const patch of [{ projectId: "foreign" }, { clientId: "foreign" }, { principalId: "foreign" }]) {
    assert.throws(() => transactionList({ ...value, transactions: [{ ...row, ...patch }] }, input, context),
      { code: "transaction_list_server_result_mismatch" });
  }
});
test("HTTP list binds host Account and scope, rejects invalid requests before fetching", async () => {
  let calls = 0, status = 200;
  const reader = new SupabaseTransactionDetailReader(new URL("https://target.invalid"), "sb_publishable_fixture", async (url, init) => {
    calls++;
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_read_transaction_list");
    assert.equal(init?.redirect, "error");
    assert.equal(new Headers(init?.headers).get("Authorization"), `Bearer ${context.accessToken}`);
    assert.deepEqual(JSON.parse(init?.body as string), { p_account_id: context.accountId, p_scope_kind: "business_inventory", p_project_id: null });
    return Response.json(status === 200 ? listFixture() : { secret: "never expose" }, { status });
  });
  assert.deepEqual(await reader.list({ scopeKind: "business_inventory" }, context), listFixture());
  for (const code of [401, 403, 500]) {
    status = code;
    await assert.rejects(reader.list({ scopeKind: "business_inventory" }, context), {
      code: code === 401 ? "authentication_required" : code === 403 ? "transaction_scope_not_available" : "transaction_list_read_failed" });
  }
  for (const input of [{ scopeKind: "project" }, { scopeKind: "business_inventory", projectId: "invented" }]) {
    await assert.rejects(reader.list(input as never, context), { code: "transaction_scope_invalid" });
  }
  assert.equal(calls, 4);
});
test("MCP advertises scoped read-only list and rejects caller identity overrides", async () => {
  const server = createTargetServer({ read: async () => assert.fail("wrong tool") }, context, undefined, undefined, undefined, {
    read: async () => assert.fail("wrong reader"),
    list: async (input, identity) => { assert.deepEqual(identity, context); return transactionList(listFixture(), input, identity); },
  });
  const client = new Client({ name: "list-tests", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const tool = (await client.listTools()).tools.find(t => t.name === "list_transactions");
    assert.equal(tool?.annotations?.readOnlyHint, true);
    const result = await client.callTool({ name: tool!.name, arguments: { scopeKind: "business_inventory" } });
    assert.notEqual(result.isError, true);
    assert.match(JSON.stringify(result), /9007199254740993/);
    for (const args of [{ scopeKind: "business_inventory", accountId: "foreign" }, { scopeKind: "project" }]) {
      assert.equal((await client.callTool({ name: tool!.name, arguments: args })).isError, true);
    }
  } finally { await client.close(); await server.close(); }
});
test("shared native display fixture preserves exact amount, metadata and scope", () => {
  const input = fixture();
  assert.deepEqual(transactionDetail(input, "detail-inventory", context), input);
  for (const field of ["source", "transactionDate", "createdAtMilliseconds", "notes", "paymentMethod", "hasEmailReceipt"]) input[field] = null;
  assert.deepEqual(transactionDetail(input, "detail-inventory", context), input);
});
test("embedded receipt retains historical evidence and must match its displayed Transaction", () => {
  const receipt = JSON.parse(readFileSync(new URL("./fixtures/transaction-receipt.json", import.meta.url), "utf8"));
  const identity = { ...context, accountId: receipt.accountId, principalId: receipt.principalId };
  const input = { ...fixture(), ...Object.fromEntries(["accountId", "principalId", "transactionId", "scopeKind", "projectId", "clientId",
    "type", "amountMinorUnits", "currency", "category"].map(key => [key, receipt[key]])), receipt };
  assert.deepEqual(transactionDetail(input, receipt.transactionId, identity), input);
  assert.equal(transactionDetail(input, receipt.transactionId, identity).receipt?.items.length, 2);
  for (const patch of [{ accountId: "foreign" }, { principalId: "foreign" }, { transactionId: "foreign" },
    { projectId: "foreign" }, { clientId: "foreign" }, { amountMinorUnits: "3051" }, { currency: "EUR" },
    { category: { ...receipt.category, revision: "2" } }]) {
    assert.throws(() => transactionDetail({ ...input, receipt: { ...receipt, ...patch } }, receipt.transactionId, identity),
      { code: "transaction_detail_server_result_mismatch" });
  }
});
test("foreign identity, invented origins, malformed dates and rounded money fail closed", () => {
  for (const [key, value] of [
    ["accountId", "foreign"], ["principalId", "foreign"], ["transactionId", "foreign"],
    ["projectId", "synthetic"], ["type", "transfer"], ["origin", "unknown"], ["origin", "firebase_client_payment"],
    ["category", null], ["transactionDate", "2023-02-29"], ["transactionDate", "1900-02-29"],
    ["transactionDate", "2024-04-31"], ["transactionDate", "0000-01-01"], ["transactionDate", "2024-1-01"],
    ["createdAtMilliseconds", "-0"], ["amountMinorUnits", 9007199254740993],
    ["amountMinorUnits", "0"], ["amountMinorUnits", "01"], ["amountMinorUnits", "9223372036854775808"],
  ]) assert.throws(() => transactionDetail({ ...fixture(), [key as string]: value }, "detail-inventory", context),
    { code: "transaction_detail_server_result_mismatch" });
});
test("imported client payment remains distinct from vendor receipt", () => {
  const input = { ...fixture(), category: null, origin: "firebase_client_payment", type: "purchase",
    scopeKind: "project", projectId: "project", clientId: "client" };
  assert.deepEqual(transactionDetail(input, "detail-inventory", context), input);
});
test("HTTP adapter binds identity and keeps private server errors out of output", async () => {
  let status = 200;
  const reader = new SupabaseTransactionDetailReader(new URL("https://target.invalid"), "sb_publishable_fixture", async (url, init) => {
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_read_transaction_detail");
    assert.equal(new Headers(init?.headers).get("Authorization"), `Bearer ${context.accessToken}`);
    assert.deepEqual(JSON.parse(init?.body as string), { p_account_id: "account-primary", p_transaction_id: "detail-inventory" });
    return Response.json(status === 200 ? fixture() : { secret: "never expose" }, { status });
  });
  assert.deepEqual(await reader.read({ transactionId: "detail-inventory" }, context), fixture());
  for (const code of [401, 403, 500]) {
    status = code;
    await assert.rejects(reader.read({ transactionId: "detail-inventory" }, context), {
      code: code === 401 ? "authentication_required" : code === 403 ? "transaction_not_available" : "transaction_detail_read_failed" });
  }
});
test("MCP exposes read-only detail with host identity, not caller-supplied Account", async () => {
  const server = createTargetServer({ read: async () => assert.fail("wrong tool") }, context, undefined, undefined, undefined, {
    read: async (input, identity) => { assert.deepEqual(identity, context); return transactionDetail(fixture(), input.transactionId, identity); },
  });
  const client = new Client({ name: "detail-tests", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const tool = (await client.listTools()).tools.find(t => t.name === "get_transaction_detail");
    assert.equal(tool?.annotations?.readOnlyHint, true);
    const result = await client.callTool({ name: tool!.name, arguments: { transactionId: "detail-inventory" } });
    assert.notEqual(result.isError, true);
    assert.match(JSON.stringify(result), /9007199254740993/);
    assert.equal((await client.callTool({ name: tool!.name, arguments: { transactionId: "detail-inventory", accountId: "foreign" } })).isError, true);
  } finally { await client.close(); await server.close(); }
});
