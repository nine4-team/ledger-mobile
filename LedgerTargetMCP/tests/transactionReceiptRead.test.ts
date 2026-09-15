import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { SupabaseTransactionReceiptReader, transactionReceiptAudit } from "../src/transactionReceiptRead.js";

const context = { accountId: "account", principalId: "member",
  accessToken: `e30.${Buffer.from(JSON.stringify({ role: "authenticated" })).toString("base64url")}.signature` };
const receipt = () => ({ accountId: "account", principalId: "member", transactionId: "transaction",
  scopeKind: "project", projectId: "project", clientId: "client", type: "purchase", currency: "USD", amountMinorUnits: "3050",
  category: { id: "category", name: "Items", kind: "itemized", revision: "1" },
  nonItemReceiptLines: [{ id: "tax", description: "Tax", amountMinorUnits: "100", effect: "increase", quantity: "10" },
    { id: "discount", description: "Discount", amountMinorUnits: "50", effect: "decrease" }],
  items: [{ itemId: "a", amountMinorUnits: "1000" as string | null, membershipKind: "linked" },
    { itemId: "b", amountMinorUnits: "2000" as string | null, membershipKind: "sold" }],
});
test("shared native receipt fixture has identical exact arithmetic and category applicability", () => {
  const fixture = JSON.parse(readFileSync(new URL("./fixtures/transaction-receipt.json", import.meta.url), "utf8"));
  const bound = { ...context, principalId: "principal" };
  for (const type of ["purchase", "return"]) for (const difference of [-1, 0, 1]) {
    const data = structuredClone(fixture);
    data.type = type; data.amountMinorUnits = String(3050 - difference);
    const result = transactionReceiptAudit(data, "transaction", bound);
    assert.equal(result.audit.status, difference === 0 ? "balanced" : "mismatch");
    assert.equal(result.audit.varianceMinorUnits, String(difference));
    assert.equal(result.audit.physicalItemTotalMinorUnits, "3000");
    assert.equal(result.audit.lineNetMinorUnits, "50");
    assert.equal(result.items[1].name, "Historical chair");
    assert.equal(result.items[1].sku, "CHAIR-2");
    assert.equal(result.items[1].source, "Original vendor");
    assert.equal(result.items[1].currentSource, "Display vendor");
    assert.equal(result.items[1].currentSpaceName, "Current room");
    assert.equal(result.items[1].imageCount, "2");
    for (const kind of ["general", "fee"]) {
      data.category.kind = kind;
      assert.equal(transactionReceiptAudit(data, "transaction", bound).audit.status, "notApplicable");
    }
  }
});
test("Transaction audit uses exact Item/history plus signed line amounts and current category", () => {
  for (const type of ["purchase", "return"]) for (const residual of [-1, 0, 1]) {
    const data = receipt(); data.type = type; data.amountMinorUnits = String(3050 - residual);
    const result = transactionReceiptAudit(data, "transaction", context);
    assert.equal(result.audit.status, residual === 0 ? "balanced" : "mismatch");
    assert.equal(result.audit.varianceMinorUnits, String(residual));
    assert.equal(result.audit.reconstructedTotalMinorUnits, "3050");
    for (const kind of ["general", "fee"]) {
      data.category.kind = kind;
      assert.equal(transactionReceiptAudit(data, "transaction", context).audit.status, "notApplicable");
    }
  }
});
test("missing Item prices are unknown, not a fabricated balanced total", () => {
  const data = receipt(); data.items[1].amountMinorUnits = null;
  const result = transactionReceiptAudit(data, "transaction", context);
  assert.equal(result.audit.status, "incompleteEvidence");
  assert.equal(result.audit.physicalItemTotalMinorUnits, null);
  assert.equal(result.audit.varianceMinorUnits, null);
  data.category.kind = "general";
  assert.equal(transactionReceiptAudit(data, "transaction", context).audit.status, "notApplicable");
});
test("foreign, duplicate, malformed and overflowing evidence fails before output", () => {
  for (const mutate of [
    (d: any) => { d.accountId = "foreign"; }, (d: any) => { d.principalId = "foreign"; },
    (d: any) => { d.transactionId = "foreign"; }, (d: any) => { d.type = "transfer"; },
    (d: any) => { d.scopeKind = "business_inventory"; }, (d: any) => { d.items.push(d.items[0]); },
    (d: any) => { d.nonItemReceiptLines.push(d.nonItemReceiptLines[0]); },
    (d: any) => { d.items[0].amountMinorUnits = "-1"; },
    (d: any) => { d.items[0].amountMinorUnits = "9223372036854775807"; },
    (d: any) => { d.amountMinorUnits = 3050; }, (d: any) => { delete d.items; },
    (d: any) => { d.nonItemReceiptLines[0].amountMinorUnits = "0"; },
  ]) {
    const data = receipt(); mutate(data);
    assert.throws(() => transactionReceiptAudit(data, "transaction", context), { code: "transaction_receipt_server_result_mismatch" });
  }
});
test("HTTP read binds Account/Transaction and sanitized failures never become empty success", async () => {
  let status = 200;
  const reader = new SupabaseTransactionReceiptReader(new URL("https://target.invalid"), "sb_publishable_fixture", async (url, init) => {
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_read_transaction_receipt");
    assert.equal(new Headers(init?.headers).get("Authorization"), `Bearer ${context.accessToken}`);
    assert.deepEqual(JSON.parse(init?.body as string), { p_account_id: "account", p_transaction_id: "transaction" });
    return Response.json(status === 200 ? receipt() : { secret: "do not expose" }, { status });
  });
  assert.equal((await reader.read({ transactionId: "transaction" }, context)).audit.status, "balanced");
  for (const code of [401, 403, 500]) {
    status = code;
    await assert.rejects(reader.read({ transactionId: "transaction" }, context), {
      code: code === 401 ? "authentication_required" : code === 403 ? "transaction_not_available" : "transaction_receipt_read_failed" });
  }
});
test("MCP registers the read-only audit without accepting tenant identity from tool arguments", async () => {
  const server = createTargetServer({ read: async () => assert.fail("wrong tool") }, context, undefined, undefined, {
    read: async (input, identity) => { assert.deepEqual(identity, context); return transactionReceiptAudit(receipt(), input.transactionId, identity); },
  });
  const client = new Client({ name: "receipt-tests", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const tool = (await client.listTools()).tools.find(t => t.name === "get_transaction_receipt_audit");
    assert.equal(tool?.annotations?.readOnlyHint, true);
    const result = await client.callTool({ name: tool!.name, arguments: { transactionId: "transaction" } });
    assert.notEqual(result.isError, true);
    assert.match(JSON.stringify(result), /balanced/);
    assert.equal((await client.callTool({ name: tool!.name, arguments: { transactionId: "transaction", accountId: "foreign" } })).isError, true);
  } finally { await client.close(); await server.close(); }
});
