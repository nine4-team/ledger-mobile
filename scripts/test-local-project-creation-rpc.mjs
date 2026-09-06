import assert from "node:assert/strict";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";

const OWNER_AUTH_USER_ID = "10000000-0000-0000-0000-000000000001";
const RESTRICTED_AUTH_USER_ID = "10000000-0000-0000-0000-000000000002";
const OTHER_ACCOUNT_AUTH_USER_ID = "10000000-0000-0000-0000-000000000003";

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
    assert.equal(typeof status[key], "string", `local Supabase status must include ${key}`);
    assert.ok(status[key].length > 0, `local Supabase status ${key} must not be empty`);
  }
  return status;
}

async function request(status, subject, path, init = {}) {
  const response = await fetch(`${status.REST_URL}${path}`, {
    ...init,
    headers: {
      Accept: "application/json",
      apikey: status.PUBLISHABLE_KEY,
      Authorization: `Bearer ${jwt(status.JWT_SECRET, subject)}`,
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

function createCommand({ restricted = false } = {}) {
  const suffix = crypto.randomUUID();
  const operationId = `rpc-project-operation-${suffix}`;
  const projectId = `rpc-project-${suffix}`;
  const clientId = `rpc-project-client-${suffix}`;
  const projectCreatedAt = 1_788_523_200_000;
  const actorPrincipalId = restricted ? "principal-restricted" : "principal-owner";
  const payload = {
    projectId,
    clientSelection: {
      kind: "new",
      clientId,
      displayName: "RPC Project Client",
    },
    displayName: "  RPC Project  ",
    description: "RPC canonical description",
    categoryAllocations: [
      {
        categoryId: "category-design-fee",
        allocation: { minorUnits: 2500, currency: "EUR" },
      },
      { categoryId: "category-furnishings" },
    ],
  };
  const envelope = {
    accountId: "account-primary",
    actorPrincipalId,
    clientCreatedAt: projectCreatedAt,
    contractVersion: "project-create-v1",
    operationId,
    payload,
    preconditions: [],
  };
  const envelopeJSON = JSON.stringify(envelope);
  const fingerprint = crypto.createHash("sha256").update(envelopeJSON).digest("hex");
  return {
    operationId,
    projectId,
    clientId,
    fingerprint,
    rpcBody: {
      p_operation_id: operationId,
      p_account_id: envelope.accountId,
      p_actor_principal_id: actorPrincipalId,
      p_contract_version: envelope.contractVersion,
      p_project_created_at: new Date(projectCreatedAt).toISOString(),
      p_project_id: projectId,
      p_client_selection_kind: payload.clientSelection.kind,
      p_client_id: clientId,
      p_new_client_display_name: payload.clientSelection.displayName,
      p_project_display_name: payload.displayName,
      p_description: payload.description,
      p_category_allocations: payload.categoryAllocations,
      p_fingerprint: fingerprint,
      p_envelope_json: envelopeJSON,
    },
  };
}

const status = localStatus();
const command = createCommand();

const applied = await request(
  status,
  OWNER_AUTH_USER_ID,
  "/rpc/spike_create_project",
  { method: "POST", body: JSON.stringify(command.rpcBody) },
);
assert.equal(applied.response.status, 200, JSON.stringify(applied.body));
assert.equal(applied.body.operation_id, command.operationId);
assert.equal(applied.body.subject_id, command.projectId);
assert.equal(applied.body.command_fingerprint, command.fingerprint);
assert.equal(applied.body.phase, "applied");
assert.equal(applied.body.result_code, "project_created");

const replayed = await request(
  status,
  OWNER_AUTH_USER_ID,
  "/rpc/spike_create_project",
  { method: "POST", body: JSON.stringify(command.rpcBody) },
);
assert.equal(replayed.response.status, 200, JSON.stringify(replayed.body));
assert.deepEqual(replayed.body, applied.body, "exact replay must return the immutable result");

const visibleProject = await request(
  status,
  OWNER_AUTH_USER_ID,
  `/spike_projects?id=eq.${encodeURIComponent(command.projectId)}&select=id,account_id,client_id,display_name,description,revision`,
);
assert.equal(visibleProject.response.status, 200, JSON.stringify(visibleProject.body));
assert.deepEqual(visibleProject.body, [{
  id: command.projectId,
  account_id: "account-primary",
  client_id: command.clientId,
  display_name: "  RPC Project  ",
  description: "RPC canonical description",
  revision: 1,
}]);

const visibleAllocations = await request(
  status,
  OWNER_AUTH_USER_ID,
  `/spike_project_category_allocations?project_id=eq.${encodeURIComponent(command.projectId)}&select=category_id,allocation_minor_units,allocation_currency&order=category_id`,
);
assert.equal(visibleAllocations.response.status, 200, JSON.stringify(visibleAllocations.body));
assert.deepEqual(visibleAllocations.body, [
  {
    category_id: "category-design-fee",
    allocation_minor_units: 2500,
    allocation_currency: "EUR",
  },
  {
    category_id: "category-furnishings",
    allocation_minor_units: null,
    allocation_currency: null,
  },
]);

const hiddenFromOtherAccount = await request(
  status,
  OTHER_ACCOUNT_AUTH_USER_ID,
  `/spike_projects?id=eq.${encodeURIComponent(command.projectId)}&select=id`,
);
assert.equal(hiddenFromOtherAccount.response.status, 200, JSON.stringify(hiddenFromOtherAccount.body));
assert.deepEqual(hiddenFromOtherAccount.body, [], "RLS must hide another Account's Project");

const restrictedCommand = createCommand({ restricted: true });
const restricted = await request(
  status,
  RESTRICTED_AUTH_USER_ID,
  "/rpc/spike_create_project",
  { method: "POST", body: JSON.stringify(restrictedCommand.rpcBody) },
);
assert.equal(restricted.response.status, 403, JSON.stringify(restricted.body));

const directWrite = await request(
  status,
  OWNER_AUTH_USER_ID,
  "/spike_projects",
  {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({
      id: `direct-project-${crypto.randomUUID()}`,
      account_id: "account-primary",
      client_id: "client-existing",
      display_name: "Bypass",
    }),
  },
);
assert.equal(directWrite.response.status, 403, JSON.stringify(directWrite.body));

console.log("local-project-creation-rpc: applied, replayed, allocated, RLS-isolated, and direct-write-protected");
