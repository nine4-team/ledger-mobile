// Synthetic inputs to the existing pinned PowerSync parameter evaluator.
import assert from 'node:assert/strict';
import {readFileSync,realpathSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHmac,randomUUID} from 'node:crypto';
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
for(let p=0;p<10;p++) for(let i=0;i<700;i++) {
  add('ledger_private','collected_invoice_lines',{id:`line-${p}-${i}`,account_id:'account',
    invoice_id:`invoice-${p}`,item_id:i===0?'selected-item':`item-${p}-${i}`,source_kind:'item'});
}
function evaluate(parameters, changedFacts=facts, userId='user') {
  const result=JSON.parse(execFileSync('docker',['exec','-i','ledger_powersync_local','node','--input-type=module','-e',
    readFileSync('scripts/evaluate-sync-parameter-budget.mjs','utf8')],{
      input:JSON.stringify({yaml:readFileSync('powersync/sync-streams.yaml','utf8'),stream:'item_invoice_history',
        facts:changedFacts,userId,parameters}),encoding:'utf8',timeout:15000}));
  for(const row of result) assert.equal(row.error,undefined,`query ${row.index}: ${row.error}`);
  return result.filter(row=>row.index!=='combined');
}
const parameters={account_id:'account',item_id:'selected-item'};
const allowed=evaluate(parameters);
assert.equal(allowed.length,2);
assert.ok(allowed.every(row=>row.buckets>0));
assert.ok(evaluate({...parameters,item_id:'item-0-1'}).every(row=>row.buckets===1),
  'Another existing Item receives only its containing Invoice, not the selected Item history');
for(const [name,params,rows,user] of [
  ['other Account',{...parameters,account_id:'other'},facts,'user'],
  ['unknown Item',{...parameters,item_id:'missing'},facts,'user'],
  ['different user',parameters,facts,'other-user'],
  ['removed membership',parameters,facts.map(f=>f.table.name==='spike_account_memberships'?{...f,row:{...f.row,state:'removed'}}:f),'user'],
  ['limited access',parameters,facts.map(f=>f.table.name==='spike_account_memberships'?{...f,row:{...f.row,financial_access:'limited'}}:f),'user']
]) assert.ok(evaluate(params,rows,user).every(row=>row.buckets===0),name);
console.log('PASS Item history: 7,000 lines/10 Invoices; allowed exact Item, denied foreign Account/user, absent Item, removed/limited membership.');
console.log(JSON.stringify(allowed));

if(process.argv.includes('--live')) {
  const local=JSON.parse(execFileSync('npx',['--offline','--yes','supabase@2.116.0','status','-o','json'],
    {encoding:'utf8',stdio:['ignore','pipe','ignore']}));
  assert.equal(local.API_URL,'http://127.0.0.1:54321');
  const container='supabase_db_ledger_target_supabase_local';
  const labels=JSON.parse(docker(['inspect','--format','{{json .Config.Labels}}',container]));
  assert.equal(realpathSync(labels['com.supabase.cli.workdir']),realpathSync(process.cwd()));
  const sql=input=>execFileSync('docker',['exec','-i',container,'psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],
    {input,encoding:'utf8',stdio:['pipe','pipe','pipe']});
  const id='invoice-history-'+randomUUID(), now=Math.floor(Date.now()/1000);
  const unsigned=[{alg:'HS256',typ:'JWT'},{aud:'authenticated',role:'authenticated',
    sub:'10000000-0000-0000-0000-000000000002',iat:now,exp:now+120}].map(v=>Buffer.from(JSON.stringify(v)).toString('base64url')).join('.');
  const token=unsigned+'.'+createHmac('sha256',local.JWT_SECRET).update(unsigned).digest('base64url');
  const invoice={invoice_id:id,invoice_revision:'1',account_id:id,project_id:id,client_id:id,purchase_id:id,
    currency:'USD',total_minor_units:'50',lines:[{id,line_position:0,source_kind:'item',source_id:id,item_id:id,
      source_revision:'1',category_id:'furnishings',signed_amount_minor_units:'50',description:'Historical chair',
      source_snapshot_json:JSON.stringify({item:{itemId:id,occurrenceId:id,price:{basis:{importedInvoiceAmount:{}},amount:{minorUnits:50,currency:'USD'}}}})}]};
  const source=[{source_document_id:id,source_line_id:id,source_bytes:'\\x02',line_source_bytes:'\\x03'}];
  const payment={p_id:id,p_account_id:id,p_project_id:id,p_client_id:id,p_amount:'50',p_currency:'USD',
    p_source_account:id,p_source_document:id,p_source_bytes:'\\x01'};
  const controller=new AbortController(), timer=setTimeout(()=>controller.abort(),30000);
  try {
    sql(`begin;
      insert into public.spike_accounts(id,display_name) values('${id}','Synthetic Invoice history');
      insert into public.spike_account_memberships(account_id,principal_id,role,state,financial_access)
        values('${id}','principal-restricted','employee','active','full');
      insert into public.spike_clients(id,account_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
        values('${id}','${id}','Synthetic',now(),now(),1,1,'principal-restricted');
      insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
        values('${id}','${id}','${id}','Synthetic',now(),now(),1,1,'principal-restricted');
      insert into public.spike_items(id,account_id,description,created_by_principal_id) values('${id}','${id}','Current chair','principal-restricted');
      do $$ begin
        perform ledger_private.import_client_payment('${id}','${id}','${id}','${id}',50,'USD','${id}','${id}',decode('01','hex'));
        perform ledger_private.import_invoice_sources('${JSON.stringify(invoice)}','${JSON.stringify(source)}',
          '${JSON.stringify(payment)}','${id}','${id}',decode('04','hex'));
      end $$;
      commit;`);
    const response=await fetch('http://127.0.0.1:5590/sync/stream',{method:'POST',signal:controller.signal,
      headers:{Authorization:'Bearer '+token,'Content-Type':'application/json',Accept:'application/x-ndjson'},
      body:JSON.stringify({buckets:[],raw_data:true,client_id:id,streams:{include_defaults:false,
        subscriptions:[{stream:'item_invoice_history',override_priority:null,parameters:{account_id:id,item_id:id}}]}})});
    assert.equal(response.status,200);
    const reader=response.body.pipeThrough(new TextDecoderStream()).getReader();
    let pending='', buckets=new Set(), received=new Set(), stage='download', removed=false;
    try {
      while(!removed) {
        const chunk=await reader.read(); if(chunk.done) break;
        pending+=chunk.value; const lines=pending.split('\n'); pending=lines.pop();
        for(const text of lines.filter(v=>v.trim())) {
          const message=JSON.parse(text); assert.ok(!message.error);
          if(message.checkpoint) {
            for(const stream of message.checkpoint.streams??[]) assert.deepEqual(stream.errors,[]);
            buckets=new Set(message.checkpoint.buckets.map(b=>b.bucket));
          }
          if(message.checkpoint_diff) {
            for(const bucket of message.checkpoint_diff.removed_buckets??[]) buckets.delete(bucket);
            for(const bucket of message.checkpoint_diff.updated_buckets??[]) buckets.add(bucket.bucket);
          }
          for(const row of message.data?.data??[]) if(row.op==='PUT') {
            assert.equal(row.object_id,id,'No foreign record delivered');
            received.add(row.object_type);
          }
          if(message.checkpoint_complete) {
            if(stage==='download' && received.has('collected_invoices') && received.has('collected_invoice_lines')) {
              sql(`update public.spike_account_memberships set financial_access='limited' where account_id='${id}';`);
              stage='withdraw';
            } else if(stage==='withdraw' && buckets.size===0) removed=true;
          }
        }
      }
    } finally { await reader.cancel().catch(()=>{}); }
    assert.ok(removed,'Live checkpoint must withdraw all Invoice history after financial access removal');
    console.log('PASS live Item Invoice history: actual imported header/line downloaded; same-session financial withdrawal removed buckets.');
  } finally {
    clearTimeout(timer); controller.abort();
    sql(`update public.spike_account_memberships set state='removed' where account_id='${id}';`);
  }
}
