import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { SqlSyncRules } from '@powersync/service-sync-rules';
import { validateSyncOutputTables } from '../sync-output-tables.mjs';

const schema = 'public static let projects = "spike_projects"\npublic static let items = "spike_items"';
test('primary aliases rename output, whereas joined and nested aliases do not', () => {
  const yaml = `streams:
  projects:
    query: |
      SELECT spike_projects.* FROM spike_projects
      JOIN membership AS member ON member.account_id = spike_projects.account_id
      WHERE spike_projects.id IN (SELECT project.id FROM other AS project)
`;
  assert.equal(validateSyncOutputTables(yaml, schema), 1);
  assert.throws(() => validateSyncOutputTables(yaml.replace('FROM spike_projects', 'FROM spike_projects AS project'), schema), /Sync output project/);
});
test('wrong aliases remain wrong even when they name another valid client table', () => {
  assert.throws(() => validateSyncOutputTables('query: |\n SELECT * FROM spike_items AS spike_projects\n', schema), /does not match/);
});
test('every checked-in stream output resolves to the native schema', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const nativeSchema = readFileSync(new URL('../../LedgeriOS/LedgerTargetPowerSync/LedgerPowerSyncSchema.swift', import.meta.url), 'utf8');
  const count = validateSyncOutputTables(yaml, nativeSchema);
  assert.equal(count, 48);
  const compiled = SqlSyncRules.fromYaml(yaml, { defaultSchema: 'public', throwOnError: false });
  assert.deepEqual(compiled.errors.map(error => error.message), []);
  const nativeNames = new Set([...nativeSchema.matchAll(/public static let \w+ = "([a-z_]+)"/g)].map(m => m[1]));
  const outputs = Object.keys(compiled.config.debugGetOutputTables());
  assert.equal(outputs.length, 26);
  for (const output of outputs) assert.ok(nativeNames.has(output), `Service outputs unknown client table ${output}`);
});
test('service parser proves primary aliases change the downloaded table', () => {
  const result = SqlSyncRules.fromYaml(`config:
  edition: 3
streams:
  items:
    query: SELECT * FROM spike_items AS item
`, { defaultSchema: 'public', throwOnError: false });
  assert.deepEqual(result.errors.map(error => error.message), []);
  assert.deepEqual(Object.keys(result.config.debugGetOutputTables()), ['item']);
});

test('Item-linked Purchase local schema contains only canonical read facts with exact text cents', () => {
  const nativeSchema = readFileSync(new URL('../../LedgeriOS/LedgerTargetPowerSync/LedgerPowerSyncSchema.swift', import.meta.url), 'utf8');
  assert.match(nativeSchema, /static let transactions = "spike_transactions"/);
  const columns = nativeSchema.match(/Table\(name: LedgerPowerSyncTable.transactions,\s*columns: \[([\s\S]*?)\]/)?.[1];
  assert.ok(columns);
  assert.deepEqual([...columns.matchAll(/\.text\("([a-z_]+)"\)/g)].map(match => match[1]),
    ['account_id', 'project_id', 'client_id', 'type', 'role', 'amount_minor_units', 'currency', 'origin']);
  assert.ok(!columns.includes('.integer'));
});
