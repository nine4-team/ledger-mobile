import assert from "node:assert/strict";
import test from "node:test";
import { SupabaseProjectInvoicingItemsReader, validateProjectInvoicingItems } from "../src/projectInvoicingItemsRead.js";
import { createTargetServer } from "../src/server.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";

const context = { accountId: "account", principalId: "principal", accessToken: "user-token" };
const input = { projectId: "project" };
const snapshot = () => ({ accountId: "account", principalId: "principal", projectId: "project", rows: [
  { occurrenceId: "same-id", itemId: "physical-item", polarity: "charge", amountMinorUnits: "9007199254740993",
    currency: "USD", availability: "paid", invoiceId: "invoice", invoiceName: "Original Invoice",
    title: "Chair", categoryId: "category", categoryName: "Furnishings" },
  { occurrenceId: "same-id", itemId: "physical-item", polarity: "credit", amountMinorUnits: "-9007199254740993",
    currency: "USD", availability: "available", invoiceId: null, invoiceName: null,
    title: "Chair", categoryId: "category", categoryName: "Furnishings" },
] });
test("Invoicing preserves exact paid charge and credit for the same Item and raw ID", () => {
  assert.deepEqual(validateProjectInvoicingItems(snapshot(), input, context), snapshot());
});
test("Invoicing rejects scope, duplicate occurrence, signs and incomplete Invoice membership", () => {
  for (const change of [{ accountId: "foreign" }, { principalId: "foreign" }, { projectId: "foreign" },
    { rows: [snapshot().rows[0], snapshot().rows[0]] }]) {
    assert.throws(() => validateProjectInvoicingItems({ ...snapshot(), ...change }, input, context));
  }
  for (const change of [{ amountMinorUnits: "-1" }, { amountMinorUnits: "0" },
    { amountMinorUnits: "9223372036854775808" }, { amountMinorUnits: 100 },
    { invoiceId: null }, { availability: "available" }, { currency: "usd" }]) {
    const value = snapshot(); Object.assign(value.rows[0]!, change);
    assert.throws(() => validateProjectInvoicingItems(value, input, context), { code: "invoicing_server_result_mismatch" });
  }
});

test("Invoicing adapter binds user scope and rejects denied or malformed responses", async () => {
  const reader = new SupabaseProjectInvoicingItemsReader(new URL("https://example.invalid"), "public-key", async (url, init) => {
    assert.equal(new URL(String(url)).pathname, "/rest/v1/rpc/spike_read_project_invoicing_items");
    assert.equal((init?.headers as Record<string, string>).Authorization, "Bearer user-token");
    assert.equal(init?.redirect, "error");
    assert.deepEqual(JSON.parse(String(init?.body)), { p_account_id: "account", p_project_id: "project" });
    return new Response(JSON.stringify(snapshot()));
  });
  assert.deepEqual(await reader.read(input, context), snapshot());
  for (const response of [new Response("private data", { status: 403 }), new Response("not JSON"),
    new Response(JSON.stringify({ ...snapshot(), accountId: "foreign" }))]) {
    const rejected = new SupabaseProjectInvoicingItemsReader(new URL("https://example.invalid"), "public-key", async () => response);
    await assert.rejects(rejected.read(input, context));
  }
});

test("registered Invoicing read tool preserves exact data and redacts adapter errors", async () => {
  let wrongScope = false;
  const args: Parameters<typeof createTargetServer> = [{ read: async () => { throw new Error("unused"); } }, context];
  args[20] = { read: async () => ({ ...validateProjectInvoicingItems(snapshot(), input, context),
    accountId: wrongScope ? "foreign" : "account" }) };
  const server = createTargetServer(...args);
  const client = new Client({ name: "invoicing-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const result = await client.callTool({ name: "list_project_invoicing_items", arguments: input });
    assert.notEqual(result.isError, true);
    assert.deepEqual(JSON.parse((result.content as { text: string }[])[0]!.text), snapshot());
    wrongScope = true;
    const rejected = await client.callTool({ name: "list_project_invoicing_items", arguments: input });
    assert.equal(rejected.isError, true);
    assert.doesNotMatch(JSON.stringify(rejected), /foreign/);
  } finally { await client.close(); await server.close(); }
});
