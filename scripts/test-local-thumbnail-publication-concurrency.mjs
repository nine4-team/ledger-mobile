import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { execFileSync, spawn } from "node:child_process";
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";

// Local metadata publication only: no Storage upload, hosted URL, supplied
// credentials, migration application, or immutable-evidence deletion bypass.
const context = "desktop-linux";
assert.equal(execFileSync("docker", ["context", "show"], { encoding: "utf8" }).trim(), context);
const contextInfo = JSON.parse(execFileSync("docker", ["context", "inspect", context], { encoding: "utf8" }));
assert.match(contextInfo[0].Endpoints.docker.Host, /^unix:\/\//, "Docker must use a local Unix socket");
const docker = ["--context", context];
const container = "supabase_db_ledger_target_supabase_local";
const labels = JSON.parse(execFileSync("docker", [...docker, "inspect", "--format", "{{json .Config.Labels}}", container], { encoding: "utf8" }));
const root = realpathSync(fileURLToPath(new URL("..", import.meta.url)));
assert.equal(realpathSync(process.cwd()), root, "Run from this Supabase worktree");
assert.equal(labels["com.supabase.cli.project"], "ledger_target_supabase_local");
assert.equal(realpathSync(labels["com.supabase.cli.workdir"]), root, "Container belongs to this exact worktree");
const args = [...docker, "exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-U", "postgres", "-d", "postgres",
  "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"];
const quote = (value) => `'${value.replaceAll("'", "''")}'`;
const live = new Set();
function query(sql) {
  return execFileSync("docker", args, { input: `set standard_conforming_strings=on;\n${sql}`,
    encoding: "utf8", timeout: 10_000 }).trim();
}
function session(sql, application, keepOpen = false) {
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
  const input = `set standard_conforming_strings=on; set application_name=${quote(application)};
    set statement_timeout='15s'; set idle_in_transaction_session_timeout='15s';\n${sql}`;
  if (keepOpen) child.stdin.write(input); else child.stdin.end(input);
  return { child, done, output: () => out };
}
async function until(check, description) {
  const deadline = Date.now() + 8_000;
  while (!check()) {
    assert.ok(Date.now() < deadline, `Timed out: ${description}`);
    await delay(25);
  }
}

const suffix = randomUUID();
const prefix = `thumbnail-race-${suffix}`;
const originalHash = "a".repeat(64), derivativeHash = "b".repeat(64);
const path = (id, hash) => `accounts/account-primary/attachments/${id}/${hash}`;
// Preflight before retaining any synthetic records.
assert.equal(query(`select count(*) from pg_proc where oid=to_regprocedure(
  'ledger_private.publish_item_card_thumbnail(text,text,text,bigint,text,text,text,text,bigint,text,text,text,text,integer,integer)');`), "1",
"Apply the trusted publisher migration locally before this test");
assert.equal(query("select count(*) from public.spike_accounts where id='account-primary';"), "1");
console.log(`Retained synthetic metadata prefix: ${prefix}`);

try {
  for (const mode of ["identical", "derivative-conflict", "dimension-conflict", "rollback"]) {
    const original = `${prefix}-${mode}-original`;
    const winner = `${prefix}-${mode}-small`;
    const loser = `${prefix}-${mode}-loser`;
    const link = `${prefix}-${mode}-link`;
    const waiter = `thumb-${suffix}-${mode}`.slice(0, 63);
    query(`insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
      values(${quote(original)},'account-primary',${quote(originalHash)},123,'image/jpeg',${quote(path(original, originalHash))});`);
    const call = (id = winner, width = 300) => `select ledger_private.publish_item_card_thumbnail(
      'account-primary',${quote(original)},${quote(originalHash)},123,'image/jpeg',${quote(path(original, originalHash))},
      ${quote(id)},${quote(derivativeHash)},321,'image/jpeg',${quote(path(id, derivativeHash))},
      ${quote(link)},'item-card-300-jpeg-v1',${width},200);`;
    const originalBefore = query(`select to_jsonb(o)::text from public.item_image_objects o where id=${quote(original)};`);
    const first = session(`begin; ${call()} select 'HOLDING_THUMBNAIL';\n`, `holder-${suffix}-${mode}`.slice(0, 63), true);
    await until(() => first.output().includes("HOLDING_THUMBNAIL"), "first publication holds original lock");
    const second = session(call(mode === "derivative-conflict" ? loser : winner, mode === "dimension-conflict" ? 299 : 300), waiter);
    // Assert a real database lock wait on this test's holder, not merely elapsed
    // time or a worker that has not started yet.
    await until(() => query(`select count(*) from pg_stat_activity a
      where a.application_name=${quote(waiter)} and a.wait_event_type='Lock'
      and exists(select 1 from pg_stat_activity h where h.pid=any(pg_blocking_pids(a.pid))
        and h.application_name=${quote(`holder-${suffix}-${mode}`.slice(0, 63))});`) === "1",
    "second publication is blocked by our first transaction");
    first.child.stdin.end(mode === "rollback" ? "rollback;\n" : "commit;\n");
    const firstResult = await first.done;
    assert.equal(firstResult.code, 0, firstResult.error);
    const secondResult = await second.done;
    if (mode === "identical" || mode === "rollback") {
      assert.equal(secondResult.code, 0, secondResult.error);
      assert.equal(secondResult.out.trim(), link, "Replay/retry returns exact link identity");
    } else {
      assert.notEqual(secondResult.code, 0, "Conflicting publication must fail");
      assert.match(secondResult.error, /22000/, secondResult.error);
    }
    // New sessions inspect committed state; the losing session's own readback
    // cannot prove atomic publication or absence of orphan metadata.
    const published = JSON.parse(query(`select json_build_array(t.id,t.original_attachment_id,t.thumbnail_attachment_id,
      t.recipe,t.pixel_width,t.pixel_height,o.content_sha256,o.byte_count,o.media_type,o.storage_path)
      from public.item_card_thumbnails t join public.item_image_objects o
        on o.account_id=t.account_id and o.id=t.thumbnail_attachment_id where t.id=${quote(link)};`));
    assert.deepEqual(published, [link, original, winner, "item-card-300-jpeg-v1", 300, 200,
      derivativeHash, 321, "image/jpeg", path(winner, derivativeHash)]);
    assert.equal(query(`select count(*) from public.item_card_thumbnails where account_id='account-primary'
      and original_attachment_id=${quote(original)};`), "1");
    assert.equal(query(`select count(*) from public.item_image_objects where id in (${quote(winner)},${quote(loser)});`), "1",
      "Exactly one derivative, no losing orphan");
    assert.equal(query(`select count(*) from public.item_image_objects where id=${quote(loser)};`), "0");
    assert.equal(query(`select to_jsonb(o)::text from public.item_image_objects o where id=${quote(original)};`), originalBefore,
      "Original metadata never changes");
    assert.equal(query(call()), link, "Fresh-client exact replay converges after every race");
    console.log(`PASS ${mode}: observed holder lock, committed exact pair, no loser orphan`);
  }
  assert.equal(query(`select count(*) from public.item_image_objects where starts_with(id,${quote(prefix)});`), "8");
  assert.equal(query(`select count(*) from public.item_card_thumbnails where starts_with(id,${quote(prefix)});`), "4");
  assert.equal(query(`select count(*) from storage.objects where starts_with(name,${quote(`accounts/account-primary/attachments/${prefix}`)});`), "0",
    "Metadata concurrency tests must not manufacture uploaded-byte evidence");
  console.log(`local-thumbnail-publication-concurrency: 4 observed lock races passed; retained 8 objects + 4 links under ${prefix}; no Storage objects`);
} finally {
  for (const child of live) {
    child.stdin.destroy();
    child.kill("SIGTERM");
  }
}
