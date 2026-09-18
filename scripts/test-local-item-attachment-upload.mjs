import assert from "node:assert/strict";
import crypto from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { realpathSync, writeFileSync } from "node:fs";

// Bounded local-only evidence for an existing Item. The fixture is intentionally
// retained so the Storage object, verifier result and synced reference can be
// inspected after the run; every identifier is unique per invocation.
assert.notEqual(process.env.USE_FIREBASE_EMULATORS, "1");
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
if (process.env.LEDGER_ATTACHMENT_ITEM_RUNTIME === "1") {
  const ready = await fetch("http://127.0.0.1:5590/probes/readiness", {
    redirect: "error", signal: AbortSignal.timeout(5_000),
  });
  assert.equal(ready.status, 200, "Start the owned local PowerSync service before live runtime verification");
}

const q = (value) => `'${String(value).replaceAll("'", "''")}'`;
const sql = (query) => docker(["exec", "-i", container, "psql", "-X", "-q", "-A", "-t",
  "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"], { input: query }).trim();
const request = async (url, options = {}) => fetch(url, {
  redirect: "error", signal: AbortSignal.timeout(20_000), ...options,
});
const parseBody = async (response) => {
  const text = await response.text();
  if (!text) return null;
  try { return JSON.parse(text); } catch { return text; }
};
const authHeaders = (token) => ({ apikey: local.PUBLISHABLE_KEY, Authorization: `Bearer ${token}` });
const rpc = async (token, name, body) => {
  const response = await request(`${local.API_URL}/rest/v1/rpc/${name}`, {
    method: "POST", headers: { ...authHeaders(token), "Content-Type": "application/json",
      Accept: "application/vnd.pgrst.object+json" }, body: JSON.stringify(body),
  });
  return { response, body: await parseBody(response) };
};
const verify = async (token, attachmentId) => {
  const response = await request(`${local.API_URL}/functions/v1/verify-item-attachment`, {
    method: "POST", headers: { ...authHeaders(token), "Content-Type": "application/json" },
    body: JSON.stringify({ attachmentId }),
  });
  return { response, body: await parseBody(response) };
};
const storagePathURL = (path) => `${local.API_URL}/storage/v1/object/authenticated/ledger-attachments/${path
  .split("/").map(encodeURIComponent).join("/")}`;
const storageGet = async (token, path) => request(storagePathURL(path), { headers: authHeaders(token) });
const expectDenied = (response, label) => assert.ok([400, 401, 403, 404].includes(response.status),
  `${label} unexpectedly succeeded with ${response.status}`);
const createUser = async (kind, suffix, password) => {
  const email = `item-upload-${kind}-${suffix}@ledger-tests.invalid`;
  const response = await request(`${local.API_URL}/auth/v1/admin/users`, {
    method: "POST", headers: { apikey: local.SERVICE_ROLE_KEY,
      Authorization: `Bearer ${local.SERVICE_ROLE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  const user = await parseBody(response);
  assert.equal(response.status, 200, JSON.stringify(user));
  const signIn = await request(`${local.API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: local.PUBLISHABLE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const session = await parseBody(signIn);
  assert.equal(signIn.status, 200, JSON.stringify(session));
  assert.equal(typeof session.access_token, "string");
  return { id: user.id, email, token: session.access_token };
};
const sha256 = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex");
const tusMetadata = (values) => Object.entries(values).map(([key, value]) =>
  `${key} ${Buffer.from(value, "utf8").toString("base64")}`).join(",");
const directTusUpload = async (token, path, bytes) => {
  const created = await request(`${local.API_URL}/storage/v1/upload/resumable`, {
    method: "POST", headers: { ...authHeaders(token), "Tus-Resumable": "1.0.0",
      "Upload-Length": String(bytes.length), "Upload-Metadata": tusMetadata({
        bucketName: "ledger-attachments", objectName: path, contentType: "image/png", cacheControl: "3600",
      }) },
  });
  assert.equal(created.status, 201, await created.text());
  const uploadURL = created.headers.get("location");
  assert.equal(typeof uploadURL, "string");
  assert.match(uploadURL, /^http:\/\/127\.0\.0\.1:54321\/storage\/v1\/upload\/resumable\//);
  const uploaded = await request(uploadURL, {
    method: "PATCH", headers: { ...authHeaders(token), "Tus-Resumable": "1.0.0",
      "Upload-Offset": "0", "Content-Type": "application/offset+octet-stream" }, body: bytes,
  });
  assert.equal(uploaded.status, 204, await uploaded.text());
  assert.equal(uploaded.headers.get("upload-offset"), String(bytes.length));
};

const suffix = crypto.randomUUID();
const item = `upload-http-item-${suffix}`;
const attachment = `upload-http-item-attachment-${suffix}`;
const badAttachment = `upload-http-item-bad-${suffix}`;
const ownerPrincipal = `upload-http-item-owner-${suffix}`;
const memberPrincipal = `upload-http-item-member-${suffix}`;
const password = `Item-${suffix}-aA1!`;
const bytes = Buffer.alloc(6 * 1024 * 1024 + 17, 0x4d);
const hash = sha256(bytes);
const path = `accounts/account-primary/attachments/${attachment}/${hash}`;
const badBytes = Buffer.alloc(4097, 0x62);
const badExpected = Buffer.alloc(badBytes.length, 0x61);
const badHash = sha256(badExpected);
const badPath = `accounts/account-primary/attachments/${badAttachment}/${badHash}`;
const owner = await createUser("owner", suffix, password);
const member = await createUser("member", suffix, password);

sql(`begin;
 insert into public.spike_principals(id,auth_user_id) values
   (${q(ownerPrincipal)},${q(owner.id)}::uuid),(${q(memberPrincipal)},${q(member.id)}::uuid);
 insert into public.spike_account_memberships(account_id,principal_id,role,state,financial_access)
 values('account-primary',${q(ownerPrincipal)},'employee','active','full'),
   ('account-primary',${q(memberPrincipal)},'employee','active','none');
 insert into public.spike_items(id,account_id,description,created_by_principal_id)
 values(${q(item)},'account-primary','Item HTTP attachment proof',${q(ownerPrincipal)});
 insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
 values(${q(item)},'account-primary',${q(item)},1,0);
 commit;`);
const baselineItem = sql(`select revision||'|'||description from public.spike_items where id=${q(item)} and account_id='account-primary';`);
assert.equal(baselineItem, "1|Item HTTP attachment proof");

if (process.env.LEDGER_ATTACHMENT_ITEM_RUNTIME === "1") {
  sql(`insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
    values(${q(`placement-${suffix}`)},'account-primary',${q(item)},'business_inventory',now(),${q(ownerPrincipal)});`);
  const runtime = spawnSync("swift", ["test", "--package-path", "LedgeriOS", "--no-parallel", "--filter",
    "AccountWorkspacePendingWorkRuntimeTests/actualItemLiveReplication"], {
    cwd: process.cwd(), encoding: "utf8", timeout: 300_000,
    env: { ...process.env, LEDGER_ATTACHMENT_LOCAL_URL: local.API_URL,
      LEDGER_ATTACHMENT_LOCAL_KEY: local.PUBLISHABLE_KEY, LEDGER_ATTACHMENT_LOCAL_TOKEN: owner.token,
      LEDGER_ATTACHMENT_LOCAL_ACCOUNT: "account-primary", LEDGER_ATTACHMENT_LOCAL_PRINCIPAL: ownerPrincipal,
      LEDGER_ATTACHMENT_LOCAL_ITEM: item, LEDGER_ATTACHMENT_LOCAL_ATTACHMENT: attachment,
      LEDGER_ATTACHMENT_LOCAL_EMAIL: owner.email, LEDGER_ATTACHMENT_LOCAL_PASSWORD: password },
  });
  const output = `${runtime.stdout ?? ""}${runtime.stderr ?? ""}`;
  writeFileSync("/tmp/ledger-item-attachment-runtime-native.log", output);
  process.stdout.write(output.split("\n").slice(-25).join("\n"));
  assert.equal(runtime.status, 0, "native Item runtime failed; /tmp/ledger-item-attachment-runtime-native.log");
  assert.match(output, /actualItemLiveReplication|Actual Item capture uploads/);
  assert.equal(sql(`select count(*) from public.item_image_references where item_id=${q(item)};`), "2");
  assert.equal(sql(`select count(*) from public.item_image_references where item_id=${q(item)} and is_primary;`), "1");
  assert.equal(sql(`select revision||'|'||description from public.spike_items where id=${q(item)};`), baselineItem);
  console.log(`item-attachment-runtime: real capture/upload/PowerSync/readback/encrypted restart/exact originals passed; ${item} retained`);
  process.exit(0);
}

const reservation = await rpc(owner.token, "spike_begin_item_attachment_upload", {
  p_id: attachment, p_account_id: "account-primary", p_item_id: item, p_content_sha256: hash,
  p_byte_count: bytes.length, p_media_type: "image/png", p_file_name: "Item original.png",
  p_local_position: 0, p_make_primary_if_empty: true,
});
assert.equal(reservation.response.status, 200, JSON.stringify(reservation.body));
assert.deepEqual(reservation.body, { attachmentId: attachment, accountId: "account-primary",
  principalId: ownerPrincipal, itemId: item, bucket: "ledger-attachments", storagePath: path,
  contentSHA256: hash, byteCount: String(bytes.length), mediaType: "image/png", phase: "awaiting_upload" });

const pendingMemberRead = await storageGet(member.token, path);
expectDenied(pendingMemberRead, "member pending Item read");
const pendingMemberVerify = await verify(member.token, attachment);
expectDenied(pendingMemberVerify.response, "member pending Item verification");
assert.equal(pendingMemberVerify.response.status, 404);
const foreignReservation = await rpc(owner.token, "spike_begin_item_attachment_upload", {
  p_id: `foreign-${suffix}`, p_account_id: "account-other", p_item_id: item, p_content_sha256: hash,
  p_byte_count: bytes.length, p_media_type: "image/png", p_file_name: "Foreign.png",
  p_local_position: 0, p_make_primary_if_empty: true,
});
expectDenied(foreignReservation.response, "foreign Account Item reservation");

// The native test performs an interrupted six-MiB TUS transfer, resumes from
// the server HEAD offset, invokes the Item verifier, and retries publication.
const native = spawnSync("swift", ["test", "--package-path", "LedgeriOS", "--no-parallel", "--filter",
  "SupabaseTransactionAttachmentUploadTests/actualLocalItemService"], {
  cwd: process.cwd(), encoding: "utf8", timeout: 300_000,
  env: { ...process.env, LEDGER_ATTACHMENT_ITEM_HTTP: "1", LEDGER_ATTACHMENT_LOCAL_URL: local.API_URL,
    LEDGER_ATTACHMENT_LOCAL_KEY: local.PUBLISHABLE_KEY, LEDGER_ATTACHMENT_LOCAL_TOKEN: owner.token,
    LEDGER_ATTACHMENT_LOCAL_ACCOUNT: "account-primary", LEDGER_ATTACHMENT_LOCAL_PRINCIPAL: ownerPrincipal,
    LEDGER_ATTACHMENT_LOCAL_ITEM: item, LEDGER_ATTACHMENT_LOCAL_ATTACHMENT: attachment,
    LEDGER_ATTACHMENT_LOCAL_EMAIL: owner.email, LEDGER_ATTACHMENT_LOCAL_PASSWORD: password },
});
const nativeOutput = `${native.stdout ?? ""}${native.stderr ?? ""}`;
writeFileSync("/tmp/ledger-item-attachment-native.log", nativeOutput);
process.stdout.write(nativeOutput.split("\n").slice(-80).join("\n"));
assert.equal(native.status, 0, `native Item upload exited ${native.status}; full log: /tmp/ledger-item-attachment-native.log`);

assert.equal(sql(`select count(*) from storage.objects where bucket_id='ledger-attachments' and name=${q(path)};`), "1");
const memberPublishedRead = await storageGet(member.token, path);
if (memberPublishedRead.status !== 200) throw new Error(`published Item read failed with ${memberPublishedRead.status}: ${await memberPublishedRead.text()}`);
assert.deepEqual(Buffer.from(await memberPublishedRead.arrayBuffer()), bytes, "published bytes changed");
const ownerApplied = await verify(owner.token, attachment);
assert.equal(ownerApplied.response.status, 200, JSON.stringify(ownerApplied.body));
assert.equal(ownerApplied.body.phase, "applied");
assert.equal(ownerApplied.body.revision, "2");
assert.equal(ownerApplied.body.position, 0);
const ownerReplay = await verify(owner.token, attachment);
assert.equal(ownerReplay.response.status, 200, JSON.stringify(ownerReplay.body));
assert.deepEqual(ownerReplay.body, ownerApplied.body, "Item publication retry changed its result");
const memberPublishedVerify = await verify(member.token, attachment);
assert.equal(memberPublishedVerify.response.status, 404, "member can invoke uploader-only verification");

const evidence = JSON.parse(sql(`select json_build_object(
 'objects',(select count(*) from public.item_image_objects where id=${q(attachment)} and account_id='account-primary'
   and content_sha256=${q(hash)} and byte_count=${bytes.length} and media_type='image/png' and storage_path=${q(path)}),
 'references',(select count(*) from public.item_image_references where id=${q(attachment)} and item_id=${q(item)}
   and attachment_id=${q(attachment)} and set_revision=2 and position=0 and is_primary),
 'gallery_revision',(select revision from public.item_image_sets where id=${q(item)}),
 'gallery_count',(select expected_count from public.item_image_sets where id=${q(item)}),
 'primary_count',(select count(*) from public.item_image_references where item_id=${q(item)} and is_primary),
 'item',(select revision||'|'||description from public.spike_items where id=${q(item)} and account_id='account-primary')
 )::text;`));
assert.deepEqual(evidence, { objects: 1, references: 1, gallery_revision: 2,
  gallery_count: 1, primary_count: 1, item: baselineItem });

// Upload bytes whose content disagrees with the reserved hash. The verifier
// must reject both attempts and must not create an Item object or reference.
const badReservation = await rpc(owner.token, "spike_begin_item_attachment_upload", {
  p_id: badAttachment, p_account_id: "account-primary", p_item_id: item, p_content_sha256: badHash,
  p_byte_count: badExpected.length, p_media_type: "image/png", p_file_name: "Wrong bytes.png",
  p_local_position: 1, p_make_primary_if_empty: false,
});
assert.equal(badReservation.response.status, 200, JSON.stringify(badReservation.body));
assert.equal(badReservation.body.storagePath, badPath);
await directTusUpload(owner.token, badPath, badBytes);
const badVerification = await verify(owner.token, badAttachment);
assert.equal(badVerification.response.status, 409, JSON.stringify(badVerification.body));
assert.equal(badVerification.body.error, "stored_bytes_mismatch");
const badRetry = await verify(owner.token, badAttachment);
assert.equal(badRetry.response.status, 409, JSON.stringify(badRetry.body));
assert.equal(badRetry.body.error, "stored_bytes_mismatch");
assert.equal(sql(`select count(*) from public.item_image_objects where id=${q(badAttachment)};`), "0");
assert.equal(sql(`select count(*) from public.item_image_references where id=${q(badAttachment)};`), "0");
const badMemberRead = await storageGet(member.token, badPath);
expectDenied(badMemberRead, "member rejected Item bytes read");

const foreignPublishedRead = await storageGet(owner.token,
  `accounts/account-other/attachments/${attachment}/${hash}`);
expectDenied(foreignPublishedRead, "foreign Account Item read");
console.log(`item-attachment-upload: authenticated reservation → pending tenant denial → interrupted TUS/HEAD resume → exact member readback → verifier reference/primary/retry → hash rejection passed; ${suffix} retained (${item}, ${attachment}, ${badAttachment})`);
