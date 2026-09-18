import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { realpathSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";

// Two real Postgres sessions publish different reserved Item images against one
// gallery. Private state and refs are removed after both sessions terminate;
// immutable image-object evidence is intentionally retained by the schema.
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT);
assert.match(JSON.parse(execFileSync("docker", ["context", "inspect", "--format", "{{json .Endpoints.docker.Host}}"], {
  encoding: "utf8", timeout: 10_000,
})), /^unix:\/\//);
const container = "supabase_db_ledger_target_supabase_local";
const labels = JSON.parse(execFileSync("docker", ["inspect", "--format", "{{json .Config.Labels}}", container], {
  encoding: "utf8", timeout: 10_000,
}));
assert.equal(labels["com.supabase.cli.project"], "ledger_target_supabase_local");
assert.equal(realpathSync(labels["com.supabase.cli.workdir"]), realpathSync(process.cwd()));
let local;
try {
  local = JSON.parse(execFileSync("npx", ["--offline", "--yes", "supabase@2.116.0", "status", "-o", "json"], {
    encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 15_000,
  }));
} catch { throw new Error("Cannot read isolated local Supabase credentials; no fallback"); }
assert.equal(local.API_URL, "http://127.0.0.1:54321");
assert.equal(typeof local.SERVICE_ROLE_KEY, "string");
const psqlArgs = ["exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-U", "postgres", "-d", "postgres",
  "-v", "ON_ERROR_STOP=1"];
const q = (value) => `'${String(value).replaceAll("'", "''")}'`;
const query = (text) => execFileSync("docker", psqlArgs, {
  input: `set statement_timeout='8s';\n${text}`, encoding: "utf8", timeout: 15_000,
}).trim();

const suffix = randomUUID();
const item = `item-attachment-race-${suffix}`;
const first = `item-attachment-race-first-${suffix}`;
const second = `item-attachment-race-second-${suffix}`;
const firstHash = "11".repeat(32);
const secondHash = "22".repeat(32);
const firstPath = `accounts/account-primary/attachments/${first}/${firstHash}`;
const secondPath = `accounts/account-primary/attachments/${second}/${secondHash}`;
const holderLabel = `item_attach_holder_${suffix}`;
const waiterLabel = `item_attach_waiter_${suffix}`;
const sessions = [];
let fixtureCreated = false;

function openSession(label) {
  const child = spawn("docker", psqlArgs, { stdio: ["pipe", "pipe", "pipe"] });
  let output = "";
  let errors = "";
  let closed = false;
  child.stdout.on("data", (data) => { output += data; });
  child.stderr.on("data", (data) => { errors += data; });
  child.on("error", (error) => { errors += String(error); });
  const done = new Promise((resolve) => child.on("close", (code) => {
    closed = true;
    resolve({ code, output, errors });
  }));
  child.stdin.write(`set application_name=${q(label)}; set statement_timeout='15s'; set idle_in_transaction_session_timeout='15s';\n`);
  const session = { child, done, output: () => output, errors: () => errors, closed: () => closed };
  sessions.push(session);
  return session;
}
async function until(check, message) {
  const deadline = Date.now() + 8_000;
  while (!check()) {
    assert.ok(Date.now() < deadline, `Timed out: ${message}`);
    await delay(25);
  }
}
function publication(id, hash) {
  return `set local role service_role;
select public.spike_publish_verified_item_attachment('10000000-0000-0000-0000-000000000001',${q(id)},${q(hash)},1,'image/png');
select 'READY';`;
}
const storageDelete = async (path) => {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${local.API_URL}/storage/v1/object/ledger-attachments/${encodedPath}`, {
    method: "DELETE",
    headers: { apikey: local.SERVICE_ROLE_KEY, Authorization: `Bearer ${local.SERVICE_ROLE_KEY}` },
    signal: AbortSignal.timeout(20_000),
  });
  const body = await response.text();
  assert.ok([200, 204].includes(response.status), `Storage cleanup failed (${response.status}): ${body}`);
};

try {
  assert.equal(query("select to_regprocedure('public.spike_publish_verified_item_attachment(uuid,text,text,bigint,text)') is not null;"), "t");
  query(`begin;
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values(${q(item)},'account-primary','Item attachment concurrency proof','principal-owner');
insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
values(${q(item)},'account-primary',${q(item)},1,0);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.spike_begin_item_attachment_upload(${q(first)},'account-primary',${q(item)},${q(firstHash)},1,'image/png','First.png',0,true);
select public.spike_begin_item_attachment_upload(${q(second)},'account-primary',${q(item)},${q(secondHash)},1,'image/png','Second.png',1,true);
reset role;
insert into storage.objects(bucket_id,name) values('ledger-attachments',${q(firstPath)}),('ledger-attachments',${q(secondPath)});
commit;`);
  fixtureCreated = true;

  const holder = openSession(holderLabel);
  holder.child.stdin.write(`begin;\n${publication(first, firstHash)}\n`);
  await until(() => holder.output().includes("READY"), "first Item publication to hold its gallery lock");

  const waiter = openSession(waiterLabel);
  waiter.child.stdin.write(`begin;\n${publication(second, secondHash)}\n`);
  await until(() => query(`select exists(
    select 1 from pg_stat_activity w join pg_stat_activity h on h.pid=any(pg_blocking_pids(w.pid))
    where w.application_name=${q(waiterLabel)} and h.application_name=${q(holderLabel)}
      and w.wait_event_type='Lock'
  );`) === "t", "second Item publication to wait on the gallery row");
  assert.equal(waiter.output().includes("READY"), false, "second publication did not block");

  holder.child.stdin.write("commit;\n");
  await until(() => waiter.output().includes("READY"), "second Item publication after first commit");
  waiter.child.stdin.end("commit;\n");
  holder.child.stdin.end();
  const [holderResult, waiterResult] = await Promise.all([holder.done, waiter.done]);
  assert.equal(holderResult.code, 0, holderResult.errors);
  assert.equal(waiterResult.code, 0, waiterResult.errors);

  assert.equal(query(`select count(*) from public.item_image_references where item_id=${q(item)};`), "2");
  assert.equal(query(`select string_agg(id,',' order by position) from public.item_image_references where item_id=${q(item)};`),
    `${first},${second}`);
  assert.equal(query(`select count(*) from public.item_image_references where item_id=${q(item)} and is_primary;`), "1");
  assert.equal(query(`select revision||':'||expected_count from public.item_image_sets where id=${q(item)};`), "3:2");
  assert.equal(query(`select count(*) from public.item_image_objects where id in (${q(first)},${q(second)});`), "2");
  console.log(`local-item-attachment-concurrency: observed gallery-row lock; concurrent publications preserved ${first},${second} order, one primary and revision/count 3:2`);
} finally {
  for (const session of sessions) {
    if (!session.child.stdin.destroyed && !session.child.stdin.writableEnded) session.child.stdin.end("rollback;\n");
  }
  await Promise.allSettled(sessions.map((session) => session.done));
  try {
    query(`select pg_terminate_backend(pid) from pg_stat_activity
      where application_name in (${q(holderLabel)},${q(waiterLabel)}) and usename='postgres' and datname='postgres';`);
  } catch {}
  if (fixtureCreated) {
    let storageCleanupError;
    try {
      await Promise.all([storageDelete(firstPath), storageDelete(secondPath)]);
    } catch (error) {
      storageCleanupError = error;
    }
    query(`begin;
set constraints all deferred;
delete from public.item_image_references where item_id=${q(item)};
update public.item_image_sets set revision=revision+1, expected_count=0 where id=${q(item)};
delete from ledger_private.item_attachment_upload_results where upload_id in (${q(first)},${q(second)});
delete from ledger_private.item_attachment_uploads where id in (${q(first)},${q(second)});
delete from public.item_image_sets where id=${q(item)};
delete from public.spike_items where id=${q(item)} and account_id='account-primary';
commit;`);
    if (storageCleanupError) throw storageCleanupError;
  }
}
