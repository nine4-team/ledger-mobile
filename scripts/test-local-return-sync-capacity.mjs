// Synthetic evaluator inputs only; no database reads or writes.
import assert from 'node:assert/strict';
import {readFileSync,realpathSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT);
const docker=args=>execFileSync('docker',args,{encoding:'utf8',timeout:15000});
assert.match(JSON.parse(docker(['context','inspect','--format','{{json .Endpoints.docker.Host}}'])),/^unix:\/\//);
const mounts=JSON.parse(docker(['inspect','--format','{{json .Mounts}}','ledger_powersync_local']));
assert.ok(mounts.some(m=>m.Destination==='/config/sync-streams.yaml'
  && realpathSync(m.Source)===realpathSync('powersync/sync-streams.yaml')));
const facts=[];
const add=(schema,name,row)=>facts.push({table:{connectionTag:'default',schema,name},row});
add('public','spike_principals',{id:'actor',auth_user_id:'user'});
add('public','spike_account_memberships',{id:'membership',account_id:'account',principal_id:'actor',state:'active',financial_access:'full'});
add('public','spike_budget_categories',{id:'category',account_id:'account',visibility_class:'ordinary'});
const projectIds=Array.from({length:10},(_,i)=>`project-${i}`);
for(const project of projectIds) for(let i=0;i<700;i++) {
 const row={
  id:`${project}-charge-${i}`,account_id:'account',project_id:project,category_id:'category',
  item_id:`${project}-item-${i}`,placement_id:`${project}-placement-${i}`,revision:1,withdrawn_at:null};
 add('ledger_private','item_charge_occurrences',row);
 add('ledger_private','item_return_reviews',{...row,withdrawn:false,has_live_invoice:i%3===0,has_collected_invoice:i%3===1});
}
const result=execFileSync('docker',['exec','-i','ledger_powersync_local','node','--input-type=module','-e',
  readFileSync('scripts/evaluate-sync-parameter-budget.mjs','utf8')],{
  input:JSON.stringify({yaml:readFileSync('powersync/sync-streams.yaml','utf8'),stream:'item_return_review',facts,projectIds,
    diagnosticStack:process.argv.includes('--diagnostic-stack'),userId:'user',parameters:{account_id:'account',project_id:projectIds[0]}}),
  encoding:'utf8',timeout:15000});
console.log(result.trim());
for(const row of JSON.parse(result)) assert.equal(row.error,undefined,`Return stream query ${row.index} exceeds evaluator capacity`);
