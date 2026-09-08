import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
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
    update public.spike_account_memberships set state='active' where account_id='${account}' and principal_id='principal-restricted';
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
    notify pgrst, 'reload schema'; commit;`);
  await client.connect(transport);
  const list = await client.listTools();
  assert.deepEqual(list.tools.map(t => t.name), ['get_property_management_report']);
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
    assert.equal(queries.length, 4);
    const tables = ['spike_projects', 'spike_spaces', 'spike_item_placements', 'spike_items'];
    const captures = queries.map((query, index) => {
      const bound = query.replaceAll("subscription.parameter('account_id')", `'${account}'`)
        .replaceAll("subscription.parameter('project_id')", `'${populated}'`)
        .replaceAll('auth.user_id()', "'10000000-0000-0000-0000-000000000002'::uuid");
      return `select json_build_object('table','${tables[index]}','rows',coalesce(json_agg(row_to_json(r)),'[]'::json)) from (${bound}) r;`;
    });
    const raw = execFileSync('docker', ['exec', '-i', container, 'psql', '-X', '-q', '-A', '-t',
      '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], {
      input: `begin isolation level repeatable read read only;\n${captures.join('\n')}\ncommit;`, encoding: 'utf8',
    }).trim().split('\n').map(JSON.parse);
    assert.equal(raw.length, 4);
    writeFileSync(parityOutput, JSON.stringify({
      accountId: account, principalId: 'principal-restricted', projectId: populated,
      currency: 'USD', tables: raw, report,
    }), { mode: 0o600, flag: 'wx' });
    console.log('Captured actual scoped stream rows and MCP snapshot for native differential verification.');
  }
  const wrongCurrency = await client.callTool({ name: 'get_property_management_report', arguments: { projectId: populated, currency: 'CAD' } });
  assert.equal(wrongCurrency.isError, true);
  sql(`update public.spike_account_memberships set state='removed' where account_id='${account}' and principal_id='principal-restricted';`);
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
