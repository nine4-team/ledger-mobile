import assert from "node:assert/strict";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { SupabaseLiveInvoiceReader, validateLiveInvoice, type LiveInvoiceSnapshot } from "../src/liveInvoiceRead.js";

const context = { accountId: "account", principalId: "principal", accessToken: "user-token" };
const input = { projectId: "project", invoiceId: "invoice" };
const invoice = (): LiveInvoiceSnapshot => ({ accountId: "account", ...input, clientId: "client", revision: "1",
  status: "created" as const, name: "Invoice", notes: "", currency: "USD", totalMinorUnits: "9007199254740993",
  lines: [{ kind: "expense" as const, sourceId: "expense", sourceRevision: "2",
    amountMinorUnits: "9007199254740993", currency: "USD", categoryId: "category", description: "Vendor" }] });

test("live Invoice validates exact money, current source identity and complete scope", () => {
  assert.deepEqual(validateLiveInvoice(invoice(), input, context), invoice());
  for (const patch of [{ accountId: "foreign" }, { projectId: "foreign" }, { invoiceId: "foreign" },
    { totalMinorUnits: "9007199254740992" }, { totalMinorUnits: 9007199254740993 }, { status: "paid" },
    { revision: "0" }, { lines: [] }, { lines: [...invoice().lines, ...invoice().lines] },
    { lines: [{ ...invoice().lines[0], currency: "CAD" }] },
    { lines: [{ ...invoice().lines[0], sourceRevision: "01" }] },
    { totalMinorUnits: "9223372036854775808" }]) {
    assert.throws(() => validateLiveInvoice({ ...invoice(), ...patch }, input, context),
      { code: "invoice_server_result_mismatch" });
  }
  const signed = { ...invoice(), totalMinorUnits: "9007199254740992", lines: [...invoice().lines,
    { ...invoice().lines[0], sourceId: "credit", amountMinorUnits: "-1" }] };
  assert.deepEqual(validateLiveInvoice(signed, input, context), signed);
});

test("live reader uses scoped user RPC and sanitizes denial or malformed response", async () => {
  const reader = new SupabaseLiveInvoiceReader(new URL("https://example.invalid"), "public-key", async (url, init) => {
    assert.equal(String(url), "https://example.invalid/rest/v1/rpc/spike_read_live_invoice");
    assert.equal(init?.redirect, "error");
    assert.equal((init?.headers as Record<string,string>).Authorization, "Bearer user-token");
    assert.deepEqual(JSON.parse(String(init?.body)), { p_account_id: "account", p_project_id: "project", p_invoice_id: "invoice" });
    return new Response(JSON.stringify(invoice()));
  });
  assert.deepEqual(await reader.read(input, context), invoice());
  for (const response of [new Response("private detail", { status: 403 }), new Response("not json"),
    new Response(JSON.stringify({ ...invoice(), accountId: "foreign" }))]) {
    const failing = new SupabaseLiveInvoiceReader(new URL("https://example.invalid"), "public-key", async () => response);
    await assert.rejects(failing.read(input, context), error => !String(error).includes("private detail"));
  }
});

test("registered live reader returns current contents and rejects faulty adapter data", async () => {
  let current = invoice();
  const server = createTargetServer({ read: async () => { throw new Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined,
    { read: async () => current });
  const client = new Client({ name: "live-invoice-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const result = await client.callTool({ name: "get_live_invoice", arguments: input });
    assert.notEqual(result.isError, true);
    assert.deepEqual(JSON.parse((result.content as { text: string }[])[0].text), invoice());
    current = { ...current, accountId: "foreign" };
    const denied = await client.callTool({ name: "get_live_invoice", arguments: input });
    assert.equal(denied.isError, true);
    assert.equal(JSON.stringify(denied).includes("foreign"), false);
  } finally { await client.close(); await server.close(); }
});
