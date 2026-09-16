import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createTargetServer } from "../src/server.js";
import { makeExpenseCreationRequest, makeExpenseEditRequest, expenseEditInputSchema, validateExpenseEditResult, expenseCreationTool, validateExpenseCreationResult, validateExpenseSnapshot, validateExpenseInvoice,
  SupabaseExpenseCreationService, type ExpenseCreationInput } from "../src/expenseCreation.js";

const context = { accountId: "account", principalId: "actor", accessToken: "user-token" };
const input: ExpenseCreationInput = {
  operationUUID: "00000000-0000-0000-0000-000000000001", clientCreatedAtMilliseconds: 123000,
  payload: { projectId: "project", expenseId: "expense", vendor: "Original/vendor", date: "2024-02-29",
    amountMinorUnits: "9223372036854775807", currency: "USD", categoryId: "category", notes: "Original notes",
    receiptLines: [{ id: "line", description: "Delivery", magnitudeMinorUnits: "1025", currency: "USD",
      effect: "increase", quantity: null }], receiptAttachmentIds: ["receipt"] },
};
const request = makeExpenseCreationRequest(input, context);
const snapshot = () => ({ ...structuredClone(input.payload), accountId: context.accountId, revision: "1" });
test("Expense paid read reuses exact Invoice validation and preserves unknown status", async () => {
  const query = { projectId: "project", expenseId: "expense" };
  const value = { expense: snapshot(), invoice: { invoice_id: "invoice", invoice_revision: "1", account_id: "account",
    project_id: "project", client_id: "client", purchase_id: "payment", currency: "USD", total_minor_units: input.payload.amountMinorUnits,
    lines: [{ id: "paid-line", line_position: 0, source_kind: "expense", source_id: "expense", item_id: null,
      source_revision: "1", category_id: "historical-category", signed_amount_minor_units: input.payload.amountMinorUnits,
      description: "Historical vendor", source_snapshot_json: JSON.stringify({ expense: { expenseId: "expense" } }) }] } };
  assert.deepEqual(validateExpenseInvoice(value,query,context),value);
  assert.equal(validateExpenseInvoice({ expense: snapshot(), invoice: null },query,context).invoice,null);
  for (const change of [
    v => { v.invoice.account_id = "other"; }, v => { v.invoice.lines[0].source_revision = "2"; },
    v => { v.invoice.lines[0].source_id = "other"; }, v => { v.invoice.total_minor_units = "1"; },
    v => { v.invoice.lines[0].source_snapshot_json = "{}"; },
  ] satisfies ((v: typeof value) => void)[]) {
    const changed = structuredClone(value); change(changed);
    assert.throws(() => validateExpenseInvoice(changed,query,context));
  }
  const service = new SupabaseExpenseCreationService(new URL("https://example.invalid"),"public-key",async (url,init) => {
    assert.equal(new URL(String(url)).pathname,"/rest/v1/rpc/spike_read_expense_invoice");
    assert.equal((init?.headers as Record<string,string>).Authorization,"Bearer user-token");
    assert.deepEqual(JSON.parse(String(init?.body)),{p_account_id:"account",p_project_id:"project",p_expense_id:"expense"});
    return new Response(JSON.stringify(value),{status:200});
  });
  assert.deepEqual(await service.invoice(query,context),value);
  const server = createTargetServer({ read: async () => { throw new Error("unused"); } },context,
    undefined,undefined,undefined,undefined,undefined,undefined,service);
  const client = new Client({ name: "expense-invoice-test", version: "1" });
  const [a,b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const result = await client.callTool({ name: "get_expense_invoice", arguments: query });
    assert.ok(!result.isError);
    assert.deepEqual(JSON.parse((result.content as { text: string }[])[0].text),value);
  } finally { await client.close(); await server.close(); }
});
const terminal = () => ({ operation_id: request.operationId, account_id: "account", actor_principal_id: "actor",
  subject_id: "expense", command_type: "create_expense", contract_version: "expense-create-v1",
  command_fingerprint: request.fingerprint, envelope_sha256: request.fingerprint, request_sha256: null,
  client_created_at_ms: 123000, server_received_at_ms: 124000, completed_at_ms: 124000,
  phase: "applied", result_code: "expense_created", error_code: null });

test("Expense edit reuses validation, authenticated transport and registered tool", async () => {
  const editInput = { ...input, expectedRevision: "2" };
  const edit = makeExpenseEditRequest(editInput, context);
  assert.equal(edit.fingerprint, "db5ccf77710ea81173301ba79d39d2772ade9becee4f98467669edc02816ac60");
  const result = { ...terminal(), operation_id: edit.operationId, command_type: "edit_expense",
    contract_version: "expense-edit-v1", command_fingerprint: edit.fingerprint,
    envelope_sha256: edit.fingerprint, result_code: "expense_edited" };
  assert.equal(JSON.parse(edit.commandJSON).expectedRevision, "2");
  assert.equal(JSON.parse(edit.commandJSON).amountMinorUnits, input.payload.amountMinorUnits);
  assert.notEqual(edit.operationId, request.operationId);
  assert.throws(() => validateExpenseEditResult(terminal(), edit));
  for (const revision of ["0", "-1", "01", "9223372036854775807"]) {
    assert.equal(expenseEditInputSchema.safeParse({ ...editInput, expectedRevision: revision }).success, false);
  }
  const service = new SupabaseExpenseCreationService(new URL("https://example.invalid"), "public-key", async (url, init) => {
    assert.equal(new URL(String(url)).pathname, "/rest/v1/rpc/spike_edit_expense");
    assert.equal((init?.headers as Record<string,string>).Authorization, "Bearer user-token");
    assert.deepEqual(JSON.parse(String(init?.body)), { p_command: edit.commandJSON });
    return new Response(JSON.stringify(result), { status: 200 });
  });
  const server = createTargetServer({ read: async () => { throw new Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, undefined, service);
  const client = new Client({ name: "expense-edit-test", version: "1" });
  const [a,b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    const reply = await client.callTool({ name: "edit_expense", arguments: editInput });
    assert.ok(!reply.isError);
    assert.equal(JSON.parse((reply.content as { text: string }[])[0].text).resultCode, "expense_edited");
  } finally { await client.close(); await server.close(); }
  assert.equal(validateExpenseEditResult({ ...result, phase: "rejected", result_code: null,
    error_code: "expense_revision_conflict" }, edit).phase, "rejected");
});

test("exact money, explicit null, source order and stable account-bound retry", () => {
  assert.deepEqual(makeExpenseCreationRequest(structuredClone(input), context), request);
  // Same vector is exercised by native CreateExpenseUploadRequestTests.
  assert.equal(request.fingerprint, "21c1aad8eefef9ea5025285e9e63ff978f1f97a19274c36a6005e581cf299356");
  const wire = JSON.parse(request.commandJSON);
  assert.equal(wire.amountMinorUnits, "9223372036854775807");
  assert.equal(wire.receiptLines[0].quantity, null);
  assert.equal(wire.vendor, "Original/vendor");
  assert.equal(wire.contractVersion, "expense-create-v1");
  assert.notEqual(makeExpenseCreationRequest(input, { ...context, accountId: "other" }).operationId, request.operationId);
  const signed = structuredClone(input);
  signed.payload.receiptLines[0].quantity = "-9223372036854775808";
  signed.payload.receiptLines[0].effect = "decrease";
  assert.equal(JSON.parse(makeExpenseCreationRequest(signed, context).commandJSON).receiptLines[0].quantity, "-9223372036854775808");
});
test("Expense reads preserve exact source evidence and reject wrong scope, malformed references and extra data", () => {
  assert.deepEqual(validateExpenseSnapshot(snapshot(), { projectId: "project", expenseId: "expense" }, context), snapshot());
  for (const change of [{ accountId: "foreign" }, { projectId: "foreign" }, { expenseId: "foreign" },
    { revision: "0" }, { revision: "9223372036854775808" }, { amountMinorUnits: 123 },
    { receiptAttachmentIds: ["receipt", "receipt"] }, { signedURL: "secret" }]) {
    assert.throws(() => validateExpenseSnapshot({ ...snapshot(), ...change },
      { projectId: "project", expenseId: "expense" }, context));
  }
});
test("authorized Expense HTTP and MCP read expose only validated requested records", async () => {
  const selection = { projectId: "project", expenseId: "expense" };
  let calls = 0;
  const service = new SupabaseExpenseCreationService(new URL("https://target.invalid"), "public-key", async (url, init) => {
    calls++;
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_read_expense");
    assert.deepEqual(JSON.parse(init?.body as string), { p_account_id: "account", p_project_id: "project", p_expense_id: "expense" });
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    return Response.json(snapshot());
  });
  assert.deepEqual(await service.read(selection, context), snapshot());
  await assert.rejects(service.read(selection, { ...context, accessToken: "sb_secret_privileged" }));
  assert.equal(calls, 1);
  let foreign = false;
  const server = createTargetServer({ read: async () => { throw Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, undefined, undefined,
    { read: async () => ({ ...snapshot(), accountId: foreign ? "foreign" : "account" }),
      receipt: async () => ({ mimeType: "application/pdf", bytes: Buffer.from("receipt bytes") }) });
  const client = new Client({ name: "expense-read-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    assert.ok((await client.listTools()).tools.some(tool => tool.name === "get_expense"));
    const result = await client.callTool({ name: "get_expense", arguments: selection });
    assert.notEqual(result.isError, true);
    assert.match(JSON.stringify(result.content), /9223372036854775807/);
    const receipt = await client.callTool({ name: "get_expense_receipt", arguments: { ...selection, attachmentId: "receipt" } });
    assert.notEqual(receipt.isError, true);
    const content = receipt.content as { type: string; resource: { uri: string; mimeType: string; blob: string } }[];
    assert.equal(content[0].type, "resource");
    assert.equal(content[0].resource.mimeType, "application/pdf");
    assert.equal(Buffer.from(content[0].resource.blob, "base64").toString(), "receipt bytes");
    assert.equal(content[0].resource.uri, "ledger-expense-receipt://account/expense/receipt");
    foreign = true;
    const denied = await client.callTool({ name: "get_expense", arguments: selection });
    assert.equal(denied.isError, true);
    assert.doesNotMatch(JSON.stringify(denied.content), /Original.notes/);
  } finally { await client.close(); await server.close(); }
});
test("malformed dates, inexact amounts, duplicate references and cross-currency lines fail before sending", () => {
  for (const change of [{ date: "2023-02-29" }, { date: "2024-04-31" }, { date: "0000-01-01" },
    { amountMinorUnits: "9223372036854775808" }, { amountMinorUnits: "1.5" }, { amountMinorUnits: "-0" },
    { amountMinorUnits: 1 }, { receiptAttachmentIds: ["receipt", "receipt"] },
    { receiptLines: [input.payload.receiptLines[0], input.payload.receiptLines[0]] },
    { receiptLines: [{ ...input.payload.receiptLines[0], currency: "EUR" }] },
    { receiptLines: [{ ...input.payload.receiptLines[0], magnitudeMinorUnits: "1.5" }] },
    { receiptLines: [{ ...input.payload.receiptLines[0], quantity: "1.5" }] }]) {
    assert.throws(() => makeExpenseCreationRequest({ ...input, payload: { ...input.payload, ...change } } as ExpenseCreationInput, context));
  }
});
test("receipt bytes require exact object identity/hash/length and renewed Expense authorization", async () => {
  const bytes = Buffer.from("%PDF-1.7\nreceipt fixture"), hash = createHash("sha256").update(bytes).digest("hex");
  const selection = { projectId: "project", expenseId: "expense", attachmentId: "receipt" };
  for (const mode of ["valid", "wrong-path", "wrong-account", "oversized", "short", "wrong-hash", "revoked", "unlinked"] as const) {
    let reads = 0, downloads = 0;
    const service = new SupabaseExpenseCreationService(new URL("https://target.invalid"), "public-key", async (url, init) => {
      assert.equal(init?.redirect, "error");
      assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
      const path = new URL(String(url)).pathname;
      if (path.endsWith("spike_read_expense")) {
        reads++;
        if (mode === "revoked" && reads === 2) return new Response(null, { status: 403 });
        return Response.json({ ...snapshot(), receiptAttachmentIds: mode === "unlinked" ? [] : ["receipt"] });
      }
      if (path.endsWith("item_image_objects")) return Response.json([{ id: "receipt",
        account_id: mode === "wrong-account" ? "foreign" : "account", content_sha256: hash,
        byte_count: bytes.length, media_type: "application/pdf",
        storage_path: mode === "wrong-path" ? "https://evil.invalid/secret" : `accounts/account/attachments/receipt/${hash}` }]);
      downloads++;
      assert.equal(path, `/storage/v1/object/authenticated/ledger-attachments/accounts/account/attachments/receipt/${hash}`);
      return new Response(mode === "oversized" ? Buffer.concat([bytes, bytes]) : mode === "short" ? bytes.subarray(1)
        : mode === "wrong-hash" ? Buffer.alloc(bytes.length) : bytes);
    });
    if (mode === "valid") {
      const result = await service.receipt(selection, context);
      assert.deepEqual(Buffer.from(result.bytes), bytes); assert.equal(result.mimeType, "application/pdf");
      assert.equal(reads, 2);
    } else await assert.rejects(service.receipt(selection, context));
    if (["wrong-path", "wrong-account", "unlinked"].includes(mode)) assert.equal(downloads, 0);
  }
});
test("server receipts must match identity, scope, digest, timestamps and exact outcome", () => {
  assert.equal(validateExpenseCreationResult(terminal(), request).phase, "applied");
  for (const [key, value] of Object.entries({ operation_id: "wrong", account_id: "foreign", actor_principal_id: "foreign",
    subject_id: "foreign", command_type: "create_payment", contract_version: "wrong", command_fingerprint: "wrong",
    envelope_sha256: "wrong", request_sha256: "wrong", client_created_at_ms: 1, completed_at_ms: 0,
    server_received_at_ms: -1, result_code: "payment_created", error_code: "unexpected" })) {
    assert.throws(() => validateExpenseCreationResult({ ...terminal(), [key]: value }, request));
  }
  assert.equal(validateExpenseCreationResult({ ...terminal(), phase: "rejected", result_code: null,
    error_code: "expense_receipt_invalid" }, request).phase, "rejected");
  assert.throws(() => validateExpenseCreationResult({ ...terminal(), phase: "rejected", result_code: null,
    error_code: "unknown" }, request));
});
test("HTTP sends the exact existing command under user credentials, never privileged or cross-account", async () => {
  let calls = 0;
  const service = new SupabaseExpenseCreationService(new URL("https://target.invalid"), "public-key", async (url, init) => {
    calls++;
    assert.equal(String(url), "https://target.invalid/rest/v1/rpc/spike_create_expense");
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer user-token");
    assert.equal(init?.redirect, "error");
    assert.deepEqual(JSON.parse(init?.body as string), { p_command: request.commandJSON });
    return Response.json(terminal());
  });
  assert.equal((await expenseCreationTool(input, context, service)).phase, "applied");
  await assert.rejects(service.apply(request, { ...context, accountId: "foreign" }));
  await assert.rejects(expenseCreationTool(input, { ...context, accessToken: "sb_secret_privileged" }, service));
  assert.equal(calls, 1);
});
test("MCP advertises Expense creation and reports rejection without exposing raw errors", async () => {
  let throwsPrivateError = false;
  const server = createTargetServer({ read: async () => { throw Error("unused"); } }, context,
    undefined, undefined, undefined, undefined, undefined, { apply: async () => {
      if (throwsPrivateError) throw Error("private secret");
      return { ...terminal(), phase: "rejected", result_code: null, error_code: "expense_category_unavailable" };
    } });
  const client = new Client({ name: "expense-test", version: "1" });
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.connect(a); await client.connect(b);
  try {
    assert.ok((await client.listTools()).tools.some(tool => tool.name === "create_expense"));
    const rejected = await client.callTool({ name: "create_expense", arguments: input });
    assert.equal(rejected.isError, true);
    assert.match(JSON.stringify(rejected.content), /expense_category_unavailable/);
    throwsPrivateError = true;
    const failed = await client.callTool({ name: "create_expense", arguments: input });
    assert.equal(failed.isError, true);
    assert.doesNotMatch(JSON.stringify(failed.content), /private secret/);
  } finally { await client.close(); await server.close(); }
});
