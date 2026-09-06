import { createHash } from "node:crypto";
import {
  canonicalJSON,
  TargetMCPFailure,
  validateIdentifier,
  type TargetMCPRequestContext,
} from "./contractSupport.js";

const ARCHIVE_CONTRACT_VERSION = "project-archive-v1";
const NOTE_PAGE_MAXIMUM = 200;
const UINT64_MAXIMUM = 18_446_744_073_709_551_615n;
const FOUNDATION_WHITESPACE_ONLY = /^[\u0009-\u000D\u0020\u0085\u00A0\u1680\u2000-\u200B\u2028\u2029\u202F\u205F\u3000]*$/u;
const ARCHIVE_REJECTION_CODES = new Set([
  "contract_unsupported",
  "project_archive_command_encoding_invalid",
  "project_archive_envelope_mismatch",
  "project_archive_fingerprint_mismatch",
  "project_archive_payload_invalid",
  "project_archive_revision_conflict",
]);

export type ProjectNoteCursorTransport = Readonly<{
  accountId: string;
  projectId: string;
  createdAtMilliseconds: number;
  noteId: string;
}>;

export type ListProjectNotesToolInput = Readonly<{
  projectId: string;
  pageSize: number;
  after?: ProjectNoteCursorTransport;
}>;

export type ProjectNoteContentTransport =
  | Readonly<{ kind: "visible"; text: string }>
  | Readonly<{
    kind: "tombstone";
    deletion: Readonly<{
      deletedByPrincipalId: string;
      deletedAtMilliseconds: number;
    }>;
  }>;

export type ProjectNoteTransport = Readonly<{
  id: string;
  accountId: string;
  projectId: string;
  content: ProjectNoteContentTransport;
  source: string;
  createdByPrincipalId: string;
  creatorDisplayName: string | null;
  createdAtMilliseconds: number;
  revision: string;
  lastEditedByPrincipalId: string | null;
  lastEditedAtMilliseconds: number | null;
}>;

export type ProjectNotePageTransportRequest = Readonly<{
  accountId: string;
  projectId: string;
  pageSize: number;
  after: ProjectNoteCursorTransport | null;
  queryFingerprint: string;
}>;

/** An authoritative online page; it deliberately carries no local readiness. */
export type ProjectNotePageTransportResult = Readonly<{
  accountId: string;
  projectId: string;
  pageSize: number;
  queryFingerprint: string;
  rows: readonly ProjectNoteTransport[];
  isCompleteForProjectHistory: boolean;
  nextCursor: ProjectNoteCursorTransport | null;
}>;

export interface ProjectNotePageReading {
  read(
    request: ProjectNotePageTransportRequest,
    context: TargetMCPRequestContext,
  ): Promise<ProjectNotePageTransportResult>;
}

export function makeProjectNotePageTransportRequest(
  input: ListProjectNotesToolInput,
  context: TargetMCPRequestContext,
): ProjectNotePageTransportRequest {
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  validateIdentifier(context.principalId, "account_not_authorized");
  const projectId = validateIdentifier(input.projectId, "project_note_project_id_invalid");
  if (!Number.isInteger(input.pageSize)
    || input.pageSize < 1
    || input.pageSize > NOTE_PAGE_MAXIMUM) {
    throw new TargetMCPFailure("project_note_page_size_invalid");
  }

  let after: ProjectNoteCursorTransport | null = null;
  if (input.after !== undefined) {
    const cursorAccountId = validateIdentifier(
      input.after.accountId,
      "project_note_cursor_invalid",
    );
    const cursorProjectId = validateIdentifier(
      input.after.projectId,
      "project_note_cursor_invalid",
    );
    const noteId = validateIdentifier(input.after.noteId, "project_note_cursor_invalid");
    validateMilliseconds(input.after.createdAtMilliseconds, "project_note_cursor_invalid");
    if (cursorAccountId !== accountId || cursorProjectId !== projectId) {
      throw new TargetMCPFailure("project_note_cursor_scope_mismatch");
    }
    after = {
      accountId: cursorAccountId,
      projectId: cursorProjectId,
      createdAtMilliseconds: input.after.createdAtMilliseconds,
      noteId,
    };
  }

  // Swift's synthesized Optional encoding omits `after` when nil.
  const fingerprintBasis: Record<string, unknown> = {
    accountId,
    pageSize: input.pageSize,
    projectId,
  };
  if (after !== null) {
    fingerprintBasis.after = {
      accountId: after.accountId,
      createdAt: after.createdAtMilliseconds,
      noteId: after.noteId,
      projectId: after.projectId,
    };
  }
  const encoded = canonicalJSON(
    fingerprintBasis,
    "project_note_query_fingerprint_mismatch",
  );
  return {
    accountId,
    projectId,
    pageSize: input.pageSize,
    after,
    queryFingerprint: sha256(encoded),
  };
}

export async function listProjectNotesTool(
  input: ListProjectNotesToolInput,
  context: TargetMCPRequestContext,
  reader: ProjectNotePageReading,
): Promise<ProjectNotePageTransportResult> {
  requirePublicCredential(context.accessToken, "authentication_required");
  const request = makeProjectNotePageTransportRequest(input, context);
  const result = await reader.read(request, context);
  try {
    validateProjectNotePageResult(result, request);
  } catch (error) {
    if (error instanceof TargetMCPFailure) throw error;
    throw new TargetMCPFailure("project_note_server_result_mismatch");
  }
  return result;
}

export class SupabaseProjectNotePageReader implements ProjectNotePageReading {
  readonly #rpcURL: URL;
  readonly #publishableKey: string;
  readonly #fetch: typeof fetch;

  constructor(
    supabaseURL: URL,
    publishableKey: string,
    fetchImplementation: typeof fetch = fetch,
  ) {
    validateBaseURL(supabaseURL, "project_note_configuration_invalid");
    requirePublicCredential(publishableKey, "project_note_configuration_invalid");
    this.#rpcURL = new URL("/rest/v1/rpc/spike_list_project_notes", supabaseURL);
    this.#publishableKey = publishableKey;
    this.#fetch = fetchImplementation;
  }

  async read(
    request: ProjectNotePageTransportRequest,
    context: TargetMCPRequestContext,
  ): Promise<ProjectNotePageTransportResult> {
    requirePublicCredential(context.accessToken, "authentication_required");
    const response = await this.#fetch(this.#rpcURL, {
      method: "POST",
      headers: {
        Accept: "application/vnd.pgrst.object+json",
        apikey: this.#publishableKey,
        Authorization: `Bearer ${context.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_account_id: request.accountId,
        p_project_id: request.projectId,
        p_page_size: request.pageSize,
        p_after_created_at_ms: request.after?.createdAtMilliseconds ?? null,
        p_after_note_id: request.after?.noteId ?? null,
        p_query_fingerprint: request.queryFingerprint,
      }),
    });
    if (!response.ok) {
      throwTransportFailure("project_note", response.status);
    }
    try {
      return decodeProjectNotePageResult(await response.json(), request);
    } catch (error) {
      if (error instanceof TargetMCPFailure) throw error;
      throw new TargetMCPFailure("project_note_server_result_mismatch");
    }
  }
}

export type ArchiveProjectToolInput = Readonly<{
  operationId: string;
  projectId: string;
  expectedRevision: string;
  projectCapturedAtMilliseconds: number;
}>;

export type ProjectArchiveRPCRequest = Readonly<{
  operationId: string;
  accountId: string;
  actorPrincipalId: string;
  contractVersion: typeof ARCHIVE_CONTRACT_VERSION;
  projectCapturedAtMilliseconds: number;
  projectId: string;
  expectedRevision: string;
  fingerprint: string;
  envelopeJSON: string;
  requestSHA256: string;
}>;

export type ProjectArchiveRPCResult = Readonly<{
  operationId: string;
  accountId: string;
  actorPrincipalId: string;
  commandType: "archive_project";
  contractVersion: typeof ARCHIVE_CONTRACT_VERSION;
  commandFingerprint: string;
  envelopeSHA256: string;
  requestSHA256: string;
  subjectId: string;
  phase: "applied" | "rejected";
  resultCode: string | null;
  errorCode: string | null;
  projectCapturedAtMilliseconds: number;
  serverReceivedAtMilliseconds: number;
  completedAtMilliseconds: number;
}>;

export interface ProjectArchiveApplying {
  apply(
    request: ProjectArchiveRPCRequest,
    context: TargetMCPRequestContext,
  ): Promise<ProjectArchiveRPCResult>;
}

export function makeProjectArchiveRPCRequest(
  input: ArchiveProjectToolInput,
  context: TargetMCPRequestContext,
): ProjectArchiveRPCRequest {
  const accountId = validateIdentifier(context.accountId, "account_not_authorized");
  const actorPrincipalId = validateIdentifier(context.principalId, "account_not_authorized");
  const projectId = validateIdentifier(input.projectId, "project_archive_project_id_invalid");
  const operationId = validateArchiveOperationId(input.operationId, accountId);
  const expectedRevision = validateUInt64Decimal(
    input.expectedRevision,
    "project_archive_expected_revision_invalid",
  );
  validateMilliseconds(
    input.projectCapturedAtMilliseconds,
    "project_archive_captured_at_invalid",
  );

  // Assemble bytes directly: JSON.stringify cannot preserve UInt64 exactly.
  const envelopeJSON = [
    "{\"accountId\":", jsonString(accountId),
    ",\"actorPrincipalId\":", jsonString(actorPrincipalId),
    ",\"clientCreatedAt\":", String(input.projectCapturedAtMilliseconds),
    ",\"contractVersion\":", jsonString(ARCHIVE_CONTRACT_VERSION),
    ",\"operationId\":", jsonString(operationId),
    ",\"payload\":{\"projectId\":", jsonString(projectId), "}",
    ",\"preconditions\":[{\"expectedRevision\":{\"revision\":", expectedRevision,
    ",\"subject\":{\"id\":", jsonString(projectId), ",\"kind\":\"project\"}}}]}",
  ].join("");
  const fingerprint = sha256(envelopeJSON);
  const fields = [
    operationId, accountId, actorPrincipalId, ARCHIVE_CONTRACT_VERSION,
    String(input.projectCapturedAtMilliseconds), projectId, expectedRevision,
    fingerprint, envelopeJSON,
  ];
  let requestMaterial = "project-archive-request-v1|";
  for (const field of fields) {
    requestMaterial += `v${Buffer.byteLength(field, "utf8")}:${field}`;
  }
  return {
    operationId,
    accountId,
    actorPrincipalId,
    contractVersion: ARCHIVE_CONTRACT_VERSION,
    projectCapturedAtMilliseconds: input.projectCapturedAtMilliseconds,
    projectId,
    expectedRevision,
    fingerprint,
    envelopeJSON,
    requestSHA256: sha256(requestMaterial),
  };
}

export async function archiveProjectTool(
  input: ArchiveProjectToolInput,
  context: TargetMCPRequestContext,
  applier: ProjectArchiveApplying,
): Promise<ProjectArchiveRPCResult> {
  requirePublicCredential(context.accessToken, "authentication_required");
  const request = makeProjectArchiveRPCRequest(input, context);
  const result = await applier.apply(request, context);
  try {
    validateProjectArchiveResult(result, request);
  } catch (error) {
    if (error instanceof TargetMCPFailure) throw error;
    throw new TargetMCPFailure("project_archive_server_result_mismatch");
  }
  return result;
}

export class SupabaseProjectArchiveApplier implements ProjectArchiveApplying {
  readonly #rpcURL: URL;
  readonly #publishableKey: string;
  readonly #fetch: typeof fetch;

  constructor(
    supabaseURL: URL,
    publishableKey: string,
    fetchImplementation: typeof fetch = fetch,
  ) {
    validateBaseURL(supabaseURL, "project_archive_configuration_invalid");
    requirePublicCredential(publishableKey, "project_archive_configuration_invalid");
    this.#rpcURL = new URL("/rest/v1/rpc/spike_archive_project", supabaseURL);
    this.#publishableKey = publishableKey;
    this.#fetch = fetchImplementation;
  }

  async apply(
    request: ProjectArchiveRPCRequest,
    context: TargetMCPRequestContext,
  ): Promise<ProjectArchiveRPCResult> {
    requirePublicCredential(context.accessToken, "authentication_required");
    const response = await this.#fetch(this.#rpcURL, {
      method: "POST",
      headers: {
        Accept: "application/vnd.pgrst.object+json",
        apikey: this.#publishableKey,
        Authorization: `Bearer ${context.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_operation_id: request.operationId,
        p_account_id: request.accountId,
        p_actor_principal_id: request.actorPrincipalId,
        p_contract_version: request.contractVersion,
        p_project_captured_at: new Date(
          request.projectCapturedAtMilliseconds,
        ).toISOString(),
        p_project_id: request.projectId,
        p_expected_revision: request.expectedRevision,
        p_fingerprint: request.fingerprint,
        p_envelope_json: request.envelopeJSON,
      }),
    });
    if (!response.ok) {
      throwTransportFailure("project_archive", response.status);
    }
    try {
      return decodeProjectArchiveResult(await response.json(), request);
    } catch (error) {
      if (error instanceof TargetMCPFailure) throw error;
      throw new TargetMCPFailure("project_archive_server_result_mismatch");
    }
  }
}

export const listProjectNotesToolDefinition = Object.freeze({
  name: "list_project_notes",
  description: "List one bounded authoritative page of notes for a Project in the current Ledger account.",
  inputSchema: Object.freeze({
    type: "object",
    additionalProperties: false,
    required: ["projectId", "pageSize"],
    properties: Object.freeze({
      projectId: { type: "string", minLength: 1, maxLength: 128 },
      pageSize: { type: "integer", minimum: 1, maximum: NOTE_PAGE_MAXIMUM },
      after: {
        type: "object",
        additionalProperties: false,
        required: ["accountId", "projectId", "createdAtMilliseconds", "noteId"],
        properties: {
          accountId: { type: "string", minLength: 1, maxLength: 128 },
          projectId: { type: "string", minLength: 1, maxLength: 128 },
          createdAtMilliseconds: { type: "integer" },
          noteId: { type: "string", minLength: 1, maxLength: 128 },
        },
      },
    }),
  }),
});

export const archiveProjectToolDefinition = Object.freeze({
  name: "archive_project",
  description: "Archive one Project through the canonical revision-checked Ledger operation.",
  inputSchema: Object.freeze({
    type: "object",
    additionalProperties: false,
    required: [
      "operationId", "projectId", "expectedRevision", "projectCapturedAtMilliseconds",
    ],
    properties: Object.freeze({
      operationId: { type: "string", minLength: 1, maxLength: 128 },
      projectId: { type: "string", minLength: 1, maxLength: 128 },
      expectedRevision: { type: "string", pattern: "^(0|[1-9][0-9]{0,19})$" },
      projectCapturedAtMilliseconds: { type: "integer" },
    }),
  }),
});

function validateProjectNotePageResult(
  result: ProjectNotePageTransportResult,
  request: ProjectNotePageTransportRequest,
): void {
  const mismatch = (): never => {
    throw new TargetMCPFailure("project_note_server_result_mismatch");
  };
  if (result.accountId !== request.accountId
    || result.projectId !== request.projectId
    || result.pageSize !== request.pageSize
    || result.queryFingerprint !== request.queryFingerprint
    || !Array.isArray(result.rows)
    || result.rows.length > request.pageSize
    || typeof result.isCompleteForProjectHistory !== "boolean"
    || "local" in result
    || "readiness" in result
    || "localDataVersion" in result
    || "asOf" in result) mismatch();

  const identities = new Set<string>();
  for (let index = 0; index < result.rows.length; index += 1) {
    const row = result.rows[index]!;
    validateProjectNote(row, request);
    if (identities.has(row.id)) mismatch();
    identities.add(row.id);
    if (request.after !== null && !precedes(request.after, row)) mismatch();
    if (index > 0 && !precedes(result.rows[index - 1]!, row)) mismatch();
  }

  if (result.isCompleteForProjectHistory) {
    if (result.nextCursor !== null) mismatch();
  } else {
    const last = result.rows.at(-1);
    if (last === undefined || result.nextCursor === null
      || result.nextCursor.accountId !== request.accountId
      || result.nextCursor.projectId !== request.projectId
      || result.nextCursor.createdAtMilliseconds !== last.createdAtMilliseconds
      || result.nextCursor.noteId !== last.id) mismatch();
  }
}

function validateProjectNote(
  row: ProjectNoteTransport,
  request: ProjectNotePageTransportRequest,
): void {
  const mismatch = (): never => {
    throw new TargetMCPFailure("project_note_server_result_mismatch");
  };
  try {
    validateIdentifier(row.id, "project_note_server_result_mismatch");
    validateIdentifier(row.accountId, "project_note_server_result_mismatch");
    validateIdentifier(row.projectId, "project_note_server_result_mismatch");
    validateIdentifier(row.createdByPrincipalId, "project_note_server_result_mismatch");
    validateMilliseconds(row.createdAtMilliseconds, "project_note_server_result_mismatch");
    validateUInt64Decimal(row.revision, "project_note_server_result_mismatch");
  } catch { mismatch(); }
  if (row.accountId !== request.accountId || row.projectId !== request.projectId) mismatch();
  if (Buffer.byteLength(row.source, "utf8") < 1
    || Buffer.byteLength(row.source, "utf8") > 64
    || !/^\p{Ll}[\p{Ll}\p{Nd}_]*$/u.test(row.source)) mismatch();
  if (row.creatorDisplayName !== null
    && (typeof row.creatorDisplayName !== "string"
      || FOUNDATION_WHITESPACE_ONLY.test(row.creatorDisplayName))) {
    mismatch();
  }
  if ((row.lastEditedByPrincipalId === null) !== (row.lastEditedAtMilliseconds === null)) {
    mismatch();
  }
  if (row.lastEditedByPrincipalId !== null) {
    try {
      validateIdentifier(row.lastEditedByPrincipalId, "project_note_server_result_mismatch");
      validateMilliseconds(
        row.lastEditedAtMilliseconds as number,
        "project_note_server_result_mismatch",
      );
    } catch { mismatch(); }
    if ((row.lastEditedAtMilliseconds as number) < row.createdAtMilliseconds) mismatch();
  }
  if (row.content.kind === "visible") {
    if (typeof row.content.text !== "string"
      || FOUNDATION_WHITESPACE_ONLY.test(row.content.text)
      || "deletion" in row.content) mismatch();
  } else if (row.content.kind === "tombstone") {
    if ("text" in row.content) mismatch();
    try {
      validateIdentifier(
        row.content.deletion.deletedByPrincipalId,
        "project_note_server_result_mismatch",
      );
      validateMilliseconds(
        row.content.deletion.deletedAtMilliseconds,
        "project_note_server_result_mismatch",
      );
    } catch { mismatch(); }
    if (row.content.deletion.deletedAtMilliseconds < row.createdAtMilliseconds
      || (row.lastEditedAtMilliseconds !== null
        && row.content.deletion.deletedAtMilliseconds < row.lastEditedAtMilliseconds)) mismatch();
  } else {
    mismatch();
  }
}

function throwTransportFailure(
  family: "project_note" | "project_archive",
  status: number,
): never {
  if (status === 401) {
    throw new TargetMCPFailure("authentication_required", status);
  }
  if (status === 403) {
    throw new TargetMCPFailure(`${family}_request_denied`, status);
  }
  if (status >= 400 && status < 500 && status !== 408 && status !== 429) {
    throw new TargetMCPFailure(`${family}_request_invalid`, status);
  }
  throw new TargetMCPFailure(`${family}_request_rejected`, status);
}

function decodeProjectNotePageResult(
  raw: unknown,
  request: ProjectNotePageTransportRequest,
): ProjectNotePageTransportResult {
  const body = record(raw, "project_note_server_result_mismatch");
  const rows = array(body.rows, "project_note_server_result_mismatch")
    .map((value): ProjectNoteTransport => decodeProjectNote(value));
  const nextCursor = body.next_cursor === null
    ? null
    : decodeCursor(body.next_cursor, "project_note_server_result_mismatch");
  const result: ProjectNotePageTransportResult = {
    accountId: requiredString(body.account_id, "project_note_server_result_mismatch"),
    projectId: requiredString(body.project_id, "project_note_server_result_mismatch"),
    pageSize: requiredSafeInteger(body.page_size, "project_note_server_result_mismatch"),
    queryFingerprint: requiredString(
      body.query_fingerprint,
      "project_note_server_result_mismatch",
    ),
    rows,
    isCompleteForProjectHistory: requiredBoolean(
      body.is_complete_for_project_history,
      "project_note_server_result_mismatch",
    ),
    nextCursor,
  };
  validateProjectNotePageResult(result, request);
  return result;
}

function decodeProjectNote(value: unknown): ProjectNoteTransport {
  const code = "project_note_server_result_mismatch";
  const row = record(value, code);
  const contentKind = requiredString(row.content_kind, code);
  let content: ProjectNoteContentTransport;
  if (contentKind === "visible") {
    if (row.deleted_by_principal_id !== null || row.deleted_at_ms !== null) {
      throw new TargetMCPFailure(code);
    }
    content = { kind: "visible", text: requiredString(row.note_text, code) };
  } else if (contentKind === "tombstone") {
    if (row.note_text !== null) throw new TargetMCPFailure(code);
    content = {
      kind: "tombstone",
      deletion: {
        deletedByPrincipalId: requiredString(row.deleted_by_principal_id, code),
        deletedAtMilliseconds: requiredSafeInteger(row.deleted_at_ms, code),
      },
    };
  } else {
    throw new TargetMCPFailure(code);
  }
  return {
    id: requiredString(row.id, code),
    accountId: requiredString(row.account_id, code),
    projectId: requiredString(row.project_id, code),
    content,
    source: requiredString(row.source, code),
    createdByPrincipalId: requiredString(row.created_by_principal_id, code),
    creatorDisplayName: optionalString(row.creator_display_name, code),
    createdAtMilliseconds: requiredSafeInteger(row.created_at_ms, code),
    revision: requiredString(row.revision, code),
    lastEditedByPrincipalId: optionalString(row.last_edited_by_principal_id, code),
    lastEditedAtMilliseconds: optionalSafeInteger(row.last_edited_at_ms, code),
  };
}

function decodeProjectArchiveResult(
  raw: unknown,
  request: ProjectArchiveRPCRequest,
): ProjectArchiveRPCResult {
  const code = "project_archive_server_result_mismatch";
  const body = record(raw, code);
  const commandType = requiredString(body.command_type, code);
  const contractVersion = requiredString(body.contract_version, code);
  const phase = requiredString(body.phase, code);
  if (commandType !== "archive_project"
    || contractVersion !== ARCHIVE_CONTRACT_VERSION
    || (phase !== "applied" && phase !== "rejected")) {
    throw new TargetMCPFailure(code);
  }
  const result: ProjectArchiveRPCResult = {
    operationId: requiredString(body.operation_id, code),
    accountId: requiredString(body.account_id, code),
    actorPrincipalId: requiredString(body.actor_principal_id, code),
    commandType,
    contractVersion,
    commandFingerprint: requiredString(body.command_fingerprint, code),
    envelopeSHA256: requiredString(body.envelope_sha256, code),
    requestSHA256: requiredString(body.request_sha256, code),
    subjectId: requiredString(body.subject_id, code),
    phase,
    resultCode: optionalString(body.result_code, code),
    errorCode: optionalString(body.error_code, code),
    projectCapturedAtMilliseconds: requiredSafeInteger(body.client_created_at_ms, code),
    serverReceivedAtMilliseconds: requiredSafeInteger(body.server_received_at_ms, code),
    completedAtMilliseconds: requiredSafeInteger(body.completed_at_ms, code),
  };
  validateProjectArchiveResult(result, request);
  return result;
}

function validateProjectArchiveResult(
  result: ProjectArchiveRPCResult,
  request: ProjectArchiveRPCRequest,
): void {
  const mismatch = (): never => {
    throw new TargetMCPFailure("project_archive_server_result_mismatch");
  };
  if (result.operationId !== request.operationId
    || result.accountId !== request.accountId
    || result.actorPrincipalId !== request.actorPrincipalId
    || result.commandType !== "archive_project"
    || result.contractVersion !== request.contractVersion
    || result.commandFingerprint !== request.fingerprint
    || result.envelopeSHA256 !== request.fingerprint
    || result.requestSHA256 !== request.requestSHA256
    || result.subjectId !== request.projectId
    || result.projectCapturedAtMilliseconds !== request.projectCapturedAtMilliseconds
    || result.completedAtMilliseconds < result.serverReceivedAtMilliseconds) mismatch();
  if (result.phase === "applied") {
    if (result.resultCode !== "project_archived" || result.errorCode !== null) mismatch();
  } else if (result.phase === "rejected") {
    if (result.resultCode !== null
      || result.errorCode === null
      || !ARCHIVE_REJECTION_CODES.has(result.errorCode)) mismatch();
  } else {
    mismatch();
  }
}

function precedes(
  earlier: ProjectNoteCursorTransport | ProjectNoteTransport,
  later: ProjectNoteTransport,
): boolean {
  if (earlier.createdAtMilliseconds !== later.createdAtMilliseconds) {
    return earlier.createdAtMilliseconds > later.createdAtMilliseconds;
  }
  return Buffer.compare(
    Buffer.from("noteId" in earlier ? earlier.noteId : earlier.id, "utf8"),
    Buffer.from(later.id, "utf8"),
  ) > 0;
}

function validateArchiveOperationId(value: string, accountId: string): string {
  validateIdentifier(value, "project_archive_operation_id_invalid");
  const prefix = `project-archive-${sha256(accountId)}-`;
  const suffix = value.slice(prefix.length);
  if (!value.startsWith(prefix)
    || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(suffix)
    || Buffer.byteLength(value, "utf8") !== 117) {
    throw new TargetMCPFailure("project_archive_operation_id_invalid");
  }
  return value;
}

function validateUInt64Decimal(value: unknown, code: string): string {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]*)$/.test(value)
    || value.length > 20 || BigInt(value) > UINT64_MAXIMUM) {
    throw new TargetMCPFailure(code);
  }
  return value;
}

function validateMilliseconds(value: unknown, code: string): asserts value is number {
  if (typeof value !== "number" || !Number.isSafeInteger(value)
    || Number.isNaN(new Date(value).valueOf())) {
    throw new TargetMCPFailure(code);
  }
}

function validateBaseURL(url: URL, code: string): void {
  if (!(url.protocol === "http:" || url.protocol === "https:")
    || url.hostname.length === 0 || url.username.length > 0 || url.password.length > 0
    || url.search.length > 0 || url.hash.length > 0) {
    throw new TargetMCPFailure(code);
  }
}

function requirePublicCredential(value: string, code: string): void {
  if (value.trim().length === 0 || isServiceRoleCredential(value)) {
    throw new TargetMCPFailure(code);
  }
}

function isServiceRoleCredential(value: string): boolean {
  if (value.startsWith("sb_secret_")) return true;
  const segments = value.split(".");
  if (segments.length !== 3) return false;
  try {
    const payload = JSON.parse(
      Buffer.from(segments[1]!, "base64url").toString("utf8"),
    ) as unknown;
    return typeof payload === "object" && payload !== null
      && (payload as Record<string, unknown>).role === "service_role";
  } catch {
    return false;
  }
}

function jsonString(value: string): string {
  return JSON.stringify(value).replaceAll("/", "\\/");
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function record(value: unknown, code: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TargetMCPFailure(code);
  }
  return value as Record<string, unknown>;
}

function array(value: unknown, code: string): unknown[] {
  if (!Array.isArray(value)) throw new TargetMCPFailure(code);
  return value;
}

function requiredString(value: unknown, code: string): string {
  if (typeof value !== "string") throw new TargetMCPFailure(code);
  return value;
}

function optionalString(value: unknown, code: string): string | null {
  if (value === null) return null;
  return requiredString(value, code);
}

function requiredBoolean(value: unknown, code: string): boolean {
  if (typeof value !== "boolean") throw new TargetMCPFailure(code);
  return value;
}

function requiredSafeInteger(value: unknown, code: string): number {
  validateMilliseconds(value, code);
  return value;
}

function optionalSafeInteger(value: unknown, code: string): number | null {
  if (value === null) return null;
  return requiredSafeInteger(value, code);
}

function decodeCursor(value: unknown, code: string): ProjectNoteCursorTransport {
  const cursor = record(value, code);
  return {
    accountId: requiredString(cursor.account_id, code),
    projectId: requiredString(cursor.project_id, code),
    createdAtMilliseconds: requiredSafeInteger(cursor.created_at_ms, code),
    noteId: requiredString(cursor.note_id, code),
  };
}
