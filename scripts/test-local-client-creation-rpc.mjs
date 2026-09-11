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

function createCommand() {
  const suffix = crypto.randomUUID();
  const operationId = `rpc-operation-${suffix}`;
  const clientId = `rpc-client-${suffix}`;
  const clientCreatedAt = 1_788_523_200_000;
  const envelope = {
    accountId: "account-primary",
    actorPrincipalId: "principal-owner",
    clientCreatedAt,
    contractVersion: "client-create-v1",
    operationId,
    payload: { clientId, displayName: "RPC Offline Client" },
    preconditions: [],
  };
  const envelopeJSON = JSON.stringify(envelope);
  return {
    operationId,
    clientId,
    envelopeJSON,
    fingerprint: crypto.createHash("sha256").update(envelopeJSON).digest("hex"),
    rpcBody: {
      p_account_id: envelope.accountId,
      p_actor_principal_id: envelope.actorPrincipalId,
      p_client_created_at: new Date(clientCreatedAt).toISOString(),
      p_client_id: clientId,
      p_contract_version: envelope.contractVersion,
      p_display_name: envelope.payload.displayName,
      p_envelope_json: envelopeJSON,
      p_fingerprint: crypto.createHash("sha256").update(envelopeJSON).digest("hex"),
      p_operation_id: operationId,
    },
  };
}

const status = localStatus();
const command = createCommand();

const applied = await request(
  status,
  OWNER_AUTH_USER_ID,
  "/rpc/spike_create_client",
  { method: "POST", body: JSON.stringify(command.rpcBody) },
);
assert.equal(applied.response.status, 200, JSON.stringify(applied.body));
assert.equal(applied.body.operation_id, command.operationId);
assert.equal(applied.body.subject_id, command.clientId);
assert.equal(applied.body.command_fingerprint, command.fingerprint);
assert.equal(applied.body.phase, "applied");
assert.equal(applied.body.result_code, "client_created");

const replayed = await request(
  status,
  OWNER_AUTH_USER_ID,
  "/rpc/spike_create_client",
  { method: "POST", body: JSON.stringify(command.rpcBody) },
);
assert.equal(replayed.response.status, 200, JSON.stringify(replayed.body));
assert.deepEqual(replayed.body, applied.body, "exact replay must return the immutable result");

const visibleClients = await request(
  status,
  OWNER_AUTH_USER_ID,
  `/spike_clients?id=eq.${encodeURIComponent(command.clientId)}&select=id,account_id,display_name,revision`,
);
assert.equal(visibleClients.response.status, 200, JSON.stringify(visibleClients.body));
assert.deepEqual(visibleClients.body, [{
  id: command.clientId,
  account_id: "account-primary",
  display_name: "RPC Offline Client",
  revision: 1,
}]);

const hiddenFromOtherAccount = await request(
  status,
  OTHER_ACCOUNT_AUTH_USER_ID,
  `/spike_clients?id=eq.${encodeURIComponent(command.clientId)}&select=id`,
);
assert.equal(hiddenFromOtherAccount.response.status, 200, JSON.stringify(hiddenFromOtherAccount.body));
assert.deepEqual(hiddenFromOtherAccount.body, [], "RLS must not expose another account's Client");

const restrictedCommand = createCommand();
const restricted = await request(
  status,
  RESTRICTED_AUTH_USER_ID,
  "/rpc/spike_create_client",
  { method: "POST", body: JSON.stringify({
    ...restrictedCommand.rpcBody,
    p_actor_principal_id: "principal-restricted",
  }) },
);
assert.equal(restricted.response.status, 403, JSON.stringify(restricted.body));

const directWrite = await request(
  status,
  OWNER_AUTH_USER_ID,
  "/spike_clients",
  {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({
      id: `direct-${crypto.randomUUID()}`,
      account_id: "account-primary",
      display_name: "Bypass",
    }),
  },
);
assert.equal(directWrite.response.status, 403, JSON.stringify(directWrite.body));

console.log("local-client-creation-rpc: applied, replayed, RLS-isolated, and direct-write-protected");
