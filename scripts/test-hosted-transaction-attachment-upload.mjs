// Explicit private Ledger QA only. Reuses the native interrupted-TUS test;
// retains one labeled test attachment, never touches Firebase or real users.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

assert.equal(process.cwd(),'/Users/benjaminmackenzie/Dev/ledger_mobile_supabase');
const expenseEditFlow=process.argv.includes('--expense-edit-flow');
const invoiceFlow=process.argv.includes('--invoice-flow');
const feeFlow=process.argv.includes('--fee-flow');
const returnFlow=process.argv.includes('--return-flow');
const expenseFlow=feeFlow||invoiceFlow||expenseEditFlow||process.argv.includes('--expense-flow');
const expenseMode=expenseFlow||process.argv.includes('--expense');
assert.deepEqual(process.argv.slice(2),returnFlow?['--apply','--return-flow']:expenseMode?['--apply',feeFlow?'--fee-flow':invoiceFlow?'--invoice-flow':expenseEditFlow?'--expense-edit-flow':expenseFlow?'--expense-flow':'--expense']:['--apply']);
// Load the existing MCP implementations before opening a QA session.
const expenseAPI=expenseFlow?await import('../LedgerTargetMCP/src/expenseCreation.ts'):null;
const projectAPI=expenseFlow?await import('../LedgerTargetMCP/src/projectCreation.ts'):null;
const invoiceAPI=invoiceFlow?await import('../LedgerTargetMCP/src/liveInvoiceRead.ts'):null;
const feeAPI=feeFlow?await import('../LedgerTargetMCP/src/feeRead.ts'):null;
const categoryAPI=feeFlow?await import('../LedgerTargetMCP/src/categoryManagement.ts'):null;
const auth=JSON.parse(fs.readFileSync('tmp/ledger-hosted-qa/auth.json'));
assert.equal(auth.userId,'5cb9aa33-337a-4fd4-a33f-121119e04c4e');
assert.equal(auth.principalId,'upload-http-owner-4b1e9766-5791-48a9-a7b1-15a541807e64');
assert.ok(auth.email.endsWith('@ledger-tests.invalid'));
const base='https://ybwviepljilrkrjoahbl.supabase.co';
const apikey='sb_publishable_oAx8Wobv1rd1OZ9m_nrE1A_bOuo1T-H';
const account='realcopy-b9d236394770-account';
const request=(path,options={})=>fetch(base+path,{redirect:'error',signal:AbortSignal.timeout(30000),...options});
const login=await request('/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey,'content-type':'application/json'},body:JSON.stringify({email:auth.email,password:auth.password})});
assert.equal(login.status,200,'QA login failed');
const session=await login.json();
const headers={apikey,Authorization:'Bearer '+session.access_token,'content-type':'application/json'};
const read=async path=>{const r=await request(path,{headers});assert.equal(r.status,200,'QA read failed');return r.json();};
try {
  const memberships=await read('/rest/v1/spike_account_memberships?account_id=eq.'+account+'&select=principal_id,role,state,financial_access,can_manage_projects,can_manage_project_budgets');
  assert.deepEqual(memberships.map(({principal_id,role,state})=>({principal_id,role,state})),
    [{principal_id:auth.principalId,role:'owner',state:'active'}]);
  if(returnFlow) {
    assert.ok(['none','full'].includes(memberships[0].financial_access));
    const clients=await read('/rest/v1/spike_clients?account_id=eq.'+account+'&lifecycle=eq.active&select=id&order=id&limit=1');
    const accounts=await read('/rest/v1/spike_accounts?id=eq.'+account+'&select=furnishings_category_id');
    assert.equal(clients.length,1);assert.equal(accounts.length,1);
    assert.equal(typeof accounts[0].furnishings_category_id,'string');
    const id='hosted-return-flow-'+crypto.randomUUID(),project=id+'-project',item=id+'-item';
    const q=value=>"'"+value.replaceAll("'","''")+"'";
    // Administrative fixture setup only. All sale/return mutations below use
    // the native signed-in QA member and normal command endpoints.
    const sql=query=>{
      const result=spawnSync('npx',['--yes','supabase@2.116.0','db','query','--linked','--project-ref','ybwviepljilrkrjoahbl',query],{encoding:'utf8',timeout:30000});
      assert.equal(result.status,0,'Hosted synthetic setup/reconciliation failed');
      return JSON.parse(result.stdout).rows;
    };
    sql(`begin;
      insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
      values(${q(project)},${q(account)},${q(clients[0].id)},'QA — hosted Item return',now(),now(),1,1,${q(auth.principalId)});
      insert into public.spike_items(id,account_id,description,created_by_principal_id)
      values(${q(item)},${q(account)},'QA synthetic return Item',${q(auth.principalId)});
      insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id,start_evidence)
      values(${q(id+'-initial')},${q(account)},${q(item)},'business_inventory','2026-01-01',${q(auth.principalId)},'import_observation');
      commit; select true as seeded;`);
    console.log(JSON.stringify({hostedReturnStarted:true,project,item}));
    const env={...process.env,LEDGER_RETURN_HOSTED_QA:'1',LEDGER_RETURN_LOCAL:'1',
      LEDGER_SALE_LOCAL_ACCOUNT:account,LEDGER_SALE_LOCAL_PRINCIPAL:auth.principalId,
      LEDGER_SALE_LOCAL_ITEM:item,LEDGER_SALE_LOCAL_PROJECT:project,LEDGER_SALE_LOCAL_KEY:apikey,
      LEDGER_SALE_LOCAL_EMAIL:auth.email,LEDGER_SALE_LOCAL_PASSWORD:auth.password,
      LEDGER_SALE_LOCAL_FINANCIAL_ACCESS:memberships[0].financial_access,LEDGER_RETURN_LOCAL_PROJECT_COUNT:'1'};
    delete env.LEDGER_RESALE_LOCAL;delete env.LEDGER_RESALE_PROJECT;
    const run=spawnSync('swift',['test','--package-path','LedgeriOS','--no-parallel','--filter',
      'AccountWorkspacePendingWorkRuntimeTests/inventorySaleLiveReplication'],{encoding:'utf8',timeout:180000,env});
    process.stdout.write(run.stdout??'');process.stderr.write(run.stderr??'');
    assert.equal(run.status,0,'Hosted native return failed');
    assert.match(run.stdout+run.stderr,/Test run with 1 test.*passed/);
    const [facts]=sql(`select
      (select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)} and item_id=${q(item)} and withdrawn_at is not null and amount_minor_units=12345) as withdrawn,
      (select count(*) from ledger_private.uninvoiced_item_returns where account_id=${q(account)} and item_id=${q(item)}) as returns,
      (select count(*) from public.spike_item_placements where account_id=${q(account)} and item_id=${q(item)} and ended_at is null and scope_kind='business_inventory') as inventory,
      (select count(*) from public.spike_transactions where account_id=${q(account)} and project_id=${q(project)}) as payments;`);
    assert.deepEqual(facts,{withdrawn:1,returns:1,inventory:1,payments:0});
    console.log(JSON.stringify({hostedReturnPassed:true,project,item,...facts}));
  } else if(expenseFlow) {
    assert.equal(memberships[0].financial_access,'full','Positive Expense flow requires financial access');
    assert.equal(memberships[0].can_manage_projects,true,'QA Project setup requires project management');
    assert.equal(memberships[0].can_manage_project_budgets,true,'QA Project setup requires category assignment permission');
    const context={accountId:account,principalId:auth.principalId,accessToken:session.access_token};
    const clients=await read('/rest/v1/spike_clients?account_id=eq.'+account+'&lifecycle=eq.active&select=id&order=id&limit=1');
    const categories=await read('/rest/v1/spike_budget_categories?account_id=eq.'+account+'&lifecycle=eq.active&kind=eq.general&select=id&order=id&limit=1');
    assert.equal(clients.length,1);assert.equal(categories.length,1);
    const feeCategories=feeFlow?await read('/rest/v1/spike_budget_categories?account_id=eq.'+account+'&lifecycle=eq.active&kind=eq.fee&select=id&order=id&limit=1'):[];
    if(feeFlow && feeCategories.length===0) {
      const categoryId='hosted-fee-qa-'+crypto.randomUUID();
      const command=categoryAPI.makeCategoryManagementRequest({operationUUID:crypto.randomUUID(),
        clientCreatedAtMilliseconds:Date.now(),payload:{action:'create',categoryId,
          name:'QA Hosted Fee '+categoryId.slice(-8),kind:'fee',excludesFromOverallBudget:false}},context);
      const raw=await new categoryAPI.SupabaseCategoryManagementApplier(new URL(base),apikey).apply(command,context);
      assert.equal(categoryAPI.validateCategoryManagementResult(raw,command).phase,'applied');
      feeCategories.push({id:categoryId});
    }
    const id='hosted-expense-flow-'+crypto.randomUUID(),project=id+'-project',expense=id+'-expense';
    const projectRequest=projectAPI.makeProjectCreationRPCRequest({operationId:id+'-create-project',projectId:project,
      clientSelection:{kind:'existing',clientId:clients[0].id},displayName:'QA — hosted Expense offline sync',
      description:'Synthetic QA only; safe to distinguish from copied source projects.',
      categoryAllocations:[{categoryId:categories[0].id},...feeCategories.map(c=>({categoryId:c.id}))],projectCreatedAtMilliseconds:Date.now()},context);
    const projectResult=await new projectAPI.SupabaseProjectCreationApplier(new URL(base),apikey).apply(projectRequest,context);
    assert.equal(projectResult.phase,'applied');
    const service=new expenseAPI.SupabaseExpenseCreationService(new URL(base),apikey);
    const payload={projectId:project,expenseId:expense,vendor:'QA delivery vendor',date:'2024-02-29',
      amountMinorUnits:'12345',currency:'USD',categoryId:categories[0].id,notes:'Hosted QA source Expense',
      receiptAttachmentIds:[],receiptLines:[{id:id+'-line',description:'Delivery',magnitudeMinorUnits:'12345',
        currency:'USD',effect:'increase',quantity:null}]};
    const command=expenseAPI.makeExpenseCreationRequest({operationUUID:crypto.randomUUID(),
      clientCreatedAtMilliseconds:Date.now(),payload},context);
    const applied=await service.apply(command,context);assert.equal(applied.phase,'applied');
    assert.deepEqual(await service.apply(command,context),applied);
    const source=await service.read({projectId:project,expenseId:expense},context);
    assert.deepEqual(source,{...payload,accountId:account,revision:'1'});
    console.log(JSON.stringify({hostedExpenseFlowStarted:true,project,expense}));
    const run=spawnSync('swift',['test','--package-path','LedgeriOS','--no-parallel','--filter',
      'AccountWorkspacePendingWorkRuntimeTests/expenseLiveReplication'],{encoding:'utf8',timeout:180000,env:{...process.env,
        LEDGER_EXPENSE_HOSTED_QA:'1',LEDGER_SALE_LOCAL_ACCOUNT:account,LEDGER_SALE_LOCAL_PRINCIPAL:auth.principalId,
        LEDGER_EXPENSE_LOCAL_EDIT:expenseEditFlow?'1':'0',LEDGER_EXPENSE_LOCAL_EDIT_MEDIA:expenseEditFlow?'1':'0',
        LEDGER_LIVE_INVOICE_LOCAL:invoiceFlow?'1':'0',LEDGER_INVOICE_LOCAL_CREATE:invoiceFlow?'1':'0',
        LEDGER_INVOICE_LOCAL_REVISE:invoiceFlow?'1':'0',
        LEDGER_FEE_LOCAL_CREATE:feeFlow?'1':'0',LEDGER_FEE_LOCAL_CATEGORY:feeCategories[0]?.id??'',
        LEDGER_SALE_LOCAL_ITEM:expense,LEDGER_SALE_LOCAL_PROJECT:project,LEDGER_SALE_LOCAL_KEY:apikey,
        LEDGER_SALE_LOCAL_EMAIL:auth.email,LEDGER_SALE_LOCAL_PASSWORD:auth.password}});
    process.stdout.write(run.stdout??'');process.stderr.write(run.stderr??'');
    assert.equal(run.status,0,'Hosted native Expense creation/sync/restart failed');
    assert.match(run.stdout+run.stderr,/Test run with 1 test.*passed/,'Native flow must execute');
    if(invoiceFlow) {
      const invoice=await new invoiceAPI.SupabaseLiveInvoiceReader(new URL(base),apikey)
        .read({projectId:project,invoiceId:expense+'-invoice'},context);
      assert.equal(invoice.revision,'2');assert.equal(invoice.name,'Revised offline Invoice');
      assert.equal(invoice.notes,'Offline edit');assert.equal(invoice.totalMinorUnits,'12345');
      assert.equal(invoice.lines.length,1);assert.equal(invoice.lines[0].sourceId,expense);
      console.log(JSON.stringify({hostedInvoiceFlow:true,project,invoice:invoice.invoiceId,
        nativeOfflineCreateAndRevise:true,restartReplay:true,mcpReadback:true}));
    } else if(feeFlow) {
      const result=await new feeAPI.SupabaseFeeReader(new URL(base),apikey).read({projectId:project},context);
      assert.equal(result.fees.length,1);const fee=result.fees[0];
      assert.equal(fee.id,expense+'-fee');assert.equal(fee.amountMinorUnits,'12345');
      assert.equal(fee.label,'Design fee');assert.equal(fee.categoryId,feeCategories[0].id);
      assert.equal(fee.status,'available');assert.equal(fee.invoiceId,null);
      console.log(JSON.stringify({hostedFeeFlow:true,project,fee:fee.id,offlineRestart:true,mcpReadback:true}));
    } else {
    const created=await service.read({projectId:project,expenseId:expenseEditFlow?expense:expense+'-native'},context);
    assert.equal(created.amountMinorUnits,'12345');assert.equal(created.notes,expenseEditFlow?'Offline edit':'Offline native creation');
    assert.equal(created.revision,expenseEditFlow?'2':'1');
    assert.deepEqual(created.receiptAttachmentIds,[expense+(expenseEditFlow?'-edit-native-receipt':'-offline-receipt')]);
    const receipt=await service.receipt({projectId:project,expenseId:created.expenseId,
      attachmentId:created.receiptAttachmentIds[0]},context);
    assert.equal(Buffer.from(receipt.bytes).toString(),expenseEditFlow?'%PDF-1.4\nOffline added Expense receipt\n%%EOF\n':'%PDF-1.4\nOffline Expense receipt\n%%EOF\n');
    assert.equal((await service.invoice({projectId:project,expenseId:created.expenseId},context)).invoice,null);
    }
    const transactions=await read('/rest/v1/spike_transactions?account_id=eq.'+account+'&project_id=eq.'+project+'&select=id');
    assert.deepEqual(transactions,[],'Expense creation must not invent a payment');
    console.log(JSON.stringify({hostedExpenseFlow:true,expenseEditFlow,invoiceFlow,feeFlow,project,
      nativeOfflineRestart:true,realPowerSync:true,mcpReadback:true,receiptBytes:!invoiceFlow&&!feeFlow,noPayment:true}));
  } else if(expenseMode) {
    assert.equal(memberships[0].financial_access,'full','Positive Expense test requires financial access; do not weaken authorization');
    const projects=await read('/rest/v1/spike_projects?account_id=eq.'+account+'&lifecycle=eq.active&select=id&order=id&limit=1');
    assert.equal(projects.length,1,'A private copied Project is required');
    const project=projects[0].id;
    assert.ok(project.startsWith('realcopy-b9d236394770-project-'));
    const expense='hosted-expense-qa-'+crypto.randomUUID();
    const attachment=expense+'-receipt';
    const run=spawnSync('swift',['test','--package-path','LedgeriOS','--no-parallel','--filter',
      'SupabaseTransactionAttachmentUploadTests/actualLocalExpense'],{
      encoding:'utf8',timeout:180000,env:{...process.env,
        LEDGER_EXPENSE_SERVICE_URL:base,LEDGER_SALE_LOCAL_KEY:apikey,
        LEDGER_EXPENSE_LOCAL_TOKEN:session.access_token,LEDGER_SALE_LOCAL_ACCOUNT:account,
        LEDGER_SALE_LOCAL_PRINCIPAL:auth.principalId,LEDGER_SALE_LOCAL_PROJECT:project,
        LEDGER_SALE_LOCAL_ITEM:expense,LEDGER_EXPENSE_LOCAL_ATTACHMENT:attachment},
    });
    process.stdout.write(run.stdout??'');process.stderr.write(run.stderr??'');
    assert.equal(run.status,0,'Native hosted Expense upload/retry failed');
    assert.match(run.stdout+run.stderr,/Test run with 1 test.*passed/,'Expense scenario must execute');
    const verified=await request('/functions/v1/verify-expense-attachment',{
      method:'POST',headers,body:JSON.stringify({attachmentId:attachment})});
    assert.equal(verified.status,200,'Hosted Expense verification retry failed');
    const result=await verified.json();
    assert.equal(result.phase,'verified');assert.equal(result.expenseId,expense);
    assert.equal(result.accountId,account);assert.equal(result.projectId,project);
    assert.equal(result.contentSHA256,crypto.createHash('sha256').update('Native Expense receipt').digest('hex'));
    assert.equal(result.byteCount,String(Buffer.byteLength('Native Expense receipt')));
    console.log(JSON.stringify({nativeExpenseUpload:true,hostedVerifiedRetry:true,attachment,expense,project,
      expenseCreated:false,scope:'Receipt staging only; no accounting or existing source attachments changed'}));
  } else {
  // Use a known-empty copied receipt section; never replace source attachments.
  const sections=await read('/rest/v1/transaction_attachment_sets?account_id=eq.'+account+'&section=eq.receipts&expected_count=eq.0&select=transaction_id&order=transaction_id&limit=1');
  assert.equal(sections.length,1,'Complete imported catalogs with an empty receipt section are required');
  const transaction=sections[0].transaction_id;
  assert.ok(transaction.startsWith('realcopy-b9d236394770-transaction-'));
  const attachment='hosted-upload-qa-'+crypto.randomUUID();
  const run=spawnSync('swift',['test','--package-path','LedgeriOS','--no-parallel','--filter','SupabaseTransactionAttachmentUploadTests/actualLocalService'],{
    encoding:'utf8',timeout:180000,env:{...process.env,
      LEDGER_ATTACHMENT_LOCAL_URL:base,LEDGER_ATTACHMENT_LOCAL_KEY:apikey,
      LEDGER_ATTACHMENT_LOCAL_TOKEN:session.access_token,LEDGER_ATTACHMENT_LOCAL_ACCOUNT:account,
      LEDGER_ATTACHMENT_LOCAL_PRINCIPAL:auth.principalId,LEDGER_ATTACHMENT_LOCAL_TRANSACTION:transaction,
      LEDGER_ATTACHMENT_LOCAL_ATTACHMENT:attachment,LEDGER_ATTACHMENT_VERIFY_EDGE:'1'},
  });
  process.stdout.write(run.stdout??'');process.stderr.write(run.stderr??'');
  assert.equal(run.status,0,'Native hosted resumable-upload check failed');
  const verify=async()=>{
    const response=await request('/functions/v1/verify-transaction-attachment',{method:'POST',headers,body:JSON.stringify({attachmentId:attachment})});
    assert.equal(response.status,200,'Hosted verification failed');return response.json();
  };
  const [first,concurrent]=await Promise.all([verify(),verify()]);
  assert.equal(first.phase,'applied');assert.equal(first.result_code,'attachment_published');
  assert.deepEqual(concurrent,first);assert.deepEqual(await verify(),first);
  const refs=await read('/rest/v1/transaction_attachment_references?account_id=eq.'+account+'&attachment_id=eq.'+attachment+'&select=id');
  assert.equal(refs.length,1,'Replay duplicated attachment');
  console.log(JSON.stringify({nativeInterruptedUpload:true,hostedPublication:true,concurrentReplay:true,attachment,transaction}));
  }
} finally {
  await request('/auth/v1/logout?scope=local',{method:'POST',headers});
}
