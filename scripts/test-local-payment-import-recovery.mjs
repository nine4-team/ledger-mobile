import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import path from "node:path";

// Execute the real Swift importer in separate processes, using only the existing
// local synthetic database. Keep run artifacts and immutable synthetic rows for
// inspection; never disable retention triggers to clean up a test.
assert.equal(process.platform, "darwin", "This executable integration is macOS-only");
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT, "No Docker destination override");
const context = JSON.parse(execFileSync("docker", ["context", "inspect"], { encoding: "utf8" }));
assert.match(context[0]?.Endpoints?.docker?.Host ?? "", /^unix:\/\//);
const container = "supabase_db_ledger_target_supabase_local";
const labels = JSON.parse(execFileSync("docker", ["inspect", "--format", "{{json .Config.Labels}}", container], { encoding: "utf8" }));
assert.equal(labels["com.supabase.cli.project"], "ledger_target_supabase_local");
assert.equal(realpathSync(labels["com.supabase.cli.workdir"]), realpathSync(process.cwd()));
const sql = (input) => execFileSync("docker", ["exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
  { input, encoding: "utf8", timeout: 15_000 }).trim();
execFileSync("swift", ["build", "--package-path", "LedgeriOS", "--product", "LedgerLocalPaymentImport"], { stdio: "inherit", timeout: 120_000 });
const binDir = execFileSync("swift", ["build", "--package-path", "LedgeriOS", "--show-bin-path"], { encoding: "utf8" }).trim();
const bin = path.join(binDir, "LedgerLocalPaymentImport");
const tempRoot = path.resolve("supabase/.temp");
mkdirSync(tempRoot, { recursive: true });
const newRun = () => {
  const dir = realpathSync(mkdtempSync(path.join(tempRoot, "payment-recovery-")));
  const id = createHash("sha256").update(dir).digest("hex").slice(0, 32);
  return { dir, id, project: `local-payment-project-${id}`, first: `local-payment-${id}-1`, second: `local-payment-${id}-2` };
};
function run(fixture, flag, env = process.env) {
  const result = spawnSync(bin, ["--run-directory", fixture.dir, ...(flag ? [flag] : [])], { encoding: "utf8", timeout: 30_000, env });
  assert.equal(result.error, undefined, String(result.error));
  return result;
}
function expectExit(result, code) {
  assert.equal(result.status, code, `${result.stdout}\n${result.stderr}`);
}
const counts = (fixture) => sql(`select count(*) || ':' || coalesce(sum(amount_minor_units),0)::text from public.spike_transactions where project_id='${fixture.project}';`);
const noteCount = (fixture) => sql(`select count(*) from ledger_private.imported_project_legacy_note_sources where project_id='${fixture.project}';`);
const journal = (fixture) => JSON.parse(readFileSync(path.join(fixture.dir, "journal.json"), "utf8"));
function assertCompleted(fixture) {
  const value = journal(fixture);
  assert.equal(value.events.at(-1).stage, "finalize");
  assert.equal(value.events.at(-1).state, "completed");
  assert.equal(value.events.at(-1).outcomes.length, 2);
  assert.equal(value.events.at(-1).outcomes[0].applied, 2);
  assert.equal(value.events.at(-1).outcomes[1].entity, "project_legacy_notes");
  assert.equal(value.events.at(-1).outcomes[1].applied, 1);
  assert.equal(counts(fixture), "2:60");
  assert.equal(sql(`select count(*) from ledger_private.imported_transaction_sources where transaction_id in ('${fixture.first}','${fixture.second}');`), "2");
  assert.equal(noteCount(fixture), "1");
  assert.deepEqual(JSON.parse(sql(`select json_build_array(p.legacy_notes,s.imported_notes) from public.spike_projects p join ledger_private.imported_project_legacy_note_sources s on s.project_id=p.id where p.id='${fixture.project}';`)),
    ["  Original Project notes\nKeep the blue sofa.  ", "  Original Project notes\nKeep the blue sofa.  "]);
}
for (const flag of ["--interrupt-before-commit", "--interrupt-after-commit"]) {
  const fixture = newRun();
  expectExit(run(fixture, flag), 86);
  assert.equal(counts(fixture), flag === "--interrupt-before-commit" ? "0:0" : "2:60");
  assert.equal(noteCount(fixture), flag === "--interrupt-before-commit" ? "0" : "1");
  assert.ok(!journal(fixture).events.some((event) => event.stage === "load" && event.state === "completed"), "No acknowledgement before readback");
  expectExit(run(fixture), 0);
  assertCompleted(fixture);
  const completedBytes = readFileSync(path.join(fixture.dir, "journal.json"));
  expectExit(run(fixture), 0);
  assertCompleted(fixture);
  assert.deepEqual(readFileSync(path.join(fixture.dir, "journal.json")), completedBytes, "Completed replay preserves exact events and counts");
}
for (const artifact of ["source.json", "mappings.json", "plan.json"]) {
  const fixture = newRun();
  expectExit(run(fixture, "--interrupt-before-commit"), 86);
  const file = path.join(fixture.dir, artifact);
  const original = readFileSync(file);
  writeFileSync(file, Buffer.concat([original, Buffer.from("\n")]));
  assert.notEqual(run(fixture).status, 0, `Changed ${artifact} must fail before database writes`);
  assert.equal(counts(fixture), "0:0");
  writeFileSync(file, original);
  expectExit(run(fixture), 0);
  assertCompleted(fixture);
}
const conflict = newRun();
// Seed a conflicting second payment so the first provisional payment must roll
// back together with the batch, rather than being accepted as a partial import.
sql(`insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
 values ('${conflict.project}','account-primary','client-existing','Synthetic conflict',now(),now(),1,1,'principal-owner');
 select ledger_private.import_client_payment('${conflict.second}','account-primary','${conflict.project}','client-existing',99,'USD','synthetic-conflict','${conflict.second}',decode('00ff','hex'));`);
assert.notEqual(run(conflict).status, 0);
assert.equal(counts(conflict), "1:99");
assert.equal(sql(`select count(*) from public.spike_transactions where id='${conflict.first}';`), "0");
assert.ok(!journal(conflict).events.some((event) => event.stage === "load" && event.state === "completed"));
assert.equal(noteCount(conflict), "0");
const noteConflict = newRun();
sql(`insert into public.spike_projects(id,account_id,client_id,display_name,legacy_notes,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
 values ('${noteConflict.project}','account-primary','client-existing','Synthetic note conflict','Existing notes',now(),now(),1,1,'principal-owner');`);
assert.notEqual(run(noteConflict).status, 0);
assert.equal(counts(noteConflict), "0:0", "Conflicting legacy notes roll back provisional payments too");
assert.equal(noteCount(noteConflict), "0");
assert.equal(sql(`select legacy_notes from public.spike_projects where id='${noteConflict.project}';`), "Existing notes");
const denied = newRun();
assert.notEqual(run(denied, undefined, { ...process.env, DOCKER_HOST: "tcp://invalid.example:2375" }).status, 0);
assert.equal(counts(denied), "0:0");
// Produce valid terminal journal fixtures, including their canonical digests,
// so rejection must be the executable's terminal-state guard, not bad JSON/hash.
const canonical = (value) => JSON.stringify((function sorted(v) {
  if (Array.isArray(v)) return v.map(sorted);
  if (v && typeof v === "object") return Object.fromEntries(Object.keys(v).sort().map((key) => [key, sorted(v[key])]));
  return v;
})(value));
const sha = (value) => createHash("sha256").update(value).digest("hex");
for (const state of ["blocked", "failed"]) {
  const fixture = newRun();
  expectExit(run(fixture, "--interrupt-before-commit"), 86);
  const value = journal(fixture);
  const event = { ...value.events.at(-1), sequence: value.events.length + 1, state };
  delete event.eventDigest;
  event.eventDigest = sha(canonical(event));
  value.events.push(event);
  value.resumeFingerprint = sha(`migration-resume-v1\u001f${value.planDigest}\u001f${event.eventDigest}`);
  delete value.contentDigest;
  value.contentDigest = sha(canonical(value));
  writeFileSync(path.join(fixture.dir, "journal.json"), canonical(value));
  const result = run(fixture);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Terminal failed or blocked journal cannot resume/);
  assert.equal(counts(fixture), "0:0");
}
console.log("local-payment-import-recovery: real Swift process interruption before/after commit, immutable artifacts, completed replay, terminal-state rejection, atomic conflict and remote Docker denial passed");
