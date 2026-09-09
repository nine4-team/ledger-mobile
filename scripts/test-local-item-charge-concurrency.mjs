import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync, realpathSync } from 'node:fs';

// Only this generated database is mutated; the existing synthetic database is
// read by pg_dump, never migrated, reset, or used for these competing writers.
const root = realpathSync(new URL('..', import.meta.url).pathname);
assert.equal(root, process.env.GITHUB_ACTIONS === 'true'
  ? realpathSync(process.env.GITHUB_WORKSPACE) : '/Users/benjaminmackenzie/Dev/ledger_mobile_supabase');
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT, 'No Docker destination overrides');
assert.match(JSON.parse(execFileSync('docker', ['context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}'],
  { encoding: 'utf8', timeout: 10_000 })), /^unix:\/\//);
const container = 'supabase_db_ledger_target_supabase_local';
const labels = JSON.parse(execFileSync('docker', ['inspect', container, '--format', '{{json .Config.Labels}}'], { encoding: 'utf8' }));
assert.equal(labels['com.supabase.cli.project'], 'ledger_target_supabase_local');
assert.equal(realpathSync(labels['com.supabase.cli.workdir']), root);
const database = `ledger_charge_race_${randomUUID().replaceAll('-', '')}`;
assert.match(database, /^ledger_charge_race_[a-f0-9]{32}$/);
const sql = (input, db = database) => execFileSync('docker', ['exec', '-i', container, 'psql', '-X', '-qAt',
  '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'],
{ input, encoding: 'utf8', timeout: 15_000, stdio: ['pipe', 'pipe', 'pipe'] }).trim();
const sessions = new Set();
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
function session(label) {
  const child = spawn('docker', ['exec', '-i', container, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', database,
    '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'], { stdio: ['pipe', 'pipe', 'pipe'] });
  sessions.add(child);
  let out = '', err = '', exited = false;
  child.stdout.on('data', bytes => { out += bytes; });
  child.stderr.on('data', bytes => { err += bytes; });
  const closed = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', code => { exited = true; sessions.delete(child); resolve({ code, out, err }); });
  });
  child.stdin.write(`set application_name='${label}'; set statement_timeout='12s'; set idle_in_transaction_session_timeout='12s'; select pg_backend_pid();\n`);
  return { child, closed, async until(marker) {
    const deadline = Date.now() + 10_000;
    while (!out.includes(marker)) {
      assert.ok(!exited, `Session exited before ${marker}: ${err}`);
      assert.ok(Date.now() < deadline, `Timed out awaiting ${marker}: ${out} ${err}`);
      await pause(20);
    }
  } };
}
const source = name => `race-${name}`;
function prepare(name, withCharge = true) {
  const id = source(name);
  sql(`insert into public.spike_items(id,account_id,description,created_by_principal_id)
    values('${id}','account-primary','Synthetic race Item','principal-owner');
    insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
    values('${id}','account-primary','${id}','project','race-project','2026-01-01','principal-owner');
    ${withCharge ? insert(name) : ''}`);
}
function insert(name) {
  const id = source(name);
  return `insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
    amount_minor_units,currency,created_at,created_by_principal_id)
    values('${id}','account-primary','race-project','${id}','${id}','category-furnishings',12345,'USD','2026-01-01','principal-owner');`;
}
const edit = name => `update ledger_private.item_charge_occurrences set amount_minor_units=12346,revision=revision+1 where id='${source(name)}';`;
const withdraw = name => `update ledger_private.item_charge_occurrences set withdrawn_at='2026-02-01',withdrawn_by_principal_id='principal-owner',revision=revision+1 where id='${source(name)}';`;
function collect(name, amount = 12345, revision = 1) {
  const id = source(name);
  return `select ledger_private.import_client_payment('payment-${id}','account-primary','race-project','client-existing',
    ${amount},'USD','synthetic-charge-race','${id}','\\x01'::bytea);
    insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
    values('invoice-${id}','account-primary','race-project','client-existing','payment-${id}',1,'USD',${amount});
    insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
      source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
    values('line-${id}','account-primary','invoice-${id}',0,'USD','item','${id}','${id}',${revision},'category-furnishings',${amount},'Synthetic','{}');
    update ledger_private.collected_invoices set sealed=true where id='invoice-${id}'; set constraints all immediate;`;
}
async function race(name, holderSQL, waiterSQL, release, expectedCode) {
  const holderLabel = `charge_holder_${name}`, waiterLabel = `charge_waiter_${name}`;
  const holder = session(holderLabel), waiter = session(waiterLabel);
  try {
    holder.child.stdin.write(`begin; ${holderSQL} select 'HOLDER_READY';\n`);
    await holder.until('HOLDER_READY');
    waiter.child.stdin.end(`begin; ${waiterSQL} commit;\n`);
    const deadline = Date.now() + 8000;
    let observed = false;
    while (!observed && Date.now() < deadline) {
      observed = sql(`select exists(select 1 from pg_stat_activity w join pg_stat_activity h
        on h.pid=any(pg_blocking_pids(w.pid)) where w.datname='${database}' and h.datname='${database}'
        and w.application_name='${waiterLabel}' and h.application_name='${holderLabel}'
        and w.wait_event_type='Lock' and w.wait_event='advisory');`) === 't';
      if (!observed) await pause(25);
    }
    assert.ok(observed, `${name}: waiter never demonstrably blocked on holder's advisory lock`);
    holder.child.stdin.end(`${release};\n`);
    const [held, waited] = await Promise.all([holder.closed, waiter.closed]);
    assert.equal(held.code, 0, held.err);
    if (expectedCode) {
      assert.equal(waited.code, 3, `${name}: expected failure: ${waited.out} ${waited.err}`);
      assert.match(waited.err, new RegExp(`ERROR:  ${expectedCode}:`));
    } else assert.equal(waited.code, 0, `${name}: ${waited.err}`);
    console.log(`PASS ${name}: observed advisory wait; holder ${release}; waiter ${expectedCode ?? 'committed'}`);
  } finally {
    for (const s of [holder, waiter]) if (!s.child.stdin.destroyed && !s.child.stdin.writableEnded) s.child.stdin.end('rollback;\n');
    await Promise.allSettled([holder.closed, waiter.closed]);
  }
}
let created = false;
try {
  // Realtime's server-owned functions require administrative GUC privileges;
  // they are unrelated to this application's transactional tables/triggers.
  const dump = execFileSync('docker', ['exec', container, 'pg_dump', '-U', 'postgres', '-d', 'postgres', '-Fc',
    '--exclude-schema=realtime', '--exclude-schema=_realtime', '--exclude-table-data=vault.secrets'],
    { maxBuffer: 128 * 1024 * 1024, timeout: 30_000 });
  sql(`create database ${database};`, 'postgres'); created = true;
  execFileSync('docker', ['exec', '-i', container, 'pg_restore', '-U', 'postgres', '-d', database,
    '--no-owner', '--no-privileges', '--exit-on-error'], { input: dump, timeout: 30_000, maxBuffer: 4 * 1024 * 1024 });
  if (sql("select to_regclass('ledger_private.item_charge_occurrences') is null") === 't') {
    sql(`begin; ${readFileSync(`${root}/supabase/migrations/20260909060126_item_charge_occurrence_source.sql`, 'utf8')} commit;`);
  }
  assert.equal(sql("select to_regprocedure('ledger_private.lock_item_charge_source(text,text)') is not null and to_regprocedure('ledger_private.validate_collected_item_charge()') is not null"), 't');
  sql(`insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
    values('race-project','account-primary','client-existing','Synthetic concurrency',now(),now(),1,1,'principal-owner');`);
  prepare('correction-first');
  await race('correction-first', edit('correction-first'), collect('correction-first'), 'commit', '23514');
  assert.equal(sql("select revision||':'||amount_minor_units from ledger_private.item_charge_occurrences where id='race-correction-first'"), '2:12346');
  prepare('withdrawal-first');
  await race('withdrawal-first', withdraw('withdrawal-first'), collect('withdrawal-first'), 'commit', '23514');
  for (const action of ['edit', 'withdraw']) {
    prepare(`collection-first-${action}`);
    const name = `collection-first-${action}`;
    await race(name, collect(name), action === 'edit' ? edit(name) : withdraw(name), 'commit', '55000');
    assert.equal(sql(`select revision||':'||(withdrawn_at is null) from ledger_private.item_charge_occurrences where id='${source(name)}'`), '1:true');
  }
  prepare('missing-first', false);
  await race('missing-first', collect('missing-first'), insert('missing-first'), 'commit', '55000');
  assert.equal(sql("select count(*) from ledger_private.item_charge_occurrences where id='race-missing-first'"), '0');
  prepare('source-first', false);
  await race('source-first', insert('source-first') + edit('source-first'), collect('source-first', 12346, 2), 'commit');
  assert.equal(sql("select source_revision||':'||signed_amount_minor_units from ledger_private.collected_invoice_lines where source_id='race-source-first'"), '2:12346');
  prepare('source-first-stale', false);
  await race('source-first-stale', insert('source-first-stale') + edit('source-first-stale'), collect('source-first-stale'), 'commit', '23514');
  prepare('missing-rollback', false);
  await race('missing-rollback', collect('missing-rollback'), insert('missing-rollback'), 'rollback');
  assert.equal(sql("select count(*) from ledger_private.collected_invoice_lines where source_id='race-missing-rollback'"), '0');
  assert.equal(sql("select revision from ledger_private.item_charge_occurrences where id='race-missing-rollback'"), '1');
  prepare('rollback');
  await race('rollback', collect('rollback'), edit('rollback'), 'rollback');
  assert.equal(sql("select count(*) from ledger_private.collected_invoice_lines where source_id='race-rollback'"), '0');
  assert.equal(sql("select revision from ledger_private.item_charge_occurrences where id='race-rollback'"), '2');
  for (const isolation of ['repeatable read', 'serializable']) {
    for (const kind of ['insert', 'edit', 'collect']) {
      const name = `${isolation.replaceAll(' ', '-')}-${kind}`;
      prepare(name, kind !== 'insert');
      const statement = kind === 'insert' ? insert(name) : kind === 'edit' ? edit(name) : collect(name);
      assert.throws(() => sql(`begin isolation level ${isolation}; ${statement} commit;`),
        error => error.status === 3 && /ERROR:  25001:.*READ COMMITTED/.test(String(error.stderr)));
      console.log(`PASS ${isolation}: ${kind} rejected explicitly`);
    }
  }
  console.log('PASS 9 observed two-session races and 6 unsupported-isolation checks; no public writer or hosted behavior claimed.');
} finally {
  for (const child of sessions) if (!child.stdin.destroyed && !child.stdin.writableEnded) child.stdin.end('rollback;\n');
  if (created) {
    // Exact random database created above, never the source database or a glob.
    sql(`drop database ${database} with (force);`, 'postgres');
    console.log(`Removed owned disposable database ${database}; original database was not modified.`);
  }
}
