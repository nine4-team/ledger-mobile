import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { makeCategoryManagementRequest, manageCategoriesTool, SupabaseCategoryManagementApplier,
  validateCategoryManagementResult, validateCategoryDirectory, type CategoryManagementInput, type CategoryManagementRequest } from "../src/categoryManagement.js";

const context = { accountId: "category-account", principalId: "member", accessToken: "user-token" };
const input: CategoryManagementInput = { operationUUID: "11111111-2222-3333-4444-555555555555",
  clientCreatedAtMilliseconds: 1800000000123, payload: { action: "create", categoryId: "category",
    name: "Art & Décor / 🪑", kind: "general", excludesFromOverallBudget: false } };
const fixtures = JSON.parse(readFileSync(new URL("./fixtures/category-management.json", import.meta.url), "utf8"));
const terminal = (request: CategoryManagementRequest): Record<string, unknown> => ({
  operation_id: request.operationId, account_id: request.accountId, actor_principal_id: request.actorPrincipalId,
  command_type: "manage_categories", contract_version: "category-management-v1", command_fingerprint: request.fingerprint,
  envelope_sha256: request.fingerprint, request_sha256: null, subject_id: request.accountId,
  phase: "applied", result_code: "categories_updated", error_code: null,
  client_created_at_ms: request.clientCreatedAtMilliseconds, server_received_at_ms: 1800000001000, completed_at_ms: 1800000001001,
});
const directory = () => ({ accountId: context.accountId, principalId: context.principalId, complete: true,
  categories: [{ id: "category", accountId: context.accountId, name: "Lighting", kind: "general",
    lifecycle: "active", isSystem: false, excludesFromOverallBudget: false, presentationOrder: 1,
    revision: "9223372036854775807" }] });

test("category lookup returns exact revisions and rejects mismatched or incomplete directories", async () => {
  const reader = new SupabaseCategoryManagementApplier(new URL("https://target.invalid"), "public-key", async (url, init) => {
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_read_budget_categories");
    assert.deepEqual(JSON.parse(init?.body as string), { p_account_id: context.accountId });
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    return Response.json(directory());
  });
  assert.equal((await reader.read(context)).categories[0].revision, "9223372036854775807");
  for (const mutate of [
    (value: any) => { value.accountId = "foreign"; },
    (value: any) => { value.principalId = "foreign"; },
    (value: any) => { value.complete = false; },
    (value: any) => { value.categories[0].accountId = "foreign"; },
    (value: any) => { value.categories[0].revision = 9223372036854775807; },
    (value: any) => { value.categories.push(value.categories[0]); },
    (value: any) => {
      value.categories[0].name = "Décor";
      value.categories.push({ ...value.categories[0], id: "another", presentationOrder: 2, name: "DE\u0301COR" });
    },
  ]) {
    const bad = directory(); mutate(bad);
    assert.throws(() => validateCategoryDirectory(bad, context), { code: "category_directory_mismatch" });
  }
});

test("Swift and MCP share exact envelopes, hashes and decimal revision strings", () => {
  for (const fixture of fixtures) {
    const envelope = JSON.parse(fixture.envelopeJSON);
    const request = makeCategoryManagementRequest({ ...input, payload: envelope.payload }, context);
    assert.equal(request.envelopeJSON, fixture.envelopeJSON);
    assert.equal(request.fingerprint, fixture.fingerprint);
  }
});

test("category name trimming and control validation agree with the Swift form", () => {
  const names: { input: string; normalized: string | null; sameKeyAs?: string }[] = JSON.parse(
    readFileSync(new URL("./fixtures/category-names.json", import.meta.url), "utf8"));
  for (const fixture of names) {
    const make = () => makeCategoryManagementRequest({ ...input,
      payload: { action: "create", categoryId: "category", kind: "general",
        excludesFromOverallBudget: false, name: fixture.input } }, context);
    if (fixture.normalized === null) assert.throws(make, { code: "category_payload_invalid" });
    else {
      assert.equal(JSON.parse(make().envelopeJSON).payload.name, fixture.normalized);
      if (fixture.sameKeyAs !== undefined) {
        assert.equal(fixture.normalized.toLowerCase().normalize("NFC"),
          fixture.sameKeyAs.toLowerCase().normalize("NFC"));
      }
    }
  }
});

test("category names allow 100 Unicode code points after trimming", () => {
  for (const name of ["a".repeat(100), "🪑".repeat(100), "e\u0301".repeat(50)]) {
    const make = (value: string) => makeCategoryManagementRequest({ ...input,
      payload: { action: "create", categoryId: "category", kind: "general",
        excludesFromOverallBudget: false, name: value } }, context);
    assert.equal(JSON.parse(make(`  ${name}  `).envelopeJSON).payload.name, name);
    assert.throws(() => make(name + "a"), { code: "category_payload_invalid" });
  }
});

test("all five actions use the same scoped envelope without accounting-conversion flags", () => {
  const actions: CategoryManagementInput["payload"][] = [input.payload,
    { action: "edit", categoryId: "category", expectedRevision: "2", name: "Renamed", kind: "itemized", excludesFromOverallBudget: true },
    { action: "archive", categoryId: "category", expectedRevision: "3" },
    { action: "restore", categoryId: "category", expectedRevision: "4" },
    { action: "reorder", order: [{ categoryId: "category", expectedRevision: "5" }] }];
  for (const payload of actions) {
    const request = makeCategoryManagementRequest({ ...input, payload }, context);
    const envelope = JSON.parse(request.envelopeJSON);
    assert.deepEqual(envelope.payload, payload);
    assert.equal(envelope.accountId, context.accountId);
    assert.equal(envelope.actorPrincipalId, context.principalId);
    assert.deepEqual(envelope.preconditions, []);
  }
});

test("invalid shapes, names, revisions and caller-supplied scope fail before transport", async () => {
  const invalid: unknown[] = [{ ...input, accountId: "foreign" }, { ...input, principalId: "spoof" },
    { ...input, operationUUID: "not-a-uuid" }, { ...input, clientCreatedAtMilliseconds: 1.1 }];
  for (const name of ["", "\n", "a".repeat(101), "a\u0001b"]) invalid.push({ ...input, payload: { ...input.payload, name } });
  for (const revision of ["0", "01", "x", "1.1", "-1", "9223372036854775807"]) {
    invalid.push({ ...input, payload: { action: "archive", categoryId: "category", expectedRevision: revision } });
  }
  invalid.push({ ...input, payload: { action: "reorder", order: [
    { categoryId: "category", expectedRevision: "1" }, { categoryId: "category", expectedRevision: "1" }] } });
  invalid.push({ ...input, payload: { ...input.payload, specialFeeToGeneralVisibility: true } });
  for (const bad of invalid) {
    await assert.rejects(manageCategoriesTool(bad as CategoryManagementInput, context,
      { apply: async () => assert.fail("invalid input reached transport") }), { code: "category_payload_invalid" });
  }
});

test("HTTP uses one canonical envelope and scoped user credentials", async () => {
  const request = makeCategoryManagementRequest(input, context);
  const applier = new SupabaseCategoryManagementApplier(new URL("https://target.invalid"), "public-key", async (url, init) => {
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_manage_categories");
    assert.equal(init?.method, "POST"); assert.equal(init?.redirect, "error");
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    assert.equal(new Headers(init?.headers).get("apikey"), "public-key");
    assert.deepEqual(JSON.parse(init?.body as string), { p_envelope_json: request.envelopeJSON });
    return Response.json(terminal(request));
  });
  assert.equal((await manageCategoriesTool(input, context, applier)).phase, "applied");
});

test("terminal responses are bound to every identity and result field", () => {
  const request = makeCategoryManagementRequest(input, context);
  const wrong = { operation_id: "other", account_id: "other", actor_principal_id: "other", command_type: "create_client",
    contract_version: "unknown", command_fingerprint: "0".repeat(64), envelope_sha256: "0".repeat(64),
    request_sha256: "unexpected", subject_id: "hidden-category", client_created_at_ms: 1,
    server_received_at_ms: -1, completed_at_ms: 0, phase: "queued", result_code: "unknown", error_code: "unexpected" };
  for (const [key, value] of Object.entries(wrong)) {
    assert.throws(() => validateCategoryManagementResult({ ...terminal(request), [key]: value }, request),
      { code: "category_server_result_mismatch" });
  }
  const rejected = { ...terminal(request), phase: "rejected", result_code: null, error_code: "category_revision_conflict" };
  assert.equal(validateCategoryManagementResult(rejected, request).phase, "rejected");
  assert.throws(() => validateCategoryManagementResult({ ...rejected, error_code: "unknown" }, request),
    { code: "category_server_result_mismatch" });
});

test("service credentials and HTTP failures cannot report success", async () => {
  const privileged = `e30.${Buffer.from('{"role":"service_role"}').toString("base64url")}.signature`;
  for (const accessToken of ["", "sb_secret_forbidden", privileged]) {
    await assert.rejects(manageCategoriesTool(input, { ...context, accessToken },
      { apply: async () => assert.fail("privileged credential reached transport") }), { code: "category_credential_refused" });
    assert.throws(() => new SupabaseCategoryManagementApplier(new URL("https://target.invalid"), accessToken),
      { code: "category_credential_refused" });
  }
  for (const status of [401, 403, 409, 503]) {
    const applier = new SupabaseCategoryManagementApplier(new URL("https://target.invalid"), "public-key",
      async () => new Response("private server details", { status }));
    await assert.rejects(manageCategoriesTool(input, context, applier), { code: "category_request_rejected", statusCode: status });
  }
});

test("MCP host advertises and dispatches category changes, preserves rejections and sanitizes failures", async () => {
  let fails = false;
  const server = createTargetServer({ read: async () => assert.fail("wrong tool") }, context, undefined, {
    read: async identity => { assert.deepEqual(identity, context); return validateCategoryDirectory(directory(), context); },
    apply: async request => {
      if (fails) throw new Error("secret backend details");
      return { ...terminal(request), phase: "rejected", result_code: null, error_code: "category_name_unavailable" };
    },
  });
  const client = new Client({ name: "category-tests", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const tool = (await client.listTools()).tools.find(tool => tool.name === "manage_budget_categories");
    assert.ok(tool); assert.equal(tool.annotations?.readOnlyHint, false);
    const lookup = await client.callTool({ name: "list_budget_categories", arguments: {} });
    assert.ok(JSON.stringify(lookup).includes("9223372036854775807"));
    const foreignLookup = await client.callTool({ name: "list_budget_categories", arguments: { accountId: "foreign" } });
    assert.equal(foreignLookup.isError, true);
    const rejected = await client.callTool({ name: tool.name, arguments: input });
    assert.equal(rejected.isError, true);
    assert.ok(JSON.stringify(rejected).includes("category_name_unavailable"));
    const invalid = await client.callTool({ name: tool.name, arguments: { ...input, accountId: "foreign" } });
    assert.equal(invalid.isError, true);
    fails = true;
    const failure = await client.callTool({ name: tool.name, arguments: input });
    assert.equal(failure.isError, true);
    assert.ok(JSON.stringify(failure).includes("category_change_failed"));
    assert.ok(!JSON.stringify(failure).includes("secret backend"));
  } finally { await client.close(); await server.close(); }
});
