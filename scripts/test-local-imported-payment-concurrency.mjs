import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { execFileSync, spawn } from "node:child_process";
import { realpathSync, readFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

// Fixed isolated local container only. No supplied URL, credentials or hosted
// fallback. Like other local RPC tests, retain uniquely named synthetic records
// for committed cross-session readback; do not bypass immutable evidence cleanup.
const container = "supabase_db_ledger_target_supabase_local";
const labels = JSON.parse(execFileSync("docker", ["inspect", "--format", "{{json .Config.Labels}}", container], { encoding: "utf8" }));
assert.equal(labels["com.supabase.cli.project"], "ledger_target_supabase_local");
assert.equal(realpathSync(labels["com.supabase.cli.workdir"]), realpathSync(process.cwd()));
const args = ["exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"];
const live = new Set();
const quote = (value) => `'${value.replaceAll("'", "''")}'`;
function query(sql) {
  return execFileSync("docker", args, { input: "set standard_conforming_strings=on;\n" + sql, encoding: "utf8", timeout: 10_000 }).trim();
}
function session(sql, keepOpen = false) {
  const child = spawn("docker", args, { stdio: ["pipe", "pipe", "pipe"] });
  live.add(child);
  let out = "", error = "";
  child.stdout.on("data", (data) => { out += data; });
  child.stderr.on("data", (data) => { error += data; });
  child.on("error", (failure) => { error += String(failure); });
  const done = new Promise((resolve) => child.on("close", (code) => {
    live.delete(child);
    resolve({ code, out, error });
  }));
  if (keepOpen) child.stdin.write(sql); else child.stdin.end(sql);
  return { child, done, output: () => out };
}
async function until(check, description) {
  const deadline = Date.now() + 8_000;
  while (!(await check())) {
    assert.ok(Date.now() < deadline, `Timed out: ${description}`);
    await delay(25);
  }
}
const suffix = randomUUID();
const project = `payment-race-project-${suffix}`;
query(`insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
 values (${quote(project)},'account-primary','client-existing','Synthetic payment concurrency',now(),now(),1,1,'principal-owner');`);

try {
  for (const mode of ["identical", "changed-amount", "changed-target"]) {
    const id = `payment-race-${mode}-${suffix}`;
    const otherID = mode === "changed-target" ? `payment-race-other-${suffix}` : id;
    const sourceID = `source-${mode}-${suffix}`;
    const application = `payment-waiter-${mode}-${suffix}`.slice(0, 63);
    const call = (target, amount) => `select ledger_private.import_client_payment(
      ${quote(target)},'account-primary',${quote(project)},'client-existing',${amount},'USD',
      'synthetic-concurrency',${quote(sourceID)},decode('007b7dff','hex'));`;
    const first = session(`begin; set local statement_timeout='15s'; ${call(id, "9007199254740993")} select 'HOLDING_PAYMENT';\n`, true);
    await until(() => first.output().includes("HOLDING_PAYMENT"), "first import acquired constraints");
    const second = session(`set application_name=${quote(application)}; set statement_timeout='15s';
      ${call(otherID, mode === "changed-amount" ? "9007199254740994" : "9007199254740993")}`);
    // Observe an actual database lock wait; timing alone is not concurrency proof.
    await until(() => query(`select count(*) from pg_stat_activity where application_name=${quote(application)} and wait_event_type='Lock';`) === "1", "second import blocked on first");
    first.child.stdin.end("commit;\n");
    assert.equal((await first.done).code, 0, "first payment commits");
    const result = await second.done;
    if (mode === "identical") assert.equal(result.code, 0, result.error);
    else {
      assert.notEqual(result.code, 0, "conflicting concurrent import must fail");
      assert.match(result.error, /22000/, result.error);
    }
    // Independent new connection reads committed facts, not a worker's own view.
    assert.equal(query(`select count(*) || ':' || min(amount_minor_units)::text from public.spike_transactions where project_id=${quote(project)} and id=${quote(id)};`), "1:9007199254740993");
    assert.equal(query(`select count(*) || ':' || min(encode(source_bytes,'hex')) from ledger_private.imported_transaction_sources where source_account_id='synthetic-concurrency' and source_document_id=${quote(sourceID)};`), "1:007b7dff");
    if (mode === "changed-target") assert.equal(query(`select count(*) from public.spike_transactions where id=${quote(otherID)};`), "0", "source conflict rolled back provisional target");
  }
  // Swift tests prove the real mapped batch emits these exact parameter values.
  // Consume that shared fixture here, crossing the JSON/text/bytea boundary.
  const p = JSON.parse(readFileSync("LedgeriOS/LedgerTargetMigrationCoreTests/Fixtures/ClientPayment/import-parameters.json", "utf8"));
  const keys = ["p_id", "p_account_id", "p_project_id", "p_client_id", "p_amount", "p_currency", "p_source_account", "p_source_document", "p_source_bytes"];
  assert.deepEqual(Object.keys(p).sort(), [...keys].sort());
  assert.ok(keys.every((key) => typeof p[key] === "string"));
  assert.equal(p.p_account_id, "account-primary");
  assert.equal(p.p_client_id, "client-existing");
  assert.equal(p.p_project_id, "project-payment-export-fixture");
  assert.equal(p.p_id, "payment-export-fixture");
  assert.equal(p.p_amount, "9007199254740993");
  assert.equal(p.p_source_account, "synthetic-export-fixture");
  assert.match(p.p_source_bytes, /^\\x[0-9a-f]+$/);
  query(`insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
    values (${quote(p.p_project_id)},'account-primary','client-existing','Synthetic Swift export fixture',now(),now(),1,1,'principal-owner') on conflict (id) do nothing;`);
  const exportedCall = `select ledger_private.import_client_payment(${keys.map((key) => quote(p[key])).join(",")});`;
  assert.equal(query(exportedCall), p.p_id);
  assert.equal(query(exportedCall), p.p_id);
  assert.equal(query(`select amount_minor_units::text from public.spike_transactions where id=${quote(p.p_id)};`), p.p_amount);
  assert.equal(query(`select encode(source_bytes,'hex') from ledger_private.imported_transaction_sources where transaction_id=${quote(p.p_id)};`), p.p_source_bytes.slice(2));
  console.log("local-imported-payment-concurrency: 3 observed lock races, conflict rollback, committed readback and exact Swift-exported payment/source bytes passed");
} finally {
  for (const child of live) {
    child.stdin.destroy();
    child.kill("SIGTERM");
  }
}
