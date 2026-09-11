import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { execFileSync, spawn } from "node:child_process";
import { realpathSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

// Local synthetic constraint test, not an authorized Item command. Neither
// placement commits: immutable history must never require cleanup bypasses.
const container = "supabase_db_ledger_target_supabase_local";
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT, "No Docker destination override");
const endpoint = JSON.parse(execFileSync("docker", ["context", "inspect", "--format", "{{json .Endpoints.docker.Host}}"], { encoding: "utf8", timeout: 10_000 }));
assert.ok(endpoint.startsWith("unix://"), "Only a local Unix Docker socket is authorized");
const labels = JSON.parse(execFileSync("docker", ["inspect", "--format", "{{json .Config.Labels}}", container], { encoding: "utf8", timeout: 10_000 }));
assert.equal(labels["com.supabase.cli.project"], "ledger_target_supabase_local");
assert.equal(realpathSync(labels["com.supabase.cli.workdir"]), realpathSync(process.cwd()));
const args = ["exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"];
const quote = (value) => `'${value.replaceAll("'", "''")}'`;
function query(sql) {
  return execFileSync("docker", args, { input: `set standard_conforming_strings=on; set statement_timeout='5s';\n${sql}`, encoding: "utf8", timeout: 8_000 }).trim();
}
const suffix = randomUUID();
const itemID = `placement-race-item-${suffix}`;
const description = `Synthetic placement race ${suffix}`;
const applications = [`placement-holder-${suffix}`, `placement-waiter-${suffix}`];
const workers = [];
function session(application, sql) {
  const child = spawn("docker", args, { stdio: ["pipe", "pipe", "pipe"] });
  let output = "", errors = "", closed = false;
  child.stdout.on("data", (data) => { output += data; });
  child.stderr.on("data", (data) => { errors += data; });
  child.on("error", (error) => { errors += String(error); });
  const done = new Promise((resolve) => child.on("close", (code) => {
    closed = true;
    resolve({ code, errors });
  }));
  // The idle timeout also bounds an abandoned holder if this Node process dies.
  child.stdin.on("error", () => {});
  child.stdin.write(`set application_name=${quote(application)}; set statement_timeout='15s'; set idle_in_transaction_session_timeout='15s'; begin;\n${sql}\n`);
  const worker = { child, done, output: () => output, closed: () => closed };
  workers.push(worker);
  return worker;
}
async function until(check, message) {
  const deadline = Date.now() + 8_000;
  while (!check()) {
    assert.ok(Date.now() < deadline, `Timed out: ${message}`);
    await delay(25);
  }
}
const insert = (id) => `insert into public.spike_item_placements
  (id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
  values (${quote(id)},'account-primary',${quote(itemID)},'business_inventory','2026-09-01T00:00:00Z','principal-owner');`;
let created = false;
try {
  query(`insert into public.spike_items(id,account_id,description,created_by_principal_id)
    values (${quote(itemID)},'account-primary',${quote(description)},'principal-owner');`);
  created = true;
  const holder = session(applications[0], `${insert(`placement-holder-${suffix}`)} select 'HOLDER_INSERTED';`);
  await until(() => holder.output().includes("HOLDER_INSERTED"), "holder inserted an uncommitted active placement");
  const waiter = session(applications[1], `${insert(`placement-waiter-${suffix}`)} select 'WAITER_INSERTED';`);
  // Prove the second backend is actually waiting on the first, not merely slow.
  await until(() => query(`select count(*) from pg_stat_activity w join pg_stat_activity h
    on h.pid = any(pg_blocking_pids(w.pid))
    where w.application_name=${quote(applications[1])} and h.application_name=${quote(applications[0])}
      and w.wait_event_type='Lock';`) === "1", "competing insert blocked by holder");
  assert.equal(waiter.output().includes("WAITER_INSERTED"), false);
  holder.child.stdin.end("rollback;\n");
  await until(() => holder.closed(), "holder rolled back");
  assert.equal((await holder.done).code, 0);
  await until(() => waiter.output().includes("WAITER_INSERTED"), "waiter succeeds after rollback releases conflict");
  waiter.child.stdin.end("select count(*) from public.spike_item_placements where item_id=" + quote(itemID) + "; rollback;\n");
  await until(() => waiter.closed(), "waiter rolled back");
  const result = await waiter.done;
  assert.equal(result.code, 0, result.errors);
  assert.match(waiter.output(), /WAITER_INSERTED\s+1(?:\s|$)/, "waiter sees exactly its own active placement");
  assert.equal(query(`select count(*) from public.spike_item_placements where item_id=${quote(itemID)};`), "0", "neither competing placement committed");
  console.log("local-item-placement-concurrency: observed competing insert lock; holder rollback admits waiter; both roll back without retained placement history");
} finally {
  // Terminate only these randomly named test sessions if an assertion failed.
  // Closing docker's client alone need not immediately terminate its DB backend.
  try {
    query(`select pg_terminate_backend(pid) from pg_stat_activity
      where application_name in (${applications.map(quote).join(",")}) and usename='postgres' and datname='postgres';`);
  } finally {
    for (const worker of workers) {
      worker.child.stdin.destroy();
      if (!worker.closed()) worker.child.kill("SIGTERM");
    }
  }
  if (created) {
    await until(() => query(`select count(*) from pg_stat_activity where application_name in (${applications.map(quote).join(",")});`) === "0", "owned backends finish rollback before fixture removal");
    // Exact fixture ownership and no placements are mandatory. Never delete or
    // truncate placement rows (including when this test itself fails).
    assert.equal(query(`select count(*) from public.spike_item_placements where item_id=${quote(itemID)};`), "0");
    assert.equal(query(`delete from public.spike_items where id=${quote(itemID)}
      and account_id='account-primary' and description=${quote(description)}
      and created_by_principal_id='principal-owner' and revision=1 returning id;`), itemID);
  }
}
