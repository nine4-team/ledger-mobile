import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { SupabaseCollectedInvoiceReader, validateCollectedInvoiceList, validateCollectedInvoice } from "../src/collectedInvoiceRead.js";

const invoice = () => JSON.parse(readFileSync(new URL("./fixtures/payment-contents.json", import.meta.url), "utf8")).invoice;
const context = { accountId: "account", principalId: "principal", accessToken: "user-token" };
const input = () => ({ projectId: "project", invoiceId: invoice().invoice_id });
test("collected directory reuses frozen validation and checks adapter/transport boundaries", async () => {
  const query = {projectId:"project"}, rows = [invoice()];
  assert.deepEqual(validateCollectedInvoiceList([],query,context),[]);
  assert.deepEqual(validateCollectedInvoiceList(rows,query,context),rows);
  for (const invalid of [[...rows,...rows],[{...invoice(),account_id:"other"}],
    [{...invoice(),project_id:"other"}],[{...invoice(),total_minor_units:"1"}]]) {
    assert.throws(() => validateCollectedInvoiceList(invalid,query,context));
  }
  const reader = new SupabaseCollectedInvoiceReader(new URL("https://example.invalid"),"public-key",async (url,init) => {
    assert.equal(String(url),"https://example.invalid/rest/v1/rpc/spike_list_project_collected_invoices");
    assert.equal((init?.headers as Record<string,string>).Authorization,"Bearer user-token");
    assert.equal(init?.redirect,"error");
    assert.deepEqual(JSON.parse(String(init?.body)),{p_account_id:"account",p_project_id:"project"});
    return new Response(JSON.stringify(rows));
  });
  assert.deepEqual(await reader.list(query,context),rows);
  const server = createTargetServer({read:async()=>{throw new Error("unused");}},context,
    undefined,undefined,undefined,undefined,undefined,undefined,undefined,reader);
  const client = new Client({name:"paid-invoice-list-test",version:"1"});
  const [a,b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const result = await client.callTool({name:"list_project_collected_invoices",arguments:query});
    assert.ok(!result.isError);
    assert.deepEqual(JSON.parse((result.content as {text:string}[])[0].text),rows);
    reader.list = async () => [{...invoice(),account_id:"other"}];
    assert.equal((await client.callTool({name:"list_project_collected_invoices",arguments:query})).isError,true);
  } finally {await client.close(); await server.close();}
});

test("direct Invoice preserves shared frozen contents and rejects scope or accounting mismatch", () => {
  assert.deepEqual(validateCollectedInvoice(invoice(), input(), context), invoice());
  for (const field of ["invoice_id", "account_id", "project_id", "total_minor_units"]) {
    const value = invoice(); value[field] = field === "total_minor_units" ? "126" : "other";
    assert.throws(() => validateCollectedInvoice(value, input(), context), { code: "invoice_server_result_mismatch" });
  }
  const value = invoice(); value.lines[0].source_snapshot_json = "{}";
  assert.throws(() => validateCollectedInvoice(value, input(), context));
});
test("reader binds user/account and fails closed on denied or malformed responses", async () => {
  const reader = new SupabaseCollectedInvoiceReader(new URL("https://example.invalid"), "public-key", async (url, init) => {
    assert.equal(new URL(String(url)).pathname, "/rest/v1/rpc/spike_read_collected_invoice");
    assert.equal((init?.headers as Record<string,string>).Authorization, "Bearer user-token");
    assert.equal(init?.redirect, "error");
    assert.deepEqual(JSON.parse(String(init?.body)), { p_account_id: "account", p_project_id: "project", p_invoice_id: input().invoiceId });
    return new Response(JSON.stringify(invoice()));
  });
  assert.deepEqual(await reader.read(input(), context), invoice());
  for (const response of [new Response("private denial detail", { status: 403 }), new Response("not json")]) {
    const failing = new SupabaseCollectedInvoiceReader(new URL("https://example.invalid"), "public-key", async () => response);
    await assert.rejects(failing.read(input(), context));
  }
});
test("registered paid-Invoice tool returns frozen data and validates adapter results", async () => {
  let current = invoice();
  const server = createTargetServer({ read: async () => { throw new Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, undefined, undefined, undefined, { read: async () => current });
  const client = new Client({ name: "invoice-read-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const result = await client.callTool({ name: "get_collected_invoice", arguments: input() });
    assert.notEqual(result.isError, true);
    assert.deepEqual(JSON.parse((result.content as { text: string }[])[0].text), invoice());
    current = { ...current, account_id: "foreign" };
    const denied = await client.callTool({ name: "get_collected_invoice", arguments: input() });
    assert.equal(denied.isError, true);
    assert.equal(JSON.stringify(denied).includes("foreign"), false);
  } finally { await client.close(); await server.close(); }
});
