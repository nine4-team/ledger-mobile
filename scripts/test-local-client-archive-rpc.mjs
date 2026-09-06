import assert from "node:assert/strict";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";

const OWNER = "10000000-0000-0000-0000-000000000001";
const RESTRICTED = "10000000-0000-0000-0000-000000000002";
const OTHER = "10000000-0000-0000-0000-000000000003";
const CAPTURED_AT_MS = 1_788_609_600_000;

function base64URL(value) {
  return Buffer.from(value).toString("base64").replaceAll("=", "")
    .replaceAll("+", "-").replaceAll("/", "_");
}

function jwt(secret, subject) {
  const now = Math.floor(Date.now() / 1_000);
  const header = base64URL(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const payload = base64URL(JSON.stringify({
    aud: "authenticated", exp: now + 600, iat: now,
    role: "authenticated", sub: subject,
  }));
  const unsigned = `${header}.${payload}`;
  const signature = crypto.createHmac("sha256", secret).update(unsigned)
    .digest("base64").replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_");
  return `${unsigned}.${signature}`;
}

function localStatus() {
  const output = execFileSync("npx", ["--yes", "supabase@2.116.0", "status", "-o", "json"], {
    encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
  });
  const status = JSON.parse(output);
  for (const key of ["REST_URL", "PUBLISHABLE_KEY", "JWT_SECRET"]) {
    assert.equal(typeof status[key], "string", `local status must include ${key}`);
    assert.ok(status[key].length > 0, `${key} must not be empty`);
  }
  const url = new URL(status.REST_URL);
  assert.equal(url.protocol, "http:");
  assert.ok(url.hostname === "127.0.0.1" || url.hostname === "localhost",
    "Client archive verification refuses hosted endpoints");
  return status;
}

async function request(status, subject, path, init = {}) {
  const response = await fetch(`${status.REST_URL}${path}`, {
    ...init,
    headers: {
      Accept: "application/json", apikey: status.PUBLISHABLE_KEY,
      ...(subject === null ? {} : { Authorization: `Bearer ${jwt(status.JWT_SECRET, subject)}` }),
      ...(init.body === undefined ? {} : { "Content-Type": "application/json" }),
      ...init.headers,
    },
  });
  const text = await response.text();
  let body = null;
  if (text.length > 0) {
    try { body = JSON.parse(text); } catch { body = text; }
  }
  return { response, body };
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function operationID(accountId, uuid = crypto.randomUUID()) {
  assert.match(uuid, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  return `client-archive-${sha256(accountId)}-${uuid}`;
}

function bindingField(value) {
  return value === null ? "n" : `v${Buffer.byteLength(value, "utf8")}:${value}`;
}

function archiveCommand({
  clientId, operationId, accountId = "account-primary",
  actorPrincipalId = "principal-owner", expectedRevision = "1",
} = {}) {
  operationId ??= operationID(accountId);
  assert.match(expectedRevision, /^(0|[1-9][0-9]*)$/);
  const envelopeJSON = `{"accountId":${JSON.stringify(accountId)},` +
    `"actorPrincipalId":${JSON.stringify(actorPrincipalId)},` +
    `"clientCreatedAt":${CAPTURED_AT_MS},"contractVersion":"client-archive-v1",` +
    `"operationId":${JSON.stringify(operationId)},` +
    `"payload":{"clientId":${JSON.stringify(clientId)}},` +
    `"preconditions":[{"expectedRevision":{"revision":${expectedRevision},` +
    `"subject":{"id":${JSON.stringify(clientId)},"kind":"client"}}}]}`;
  const fingerprint = sha256(envelopeJSON);
  const fields = [operationId, accountId, actorPrincipalId, "client-archive-v1",
    String(CAPTURED_AT_MS), clientId, expectedRevision, fingerprint, envelopeJSON];
  const requestSHA256 = sha256(`client-archive-request-v1|${fields.map(bindingField).join("")}`);
  return {
    operationId, envelopeJSON, fingerprint, requestSHA256,
    rpcBody: {
      p_operation_id: operationId, p_account_id: accountId,
      p_actor_principal_id: actorPrincipalId, p_contract_version: "client-archive-v1",
      p_client_captured_at: new Date(CAPTURED_AT_MS).toISOString(),
      p_client_id: clientId, p_expected_revision: expectedRevision,
      p_fingerprint: fingerprint, p_envelope_json: envelopeJSON,
    },
  };
}

function createClientCommand({ clientId, operationId, displayName,
  accountId = "account-primary", actorPrincipalId = "principal-owner" }) {
  const envelope = {
    accountId, actorPrincipalId, clientCreatedAt: CAPTURED_AT_MS,
    contractVersion: "client-create-v1", operationId,
    payload: { clientId, displayName }, preconditions: [],
  };
  const envelopeJSON = JSON.stringify(envelope);
  return {
    p_operation_id: operationId, p_account_id: accountId,
    p_actor_principal_id: actorPrincipalId, p_contract_version: "client-create-v1",
    p_client_created_at: new Date(CAPTURED_AT_MS).toISOString(),
    p_client_id: clientId, p_display_name: displayName,
    p_fingerprint: sha256(envelopeJSON), p_envelope_json: envelopeJSON,
  };
}

function createProjectCommand({ projectId, operationId, clientId,
  displayName = "Client archive relationship", accountId = "account-primary",
  actorPrincipalId = "principal-owner" }) {
  const payload = {
    categoryAllocations: [], clientSelection: { clientId, kind: "existing" },
    displayName, projectId,
  };
  const envelope = {
    accountId, actorPrincipalId, clientCreatedAt: CAPTURED_AT_MS,
    contractVersion: "project-create-v1", operationId, payload, preconditions: [],
  };
  const envelopeJSON = JSON.stringify(envelope);
  return {
    p_operation_id: operationId, p_account_id: accountId,
    p_actor_principal_id: actorPrincipalId, p_contract_version: "project-create-v1",
    p_project_created_at: new Date(CAPTURED_AT_MS).toISOString(), p_project_id: projectId,
    p_client_selection_kind: "existing", p_client_id: clientId,
    p_new_client_display_name: null, p_project_display_name: displayName,
    p_description: null, p_category_allocations: [],
    p_fingerprint: sha256(envelopeJSON), p_envelope_json: envelopeJSON,
  };
}

async function rpc(status, subject, name, body) {
  return request(status, subject, `/rpc/${name}`, { method: "POST", body: JSON.stringify(body) });
}

async function rows(status, subject, path) {
  const result = await request(status, subject, path);
  assert.equal(result.response.status, 200, JSON.stringify(result.body));
  assert.ok(Array.isArray(result.body));
  return result.body;
}

async function createClient(status, clientId, operationId, displayName = "Archive Client") {
  const result = await rpc(status, OWNER, "spike_create_client",
    createClientCommand({ clientId, operationId, displayName }));
  assert.equal(result.response.status, 200, JSON.stringify(result.body));
  assert.equal(result.body.phase, "applied");
}

const status = localStatus();
const suffix = crypto.randomUUID();
const vector = archiveCommand({
  operationId: operationID("account-primary", "11111111-2222-4333-8444-555555555555"),
  clientId: "client-archive-vector", expectedRevision: "41",
});
assert.equal(vector.operationId.length, 116);
assert.equal(vector.fingerprint,
  "b78d5bc5e1668cb70d55ea870279388b1619e0ef22965b84e9864362cf4af578",
  "canonical Client archive envelope must match the frozen digest vector");
assert.equal(vector.requestSHA256,
  "1c06768afba8dc718a657a3d89a9b46b9ddccb630e823fdaa2c1e4a8d1460cd2",
  "nine-field Client archive request binding must match the frozen vector");

const otherClientId = `rpc-client-archive-other-${suffix}`;
const otherCreate = await rpc(status, OTHER, "spike_create_client", createClientCommand({
  clientId: otherClientId, operationId: `rpc-client-other-create-${suffix}`,
  displayName: "Other Account Archive", accountId: "account-other",
  actorPrincipalId: "principal-other",
}));
assert.equal(otherCreate.response.status, 200);
assert.equal(otherCreate.body.phase, "applied");
const otherCommand = archiveCommand({
  clientId: otherClientId, accountId: "account-other", actorPrincipalId: "principal-other",
});
const otherApplied = await rpc(status, OTHER, "spike_archive_client", otherCommand.rpcBody);
assert.equal(otherApplied.response.status, 200);
assert.equal(otherApplied.body.phase, "applied");
const foreignIDProbe = archiveCommand({
  operationId: otherCommand.operationId, clientId: "client-existing",
});
const foreignProbeResult = await rpc(status, OWNER, "spike_archive_client", foreignIDProbe.rpcBody);
assert.equal(foreignProbeResult.response.status, 400);
assert.equal(foreignProbeResult.body.code, "22023");
assert.equal(foreignProbeResult.body.message, "client archive request identity invalid");
assert.deepEqual(await rows(status, OWNER,
  `/spike_operation_results?operation_id=eq.${encodeURIComponent(otherCommand.operationId)}&select=operation_id`),
  [], "cross-Account result identity cannot be disclosed or rebound");

const clientId = `rpc-client-archive-${suffix}`;
await createClient(status, clientId, `rpc-client-create-${suffix}`, "  Preserved Client  ");
const projectId = `rpc-project-preserved-${suffix}`;
const projectCreate = await rpc(status, OWNER, "spike_create_project",
  createProjectCommand({ projectId, operationId: `rpc-project-before-${suffix}`, clientId }));
assert.equal(projectCreate.response.status, 200, JSON.stringify(projectCreate.body));
assert.equal(projectCreate.body.phase, "applied");

const clientPath = `/spike_clients?id=eq.${encodeURIComponent(clientId)}&select=*`;
const projectPath = `/spike_projects?client_id=eq.${encodeURIComponent(clientId)}&select=*&order=id`;
const [beforeClient, beforeProjects] = await Promise.all([
  rows(status, OWNER, clientPath), rows(status, OWNER, projectPath),
]);
assert.equal(beforeClient.length, 1);
const command = archiveCommand({ clientId });
const applied = await rpc(status, OWNER, "spike_archive_client", command.rpcBody);
assert.equal(applied.response.status, 200, JSON.stringify(applied.body));
assert.equal(applied.body.operation_id, command.operationId);
assert.equal(applied.body.command_type, "archive_client");
assert.equal(applied.body.contract_version, "client-archive-v1");
assert.equal(applied.body.command_fingerprint, command.fingerprint);
assert.equal(applied.body.envelope_sha256, command.fingerprint);
assert.equal(applied.body.request_sha256, command.requestSHA256);
assert.equal(applied.body.subject_id, clientId);
assert.equal(applied.body.phase, "applied");
assert.equal(applied.body.result_code, "client_archived");
assert.equal(applied.body.error_code, null);

const replay = await rpc(status, OWNER, "spike_archive_client", command.rpcBody);
assert.equal(replay.response.status, 200);
assert.deepEqual(replay.body, applied.body, "lost-response replay must be byte-identical");
for (const changed of [
  { ...command.rpcBody, p_expected_revision: "2" },
  { ...command.rpcBody, p_client_captured_at: new Date(CAPTURED_AT_MS + 1).toISOString() },
]) {
  const result = await rpc(status, OWNER, "spike_archive_client", changed);
  assert.equal(result.response.status, 409);
  assert.equal(result.body.code, "23505");
}

const [afterClient, afterProjects] = await Promise.all([
  rows(status, OWNER, clientPath), rows(status, OWNER, projectPath),
]);
assert.equal(afterClient[0].lifecycle, "archived");
assert.equal(afterClient[0].revision, 2);
assert.ok(afterClient[0].updated_at_ms > beforeClient[0].updated_at_ms);
for (const key of ["lifecycle", "revision", "updated_at", "updated_at_ms"]) {
  delete beforeClient[0][key]; delete afterClient[0][key];
}
assert.deepEqual(afterClient, beforeClient, "archive may mutate only lifecycle/revision/update time");
assert.deepEqual(afterProjects, beforeProjects, "all Projects must remain byte-identical");
assert.deepEqual(await rows(status, RESTRICTED,
  `/spike_clients?id=eq.${encodeURIComponent(clientId)}&select=id,lifecycle,revision`),
  [{ id: clientId, lifecycle: "archived", revision: 2 }],
  "restricted same-Account member retains archived Client read access");
assert.deepEqual(await rows(status, RESTRICTED,
  `/spike_projects?id=eq.${encodeURIComponent(projectId)}&select=id,client_id`),
  [{ id: projectId, client_id: clientId }],
  "restricted same-Account member retains related Project read access");
assert.deepEqual(await rows(status, RESTRICTED,
  `/spike_operation_results?operation_id=eq.${encodeURIComponent(command.operationId)}&select=operation_id,phase`),
  [{ operation_id: command.operationId, phase: "applied" }],
  "restricted same-Account member retains archive-result read access");

const projectReplay = await rpc(status, OWNER, "spike_create_project",
  createProjectCommand({ projectId, operationId: `rpc-project-before-${suffix}`, clientId }));
assert.equal(projectReplay.response.status, 200);
assert.deepEqual(projectReplay.body, projectCreate.body,
  "Project Setup accepted before archive must replay before archived-Client admission checks");

const archivedProjectAttempt = await rpc(status, OWNER, "spike_create_project",
  createProjectCommand({ projectId: `rpc-project-after-${suffix}`,
    operationId: `rpc-project-after-op-${suffix}`, clientId }));
assert.equal(archivedProjectAttempt.response.status, 200);
assert.equal(archivedProjectAttempt.body.phase, "rejected");
assert.equal(archivedProjectAttempt.body.error_code, "project_setup_client_not_selectable");

const concurrentClient = `rpc-client-concurrent-${suffix}`;
await createClient(status, concurrentClient, `rpc-client-concurrent-create-${suffix}`);
const concurrentResults = await Promise.all([
  rpc(status, OWNER, "spike_archive_client", archiveCommand({ clientId: concurrentClient }).rpcBody),
  rpc(status, OWNER, "spike_archive_client", archiveCommand({ clientId: concurrentClient }).rpcBody),
]);
assert.deepEqual(concurrentResults.map(result => result.body.phase).sort(), ["applied", "rejected"]);
assert.equal(concurrentResults.find(result => result.body.phase === "rejected").body.error_code,
  "client_archive_revision_conflict");

const raceClient = `rpc-client-race-${suffix}`;
await createClient(status, raceClient, `rpc-client-race-create-${suffix}`);
const raceProjectId = `rpc-project-race-${suffix}`;
const raceResults = await Promise.all([
  rpc(status, OWNER, "spike_archive_client", archiveCommand({ clientId: raceClient }).rpcBody),
  rpc(status, OWNER, "spike_create_project", createProjectCommand({
    projectId: raceProjectId, operationId: `rpc-project-race-op-${suffix}`, clientId: raceClient,
  })),
]);
assert.equal(raceResults[0].response.status, 200);
assert.equal(raceResults[0].body.phase, "applied");
assert.equal(raceResults[1].response.status, 200);
assert.ok(raceResults[1].body.phase === "applied" ||
  (raceResults[1].body.phase === "rejected" &&
   raceResults[1].body.error_code === "project_setup_client_not_selectable"));
const raceProjects = await rows(status, OWNER,
  `/spike_projects?id=eq.${encodeURIComponent(raceProjectId)}&select=id,client_id`);
assert.equal(raceProjects.length, raceResults[1].body.phase === "applied" ? 1 : 0);

const archiveFirstClient = `rpc-client-archive-first-${suffix}`;
await createClient(status, archiveFirstClient, `rpc-client-archive-first-create-${suffix}`);
const committedArchiveFirst = await rpc(status, OWNER, "spike_archive_client",
  archiveCommand({ clientId: archiveFirstClient }).rpcBody);
assert.equal(committedArchiveFirst.response.status, 200);
assert.equal(committedArchiveFirst.body.phase, "applied");
assert.deepEqual(await rows(status, OWNER,
  `/spike_clients?id=eq.${encodeURIComponent(archiveFirstClient)}&select=lifecycle,revision`),
  [{ lifecycle: "archived", revision: 2 }],
  "archive-first harness observes authoritative committed archive before Project submission");
const archiveFirstProjectId = `rpc-project-archive-first-${suffix}`;
const afterArchive = await rpc(status, OWNER, "spike_create_project", createProjectCommand({
  projectId: archiveFirstProjectId,
  operationId: `rpc-project-archive-first-op-${suffix}`, clientId: archiveFirstClient,
}));
assert.equal(afterArchive.response.status, 200);
assert.equal(afterArchive.body.phase, "rejected");
assert.equal(afterArchive.body.error_code, "project_setup_client_not_selectable");
assert.deepEqual(await rows(status, OWNER,
  `/spike_projects?id=eq.${encodeURIComponent(archiveFirstProjectId)}&select=id`), [],
  "a Project cannot commit after authoritative Client archive is observable");

const reserved = operationID("account-primary");
const squatClient = `rpc-client-squat-${suffix}`;
const squat = await rpc(status, OTHER, "spike_create_client", createClientCommand({
  clientId: squatClient, operationId: reserved, displayName: "Squat",
  accountId: "account-other", actorPrincipalId: "principal-other",
}));
assert.equal(squat.response.status, 400);
assert.equal(squat.body.code, "22023");
assert.equal(squat.body.message, "client archive request identity invalid");
assert.deepEqual(await rows(status, OTHER,
  `/spike_clients?id=eq.${encodeURIComponent(squatClient)}&select=id`), []);

for (const expectedRevision of ["9223372036854775808", "18446744073709551615", "18446744073709551616"]) {
  const result = await rpc(status, OWNER, "spike_archive_client",
    archiveCommand({ clientId, expectedRevision }).rpcBody);
  assert.equal(result.response.status, 200);
  assert.equal(result.body.error_code, expectedRevision === "18446744073709551616"
    ? "client_archive_payload_invalid" : "client_archive_revision_conflict");
}

const restricted = await rpc(status, RESTRICTED, "spike_archive_client",
  archiveCommand({ clientId, actorPrincipalId: "principal-restricted", expectedRevision: "2" }).rpcBody);
assert.equal(restricted.response.status, 403);
const mismatch = await rpc(status, OWNER, "spike_archive_client",
  archiveCommand({ clientId, actorPrincipalId: "principal-restricted", expectedRevision: "2" }).rpcBody);
assert.equal(mismatch.response.status, 403);
const anonymous = await rpc(status, null, "spike_archive_client", command.rpcBody);
assert.ok([401, 403].includes(anonymous.response.status));
assert.deepEqual(await rows(status, OTHER, clientPath), [], "RLS hides foreign Client");
assert.deepEqual(await rows(status, OTHER,
  `/spike_operation_results?operation_id=eq.${encodeURIComponent(command.operationId)}&select=operation_id`),
  [], "RLS hides foreign archive result");

const directClientWrite = await request(status, OWNER, clientPath, {
  method: "PATCH", headers: { Prefer: "return=representation" },
  body: JSON.stringify({ lifecycle: "active" }),
});
assert.equal(directClientWrite.response.status, 403);
const directResultWrite = await request(status, OWNER,
  `/spike_operation_results?operation_id=eq.${encodeURIComponent(command.operationId)}`, {
    method: "PATCH", headers: { Prefer: "return=representation" },
    body: JSON.stringify({ phase: "rejected" }),
  });
assert.equal(directResultWrite.response.status, 403);

console.log("local-client-archive-rpc: binding, replay, concurrency, Project serialization, scope, RLS, and preservation passed");
