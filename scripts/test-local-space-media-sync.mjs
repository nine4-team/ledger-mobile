// Exercise the pinned service's actual parameter evaluator with synthetic rows.
// This proves stream selection, not live replication or UI behavior.
import assert from 'node:assert/strict';
import { readFileSync, realpathSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT);
const docker = args => execFileSync('docker', args, { encoding: 'utf8', timeout: 15000 });
assert.match(JSON.parse(docker(['context','inspect','--format','{{json .Endpoints.docker.Host}}'])), /^unix:\/\//);
const mounts = JSON.parse(docker(['inspect','--format','{{json .Mounts}}','ledger_powersync_local']));
assert.ok(mounts.some(m => m.Destination === '/config/sync-streams.yaml'
  && realpathSync(m.Source) === realpathSync('powersync/sync-streams.yaml')));
const fact = (name, row) => ({table: {connectionTag:'default',schema:'public',name},row});
const facts = [
  fact('spike_principals',{id:'actor',auth_user_id:'user'}),
  fact('spike_account_memberships',{id:'member',account_id:'account',principal_id:'actor',state:'active',financial_access:'limited'}),
  fact('spike_spaces',{id:'space',account_id:'account',lifecycle:'active',sync_current_item_count:0}),
  fact('space_media_sets',{id:'set',account_id:'account',space_id:'space',revision:1,expected_count:1}),
  fact('space_media_references',{id:'reference',account_id:'account',space_id:'space',set_revision:1,attachment_id:'photo',sync_is_current:true})
];
function evaluate(rows = facts, parameters = {account_id:'account',space_id:'space'}, userId = 'user') {
  const output = execFileSync('docker',['exec','-i','ledger_powersync_local','node','--input-type=module','-e',
    readFileSync('scripts/evaluate-sync-parameter-budget.mjs','utf8')], {encoding:'utf8',timeout:15000,
    input:JSON.stringify({yaml:readFileSync('powersync/sync-streams.yaml','utf8'),stream:'space_media',facts:rows,parameters,userId})});
  const results = JSON.parse(output).filter(r => r.index !== 'combined');
  assert.equal(results.length,3);
  for (const result of results) assert.equal(result.error,undefined);
  return results.map(r => r.buckets);
}
const change = (table, patch) => facts.map(f => f.table.name === table ? {...f,row:{...f.row,...patch}} : f);
assert.ok(evaluate().every(n => n > 0), 'limited member sees current ordinary Space media');
for (const values of [
  evaluate(facts,{account_id:'foreign',space_id:'space'}),
  evaluate(facts,{account_id:'account',space_id:'other'}),
  evaluate(facts,undefined,'other-user'),
  evaluate(change('spike_account_memberships',{state:'removed'})),
  evaluate(change('spike_spaces',{lifecycle:'archived'}))
]) assert.ok(values.every(n => n === 0), 'foreign, removed and inaccessible archived scopes deny');
assert.ok(evaluate(change('spike_spaces',{lifecycle:'archived',sync_current_item_count:1})).every(n => n > 0),
  'archived current physical parent stays readable');
const stale = evaluate(change('space_media_sets',{revision:2,expected_count:0}));
// Scope buckets intentionally survive revision changes. SQL routing tests prove
// stale reference/object rows withdraw inside them; no attachment parameter rows.
assert.ok(stale.every(n => n > 0), `revision change retains fixed scope buckets: ${stale}`);
console.log('PASS Space media service parameter evaluation: current, foreign Account/Space/user, removed, archived visibility and revision-independent scope buckets. Not live replication.');

if (process.argv.includes('--live')) {
  const local = JSON.parse(execFileSync('npx',['--offline','--yes','supabase@2.116.0','status','-o','json'],
    {encoding:'utf8',stdio:['ignore','pipe','ignore'],timeout:15000}));
  assert.equal(local.API_URL,'http://127.0.0.1:54321');
  const container = 'supabase_db_ledger_target_supabase_local';
  const labels = JSON.parse(docker(['inspect','--format','{{json .Config.Labels}}',container]));
  assert.equal(realpathSync(labels['com.supabase.cli.workdir']),realpathSync(process.cwd()));
  const sql = input => execFileSync('docker',['exec','-i',container,'psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],
    {input,encoding:'utf8',timeout:15000,stdio:['pipe','pipe','pipe']});
  const id = 'space-media-' + randomUUID(), now = Math.floor(Date.now()/1000);
  assert.equal(sql("select count(*) from pg_publication_tables where pubname='powersync' and schemaname='public' and tablename in ('space_media_sets','space_media_references');").trim(), '2',
    'Space media tables must be published before testing live replication');
  assert.equal(sql("select count(*) from pg_publication_tables where pubname='powersync' and schemaname='ledger_private' and tablename in ('media_sync_objects','media_sync_thumbnails');").trim(), '2',
    'Scoped media projections must be published before testing live replication');
  const unsigned = [{alg:'HS256',typ:'JWT'},{aud:'authenticated',role:'authenticated',
    sub:'10000000-0000-0000-0000-000000000002',iat:now,exp:now+120}]
    .map(v => Buffer.from(JSON.stringify(v)).toString('base64url')).join('.');
  const token = unsigned + '.' + createHmac('sha256',local.JWT_SECRET).update(unsigned).digest('base64url');
  const controller = new AbortController(), timer = setTimeout(() => controller.abort(),30000);
  let created = false;
  try {
    sql(`begin;
      insert into public.spike_accounts(id,display_name) values('${id}','Synthetic Space media');
      insert into public.spike_account_memberships(account_id,principal_id,role,state,financial_access)
        values('${id}','principal-restricted','employee','active','limited');
      insert into public.spike_spaces(id,account_id,scope_kind,display_name) values('${id}','${id}','business_inventory','Synthetic Space');
      insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
        values('${id}','${id}',repeat('a',64),4,'image/jpeg','accounts/${id}/attachments/${id}/'||repeat('a',64));
      insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
        values('${id}-pdf','${id}',repeat('b',64),8,'application/pdf','accounts/${id}/attachments/${id}-pdf/'||repeat('b',64));
      insert into public.space_media_sets values('${id}','${id}','${id}',1,2);
      insert into public.space_media_references values('${id}','${id}','${id}','${id}',1,0,true,'Synthetic.jpg');
      insert into public.space_media_references values('${id}-pdf','${id}','${id}','${id}-pdf',1,1,false,'Synthetic.pdf');
      insert into public.spike_clients(id,account_id,display_name,lifecycle,revision,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
        values('${id}','${id}','Synthetic media client','active',1,'2026-09-05T12:00:00Z','2026-09-05T12:00:00Z',1788609600000,1788609600000,'principal-restricted');
      insert into public.spike_projects(id,account_id,client_id,display_name,lifecycle,revision,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
        values('${id}','${id}','${id}','Synthetic media project','active',1,'2026-09-05T12:00:00Z','2026-09-05T12:00:00Z',1788609600000,1788609600000,'principal-restricted');
      insert into public.spike_items(id,account_id,description,created_by_principal_id) values('${id}','${id}','Synthetic media Item','principal-restricted');
      insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
        values('${id}','${id}','${id}','project','${id}','2026-09-18','principal-restricted');
      insert into public.item_image_sets(id,account_id,item_id,revision,expected_count) values('${id}','${id}','${id}',1,1);
      insert into public.item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary)
        values('${id}','${id}','${id}','${id}',1,0,true);
      commit;`);
    created = true;
    const response = await fetch('http://127.0.0.1:5590/sync/stream',{method:'POST',signal:controller.signal,
      headers:{Authorization:'Bearer '+token,'Content-Type':'application/json',Accept:'application/x-ndjson'},
      body:JSON.stringify({buckets:[],raw_data:true,client_id:id,streams:{include_defaults:false,
        subscriptions:[{stream:'space_media',override_priority:null,parameters:{account_id:id,space_id:id}},
          {stream:'project_item_images',override_priority:null,parameters:{account_id:id,project_id:id}}]}})});
    assert.equal(response.status,200);
    const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
    let pending = '', buckets = new Set(), received = new Set(), stage = 'download', removed = false, pdfReceived = false;
    try {
      while (!removed) {
        const chunk = await reader.read(); if (chunk.done) break;
        pending += chunk.value; const lines = pending.split('\n'); pending = lines.pop();
        for (const line of lines.filter(v => v.trim())) {
          const message = JSON.parse(line); assert.ok(!message.error);
          if (message.checkpoint) {
            for (const stream of message.checkpoint.streams ?? []) assert.deepEqual(stream.errors,[]);
            buckets = new Set(message.checkpoint.buckets.map(b => b.bucket));
          }
          if (message.checkpoint_diff) {
            for (const bucket of message.checkpoint_diff.removed_buckets ?? []) buckets.delete(bucket);
            for (const bucket of message.checkpoint_diff.updated_buckets ?? []) buckets.add(bucket.bucket);
          }
          for (const row of message.data?.data ?? []) if (row.op === 'PUT') {
            assert.ok(row.object_id===id || row.object_id===`${id}-pdf`,'No foreign media delivered');
            const data = typeof row.data === 'string' ? JSON.parse(row.data) : row.data;
            assert.equal(data.account_id,id);
            if (row.object_type==='item_image_objects' && row.object_id===`${id}-pdf`) {
              assert.equal(data.media_type,'application/pdf'); assert.equal(data.byte_count,'8');
              assert.equal(data.content_sha256,'b'.repeat(64)); pdfReceived=true;
            }
            received.add(row.object_type);
          }
          if (message.checkpoint_complete) {
            if (stage === 'download' && pdfReceived && ['space_media_sets','space_media_references','item_image_objects','item_image_sets','item_image_references'].every(t => received.has(t))) {
              sql(`update public.spike_account_memberships set state='removed' where account_id='${id}';`);
              stage = 'withdraw';
            } else if (stage === 'withdraw' && buckets.size === 0) removed = true;
          }
        }
      }
    } finally { await reader.cancel().catch(() => {}); }
    assert.ok(removed,'Same-session removal must withdraw every Space media bucket');
    console.log('PASS live Space + Project Item media: exact catalogs/references/shared object downloaded and same-session membership removal withdrew all buckets. Synthetic metadata only; no Storage bytes or native app proof.');
  } finally {
    clearTimeout(timer); controller.abort();
    if (created) sql(`update public.spike_account_memberships set state='removed' where account_id='${id}';`);
  }
}
