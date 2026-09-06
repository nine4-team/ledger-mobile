import assert from "node:assert/strict";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OWNER_AUTH_USER_ID = "10000000-0000-0000-0000-000000000001";
const EMPLOYEE_AUTH_USER_ID = "10000000-0000-0000-0000-000000000002";
const OTHER_AUTH_USER_ID = "10000000-0000-0000-0000-000000000003";
const ADMIN_AUTH_USER_ID = crypto.randomUUID();
const REVOKED_AUTH_USER_ID = crypto.randomUUID();
const PROJECT_ARCHIVE_CAPTURED_AT_MS = 1_788_609_600_000;
const suffix = crypto.randomUUID().replaceAll("-", "");

const ids = {
  primaryAccount: `note-read-primary-${suffix}`,
  otherAccount: `note-read-other-${suffix}`,
  adminPrincipal: `note-read-admin-${suffix}`,
  revokedPrincipal: `note-read-revoked-${suffix}`,
  primaryClient: `note-read-client-primary-${suffix}`,
  otherClient: `note-read-client-other-${suffix}`,
  activeProject: `note-read-project-active-${suffix}`,
  archivedProject: `note-read-project-archived-${suffix}`,
  emptyProject: `note-read-project-empty-${suffix}`,
  otherProject: `note-read-project-other-${suffix}`,
  newestNote: `note-read-z-${suffix}`,
  tiedHighNote: `note-read-b-${suffix}`,
  tiedLowNote: `note-read-a-${suffix}`,
  archivedNote: `note-read-archived-${suffix}`,
  otherNote: `note-read-other-${suffix}`,
};

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function base64URL(value) {
  return Buffer.from(value).toString("base64").replaceAll("=", "")
    .replaceAll("+", "-").replaceAll("/", "_");
}

function jwt(secret, subject) {
  const now = Math.floor(Date.now() / 1_000);
  const header = base64URL(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const payload = base64URL(JSON.stringify({
    aud: "authenticated",
    exp: now + 600,
    iat: now,
    role: "authenticated",
    sub: subject,
  }));
  const unsigned = `${header}.${payload}`;
  const signature = crypto.createHmac("sha256", secret).update(unsigned)
    .digest("base64").replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_");
  return `${unsigned}.${signature}`;
}

function localStatus() {
  const output = execFileSync(
    "npx",
    ["--yes", "supabase@2.116.0", "status", "-o", "json"],
    { cwd: ROOT, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
  );
  const status = JSON.parse(output);
  for (const key of ["REST_URL", "PUBLISHABLE_KEY", "JWT_SECRET"]) {
    assert.equal(typeof status[key], "string", `local Supabase status must include ${key}`);
    assert.ok(status[key].length > 0, `local Supabase status ${key} must not be empty`);
  }
  const url = new URL(status.REST_URL);
  assert.equal(url.protocol, "http:", "Project-note verification refuses HTTPS/hosted endpoints");
  assert.ok(
    url.hostname === "127.0.0.1" || url.hostname === "localhost",
    "Project-note verification refuses non-local endpoints",
  );
  return status;
}

function localSQL(sql) {
  execFileSync(
    "npx",
    ["--yes", "supabase@2.116.0", "db", "query", "--local", sql],
    { cwd: ROOT, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  );
}

async function request(status, subject, requestPath, init = {}) {
  const response = await fetch(`${status.REST_URL}${requestPath}`, {
    ...init,
    headers: {
      Accept: "application/json",
      apikey: status.PUBLISHABLE_KEY,
      ...(subject === null
        ? {}
        : { Authorization: `Bearer ${jwt(status.JWT_SECRET, subject)}` }),
      ...(init.body === undefined ? {} : { "Content-Type": "application/json" }),
      ...init.headers,
    },
  });
  const text = await response.text();
  let body = null;
  if (text.length > 0) {
    try {
      body = JSON.parse(text);
    } catch {
      body = text;
    }
  }
  return { response, body };
}

function fingerprint(accountId, projectId, pageSize, after = null) {
  const basis = {
    accountId,
    ...(after === null ? {} : {
      after: {
        accountId,
        createdAt: after.created_at_ms,
        noteId: after.note_id,
        projectId,
      },
    }),
    pageSize,
    projectId,
  };
  return crypto.createHash("sha256").update(JSON.stringify(basis)).digest("hex");
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function archiveCommand(accountId, projectId, expectedRevision) {
  const operationId = `project-archive-${sha256(accountId)}-${crypto.randomUUID()}`;
  const envelopeJSON = `{"accountId":${JSON.stringify(accountId)},` +
    `"actorPrincipalId":"principal-owner",` +
    `"clientCreatedAt":${PROJECT_ARCHIVE_CAPTURED_AT_MS},` +
    `"contractVersion":"project-archive-v1",` +
    `"operationId":${JSON.stringify(operationId)},` +
    `"payload":{"projectId":${JSON.stringify(projectId)}},` +
    `"preconditions":[{"expectedRevision":{"revision":${expectedRevision},` +
    `"subject":{"id":${JSON.stringify(projectId)},"kind":"project"}}}]}`;
  const commandFingerprint = sha256(envelopeJSON);
  return {
    operationId,
    envelopeJSON,
    commandFingerprint,
    rpcBody: {
      p_operation_id: operationId,
      p_account_id: accountId,
      p_actor_principal_id: "principal-owner",
      p_contract_version: "project-archive-v1",
      p_project_captured_at: new Date(PROJECT_ARCHIVE_CAPTURED_AT_MS).toISOString(),
      p_project_id: projectId,
      p_expected_revision: expectedRevision,
      p_fingerprint: commandFingerprint,
      p_envelope_json: envelopeJSON,
    },
  };
}

async function listNotes(status, subject, accountId, projectId, pageSize, after = null) {
  return request(status, subject, "/rpc/spike_list_project_notes", {
    method: "POST",
    body: JSON.stringify({
      p_account_id: accountId,
      p_project_id: projectId,
      p_page_size: pageSize,
      p_after_created_at_ms: after?.created_at_ms ?? null,
      p_after_note_id: after?.note_id ?? null,
      p_query_fingerprint: fingerprint(accountId, projectId, pageSize, after),
    }),
  });
}

function assertDenied(result, label) {
  assert.ok(
    result.response.status === 401 || result.response.status === 403,
    `${label}: expected 401/403, received ${result.response.status} ${JSON.stringify(result.body)}`,
  );
  assert.equal(result.body?.code, "42501", `${label}: expected PostgreSQL privilege denial`);
}

function assertPage(result, accountId, projectId, pageSize) {
  assert.equal(result.response.status, 200, JSON.stringify(result.body));
  assert.equal(result.body.account_id, accountId);
  assert.equal(result.body.project_id, projectId);
  assert.equal(result.body.page_size, pageSize);
  assert.equal(result.body.query_fingerprint.length, 64);
  assert.ok(Array.isArray(result.body.rows));
  return result.body;
}

const setupSQL = `
do $project_note_read_setup$
begin
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000', ${sqlLiteral(ADMIN_AUTH_USER_ID)},
    'authenticated', 'authenticated', ${sqlLiteral(`note-admin-${suffix}@ledger-spike.invalid`)},
    '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000', ${sqlLiteral(REVOKED_AUTH_USER_ID)},
    'authenticated', 'authenticated', ${sqlLiteral(`note-revoked-${suffix}@ledger-spike.invalid`)},
    '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );
insert into public.spike_principals (id, auth_user_id) values
  (${sqlLiteral(ids.adminPrincipal)}, ${sqlLiteral(ADMIN_AUTH_USER_ID)}),
  (${sqlLiteral(ids.revokedPrincipal)}, ${sqlLiteral(REVOKED_AUTH_USER_ID)});
insert into public.spike_accounts (id, display_name) values
  (${sqlLiteral(ids.primaryAccount)}, 'Project Note Primary'),
  (${sqlLiteral(ids.otherAccount)}, 'Project Note Other');
insert into public.spike_account_memberships (
  account_id, principal_id, role, state, can_manage_clients,
  can_manage_projects, can_manage_project_budgets, financial_access
) values
  (${sqlLiteral(ids.primaryAccount)}, 'principal-owner', 'owner', 'active', true, true, true, 'full'),
  (${sqlLiteral(ids.primaryAccount)}, ${sqlLiteral(ids.adminPrincipal)}, 'admin', 'active', false, false, false, 'none'),
  (${sqlLiteral(ids.primaryAccount)}, 'principal-restricted', 'employee', 'active', false, false, false, 'none'),
  (${sqlLiteral(ids.primaryAccount)}, ${sqlLiteral(ids.revokedPrincipal)}, 'employee', 'removed', false, false, false, 'none'),
  (${sqlLiteral(ids.otherAccount)}, 'principal-other', 'owner', 'active', true, true, true, 'full');
insert into public.spike_clients (
  id, account_id, display_name, lifecycle, revision, created_at, updated_at,
  created_at_ms, updated_at_ms, created_by_principal_id
) values
  (${sqlLiteral(ids.primaryClient)}, ${sqlLiteral(ids.primaryAccount)}, 'Primary Client',
   'active', 1, now(), now(), 1, 1, 'principal-owner'),
  (${sqlLiteral(ids.otherClient)}, ${sqlLiteral(ids.otherAccount)}, 'Other Client',
   'active', 1, now(), now(), 1, 1, 'principal-other');
insert into public.spike_projects (
  id, account_id, client_id, display_name, lifecycle, revision,
  created_at, updated_at, created_at_ms, updated_at_ms, created_by_principal_id
) values
  (${sqlLiteral(ids.activeProject)}, ${sqlLiteral(ids.primaryAccount)},
   ${sqlLiteral(ids.primaryClient)}, 'Active Project', 'active', 4,
   now(), now(), 1, 1, 'principal-owner'),
  (${sqlLiteral(ids.archivedProject)}, ${sqlLiteral(ids.primaryAccount)},
   ${sqlLiteral(ids.primaryClient)}, 'Archived Project', 'archived', 8,
   now(), now(), 1, 1, 'principal-owner'),
  (${sqlLiteral(ids.emptyProject)}, ${sqlLiteral(ids.primaryAccount)},
   ${sqlLiteral(ids.primaryClient)}, 'Empty Project', 'active', 1,
   now(), now(), 1, 1, 'principal-owner'),
  (${sqlLiteral(ids.otherProject)}, ${sqlLiteral(ids.otherAccount)},
   ${sqlLiteral(ids.otherClient)}, 'Other Project', 'active', 1,
   now(), now(), 1, 1, 'principal-other');
insert into public.spike_project_notes (
  id, account_id, project_id, content_kind, note_text, source,
  created_by_principal_id, creator_display_name, created_at, created_at_ms,
  revision, last_edited_by_principal_id, last_edited_at, last_edited_at_ms,
  deleted_by_principal_id, deleted_at, deleted_at_ms
) values
  (${sqlLiteral(ids.newestNote)}, ${sqlLiteral(ids.primaryAccount)},
   ${sqlLiteral(ids.activeProject)}, 'tombstone', null, 'mcp', 'principal-owner',
   'Owner', '2026-09-05T12:00:02Z', 1788609602000, 3,
   'principal-restricted', '2026-09-05T12:00:03Z', 1788609603000,
   'principal-restricted', '2026-09-05T12:00:04Z', 1788609604000),
  (${sqlLiteral(ids.tiedHighNote)}, ${sqlLiteral(ids.primaryAccount)},
   ${sqlLiteral(ids.activeProject)}, 'visible', 'Revised delivery window', 'text',
   'principal-owner', 'Owner', '2026-09-05T12:00:01Z', 1788609601000,
   18446744073709551615, 'principal-restricted', '2026-09-05T12:00:03Z',
   1788609603000, null, null, null),
  (${sqlLiteral(ids.tiedLowNote)}, ${sqlLiteral(ids.primaryAccount)},
   ${sqlLiteral(ids.activeProject)}, 'visible', 'Original selection', 'text',
   'principal-owner', null, '2026-09-05T12:00:01Z', 1788609601000,
   0, null, null, null, null, null, null),
  (${sqlLiteral(ids.archivedNote)}, ${sqlLiteral(ids.primaryAccount)},
   ${sqlLiteral(ids.archivedProject)}, 'visible', 'Preserved archive note', 'text',
   'principal-owner', 'Owner', '2026-09-05T12:00:01Z', 1788609601000,
   2, null, null, null, null, null, null),
  (${sqlLiteral(ids.otherNote)}, ${sqlLiteral(ids.otherAccount)},
   ${sqlLiteral(ids.otherProject)}, 'visible', 'Other Account', 'text',
   'principal-other', null, '2026-09-05T12:00:01Z', 1788609601000,
   1, null, null, null, null, null, null);
end;
$project_note_read_setup$;
`;

const cleanupSQL = `
do $project_note_read_cleanup$
begin
execute 'alter table public.spike_operation_results disable trigger spike_operation_results_immutable';
delete from public.spike_operation_results
where account_id in (${sqlLiteral(ids.primaryAccount)}, ${sqlLiteral(ids.otherAccount)});
execute 'alter table public.spike_operation_results enable trigger spike_operation_results_immutable';
delete from public.spike_project_notes
where account_id in (${sqlLiteral(ids.primaryAccount)}, ${sqlLiteral(ids.otherAccount)});
delete from public.spike_accounts
where id in (${sqlLiteral(ids.primaryAccount)}, ${sqlLiteral(ids.otherAccount)});
delete from auth.users
where id in (${sqlLiteral(ADMIN_AUTH_USER_ID)}, ${sqlLiteral(REVOKED_AUTH_USER_ID)});
end;
$project_note_read_cleanup$;
`;

const status = localStatus();
localSQL(setupSQL);

try {
  for (const [label, subject] of [
    ["owner", OWNER_AUTH_USER_ID],
    ["admin", ADMIN_AUTH_USER_ID],
    ["employee", EMPLOYEE_AUTH_USER_ID],
  ]) {
    const page = assertPage(
      await listNotes(status, subject, ids.primaryAccount, ids.activeProject, 2),
      ids.primaryAccount,
      ids.activeProject,
      2,
    );
    assert.deepEqual(
      page.rows.map((row) => row.id),
      [ids.newestNote, ids.tiedHighNote],
      `${label} exact first page`,
    );
    assert.equal(page.rows[0].content_kind, "tombstone");
    assert.equal(page.rows[0].note_text, null);
    assert.equal(page.rows[1].revision, "18446744073709551615");
    assert.equal(page.is_complete_for_project_history, false);
    assert.deepEqual(page.next_cursor, {
      account_id: ids.primaryAccount,
      project_id: ids.activeProject,
      created_at_ms: 1788609601000,
      note_id: ids.tiedHighNote,
    });
  }

  const first = assertPage(
    await listNotes(status, OWNER_AUTH_USER_ID, ids.primaryAccount, ids.activeProject, 2),
    ids.primaryAccount,
    ids.activeProject,
    2,
  );
  const finalPage = assertPage(
    await listNotes(
      status,
      OWNER_AUTH_USER_ID,
      ids.primaryAccount,
      ids.activeProject,
      2,
      first.next_cursor,
    ),
    ids.primaryAccount,
    ids.activeProject,
    2,
  );
  assert.deepEqual(finalPage.rows.map((row) => row.id), [ids.tiedLowNote]);
  assert.equal(finalPage.rows[0].revision, "0");
  assert.equal(finalPage.is_complete_for_project_history, true);
  assert.equal(finalPage.next_cursor, null);

  const activeHistoryBeforeArchive = assertPage(
    await listNotes(status, OWNER_AUTH_USER_ID, ids.primaryAccount, ids.activeProject, 20),
    ids.primaryAccount,
    ids.activeProject,
    20,
  );
  assert.deepEqual(
    activeHistoryBeforeArchive.rows.map((row) => row.id),
    [ids.newestNote, ids.tiedHighNote, ids.tiedLowNote],
  );
  assert.equal(activeHistoryBeforeArchive.is_complete_for_project_history, true);

  const archive = archiveCommand(ids.primaryAccount, ids.activeProject, "4");
  assert.match(
    archive.operationId,
    new RegExp(`^project-archive-${sha256(ids.primaryAccount)}-` +
      "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"),
  );
  assert.equal(archive.commandFingerprint, sha256(archive.envelopeJSON));
  const archiveResult = await request(
    status,
    OWNER_AUTH_USER_ID,
    "/rpc/spike_archive_project",
    { method: "POST", body: JSON.stringify(archive.rpcBody) },
  );
  assert.equal(archiveResult.response.status, 200, JSON.stringify(archiveResult.body));
  assert.equal(archiveResult.body.operation_id, archive.operationId);
  assert.equal(archiveResult.body.command_type, "archive_project");
  assert.equal(archiveResult.body.command_fingerprint, archive.commandFingerprint);
  assert.equal(archiveResult.body.envelope_sha256, archive.commandFingerprint);
  assert.equal(archiveResult.body.subject_id, ids.activeProject);
  assert.equal(archiveResult.body.phase, "applied");
  assert.equal(archiveResult.body.result_code, "project_archived");
  assert.equal(archiveResult.body.error_code, null);

  const activeHistoryAfterArchive = assertPage(
    await listNotes(status, OWNER_AUTH_USER_ID, ids.primaryAccount, ids.activeProject, 20),
    ids.primaryAccount,
    ids.activeProject,
    20,
  );
  assert.deepEqual(
    activeHistoryAfterArchive,
    activeHistoryBeforeArchive,
    "the same complete Project-note history must remain readable after archival",
  );

  const archived = assertPage(
    await listNotes(status, OWNER_AUTH_USER_ID, ids.primaryAccount, ids.archivedProject, 20),
    ids.primaryAccount,
    ids.archivedProject,
    20,
  );
  assert.deepEqual(archived.rows.map((row) => row.id), [ids.archivedNote]);
  assert.equal(archived.is_complete_for_project_history, true);

  const empty = assertPage(
    await listNotes(status, OWNER_AUTH_USER_ID, ids.primaryAccount, ids.emptyProject, 200),
    ids.primaryAccount,
    ids.emptyProject,
    200,
  );
  assert.deepEqual(empty.rows, []);
  assert.equal(empty.is_complete_for_project_history, true);

  assertDenied(
    await listNotes(status, REVOKED_AUTH_USER_ID, ids.primaryAccount, ids.activeProject, 2),
    "removed membership",
  );
  assertDenied(
    await listNotes(status, OWNER_AUTH_USER_ID, ids.otherAccount, ids.otherProject, 2),
    "cross-Account scope",
  );
  assertDenied(
    await listNotes(
      status,
      OWNER_AUTH_USER_ID,
      ids.primaryAccount,
      `missing-${suffix}`,
      2,
    ),
    "missing Project scope",
  );

  const invalidFingerprint = await request(
    status,
    OWNER_AUTH_USER_ID,
    "/rpc/spike_list_project_notes",
    {
      method: "POST",
      body: JSON.stringify({
        p_account_id: ids.primaryAccount,
        p_project_id: ids.activeProject,
        p_page_size: 2,
        p_after_created_at_ms: null,
        p_after_note_id: null,
        p_query_fingerprint: "a".repeat(64),
      }),
    },
  );
  assert.equal(invalidFingerprint.response.status, 400);
  assert.equal(invalidFingerprint.body?.code, "22023");

  assertDenied(
    await listNotes(status, null, ids.primaryAccount, ids.activeProject, 2),
    "anonymous RPC",
  );

  const directInsert = await request(status, OWNER_AUTH_USER_ID, "/spike_project_notes", {
    method: "POST",
    body: JSON.stringify({
      id: `direct-${suffix}`,
      account_id: ids.primaryAccount,
      project_id: ids.activeProject,
      content_kind: "visible",
      note_text: "Denied",
      source: "text",
      created_by_principal_id: "principal-owner",
      created_at: "2026-09-05T12:00:00Z",
      created_at_ms: 1788609600000,
      revision: 1,
    }),
  });
  assertDenied(directInsert, "authenticated direct insert");

  const directUpdate = await request(
    status,
    OWNER_AUTH_USER_ID,
    `/spike_project_notes?id=eq.${encodeURIComponent(ids.tiedLowNote)}`,
    { method: "PATCH", body: JSON.stringify({ note_text: "Changed" }) },
  );
  assertDenied(directUpdate, "authenticated direct update");

  const directDelete = await request(
    status,
    OWNER_AUTH_USER_ID,
    `/spike_project_notes?id=eq.${encodeURIComponent(ids.tiedLowNote)}`,
    { method: "DELETE" },
  );
  assertDenied(directDelete, "authenticated direct delete");

  const other = assertPage(
    await listNotes(status, OTHER_AUTH_USER_ID, ids.otherAccount, ids.otherProject, 20),
    ids.otherAccount,
    ids.otherProject,
    20,
  );
  assert.deepEqual(other.rows.map((row) => row.id), [ids.otherNote]);

  console.log(
    "local-project-note-read: bounded active/archived/empty pages, archival continuity, and UInt64 exact; "
      + "anonymous/removed/cross-account/missing/write denied",
  );
} finally {
  localSQL(cleanupSQL);
}
