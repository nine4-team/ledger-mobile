import assert from "node:assert/strict";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { SupabaseProjectBudgetReader, validateProjectBudget } from "../src/projectBudgetRead.js";

const context = { accountId: "account", principalId: "principal", accessToken: "user-token" };
const input = { projectId: "project", currency: "USD" };
const snapshot = () => ({ accountId: "account", principalId: "principal", projectId: "project", clientId: "client",
  currency: "USD", isCompleteForProjectBudget: false as const,
  missingCoverage: ["transfers", "additional_requests"] as ["transfers", "additional_requests"],
  categories: [{ id: "category", name: "Furnishings", kind: "itemized" as const,
    excludesFromOverallBudget: false, enabled: true, allocationMinorUnits: "1000",
    paidMinorUnits: "20", unpaidMinorUnits: "175", recognizedMinorUnits: "195" }],
  overallPaidMinorUnits: "20", overallUnpaidMinorUnits: "175", overallRecognizedMinorUnits: "195", overallBudgetMinorUnits: "1000" });

test("budget validates exact mixed-source totals and explicit incomplete coverage", () => {
  assert.deepEqual(validateProjectBudget(snapshot(), input, context), snapshot());
  const value = snapshot();
  value.categories[0]!.paidMinorUnits = value.overallPaidMinorUnits = "9007199254740993";
  value.categories[0]!.unpaidMinorUnits = value.overallUnpaidMinorUnits = "-100";
  value.categories[0]!.recognizedMinorUnits = value.overallRecognizedMinorUnits = "9007199254740893";
  assert.deepEqual(validateProjectBudget(value, input, context), value);
});
test("budget rejects scope, totals, duplicates, overflow, disabled allocations and false completeness", () => {
  for (const change of [
    { accountId: "foreign" }, { principalId: "foreign" }, { projectId: "foreign" }, { currency: "EUR" },
    { overallRecognizedMinorUnits: "196" }, { overallBudgetMinorUnits: "999" },
    { overallPaidMinorUnits: 20 }, { overallPaidMinorUnits: "9223372036854775808" },
    { isCompleteForProjectBudget: true }, { missingCoverage: [] },
    { categories: [...snapshot().categories, ...snapshot().categories] },
    { categories: [{ ...snapshot().categories[0], enabled: false }] },
    { categories: [{ ...snapshot().categories[0], recognizedMinorUnits: "194" }] },
  ]) assert.throws(() => validateProjectBudget({ ...snapshot(), ...change }, input, context), { code: "budget_server_result_mismatch" });
  const value = snapshot(); value.categories.push({ ...value.categories[0]!, id: "excluded", excludesFromOverallBudget: true });
  assert.deepEqual(validateProjectBudget(value, input, context), value);
});
test("budget RPC binds user scope and rejects denied or malformed responses", async () => {
  const reader = new SupabaseProjectBudgetReader(new URL("https://example.invalid"), "public-key", async (url, init) => {
    assert.equal(new URL(String(url)).pathname, "/rest/v1/rpc/spike_read_project_budget");
    assert.equal((init?.headers as Record<string, string>).Authorization, "Bearer user-token");
    assert.equal(init?.redirect, "error");
    assert.deepEqual(JSON.parse(String(init?.body)), { p_account_id: "account", p_project_id: "project", p_currency: "USD" });
    return new Response(JSON.stringify(snapshot()));
  });
  assert.deepEqual(await reader.read(input, context), snapshot());
  for (const response of [new Response("private detail", { status: 403 }), new Response("not JSON")]) {
    const failing = new SupabaseProjectBudgetReader(new URL("https://example.invalid"), "public-key", async () => response);
    await assert.rejects(failing.read(input, context));
  }
});
test("registered Budget tool validates adapter output and preserves warning", async () => {
  let current = snapshot();
  const args: Parameters<typeof createTargetServer> = [{ read: async () => { throw new Error("unused"); } }, context];
  args[19] = { read: async () => current };
  const server = createTargetServer(...args);
  const client = new Client({ name: "budget-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const result = await client.callTool({ name: "get_project_budget", arguments: input });
    assert.notEqual(result.isError, true);
    assert.deepEqual(JSON.parse((result.content as { text: string }[])[0]!.text), current);
    current = { ...current, accountId: "foreign" };
    const rejected = await client.callTool({ name: "get_project_budget", arguments: input });
    assert.equal(rejected.isError, true);
    assert.doesNotMatch(JSON.stringify(rejected), /foreign/);
  } finally { await client.close(); await server.close(); }
});
