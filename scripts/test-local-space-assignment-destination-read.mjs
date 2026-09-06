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
const suffix = crypto.randomUUID().replaceAll("-", "");

const ids = {
  primaryAccount: `space-read-primary-${suffix}`,
  otherAccount: `space-read-other-${suffix}`,
  adminPrincipal: `space-read-admin-${suffix}`,
  revokedPrincipal: `space-read-revoked-${suffix}`,
  primaryClient: `space-read-client-primary-${suffix}`,
  otherClient: `space-read-client-other-${suffix}`,
  primaryProject: `space-read-project-primary-${suffix}`,
  otherProject: `space-read-project-other-${suffix}`,
  kitchen: `space-read-kitchen-${suffix}`,
  loftA: `space-read-loft-a-${suffix}`,
  loftZ: `space-read-loft-z-${suffix}`,
  inventory: `space-read-inventory-${suffix}`,
  archived: `space-read-archived-${suffix}`,
  otherProjectSpace: `space-read-other-project-${suffix}`,
  otherInventorySpace: `space-read-other-inventory-${suffix}`,
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
  assert.equal(url.protocol, "http:", "Space read verification refuses HTTPS/hosted endpoints");
  assert.ok(
    url.hostname === "127.0.0.1" || url.hostname === "localhost",
    "Space read verification refuses non-local endpoints",
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

async function rows(status, subject, requestPath) {
  const result = await request(status, subject, requestPath);
  assert.equal(result.response.status, 200, JSON.stringify(result.body));
  assert.ok(Array.isArray(result.body), JSON.stringify(result.body));
  return result.body;
}

function assertDenied(result, label) {
  assert.ok(
    result.response.status === 401 || result.response.status === 403,
    `${label}: expected 401/403, received ${result.response.status} ${JSON.stringify(result.body)}`,
  );
  assert.equal(result.body?.code, "42501", `${label}: expected PostgreSQL privilege denial`);
}

const setupSQL = `
do $space_read_setup$
begin
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000', ${sqlLiteral(ADMIN_AUTH_USER_ID)},
    'authenticated', 'authenticated', ${sqlLiteral(`space-admin-${suffix}@ledger-spike.invalid`)},
    '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000', ${sqlLiteral(REVOKED_AUTH_USER_ID)},
    'authenticated', 'authenticated', ${sqlLiteral(`space-revoked-${suffix}@ledger-spike.invalid`)},
    '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );
insert into public.spike_principals (id, auth_user_id) values
  (${sqlLiteral(ids.adminPrincipal)}, ${sqlLiteral(ADMIN_AUTH_USER_ID)}),
  (${sqlLiteral(ids.revokedPrincipal)}, ${sqlLiteral(REVOKED_AUTH_USER_ID)});
insert into public.spike_accounts (id, display_name) values
  (${sqlLiteral(ids.primaryAccount)}, 'Space Data API Primary'),
  (${sqlLiteral(ids.otherAccount)}, 'Space Data API Other');
insert into public.spike_account_memberships (
  account_id, principal_id, role, state, can_manage_clients,
  can_manage_projects, can_manage_project_budgets, financial_access
) values
  (${sqlLiteral(ids.primaryAccount)}, 'principal-owner', 'owner', 'active', false, false, false, 'none'),
  (${sqlLiteral(ids.primaryAccount)}, ${sqlLiteral(ids.adminPrincipal)}, 'admin', 'active', false, false, false, 'none'),
  (${sqlLiteral(ids.primaryAccount)}, 'principal-restricted', 'employee', 'active', false, false, false, 'none'),
  (${sqlLiteral(ids.primaryAccount)}, ${sqlLiteral(ids.revokedPrincipal)}, 'employee', 'removed', false, false, false, 'none'),
  (${sqlLiteral(ids.otherAccount)}, 'principal-other', 'owner', 'active', false, false, false, 'none');
insert into public.spike_clients (
  id, account_id, display_name, lifecycle, revision, created_at, updated_at,
  created_at_ms, updated_at_ms, created_by_principal_id
) values
  (${sqlLiteral(ids.primaryClient)}, ${sqlLiteral(ids.primaryAccount)}, 'Space Client',
   'active', 1, now(), now(), 1, 1, 'principal-owner'),
  (${sqlLiteral(ids.otherClient)}, ${sqlLiteral(ids.otherAccount)}, 'Other Space Client',
   'active', 1, now(), now(), 1, 1, 'principal-other');
insert into public.spike_projects (
  id, account_id, client_id, display_name, lifecycle, revision,
  created_at, updated_at, created_at_ms, updated_at_ms, created_by_principal_id
) values
  (${sqlLiteral(ids.primaryProject)}, ${sqlLiteral(ids.primaryAccount)},
   ${sqlLiteral(ids.primaryClient)}, 'Space Project', 'active', 1,
   now(), now(), 1, 1, 'principal-owner'),
  (${sqlLiteral(ids.otherProject)}, ${sqlLiteral(ids.otherAccount)},
   ${sqlLiteral(ids.otherClient)}, 'Other Space Project', 'active', 1,
   now(), now(), 1, 1, 'principal-other');
insert into public.spike_spaces (
  id, account_id, scope_kind, project_id, display_name, lifecycle, revision
) values
  (${sqlLiteral(ids.kitchen)}, ${sqlLiteral(ids.primaryAccount)}, 'project',
   ${sqlLiteral(ids.primaryProject)}, 'Kitchen', 'active', 7),
  (${sqlLiteral(ids.loftA)}, ${sqlLiteral(ids.primaryAccount)}, 'project',
   ${sqlLiteral(ids.primaryProject)}, 'Loft', 'active', 8),
  (${sqlLiteral(ids.loftZ)}, ${sqlLiteral(ids.primaryAccount)}, 'project',
   ${sqlLiteral(ids.primaryProject)}, 'Loft', 'active', 9),
  (${sqlLiteral(ids.inventory)}, ${sqlLiteral(ids.primaryAccount)}, 'business_inventory',
   null, 'Warehouse', 'active', 41),
  (${sqlLiteral(ids.archived)}, ${sqlLiteral(ids.primaryAccount)}, 'project',
   ${sqlLiteral(ids.primaryProject)}, 'Archived', 'archived', 42),
  (${sqlLiteral(ids.otherProjectSpace)}, ${sqlLiteral(ids.otherAccount)}, 'project',
   ${sqlLiteral(ids.otherProject)}, 'Other Project', 'active', 2),
  (${sqlLiteral(ids.otherInventorySpace)}, ${sqlLiteral(ids.otherAccount)},
   'business_inventory', null, 'Other Inventory', 'active', 3);
end;
$space_read_setup$;
`;

const cleanupSQL = `
do $space_read_cleanup$
begin
delete from public.spike_accounts
where id in (${sqlLiteral(ids.primaryAccount)}, ${sqlLiteral(ids.otherAccount)});
delete from auth.users
where id in (${sqlLiteral(ADMIN_AUTH_USER_ID)}, ${sqlLiteral(REVOKED_AUTH_USER_ID)});
end;
$space_read_cleanup$;
`;

const status = localStatus();
localSQL(setupSQL);

try {
  const projectFilter = `account_id=eq.${encodeURIComponent(ids.primaryAccount)}`
    + `&scope_kind=eq.project&project_id=eq.${encodeURIComponent(ids.primaryProject)}`;
  const projectPath = `/spike_spaces?${projectFilter}`
    + "&select=id,account_id,scope_kind,project_id,display_name,lifecycle,revision";
  const expectedProjectIDs = [ids.kitchen, ids.loftA, ids.loftZ].sort();

  for (const [label, subject] of [
    ["owner", OWNER_AUTH_USER_ID],
    ["admin", ADMIN_AUTH_USER_ID],
    ["employee", EMPLOYEE_AUTH_USER_ID],
  ]) {
    const visible = await rows(status, subject, projectPath);
    assert.deepEqual(visible.map((row) => row.id).sort(), expectedProjectIDs, `${label} Project rows`);
    assert.ok(visible.every((row) => row.account_id === ids.primaryAccount));
    assert.ok(visible.every((row) => row.scope_kind === "project"));
    assert.ok(visible.every((row) => row.project_id === ids.primaryProject));
    assert.ok(visible.every((row) => row.lifecycle === "active"));
    assert.ok(visible.every((row) => Number.isSafeInteger(row.revision) && row.revision > 0));
  }

  const inventory = await rows(
    status,
    EMPLOYEE_AUTH_USER_ID,
    `/spike_spaces?account_id=eq.${encodeURIComponent(ids.primaryAccount)}`
      + "&scope_kind=eq.business_inventory&project_id=is.null&select=*",
  );
  assert.deepEqual(inventory, [{
    id: ids.inventory,
    account_id: ids.primaryAccount,
    scope_kind: "business_inventory",
    project_id: null,
    display_name: "Warehouse",
    lifecycle: "active",
    revision: 41,
  }]);

  const ownerAll = await rows(
    status,
    OWNER_AUTH_USER_ID,
    `/spike_spaces?account_id=eq.${encodeURIComponent(ids.primaryAccount)}&select=id`,
  );
  assert.deepEqual(
    ownerAll.map((row) => row.id).sort(),
    [...expectedProjectIDs, ids.inventory].sort(),
    "archived rows must be absent even without a lifecycle filter",
  );

  assert.deepEqual(
    await rows(status, OWNER_AUTH_USER_ID,
      `/spike_spaces?id=eq.${encodeURIComponent(ids.archived)}&select=id`),
    [],
    "archived Space must be non-enumerable",
  );
  assert.deepEqual(
    await rows(status, REVOKED_AUTH_USER_ID,
      `/spike_spaces?account_id=eq.${encodeURIComponent(ids.primaryAccount)}&select=id`),
    [],
    "revoked membership must be non-enumerable",
  );
  assert.deepEqual(
    await rows(status, OWNER_AUTH_USER_ID,
      `/spike_spaces?account_id=eq.${encodeURIComponent(ids.otherAccount)}&select=id`),
    [],
    "caller-supplied foreign Account filter cannot broaden visibility",
  );

  const otherVisible = await rows(status, OTHER_AUTH_USER_ID, "/spike_spaces?select=id");
  assert.deepEqual(
    otherVisible.map((row) => row.id).sort(),
    [ids.otherInventorySpace, ids.otherProjectSpace].sort(),
    "cross-Account caller must see only their active Account rows",
  );

  const anonymousRead = await request(status, null, "/spike_spaces?select=id");
  assertDenied(anonymousRead, "anonymous read");

  const directInsert = await request(status, OWNER_AUTH_USER_ID, "/spike_spaces", {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({
      id: `space-read-direct-${suffix}`,
      account_id: ids.primaryAccount,
      scope_kind: "business_inventory",
      project_id: null,
      display_name: "Direct",
      lifecycle: "active",
      revision: 1,
    }),
  });
  assertDenied(directInsert, "authenticated insert");

  const directUpdate = await request(
    status,
    OWNER_AUTH_USER_ID,
    `/spike_spaces?id=eq.${encodeURIComponent(ids.kitchen)}`,
    { method: "PATCH", body: JSON.stringify({ display_name: "Changed" }) },
  );
  assertDenied(directUpdate, "authenticated update");

  const directDelete = await request(
    status,
    OWNER_AUTH_USER_ID,
    `/spike_spaces?id=eq.${encodeURIComponent(ids.kitchen)}`,
    { method: "DELETE" },
  );
  assertDenied(directDelete, "authenticated delete");

  const anonymousWrite = await request(status, null, "/spike_spaces", {
    method: "POST",
    body: JSON.stringify({ id: `space-read-anon-${suffix}` }),
  });
  assertDenied(anonymousWrite, "anonymous write");

  console.log(
    "local-space-assignment-destination-read: owner/admin/employee visible; "
      + "anonymous/revoked/cross-account/archived/write denied",
  );
} finally {
  localSQL(cleanupSQL);
}
