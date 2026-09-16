import assert from "node:assert/strict";
import test from "node:test";
import { validateFees, SupabaseFeeReader } from "../src/feeRead.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
const context = { accountId: "account", principalId: "actor", accessToken: "user-token" };
const input = { projectId: "project" };
const row = { id: "fee", label: "Design", amountMinorUnits: "9007199254740993", currency: "USD",
  categoryId: "category", categoryName: "Design", revision: "1", status: "available", invoiceId: null, invoiceName: null };
const snapshot = { accountId: "account", projectId: "project", clientId: "client", canCreate: true, fees: [row] };
test("Fee browse MCP registration validates and exposes read-only results", async () => {
  const server = createTargetServer({ read: async () => { throw new Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined,
    { read: async () => validateFees(snapshot, input, context) });
  const client = new Client({ name: "fee-read-test", version: "1" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport); await client.connect(clientTransport);
  try {
    assert.equal((await client.listTools()).tools.find(tool => tool.name === "list_project_fees")?.annotations?.readOnlyHint, true);
    const response = await client.callTool({ name: "list_project_fees", arguments: input });
    assert.notEqual(response.isError, true);
    assert.match(JSON.stringify(response.content), /9007199254740993/);
  } finally { await client.close(); await server.close(); }
});
test("Fee browse validates exact amount, scope, unique IDs and membership states", () => {
  assert.deepEqual(validateFees(snapshot, input, context), snapshot);
  for (const status of ["created", "sent", "paid"]) {
    assert.equal(validateFees({ ...snapshot, canCreate: false, fees: [{ ...row, status, invoiceId: "invoice",
      categoryName: status === "paid" ? null : "Design" }] }, input, context).fees[0].status, status);
  }
  for (const invalid of [{ ...snapshot, accountId: "foreign" }, { ...snapshot, projectId: "foreign" },
    { ...snapshot, fees: [row, row] }, { ...snapshot, fees: [{ ...row, amountMinorUnits: "9223372036854775808" }] },
    { ...snapshot, fees: [{ ...row, status: "paid" }] },
    { ...snapshot, fees: [{ ...row, status: "paid", invoiceId: "invoice" }] }]) {
    assert.throws(() => validateFees(invalid, input, context));
  }
});
test("Fee browse HTTP is scoped and never turns denial into an empty list", async () => {
  const reader = new SupabaseFeeReader(new URL("http://127.0.0.1:54321"), "publishable", async (url, options) => {
    assert.equal(String(url), "http://127.0.0.1:54321/rest/v1/rpc/spike_read_project_fees");
    assert.deepEqual(JSON.parse(String(options?.body)), { p_account_id: "account", p_project_id: "project" });
    assert.equal(new Headers(options?.headers).get("Authorization"), "Bearer user-token");
    return new Response(JSON.stringify(snapshot));
  });
  assert.deepEqual(await reader.read(input, context), snapshot);
  const denied = new SupabaseFeeReader(new URL("http://127.0.0.1:54321"), "publishable", async () => new Response("", { status: 403 }));
  await assert.rejects(denied.read(input, context), { code: "fee_request_rejected", statusCode: 403 });
});
