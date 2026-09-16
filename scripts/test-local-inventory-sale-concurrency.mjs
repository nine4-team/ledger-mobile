import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {execFileSync, spawn} from 'node:child_process';
import {realpathSync} from 'node:fs';

assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT);
const container = 'supabase_db_ledger_target_supabase_local';
const docker = args => execFileSync('docker', args, {encoding:'utf8', timeout:15000});
assert.match(JSON.parse(docker(['context','inspect','--format','{{json .Endpoints.docker.Host}}'])), /^unix:\/\//);
const labels = JSON.parse(docker(['inspect','--format','{{json .Config.Labels}}',container]));
assert.equal(labels['com.supabase.cli.project'],'ledger_target_supabase_local');
assert.equal(realpathSync(labels['com.supabase.cli.workdir']),realpathSync(process.cwd()));
const args = ['exec','-i',container,'psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'];
const sql = input => execFileSync('docker',args,{input,encoding:'utf8',timeout:15000}).trim();
const key = 'sale-race-'+randomUUID();
const q = value => "'"+value.replaceAll("'","''")+"'";
const account=key+'-account', category=key+'-category', client=key+'-client', project=key+'-project', item=key+'-item', placement=key+'-old';
sql(`begin;
 insert into public.spike_accounts(id,display_name) values(${q(account)},'Synthetic sale concurrency');
 insert into public.spike_account_memberships(account_id,principal_id,role,state) values(${q(account)},'principal-owner','owner','active');
 insert into public.spike_clients(id,account_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
 values(${q(client)},${q(account)},'Synthetic',now(),now(),1,1,'principal-owner');
 insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
 values(${q(project)},${q(account)},${q(client)},'Synthetic',now(),now(),1,1,'principal-owner');
 insert into public.spike_budget_categories(id,account_id,display_name,kind,presentation_order,created_at_ms,updated_at_ms)
 values(${q(category)},${q(account)},'Furnishings','itemized',0,1,1);
 update public.spike_accounts set furnishings_category_id=${q(category)} where id=${q(account)};
 insert into public.spike_items(id,account_id,description,created_by_principal_id) values(${q(item)},${q(account)},'Race Item','principal-owner');
 insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
 values(${q(placement)},${q(account)},${q(item)},'business_inventory','2026-01-01','principal-owner');
 insert into ledger_private.item_project_prices(account_id,item_id,amount_minor_units,currency,updated_at,updated_by_principal_id)
 values(${q(account)},${q(item)},12345,'USD',now(),'principal-owner'); commit;`);

const children=[];
function session() {
 const child=spawn('docker',args,{stdio:['pipe','pipe','pipe']}); children.push(child);
 let out='',err=''; child.stdout.on('data',b=>out+=b); child.stderr.on('data',b=>err+=b);
 const done=new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',code=>code===0?resolve(out.trim()):reject(Error(err)));});
 // Attach immediately, including for the lock-holder which is awaited later.
 done.catch(()=>{});
 return {child,done,output:()=>out};
}
const waitFor=async condition=>{
 const deadline=Date.now()+10000;
 while(!condition()) {assert.ok(Date.now()<deadline,'Timed out waiting for actual database lock'); await new Promise(r=>setTimeout(r,50));}
};
try {
 const blocker=session();
 blocker.child.stdin.write(`begin; select id from public.spike_items where id=${q(item)} for update;\n\\echo LOCKED\n`);
 await waitFor(()=>blocker.output().includes('LOCKED'));
 const run=suffix=>{
  const command=JSON.stringify({operationId:key+'-'+suffix,accountId:account,actorPrincipalId:'principal-owner',projectId:project,
   contractVersion:'inventory-sale-v1',createdAtMs:'1788523200000',currency:'USD',items:[{itemId:item,placementId:placement,priceRevision:'1',reviewedPriceMinorUnits:'12345',newPlacementId:key+'-new-'+suffix,occurrenceId:key+'-charge-'+suffix}]});
  const s=session();
  s.child.stdin.end(`set application_name=${q(key+'-'+suffix)}; set request.jwt.claims='{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}'; select (ledger_private.sell_inventory_items(${q(command)})).phase;`);
  return s.done;
 };
 const first=run('a'),second=run('b');
 await waitFor(()=>sql(`select count(*) from pg_stat_activity where application_name in (${q(key+'-a')},${q(key+'-b')}) and wait_event_type='Lock'`)==='2');
 blocker.child.stdin.end('commit;\n');
 await blocker.done;
 assert.deepEqual((await Promise.all([first,second])).sort(),['applied','rejected']);
 assert.equal(sql(`select count(*) from public.spike_item_placements where account_id=${q(account)} and ended_at is null`),'1');
 assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)}`),'1');
 assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'0');
 assert.equal(sql(`select error_code from public.spike_operation_results where account_id=${q(account)} and phase='rejected'`),'sale_placement_stale');
 // Exercise the inverse physical movement against the exact successful sale.
 // Both real sessions must wait on the same Item before either can proceed.
 const currentPlacement=sql(`select id from public.spike_item_placements where account_id=${q(account)} and ended_at is null`);
 const charge=sql(`select id from ledger_private.item_charge_occurrences where account_id=${q(account)}`);
 const returnBlocker=session();
 returnBlocker.child.stdin.write(`begin; select id from public.spike_items where id=${q(item)} for update;\n\\echo RETURN_LOCKED\n`);
 await waitFor(()=>returnBlocker.output().includes('RETURN_LOCKED'));
 const runReturn=suffix=>{
  const command=JSON.stringify({operationId:key+'-return-'+suffix,accountId:account,actorPrincipalId:'principal-owner',
   projectId:project,contractVersion:'return-uninvoiced-items-v1',createdAtMs:'1788523200000',items:[{
    itemId:item,placementId:currentPlacement,chargeId:charge,expectedChargeRevision:'1',
    inventoryPlacementId:key+'-inventory-'+suffix,returnOccurrenceId:key+'-return-fact-'+suffix}]});
  const s=session();
  s.child.stdin.end(`set application_name=${q(key+'-return-'+suffix)}; set role authenticated;
   set request.jwt.claims='{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
   select (public.spike_return_uninvoiced_items(${q(command)})).phase;`);
  return s.done;
 };
 const returnA=runReturn('a'),returnB=runReturn('b');
 await waitFor(()=>sql(`select count(*) from pg_stat_activity where application_name in
   (${q(key+'-return-a')},${q(key+'-return-b')}) and wait_event_type='Lock'`)==='2');
 returnBlocker.child.stdin.end('commit;\n');
 await returnBlocker.done;
 assert.deepEqual((await Promise.all([returnA,returnB])).sort(),['applied','rejected']);
 assert.equal(sql(`select count(*) from ledger_private.uninvoiced_item_returns where account_id=${q(account)} and charge_id=${q(charge)}`),'1');
 assert.equal(sql(`select count(*) from public.spike_item_placements where account_id=${q(account)} and ended_at is null and scope_kind='business_inventory'`),'1');
 assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where id=${q(charge)} and withdrawn_at is not null and revision=2 and amount_minor_units=12345`),'1');
 assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'0');
 assert.equal(sql(`select error_code from public.spike_operation_results where account_id=${q(account)} and command_type='return_uninvoiced_items' and phase='rejected'`),'return_placement_stale');
 // Hold the first successful mutation uncommitted while the other operation
 // contends on its source lock. Exercise both winners, not a timing-only race.
 sql(`update public.spike_account_memberships set financial_access='full' where account_id=${q(account)} and principal_id='principal-owner';`);
 for(const winner of ['return','invoice']) {
  const raceItem=key+'-'+winner+'-item', old=key+'-'+winner+'-old', placed=key+'-'+winner+'-placed';
  const source=key+'-'+winner+'-source', invoice=key+'-'+winner+'-invoice';
  sql(`begin;
   insert into public.spike_items(id,account_id,description,created_by_principal_id) values(${q(raceItem)},${q(account)},'Invoice return race','principal-owner');
   insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,ended_at,started_by_principal_id,ended_by_principal_id)
   values(${q(old)},${q(account)},${q(raceItem)},'business_inventory','2025-01-01','2026-01-01','principal-owner','principal-owner');
   insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
   values(${q(placed)},${q(account)},${q(raceItem)},'project',${q(project)},'2026-01-01','principal-owner');
   insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,created_at,created_by_principal_id)
   values(${q(source)},${q(account)},${q(project)},${q(raceItem)},${q(placed)},${q(category)},12345,'USD','2026-01-01','principal-owner'); commit;`);
  const base={accountId:account,actorPrincipalId:'principal-owner',projectId:project,createdAtMs:'1788523200000'};
  const returning=JSON.stringify({...base,operationId:key+'-'+winner+'-return-op',contractVersion:'return-uninvoiced-items-v1',items:[{
   itemId:raceItem,placementId:placed,chargeId:source,expectedChargeRevision:'1',inventoryPlacementId:key+'-'+winner+'-inventory',returnOccurrenceId:key+'-'+winner+'-return-fact'}]});
  const invoicing=JSON.stringify({...base,operationId:key+'-'+winner+'-invoice-op',contractVersion:'invoice-create-v1',clientId:client,
   invoiceId:invoice,name:'Race invoice',notes:'',sources:[{kind:'item',sourceId:source,expectedRevision:'1',amountMinorUnits:'12345',currency:'USD'}]});
  const calls={return:`select (public.spike_return_uninvoiced_items(${q(returning)})).phase;`,
   invoice:`select (public.spike_create_invoice(${q(invoicing)})).phase;`};
  const auth=`set role authenticated; set request.jwt.claims='{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';`;
  const holding=session();
  holding.child.stdin.write(`begin; ${auth} ${calls[winner]}\n\\echo WINNER_PENDING\n`);
  await waitFor(()=>holding.output().includes('WINNER_PENDING'));
  assert.match(holding.output(),/applied/);
  const loser=winner==='return'?'invoice':'return';
  const waiting=session(), application=key+'-'+winner+'-waiter';
  waiting.child.stdin.end(`set application_name=${q(application)}; ${auth} ${calls[loser]}`);
  await waitFor(()=>sql(`select count(*) from pg_stat_activity where application_name=${q(application)} and wait_event_type='Lock'`)==='1');
  holding.child.stdin.end('commit;\n');
  await holding.done;
  assert.equal(await waiting.done,'rejected');
  assert.equal(sql(`select count(*) from ledger_private.live_invoice_memberships where account_id=${q(account)} and source_id=${q(source)} and released_at is null`),winner==='invoice'?'1':'0');
  assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where id=${q(source)} and withdrawn_at is not null`),winner==='return'?'1':'0');
  assert.equal(sql(`select withdrawn::text||':'||has_live_invoice::text||':'||has_collected_invoice::text from ledger_private.item_return_reviews where id=${q(source)}`),
   winner==='return'?'true:false:false':'false:true:false');
  assert.equal(sql(`select scope_kind from public.spike_item_placements where account_id=${q(account)} and item_id=${q(raceItem)} and ended_at is null`),winner==='return'?'business_inventory':'project');
  assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'0');
 }
 // Two independent purchase receipts for one Item must leave ambiguous cost,
 // even when the second statement started before the first committed.
 const reviewItem=key+'-review-item';
 sql(`insert into public.spike_items(id,account_id,description,created_by_principal_id)
   values(${q(reviewItem)},${q(account)},'Concurrent acquisition','principal-owner');
   insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
   values(${q(key+'-purchase-a')},${q(account)},100,'USD','purchase','vendor_payment','business_inventory',${q(category)}),
         (${q(key+'-purchase-b')},${q(account)},200,'USD','purchase','vendor_payment','business_inventory',${q(category)});`);
 const receiptInsert=(suffix,amount)=>`insert into public.transaction_receipt_items
   (id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
   values(${q(key+'-receipt-'+suffix)},${q(account)},${q(key+'-purchase-'+suffix)},${q(reviewItem)},'USD',${amount},'linked');`;
 const acquisitionA=session();
 acquisitionA.child.stdin.write(`begin; ${receiptInsert('a',100)}\n\\echo ACQUISITION_LOCKED\n`);
 await waitFor(()=>acquisitionA.output().includes('ACQUISITION_LOCKED'));
 const acquisitionB=session();
 acquisitionB.child.stdin.end(`set application_name=${q(key+'-acquisition-b')}; ${receiptInsert('b',200)}`);
 await waitFor(()=>sql(`select count(*) from pg_stat_activity where application_name=${q(key+'-acquisition-b')} and wait_event_type='Lock'`)==='1');
 acquisitionA.child.stdin.end('commit;\n');
 await Promise.all([acquisitionA.done,acquisitionB.done]);
 assert.equal(sql(`select state||':'||(amount_minor_units is null)::text from ledger_private.item_acquisition_reviews where id=${q(reviewItem)}`),'unavailable:true');
 sql(`delete from public.transaction_receipt_items where id=${q(key+'-receipt-a')} and account_id=${q(account)};`);
 assert.equal(sql(`select state||':'||amount_minor_units::text from ledger_private.item_acquisition_reviews where id=${q(reviewItem)}`),'known:200');
 console.log(JSON.stringify({twoSessionsObservedBlocked:true,applied:1,rejected:1,currentPlacements:1,charges:1,saleCreatedPayments:0,
   returnSessionsObservedBlocked:true,returnApplied:1,returnRejected:1,returnFacts:1,returnVsInvoiceBothCommitOrders:true,
   acquisitionRefreshAfterConcurrentCommit:'unavailable',acquisitionRefreshAfterRemoval:'known:200',fixtureAccount:account}));
} finally {
 for(const child of children) if(child.exitCode===null) {child.stdin.end();child.kill('SIGTERM');}
 // Retain accounting evidence, but do not contaminate the shared user's
 // account-discovery fixtures after this test finishes (including failures).
 sql(`update public.spike_account_memberships set state='removed'
   where account_id=${q(account)} and principal_id='principal-owner';`);
}
