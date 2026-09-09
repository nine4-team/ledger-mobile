import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,realpathSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT);
const docker=args=>execFileSync('docker',args,{encoding:'utf8',timeout:10000});
assert.match(JSON.parse(docker(['context','inspect','--format','{{json .Endpoints.docker.Host}}'])),/^unix:\/\//);
const container='supabase_db_ledger_target_supabase_local';
const labels=JSON.parse(docker(['inspect','--format','{{json .Config.Labels}}',container]));
assert.equal(labels['com.supabase.cli.project'],'ledger_target_supabase_local');
assert.equal(realpathSync(labels['com.supabase.cli.workdir']),realpathSync(process.cwd()));
const block=readFileSync('powersync/sync-streams.yaml','utf8').match(/^  item_images:\n([\s\S]*?)(?=^  \S)/m)?.[1];
assert.ok(block);
const queries=[...block.matchAll(/^      - \|\n((?:        .*(?:\n|$))+)/gm)].map(m=>m[1].replace(/^        /gm,'').trim());
assert.equal(queries.length,3);
const q=s=>`'${s.replaceAll("'","''")}'`;
const item=`image-stream-${randomUUID()}`,other=`other-${randomUUID()}`,object=`object-${randomUUID()}`;
const statements=['begin;set local statement_timeout=\'5s\';'];
statements.push(`insert into public.spike_items(id,account_id,description,created_by_principal_id) values
 (${q(item)},'account-primary','Image','principal-owner'),(${q(other)},'account-primary','No image','principal-owner');`);
statements.push(`insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
 values (${q(object)},'account-primary',repeat('a',64),9007199254740993,'image/png',${q(`accounts/account-primary/attachments/${object}/`)}||repeat('a',64));`);
statements.push(`insert into public.item_image_sets values (${q(item)},'account-primary',${q(item)},2,1),(${q(other)},'account-primary',${q(other)},1,0);`);
statements.push(`insert into public.item_image_references values
 (${q(`ref-${item}`)},'account-primary',${q(item)},${q(object)},2,0,true),
 (${q(`old-${item}`)},'account-primary',${q(item)},${q(object)},1,0,true);set constraints all immediate;`);
function capture(label,user,account,requestedItem){
 queries.forEach((source,index)=>{
  const sql=source.replaceAll('auth.user_id()',`${q(user)}::uuid`)
   .replaceAll("subscription.parameter('account_id')",q(account))
   .replaceAll("subscription.parameter('item_id')",q(requestedItem));
  statements.push(`select json_build_object('label',${q(label)},'index',${index},'rows',coalesce(json_agg(row_to_json(t)),'[]')) from (${sql})t;`);
 });
}
const member='10000000-0000-0000-0000-000000000002';
capture('member',member,'account-primary',item);
capture('empty',member,'account-primary',other);
capture('foreign-account',member,'account-other',item);
capture('foreign-user','10000000-0000-0000-0000-000000000003','account-primary',item);
capture('wrong-item',member,'account-primary','absent');
statements.push("update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';");
capture('removed',member,'account-primary',item);
statements.push('rollback;');
const output=execFileSync('docker',['exec','-i',container,'psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],
 {input:statements.join('\n'),encoding:'utf8',timeout:30000});
const results=output.trim().split('\n').map(JSON.parse);
assert.equal(results.length,18);
for(const {label,index,rows} of results){
 if(label==='member'){
  assert.equal(rows.length,1);
  assert.equal(rows[0].account_id,'account-primary');
  if(index===0) assert.equal(rows[0].revision,'2');
  if(index===1){assert.equal(rows[0].id,`ref-${item}`);assert.equal(rows[0].set_revision,'2');}
  if(index===2){assert.equal(rows[0].id,object);assert.equal(rows[0].byte_count,'9007199254740993');}
 }else if(label==='empty' && index===0){assert.equal(rows.length,1);assert.equal(rows[0].expected_count,0);}
 else assert.deepEqual(rows,[],`${label}/${index}: no unauthorized or historical rows`);
}
console.log('item-image-stream:18 privileged actual SQL captures pass current revision,known empty,exact bytes,wrong Item,Account,user and removal;fixtures rolled back (not hosted replication)');
