import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { makeInvoiceCreationRequest, validateInvoiceCreationResult, invoiceCreationTool,
  makeInvoiceRevisionRequest, validateInvoiceRevisionResult, invoiceRevisionTool, SupabaseInvoiceRevisionService,
  SupabaseInvoiceCreationService, type InvoiceCreationInput, type InvoiceCreationRequest } from "../src/invoiceCreation.js";
const context = { accountId: "account", principalId: "actor", accessToken: "user-token" };
const input: InvoiceCreationInput = { operationUUID: "00000000-0000-0000-0000-000000000001", clientCreatedAtMilliseconds: 100000,
  payload: { projectId: "project", clientId: "client", invoiceId: "invoice", name: "Phase 1", notes: "Notes",
    sources: [{ kind: "item", sourceId: "occurrence", expectedRevision: "9", amountMinorUnits: "9007199254740993", currency: "USD" }] } };
const result = (r: InvoiceCreationRequest) => ({ operation_id: r.operationId, account_id: r.accountId,
  actor_principal_id: r.actorPrincipalId, subject_id: r.invoiceId, command_type: "create_invoice", contract_version: "invoice-create-v1",
  command_fingerprint: r.fingerprint, envelope_sha256: r.fingerprint, request_sha256: null,
  client_created_at_ms: r.createdAtMs, server_received_at_ms: r.createdAtMs, completed_at_ms: r.createdAtMs,
  phase: "applied", result_code: "invoice_created", error_code: null });
test("Invoice revision shares exact encoding but has distinct identity and validated outcomes", async () => {
  const edit = {...input, expectedRevision: "9007199254740993"};
  const request = makeInvoiceRevisionRequest(edit, context);
  assert.deepEqual(makeInvoiceRevisionRequest(structuredClone(edit), context), request);
  assert.equal(JSON.parse(request.commandJSON).expectedRevision, edit.expectedRevision);
  assert.deepEqual(JSON.parse(request.commandJSON).sources, input.payload.sources);
  assert.notEqual(request.operationId, makeInvoiceCreationRequest(input, context).operationId);
  for (const expectedRevision of ["0", "-1", "01", "9223372036854775807", "garbage"]) {
    assert.throws(() => makeInvoiceRevisionRequest({...edit, expectedRevision}, context));
  }
  const row = {...result(request), command_type:"revise_created_invoice", contract_version:"invoice-revise-created-v1", result_code:"invoice_revised"};
  assert.equal(validateInvoiceRevisionResult(row, request).phase, "applied");
  assert.throws(() => validateInvoiceCreationResult(row, request));
  assert.throws(() => validateInvoiceRevisionResult(result(request), request));
  for (const field of ["operation_id", "account_id", "actor_principal_id", "subject_id", "command_fingerprint", "envelope_sha256"]) {
    assert.throws(() => validateInvoiceRevisionResult({...row,[field]:"wrong"}, request));
  }
  for (const error_code of ["invoice_revision_conflict", "invoice_not_editable", "invoice_unavailable", "invoice_source_changed"]) {
    assert.equal(validateInvoiceRevisionResult({...row,phase:"rejected",result_code:null,error_code},request).errorCode,error_code);
  }
  const service = new SupabaseInvoiceRevisionService(new URL("https://example.supabase.co"), "publishable", async (url, init) => {
    assert.equal(String(url), "https://example.supabase.co/rest/v1/rpc/spike_revise_created_invoice");
    assert.equal((init?.headers as Record<string,string>).Authorization,"Bearer user-token");
    assert.deepEqual(JSON.parse(String(init?.body)), {p_command:request.commandJSON});
    return Response.json(row);
  });
  assert.equal((await invoiceRevisionTool(edit,context,service)).phase,"applied");
  await assert.rejects(service.apply(request,{...context,accountId:"other"}));
  await assert.rejects(invoiceRevisionTool(edit,{...context,accessToken:"sb_secret_forbidden"},service));
  const server = createTargetServer({read:async()=>{throw new Error("unused");}},context,
    undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined,service);
  const [clientTransport,serverTransport] = InMemoryTransport.createLinkedPair();
  const client = new Client({name:"invoice-edit-test",version:"1"});
  await server.connect(serverTransport); await client.connect(clientTransport);
  try {
    assert.ok((await client.listTools()).tools.some(tool=>tool.name === "revise_created_invoice"));
    assert.equal((await client.callTool({name:"revise_created_invoice",arguments:edit})).isError,false);
  } finally { await client.close(); await server.close(); }
});
test("Invoice exact wire, identity and deterministic retry", () => {
  const request = makeInvoiceCreationRequest(input, context);
  assert.deepEqual(makeInvoiceCreationRequest(structuredClone(input), context), request);
  assert.equal(request.operationId, `invoice-create-${createHash("sha256").update("account").digest("hex")}-${input.operationUUID}`);
  assert.deepEqual(JSON.parse(request.commandJSON).sources, input.payload.sources);
  assert.equal(JSON.parse(request.commandJSON).createdAtMs, "100000");
  assert.notEqual(makeInvoiceCreationRequest(input, { ...context, accountId: "other" }).operationId, request.operationId);
});
test("Invoice malformed, duplicate, mixed-currency and overflow selections are denied", () => {
  const changes: ((v: InvoiceCreationInput) => void)[] = [
    v => { v.payload.sources.splice(0); }, v => { v.payload.sources.push({ ...v.payload.sources[0] }); },
    v => { v.payload.sources[0].expectedRevision = "garbage"; },
    v => { v.payload.sources[0].amountMinorUnits = "9223372036854775808"; },
    v => { v.payload.sources.push({ ...v.payload.sources[0], sourceId: "other", currency: "EUR" }); },
    v => { v.payload.sources[0].amountMinorUnits = "9223372036854775807";
      v.payload.sources.push({ ...v.payload.sources[0], sourceId: "other", amountMinorUnits: "1" }); },
  ];
  for (const change of changes) { const value = structuredClone(input); change(value); assert.throws(() => makeInvoiceCreationRequest(value, context)); }
});
test("Invoice result validation binds request and retains source rejection", async () => {
  const request = makeInvoiceCreationRequest(input, context), row = result(request);
  assert.equal(validateInvoiceCreationResult(row, request).phase, "applied");
  for (const key of ["operation_id", "account_id", "actor_principal_id", "subject_id", "command_type", "contract_version",
    "command_fingerprint", "envelope_sha256", "request_sha256", "result_code", "completed_at_ms"]) {
    assert.throws(() => validateInvoiceCreationResult({ ...row, [key]: "wrong" }, request));
  }
  assert.equal(validateInvoiceCreationResult({ ...row, phase: "rejected", result_code: null, error_code: "invoice_source_changed" }, request).errorCode,
    "invoice_source_changed");
  await assert.rejects(invoiceCreationTool(input, { ...context, accessToken: "sb_secret_forbidden" }, { apply: async () => row }));
});
test("Invoice provider uses scoped user RPC and server registration", async () => {
  const service = new SupabaseInvoiceCreationService(new URL("https://example.supabase.co"), "publishable", async (url, init) => {
    assert.equal(String(url), "https://example.supabase.co/rest/v1/rpc/spike_create_invoice");
    assert.equal((init?.headers as Record<string, string>).Authorization, "Bearer user-token");
    assert.equal(init?.redirect, "error");
    const request = makeInvoiceCreationRequest(input, context);
    assert.deepEqual(JSON.parse(String(init?.body)), { p_command: request.commandJSON });
    return Response.json(result(request));
  });
  assert.equal((await invoiceCreationTool(input, context, service)).phase, "applied");
  await assert.rejects(service.apply(makeInvoiceCreationRequest(input, context), { ...context, accountId: "other" }));
  const server = createTargetServer({ read: async () => { throw new Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined, service);
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "invoice-test", version: "1" });
  await server.connect(serverTransport); await client.connect(clientTransport);
  try {
    assert.ok((await client.listTools()).tools.some(tool => tool.name === "create_invoice"));
    assert.equal((await client.callTool({ name: "create_invoice", arguments: input })).isError, false);
  } finally { await client.close(); await server.close(); }
});
