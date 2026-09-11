import assert from "node:assert/strict";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";

const OWNER_AUTH_USER_ID = "10000000-0000-0000-0000-000000000001";
const RESTRICTED_AUTH_USER_ID = "10000000-0000-0000-0000-000000000002";
const OTHER_ACCOUNT_AUTH_USER_ID = "10000000-0000-0000-0000-000000000003";
const CAPTURED_AT_MS = 1_788_609_600_000;

function base64URL(value) {
  return Buffer.from(value)
    .toString("base64")
    .replaceAll("=", "")
    .replaceAll("+", "-")
    .replaceAll("/", "_");
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
  const signature = crypto
    .createHmac("sha256", secret)
    .update(unsigned)
    .digest("base64")
    .replaceAll("=", "")
    .replaceAll("+", "-")
    .replaceAll("/", "_");
  return `${unsigned}.${signature}`;
}

function localStatus() {
  const output = execFileSync(
    "npx",
    ["--yes", "supabase@2.116.0", "status", "-o", "json"],
    { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
  );
  const status = JSON.parse(output);
  for (const key of ["REST_URL", "PUBLISHABLE_KEY", "JWT_SECRET"]) {
    assert.equal(typeof status[key], "string", `local status must include ${key}`);
    assert.ok(status[key].length > 0, `local status ${key} must not be empty`);
  }
  const restURL = new URL(status.REST_URL);
  assert.equal(restURL.protocol, "http:", "archive verification requires local HTTP");
  assert.ok(
    restURL.hostname === "127.0.0.1" || restURL.hostname === "localhost",
    "archive verification refuses a hosted endpoint",
  );
  return status;
}

async function request(status, subject, path, init = {}) {
  const authorization = subject === null
    ? {}
    : { Authorization: `Bearer ${jwt(status.JWT_SECRET, subject)}` };
  const response = await fetch(`${status.REST_URL}${path}`, {
    ...init,
    headers: {
      Accept: "application/json",
      apikey: status.PUBLISHABLE_KEY,
      ...authorization,
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

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function archiveOperationID(accountId, canonicalUUID = crypto.randomUUID()) {
  assert.match(
    canonicalUUID,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
  return `project-archive-${sha256(accountId)}-${canonicalUUID}`;
}

function requestBindingField(value) {
  if (value === null) return "n";
  return `v${Buffer.byteLength(value, "utf8")}:${value}`;
}

function archiveRequestSHA256({
  operationId,
  accountId,
  actorPrincipalId,
  contractVersion,
  capturedAtMilliseconds,
  projectId,
  expectedRevision,
  fingerprint,
  envelopeJSON,
}) {
  const fields = [
    operationId,
    accountId,
    actorPrincipalId,
    contractVersion,
    String(capturedAtMilliseconds),
    projectId,
    expectedRevision,
    fingerprint,
    envelopeJSON,
  ];
  return sha256(
    `project-archive-request-v1|${fields.map(requestBindingField).join("")}`,
  );
}

function canonicalArchiveEnvelope({
  operationId,
  accountId,
  actorPrincipalId,
  projectId,
  expectedRevision,
}) {
  assert.match(expectedRevision, /^(0|[1-9][0-9]*)$/);
  return `{"accountId":${JSON.stringify(accountId)},` +
    `"actorPrincipalId":${JSON.stringify(actorPrincipalId)},` +
    `"clientCreatedAt":${CAPTURED_AT_MS},` +
    `"contractVersion":"project-archive-v1",` +
    `"operationId":${JSON.stringify(operationId)},` +
    `"payload":{"projectId":${JSON.stringify(projectId)}},` +
    `"preconditions":[{"expectedRevision":{"revision":${expectedRevision},` +
    `"subject":{"id":${JSON.stringify(projectId)},"kind":"project"}}}]}`;
}

function archiveCommand({
  operationId,
  accountId = "account-primary",
  actorPrincipalId = "principal-owner",
  projectId,
  expectedRevision = "1",
} = {}) {
  operationId ??= archiveOperationID(accountId);
  const envelopeJSON = canonicalArchiveEnvelope({
    operationId,
    accountId,
    actorPrincipalId,
    projectId,
    expectedRevision,
  });
  const fingerprint = sha256(envelopeJSON);
  const requestSHA256 = archiveRequestSHA256({
    operationId,
    accountId,
    actorPrincipalId,
    contractVersion: "project-archive-v1",
    capturedAtMilliseconds: CAPTURED_AT_MS,
    projectId,
    expectedRevision,
    fingerprint,
    envelopeJSON,
  });
  return {
    operationId,
    accountId,
    actorPrincipalId,
    projectId,
    expectedRevision,
    envelopeJSON,
    fingerprint,
    requestSHA256,
    rpcBody: {
      p_operation_id: operationId,
      p_account_id: accountId,
      p_actor_principal_id: actorPrincipalId,
      p_contract_version: "project-archive-v1",
      p_project_captured_at: new Date(CAPTURED_AT_MS).toISOString(),
      p_project_id: projectId,
      p_expected_revision: expectedRevision,
      p_fingerprint: fingerprint,
      p_envelope_json: envelopeJSON,
    },
  };
}

function projectCreationCommand({
  projectId,
  operationId,
  displayName,
  accountId = "account-primary",
  actorPrincipalId = "principal-owner",
  clientId = "client-existing",
  description = "Preserved RPC archive description",
  categoryAllocations = [{
    allocation: { currency: "USD", minorUnits: 12_345 },
    categoryId: "category-furnishings",
  }],
}) {
  const envelope = {
    accountId,
    actorPrincipalId,
    clientCreatedAt: CAPTURED_AT_MS,
    contractVersion: "project-create-v1",
    operationId,
    payload: {
      categoryAllocations,
      clientSelection: { clientId, kind: "existing" },
      description,
      displayName,
      projectId,
    },
    preconditions: [],
  };
  const envelopeJSON = JSON.stringify(envelope);
  return {
    p_operation_id: operationId,
    p_account_id: envelope.accountId,
    p_actor_principal_id: envelope.actorPrincipalId,
    p_contract_version: envelope.contractVersion,
    p_project_created_at: new Date(CAPTURED_AT_MS).toISOString(),
    p_project_id: projectId,
    p_client_selection_kind: "existing",
    p_client_id: clientId,
    p_new_client_display_name: null,
    p_project_display_name: displayName,
    p_description: envelope.payload.description,
    p_category_allocations: envelope.payload.categoryAllocations,
    p_fingerprint: sha256(envelopeJSON),
    p_envelope_json: envelopeJSON,
  };
}

function clientCreationCommand({
  accountId,
  actorPrincipalId,
  clientId,
  operationId,
  displayName,
}) {
  const envelope = {
    accountId,
    actorPrincipalId,
    clientCreatedAt: CAPTURED_AT_MS,
    contractVersion: "client-create-v1",
    operationId,
    payload: { clientId, displayName },
    preconditions: [],
  };
  const envelopeJSON = JSON.stringify(envelope);
  return {
    p_operation_id: operationId,
    p_account_id: accountId,
    p_actor_principal_id: actorPrincipalId,
    p_contract_version: "client-create-v1",
    p_client_created_at: new Date(CAPTURED_AT_MS).toISOString(),
    p_client_id: clientId,
    p_display_name: displayName,
    p_fingerprint: sha256(envelopeJSON),
    p_envelope_json: envelopeJSON,
  };
}

async function rpc(status, subject, name, body) {
  return request(status, subject, `/rpc/${name}`, {
    method: "POST",
    body: JSON.stringify(body),
  });
}

async function readRows(status, subject, path) {
  const result = await request(status, subject, path);
  assert.equal(result.response.status, 200, "authorized local read must succeed");
  assert.ok(Array.isArray(result.body), "Data API table read must return rows");
  return result.body;
}

function withoutArchiveColumns(project) {
  const copy = { ...project };
  for (const key of ["lifecycle", "revision", "updated_at", "updated_at_ms"]) {
    delete copy[key];
  }
  return copy;
}

const status = localStatus();
const bindingVector = archiveCommand({
  operationId: archiveOperationID(
    "account-primary",
    "11111111-2222-4333-8444-555555555555",
  ),
  projectId: "project-archive-vector",
  expectedRevision: "41",
});
assert.equal(
  bindingVector.fingerprint,
  "285d889a2f53b8aaf0355ddaca6c13228bdcc8dde0c0fdbda80de6ea5f5bb933",
  "canonical archive envelope must match the frozen fingerprint vector",
);
assert.equal(
  bindingVector.requestSHA256,
  "9ac984815935b833e106d154f3b8f968e4d7a7f877d8199bb1698bfbd9e6bc43",
  "nine-field request binding must match the frozen digest vector",
);
const suffix = crypto.randomUUID();
const projectId = `rpc-archive-project-${suffix}`;
const createOperationId = `rpc-create-for-archive-${suffix}`;
const concurrentProjectId = `rpc-archive-concurrent-${suffix}`;

for (const [id, operationId, displayName] of [
  [projectId, createOperationId, "  RPC Archive Main  "],
  [concurrentProjectId, `rpc-create-concurrent-${suffix}`, "RPC Archive Concurrent"],
]) {
  const created = await rpc(
    status,
    OWNER_AUTH_USER_ID,
    "spike_create_project",
    projectCreationCommand({ projectId: id, operationId, displayName }),
  );
  assert.equal(created.response.status, 200, "synthetic Project fixture must be created");
  assert.equal(created.body.phase, "applied");
}

const otherClientId = `rpc-archive-other-client-${suffix}`;
const otherProjectId = `rpc-archive-other-project-${suffix}`;
const otherClientCreated = await rpc(
  status,
  OTHER_ACCOUNT_AUTH_USER_ID,
  "spike_create_client",
  clientCreationCommand({
    accountId: "account-other",
    actorPrincipalId: "principal-other",
    clientId: otherClientId,
    operationId: `rpc-create-other-client-${suffix}`,
    displayName: "Other Archive Client",
  }),
);
assert.equal(otherClientCreated.response.status, 200);
assert.equal(otherClientCreated.body.phase, "applied");

const otherProjectCreated = await rpc(
  status,
  OTHER_ACCOUNT_AUTH_USER_ID,
  "spike_create_project",
  projectCreationCommand({
    accountId: "account-other",
    actorPrincipalId: "principal-other",
    clientId: otherClientId,
    projectId: otherProjectId,
    operationId: `rpc-create-other-project-${suffix}`,
    displayName: "Other Archive Project",
    description: "Cross-account namespace fixture",
    categoryAllocations: [],
  }),
);
assert.equal(otherProjectCreated.response.status, 200);
assert.equal(otherProjectCreated.body.phase, "applied");

const otherArchive = archiveCommand({
  accountId: "account-other",
  actorPrincipalId: "principal-other",
  projectId: otherProjectId,
});
const otherArchiveResult = await rpc(
  status,
  OTHER_ACCOUNT_AUTH_USER_ID,
  "spike_archive_project",
  otherArchive.rpcBody,
);
assert.equal(otherArchiveResult.response.status, 200);
assert.equal(otherArchiveResult.body.phase, "applied");

const otherArchivePresentedToOwner = archiveCommand({
  operationId: otherArchive.operationId,
  projectId,
});
const crossAccountNamespaceResult = await rpc(
  status,
  OWNER_AUTH_USER_ID,
  "spike_archive_project",
  otherArchivePresentedToOwner.rpcBody,
);
assert.equal(crossAccountNamespaceResult.response.status, 400);
assert.equal(crossAccountNamespaceResult.body.code, "22023");
assert.equal(
  crossAccountNamespaceResult.body.message,
  "project archive request identity invalid",
);
assert.deepEqual(
  await readRows(
    status,
    OWNER_AUTH_USER_ID,
    `/spike_operation_results?operation_id=eq.${encodeURIComponent(otherArchive.operationId)}&select=operation_id`,
  ),
  [],
  "Account A cannot disclose the existing Account B result",
);
assert.deepEqual(
  await readRows(
    status,
    OTHER_ACCOUNT_AUTH_USER_ID,
    `/spike_operation_results?operation_id=eq.${encodeURIComponent(otherArchive.operationId)}&select=account_id,phase`,
  ),
  [{ account_id: "account-other", phase: "applied" }],
  "wrongly namespaced presentation must not alter Account B's result",
);

const projectPath = `/spike_projects?id=eq.${encodeURIComponent(projectId)}` +
  "&select=id,account_id,client_id,display_name,description,lifecycle,revision," +
  "created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id";
const clientPath = "/spike_clients?id=eq.client-existing&select=*";
const categoriesPath = "/spike_budget_categories?account_id=eq.account-primary&select=*&order=id";
const allocationsPath = `/spike_project_category_allocations?project_id=eq.${encodeURIComponent(projectId)}&select=*&order=id`;

const [projectBeforeRows, clientBefore, categoriesBefore, allocationsBefore] =
  await Promise.all([
    readRows(status, OWNER_AUTH_USER_ID, projectPath),
    readRows(status, OWNER_AUTH_USER_ID, clientPath),
    readRows(status, OWNER_AUTH_USER_ID, categoriesPath),
    readRows(status, OWNER_AUTH_USER_ID, allocationsPath),
  ]);
assert.equal(projectBeforeRows.length, 1);
assert.equal(projectBeforeRows[0].lifecycle, "active");
assert.equal(projectBeforeRows[0].revision, 1);

const command = archiveCommand({ projectId });
assert.equal(command.fingerprint, sha256(command.envelopeJSON));
assert.equal(JSON.parse(command.envelopeJSON).preconditions[0]
  .expectedRevision.revision, 1);

const applied = await rpc(
  status,
  OWNER_AUTH_USER_ID,
  "spike_archive_project",
  command.rpcBody,
);
assert.equal(applied.response.status, 200, "authorized archive must succeed");
assert.equal(applied.body.operation_id, command.operationId);
assert.equal(applied.body.account_id, command.accountId);
assert.equal(applied.body.actor_principal_id, command.actorPrincipalId);
assert.equal(applied.body.command_type, "archive_project");
assert.equal(applied.body.contract_version, "project-archive-v1");
assert.equal(applied.body.command_fingerprint, command.fingerprint);
assert.equal(applied.body.envelope_sha256, command.fingerprint);
assert.equal(applied.body.request_sha256, command.requestSHA256);
assert.equal(applied.body.subject_id, projectId);
assert.equal(applied.body.phase, "applied");
assert.equal(applied.body.result_code, "project_archived");
assert.equal(applied.body.error_code, null);

// This is also the lost-response case: the client can discard the first body
// and retry the exact immutable command.
const replayed = await rpc(
  status,
  OWNER_AUTH_USER_ID,
  "spike_archive_project",
  command.rpcBody,
);
assert.equal(replayed.response.status, 200);
assert.deepEqual(replayed.body, applied.body, "exact retry must replay one result");

for (const changedBody of [
  { ...command.rpcBody, p_expected_revision: "2" },
  {
    ...command.rpcBody,
    p_project_captured_at: new Date(CAPTURED_AT_MS + 1).toISOString(),
  },
]) {
  const changedBinding = await rpc(
    status,
    OWNER_AUTH_USER_ID,
    "spike_archive_project",
    changedBody,
  );
  assert.equal(changedBinding.response.status, 409);
  assert.equal(changedBinding.body.code, "23505");
}

const [projectAfterRows, clientAfter, categoriesAfter, allocationsAfter] =
  await Promise.all([
    readRows(status, OWNER_AUTH_USER_ID, projectPath),
    readRows(status, OWNER_AUTH_USER_ID, clientPath),
    readRows(status, OWNER_AUTH_USER_ID, categoriesPath),
    readRows(status, OWNER_AUTH_USER_ID, allocationsPath),
  ]);
assert.equal(projectAfterRows.length, 1);
assert.equal(projectAfterRows[0].lifecycle, "archived");
assert.equal(projectAfterRows[0].revision, 2);
assert.ok(projectAfterRows[0].updated_at_ms > projectBeforeRows[0].updated_at_ms);
assert.deepEqual(
  withoutArchiveColumns(projectAfterRows[0]),
  withoutArchiveColumns(projectBeforeRows[0]),
  "archive may change only Project lifecycle, revision, and server update time",
);
assert.deepEqual(clientAfter, clientBefore, "Client relationship row must be preserved");
assert.deepEqual(categoriesAfter, categoriesBefore, "category rows must be preserved");
assert.deepEqual(allocationsAfter, allocationsBefore, "allocation rows must be preserved");

const changedReplay = archiveCommand({
  operationId: command.operationId,
  projectId: concurrentProjectId,
});
const changedReplayResult = await rpc(
  status,
  OWNER_AUTH_USER_ID,
  "spike_archive_project",
  changedReplay.rpcBody,
);
assert.equal(changedReplayResult.response.status, 409);
assert.equal(changedReplayResult.body.code, "23505");

const reservedOperationId = archiveOperationID("account-primary");
const reservedClientId = `rpc-reserved-client-${suffix}`;
const crossCommandResult = await rpc(
  status,
  OTHER_ACCOUNT_AUTH_USER_ID,
  "spike_create_client",
  clientCreationCommand({
    accountId: "account-other",
    actorPrincipalId: "principal-other",
    clientId: reservedClientId,
    operationId: reservedOperationId,
    displayName: "Reserved Prefix",
  }),
);
assert.equal(crossCommandResult.response.status, 400);
assert.equal(crossCommandResult.body.code, "22023");
assert.equal(crossCommandResult.body.message, "project archive request identity invalid");
assert.deepEqual(
  await readRows(
    status,
    OTHER_ACCOUNT_AUTH_USER_ID,
    `/spike_clients?id=eq.${encodeURIComponent(reservedClientId)}&select=id`,
  ),
  [],
  "namespace rejection must roll back the generic command entity insert",
);
assert.deepEqual(
  await readRows(
    status,
    OTHER_ACCOUNT_AUTH_USER_ID,
    `/spike_operation_results?operation_id=eq.${encodeURIComponent(reservedOperationId)}&select=operation_id`,
  ),
  [],
  "namespace rejection must leave the reserved ID unoccupied",
);

const rightfulReservedUse = archiveCommand({
  operationId: reservedOperationId,
  projectId: `rpc-reserved-missing-${suffix}`,
});
const rightfulReservedResult = await rpc(
  status,
  OWNER_AUTH_USER_ID,
  "spike_archive_project",
  rightfulReservedUse.rpcBody,
);
assert.equal(rightfulReservedResult.response.status, 200);
assert.equal(rightfulReservedResult.body.phase, "rejected");
assert.equal(
  rightfulReservedResult.body.error_code,
  "project_archive_revision_conflict",
);
assert.deepEqual(
  await readRows(
    status,
    OTHER_ACCOUNT_AUTH_USER_ID,
    `/spike_operation_results?operation_id=eq.${encodeURIComponent(reservedOperationId)}&select=operation_id`,
  ),
  [],
  "foreign Account must not observe rightful reserved-ID reuse",
);

const concurrentA = archiveCommand({ projectId: concurrentProjectId });
const concurrentB = archiveCommand({ projectId: concurrentProjectId });
const concurrentResults = await Promise.all([
  rpc(status, OWNER_AUTH_USER_ID, "spike_archive_project", concurrentA.rpcBody),
  rpc(status, OWNER_AUTH_USER_ID, "spike_archive_project", concurrentB.rpcBody),
]);
for (const result of concurrentResults) {
  assert.equal(result.response.status, 200, "both terminal concurrency results are durable");
}
assert.deepEqual(
  concurrentResults.map(({ body }) => body.phase).sort(),
  ["applied", "rejected"],
  "same-revision concurrency must have one apply and one conflict",
);
const rejectedConcurrent = concurrentResults.find(({ body }) => body.phase === "rejected");
assert.equal(rejectedConcurrent.body.error_code, "project_archive_revision_conflict");
const concurrentRows = await readRows(
  status,
  OWNER_AUTH_USER_ID,
  `/spike_projects?id=eq.${encodeURIComponent(concurrentProjectId)}&select=lifecycle,revision`,
);
assert.deepEqual(concurrentRows, [{ lifecycle: "archived", revision: 2 }]);

for (const [expectedRevision, expectedCode] of [
  ["9223372036854775808", "project_archive_revision_conflict"],
  ["18446744073709551615", "project_archive_revision_conflict"],
  ["18446744073709551616", "project_archive_payload_invalid"],
]) {
  const boundary = archiveCommand({ projectId, expectedRevision });
  const result = await rpc(
    status,
    OWNER_AUTH_USER_ID,
    "spike_archive_project",
    boundary.rpcBody,
  );
  assert.equal(result.response.status, 200);
  assert.equal(result.body.phase, "rejected");
  assert.equal(result.body.error_code, expectedCode);
}

const missingProject = archiveCommand({
  projectId: `rpc-archive-missing-${suffix}`,
  expectedRevision: "1",
});
const missingProjectResult = await rpc(
  status,
  OWNER_AUTH_USER_ID,
  "spike_archive_project",
  missingProject.rpcBody,
);
assert.equal(missingProjectResult.response.status, 200);
assert.equal(missingProjectResult.body.phase, "rejected");
assert.equal(
  missingProjectResult.body.error_code,
  "project_archive_revision_conflict",
  "an authorized missing Project must use the generic non-enumerating conflict",
);

const malformedOperationId = archiveOperationID("account-primary");
const malformedEnvelope = "{";
const malformedBody = {
  ...archiveCommand({
    operationId: malformedOperationId,
    projectId,
    expectedRevision: "2",
  }).rpcBody,
  p_fingerprint: sha256(malformedEnvelope),
  p_envelope_json: malformedEnvelope,
};
const malformed = await rpc(
  status,
  OWNER_AUTH_USER_ID,
  "spike_archive_project",
  malformedBody,
);
assert.equal(malformed.response.status, 200);
assert.equal(malformed.body.phase, "rejected");
assert.equal(malformed.body.error_code, "project_archive_command_encoding_invalid");
const malformedReplay = await rpc(
  status,
  OWNER_AUTH_USER_ID,
  "spike_archive_project",
  malformedBody,
);
assert.equal(malformedReplay.response.status, 200);
assert.deepEqual(
  malformedReplay.body,
  malformed.body,
  "an exact previously rejected request must replay byte-identically",
);
const changedMalformedReplay = await rpc(
  status,
  OWNER_AUTH_USER_ID,
  "spike_archive_project",
  { ...malformedBody, p_expected_revision: "3" },
);
assert.equal(changedMalformedReplay.response.status, 409);
assert.equal(changedMalformedReplay.body.code, "23505");

const restricted = archiveCommand({
  actorPrincipalId: "principal-restricted",
  projectId,
  expectedRevision: "2",
});
const restrictedResult = await rpc(
  status,
  RESTRICTED_AUTH_USER_ID,
  "spike_archive_project",
  restricted.rpcBody,
);
assert.equal(restrictedResult.response.status, 403);

const actorMismatch = archiveCommand({
  actorPrincipalId: "principal-restricted",
  projectId,
  expectedRevision: "2",
});
const actorMismatchResult = await rpc(
  status,
  OWNER_AUTH_USER_ID,
  "spike_archive_project",
  actorMismatch.rpcBody,
);
assert.equal(actorMismatchResult.response.status, 403);

const crossAccount = archiveCommand({
  accountId: "account-other",
  actorPrincipalId: "principal-owner",
  projectId: "project-does-not-matter",
});
const crossAccountResult = await rpc(
  status,
  OWNER_AUTH_USER_ID,
  "spike_archive_project",
  crossAccount.rpcBody,
);
assert.equal(crossAccountResult.response.status, 403);

const structuralBase = archiveCommand({
  operationId: archiveOperationID("account-primary"),
  projectId,
  expectedRevision: "2",
}).rpcBody;
const archiveResultsBeforeTransport = await readRows(
  status,
  OWNER_AUTH_USER_ID,
  "/spike_operation_results?command_type=eq.archive_project&select=operation_id&order=operation_id",
);
const unrecordableBodies = [
  { ...structuralBase, p_operation_id: "invalid operation id" },
  { ...structuralBase, p_operation_id: null },
  {
    ...structuralBase,
    p_operation_id: archiveOperationID("account-primary"),
    p_contract_version: null,
  },
  {
    ...structuralBase,
    p_operation_id: archiveOperationID("account-primary"),
    p_contract_version: "bad contract",
  },
  {
    ...structuralBase,
    p_operation_id: archiveOperationID("account-primary"),
    p_project_captured_at: null,
  },
  {
    ...structuralBase,
    p_operation_id: archiveOperationID("account-primary"),
    p_project_captured_at: "2026-09-05T12:00:00.000001Z",
  },
  {
    ...structuralBase,
    p_operation_id: archiveOperationID("account-primary"),
    p_project_id: null,
  },
  {
    ...structuralBase,
    p_operation_id: archiveOperationID("account-primary"),
    p_project_id: "bad project",
  },
  {
    ...structuralBase,
    p_operation_id: archiveOperationID("account-primary"),
    p_fingerprint: null,
  },
  {
    ...structuralBase,
    p_operation_id: archiveOperationID("account-primary"),
    p_fingerprint: "not-a-fingerprint",
  },
  {
    ...structuralBase,
    p_operation_id: archiveOperationID("account-primary"),
    p_envelope_json: null,
  },
];
for (const body of unrecordableBodies) {
  const result = await rpc(
    status,
    OWNER_AUTH_USER_ID,
    "spike_archive_project",
    body,
  );
  assert.equal(result.response.status, 400);
  assert.equal(result.body.code, "22023");
  assert.equal(result.body.message, "project archive request identity invalid");
}

const archiveResultsAfterTransport = await readRows(
  status,
  OWNER_AUTH_USER_ID,
  "/spike_operation_results?command_type=eq.archive_project&select=operation_id&order=operation_id",
);
assert.deepEqual(
  archiveResultsAfterTransport,
  archiveResultsBeforeTransport,
  "unrecordable identity must not create or sanitize a terminal result",
);

const anonymous = await rpc(
  status,
  null,
  "spike_archive_project",
  command.rpcBody,
);
assert.ok([401, 403].includes(anonymous.response.status));

const hiddenProjects = await readRows(
  status,
  OTHER_ACCOUNT_AUTH_USER_ID,
  `/spike_projects?id=eq.${encodeURIComponent(projectId)}&select=id`,
);
assert.deepEqual(hiddenProjects, [], "RLS must hide another Account's Project");
const hiddenResults = await readRows(
  status,
  OTHER_ACCOUNT_AUTH_USER_ID,
  `/spike_operation_results?operation_id=eq.${encodeURIComponent(command.operationId)}&select=operation_id`,
);
assert.deepEqual(hiddenResults, [], "RLS must hide another Account's result");

const directProjectWrite = await request(
  status,
  OWNER_AUTH_USER_ID,
  `/spike_projects?id=eq.${encodeURIComponent(projectId)}`,
  {
    method: "PATCH",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({ lifecycle: "active" }),
  },
);
assert.equal(directProjectWrite.response.status, 403);

const directResultWrite = await request(
  status,
  OWNER_AUTH_USER_ID,
  `/spike_operation_results?operation_id=eq.${encodeURIComponent(command.operationId)}`,
  {
    method: "PATCH",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({ phase: "rejected" }),
  },
);
assert.equal(directResultWrite.response.status, 403);

console.log(
  "local-project-archive-rpc: request binding/transport, apply/replay, parallel conflict, UInt64 boundaries, scope, RLS, and preservation passed",
);
