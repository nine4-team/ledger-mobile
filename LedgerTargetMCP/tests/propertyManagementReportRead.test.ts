import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";
import { accounted } from "./fixtures/propertyManagementAccounting.js";
import { SupabasePropertyManagementReportReader } from "../src/propertyManagementReportRead.js";
import { buildPropertyManagementReportSnapshot } from "../src/propertyManagementReport.js";

const golden = JSON.parse(readFileSync(new URL("./fixtures/property-management-report-online.json", import.meta.url), "utf8"));
golden.provenance.authorityVersion = "property-management-v1";
// The pure encoding fixture intentionally uses an arbitrary valid hash. A real
// provider must bind the scope hash to the authenticated request.
golden.provenance.visibilityScopeID = createHash("sha256").update(JSON.stringify([
  golden.project.accountId, golden.provenance.principalId, golden.project.projectId,
  "physical-property-report-v1",
])).digest("hex");
const facts = () => structuredClone({ project: golden.project, spaces: golden.spaces,
  items: golden.groups.flatMap((g: any) => g.rows).map((item: any) => ({ ...item, accounting: accounted(item) })),
  currency: golden.currency, provenance: golden.provenance });
const token = (role: string) => `e30.${Buffer.from(JSON.stringify({ role })).toString("base64url")}.signature`;
const context = { accountId: golden.project.accountId, principalId: golden.provenance.principalId,
  accessToken: token("authenticated") };
const input = { projectId: golden.project.projectId, currency: golden.currency };
const url = new URL("http://127.0.0.1:54321");
const reader = (fetcher: typeof fetch) => new SupabasePropertyManagementReportReader(url, "sb_publishable_test", fetcher);

test("sends caller JWT and exact scope, returning the Swift-equivalent report", async () => {
  const client = reader(async (endpoint, init) => {
    assert.equal(String(endpoint), `${url.origin}/rest/v1/rpc/spike_read_property_management_report`);
    assert.equal(init?.method, "POST"); assert.equal(init?.redirect, "error");
    assert.ok(init?.signal);
    assert.deepEqual(JSON.parse(init?.body as string), { p_account_id: context.accountId,
      p_project_id: input.projectId, p_currency: input.currency });
    assert.equal(new Headers(init?.headers).get("Authorization"), `Bearer ${context.accessToken}`);
    assert.equal(new Headers(init?.headers).get("apikey"), "sb_publishable_test");
    return Response.json(facts());
  });
  assert.deepEqual(await client.read(input, context), buildPropertyManagementReportSnapshot(facts()));
});

test("rejects mismatched scope, malformed facts and fabricated offline provenance", async () => {
  for (const change of [
    (x: any) => { x.project.accountId = x.provenance.accountId = "foreign"; x.spaces = []; x.items = []; },
    (x: any) => { x.project.projectId = x.provenance.projectId = "foreign"; x.spaces = []; x.items = []; },
    (x: any) => { x.provenance.principalId = "foreign"; },
    (x: any) => { x.provenance.visibilityScopeID = "0".repeat(64); },
    (x: any) => { x.provenance.authorityVersion = "unsupported-v2"; },
    (x: any) => { x.currency = "ZZZ"; x.items = []; },
    (x: any) => { x.items[0].itemRevision = 123; },
    (x: any) => { x.items[0].accounting.resolution = "unaccountedFor"; },
    (x: any) => { x.provenance.source = { kind: "downloaded" }; },
    (x: any) => { x.items[0] = null; },
  ]) {
    const body = facts(); change(body);
    await assert.rejects(reader(async () => Response.json(body)).read(input, context),
      { code: "property_report_server_result_mismatch" });
  }
  for (const body of ["null", "[]", "not json"]) {
    await assert.rejects(reader(async () => new Response(body)).read(input, context),
      { code: "property_report_server_result_mismatch" });
  }
});

test("missing relationship evidence is not ready, not empty or a mismatched response", async () => {
  const body = facts();
  delete body.items[0].accounting;
  await assert.rejects(reader(async () => Response.json(body)).read(input, context),
    { code: "property_report_incomplete_readiness" });
  // Request binding still precedes the incomplete-data distinction.
  body.provenance.principalId = "foreign";
  await assert.rejects(reader(async () => Response.json(body)).read(input, context),
    { code: "property_report_server_result_mismatch" });
});

test("sanitizes transport and server failures without retrying", async () => {
  let calls = 0;
  await assert.rejects(reader(async () => { calls++; throw new Error(`secret ${context.accessToken}`); }).read(input, context),
    { message: "property_report_transport_failed" });
  assert.equal(calls, 1);
  for (const [status, code] of [[401, "authentication_required"], [403, "account_not_authorized"],
    [500, "property_report_read_failed"]] as const) {
    await assert.rejects(reader(async () => new Response("private database detail", { status })).read(input, context),
      { message: code, statusCode: status });
  }
});

test("rejects privileged credentials and unsafe destinations before network access", async () => {
  for (const key of ["sb_secret_test", token("service_role"), "unknown"]) {
    assert.throws(() => new SupabasePropertyManagementReportReader(url, key),
      { code: "property_report_configuration_invalid" });
  }
  for (const address of ["http://example.com", "https://u:p@example.com", "https://example.com/path", "https://example.com/?key=secret"]) {
    assert.throws(() => new SupabasePropertyManagementReportReader(new URL(address), "sb_publishable_test"),
      { code: "property_report_configuration_invalid" });
  }
  const client = reader(async () => { assert.fail("must not send request"); });
  for (const accessToken of [token("service_role"), token("anon"), "sb_secret_test", "bad\r\nheader"]) {
    await assert.rejects(client.read(input, { ...context, accessToken }), { code: "authentication_required" });
  }
});

test("resolves exactly one RLS-authorized Principal, never trusts a supplied identity", async () => {
  const client = reader(async (url, init) => {
    assert.equal(new URL(String(url)).pathname, "/rest/v1/spike_principals");
    assert.equal(new Headers(init?.headers).get("Authorization"), `Bearer ${context.accessToken}`);
    return Response.json([{ id: context.principalId }]);
  });
  assert.deepEqual(await client.resolveContext(context.accountId, context.accessToken), context);
  for (const body of [[], [{ id: "one" }, { id: "two" }], [{ id: null }], null]) {
    await assert.rejects(reader(async () => Response.json(body)).resolveContext(context.accountId, context.accessToken),
      { code: "authentication_required" });
  }
  await assert.rejects(reader(async () => new Response("secret", { status: 401 }))
    .resolveContext(context.accountId, context.accessToken), { code: "authentication_required" });
});
