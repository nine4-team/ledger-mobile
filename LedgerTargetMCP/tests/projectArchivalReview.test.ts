import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import { TargetMCPFailure, type TargetMCPRequestContext } from "../src/contractSupport.js";
import {
  archiveProjectTool,
  archiveProjectToolDefinition,
  listProjectNotesTool,
  listProjectNotesToolDefinition,
  makeProjectArchiveRPCRequest,
  makeProjectNotePageTransportRequest,
  SupabaseProjectArchiveApplier,
  SupabaseProjectNotePageReader,
  type ProjectArchiveApplying,
  type ProjectArchiveRPCRequest,
  type ProjectArchiveRPCResult,
  type ProjectNotePageReading,
  type ProjectNotePageTransportRequest,
  type ProjectNotePageTransportResult,
  type ProjectNoteTransport,
} from "../src/projectArchivalReview.js";

const context: TargetMCPRequestContext = {
  accountId: "account-primary",
  principalId: "principal-owner",
  accessToken: "user-access-token",
};
const accountHash = createHash("sha256").update(context.accountId).digest("hex");
const archiveInput = {
  operationId: `project-archive-${accountHash}-00000000-0000-0000-0000-000000000001`,
  projectId: "project-primary",
  expectedRevision: "7",
  projectCapturedAtMilliseconds: 1_788_600_000_000,
};

test("note request fingerprints are byte-identical to Swift with and without a cursor", () => {
  const first = makeProjectNotePageTransportRequest(
    { projectId: "project-primary", pageSize: 2 },
    context,
  );
  assert.equal(
    first.queryFingerprint,
    "b101bf9976f739e33ba8f73b6ab4ac738e384674cd2914ff6624796f953f2364",
  );
  assert.equal(first.after, null);

  const after = {
    accountId: context.accountId,
    projectId: "project-primary",
    createdAtMilliseconds: 1_788_600_000_000,
    noteId: "note-z",
  };
  const continuation = makeProjectNotePageTransportRequest(
    { projectId: "project-primary", pageSize: 2, after },
    context,
  );
  assert.equal(
    continuation.queryFingerprint,
    "255bb80755819962da920239c9e5425a3730b7ab8dc78dc77ca007f6b0b320b6",
  );
  assert.deepEqual(continuation.after, after);
});

test("note input is strictly bounded and a rebound cursor never reaches the reader", async () => {
  let calls = 0;
  const reader: ProjectNotePageReading = {
    async read(): Promise<ProjectNotePageTransportResult> {
      calls += 1;
      throw new Error("must not run");
    },
  };
  for (const pageSize of [0, 201, 1.5, Number.MAX_SAFE_INTEGER + 1]) {
    await assert.rejects(
      listProjectNotesTool({ projectId: "project-primary", pageSize }, context, reader),
      failure("project_note_page_size_invalid"),
    );
  }
  await assert.rejects(
    listProjectNotesTool({
      projectId: "project-primary",
      pageSize: 2,
      after: {
        accountId: "account-other",
        projectId: "project-primary",
        createdAtMilliseconds: 1_788_600_000_000,
        noteId: "note-z",
      },
    }, context, reader),
    failure("project_note_cursor_scope_mismatch"),
  );
  assert.equal(calls, 0);
});

test("authoritative note results enforce ordering, continuation, audit, scope, and decimal revision", async () => {
  const request = makeProjectNotePageTransportRequest(
    { projectId: "project-primary", pageSize: 2 },
    context,
  );
  const rows = [
    note("note-z", 1_788_600_000_000, "18446744073709551615"),
    note("note-a", 1_788_600_000_000, "9007199254740992"),
  ];
  const valid = page(request, rows, false);
  const reader: ProjectNotePageReading = { async read() { return valid; } };
  assert.deepEqual(
    (await listProjectNotesTool(
      { projectId: request.projectId, pageSize: request.pageSize },
      context,
      reader,
    )).rows.map((row) => row.revision),
    ["18446744073709551615", "9007199254740992"],
  );

  const invalidResults: ProjectNotePageTransportResult[] = [
    { ...valid, rows: [rows[1]!, rows[0]!] },
    { ...valid, rows: [rows[0]!, rows[0]!] },
    { ...valid, rows: [{ ...rows[0]!, accountId: "account-other" }] },
    { ...valid, rows: [{ ...rows[0]!, revision: "01" }] },
    { ...valid, isCompleteForProjectHistory: true },
    { ...valid, nextCursor: { ...valid.nextCursor!, noteId: "note-wrong" } },
  ];
  for (const invalid of invalidResults) {
    await assert.rejects(
      listProjectNotesTool(
        { projectId: request.projectId, pageSize: request.pageSize },
        context,
        { async read() { return invalid; } },
      ),
      failure("project_note_server_result_mismatch"),
    );
  }
});

test("note sources match Swift Unicode scalars and the 64-byte UTF-8 boundary", async () => {
  const request = makeProjectNotePageTransportRequest(
    { projectId: "project-primary", pageSize: 1 },
    context,
  );
  const sixtyFourByteUnicodeSource = "é".repeat(32);
  assert.equal(Buffer.byteLength(sixtyFourByteUnicodeSource, "utf8"), 64);
  const valid = page(
    request,
    [{ ...note("note-unicode", 1_788_600_000_000, "1"), source: sixtyFourByteUnicodeSource }],
    true,
  );
  assert.equal(
    (await listProjectNotesTool(
      { projectId: request.projectId, pageSize: request.pageSize },
      context,
      { async read() { return valid; } },
    )).rows[0]?.source,
    sixtyFourByteUnicodeSource,
  );

  const sixtyFiveByteUnicodeSource = `${sixtyFourByteUnicodeSource}a`;
  assert.equal(Buffer.byteLength(sixtyFiveByteUnicodeSource, "utf8"), 65);
  await assert.rejects(
    listProjectNotesTool(
      { projectId: request.projectId, pageSize: request.pageSize },
      context,
      {
        async read() {
          return {
            ...valid,
            rows: [{ ...valid.rows[0]!, source: sixtyFiveByteUnicodeSource }],
          };
        },
      },
    ),
    failure("project_note_server_result_mismatch"),
  );
});

test("note text and creator names reject the exact Foundation whitespace set", async () => {
  const request = makeProjectNotePageTransportRequest(
    { projectId: "project-primary", pageSize: 1 },
    context,
  );
  const foundationOnly = "\u0085\u200B";
  for (const invalidRow of [
    {
      ...note("note-blank-text", 1_788_600_000_000, "1"),
      content: { kind: "visible" as const, text: foundationOnly },
    },
    {
      ...note("note-blank-creator", 1_788_600_000_000, "1"),
      creatorDisplayName: foundationOnly,
    },
  ]) {
    await assert.rejects(
      listProjectNotesTool(
        { projectId: request.projectId, pageSize: request.pageSize },
        context,
        { async read() { return page(request, [invalidRow], true); } },
      ),
      failure("project_note_server_result_mismatch"),
    );
  }
});

test("equal-time note identifiers use Postgres and SQLite UTF-8 byte ordering", async () => {
  const request = makeProjectNotePageTransportRequest(
    { projectId: "project-primary", pageSize: 2 },
    context,
  );
  // UTF-8 orders the supplementary-plane letter after the high-BMP letter,
  // while JavaScript's default UTF-16 comparison orders this pair oppositely.
  const supplementaryLetterId = "𐐀";
  const highBMPLetterId = "Ａ";
  assert.ok(Buffer.compare(
    Buffer.from(supplementaryLetterId, "utf8"),
    Buffer.from(highBMPLetterId, "utf8"),
  ) > 0);
  assert.equal(supplementaryLetterId > highBMPLetterId, false);
  const correctlyOrdered = page(request, [
    note(supplementaryLetterId, 1_788_600_000_000, "2"),
    note(highBMPLetterId, 1_788_600_000_000, "1"),
  ], true);
  assert.deepEqual(
    (await listProjectNotesTool(
      { projectId: request.projectId, pageSize: request.pageSize },
      context,
      { async read() { return correctlyOrdered; } },
    )).rows.map((row) => row.id),
    [supplementaryLetterId, highBMPLetterId],
  );
  await assert.rejects(
    listProjectNotesTool(
      { projectId: request.projectId, pageSize: request.pageSize },
      context,
      {
        async read() {
          return page(request, [...correctlyOrdered.rows].reverse(), true);
        },
      },
    ),
    failure("project_note_server_result_mismatch"),
  );
});

test("note transport uses one scoped read RPC and decodes tombstones without fabricating local state", async () => {
  const request = makeProjectNotePageTransportRequest(
    { projectId: "project-primary", pageSize: 1 },
    context,
  );
  let observedURL: URL | undefined;
  let observedInit: RequestInit | undefined;
  const reader = new SupabaseProjectNotePageReader(
    new URL("http://127.0.0.1:54321"),
    "publishable-key",
    async (resource, init) => {
      observedURL = resource instanceof URL ? resource : new URL(String(resource));
      observedInit = init;
      return new Response(JSON.stringify({
        account_id: request.accountId,
        project_id: request.projectId,
        page_size: request.pageSize,
        query_fingerprint: request.queryFingerprint,
        rows: [{
          id: "note-z",
          account_id: request.accountId,
          project_id: request.projectId,
          content_kind: "tombstone",
          note_text: null,
          deleted_by_principal_id: "principal-editor",
          deleted_at_ms: 1_788_600_002_000,
          source: "manual",
          created_by_principal_id: "principal-owner",
          creator_display_name: "Jordan Lee",
          created_at_ms: 1_788_600_000_000,
          revision: "18446744073709551615",
          last_edited_by_principal_id: "principal-editor",
          last_edited_at_ms: 1_788_600_001_000,
        }],
        is_complete_for_project_history: true,
        next_cursor: null,
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    },
  );
  const result = await reader.read(request, context);
  assert.equal(observedURL?.pathname, "/rest/v1/rpc/spike_list_project_notes");
  assert.deepEqual(JSON.parse(String(observedInit?.body)), {
    p_account_id: request.accountId,
    p_project_id: request.projectId,
    p_page_size: 1,
    p_after_created_at_ms: null,
    p_after_note_id: null,
    p_query_fingerprint: request.queryFingerprint,
  });
  assert.equal((observedInit?.headers as Record<string, string>).apikey, "publishable-key");
  assert.equal(
    (observedInit?.headers as Record<string, string>).Authorization,
    "Bearer user-access-token",
  );
  assert.deepEqual(result.rows[0]?.content, {
    kind: "tombstone",
    deletion: {
      deletedByPrincipalId: "principal-editor",
      deletedAtMilliseconds: 1_788_600_002_000,
    },
  });
  assert.equal("local" in result, false);
  assert.equal("readiness" in result, false);
});

test("archive request matches canonical Swift/Postgres bytes and request hash", () => {
  const request = makeProjectArchiveRPCRequest(archiveInput, context);
  assert.equal(
    request.envelopeJSON,
    `{"accountId":"account-primary","actorPrincipalId":"principal-owner",`
      + `"clientCreatedAt":1788600000000,"contractVersion":"project-archive-v1",`
      + `"operationId":"${archiveInput.operationId}","payload":{"projectId":"project-primary"},`
      + `"preconditions":[{"expectedRevision":{"revision":7,`
      + `"subject":{"id":"project-primary","kind":"project"}}}]}`,
  );
  assert.equal(request.fingerprint, sha256(request.envelopeJSON));
  assert.equal(request.requestSHA256, archiveRequestSHA256(request));
  assert.equal(
    request.fingerprint,
    "0603bc59f95269c51fa83e1699fea55f746871d2f26b6db85486696199ea1e96",
  );
  assert.equal(
    request.requestSHA256,
    "54d370b2284d6f9028ffb0594b98599ccaf5e1d9d6bd914eafde446336a7f6bb",
  );
});

test("archive preserves the full UInt64 boundary and rejects noncanonical evidence", () => {
  for (const revision of [
    "0", "9007199254740991", "9007199254740992",
    "9223372036854775807", "18446744073709551615",
  ]) {
    const request = makeProjectArchiveRPCRequest(
      { ...archiveInput, expectedRevision: revision },
      context,
    );
    assert.equal(request.expectedRevision, revision);
    assert.match(request.envelopeJSON, new RegExp(`"revision":${revision},`));
  }
  for (const revision of ["-1", "+1", "01", "1.0", "18446744073709551616"]) {
    assert.throws(
      () => makeProjectArchiveRPCRequest({ ...archiveInput, expectedRevision: revision }, context),
      failure("project_archive_expected_revision_invalid"),
    );
  }
  assert.throws(
    () => makeProjectArchiveRPCRequest({
      ...archiveInput,
      operationId: archiveInput.operationId.replace(accountHash, "0".repeat(64)),
    }, context),
    failure("project_archive_operation_id_invalid"),
  );
});

test("archive tool validates exact applied and rejected terminal identity", async () => {
  const request = makeProjectArchiveRPCRequest(archiveInput, context);
  const applied = archiveResult(request);
  const applier: ProjectArchiveApplying = { async apply() { return applied; } };
  assert.equal((await archiveProjectTool(archiveInput, context, applier)).phase, "applied");

  const rejected: ProjectArchiveRPCResult = {
    ...applied,
    phase: "rejected",
    resultCode: null,
    errorCode: "project_archive_revision_conflict",
  };
  assert.equal((await archiveProjectTool(
    archiveInput,
    context,
    { async apply() { return rejected; } },
  )).errorCode, "project_archive_revision_conflict");

  for (const invalid of [
    { ...applied, subjectId: "project-other" },
    { ...applied, requestSHA256: "0".repeat(64) },
    { ...applied, resultCode: "project_restored" },
    { ...rejected, errorCode: "unknown" },
  ] as ProjectArchiveRPCResult[]) {
    await assert.rejects(
      archiveProjectTool(archiveInput, context, { async apply() { return invalid; } }),
      failure("project_archive_server_result_mismatch"),
    );
  }
});

test("archive transport reuses the existing scoped RPC exactly", async () => {
  const request = makeProjectArchiveRPCRequest(archiveInput, context);
  let observedURL: URL | undefined;
  let observedInit: RequestInit | undefined;
  const applier = new SupabaseProjectArchiveApplier(
    new URL("http://127.0.0.1:54321"),
    "publishable-key",
    async (resource, init) => {
      observedURL = resource instanceof URL ? resource : new URL(String(resource));
      observedInit = init;
      const result = archiveResult(request);
      return new Response(JSON.stringify({
        operation_id: result.operationId,
        account_id: result.accountId,
        actor_principal_id: result.actorPrincipalId,
        command_type: result.commandType,
        contract_version: result.contractVersion,
        command_fingerprint: result.commandFingerprint,
        envelope_sha256: result.envelopeSHA256,
        request_sha256: result.requestSHA256,
        subject_id: result.subjectId,
        phase: result.phase,
        result_code: result.resultCode,
        error_code: result.errorCode,
        client_created_at_ms: result.projectCapturedAtMilliseconds,
        server_received_at_ms: result.serverReceivedAtMilliseconds,
        completed_at_ms: result.completedAtMilliseconds,
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    },
  );
  assert.equal((await applier.apply(request, context)).phase, "applied");
  assert.equal(observedURL?.pathname, "/rest/v1/rpc/spike_archive_project");
  const body = JSON.parse(String(observedInit?.body)) as Record<string, unknown>;
  assert.equal(body.p_expected_revision, "7");
  assert.equal(body.p_envelope_json, request.envelopeJSON);
  assert.equal((observedInit?.headers as Record<string, string>).apikey, "publishable-key");
  assert.equal(
    (observedInit?.headers as Record<string, string>).Authorization,
    "Bearer user-access-token",
  );
});

test("HTTP failures distinguish auth, denial, invalid requests, and retryable infrastructure", async () => {
  const noteRequest = makeProjectNotePageTransportRequest(
    { projectId: "project-primary", pageSize: 1 },
    context,
  );
  const archiveRequest = makeProjectArchiveRPCRequest(archiveInput, context);
  const cases: Array<[number, string, string]> = [
    [400, "project_note_request_invalid", "project_archive_request_invalid"],
    [401, "authentication_required", "authentication_required"],
    [403, "project_note_request_denied", "project_archive_request_denied"],
    [500, "project_note_request_rejected", "project_archive_request_rejected"],
  ];
  for (const [status, noteCode, archiveCode] of cases) {
    const response = async () => new Response("{}", {
      status,
      headers: { "Content-Type": "application/json" },
    });
    const reader = new SupabaseProjectNotePageReader(
      new URL("http://127.0.0.1:54321"),
      "publishable-key",
      response,
    );
    await assert.rejects(
      reader.read(noteRequest, context),
      (error) => error instanceof TargetMCPFailure
        && error.code === noteCode
        && error.statusCode === status,
    );
    const applier = new SupabaseProjectArchiveApplier(
      new URL("http://127.0.0.1:54321"),
      "publishable-key",
      response,
    );
    await assert.rejects(
      applier.apply(archiveRequest, context),
      (error) => error instanceof TargetMCPFailure
        && error.code === archiveCode
        && error.statusCode === status,
    );
  }
});

test("public credential guard refuses service-role keys and tokens before fetch", async () => {
  const serviceRoleJWT = `x.${Buffer.from(JSON.stringify({ role: "service_role" })).toString("base64url")}.x`;
  assert.throws(
    () => new SupabaseProjectNotePageReader(new URL("https://target.invalid"), "sb_secret_key"),
    failure("project_note_configuration_invalid"),
  );
  assert.throws(
    () => new SupabaseProjectArchiveApplier(new URL("https://target.invalid"), serviceRoleJWT),
    failure("project_archive_configuration_invalid"),
  );
  const noFetchReader: ProjectNotePageReading = {
    async read() { throw new Error("must not run"); },
  };
  await assert.rejects(
    listProjectNotesTool(
      { projectId: "project-primary", pageSize: 1 },
      { ...context, accessToken: serviceRoleJWT },
      noFetchReader,
    ),
    failure("authentication_required"),
  );
});

test("definitions expose only the two gated narrow responsibilities", () => {
  assert.equal(listProjectNotesToolDefinition.name, "list_project_notes");
  assert.equal(archiveProjectToolDefinition.name, "archive_project");
  const definitions = JSON.stringify([
    listProjectNotesToolDefinition,
    archiveProjectToolDefinition,
  ]).toLowerCase();
  for (const forbidden of [
    "add_project_note", "search_project_notes", "restore", "unarchive",
    "delete", "firebase", "service_role",
  ]) {
    assert.doesNotMatch(definitions, new RegExp(forbidden));
  }
});

function note(id: string, createdAtMilliseconds: number, revision: string): ProjectNoteTransport {
  return {
    id,
    accountId: context.accountId,
    projectId: "project-primary",
    content: { kind: "visible", text: `Visible ${id}` },
    source: "manual",
    createdByPrincipalId: context.principalId,
    creatorDisplayName: "Jordan Lee",
    createdAtMilliseconds,
    revision,
    lastEditedByPrincipalId: null,
    lastEditedAtMilliseconds: null,
  };
}

function page(
  request: ProjectNotePageTransportRequest,
  rows: readonly ProjectNoteTransport[],
  complete: boolean,
): ProjectNotePageTransportResult {
  const last = rows.at(-1);
  return {
    accountId: request.accountId,
    projectId: request.projectId,
    pageSize: request.pageSize,
    queryFingerprint: request.queryFingerprint,
    rows,
    isCompleteForProjectHistory: complete,
    nextCursor: complete || last === undefined ? null : {
      accountId: request.accountId,
      projectId: request.projectId,
      createdAtMilliseconds: last.createdAtMilliseconds,
      noteId: last.id,
    },
  };
}

function archiveResult(request: ProjectArchiveRPCRequest): ProjectArchiveRPCResult {
  return {
    operationId: request.operationId,
    accountId: request.accountId,
    actorPrincipalId: request.actorPrincipalId,
    commandType: "archive_project",
    contractVersion: "project-archive-v1",
    commandFingerprint: request.fingerprint,
    envelopeSHA256: request.fingerprint,
    requestSHA256: request.requestSHA256,
    subjectId: request.projectId,
    phase: "applied",
    resultCode: "project_archived",
    errorCode: null,
    projectCapturedAtMilliseconds: request.projectCapturedAtMilliseconds,
    serverReceivedAtMilliseconds: request.projectCapturedAtMilliseconds + 1,
    completedAtMilliseconds: request.projectCapturedAtMilliseconds + 2,
  };
}

function archiveRequestSHA256(request: ProjectArchiveRPCRequest): string {
  const fields = [
    request.operationId, request.accountId, request.actorPrincipalId,
    request.contractVersion, String(request.projectCapturedAtMilliseconds),
    request.projectId, request.expectedRevision, request.fingerprint,
    request.envelopeJSON,
  ];
  return sha256(
    `project-archive-request-v1|${fields.map((field) => (
      `v${Buffer.byteLength(field, "utf8")}:${field}`
    )).join("")}`,
  );
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function failure(code: string): (error: unknown) => boolean {
  return (error) => error instanceof TargetMCPFailure && error.code === code;
}
