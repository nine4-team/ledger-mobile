// Exercise the pinned service's actual parameter evaluator with synthetic rows.
// This proves stream selection, not live replication or UI behavior.
import assert from 'node:assert/strict';
import { readFileSync, realpathSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
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
  fact('space_media_references',{id:'reference',account_id:'account',space_id:'space',set_revision:1,attachment_id:'photo'})
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
// The reference query may subscribe to an empty bucket for revision 2. Bucket
// existence is not row delivery; only the object lookup must disappear here.
assert.ok(stale[0] > 0 && stale[2] === 0, `revision change withdraws old object lookup: ${stale}`);
console.log('PASS Space media service parameter evaluation: current, foreign Account/Space/user, removed, archived visibility and stale revisions. Not live replication.');
