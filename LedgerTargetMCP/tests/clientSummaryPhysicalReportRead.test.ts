import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { SupabaseClientSummaryPhysicalReportReader } from "../src/clientSummaryPhysicalReportRead.js";
import { buildClientSummaryPhysicalReportSnapshot as build, isClientSummaryPhysicalReportComplete as complete } from "../src/clientSummaryPhysicalReport.js";
import { createTargetServer } from "../src/server.js";

const native = JSON.parse(readFileSync(new URL("./fixtures/client-summary-physical-online.jsonl", import.meta.url), "utf8").trim().split("\n")[0]);
const token = (role: string) => `e30.${Buffer.from(JSON.stringify({ role })).toString("base64url")}.signature`;
const context = { accountId: native.project.accountId, principalId: native.provenance.principalId, accessToken: token("authenticated") };
const input = { projectId: native.project.projectId };
function facts(): any {
  const value = structuredClone(native);
  value.provenance.authorityVersion = "client-summary-physical-v1";
  value.provenance.visibilityScopeID = createHash("sha256").update(JSON.stringify([
    context.accountId, context.principalId, input.projectId, "client-summary-physical-v1",
  ])).digest("hex");
  return value;
}
const reader = (fetcher: typeof fetch) => new SupabaseClientSummaryPhysicalReportReader(new URL("http://127.0.0.1:54321"), "sb_publishable_test", fetcher);
test("physical reader sends only verified Account and selected Project with caller JWT", async () => {
  const result = await reader(async (url, init) => {
    assert.equal(String(url), "http://127.0.0.1:54321/rest/v1/rpc/spike_read_client_summary_physical_report");
    assert.deepEqual(JSON.parse(init?.body as string), { p_account_id: context.accountId, p_project_id: input.projectId });
    assert.equal(new Headers(init?.headers).get("Authorization"), `Bearer ${context.accessToken}`);
    assert.equal(new Headers(init?.headers).get("apikey"), "sb_publishable_test");
    assert.equal(init?.redirect, "error"); assert.equal(init?.method, "POST"); assert.ok(init?.signal);
    return Response.json(facts());
  }).read(input, context);
  assert.deepEqual(result, build(facts())); assert.ok(complete(result));
});
test("missing physical evidence returns incomplete preview rather than fabricated empty or ready", async () => {
  const value = facts(); value.items[0].accounting = null; value.items[0].category = { unavailable: {} };
  value.client = { kind: "unavailable", clientId: value.client.clientId };
  const result = await reader(async () => Response.json(value)).read(input, context);
  assert.equal(complete(result), false); assert.equal(result.items.length, value.items.length);
});
test("foreign, malformed, offline and wrong-profile responses fail closed even when evidence is missing", async () => {
  for (const change of [
    (v: any) => { v.project.accountId = "foreign"; },
    (v: any) => { v.project.projectId = "foreign"; },
    (v: any) => { v.provenance.principalId = "foreign"; },
    (v: any) => { v.provenance.visibilityScopeID = "0".repeat(64); },
    (v: any) => { v.provenance.authorityVersion = "property-management-v1"; },
    (v: any) => { v.provenance.accountId = "foreign"; },
    (v: any) => { v.provenance.source = { kind: "downloaded" }; },
    (v: any) => { v.items[0].itemRevision = 2; },
    (v: any) => { v.items[0].accountId = "foreign"; },
  ]) {
    const value = facts(); value.items[0].accounting = null; change(value);
    await assert.rejects(reader(async () => Response.json(value)).read(input, context), { code: "client_summary_physical_server_result_mismatch" });
  }
  for (const value of ["null", "[]", "bad json"]) await assert.rejects(reader(async () => new Response(value)).read(input, context), { code: "client_summary_physical_server_result_mismatch" });
});
test("unsafe config and privileged credentials are rejected before network", async () => {
  for (const key of ["sb_secret_test", token("service_role"), "bad"]) assert.throws(() =>
    new SupabaseClientSummaryPhysicalReportReader(new URL("https://example.com"), key), { code: "client_summary_physical_configuration_invalid" });
  for (const url of ["http://example.com", "https://u:p@example.com", "https://example.com/path", "https://example.com/#secret"]) assert.throws(() =>
    new SupabaseClientSummaryPhysicalReportReader(new URL(url), "sb_publishable_test"), { code: "client_summary_physical_configuration_invalid" });
  for (const accessToken of [token("service_role"), token("anon"), "bad\r\nheader"]) await assert.rejects(
    reader(async () => assert.fail("no network")).read(input, { ...context, accessToken }), { code: "authentication_required" });
});
test("provider and transport errors are sanitized without retries", async () => {
  let calls = 0;
  await assert.rejects(reader(async () => { calls++; throw new Error(context.accessToken); }).read(input, context), { message: "client_summary_physical_transport_failed" });
  assert.equal(calls, 1);
  for (const [status, code] of [[401, "authentication_required"], [403, "account_not_authorized"], [500, "client_summary_physical_read_failed"]] as const) {
    await assert.rejects(reader(async () => new Response("private", { status })).read(input, context), { message: code, statusCode: status });
  }
});
test("MCP registers preview-only tool, binds host context, rejects model identity and sanitizes errors", async () => {
  let calls = 0, fail = false;
  const value = facts(); value.items[0].accounting = null;
  const snapshot = build(value);
  const server = createTargetServer({ read: async () => assert.fail("wrong report") }, context, { read: async (selection, identity) => {
    calls++; assert.deepEqual(selection, input); assert.deepEqual(identity, context);
    if (fail) throw new Error(context.accessToken);
    return snapshot;
  } });
  const client = new Client({ name: "test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const tools = await client.listTools();
    assert.equal(tools.tools.length, 2);
    const tool = tools.tools.find(t => t.name === "get_client_summary_physical_report")!;
    assert.match(tool.description!, /preview/); assert.equal(tool.annotations?.readOnlyHint, true);
    const result = await client.callTool({ name: tool.name, arguments: input });
    const payload = JSON.parse((result.content as any)[0].text);
    assert.deepEqual(payload, snapshot); assert.equal(complete(payload), false);
    const invalid = await client.callTool({ name: tool.name, arguments: { ...input, accountId: "foreign" } });
    assert.equal(invalid.isError, true); assert.equal(calls, 1);
    fail = true;
    const error = await client.callTool({ name: tool.name, arguments: input });
    assert.equal(error.isError, true); assert.equal((error.content as any)[0].text, '{"code":"client_summary_physical_read_failed"}');
  } finally { await client.close(); await server.close(); }
});
