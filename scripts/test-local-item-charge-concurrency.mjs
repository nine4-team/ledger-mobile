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
  if (!process.argv.includes('--adjustments-only')) {
  prepare('correction-first');
  for (const scenario of ['exact', 'changed', 'rollback']) {
    const id = `mixed-import-${scenario}`;
    sql(`insert into public.spike_items(id,account_id,description,created_by_principal_id)
      values('${id}-item','account-primary','Current Item','principal-owner');`);
    sql(`select ledger_private.import_client_payment('${id}-payment','account-primary','race-project','client-existing',
      150,'USD','source-account','${id}-source-payment','\\x00ff');`);
    const importMixed = (label = 'Fee') => {
      const lines = ['fee', 'expense'].map((kind, position) => ({
        id: `${id}-${kind}-line`, line_position: position, source_kind: kind === 'fee' ? 'fee_installment' : 'expense',
        source_id: `${id}-${kind}`, item_id: null, source_revision: '1',
        category_id: kind === 'fee' ? 'category-design-fee' : 'category-system', signed_amount_minor_units: '50',
        description: kind, source_snapshot_json: JSON.stringify(kind === 'fee'
          ? { feeInstallment: { installmentId: `${id}-fee` } } : { expense: { expenseId: `${id}-expense` } })
      }));
      lines.push({ id: `${id}-item-line`, line_position: 2, source_kind: 'item', source_id: `${id}-occurrence`,
        item_id: `${id}-item`, source_revision: '1', category_id: 'furnishings', signed_amount_minor_units: '50',
        description: 'Historical Item', source_snapshot_json: JSON.stringify({ item: { itemId: `${id}-item`,
          occurrenceId: `${id}-occurrence`, price: { basis: { importedInvoiceAmount: {} }, amount: { minorUnits: 50, currency: 'USD' } } } }) });
      const invoice = { invoice_id: `${id}-invoice`, invoice_revision: '1', account_id: 'account-primary',
        project_id: 'race-project', client_id: 'client-existing', purchase_id: `${id}-payment`, currency: 'USD',
        total_minor_units: '150', lines };
      const common = { account_id: 'account-primary', project_id: 'race-project', currency: 'USD', revision: '1',
        created_at: null, created_by_principal_id: null };
      const sources = [
        { source_document_id: `${id}-fee-source`, source_project_id: 'source-project', source_bytes: '\\x01ff',
          record: { ...common, id: `${id}-fee`, category_id: 'category-design-fee', label, amount_minor_units: '50' } },
        { source_document_id: `${id}-expense-source`, source_bytes: '\\x02ff', record: { ...common,
          id: `${id}-expense`, category_id: 'category-system', vendor: 'Vendor', expense_date: '2024-02-29',
          final_amount_minor_units: '50', notes: '' } }
      ];
      sources.push({ source_document_id: `${id}-source-item`, source_line_id: `${id}-source-line`,
        source_bytes: '\\x04ff', line_source_bytes: '\\x05ff' });
      const payment = { p_id: `${id}-payment`, p_account_id: 'account-primary', p_project_id: 'race-project',
        p_client_id: 'client-existing', p_amount: '150', p_currency: 'USD', p_source_account: 'source-account',
        p_source_document: `${id}-source-payment`, p_source_bytes: '\\x00ff' };
      return `select ledger_private.import_invoice_sources('${JSON.stringify(invoice)}','${JSON.stringify(sources)}',
        '${JSON.stringify(payment)}','source-account','${id}-source-invoice','\\x03ff');`;
    };
    await race(id, importMixed(), importMixed(scenario === 'changed' ? 'Changed' : 'Fee'),
      scenario === 'rollback' ? 'rollback' : 'commit', scenario === 'changed' ? '22000' : undefined);
    assert.equal(sql(`select count(*) from ledger_private.collected_invoice_lines where invoice_id='${id}-invoice'`), '3');
    assert.equal(sql(`select count(*) from ledger_private.imported_item_invoice_sources where line_id='${id}-item-line'`), '1');
    assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where item_id='${id}-item'`), '0');
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
  const priceEdit = (name, amount='12346') => {
    const id=source(name);
    const command=JSON.stringify({operationId:'edit-'+id,accountId:'account-primary',actorPrincipalId:'principal-owner',
      projectId:'race-project',itemId:id,placementId:id,occurrenceId:id,
      contractVersion:'item-uncollected-price-edit-v1',createdAtMs:'1000',expectedPriceRevision:'0',
      expectedChargeRevision:'1',requestedPriceMinorUnits:amount,reviewedPriceMinorUnits:amount,currency:'USD'});
    return `select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
      select (ledger_private.edit_uncollected_item_price('${command}')).phase;`;
  };
  for(const name of ['price-first','price-paid-first','price-paid-rollback']) prepare(name);
  await race('price-first',priceEdit('price-first'),collect('price-first'),'commit','23514');
  assert.equal(sql("select amount_minor_units from ledger_private.item_project_prices where item_id='race-price-first'"),'12346');
  await race('price-paid-first',collect('price-paid-first'),priceEdit('price-paid-first'),'commit');
  assert.equal(sql("select phase||':'||error_code from public.spike_operation_results where operation_id='edit-race-price-paid-first'"),
    'rejected:price_charge_collected');
  assert.equal(sql("select count(*) from ledger_private.item_project_prices where item_id='race-price-paid-first'"),'0');
  await race('price-paid-rollback',collect('price-paid-rollback'),priceEdit('price-paid-rollback'),'rollback');
  assert.equal(sql("select phase from public.spike_operation_results where operation_id='edit-race-price-paid-rollback'"),'applied');
  console.log('PASS 3 price-command/collection races, including collection rollback');
  for (const name of ['inventory-cost-change','inventory-access-change']) {
    const id=source(name);
    sql(`insert into public.spike_items(id,account_id,description,created_by_principal_id)
      values('${id}','account-primary','Inventory price race','principal-owner');
      insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
      values('${id}','account-primary','${id}','business_inventory','2026-01-01','principal-owner');`);
  }
  const inventoryEdit = name => {
    const id=source(name);
    const command=JSON.stringify({operationId:'edit-'+id,accountId:'account-primary',actorPrincipalId:'principal-owner',
      itemId:id,placementId:id,contractVersion:'item-inventory-price-edit-v2',createdAtMs:'1000',
      expectedPriceRevision:'0',requestedPriceMinorUnits:'100',reviewedPriceMinorUnits:'100',currency:'USD',clearPrice:'false'});
    return `set local role authenticated;
      select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
      select (public.spike_edit_uncollected_item_price('${command}')).phase;`;
  };
  sql(`insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
    values('inventory-price-cost','account-primary',150,'USD','purchase','vendor_payment','business_inventory','category-furnishings');`);
  await race('inventory-cost-change', `insert into public.transaction_receipt_items
    (id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
    values('inventory-price-cost-line','account-primary','inventory-price-cost','race-inventory-cost-change','USD',150,'linked');`,
    inventoryEdit('inventory-cost-change'),'commit');
  assert.equal(sql("select phase||':'||error_code from public.spike_operation_results where operation_id='edit-race-inventory-cost-change'"),
    'rejected:price_review_stale');
  assert.equal(sql("select count(*) from ledger_private.item_project_prices where item_id='race-inventory-cost-change'"),'0');
  await race('inventory-access-change', `update public.spike_account_memberships set financial_access='none'
    where account_id='account-primary' and principal_id='principal-owner';`,
    inventoryEdit('inventory-access-change'),'commit','42501');
  assert.equal(sql("select count(*) from public.spike_operation_results where operation_id='edit-race-inventory-access-change'"),'0');
  sql("update public.spike_account_memberships set financial_access='full' where account_id='account-primary' and principal_id='principal-owner';");
  console.log('PASS Inventory edit rechecks committed acquisition cost and access revocation after lock waits');
  for(const [name,expenseFirst,release] of [['total-price-first',false,'commit'],['total-expense-first',true,'commit'],['total-rollback',false,'rollback']]) {
    prepare(name); prepareExpense(name);
    const id=source(name), invoice='live-'+id;
    sql(`insert into ledger_private.live_invoices(id,account_id,project_id,name,status,created_at,created_by_principal_id)
      values('${invoice}','account-primary','race-project','Concurrent sources','created',now(),'principal-owner');
      insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
      values('account-primary','${invoice}','item','${id}',0),('account-primary','${invoice}','expense','${id}',1);`);
    const command=JSON.stringify({operationId:'expense-'+id,accountId:'account-primary',actorPrincipalId:'principal-owner',
      projectId:'race-project',expenseId:id,contractVersion:'expense-edit-v1',createdAtMs:'1000',vendor:'Synthetic',
      date:'2026-01-01',amountMinorUnits:'12346',currency:'USD',categoryId:'category-system',notes:'',
      receiptLines:[],receiptAttachmentIds:[],expectedRevision:'1'});
    const expense=`select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
      select (ledger_private.edit_expense('${command}')).phase;`;
    const price=priceEdit(name,'9223372036854763462'); // Int64.max minus original Expense12345.
    await race(name,expenseFirst?expense:price,expenseFirst?price:expense,release);
    const waiterOperation=expenseFirst?'edit-'+id:'expense-'+id;
    assert.equal(sql(`select phase from public.spike_operation_results where operation_id='${waiterOperation}'`),
      release==='rollback'?'applied':'rejected');
    const total=sql(`select c.amount_minor_units::numeric+e.final_amount_minor_units::numeric
      from ledger_private.item_charge_occurrences c join ledger_private.expenses e on e.id=c.id where c.id='${id}'`);
    assert.ok(BigInt(total)<=9223372036854775807n,'Committed mixed-source total must remain representable');
    if(release==='rollback') assert.equal(total,'24691');
  }
  console.log('PASS mixed Item/Expense Invoice edits serialize in both orders and recover after rollback');
  const detailsEdit = (name, operation, label) => {
    const command = JSON.stringify({ operationId: operation, accountId: 'account-primary',
      actorPrincipalId: 'principal-owner', contractVersion: 'item-details-edit-v1', createdAtMs: '1000',
      items: [{ itemId: source(name), expectedRevision: '1' }], changes: { name: label } });
    return `select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
      select (ledger_private.edit_item_details('${command}')).phase;`;
  };
  for (const release of ['commit', 'rollback']) {
    const name = `details-${release}`;
    prepare(name, false);
    await race(name, detailsEdit(name, `${name}-first`, 'First'),
      detailsEdit(name, `${name}-second`, 'Second'), release);
    assert.equal(sql(`select name||':'||revision from public.spike_items where id='${source(name)}'`),
      release === 'commit' ? 'First:2' : 'Second:2');
    assert.equal(sql(`select phase||coalesce(':'||error_code,'') from public.spike_operation_results where operation_id='${name}-second'`),
      release === 'commit' ? 'rejected:item_edit_stale' : 'applied');
  }
  prepare('details-retry', false);
  const retry = detailsEdit('details-retry', 'details-same-operation', 'Once');
  await race('details-retry', retry, retry, 'commit');
  assert.equal(sql("select name||':'||revision from public.spike_items where id='race-details-retry'"), 'Once:2');
  assert.equal(sql("select count(*) from public.spike_operation_results where operation_id='details-same-operation'"), '1');
  console.log('PASS Item details competing edits, rollback and identical-operation races; no lost update or double revision');
  for (const scenario of ['same-operation', 'competing-operation', 'rollback']) {
    const name = `paid-return-${scenario}`, id = source(name);
    prepare(name);
    sql(`insert into public.spike_item_placements(id,account_id,item_id,scope_kind,
      started_at,started_by_principal_id,ended_at,ended_by_principal_id)
      values('original-${id}','account-primary','${id}','business_inventory',
      '2025-01-01','principal-owner','2026-01-01','principal-owner');
      begin; ${collect(name)} commit;`);
    const paidReturn = suffix => {
      const command = JSON.stringify({ operationId: `${id}-${suffix}`, accountId: 'account-primary',
        actorPrincipalId: 'principal-owner', projectId: 'race-project',
        contractVersion: 'return-paid-items-v1', createdAtMs: '1788523200000',
        items: [{ itemId: id, placementId: id, chargeId: id, paidInvoiceLineId: `line-${id}`,
          inventoryPlacementId: `inventory-${id}-${suffix}`, returnOccurrenceId: `return-${id}-${suffix}`,
          creditId: `credit-${id}-${suffix}` }] });
      return `set local role authenticated;
        select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
        select (public.spike_return_paid_items('${command}')).phase; reset role;`;
    };
    const waiter = scenario === 'same-operation' ? 'first' : 'second';
    await race(name, paidReturn('first'), paidReturn(waiter), scenario === 'rollback' ? 'rollback' : 'commit');
    assert.equal(sql(`select phase||coalesce(':'||error_code,'') from public.spike_operation_results
      where operation_id='${id}-${waiter}'`),
    scenario === 'competing-operation' ? 'rejected:return_placement_stale' : 'applied');
    assert.equal(sql(`select count(*) from ledger_private.paid_item_return_credits where item_id='${id}'`), '1');
    assert.equal(sql(`select count(*) from public.spike_item_placements
      where item_id='${id}' and scope_kind='business_inventory' and ended_at is null`), '1');
    assert.equal(sql(`select source_revision||':'||signed_amount_minor_units from ledger_private.collected_invoice_lines
      where id='line-${id}'`), '1:12345');
    assert.equal(sql(`select revision||':'||amount_minor_units||':'||(withdrawn_at is null)
      from ledger_private.item_charge_occurrences where id='${id}'`), '1:12345:true');
    assert.equal(sql(`select count(*) from public.spike_transactions where project_id='race-project'
      and id='payment-${id}'`), '1');
  }
  console.log('PASS paid return identical retry, competing returns and rollback: one credit, one Inventory placement, frozen charge/line preserved');
  for (const scenario of ['retry','conflicting-review','rollback']) {
    const name='imported-placement-'+scenario, id=source(name);
    prepare(name,false);
    sql(`select ledger_private.import_client_payment('payment-${id}','account-primary','race-project','client-existing',
      100,'USD','synthetic-placement-race','${id}',decode('01','hex'));`);
    const invoice={invoice_id:'invoice-'+id,invoice_revision:'1',account_id:'account-primary',project_id:'race-project',
      client_id:'client-existing',purchase_id:'payment-'+id,currency:'USD',total_minor_units:'100',lines:[{
        id:'line-'+id,line_position:0,source_kind:'item',source_id:id,item_id:id,source_revision:'1',
        category_id:'category-furnishings',signed_amount_minor_units:'100',description:'Imported race Item',
        source_snapshot_json:JSON.stringify({item:{itemId:id,occurrenceId:id,
          price:{basis:{importedInvoiceAmount:{}},amount:{minorUnits:100,currency:'USD'}}}})}]};
    const sources=[{source_document_id:id,source_line_id:'line-'+id,source_bytes:'\\x02',line_source_bytes:'\\x03'}];
    const payment={p_id:'payment-'+id,p_account_id:'account-primary',p_project_id:'race-project',p_client_id:'client-existing',
      p_amount:'100',p_currency:'USD',p_source_account:'synthetic-placement-race',p_source_document:id,p_source_bytes:'\\x01'};
    const quote=value=>"'"+JSON.stringify(value).replaceAll("'","''")+"'::jsonb";
    const reviewedImport=review=>`select ledger_private.import_invoice_sources_with_placements(
      ${quote(invoice)},${quote(sources)},${quote(payment)},'synthetic-placement-race','invoice-${id}',decode('04','hex'),
      ${quote([{line_id:'line-'+id,placement_id:id}])},'principal-owner',decode('${review}','hex')); set constraints all immediate;`;
    await race(name,reviewedImport('05'),reviewedImport(scenario==='conflicting-review'?'06':'05'),
      scenario==='rollback'?'rollback':'commit',scenario==='conflicting-review'?'22000':undefined);
    assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where id='${id}'`),'1');
    assert.equal(sql(`select count(*) from ledger_private.collected_invoice_lines where id='line-${id}'`),'1');
    assert.equal(sql(`select encode(review_bytes,'hex') from ledger_private.imported_invoice_placement_reviews
      where invoice_id='invoice-${id}'`),'05');
  }
  console.log('PASS reviewed placement import concurrent retry, changed-review rejection and rollback recovery');
  sql(`insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
    values('assignment-race-a','account-primary','project','race-project','A','active'),
          ('assignment-race-b','account-primary','project','race-project','B','active');`);
  for (const scenario of ['retry','competing','rollback','movement']) {
    const name='space-assignment-'+scenario, id=source(name);
    prepare(name);
    const assign=(suffix,destination)=>{
      const command=JSON.stringify({operationId:`${id}-${suffix}`,accountId:'account-primary',
        actorPrincipalId:'principal-owner',contractVersion:'item-space-v1',createdAtMs:'1788523200000',
        scopeKind:'project',projectId:'race-project',destinationSpaceId:destination,expectedSpaceRevision:'1',
        items:[{itemId:id,expectedRevision:'1',currentSpaceId:null}]});
      return `select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
        select (ledger_private.set_item_spaces('${command}')).phase;`;
    };
    const first=scenario==='movement'
      ? `select 1 from public.spike_items where id='${id}' for update;
         update public.spike_item_placements set ended_at='2026-09-17',ended_by_principal_id='principal-owner' where id='${id}';`
      : assign('first','assignment-race-a');
    const waiter=scenario==='retry'?'first':'second';
    await race(name,first,assign(waiter,scenario==='retry'?'assignment-race-a':'assignment-race-b'),
      scenario==='rollback'?'rollback':'commit');
    assert.equal(sql(`select phase||coalesce(':'||error_code,'') from public.spike_operation_results
      where operation_id='${id}-${waiter}'`),scenario==='competing'?'rejected:space_item_stale':
      scenario==='movement'?'rejected:space_item_scope_changed':'applied');
    assert.equal(sql(`select count(*) from ledger_private.item_space_changes where item_id='${id}'`),
      scenario==='movement'?'0':'1');
    assert.equal(sql(`select placement_id||':'||amount_minor_units from ledger_private.item_charge_occurrences where id='${id}'`),`${id}:12345`);
    assert.equal(sql(`select count(*) from public.spike_item_placements where item_id='${id}'`),'1');
  }
  console.log('PASS Space assignment retry, competing destination, rollback and movement races; exact placement/charge identity preserved');
  const detailsAuth = `select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);`;
  for (const scenario of ['retry', 'competing', 'rollback', 'removed', 'hidden']) {
    const id = `transaction-details-${scenario}`;
    sql(`insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,
      presentation_order,lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms)
      values('${id}','account-primary','${id}','general','ordinary',
        (select max(presentation_order)+1 from public.spike_budget_categories where account_id='account-primary'),
        'active',false,false,1,1);
      insert into public.spike_transactions(id,account_id,amount_minor_units,currency,origin,scope_kind,category_id,notes)
      values('${id}','account-primary',9007199254740993,'USD','vendor_payment','business_inventory','${id}','Original');
      update public.spike_account_memberships set state='active' where account_id='account-primary' and principal_id='principal-restricted';`);
    const detailsEdit = suffix => `${detailsAuth} select ledger_private.edit_transaction_details('${JSON.stringify({
      operationId: `${id}-${suffix}`, accountId: 'account-primary', actorPrincipalId: 'principal-restricted',
      contractVersion: 'transaction-details-edit-v1', createdAtMs: '1000', transactionId: id,
      scopeKind: 'business_inventory', projectId: null, clientId: null, expectedRevision: '1', changes: { notes: suffix }
    })}');`;
    const holder = scenario === 'removed'
      ? "update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';"
      : scenario === 'hidden'
        ? `update public.spike_budget_categories set kind='fee',revision=revision+1 where id='${id}';`
        : detailsEdit('first');
    const waiter = scenario === 'retry' ? 'first' : 'second';
    await race(id, holder, detailsEdit(waiter), scenario === 'rollback' ? 'rollback' : 'commit',
      ['removed', 'hidden'].includes(scenario) ? '42501' : undefined);
    const denied = ['removed', 'hidden'].includes(scenario);
    assert.equal(sql(`select notes||':'||details_revision||':'||amount_minor_units from public.spike_transactions where id='${id}'`),
      `${denied ? 'Original:1' : scenario === 'rollback' ? 'second:2' : 'first:2'}:9007199254740993`);
    assert.equal(sql(`select coalesce(string_agg(phase||coalesce(':'||error_code,''),','),'none')
      from public.spike_operation_results where operation_id='${id}-${waiter}'`),
      denied ? 'none' : scenario === 'competing' ? 'rejected:transaction_edit_stale' : 'applied');
  }
  console.log('PASS Transaction descriptive-edit retry, competing edit, rollback, removal and financial-visibility races');
  for (const scenario of ['retry', 'competing', 'rollback', 'removed', 'hidden']) {
    const id = `transaction-receipt-${scenario}`;
    sql(`insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,
      presentation_order,lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms)
      values('${id}','account-primary','${id}','general','ordinary',
        (select max(presentation_order)+1 from public.spike_budget_categories where account_id='account-primary'),
        'active',false,false,1,1);
      insert into public.spike_transactions(id,account_id,amount_minor_units,currency,origin,scope_kind,category_id,notes)
      values('${id}','account-primary',9007199254740993,'USD','vendor_payment','business_inventory','${id}','Original');
      update public.spike_account_memberships set state='active' where account_id='account-primary' and principal_id='principal-restricted';`);
    const receiptEdit = suffix => `${detailsAuth} select ledger_private.edit_transaction_receipt_lines('${JSON.stringify({
      operationId: `${id}-${suffix}`, accountId: 'account-primary', actorPrincipalId: 'principal-restricted',
      contractVersion: 'transaction-receipt-lines-edit-v1', createdAtMs: '1000', transactionId: id,
      scopeKind: 'business_inventory', projectId: null, clientId: null, currency: 'USD', expectedLines: [],
      lines: [{ id: 'printed-tax', description: suffix, amountMinorUnits: '101', effect: 'increase', quantity: null }]
    })}');`;
    const holder = scenario === 'removed'
      ? "update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';"
      : scenario === 'hidden'
        ? `update public.spike_budget_categories set kind='fee',revision=revision+1 where id='${id}';`
        : receiptEdit('first');
    const waiter = scenario === 'retry' ? 'first' : 'second';
    const denied = ['removed', 'hidden'].includes(scenario);
    await race(id, holder, receiptEdit(waiter), scenario === 'rollback' ? 'rollback' : 'commit', denied ? '42501' : undefined);
    assert.equal(sql(`select coalesce(non_item_receipt_lines->0->>'description','none')||':'||notes||':'||details_revision||':'||amount_minor_units
      from public.spike_transactions where id='${id}'`),
      `${denied ? 'none' : scenario === 'rollback' ? 'second' : 'first'}:Original:1:9007199254740993`);
    assert.equal(sql(`select coalesce(string_agg(phase||coalesce(':'||error_code,''),','),'none')
      from public.spike_operation_results where operation_id='${id}-${waiter}'`),
      denied ? 'none' : scenario === 'competing' ? 'rejected:transaction_receipt_edit_stale' : 'applied');
  }
  console.log('PASS Transaction receipt-line retry, competing edit, rollback, removal and financial-visibility races');
  }
  if (process.argv.includes('--adjustments-only')) {
    for (const scenario of ['retry','competing','rollback','header','collected-first','edit-first']) {
      const name = `adjustments-${scenario}`, id = source(name);
      prepare(name);
      sql(`insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id,non_item_receipt_lines)
        values('${id}-order','account-primary',120,'USD','purchase','vendor_payment','business_inventory','category-furnishings',
          '[{"id":"shipping","description":"Shipping","amountMinorUnits":"20","effect":"increase"}]');
        insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
        values('${id}-receipt','account-primary','${id}-order','${id}','USD',100,'linked');`);
      const revision = sql(`select revision from ledger_private.item_adjustment_orders where id='${id}-order'`);
      const editAdjustment = suffix => `select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
        select (public.spike_edit_uncollected_item_price('${JSON.stringify({operationId:`${id}-${suffix}`,
          accountId:'account-primary',actorPrincipalId:'principal-owner',contractVersion:'item-live-adjustment-price-edit-v3',
          createdAtMs:'1000',projectId:'race-project',itemId:id,placementId:id,occurrenceId:id,
          transactionId:`${id}-order`,expectedAdjustmentRevision:revision,expectedPriceRevision:'0',expectedChargeRevision:'1',
          requestedPriceMinorUnits:'120',reviewedPriceMinorUnits:'120',currency:'USD'})}')).phase;`;
      const holder = scenario === 'header' ? `update public.spike_transactions set amount_minor_units=121 where id='${id}-order';`
        : scenario === 'collected-first' ? collect(name) : editAdjustment('first');
      const waiter = scenario === 'edit-first' ? collect(name) : editAdjustment(scenario === 'retry'?'first':'second');
      await race(name,holder,waiter,scenario === 'rollback'?'rollback':'commit',scenario === 'edit-first'?'23514':undefined);
      if (scenario !== 'edit-first') {
        assert.equal(sql(`select phase||coalesce(':'||error_code,'') from public.spike_operation_results
          where operation_id='${id}-${scenario === 'retry'?'first':'second'}'`),
          ['competing','header'].includes(scenario)?'rejected:price_revision_stale':'applied');
      }
      assert.equal(sql(`select count(*) from ledger_private.item_adjustment_inputs where item_id='${id}'`),scenario === 'header'?'0':'1');
      if (scenario === 'collected-first') {
        assert.equal(sql(`select amount_minor_units from ledger_private.item_project_prices where item_id='${id}'`),'120');
        assert.equal(sql(`select signed_amount_minor_units from ledger_private.collected_invoice_lines where item_id='${id}'`),'12345');
      }
    }
    console.log('PASS live adjustments: exact retry, competing revision, rollback, header edit and both collection orders');
  }
} finally {
  for (const child of sessions) if (!child.stdin.destroyed && !child.stdin.writableEnded) child.stdin.end('rollback;\n');
  if (created) {
    // Exact random database created above, never the source database or a glob.
    sql(`drop database ${database} with (force);`, 'postgres');
    console.log(`Removed owned disposable database ${database}; original database was not modified.`);
  }
}
