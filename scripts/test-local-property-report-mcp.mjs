import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
import { readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { Client } from '../LedgerTargetMCP/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js';
import { StdioClientTransport } from '../LedgerTargetMCP/node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js';

const root = realpathSync(new URL('..', import.meta.url).pathname);
assert.equal(root, process.env.GITHUB_ACTIONS === 'true'
  ? realpathSync(process.env.GITHUB_WORKSPACE) : '/Users/benjaminmackenzie/Dev/ledger_mobile_supabase');
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT, 'No Docker destination overrides');
assert.match(JSON.parse(execFileSync('docker', ['context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}'],
  { encoding: 'utf8', timeout: 10_000 })), /^unix:\/\//, 'Only a local Docker socket');
const container = 'supabase_db_ledger_target_supabase_local';
const labels = JSON.parse(execFileSync('docker', ['inspect', container, '--format', '{{json .Config.Labels}}'], { encoding: 'utf8' }));
assert.equal(labels['com.supabase.cli.project'], 'ledger_target_supabase_local');
assert.equal(realpathSync(labels['com.supabase.cli.workdir']), root);
const status = JSON.parse(execFileSync('npx', ['--offline', '--yes', 'supabase@2.116.0', 'status', '-o', 'json'],
  { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
const endpoint = new URL(status.API_URL);
assert.equal(endpoint.protocol, 'http:');
assert.ok(['localhost', '127.0.0.1'].includes(endpoint.hostname));
const sql = text => execFileSync('docker', ['exec', '-i', container, 'psql', '-X', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'],
  { input: text, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
// Reuse this script's fixed synthetic placement. Both attempted changes roll
// back; the test adds no history and never needs to defeat retention triggers.
async function verifyCategoryDepartureSerialization() {
  const holder = spawn('docker', ['exec', '-i', container, 'psql', '-X', '-q', '-A', '-t',
    '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], { stdio: ['pipe', 'pipe', 'pipe'] });
  const closed = new Promise(resolve => holder.once('close', resolve));
  let output = '', timer;
  try {
    await new Promise((resolve, reject) => {
      timer = setTimeout(() => reject(new Error('Category lock holder did not become ready')), 5000);
      holder.once('error', reject);
      holder.stderr.on('data', () => reject(new Error('Category lock holder failed')));
      holder.stdout.on('data', data => { output += data; if (output.includes('CATEGORY_LOCK_HELD')) resolve(); });
      holder.stdin.write("begin; set local idle_in_transaction_session_timeout='5s'; update public.spike_item_project_categories set revision=revision+1 where id='report-mcp-fixture-p1'; select 'CATEGORY_LOCK_HELD';\n");
    });
    clearTimeout(timer);
    assert.throws(() => sql("begin; set local lock_timeout='250ms'; update public.spike_item_placements set ended_at='2026-09-10',ended_by_principal_id='principal-owner' where id='report-mcp-fixture-p1'; rollback;"),
      error => error.status === 3 && /lock timeout/.test(String(error.stderr)),
      'A category correction holds the placement lock against concurrent departure');
  } finally {
    clearTimeout(timer);
    holder.stdin.end('rollback;\n');
    await closed;
  }
}
const project = `report-mcp-${randomUUID()}`;
// Fixed synthetic fixture: repeat runs reuse immutable placement history rather
// than deleting it or creating another permanent graph each time.
const account = 'report-mcp-fixture-account';
const populated = 'report-mcp-fixture-project';
const now = Math.floor(Date.now() / 1000);
const unsigned = `${Buffer.from('{"alg":"HS256","typ":"JWT"}').toString('base64url')}.${Buffer.from(JSON.stringify({
  aud: 'authenticated', role: 'authenticated', sub: '10000000-0000-0000-0000-000000000002', iat: now, exp: now + 300,
})).toString('base64url')}`;
const token = `${unsigned}.${createHmac('sha256', status.JWT_SECRET).update(unsigned).digest('base64url')}`;
const transport = new StdioClientTransport({ command: process.execPath,
  args: ['--import', `${root}/LedgerTargetMCP/node_modules/tsx/dist/loader.mjs`, `${root}/LedgerTargetMCP/src/stdio.ts`],
  env: { PATH: process.env.PATH, LEDGER_TARGET_SUPABASE_URL: endpoint.origin,
    LEDGER_TARGET_PUBLISHABLE_KEY: status.PUBLISHABLE_KEY, LEDGER_TARGET_ACCESS_TOKEN: token,
    LEDGER_TARGET_ACCOUNT_ID: account }, stderr: 'pipe' });
const client = new Client({ name: 'ledger-local-report-test', version: '1' });
try {
  sql(`begin;
    insert into public.spike_accounts(id,display_name) values ('${account}','Synthetic MCP report fixture') on conflict do nothing;
    insert into public.spike_account_memberships(account_id,principal_id,role,state)
      values ('${account}','principal-restricted','employee','active') on conflict do nothing;
    update public.spike_account_memberships set state='active',financial_access='full' where account_id='${account}' and principal_id='principal-restricted';
    insert into public.spike_clients(id,account_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
      values ('report-mcp-fixture-client','${account}','Synthetic',now(),now(),1,1,'principal-owner') on conflict do nothing;
    insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
      values ('${project}','${account}','report-mcp-fixture-client','MCP empty report',now(),now(),1,1,'principal-owner'),
      ('${populated}','${account}','report-mcp-fixture-client','MCP populated report',now(),now(),1,1,'principal-owner') on conflict do nothing;
    insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
      values ('report-mcp-fixture-room','${account}','project','${populated}','Archived room','archived'),
      ('report-mcp-fixture-unused','${account}','project','${populated}','Unused archived room','archived') on conflict do nothing;
    insert into public.spike_items(id,account_id,name,description,sku,market_value_minor_units,market_value_currency,created_by_principal_id)
      values ('report-mcp-fixture-large','${account}','Table / 木','', 'SKU-L',9007199254740993,'USD','principal-owner'),
      ('report-mcp-fixture-zero','${account}','Chair','',null,0,'USD','principal-owner'),
      ('report-mcp-fixture-unknown','${account}',null,'Unknown chair',null,null,null,'principal-owner') on conflict do nothing;
    insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at,started_by_principal_id)
      values ('report-mcp-fixture-p1','${account}','report-mcp-fixture-large','project','${populated}','report-mcp-fixture-room','2026-09-01','principal-owner'),
      ('report-mcp-fixture-p2','${account}','report-mcp-fixture-zero','project','${populated}',null,'2026-09-01','principal-owner'),
      ('report-mcp-fixture-p3','${account}','report-mcp-fixture-unknown','project','${populated}',null,'2026-09-01','principal-owner') on conflict do nothing;
    insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency)
      values ('report-mcp-payment','${account}','${populated}','report-mcp-fixture-client',500,'USD') on conflict do nothing;
    insert into ledger_private.item_client_payment_connections(id,account_id,project_id,client_id,item_id,
      placement_id,transaction_id,started_at,started_by_principal_id)
      select 'report-mcp-link-' || placement.id,'${account}','${populated}','report-mcp-fixture-client',
        placement.item_id,placement.id,'report-mcp-payment','2026-09-02','principal-owner'
      from public.spike_item_placements placement where placement.account_id='${account}'
        and placement.project_id='${populated}' and placement.ended_at is null
      on conflict do nothing;
    insert into public.spike_budget_categories(id,account_id,display_name,kind,lifecycle,visibility_class,presentation_order,created_at_ms,updated_at_ms)
      values ('report-mcp-category','${account}','Furnishings','itemized','archived','ordinary',10,1,1) on conflict do nothing;
    insert into public.spike_item_project_categories(id,account_id,project_id,item_id,category_id)
      select placement.id,'${account}','${populated}',placement.item_id,'report-mcp-category'
      from public.spike_item_placements placement where placement.account_id='${account}'
        and placement.project_id='${populated}' and placement.ended_at is null
      on conflict do nothing;
    insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
      amount_minor_units,currency,created_at,created_by_principal_id)
      select 'report-mcp-charge-'||placement.id,'${account}','${populated}',placement.item_id,placement.id,
        'report-mcp-category',case when placement.id='report-mcp-fixture-p3' then 9007199254740993 else 250 end,
        'USD','2026-09-02','principal-owner'
      from public.spike_item_placements placement where placement.id in ('report-mcp-fixture-p2','report-mcp-fixture-p3')
        and not exists(select 1 from ledger_private.item_charge_occurrences charge where charge.id='report-mcp-charge-'||placement.id);
    update ledger_private.item_client_payment_connections set ended_at='2026-09-03',ended_by_principal_id='principal-owner'
      where id in ('report-mcp-link-report-mcp-fixture-p2','report-mcp-link-report-mcp-fixture-p3') and ended_at is null;
    insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency)
      values('report-mcp-charge-payment','${account}','${populated}','report-mcp-fixture-client',250,'USD') on conflict do nothing;
    insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
      select 'report-mcp-charge-invoice','${account}','${populated}','report-mcp-fixture-client','report-mcp-charge-payment',1,'USD',250
      where not exists(select 1 from ledger_private.collected_invoices where id='report-mcp-charge-invoice');
    insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
      source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
      select 'report-mcp-charge-line','${account}','report-mcp-charge-invoice',0,'USD','item','report-mcp-charge-report-mcp-fixture-p2',
        'report-mcp-fixture-zero',1,'report-mcp-category',250,'Synthetic charge','{}'::jsonb
      where not exists(select 1 from ledger_private.collected_invoice_lines where id='report-mcp-charge-line');
    update ledger_private.collected_invoices set sealed=true where id='report-mcp-charge-invoice' and not sealed;
    notify pgrst, 'reload schema'; commit;`);
  await verifyCategoryDepartureSerialization();
  await client.connect(transport);
  const list = await client.listTools();
  assert.deepEqual(list.tools.map(t => t.name), ['get_property_management_report', 'get_client_summary_physical_report']);
  const result = await client.callTool({ name: 'get_property_management_report', arguments: { projectId: project, currency: 'USD' } });
  assert.notEqual(result.isError, true);
  const snapshot = JSON.parse(result.content[0].text);
  assert.equal(snapshot.project.projectId, project);
  assert.equal(snapshot.provenance.principalId, 'principal-restricted');
  assert.equal(snapshot.provenance.source.kind, 'authoritative');
  assert.equal(snapshot.totals.itemCount, 0);
  assert.equal(snapshot.totals.totalMarketValueMinorUnits, '0');
  const readPopulated = () => client.callTool({ name: 'get_property_management_report', arguments: { projectId: populated, currency: 'USD' } });
  const populatedResult = await readPopulated();
  assert.notEqual(populatedResult.isError, true);
  const report = JSON.parse(populatedResult.content[0].text);
  assert.equal(report.totals.itemCount, 3);
  assert.equal(report.totals.knownMarketValueSubtotalMinorUnits, '9007199254740993');
  assert.equal(report.totals.totalMarketValueMinorUnits, null);
  assert.equal(report.totals.unknownMarketValueCount, 1);
  assert.deepEqual(report.spaces.map(s => s.spaceId), ['report-mcp-fixture-room']);
  const rows = report.groups.flatMap(g => g.rows);
  assert.equal(rows.find(r => r.itemId.endsWith('-large')).name, 'Table / 木');
  assert.equal(rows.find(r => r.itemId.endsWith('-unknown')).name, 'Unknown chair');
  assert.equal(rows.find(r => r.itemId.endsWith('-zero')).marketValueMinorUnits, '0');
  assert.ok(report.groups.some(g => g.name === 'No Space' && g.rows.length === 2));
  const readClient = () => client.callTool({ name: 'get_client_summary_physical_report', arguments: { projectId: populated } });
  const clientResult = await readClient();
  assert.notEqual(clientResult.isError, true);
  const clientReport = JSON.parse(clientResult.content[0].text);
  assert.equal(clientReport.reportKind, 'client_summary_physical');
  assert.equal(clientReport.items.length, 3);
  assert.equal(clientReport.client.kind, 'known');
  assert.ok(clientReport.items.every(item => item.category.known.name === 'Furnishings'
    && item.accounting.resolution === 'accountedFor'));
  assert.ok(!Object.hasOwn(clientReport, 'totals') && !Object.hasOwn(clientReport, 'currency'));
  assert.ok(clientReport.items.every(item => !Object.hasOwn(item, 'marketValueMinorUnits')));
  const charged = clientReport.items.filter(item => item.accounting.evidence.billableOccurrences.length);
  assert.equal(charged.length, 2);
  assert.ok(charged.every(item => item.accounting.evidence.clientPaidPurchases.length === 0));
  assert.deepEqual(charged.map(item => item.accounting.evidence.billableOccurrences[0].phase.kind).sort(),
    ['availableToInvoice','frozenPaid']);
  // Optional differential artifact: actual stream projections, not a second
  // hand-maintained fixture. The native test consumes these exact source rows.
  const parityOutput = process.env.LEDGER_REPORT_PARITY_OUTPUT
    ?? (process.env.GITHUB_ACTIONS === 'true' ? `${process.env.RUNNER_TEMP}/ledger-property-report-parity.json` : undefined);
  if (parityOutput) {
    const yaml = readFileSync(`${root}/powersync/sync-streams.yaml`, 'utf8');
    const block = yaml.match(/^  property_management_report:\n([\s\S]*?)(?=^  \S|$(?![\s\S]))/m)?.[1];
    assert.ok(block);
    const queries = [...block.matchAll(/^      - \|\n((?:        .*(?:\n|$))+)/gm)]
      .map(match => match[1].replace(/^        /gm, '').trim());
    assert.equal(queries.length, 13);
    const tables = ['item_image_sets', 'spike_projects', 'spike_spaces', 'spike_item_placements', 'spike_items',
      'spike_clients', 'spike_transactions', 'item_client_payment_connections', 'spike_item_project_categories', 'spike_budget_categories',
      'item_charge_occurrences', 'collected_invoice_lines', 'collected_invoices'];
    const captures = queries.map((query, index) => {
      assert.equal(query.match(/\bFROM\s+(?:ledger_private\.)?([a-z_]+)/)?.[1], tables[index],
        'Every captured query must retain its actual source-table identity');
      const bound = query.replaceAll("subscription.parameter('account_id')", `'${account}'`)
        .replaceAll("subscription.parameter('project_id')", `'${populated}'`)
        .replaceAll('auth.user_id()', "'10000000-0000-0000-0000-000000000002'::uuid");
      return `select json_build_object('table','${tables[index]}','rows',coalesce(json_agg(row_to_json(r)),'[]'::json)) from (${bound}) r;`;
    });
    const raw = execFileSync('docker', ['exec', '-i', container, 'psql', '-X', '-q', '-A', '-t',
      '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], {
      input: `begin isolation level repeatable read read only;\n${captures.join('\n')}\ncommit;`, encoding: 'utf8',
    }).trim().split('\n').map(JSON.parse);
    assert.equal(raw.length, 13);
    // Extend the same-commit native artifact with actual private Invoice storage
    // output. This isolated synthetic transaction rolls back even on success;
    // it creates no public collection API or durable accounting fixture graph.
    // Source JSON stays TEXT through Node so embedded Int64 money is never
    // parsed as a JavaScript Number before Swift consumes the SQL result.
    const description = '  e\u0301\r\nOriginal description  ';
    const line = (id, position, kind, sourceId, itemId, amount, sourceJSON) => ({
      id, line_position: position, source_kind: kind, source_id: sourceId,
      item_id: itemId, source_revision: '2', category_id: 'furnishings',
      signed_amount_minor_units: amount, description, source_snapshot_json: sourceJSON,
    });
    const invoiceInput = {
      invoice_id: 'frozen-invoice', invoice_revision: '3', account_id: 'account-primary',
      project_id: 'frozen-project', client_id: 'client-existing', purchase_id: 'frozen-purchase',
      currency: 'USD', total_minor_units: '9007199254740978', lines: [
        line('z-sale', 0, 'item', 'sale', 'frozen-item', '9007199254740993',
          '{"item":{"itemId":"frozen-item","occurrenceId":"sale","price":{"basis":{"projectPrice":{}},"amount":{"minorUnits":9007199254740993,"currency":"USD"}}}}'),
        line('a-credit', 1, 'item', 'return', 'frozen-item', '-20',
          '{"item":{"itemId":"frozen-item","occurrenceId":"return","price":{"basis":{"paidInvoiceLine":{"invoiceId":"prior-invoice","lineId":"prior-line"}},"amount":{"minorUnits":20,"currency":"USD"}}}}'),
        line('expense-line', 2, 'expense', 'expense', null, '3', '{"expense":{"expenseId":"expense"}}'),
        line('fee-line', 3, 'fee_installment', 'installment', null, '2', '{"feeInstallment":{"installmentId":"installment"}}'),
      ],
    };
    const frozenInvoice = JSON.parse(execFileSync('docker', ['exec', '-i', container, 'psql', '-X', '-q', '-A', '-t',
      '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], {
      input: `begin;
        insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
          values ('frozen-project','account-primary','client-existing','Synthetic frozen Invoice parity',now(),now(),1,1,'principal-owner');
        insert into public.spike_items(id,account_id,description,created_by_principal_id)
          values ('frozen-item','account-primary','Original Item','principal-owner');
        do $fixture$ declare stored jsonb; begin
          perform ledger_private.import_client_payment('frozen-purchase','account-primary','frozen-project','client-existing',
            9007199254740978,'USD','synthetic-frozen-parity','frozen-invoice',decode('01','hex'));
          stored := ledger_private.store_collected_invoice($record$${JSON.stringify(invoiceInput)}$record$::jsonb);
          if stored is distinct from ledger_private.read_collected_invoice('account-primary','frozen-invoice')
            or stored is distinct from ledger_private.store_collected_invoice($record$${JSON.stringify(invoiceInput)}$record$::jsonb)
          then raise exception 'Frozen Invoice store, read and replay differ'; end if;
        end $fixture$;
        set constraints all immediate;
        select ledger_private.read_collected_invoice('account-primary','frozen-invoice');
        rollback;`, encoding: 'utf8',
    }).trim());
    assert.equal(frozenInvoice.total_minor_units, '9007199254740978');
    assert.equal(frozenInvoice.lines[0].signed_amount_minor_units, '9007199254740993');
    assert.match(frozenInvoice.lines[0].source_snapshot_json, /9007199254740993/);
    assert.deepEqual(frozenInvoice.lines.map(line => line.id), ['z-sale', 'a-credit', 'expense-line', 'fee-line']);
    assert.deepEqual(frozenInvoice.lines.map(line => line.line_position), [0, 1, 2, 3]);
    assert.ok(frozenInvoice.lines.every(line => line.description === description));
    assert.equal(frozenInvoice.lines[2].item_id, null);
    assert.equal(frozenInvoice.lines[3].item_id, null);
    writeFileSync(parityOutput, JSON.stringify({
      accountId: account, principalId: 'principal-restricted', projectId: populated,
      currency: 'USD', tables: raw, report, clientReport, frozenInvoice,
    }), { mode: 0o600, flag: 'wx' });
    console.log('Captured actual scoped stream rows, MCP snapshot and SQL frozen Invoice for native differential verification.');
  }
  const wrongCurrency = await client.callTool({ name: 'get_property_management_report', arguments: { projectId: populated, currency: 'CAD' } });
  assert.equal(wrongCurrency.isError, true);
  sql(`update public.spike_account_memberships set financial_access='limited' where account_id='${account}' and principal_id='principal-restricted';`);
  const limited = await readPopulated();
  assert.equal(limited.isError, true);
  assert.deepEqual(JSON.parse(limited.content[0].text), { code: 'property_report_incomplete_readiness' });
  const limitedClient = await readClient();
  assert.notEqual(limitedClient.isError, true);
  assert.ok(JSON.parse(limitedClient.content[0].text).items.every(item => item.accounting === null),
    'Physical preview retains unknown eligibility without leaking hidden payment links');
  sql(`update public.spike_account_memberships set financial_access='full' where account_id='${account}' and principal_id='principal-restricted';`);
  sql(`update public.spike_account_memberships set state='removed' where account_id='${account}' and principal_id='principal-restricted';`);
  assert.equal((await readClient()).isError, true, 'Removed membership denies Client report with same JWT');
  const revoked = await readPopulated();
  assert.equal(revoked.isError, true);
  assert.deepEqual(JSON.parse(revoked.content[0].text), { code: 'account_not_authorized' });
  sql(`update public.spike_account_memberships set state='active' where account_id='${account}' and principal_id='principal-restricted';`);
  assert.notEqual((await readPopulated()).isError, true, 'Same session can read after explicit membership restoration');
  const injected = await client.callTool({ name: 'get_property_management_report', arguments: {
    projectId: project, currency: 'USD', principalId: 'principal-owner', accountId: 'account-other',
  } });
  assert.equal(injected.isError, true);
  const denied = await client.callTool({ name: 'get_property_management_report', arguments: { projectId: 'missing', currency: 'USD' } });
  assert.equal(denied.isError, true);
  assert.ok(!JSON.stringify(denied).includes(token));
  let invalidSession;
  try {
    execFileSync(process.execPath, ['--import', `${root}/LedgerTargetMCP/node_modules/tsx/dist/loader.mjs`,
      `${root}/LedgerTargetMCP/src/stdio.ts`], { timeout: 10_000, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
      env: { PATH: process.env.PATH, LEDGER_TARGET_SUPABASE_URL: endpoint.origin,
        LEDGER_TARGET_PUBLISHABLE_KEY: status.PUBLISHABLE_KEY,
        LEDGER_TARGET_ACCESS_TOKEN: `${unsigned}.invalidsignature`, LEDGER_TARGET_ACCOUNT_ID: 'account-primary' } });
  } catch (error) { invalidSession = error; }
  assert.equal(invalidSession?.status, 1, 'Bad JWT signature must prevent MCP startup');
  assert.equal(invalidSession.stdout, '');
  assert.equal(invalidSession.stderr, 'Ledger target MCP could not start: check target configuration and user session.\n');
  console.log('PASS: real MCP/HTTP populated + empty reports, exact money/unknowns/Space parents, same-session revocation/restoration, identity injection and invalid JWT denial.');
} finally {
  try { await client.close(); }
  finally {
    try { await transport.close(); }
    finally { sql(`begin; update public.spike_account_memberships set state='removed' where account_id='${account}' and principal_id='principal-restricted';
      delete from public.spike_projects where id='${project}' and account_id='${account}'; commit;`); }
  }
}
