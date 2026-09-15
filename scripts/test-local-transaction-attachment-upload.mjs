import assert from "node:assert/strict";
import crypto from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { realpathSync } from "node:fs";

assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT);
const docker = (args, options = {}) => execFileSync("docker", args, {
  encoding: "utf8", timeout: 15_000, ...options,
});
assert.match(JSON.parse(docker(["context", "inspect", "--format", "{{json .Endpoints.docker.Host}}"])), /^unix:\/\//);
const container = "supabase_db_ledger_target_supabase_local";
const labels = JSON.parse(docker(["inspect", "--format", "{{json .Config.Labels}}", container]));
assert.equal(labels["com.supabase.cli.project"], "ledger_target_supabase_local");
assert.equal(realpathSync(labels["com.supabase.cli.workdir"]), realpathSync(process.cwd()));

let local;
try {
  local = JSON.parse(execFileSync("npx", ["--offline", "--yes", "supabase@2.116.0", "status", "-o", "json"], {
    encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 15_000,
  }));
} catch { throw new Error("Cannot read isolated local Supabase credentials; no fallback"); }
for (const key of ["API_URL", "PUBLISHABLE_KEY", "SERVICE_ROLE_KEY"]) {
  assert.equal(typeof local[key], "string");
  assert.ok(local[key].length > 0);
}
assert.equal(local.API_URL, "http://127.0.0.1:54321");

const q = (value) => `'${String(value).replaceAll("'", "''")}'`;
const sql = (query) => docker(["exec", "-i", container, "psql", "-X", "-q", "-A", "-t",
  "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"], { input: query }).trim();
const suffix = crypto.randomUUID();
const transaction = `upload-http-transaction-${suffix}`;
const attachment = `upload-http-attachment-${suffix}`;
const ownerPrincipal = `upload-http-owner-${suffix}`;
const memberPrincipal = `upload-http-member-${suffix}`;
const password = `Upload-${suffix}-aA1!`;
const createUser = async (kind) => {
  const email = `upload-${kind}-${suffix}@ledger-tests.invalid`;
  const response = await fetch(`${local.API_URL}/auth/v1/admin/users`, {
    method: "POST", redirect: "error", signal: AbortSignal.timeout(10_000),
    headers: { apikey: local.SERVICE_ROLE_KEY, Authorization: `Bearer ${local.SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  const user = await response.json();
  assert.equal(response.status, 200, JSON.stringify(user));
  const signIn = await fetch(`${local.API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", redirect: "error", signal: AbortSignal.timeout(10_000),
    headers: { apikey: local.PUBLISHABLE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const session = await signIn.json();
  assert.equal(signIn.status, 200, JSON.stringify(session));
  assert.equal(typeof session.access_token, "string");
  return { id: user.id, token: session.access_token, email };
};
const owner = await createUser("owner");
const member = await createUser("member");
sql(`begin;
 insert into public.spike_principals(id,auth_user_id) values
   (${q(ownerPrincipal)},${q(owner.id)}::uuid),(${q(memberPrincipal)},${q(member.id)}::uuid);
 insert into public.spike_account_memberships(account_id,principal_id,role,state,financial_access)
 values('account-primary',${q(ownerPrincipal)},'employee','active','full'),
   ('account-primary',${q(memberPrincipal)},'employee','active','none');
 insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
 values(${q(transaction)},'account-primary',1,'USD','purchase','vendor_payment','business_inventory','category-furnishings');
 insert into public.transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count)
 values(${q(`upload-http-set-${suffix}`)},'account-primary',${q(transaction)},'receipts',1,0);
 commit;`);

const ownerToken = owner.token;
const userProbe = await fetch(`${local.API_URL}/auth/v1/user`, {
  headers: { apikey: local.PUBLISHABLE_KEY, Authorization: `Bearer ${ownerToken}` },
});
assert.equal(userProbe.status, 200, await userProbe.text());
const run = spawnSync("swift", ["test", "--package-path", "LedgeriOS", "--no-parallel", "--filter",
  process.env.LEDGER_ATTACHMENT_RUNTIME === "1"
    ? "AccountWorkspacePendingWorkRuntimeTests/attachmentLiveReplication"
    : "SupabaseTransactionAttachmentUploadTests/actualLocalService"], {
  cwd: process.cwd(), encoding: "utf8", timeout: 120_000,
  env: {
    ...process.env,
    LEDGER_ATTACHMENT_LOCAL_URL: local.API_URL,
    LEDGER_ATTACHMENT_LOCAL_KEY: local.PUBLISHABLE_KEY,
    LEDGER_ATTACHMENT_LOCAL_TOKEN: ownerToken,
    LEDGER_ATTACHMENT_LOCAL_ACCOUNT: "account-primary",
    LEDGER_ATTACHMENT_LOCAL_PRINCIPAL: ownerPrincipal,
    LEDGER_ATTACHMENT_LOCAL_TRANSACTION: transaction,
    LEDGER_ATTACHMENT_LOCAL_ATTACHMENT: attachment,
    LEDGER_ATTACHMENT_LOCAL_EMAIL: owner.email,
    LEDGER_ATTACHMENT_LOCAL_PASSWORD: password,
  },
});
process.stdout.write(run.stdout);
process.stderr.write(run.stderr);
assert.equal(run.status, 0, `native resumable upload exited ${run.status}`);
if (process.env.LEDGER_ATTACHMENT_RUNTIME === "1") {
  assert.equal(sql(`select count(*) from public.transaction_attachment_references where transaction_id=${q(transaction)};`), "3");
  assert.equal(sql(`select count(*) from public.transaction_attachment_upload_results where transaction_id=${q(transaction)} and phase='applied';`), "3");
  console.log(`transaction-attachment-runtime: image/image/PDF captures → server verification → real sync → exact offline bytes and metadata after restart passed; ${suffix} retained`);
  process.exit(0);
}

const hash = crypto.createHash("sha256").update(Buffer.alloc(6 * 1024 * 1024 + 17, 0x7e)).digest("hex");
const path = `accounts/account-primary/attachments/${attachment}/${hash}`;
assert.equal(sql(`select count(*) from storage.objects where bucket_id='ledger-attachments' and name=${q(path)};`), "1");
assert.equal(sql(`select count(*) from public.transaction_attachment_references where transaction_id=${q(transaction)};`), "0",
  "byte transfer must not publish an attachment reference");

const denied = await fetch(`${local.API_URL}/storage/v1/object/authenticated/ledger-attachments/${path.split("/").map(encodeURIComponent).join("/")}`, {
  redirect: "error", signal: AbortSignal.timeout(10_000),
  headers: { apikey: local.PUBLISHABLE_KEY, Authorization: `Bearer ${member.token}` },
});
assert.ok([400, 403, 404].includes(denied.status), `another principal read unverified bytes: ${denied.status}`);
if (process.env.LEDGER_ATTACHMENT_VERIFY_EDGE === "1") {
  const verify = async (token, payload = { attachmentId: attachment }) => {
    const response = await fetch(`${local.API_URL}/functions/v1/verify-transaction-attachment`, {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(20_000),
      headers: { apikey: local.PUBLISHABLE_KEY, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const body = await response.json();
    return { response, body };
  };
  const invalid = await verify(ownerToken, null);
  assert.equal(invalid.response.status, 400, JSON.stringify(invalid.body));
  assert.equal(invalid.body.error, "invalid_attachment_id");
  const [published, concurrent] = await Promise.all([verify(ownerToken), verify(ownerToken)]);
  assert.equal(published.response.status, 200, JSON.stringify(published.body));
  assert.equal(published.body.phase, "applied");
  assert.equal(published.body.result_code, "attachment_published");
  assert.equal(concurrent.response.status, 200, JSON.stringify(concurrent.body));
  assert.deepEqual(concurrent.body, published.body, "concurrent verifiers share one immutable result");
  const replay = await verify(ownerToken);
  assert.equal(replay.response.status, 200, JSON.stringify(replay.body));
  assert.deepEqual(replay.body, published.body);
  assert.equal(sql(`select count(*) from public.transaction_attachment_references where id=${q(attachment)} and attachment_id=${q(attachment)};`), "1");
  assert.equal(sql(`select count(*) from public.transaction_attachment_upload_results where upload_id=${q(attachment)} and phase='applied';`), "1");
  const publishedRead = await fetch(`${local.API_URL}/storage/v1/object/authenticated/ledger-attachments/${path.split("/").map(encodeURIComponent).join("/")}`, {
    redirect: "error", signal: AbortSignal.timeout(10_000),
    headers: { apikey: local.PUBLISHABLE_KEY, Authorization: `Bearer ${member.token}` },
  });
  assert.equal(publishedRead.status, 200, "ordinary authorized member should read published bytes");
  assert.equal(Buffer.compare(Buffer.from(await publishedRead.arrayBuffer()), Buffer.alloc(6 * 1024 * 1024 + 17, 0x7e)), 0);
  const hidden = await verify(member.token);
  assert.equal(hidden.response.status, 404, "another principal cannot invoke verification by upload ID");
  console.log(`transaction-attachment-upload: real local RPC → interrupted TUS → server hash/publication → idempotent replay passed; ${suffix} retained published`);
} else {
  console.log(`transaction-attachment-upload: real local RPC → interrupted TUS chunk → HEAD resume → exact GET passed; ${suffix} retained unpublished`);
}
