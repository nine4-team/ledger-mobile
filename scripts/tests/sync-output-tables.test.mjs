import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { SqlSyncRules, DEFAULT_HYDRATION_STATE, RequestParameters } from '@powersync/service-sync-rules';
import { validateSyncOutputTables } from '../sync-output-tables.mjs';

const schema = 'public static let projects = "spike_projects"\npublic static let items = "spike_items"';
test('operation results download under their stable operation identity with readback evidence', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const { config } = SqlSyncRules.fromYaml(yaml, { defaultSchema: 'public' });
  const evaluator = config.hydrate({ hydrationState: DEFAULT_HYDRATION_STATE, sqlite: null });
  const sourceTable = { connectionTag: 'default', schema: 'public', name: 'spike_operation_results' };
  for (const operation_id of ['receipt-edit-first', 'receipt-edit-second']) {
    const { results, errors } = evaluator.evaluateRowWithErrors({ sourceTable,
      record: { operation_id, account_id: 'account-proof', receipt_lines_revision: '2' } });
    assert.deepEqual(errors, []);
    assert.equal(results.length, 1);
    assert.equal(results[0].table, 'spike_operation_results');
    assert.equal(results[0].id, operation_id);
    assert.equal(results[0].data.receipt_lines_revision, '2');
  }
});
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
  // Project and Inventory reads include coherent placement-revision evidence.
  assert.equal(count, 98);
  const compiled = SqlSyncRules.fromYaml(yaml, { defaultSchema: 'public', throwOnError: false });
  assert.deepEqual(compiled.errors.map(error => error.message), []);
  const nativeNames = new Set([...nativeSchema.matchAll(/public static let \w+ = "([a-z_]+)"/g)].map(m => m[1]));
  const outputs = Object.keys(compiled.config.debugGetOutputTables());
  assert.equal(outputs.length, 46);
  for (const output of outputs) assert.ok(nativeNames.has(output), `Service outputs unknown client table ${output}`);
});
test('adjustment and Project category lookups constrain the subscribed Account before expansion', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const adjustment = yaml.split('FROM ledger_private.item_adjustment_orders')[1].split('      - |')[0];
  for (const alias of ['txn', 'category', 'membership']) {
    assert.match(adjustment, new RegExp(`${alias}\\.account_id\\s*=\\s*subscription\\.parameter\\('account_id'\\)`));
  }
  const projectCategory = yaml.split('FROM spike_item_project_categories')[1].split('      - |')[0];
  assert.match(projectCategory, /category\.account_id\s*=\s*subscription\.parameter\('account_id'\)/);
});
test('return review outputs exclude money and Invoice identities while retaining category authorization', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const block = yaml.split('  item_return_review:')[1].split('  physical_account_items:')[0];
  const queries = block.split('      - |').slice(1);
  assert.equal(queries.length, 3);
  for (const query of queries) {
    const projection = query.split('FROM')[0];
    assert.doesNotMatch(projection, /amount|currency|invoice_id|purchase_id|description|snapshot/);
    assert.match(query, /principal.auth_user_id=auth.user_id\(\)/);
    assert.match(query, /membership.state='active'/);
    assert.match(query, /category.visibility_class='ordinary' OR membership.financial_access='full'/);
    assert.match(query, /project_id=subscription.parameter\('project_id'\)/);
  }
});

test('paid return history stays Item-scoped and full-financial, independent of current Project placement', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const block = yaml.split('  item_invoice_history:')[1].split('  item_return_review:')[0];
  const credit = block.split('      - |').find(query => query.includes('FROM ledger_private.paid_item_return_credits'));
  assert.ok(credit);
  assert.match(credit, /paid_item_return_credits.account_id=subscription.parameter\('account_id'\)/);
  assert.match(credit, /paid_item_return_credits.item_id=subscription.parameter\('item_id'\)/);
  assert.match(credit, /principal.auth_user_id=auth.user_id\(\)/);
  assert.match(credit, /membership.state='active' AND membership.financial_access='full'/);
  assert.doesNotMatch(credit, /sync_is_current|project_id|amount_minor_units/);
});

test('Project credit routing and category labels do not expand once per charge', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const block = yaml.split('  project_invoicing_item_charges:')[1].split('  transaction_receipts:')[0];
  const queries = block.split('      - |');
  const credit = queries.find(query => query.includes('FROM ledger_private.paid_item_return_credits'));
  const categories = queries.find(query => query.includes('FROM spike_budget_categories'));
  assert.match(credit, /paid_item_return_credits.project_id = subscription.parameter\('project_id'\)/);
  assert.doesNotMatch(credit, /JOIN ledger_private.item_charge_occurrences/);
  assert.doesNotMatch(categories, /FROM ledger_private.item_charge_occurrences/);
  assert.match(categories, /spike_budget_categories.account_id = subscription.parameter\('account_id'\)/);
  assert.match(categories, /membership.state = 'active' AND membership.financial_access = 'full'/);
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

test('live Invoice stream scopes all new outputs to full financial membership and the selected Project', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const block = yaml.split('  project_live_invoices:')[1].split('  project_expenses:')[0];
  const queries = block.split('      - |').slice(1);
  assert.equal(queries.length, 3);
  for (const query of queries) {
    assert.match(query, /principal\.auth_user_id = auth\.user_id\(\)/);
    assert.match(query, /membership\.state = 'active' AND membership\.financial_access = 'full'/);
    assert.match(query, /account_id = subscription\.parameter\('account_id'\)/);
    assert.match(query, /project_id = subscription\.parameter\('project_id'\)/);
  }
  assert.match(queries[1], /released_at IS NULL/);
  assert.match(queries[1], /live_invoices\.status = 'created' OR live_invoices\.status = 'sent'/);
  assert.match(queries[2], /amount_minor_units::text AS amount_minor_units/);
  assert.match(queries[2], /revision::text AS revision/);
});

test('media buckets route on physical scope columns, never attachment identities', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const { config, errors } = SqlSyncRules.fromYaml(yaml, { defaultSchema: 'public', throwOnError: false });
  assert.deepEqual(errors.map(error => error.message), []);
  for (const name of ['item_images','project_item_images','space_media']) {
    const stream = config.bucketSources.find(source => source.name === name);
    for (const source of stream.dataSources.flatMap(source => source.source.sources)) {
      const columns = source.parameters.map(parameter => parameter.expr.source?.column);
      assert.ok(columns.every(column => ['account_id','item_id','space_id','sync_project_id','scope_id'].includes(column)),
        `${name}/${source.sourceTable.tablePattern}: ${columns}`);
    }
  }
});

test('700-Item Project media and mixed117-Item Space subscriptions stay below the real pre-dedup budget', async () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const { config } = SqlSyncRules.fromYaml(yaml, { defaultSchema: 'public', throwOnError: true });
  const evaluator = config.hydrate({ hydrationState: DEFAULT_HYDRATION_STATE, sqlite: null });
  const facts = [];
  const add = (name, row, schema = 'public') => facts.push({ table: {connectionTag:'default',schema,name}, row });
  add('spike_principals', {id:'actor',auth_user_id:'user'});
  add('spike_account_memberships', {id:'member',account_id:'account',principal_id:'actor',state:'active',financial_access:'full'});
  add('spike_projects', {id:'project',account_id:'account',lifecycle:'active'});
  add('spike_spaces', {id:'space',account_id:'account',scope_kind:'project',project_id:'project',lifecycle:'active',sync_current_item_count:117});
  add('space_media_sets', {id:'space-set',account_id:'account',space_id:'space',revision:1,expected_count:30});
  for (let i=0;i<700;i++) {
    add('spike_items', {id:`item${i}`,account_id:'account',sync_project_id:'project'});
    add('spike_item_placements', {id:`placement${i}`,account_id:'account',item_id:`item${i}`,scope_kind:'project',project_id:'project',space_id:i<117?'space':null,ended_at:null});
    add('item_image_sets', {id:`item${i}`,account_id:'account',item_id:`item${i}`,sync_project_id:'project',revision:1,expected_count:4});
    for (let j=0;j<4;j++) {
      const object = `object${i}-${j}`;
      add('item_image_references', {id:`ref${i}-${j}`,account_id:'account',item_id:`item${i}`,attachment_id:object,set_revision:1,position:j,is_primary:j===0?1:0,sync_project_id:'project',sync_is_current:1});
      for (const [scope_kind,scope_id] of [['item',`item${i}`],['project','project']]) {
        add('media_sync_objects', {id:`${scope_id}-${object}`,account_id:'account',scope_kind,scope_id,attachment_id:object,byte_count:123,content_sha256:'a'.repeat(64),media_type:'image/jpeg',storage_path:object}, 'ledger_private');
        add('media_sync_thumbnails', {id:`${scope_id}-${object}`,account_id:'account',scope_kind,scope_id,thumbnail_link_id:`thumb-${object}`,original_attachment_id:object,thumbnail_attachment_id:`small-${object}`,recipe:'item-card-300-jpeg-v1',pixel_width:300,pixel_height:200}, 'ledger_private');
      }
    }
  }
  async function budget(streams, userId = 'user', removed = false) {
    const index = new Map();
    for (const fact of facts) {
      const row = removed && fact.table.name === 'spike_account_memberships' ? {...fact.row,state:'removed'} : fact.row;
      for (const entry of evaluator.evaluateParameterRow(fact.table,row)) {
        const key = entry.lookup.serializedRepresentation;
        index.set(key,[...(index.get(key)??[]),...entry.bucketParameters]);
      }
    }
    const {querier,errors} = evaluator.getBucketParameterQuerier({globalParameters:new RequestParameters({parsedPayload:{sub:userId},userIdJson:userId,parameters:{}},{}),hasDefaultStreams:false,streams});
    assert.deepEqual(errors,[]);
    let rows=0;
    const buckets=await querier.queryDynamicBucketDescriptions({getParameterSets:async lookups=>lookups.map(lookup=>{
      const values=index.get(lookup.serializedRepresentation)??[];
      rows+=values.length; // Intentionally before any DISTINCT/bucket deduplication.
      assert.ok(rows<1000,`pre-dedup parameter budget exceeded: ${rows}`);
      return {lookup,rows:values};
    })});
    return {rows,buckets:[...buckets,...querier.staticBuckets].length};
  }
  const sub = parameters => ({parameters:{account_id:'account',...parameters},priorityOverride:null,opaque_id:0});
  const projectStreams = {project_item_images:[sub({project_id:'project'})],property_management_report:[sub({project_id:'project'})],
    space_media:[sub({space_id:'space'})],space_core_details:[sub({space_id:'space'})]};
  const project = await budget(projectStreams);
  assert.ok(project.rows<100,`700-Item Project uses scope-sized parameter results: ${project.rows}`);
  const mixed = await budget({...projectStreams,project_item_images:[],item_images:Array.from({length:117},(_,i)=>sub({item_id:`item${i}`}))});
  assert.ok(mixed.buckets>0);
  assert.equal((await budget(projectStreams,'foreign-user')).buckets,0);
  assert.equal((await budget(projectStreams,'user',true)).buckets,0);
  console.log(`Media capacity: Project700=${project.rows} parameter rows; mixed117=${mixed.rows} (limit1000)`);
  // Verify physical aliases preserve downloaded IDs and exact descriptors.
  const {results,errors}=evaluator.evaluateRowWithErrors({sourceTable:{connectionTag:'default',schema:'ledger_private',name:'media_sync_objects'},
    record:{id:'route-key',account_id:'account',scope_kind:'project',scope_id:'project',attachment_id:'original',content_sha256:'a'.repeat(64),byte_count:123,media_type:'image/jpeg',storage_path:'protected-original'}});
  assert.deepEqual(errors,[]);
  assert.ok(results.some(row=>row.table==='item_image_objects' && row.id==='original' && row.data.byte_count==='123' && row.data.storage_path==='protected-original'));
});

test('project Item and accounting buckets do not grow per physical Item', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const { config, errors } = SqlSyncRules.fromYaml(yaml, { defaultSchema: 'public', throwOnError: false });
  assert.deepEqual(errors.map(error => error.message), []);
  const stream = config.bucketSources.find(source => source.name === 'property_management_report');
  // Inspect actual compiler inputs, not SQL spelling: an IN/placement join
  // compiled successfully but created hundreds of parameter results per query.
  const expected = {
    spike_items: ['account_id', 'sync_project_id'],
    item_image_sets: ['account_id', 'sync_project_id'],
    item_client_payment_connections: ['account_id', 'project_id'],
    item_charge_occurrences: ['account_id', 'project_id'],
    collected_invoice_lines: ['account_id', 'sync_project_id'],
    spike_item_project_categories: ['category_id', 'account_id', 'project_id'],
  };
  for (const [table, parameters] of Object.entries(expected)) {
    const sources = stream.dataSources.flatMap(source => source.source.sources)
      .filter(source => source.sourceTable.tablePattern === table);
    assert.ok(sources.length > 0);
    for (const source of sources) {
      assert.deepEqual(source.parameters.map(parameter => parameter.expr.source?.column),
        parameters);
    }
  }
});

test('receipt and physical Item streams provide identical overlapping Item fields', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const receipt = yaml.split('  transaction_receipts:')[1].split('  physical_account_items:')[0];
  const physical = yaml.split('  physical_account_items:')[1].split('  spike_account_bootstrap:')[0];
  const projection = block => block.match(/SELECT spike_items\.id,([\s\S]*?)FROM spike_items/)?.[1].replace(/\s+/g, ' ').trim();
  assert.ok(projection(receipt));
  assert.equal(projection(receipt), projection(physical));
});

test('Transaction current relationships reuse the physical report projections', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const receipt = yaml.split('  transaction_receipts:')[1].split('  physical_account_items:')[0];
  const physical = yaml.split('  property_management_report:')[1].split('  transaction_receipts:')[0];
  for (const table of ['spike_item_placements', 'spike_item_project_categories', 'item_client_payment_connections', 'spike_spaces', 'item_image_sets', 'collected_invoices', 'collected_invoice_lines']) {
    const projections = block => [...block.matchAll(new RegExp(`SELECT ${table}\\.id,([\\s\\S]*?)FROM (?:ledger_private\\.)?${table}`, 'g'))]
      .map(match => match[1].replace(/\s+/g, ' ').trim());
    assert.ok(projections(receipt).length);
    for (const projection of projections(receipt)) assert.equal(projection, projections(physical)[0]);
  }
});

test('Item-linked Purchase local schema contains only canonical read facts with exact text cents', () => {
  const nativeSchema = readFileSync(new URL('../../LedgeriOS/LedgerTargetPowerSync/LedgerPowerSyncSchema.swift', import.meta.url), 'utf8');
  assert.match(nativeSchema, /static let transactions = "spike_transactions"/);
  const columns = nativeSchema.match(/Table\(name: LedgerPowerSyncTable.transactions,\s*columns: \[([\s\S]*?)\]/)?.[1];
  assert.ok(columns);
  assert.deepEqual([...columns.matchAll(/\.text\("([a-z_]+)"\)/g)].map(match => match[1]),
    ['account_id', 'project_id', 'client_id', 'type', 'role', 'amount_minor_units', 'currency', 'origin',
      'scope_kind', 'category_id', 'non_item_receipt_lines', 'source', 'transaction_date', 'created_at_ms',
      'notes', 'payment_method', 'details_revision', 'receipt_lines_revision', 'legacy_subtotal_minor_units', 'legacy_tax_rate_pct']);
  assert.deepEqual([...columns.matchAll(/\.integer\("([a-z_]+)"\)/g)].map(match => match[1]), ['has_email_receipt']);
});

test('overlapping Transaction streams preserve the same exact metadata projection', () => {
  const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
  const projections = [...yaml.matchAll(/SELECT spike_transactions\.id,([\s\S]*?)FROM spike_transactions/g)]
    .map(match => match[1].replace(/\s+/g, ' ').trim());
  assert.equal(projections.length, 3);
  assert.equal(projections[1], projections[0]); // Imported payments overlap.
  // Vendor rows are disjoint by origin and additionally own category/receipt
  // facts; their common display metadata must still have the same projection.
  assert.equal(projections[2].replace('spike_transactions.category_id, spike_transactions.non_item_receipt_lines, ', ''), projections[0]);
  assert.match(projections[0], /legacy_subtotal_minor_units::text AS legacy_subtotal_minor_units/);
  assert.match(projections[0], /legacy_tax_rate_pct::text AS legacy_tax_rate_pct/);
  assert.match(projections[0], /details_revision::text AS details_revision/);
});
