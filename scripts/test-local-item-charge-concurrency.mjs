import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync, readdirSync, realpathSync } from 'node:fs';

// Only this generated database is mutated. Copy schema, not local user/test data;
// the committed synthetic seed supplies the race's independent prerequisites.
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
        and w.wait_event_type='Lock' and w.wait_event in ('advisory','transactionid','tuple'));`) === 't';
      if (!observed) await pause(25);
    }
    assert.ok(observed, `${name}: waiter never demonstrably blocked on holder's lock`);
    holder.child.stdin.end(`${release};\n`);
    const [held, waited] = await Promise.all([holder.closed, waiter.closed]);
    assert.equal(held.code, 0, held.err);
    if (expectedCode) {
      assert.equal(waited.code, 3, `${name}: expected failure: ${waited.out} ${waited.err}`);
      assert.match(waited.err, new RegExp(`ERROR:  ${expectedCode}:`));
    } else assert.equal(waited.code, 0, `${name}: ${waited.err}`);
    console.log(`PASS ${name}: observed holder lock wait; holder ${release}; waiter ${expectedCode ?? 'committed'}`);
  } finally {
    for (const s of [holder, waiter]) if (!s.child.stdin.destroyed && !s.child.stdin.writableEnded) s.child.stdin.end('rollback;\n');
    await Promise.allSettled([holder.closed, waiter.closed]);
  }
}
function prepareExpense(name) {
  sql(`insert into ledger_private.expenses(id,account_id,project_id,category_id,vendor,expense_date,
    final_amount_minor_units,currency,notes,created_at,created_by_principal_id)
    values('${source(name)}','account-primary','race-project','category-system','Synthetic','2026-01-01',
      12345,'USD','',now(),'principal-owner');`);
}
const editExpense = name => `update ledger_private.expenses set final_amount_minor_units=12346,revision=revision+1 where id='${source(name)}';`;
function reserveExpenseReceipt(name) {
  return `set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
    select public.spike_begin_expense_attachment_upload('receipt-${source(name)}','account-primary',
      'race-project','${source(name)}',repeat('a',64),12,'application/pdf','Receipt.pdf');
    reset role;`;
}
function prepareVerifiedExpenseReceipt(name) {
  prepareExpense(name);
  sql(`begin; ${reserveExpenseReceipt(name)} commit;
    insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
    select id,account_id,content_sha256,byte_count,media_type,storage_path
    from ledger_private.expense_attachment_uploads where id='receipt-${source(name)}';`);
}
function linkExpenseReceipt(name) {
  const command = JSON.stringify({ operationId: `edit-${source(name)}`, accountId: 'account-primary',
    actorPrincipalId: 'principal-owner', projectId: 'race-project', expenseId: source(name),
    contractVersion: 'expense-edit-v1', createdAtMs: '1000', vendor: 'Synthetic', date: '2026-01-01',
    amountMinorUnits: '12345', currency: 'USD', categoryId: 'category-system', notes: '',
    receiptLines: [], receiptAttachmentIds: [`receipt-${source(name)}`], expectedRevision: '1' });
  return `set local role authenticated;
    select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
    select public.spike_edit_expense('${command}'); reset role;`;
}
function createInvoice(name, suffix) {
  const command = JSON.stringify({ operationId: `invoice-${source(name)}-${suffix}`, accountId: 'account-primary',
    actorPrincipalId: 'principal-owner', projectId: 'race-project', clientId: 'client-existing',
    invoiceId: `invoice-${source(name)}-${suffix}`, contractVersion: 'invoice-create-v1', createdAtMs: '1000',
    name: 'Synthetic race Invoice', notes: '', sources: [{kind: 'expense', sourceId: source(name),
      expectedRevision: '1', amountMinorUnits: '12345', currency: 'USD'}] });
  // Private handler until the full source set and endpoint are implemented.
  return `select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
    select ledger_private.create_live_invoice('${command}');`;
}
function reviseInvoice(name, suffix) {
  const command = JSON.stringify({ operationId: `revision-${source(name)}-${suffix}`, accountId: 'account-primary',
    actorPrincipalId: 'principal-owner', projectId: 'race-project', clientId: 'client-existing',
    invoiceId: `invoice-${source(name)}-initial`, contractVersion: 'invoice-revise-created-v1',
    expectedRevision: '1', createdAtMs: '1000', name: `Edited ${suffix}`, notes: '',
    sources: [{ kind: 'expense', sourceId: source(name), expectedRevision: '1', amountMinorUnits: '12345', currency: 'USD' }] });
  return `select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
    select ledger_private.revise_created_invoice('${command}');`;
}
function collectExpense(name, kind = 'expense', category = 'category-system') {
  const id = source(name);
  return `select ledger_private.import_client_payment('payment-${id}','account-primary','race-project','client-existing',
    12345,'USD','synthetic-expense-race','${id}','\\x01'::bytea);
    insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
    values('invoice-${id}','account-primary','race-project','client-existing','payment-${id}',1,'USD',12345);
    insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,
      source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
    values('line-${id}','account-primary','invoice-${id}',0,'USD','${kind}','${id}',1,'${category}',12345,'Synthetic','{}');
    update ledger_private.collected_invoices set sealed=true where id='invoice-${id}'; set constraints all immediate;`;
}
let created = false;
try {
  // Realtime's server-owned functions require administrative GUC privileges;
  // they are unrelated to this application's transactional tables/triggers.
  const dump = execFileSync('docker', ['exec', container, 'pg_dump', '-U', 'postgres', '-d', 'postgres', '-Fc', '--schema-only',
    '--exclude-schema=realtime', '--exclude-schema=_realtime', '--exclude-table-data=vault.secrets'],
    { maxBuffer: 128 * 1024 * 1024, timeout: 30_000 });
  sql(`create database ${database};`, 'postgres'); created = true;
  execFileSync('docker', ['exec', '-i', container, 'pg_restore', '-U', 'postgres', '-d', database,
    '--no-owner', '--no-privileges', '--exit-on-error'], { input: dump, timeout: 30_000, maxBuffer: 4 * 1024 * 1024 });
  // Replay is now required: authenticated receipt races need the actual Ledger
  // grants, while platform extension ACLs cannot be restored by local postgres.
  // The previous --replay-migrations invocation remains compatible.
  {
    // Retain the schema-only Supabase platform, but remove every Ledger object.
    // This is only the generated disposable database, never the working database.
    sql(`drop schema ledger_private cascade; drop schema public cascade;
      create schema public authorization pg_database_owner;
      grant usage on schema public to postgres,anon,authenticated,service_role;
      grant all on schema public to postgres,service_role;`);
    const migrations = readdirSync(`${root}/supabase/migrations`).filter(name => name.endsWith('.sql')).sort();
    assert.ok(migrations.length > 0);
    sql(migrations.map(name => readFileSync(`${root}/supabase/migrations/${name}`, 'utf8')).join('\n'));
    console.log(`Replayed ${migrations.length} Ledger migrations on empty application schemas; Supabase platform schema retained, no source records copied.`);
  }
  sql(readFileSync(`${root}/supabase/seed.sql`, 'utf8'));
  if (sql("select to_regclass('ledger_private.item_charge_occurrences') is null") === 't') {
    sql(`begin; ${readFileSync(`${root}/supabase/migrations/20260909060126_item_charge_occurrence_source.sql`, 'utf8')} commit;`);
  }
  assert.equal(sql("select to_regprocedure('ledger_private.lock_item_charge_source(text,text)') is not null and to_regprocedure('ledger_private.validate_collected_item_charge()') is not null"), 't');
  sql(`insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
    values('race-project','account-primary','client-existing','Synthetic concurrency',now(),now(),1,1,'principal-owner');`);
  prepare('correction-first');
  for (const scenario of ['exact', 'changed', 'rollback']) {
    const id = `mixed-import-${scenario}`;
    sql(`select ledger_private.import_client_payment('${id}-payment','account-primary','race-project','client-existing',
      100,'USD','source-account','${id}-source-payment','\\x00ff');`);
    const importMixed = (label = 'Fee') => {
      const lines = ['fee', 'expense'].map((kind, position) => ({
        id: `${id}-${kind}-line`, line_position: position, source_kind: kind === 'fee' ? 'fee_installment' : 'expense',
        source_id: `${id}-${kind}`, item_id: null, source_revision: '1',
        category_id: kind === 'fee' ? 'category-design-fee' : 'category-system', signed_amount_minor_units: '50',
        description: kind, source_snapshot_json: JSON.stringify(kind === 'fee'
          ? { feeInstallment: { installmentId: `${id}-fee` } } : { expense: { expenseId: `${id}-expense` } })
      }));
      const invoice = { invoice_id: `${id}-invoice`, invoice_revision: '1', account_id: 'account-primary',
        project_id: 'race-project', client_id: 'client-existing', purchase_id: `${id}-payment`, currency: 'USD',
        total_minor_units: '100', lines };
      const common = { account_id: 'account-primary', project_id: 'race-project', currency: 'USD', revision: '1',
        created_at: null, created_by_principal_id: null };
      const sources = [
        { source_document_id: `${id}-fee-source`, source_project_id: 'source-project', source_bytes: '\\x01ff',
          record: { ...common, id: `${id}-fee`, category_id: 'category-design-fee', label, amount_minor_units: '50' } },
        { source_document_id: `${id}-expense-source`, source_bytes: '\\x02ff', record: { ...common,
          id: `${id}-expense`, category_id: 'category-system', vendor: 'Vendor', expense_date: '2024-02-29',
          final_amount_minor_units: '50', notes: '' } }
      ];
      const payment = { p_id: `${id}-payment`, p_account_id: 'account-primary', p_project_id: 'race-project',
        p_client_id: 'client-existing', p_amount: '100', p_currency: 'USD', p_source_account: 'source-account',
        p_source_document: `${id}-source-payment`, p_source_bytes: '\\x00ff' };
      return `select ledger_private.import_invoice_sources('${JSON.stringify(invoice)}','${JSON.stringify(sources)}',
        '${JSON.stringify(payment)}','source-account','${id}-source-invoice','\\x03ff');`;
    };
    await race(id, importMixed(), importMixed(scenario === 'changed' ? 'Changed' : 'Fee'),
      scenario === 'rollback' ? 'rollback' : 'commit', scenario === 'changed' ? '22000' : undefined);
    assert.equal(sql(`select count(*) from ledger_private.collected_invoice_lines where invoice_id='${id}-invoice'`), '2');
    assert.equal(sql(`select label from ledger_private.fee_installments where id='${id}-fee'`), 'Fee');
    assert.equal(sql(`select count(*) from ledger_private.imported_fee_sources where fee_id='${id}-fee'`), '1');
  }
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
  for (const name of ['expense-edit-first', 'expense-collection-first', 'expense-rollback']) prepareExpense(name);
  await race('expense-edit-first', editExpense('expense-edit-first'), collectExpense('expense-edit-first'), 'commit', '23514');
  assert.equal(sql("select revision||':'||final_amount_minor_units from ledger_private.expenses where id='race-expense-edit-first'"), '2:12346');
  assert.equal(sql("select count(*) from ledger_private.collected_invoices where id='invoice-race-expense-edit-first'"), '0');
  await race('expense-collection-first', collectExpense('expense-collection-first'), editExpense('expense-collection-first'), 'commit', '23514');
  assert.equal(sql("select revision||':'||final_amount_minor_units from ledger_private.expenses where id='race-expense-collection-first'"), '1:12345');
  await race('expense-rollback', collectExpense('expense-rollback'), editExpense('expense-rollback'), 'rollback');
  assert.equal(sql("select revision from ledger_private.expenses where id='race-expense-rollback'"), '2');
  console.log('PASS 3 observed Expense edit/collection races; rollback releases the source without a paid lock.');
  for (const name of ['receipt-collection-first', 'receipt-reservation-first', 'receipt-collection-rollback']) prepareExpense(name);
  await race('receipt-collection-first', collectExpense('receipt-collection-first'),
    reserveExpenseReceipt('receipt-collection-first'), 'commit', '42501');
  assert.equal(sql("select count(*) from ledger_private.expense_attachment_uploads where expense_id='race-receipt-collection-first'"), '0');
  await race('receipt-reservation-first', reserveExpenseReceipt('receipt-reservation-first'),
    collectExpense('receipt-reservation-first'), 'commit');
  assert.equal(sql("select revision||':'||final_amount_minor_units from ledger_private.expenses where id='race-receipt-reservation-first'"), '1:12345');
  assert.equal(sql("select count(*) from ledger_private.expense_attachment_uploads where expense_id='race-receipt-reservation-first'"), '1');
  // Exact retry may recover an already-reserved upload, but never adds a paid reference.
  sql(`begin; ${reserveExpenseReceipt('receipt-reservation-first')} commit;`);
  assert.equal(sql("select count(*) from ledger_private.expense_receipt_attachments where expense_id='race-receipt-reservation-first'"), '0');
  await race('receipt-collection-rollback', collectExpense('receipt-collection-rollback'),
    reserveExpenseReceipt('receipt-collection-rollback'), 'rollback');
  assert.equal(sql("select count(*) from ledger_private.expense_attachment_uploads where expense_id='race-receipt-collection-rollback'"), '1');
  console.log('PASS 3 observed receipt-reservation/collection races; reservations do not mutate paid receipt references.');
  for (const name of ['receipt-link-first', 'receipt-link-paid', 'receipt-link-rollback']) prepareVerifiedExpenseReceipt(name);
  await race('receipt-link-first', linkExpenseReceipt('receipt-link-first'), collectExpense('receipt-link-first'), 'commit', '23514');
  assert.equal(sql("select phase from public.spike_operation_results where operation_id='edit-race-receipt-link-first'"), 'applied');
  assert.equal(sql("select count(*) from ledger_private.expense_receipt_attachments where expense_id='race-receipt-link-first'"), '1');
  await race('receipt-link-paid', collectExpense('receipt-link-paid'), linkExpenseReceipt('receipt-link-paid'), 'commit');
  assert.equal(sql("select phase||':'||error_code from public.spike_operation_results where operation_id='edit-race-receipt-link-paid'"), 'rejected:expense_collected');
  assert.equal(sql("select count(*) from ledger_private.expense_receipt_attachments where expense_id='race-receipt-link-paid'"), '0');
  await race('receipt-link-rollback', collectExpense('receipt-link-rollback'), linkExpenseReceipt('receipt-link-rollback'), 'rollback');
  assert.equal(sql("select phase from public.spike_operation_results where operation_id='edit-race-receipt-link-rollback'"), 'applied');
  assert.equal(sql("select count(*) from ledger_private.expense_receipt_attachments where expense_id='race-receipt-link-rollback'"), '1');
  console.log('PASS 3 observed verified-receipt edit RPC/collection races; synthetic verified objects, no Storage upload claim.');
  for (const name of ['invoice-compete','invoice-rollback','invoice-source-edit','invoice-source-paid']) prepareExpense(name);
  await race('invoice-compete', createInvoice('invoice-compete','first'), createInvoice('invoice-compete','second'), 'commit');
  assert.equal(sql("select phase||':'||error_code from public.spike_operation_results where operation_id='invoice-race-invoice-compete-second'"), 'rejected:invoice_source_reserved');
  assert.equal(sql("select count(*) from ledger_private.live_invoice_memberships where source_id='race-invoice-compete'"), '1');
  await race('invoice-rollback', createInvoice('invoice-rollback','first'), createInvoice('invoice-rollback','second'), 'rollback');
  assert.equal(sql("select phase from public.spike_operation_results where operation_id='invoice-race-invoice-rollback-second'"), 'applied');
  await race('invoice-source-edit', editExpense('invoice-source-edit'), createInvoice('invoice-source-edit','first'), 'commit');
  assert.equal(sql("select error_code from public.spike_operation_results where operation_id='invoice-race-invoice-source-edit-first'"), 'invoice_source_changed');
  await race('invoice-source-paid', collectExpense('invoice-source-paid'), createInvoice('invoice-source-paid','first'), 'commit');
  assert.equal(sql("select error_code from public.spike_operation_results where operation_id='invoice-race-invoice-source-paid-first'"), 'invoice_source_collected');
  console.log('PASS 4 observed live Invoice creation/source races; private handler, not public endpoint proof.');
  for (const name of ['revision-compete', 'revision-rollback', 'revision-source-edit']) {
    prepareExpense(name);
    sql(`begin; ${createInvoice(name, 'initial')} commit;`);
  }
  await race('revision-compete', reviseInvoice('revision-compete', 'first'), reviseInvoice('revision-compete', 'second'), 'commit');
  assert.equal(sql("select phase||':'||error_code from public.spike_operation_results where operation_id='revision-race-revision-compete-second'"), 'rejected:invoice_revision_conflict');
  await race('revision-rollback', reviseInvoice('revision-rollback', 'first'), reviseInvoice('revision-rollback', 'second'), 'rollback');
  assert.equal(sql("select phase from public.spike_operation_results where operation_id='revision-race-revision-rollback-second'"), 'applied');
  assert.equal(sql("select count(*) from public.spike_operation_results where operation_id='revision-race-revision-rollback-first'"), '0');
  for (const name of ['revision-compete', 'revision-rollback']) {
    assert.equal(sql(`select revision from ledger_private.live_invoices where id='invoice-${source(name)}-initial'`), '2');
    assert.equal(sql(`select count(*)||':'||count(*) filter(where released_at is null) from ledger_private.live_invoice_memberships where invoice_id='invoice-${source(name)}-initial'`), '2:1');
  }
  await race('revision-source-edit', editExpense('revision-source-edit'), reviseInvoice('revision-source-edit', 'first'), 'commit');
  assert.equal(sql("select error_code from public.spike_operation_results where operation_id='revision-race-revision-source-edit-first'"), 'invoice_source_changed');
  assert.equal(sql("select revision from ledger_private.live_invoices where id='invoice-race-revision-source-edit-initial'"), '1');
  console.log('PASS created Invoice competing edits, rollback and source-change races; no lost update or partial history.');
  for (const name of ['fee-edit-first','fee-paid-first','fee-paid-rollback']) {
    sql(`insert into ledger_private.fee_installments(id,account_id,project_id,category_id,label,amount_minor_units,currency,created_at,created_by_principal_id)
      values('${source(name)}','account-primary','race-project','category-design-fee','Design fee',12345,'USD',now(),'principal-owner');`);
  }
  const editFee = name => `update ledger_private.fee_installments set amount_minor_units=12346,revision=2 where id='${source(name)}';`;
  const collectFee = name => collectExpense(name, 'fee_installment', 'category-design-fee');
  await race('fee-edit-first', editFee('fee-edit-first'), collectFee('fee-edit-first'), 'commit', '23514');
  await race('fee-paid-first', collectFee('fee-paid-first'), editFee('fee-paid-first'), 'commit', '23514');
  assert.equal(sql("select amount_minor_units from ledger_private.fee_installments where id='race-fee-paid-first'"), '12345');
  await race('fee-paid-rollback', collectFee('fee-paid-rollback'), editFee('fee-paid-rollback'), 'rollback');
  assert.equal(sql("select revision from ledger_private.fee_installments where id='race-fee-paid-rollback'"), '2');
  console.log('PASS 3 observed Fee edit/collection races; no user-facing Fee writer claimed.');
  sql(`insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
    values('fee-cap-race','account-primary','client-existing','Fee cap race',now(),now(),1,1,'principal-owner');
    insert into public.spike_project_category_allocations(id,account_id,project_id,category_id,allocation_minor_units,allocation_currency,
      created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
    values('fee-cap-race','account-primary','fee-cap-race','category-design-fee',100,'USD',now(),now(),1,1,'principal-owner');`);
  const createFee = id => {
    const command = JSON.stringify({ operationId: id, accountId: 'account-primary', actorPrincipalId: 'principal-owner',
      projectId: 'fee-cap-race', installmentId: id, categoryId: 'category-design-fee',
      contractVersion: 'fee-installment-create-v1', createdAtMs: '1000', label: 'Design fee',
      amountMinorUnits: '60', currency: 'USD', sortOrder: '' });
    return `select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
      select (ledger_private.create_fee_installment('${command}')).phase;`;
  };
  await race('fee-cap-creators', createFee('fee-cap-first'), createFee('fee-cap-second'), 'commit');
  assert.equal(sql("select phase || ':' || error_code from public.spike_operation_results where operation_id='fee-cap-second'"),
    'rejected:fee_total_exceeded');
  assert.equal(sql("select sum(amount_minor_units) from ledger_private.fee_installments where project_id='fee-cap-race'"), '60');
  console.log('PASS competing Fee creators cannot jointly exceed configured total');
} finally {
  for (const child of sessions) if (!child.stdin.destroyed && !child.stdin.writableEnded) child.stdin.end('rollback;\n');
  if (created) {
    // Exact random database created above, never the source database or a glob.
    sql(`drop database ${database} with (force);`, 'postgres');
    console.log(`Removed owned disposable database ${database}; original database was not modified.`);
  }
}
