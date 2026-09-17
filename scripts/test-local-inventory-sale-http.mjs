import assert from 'node:assert/strict';
import {randomUUID, createHash} from 'node:crypto';
import {execFile, execFileSync} from 'node:child_process';
import {promisify} from 'node:util';
import {realpathSync} from 'node:fs';

assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT);
const docker = (args, options={}) => execFileSync('docker',args,{encoding:'utf8',timeout:15000,...options});
assert.match(JSON.parse(docker(['context','inspect','--format','{{json .Endpoints.docker.Host}}'])),/^unix:\/\//);
const container='supabase_db_ledger_target_supabase_local';
const labels=JSON.parse(docker(['inspect','--format','{{json .Config.Labels}}',container]));
assert.equal(labels['com.supabase.cli.project'],'ledger_target_supabase_local');
assert.equal(realpathSync(labels['com.supabase.cli.workdir']),realpathSync(process.cwd()));
const local=JSON.parse(execFileSync('npx',['--offline','--yes','supabase@2.116.0','status','-o','json'],
    {encoding:'utf8',stdio:['ignore','pipe','ignore'],timeout:15000}));
assert.equal(local.API_URL,'http://127.0.0.1:54321');
const budgetRead = process.argv.includes('--native-budget');
const profileLogo = process.argv.includes('--native-profile-logo');
const profileRead = profileLogo || process.argv.includes('--native-profile');
if (profileRead) assert.deepEqual(process.argv.slice(2), [profileLogo ? '--native-profile-logo' : '--native-profile'], 'Profile read uses an isolated read-only scenario');
const profileLogoBytes = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jH1sAAAAASUVORK5CYII=', 'base64');
const profileStorageFixtures = [];
const paidReturnNative = process.argv.includes('--native-paid-return');
const importedPaidReturn = process.argv.includes('--imported-paid-return');
assert.ok(!importedPaidReturn || paidReturnNative, 'Imported paid return uses the existing native return scenario');
assert.ok(!paidReturnNative || (!budgetRead && ['--mixed','--mcp','--financial'].every(flag=>process.argv.includes(flag))),
    'Paid return uses the existing mixed financial sale fixture');
assert.ok(!budgetRead || ['--mixed','--mcp','--financial','--native-history'].every(flag=>process.argv.includes(flag)),
    'Budget parity uses the existing mixed historical financial fixture');
if(process.argv.includes('--price-edit')) assert.ok(process.argv.includes('--financial') &&
    !process.argv.some(flag=>flag !== '--native-price-edit' && /^(--native.*|--expense.*|--mixed|--return.*|--resale.*)$/.test(flag)),
    'Price edit uses the standalone financial sale fixture');
assert.ok(!process.argv.includes('--native-return') || process.argv.includes('--native'), '--native-return requires --native');
const returnScale=process.argv.includes('--return-scale')?700:1;
const mixedInvoice = process.argv.includes('--invoice-mixed');
assert.ok(!mixedInvoice || (process.argv.includes('--native-live-invoice') && !process.argv.includes('--native-invoice-create')
    && !process.argv.includes('--invoice-revise')), 'Mixed read fixture requires seeded live Invoice');
assert.ok(!process.argv.includes('--invoice-sent') || (process.argv.includes('--native-live-invoice')
    && !process.argv.includes('--native-invoice-create') && !process.argv.includes('--invoice-revise')),
    'Sent read fixture requires a seeded live Invoice, not creation/revision testing');
assert.ok(returnScale===1 || process.argv.includes('--native-return'), '--return-scale requires --native-return');
assert.ok(!process.argv.includes('--native-invoice-create') || process.argv.includes('--native-live-invoice'),
    '--native-invoice-create requires --native-live-invoice');
assert.ok(!process.argv.includes('--native-invoice-revise') || process.argv.includes('--native-invoice-create'),
    '--native-invoice-revise requires --native-invoice-create');
if (process.argv.includes('--native-invoice-create')) {
    assert.ok(process.argv.includes('--expense') && process.argv.includes('--financial') &&
        !['--expense-paid','--expense-edit','--native-expense','--native-expense-edit'].some(flag => process.argv.includes(flag)),
        'Native Invoice creation requires the uncollected revision1 Expense fixture');
}
assert.ok(!process.argv.includes('--expense-edit-conflict') || process.argv.includes('--native-expense-edit'),
    '--expense-edit-conflict requires --native-expense-edit');
if (process.argv.includes('--native-fee-create')) {
    assert.ok(process.argv.includes('--expense') && process.argv.includes('--financial') &&
        !['--native-live-invoice','--native-invoice-create','--expense-paid','--expense-edit','--native-expense','--native-expense-edit'].some(flag => process.argv.includes(flag)),
        'Fee replication uses the separate uncollected financial fixture');
}
assert.ok(!process.argv.includes('--native-price-edit') || process.argv.includes('--price-edit'));
if (process.argv.includes('--native-price-edit') || process.argv.includes('--native-expense') || process.argv.includes('--native-expense-edit') || process.argv.includes('--native-live-invoice') || process.argv.includes('--native-fee-create')) {
    const ready = await fetch('http://127.0.0.1:5590/probes/readiness', {
        redirect:'error', signal:AbortSignal.timeout(3000),
    }).catch(() => null);
    assert.equal(ready?.status,200,'Start the existing Ledger local PowerSync service before native replication tests');
}
const sql=query=>docker(['exec','-i',container,'psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{input:query}).trim();
const q=value=>"'"+value.replaceAll("'","''")+"'";
const key='sale-http-'+randomUUID(), account=key+'-account', principal=key+'-actor';
const project=key+'-project', client=key+'-client', item=key+'-item', category=key+'-category';
async function call(path, body, token, apiKey=local.PUBLISHABLE_KEY) {
    return fetch(local.API_URL+path,{method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),
        headers:{apikey:apiKey,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),
            ...(path.startsWith('/rest/')?{Accept:'application/vnd.pgrst.object+json'}:{})},body:JSON.stringify(body)});
}
const email=key+'@ledger-tests.invalid', password=randomUUID()+'-aA1!';
// Resolve optional test adapters before provisioning a synthetic user. A loader
// failure must not leave a signed-in fixture outside the cleanup block.
const mcp=process.argv.includes('--mcp') ? await import('../LedgerTargetMCP/src/inventorySale.ts') : null;
const budgetMCP=budgetRead ? await import('../LedgerTargetMCP/src/projectBudgetRead.ts') : null;
const priceMCP=process.argv.includes('--price-edit') ? await import('../LedgerTargetMCP/src/itemPriceEdit.ts') : null;
const priceTransport=priceMCP ? await import('../LedgerTargetMCP/src/inventorySale.ts') : null;
const returnMCP=process.argv.includes('--return-mcp') ? await import('../LedgerTargetMCP/src/uninvoicedReturn.ts') : null;
assert.ok(!process.argv.includes('--return-withdrawal') || (returnMCP && !process.argv.includes('--financial')),
    '--return-withdrawal requires --return-mcp with the ordinary no-financial-access fixture');
assert.ok(!returnMCP || (mcp && !['--expense','--mixed','--native'].some(flag=>process.argv.includes(flag))),
    'Return MCP uses the ordinary sale fixture with --mcp');
const expenseMCP=process.argv.includes('--expense-mcp') ? await import('../LedgerTargetMCP/src/expenseCreation.ts') : null;
const invoiceCreationMCP=process.argv.includes('--invoice-mcp') ? await import('../LedgerTargetMCP/src/invoiceCreation.ts') : null;
const feeMCP=process.argv.includes('--fee-mcp') ? await import('../LedgerTargetMCP/src/feeCreation.ts') : null;
const feeReadMCP=feeMCP ? await import('../LedgerTargetMCP/src/feeRead.ts') : null;
assert.ok(!feeMCP || (process.argv.includes('--expense') && process.argv.includes('--financial')
    && !process.argv.includes('--native-fee-create')), 'Fee MCP requires its own financial Expense fixture');
assert.ok(!invoiceCreationMCP || (process.argv.includes('--expense') && process.argv.includes('--financial')
    && !process.argv.includes('--native-invoice-create')), 'Invoice MCP requires the separate financial Expense fixture');
const invoiceMCP=process.argv.includes('--expense-mcp') && process.argv.includes('--expense-paid')
    ? await import('../LedgerTargetMCP/src/collectedInvoiceRead.ts') : null;
const invoiceReader=invoiceMCP ? new invoiceMCP.SupabaseCollectedInvoiceReader(new URL(local.API_URL),local.PUBLISHABLE_KEY) : null;
const created=await call('/auth/v1/admin/users',{email,password,email_confirm:true},local.SERVICE_ROLE_KEY,local.SERVICE_ROLE_KEY);
assert.equal(created.status,200,'Local synthetic user creation failed');
const user=await created.json();
const login=await call('/auth/v1/token?grant_type=password',{email,password});
assert.equal(login.status,200,'Local sign-in failed');
const {access_token:token}=await login.json();
assert.equal(typeof token,'string');
const context={accountId:account,principalId:principal,accessToken:token};
const service=mcp ? new mcp.SupabaseInventorySaleService(new URL(local.API_URL),local.PUBLISHABLE_KEY) : null;
try {
    sql(`begin;
      insert into public.spike_principals(id,auth_user_id) values(${q(principal)},${q(user.id)}::uuid);
      insert into public.spike_accounts(id,display_name) values(${q(account)},'Synthetic HTTP sale');
      insert into public.spike_account_memberships(account_id,principal_id,role,state,financial_access)
        values(${q(account)},${q(principal)},'employee','active',${q(process.argv.includes('--financial') ? 'full' : 'none')});
      insert into public.spike_clients(id,account_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
        values(${q(client)},${q(account)},'Synthetic',now(),now(),1,1,${q(principal)});
      insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
        values(${q(project)},${q(account)},${q(client)},'Synthetic',now(),now(),1,1,${q(principal)});
      insert into public.spike_budget_categories(id,account_id,display_name,kind,presentation_order,created_at_ms,updated_at_ms)
        values(${q(category)},${q(account)},'Furnishings','itemized',0,1,1);
      update public.spike_accounts set furnishings_category_id=${q(category)} where id=${q(account)};
      insert into public.spike_items(id,account_id,description,created_by_principal_id)
        values(${q(item)},${q(account)},'Synthetic',${q(principal)});
      insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id,start_evidence)
        values(${q(key+'-old')},${q(account)},${q(item)},'business_inventory','2026-01-01',${q(principal)},${q(process.argv.includes('--return-mcp') ? 'import_observation' : 'recorded_move')});
      commit; notify pgrst,'reload schema';`);
    if(returnScale>1) sql(`begin;
      insert into public.spike_items(id,account_id,description,created_by_principal_id)
        select ${q(key)}||'-scale-'||i,${q(account)},'Synthetic scale Item',${q(principal)} from generate_series(1,${returnScale-1}) i;
      insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,ended_at,started_by_principal_id,ended_by_principal_id)
        select ${q(key)}||'-scale-old-'||i,${q(account)},${q(key)}||'-scale-'||i,'business_inventory','2025-01-01','2026-01-01',${q(principal)},${q(principal)} from generate_series(1,${returnScale-1}) i;
      insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
        select ${q(key)}||'-scale-placement-'||i,${q(account)},${q(key)}||'-scale-'||i,'project',${q(project)},'2026-01-01',${q(principal)} from generate_series(1,${returnScale-1}) i;
      insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,created_at,created_by_principal_id)
        select ${q(key)}||'-scale-charge-'||i,${q(account)},${q(project)},${q(key)}||'-scale-'||i,${q(key)}||'-scale-placement-'||i,${q(category)},1,'USD','2026-01-01',${q(principal)} from generate_series(1,${returnScale-1}) i;
      commit;`);
    if(process.argv.includes('--native-resale-other-project')) sql(`begin;
      insert into public.spike_clients(id,account_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
        values(${q(key+'-native-client')},${q(account)},'Other native Client',now(),now(),1,1,${q(principal)});
      insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
        values(${q(key+'-native-project')},${q(account)},${q(key+'-native-client')},'Other native Project',now(),now(),1,1,${q(principal)});
      commit;`);
    const runNative = async (test, selectedProject=project, selectedItem=item) => {
        // Keep processing HTTP socket closures while Swift builds/tests run.
        const {stdout: output}=await promisify(execFile)('swift',['test','--package-path','LedgeriOS','--no-parallel','--filter',
            test==='actualLocalExpense' ? `SupabaseTransactionAttachmentUploadTests/${test}` : `AccountWorkspacePendingWorkRuntimeTests/${test}`],{encoding:'utf8',timeout:120000,
            env:{...process.env,LEDGER_SALE_LOCAL_ACCOUNT:account,LEDGER_SALE_LOCAL_PRINCIPAL:principal,
                LEDGER_SALE_LOCAL_ITEM:selectedItem,LEDGER_SALE_LOCAL_PROJECT:selectedProject,LEDGER_SALE_LOCAL_KEY:local.PUBLISHABLE_KEY,
                LEDGER_SALE_LOCAL_DESTINATION_PROJECT:project,
                ...(process.argv.includes('--native-price-edit')?{LEDGER_PRICE_LOCAL:'1'}:{}),
                ...(process.argv.includes('--native-return')?{LEDGER_RETURN_LOCAL:'1'}:{}),
                ...(process.argv.includes('--native-resale')?{LEDGER_RESALE_LOCAL:'1'}:{}),
                ...(process.argv.includes('--native-resale-other-project')?{LEDGER_RESALE_PROJECT:key+'-native-project'}:{}),
                LEDGER_RETURN_LOCAL_PROJECT_COUNT:String(returnScale),
                LEDGER_SALE_LOCAL_CLIENT:client,
                ...(process.argv.includes('--native-invoice-create')?{LEDGER_INVOICE_LOCAL_CREATE:'1'}:{}),
                ...(process.argv.includes('--native-invoice-revise')?{LEDGER_INVOICE_LOCAL_REVISE:'1'}:{}),
                ...(process.argv.includes('--native-fee-create')?{LEDGER_FEE_LOCAL_CREATE:'1',LEDGER_FEE_LOCAL_CATEGORY:key+'-fee-category'}:{}),
                ...(process.argv.includes('--expense-paid')?{LEDGER_EXPENSE_LOCAL_PAID:'1'}:{}),
                ...(process.argv.includes('--native-live-invoice')?{LEDGER_LIVE_INVOICE_LOCAL:'1'}:{}),
                ...(process.argv.includes('--invoice-sent')?{LEDGER_INVOICE_LOCAL_SENT:'1'}:{}),
                ...(mixedInvoice?{LEDGER_INVOICE_LOCAL_MIXED:'1'}:{}),
                ...(process.argv.includes('--native-history-invoice')?{LEDGER_HISTORY_LIVE_INVOICE:'1'}:{}),
                ...(budgetRead?{LEDGER_BUDGET_LOCAL:'1'}:{}),
                ...(profileLogo?{LEDGER_PROFILE_LOCAL_LOGO:profileLogoBytes.toString('base64')}:{}),
                ...(paidReturnNative?{LEDGER_PAID_RETURN_LOCAL:'1'}:{}),
                ...(process.argv.includes('--native-expense-edit')?{LEDGER_EXPENSE_LOCAL_EDIT:'1'}:{}),
                ...(process.argv.includes('--expense-edit-media')?{LEDGER_EXPENSE_LOCAL_EDIT_MEDIA:'1'}:{}),
                ...(process.argv.includes('--expense-edit-conflict')?{LEDGER_EXPENSE_LOCAL_EDIT_CONFLICT:'1'}:{}),
                ...(test==='actualLocalExpense'?{LEDGER_EXPENSE_LOCAL_TOKEN:token,LEDGER_EXPENSE_LOCAL_ATTACHMENT:key+'-native-receipt'}:{}),
                LEDGER_SALE_LOCAL_FINANCIAL_ACCESS:process.argv.includes('--financial') ? 'full' : 'none',
                LEDGER_SALE_LOCAL_EMAIL:email,LEDGER_SALE_LOCAL_PASSWORD:password}});
        assert.match(output,/Test run with [1-9][0-9]* tests? .* passed/,
            'Native integration must execute a nonzero number of matching tests');
        console.log(output.slice(-2500));
    };
    if(process.argv.includes('--expense')) {
        assert.ok(process.argv.includes('--financial'),'Expense requires authorized financial fixture');
        const expense=key+'-expense', expenseCategory=key+'-expense-category';
        const receiptAttachmentIds=[];
        if(process.argv.includes('--native-expense-media')) {
            await runNative('actualLocalExpense',project,expense);
            receiptAttachmentIds.push(key+'-native-receipt');
        }
        async function uploadExpenseReceipt(attachment, expectedExpenseCount) {
            const bytes=Buffer.from('%PDF-1.4\nSynthetic Expense receipt\n%%EOF\n');
            const hash=createHash('sha256').update(bytes).digest('hex');
            const reservation=await call('/rest/v1/rpc/spike_begin_expense_attachment_upload',{
                p_id:attachment,p_account_id:account,p_project_id:project,p_expense_id:expense,
                p_content_sha256:hash,p_byte_count:bytes.length,p_media_type:'application/pdf',p_file_name:'Receipt.pdf',
            },token);
            assert.equal(reservation.status,200,await reservation.clone().text());
            const claims=await reservation.json();
            const verify=()=>call('/functions/v1/verify-expense-attachment',{attachmentId:attachment},token);
            const missing=await verify();
            assert.equal(missing.status,409,await missing.clone().text());
            assert.equal((await missing.json()).error,'attachment_upload_incomplete');
            const uploaded=await fetch(local.API_URL+'/storage/v1/object/ledger-attachments/'+claims.storagePath,{
                method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),
                headers:{apikey:local.PUBLISHABLE_KEY,Authorization:'Bearer '+token,'Content-Type':'application/pdf'},body:bytes,
            });
            assert.equal(uploaded.status,200,await uploaded.clone().text());
            const verified=await verify();
            assert.equal(verified.status,200,await verified.clone().text());
            const published=await verified.json();
            assert.equal(published.phase,'verified'); assert.equal(published.expenseId,expense);
            assert.equal(published.contentSHA256,hash); assert.equal(published.byteCount,String(bytes.length));
            const replay=await verify(); assert.equal(replay.status,200); assert.deepEqual(await replay.json(),published);
            assert.equal(sql(`select count(*) from ledger_private.expenses where id=${q(expense)}`),String(expectedExpenseCount));
            return attachment;
        }
        if(process.argv.includes('--expense-media')) receiptAttachmentIds.push(await uploadExpenseReceipt(key+'-receipt',0));
        sql(`insert into public.spike_budget_categories(id,account_id,display_name,kind,presentation_order,created_at_ms,updated_at_ms)
          values(${q(expenseCategory)},${q(account)},'Delivery','general',1,1,1)`);
        const intent={operationId:key+'-expense-op',accountId:account,actorPrincipalId:principal,
          projectId:project,expenseId:expense,contractVersion:'expense-create-v1',createdAtMs:'1788523200000',
          vendor:'Original vendor',date:'2024-02-29',amountMinorUnits:mixedInvoice?'9223372036854775806':'9223372036854775807',currency:'USD',
          categoryId:expenseCategory,notes:'Source notes',receiptAttachmentIds,receiptLines:[
            {id:key+'-line',description:'Delivery',magnitudeMinorUnits:'25',currency:'USD',effect:'increase',quantity:null}]};
        let expenseRequest, expenseService;
        if(expenseMCP) {
            const {operationId,accountId,actorPrincipalId,contractVersion,createdAtMs,...payload}=intent;
            expenseRequest=expenseMCP.makeExpenseCreationRequest({operationUUID:randomUUID(),
                clientCreatedAtMilliseconds:Number(createdAtMs),payload},context);
            intent.operationId=expenseRequest.operationId;
            expenseService=new expenseMCP.SupabaseExpenseCreationService(new URL(local.API_URL),local.PUBLISHABLE_KEY);
        }
        const body={p_command:expenseRequest?.commandJSON ?? JSON.stringify(intent)};
        const first=await call('/rest/v1/rpc/spike_create_expense',body,token);
        assert.equal(first.status,200,await first.clone().text());
        const applied=await first.json(); assert.equal(applied.phase,'applied');
        if(expenseRequest) {
            expenseMCP.validateExpenseCreationResult(applied,expenseRequest);
            assert.deepEqual(await expenseService.apply(expenseRequest,context),applied);
        }
        assert.equal(applied.command_fingerprint,createHash('sha256').update(body.p_command).digest('hex'));
        const retry=await call('/rest/v1/rpc/spike_create_expense',body,token);
        assert.equal(retry.status,200); assert.deepEqual(await retry.json(),applied);
        const readBody={p_account_id:account,p_project_id:project,p_expense_id:expense};
        const read=await call('/rest/v1/rpc/spike_read_expense',readBody,token);
        assert.equal(read.status,200); const snapshot=await read.json();
        assert.equal(snapshot.amountMinorUnits,intent.amountMinorUnits);
        assert.equal(snapshot.date,intent.date); assert.deepEqual(snapshot.receiptLines,intent.receiptLines);
        assert.deepEqual(snapshot.receiptAttachmentIds,receiptAttachmentIds);
        if(expenseService) {
            assert.deepEqual(await expenseService.read({projectId:project,expenseId:expense},context),snapshot);
            assert.deepEqual(await expenseService.invoice({projectId:project,expenseId:expense},context),{expense:snapshot,invoice:null});
            for(const attachmentId of receiptAttachmentIds) {
                const receipt=await expenseService.receipt({projectId:project,expenseId:expense,attachmentId},context);
                assert.equal(receipt.mimeType,'application/pdf');
                assert.equal(createHash('sha256').update(receipt.bytes).digest('hex'),
                    sql(`select content_sha256 from public.item_image_objects where id=${q(attachmentId)}`));
            }
            await assert.rejects(expenseService.read({projectId:project,expenseId:expense},
                {...context,accountId:key+'-foreign'}),error=>error.statusCode===403);
        }
        let editRequest;
        if(process.argv.includes('--expense-edit')) {
            assert.ok(expenseService, '--expense-edit requires --expense-mcp');
            assert.ok(!process.argv.includes('--expense-paid') && !process.argv.includes('--native-expense'),
                'Edit proof uses its own revision assertions, not the creation-only native/paid fixtures');
            const {operationId,accountId,actorPrincipalId,contractVersion,createdAtMs,...payload}=intent;
            const editedReceiptIds=[...receiptAttachmentIds];
            if(process.argv.includes('--expense-edit-media')) {
                editedReceiptIds.push(await uploadExpenseReceipt(key+'-edit-receipt',1));
            }
            const editInput={operationUUID:randomUUID(),clientCreatedAtMilliseconds:Number(createdAtMs),
                expectedRevision:'1',payload:{...payload,receiptAttachmentIds:editedReceiptIds,vendor:'Edited vendor',notes:'Edited notes'}};
            editRequest=expenseMCP.makeExpenseEditRequest(editInput,context);
            const edited=await expenseService.edit(editRequest,context);
            assert.equal(edited.phase,'applied');
            assert.deepEqual(await expenseService.edit(editRequest,context),edited);
            const updated=await expenseService.read({projectId:project,expenseId:expense},context);
            assert.equal(String(updated.revision),'2');
            assert.equal(updated.vendor,'Edited vendor');
            assert.equal(updated.notes,'Edited notes');
            assert.equal(updated.amountMinorUnits,intent.amountMinorUnits);
            assert.deepEqual(updated.receiptLines,intent.receiptLines);
            assert.deepEqual(updated.receiptAttachmentIds,editedReceiptIds);
            const stale=expenseMCP.makeExpenseEditRequest({...editInput,operationUUID:randomUUID()},context);
            const rejected=await expenseService.edit(stale,context);
            assert.equal(rejected.phase,'rejected');
            assert.equal(rejected.error_code,'expense_revision_conflict');
            const anonymousEdit=await call('/rest/v1/rpc/spike_edit_expense',{p_command:editRequest.commandJSON});
            assert.ok([401,403].includes(anonymousEdit.status));
        }
        if(process.argv.includes('--expense-paid')) {
            assert.ok(process.argv.includes('--native-expense'),'Paid evidence requires actual native download verification');
            const invoice={invoice_id:key+'-invoice',invoice_revision:'1',account_id:account,project_id:project,
                client_id:client,purchase_id:key+'-payment',currency:'USD',total_minor_units:intent.amountMinorUnits,
                display_metadata:{invoiceNumber:'INV-LIVE-001',notes:'Original Invoice notes',paidAtMilliseconds:'-1'},
                lines:[{id:key+'-invoice-line',line_position:0,source_kind:'expense',source_id:expense,item_id:null,
                    source_revision:'1',category_id:expenseCategory,signed_amount_minor_units:intent.amountMinorUnits,
                    description:'Frozen Expense description',source_snapshot_json:JSON.stringify({expense:{expenseId:expense}})}]};
            sql(`begin;
              select ledger_private.import_client_payment(${q(invoice.purchase_id)},${q(account)},${q(project)},${q(client)},
                ${intent.amountMinorUnits},'USD',${q(key+'-source')},'payment','\\x01');
              select ledger_private.store_collected_invoice(${q(JSON.stringify(invoice))}::jsonb);
              commit;`);
            if(expenseService) {
                const paid=await expenseService.invoice({projectId:project,expenseId:expense},context);
                assert.deepEqual(paid.expense,snapshot);
                assert.equal(paid.invoice.purchase_id,invoice.purchase_id);
                assert.equal(paid.invoice.total_minor_units,intent.amountMinorUnits);
                assert.equal(paid.invoice.lines[0].source_id,expense);
                assert.deepEqual(paid.invoice.display_metadata,invoice.display_metadata);
                assert.deepEqual(await invoiceReader.read({projectId:project,invoiceId:invoice.invoice_id},context),paid.invoice);
                await assert.rejects(invoiceReader.read({projectId:key+'-foreign-project',invoiceId:invoice.invoice_id},context),error=>error.statusCode===403);
                await assert.rejects(invoiceReader.read({projectId:project,invoiceId:invoice.invoice_id},
                    {...context,accountId:key+'-foreign-account'}),error=>error.statusCode===403);
                const anonymous=await call('/rest/v1/rpc/spike_read_collected_invoice',
                    {p_account_id:account,p_project_id:project,p_invoice_id:invoice.invoice_id});
                assert.ok([401,403].includes(anonymous.status));
            }
        }
        if((process.argv.includes('--native-live-invoice') || process.argv.includes('--invoice-revise') || invoiceCreationMCP) && !process.argv.includes('--native-invoice-create')) {
            assert.ok(!process.argv.includes('--expense-paid') && !process.argv.includes('--expense-edit') && !process.argv.includes('--native-expense'),
                'Live Invoice replication requires the uncollected revision1 Expense fixture');
            const command = {operationId:key+'-invoice-op',accountId:account,actorPrincipalId:principal,
                projectId:project,clientId:client,invoiceId:key+'-invoice',contractVersion:'invoice-create-v1',
                createdAtMs:'1788523200000',name:'Live sync Invoice',notes:'External delivery',
                sources:[{kind:'expense',sourceId:expense,expectedRevision:'1',amountMinorUnits:intent.amountMinorUnits,currency:intent.currency}]};
            const createBody = {p_command:JSON.stringify(command)};
            if(mixedInvoice) {
                sql(`insert into public.spike_budget_categories(id,account_id,display_name,kind,presentation_order,created_at_ms,updated_at_ms)
                  values(${q(key+'-mixed-category')},${q(account)},'Design Fee','fee',2,1,1);
                  insert into ledger_private.fee_installments(id,account_id,project_id,category_id,label,amount_minor_units,currency,created_at,created_by_principal_id)
                  values(${q(key+'-mixed-fee')},${q(account)},${q(project)},${q(key+'-mixed-category')},'Design fee',1,'USD',now(),${q(principal)});`);
                command.sources.push({kind:'fee_installment',sourceId:key+'-mixed-fee',expectedRevision:'1',amountMinorUnits:'1',currency:'USD'});
                createBody.p_command=JSON.stringify(command);
            }
            let mcpResult;
            if (invoiceCreationMCP) {
                const request = invoiceCreationMCP.makeInvoiceCreationRequest({operationUUID:randomUUID(),
                    clientCreatedAtMilliseconds:Number(command.createdAtMs), payload:{projectId:project,clientId:client,
                        invoiceId:command.invoiceId,name:command.name,notes:command.notes,sources:command.sources}},context);
                createBody.p_command = request.commandJSON;
                const service = new invoiceCreationMCP.SupabaseInvoiceCreationService(new URL(local.API_URL),local.PUBLISHABLE_KEY);
                mcpResult = await service.apply(request,context);
                assert.equal(invoiceCreationMCP.validateInvoiceCreationResult(mcpResult,request).phase,'applied');
                assert.deepEqual(await service.apply(request,context),mcpResult);
            }
            const createdInvoice = await call('/rest/v1/rpc/spike_create_invoice',createBody,token);
            assert.equal(createdInvoice.status,200,await createdInvoice.clone().text());
            const createdResult = await createdInvoice.json();
            assert.equal(createdResult.result_code,'invoice_created');
            if (mcpResult) assert.deepEqual(createdResult,mcpResult);
            assert.deepEqual(await (await call('/rest/v1/rpc/spike_create_invoice',createBody,token)).json(),createdResult);
            if(process.argv.includes('--invoice-sent')) {
                // Synthetic read fixture only; this does not define the pending sent-action policy.
                sql(`update ledger_private.live_invoices set status='sent' where id=${q(command.invoiceId)}`);
            }
            assert.ok([401,403].includes((await call('/rest/v1/rpc/spike_create_invoice',createBody)).status));
            const response = await call('/rest/v1/rpc/spike_read_live_invoice',
                {p_account_id:account,p_project_id:project,p_invoice_id:key+'-invoice'},token);
            assert.equal(response.status,200);
            assert.equal((await response.json()).totalMinorUnits,mixedInvoice?'9223372036854775807':intent.amountMinorUnits);
            if (process.argv.includes('--invoice-revise')) {
                const edit = {...command, operationId:key+'-invoice-revision', contractVersion:'invoice-revise-created-v1',
                    expectedRevision:'1', name:'Revised Invoice'};
                const body = {p_command:JSON.stringify(edit)};
                const revised = await call('/rest/v1/rpc/spike_revise_created_invoice',body,token);
                assert.equal(revised.status,200,await revised.clone().text());
                const receipt = await revised.json();
                assert.equal(receipt.result_code,'invoice_revised');
                assert.deepEqual(await (await call('/rest/v1/rpc/spike_revise_created_invoice',body,token)).json(),receipt);
                assert.ok([401,403].includes((await call('/rest/v1/rpc/spike_revise_created_invoice',body)).status));
                const stale = await call('/rest/v1/rpc/spike_revise_created_invoice',
                    {p_command:JSON.stringify({...edit,operationId:key+'-stale-revision'})},token);
                assert.equal(stale.status,200);
                assert.equal((await stale.json()).error_code,'invoice_revision_conflict');
                assert.equal(sql(`select revision from ledger_private.live_invoices where id=${q(command.invoiceId)}`),'2');
                const mcp = await import('../LedgerTargetMCP/src/invoiceCreation.ts');
                const input = {operationUUID:randomUUID(),clientCreatedAtMilliseconds:Number(command.createdAtMs),expectedRevision:'2',
                    payload:{projectId:project,clientId:client,invoiceId:command.invoiceId,name:'MCP revised Invoice',notes:command.notes,sources:command.sources}};
                const request = mcp.makeInvoiceRevisionRequest(input,context);
                const service = new mcp.SupabaseInvoiceRevisionService(new URL(local.API_URL),local.PUBLISHABLE_KEY);
                assert.equal((await mcp.invoiceRevisionTool(input,context,service)).phase,'applied');
                const mcpReceipt = await service.apply(request,context);
                assert.equal(mcp.validateInvoiceRevisionResult(mcpReceipt,request).resultCode,'invoice_revised');
                assert.deepEqual(await service.apply(request,context),mcpReceipt);
                assert.equal(sql(`select revision from ledger_private.live_invoices where id=${q(command.invoiceId)}`),'3');
                console.log('PASS authenticated Invoice revision HTTP: exact replay, anonymous denial, stale edit rejection');
                console.log('PASS MCP Invoice revision uses same authorized HTTP writer and exact replay');
            }
        }
        if(process.argv.includes('--native-fee-create') || feeMCP) {
            sql(`insert into public.spike_budget_categories(id,account_id,display_name,kind,presentation_order,created_at_ms,updated_at_ms)
              values(${q(key+'-fee-category')},${q(account)},'Design Fee','fee',2,1,1);
              insert into public.spike_project_category_allocations(id,account_id,project_id,category_id,allocation_minor_units,allocation_currency,
                created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
              values(${q(key+'-fee-cap')},${q(account)},${q(project)},${q(key+'-fee-category')},12345,'USD',now(),now(),1,1,${q(principal)});`);
        }
        if(feeMCP) {
            const input={operationUUID:randomUUID(),clientCreatedAtMilliseconds:1788523200000,
                payload:{projectId:project,installmentId:key+'-fee',categoryId:key+'-fee-category',
                    label:'Design installment',amountMinorUnits:'12345',currency:'USD'}};
            const request=feeMCP.makeFeeCreationRequest(input,context);
            const service=new feeMCP.SupabaseFeeCreationService(new URL(local.API_URL),local.PUBLISHABLE_KEY);
            const applied=await service.apply(request,context);
            assert.equal(feeMCP.validateFeeCreationResult(applied,request).phase,'applied');
            assert.deepEqual(await service.apply(request,context),applied);
            await assert.rejects(service.apply(feeMCP.makeFeeCreationRequest({...input,
                payload:{...input.payload,label:'Changed retry'}},context),context));
            const excess=feeMCP.makeFeeCreationRequest({...input,operationUUID:randomUUID(),
                payload:{...input.payload,installmentId:key+'-excess',amountMinorUnits:'1'}},context);
            assert.equal(feeMCP.validateFeeCreationResult(await service.apply(excess,context),excess).errorCode,'fee_total_exceeded');
            assert.ok([401,403].includes((await call('/rest/v1/rpc/spike_create_fee_installment',{p_command:request.commandJSON})).status));
            const foreign={...context,accountId:key+'-foreign-account'};
            await assert.rejects(service.apply(feeMCP.makeFeeCreationRequest(input,foreign),foreign));
            assert.equal(sql(`select count(*) from ledger_private.fee_installments where account_id=${q(account)}`),'1');
            assert.equal(sql(`select amount_minor_units from ledger_private.fee_installments where id=${q(key+'-fee')}`),'12345');
            const reader=new feeReadMCP.SupabaseFeeReader(new URL(local.API_URL),local.PUBLISHABLE_KEY);
            const snapshot=await reader.read({projectId:project},context);
            assert.equal(snapshot.fees.length,1);
            assert.equal(snapshot.fees[0].id,key+'-fee');
            assert.equal(snapshot.fees[0].amountMinorUnits,'12345');
            assert.equal(snapshot.fees[0].status,'available');
            await assert.rejects(reader.read({projectId:project},foreign),error=>error.statusCode===403);
        }
        if(process.argv.includes('--native-expense') || process.argv.includes('--native-expense-edit') || process.argv.includes('--native-live-invoice') || process.argv.includes('--native-fee-create')) {
            assert.ok(!(process.argv.includes('--native-expense-edit') && (process.argv.includes('--expense-edit') || process.argv.includes('--expense-paid') || process.argv.includes('--native-expense'))),
                'Native edit uses its own uncollected revision1 fixture');
            await runNative('expenseLiveReplication',project,expense);
        }
        if(process.argv.includes('--native-invoice-create')) {
            assert.equal(sql(`select count(*) from ledger_private.live_invoices where account_id=${q(account)}`),'1');
            assert.equal(sql(`select count(*) from public.spike_operation_results where account_id=${q(account)} and command_type='create_invoice' and phase='applied'`),'1');
        }
        if(process.argv.includes('--native-invoice-revise')) {
            assert.equal(sql(`select count(*) from public.spike_operation_results where account_id=${q(account)} and command_type='revise_created_invoice' and phase='applied'`),'1');
            assert.equal(sql(`select revision from ledger_private.live_invoices where account_id=${q(account)}`),'2');
        }
        if(process.argv.includes('--native-fee-create')) {
            assert.equal(sql(`select count(*) from ledger_private.fee_installments where account_id=${q(account)} and amount_minor_units=12345`),'1');
            assert.equal(sql(`select count(*) from public.spike_operation_results where account_id=${q(account)} and command_type='create_fee_installment' and phase='applied'`),'1');
        }
        assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),process.argv.includes('--expense-paid')?'1':'0');
        assert.equal(sql(`select count(*) from ledger_private.expenses where account_id=${q(account)}`),process.argv.includes('--native-expense')?'2':'1');
        const changed=await call('/rest/v1/rpc/spike_create_expense',{p_command:JSON.stringify({...intent,notes:'Changed'})},token);
        assert.equal(changed.status,409);
        const anonymous=await call('/rest/v1/rpc/spike_create_expense',body);
        assert.ok([401,403].includes(anonymous.status));
        sql(`update public.spike_account_memberships set state='removed' where account_id=${q(account)} and principal_id=${q(principal)}`);
        if(feeMCP) {
            const service=new feeMCP.SupabaseFeeCreationService(new URL(local.API_URL),local.PUBLISHABLE_KEY);
            await assert.rejects(new feeReadMCP.SupabaseFeeReader(new URL(local.API_URL),local.PUBLISHABLE_KEY)
                .read({projectId:project},context),error=>error.statusCode===403);
            const request=feeMCP.makeFeeCreationRequest({operationUUID:randomUUID(),clientCreatedAtMilliseconds:1788523200000,
                payload:{projectId:project,installmentId:key+'-removed',categoryId:key+'-fee-category',
                    label:'Removed member',amountMinorUnits:'1',currency:'USD'}},context);
            await assert.rejects(service.apply(request,context),error=>error.statusCode===403);
        }
        assert.equal((await call('/rest/v1/rpc/spike_create_expense',body,token)).status,403);
        if(editRequest) await assert.rejects(expenseService.edit(editRequest,context),error=>error.statusCode===403);
        if(expenseRequest) await assert.rejects(expenseService.apply(expenseRequest,context),
            error=>error.code==='expense_request_rejected' && error.statusCode===403);
        if(expenseService) await assert.rejects(expenseService.read({projectId:project,expenseId:expense},context),
            error=>error.statusCode===403);
        if(expenseService) await assert.rejects(expenseService.invoice({projectId:project,expenseId:expense},context),
            error=>error.statusCode===403);
        if(invoiceReader) await assert.rejects(invoiceReader.read({projectId:project,invoiceId:key+'-invoice'},context),
            error=>error.statusCode===403);
        if(expenseService && receiptAttachmentIds.length) await assert.rejects(expenseService.receipt({projectId:project,
            expenseId:expense,attachmentId:receiptAttachmentIds[0]},context),error=>error.statusCode===403);
        assert.equal((await call('/rest/v1/rpc/spike_read_expense',readBody,token)).status,403);
        if(receiptAttachmentIds.length) {
            const removed=await call('/functions/v1/verify-expense-attachment',{attachmentId:receiptAttachmentIds[0]},token);
            assert.equal(removed.status,404,'removed member cannot reuse verifier admission');
        }
        console.log(JSON.stringify({authenticatedExpense:true,feeCreationMCP:!!feeMCP,nativeFeeCreation:process.argv.includes('--native-fee-create'),invoiceCreationMCP:!!invoiceCreationMCP,exactInt64:true,replay:true,changedReplayDenied:true,
            noPayment:!process.argv.includes('--expense-paid'),anonymousDenied:true,removedMemberDenied:true,verifiedReceiptBytes:receiptAttachmentIds.length>0,
            nativeScheduledReceipt:process.argv.includes('--native-expense'),nativeOfflineEdit:process.argv.includes('--native-expense-edit'),mcpCommand:!!expenseRequest,
            seededPaidInvoice:process.argv.includes('--expense-paid'),directInvoiceMCP:!!invoiceReader,
            authenticatedEdit:!!editRequest,editReplayAndStaleRevision:!!editRequest}));
    } else if(process.argv.includes('--mixed')) {
        assert.ok(mcp,'--mixed requires --mcp');
        const sourceProject=key+'-source-project', originItem=key+'-origin-item', thirdItem=key+'-third-item';
        const purchase=key+'-source-purchase', receipt=key+'-source-receipt', historical=key+'-historical';
        const paidCharge=key+'-paid-charge', payment=key+'-payment', invoice=key+'-invoice', line=key+'-line';
        sql(`begin;
          insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
            values(${q(sourceProject)},${q(account)},${q(client)},'Original Project',now(),now(),1,1,${q(principal)});
          insert into public.spike_items(id,account_id,description,created_by_principal_id)
            values(${q(originItem)},${q(account)},'Project-origin Item',${q(principal)}),(${q(thirdItem)},${q(account)},'Ordinary Inventory Item',${q(principal)});
          insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
            values(${q(originItem+'-old')},${q(account)},${q(originItem)},'business_inventory','2026-01-01',${q(principal)}),
                  (${q(thirdItem+'-old')},${q(account)},${q(thirdItem)},'business_inventory','2026-01-01',${q(principal)});
          insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,ended_at,started_by_principal_id,ended_by_principal_id)
            values(${q(historical)},${q(account)},${q(originItem)},'project',${q(sourceProject)},'2025-01-01','2026-01-01',${q(principal)},${q(principal)});
          insert into public.spike_transactions(id,account_id,project_id,client_id,scope_kind,origin,type,amount_minor_units,currency,category_id)
            values(${q(purchase)},${q(account)},${q(sourceProject)},${q(client)},'project','vendor_payment','purchase',200,'USD',${q(category)});
          insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
            values(${q(receipt)},${q(account)},${q(purchase)},${q(originItem)},'USD',200,'sold');
          insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,
            category_id,amount_minor_units,currency,created_at,created_by_principal_id)
            values(${q(paidCharge)},${q(account)},${q(sourceProject)},${q(originItem)},${q(historical)},
              ${q(category)},900,'USD','2025-01-01',${q(principal)});
          select ledger_private.import_client_payment(${q(payment)},${q(account)},${q(sourceProject)},${q(client)},
            900,'USD','synthetic-sale-history',${q(payment)},decode('01','hex'));
          insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
            values(${q(invoice)},${q(account)},${q(sourceProject)},${q(client)},${q(payment)},1,'USD',900);
          insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
            source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
            values(${q(line)},${q(account)},${q(invoice)},0,'USD','item',${q(paidCharge)},${q(originItem)},
              1,${q(category)},900,'Previous collected sale',
              jsonb_build_object('item',jsonb_build_object('itemId',${q(originItem)},'occurrenceId',${q(paidCharge)},
                'price',jsonb_build_object('basis',jsonb_build_object('projectPrice','{}'::jsonb),'amount',jsonb_build_object('minorUnits',900,'currency','USD')))));
          update ledger_private.collected_invoices set sealed=true where id=${q(invoice)};
          commit;`);
        const history=()=>sql(`select jsonb_build_object('purchase',(select to_jsonb(t) from public.spike_transactions t where id=${q(purchase)}),
            'receipt',(select to_jsonb(r) from public.transaction_receipt_items r where id=${q(receipt)}),
            'placement',(select to_jsonb(p) from public.spike_item_placements p where id=${q(historical)}),
            'paidCharge',(select to_jsonb(c) from ledger_private.item_charge_occurrences c where id=${q(paidCharge)}),
            'invoice',(select to_jsonb(i) from ledger_private.collected_invoices i where id=${q(invoice)}),
            'line',(select to_jsonb(l) from ledger_private.collected_invoice_lines l where id=${q(line)}),
            'payment',(select to_jsonb(t) from public.spike_transactions t where id=${q(payment)}))::text;`);
        const before=history(), ids=[item,originItem,thirdItem];
        const reviewed=await mcp.inventorySaleReviewTool({itemIds:ids},context,service);
        assert.deepEqual(reviewed.items.find(row=>row.itemId===originItem).purchaseCost,{state:'known',amountMinorUnits:'200',currency:'USD'});
        const input={operationUUID:randomUUID(),clientCreatedAtMilliseconds:1788523200000,payload:{projectId:project,currency:'USD',
            items:ids.map(id=>({itemId:id,placementId:id===item?key+'-old':id+'-old',priceRevision:'0',
                reviewedPriceMinorUnits:id===originItem?'200':'100',newPlacementId:id+'-new',occurrenceId:id+'-charge'}))}};
        const stale=structuredClone(input); stale.operationUUID=randomUUID(); stale.payload.items[1].placementId='missing-placement';
        assert.equal((await mcp.inventorySaleTool(stale,context,service)).phase,'rejected');
        assert.equal(sql(`select count(*) from public.spike_item_placements where account_id=${q(account)} and scope_kind='business_inventory' and ended_at is null`),'3');
        assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)} and project_id=${q(project)}`),'0');
        const applied=await mcp.inventorySaleTool(input,context,service);
        assert.equal(applied.phase,'applied');
        assert.deepEqual(await mcp.inventorySaleTool(input,context,service),applied);
        assert.equal(sql(`select count(*)||':'||sum(amount_minor_units)::text from ledger_private.item_charge_occurrences where account_id=${q(account)} and project_id=${q(project)}`),'3:400');
        assert.equal(sql(`select count(*) from public.spike_item_placements where account_id=${q(account)} and project_id=${q(project)} and ended_at is null`),'3');
        assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'2');
        assert.equal(history(),before);
        if(process.argv.includes('--native-history')) {
            assert.ok(process.argv.includes('--financial'),'Historical financial read requires authorized fixture');
            if(process.argv.includes('--native-history-invoice')) {
                const command={operationId:key+'-history-invoice-op',accountId:account,actorPrincipalId:principal,
                    projectId:project,clientId:client,invoiceId:key+'-history-live',contractVersion:'invoice-create-v1',
                    createdAtMs:'1788523200000',name:'Current sale Invoice',notes:'Synthetic Sent read fixture',
                    sources:[{kind:'item',sourceId:originItem+'-charge',expectedRevision:'1',amountMinorUnits:'200',currency:'USD'}]};
                const response=await call('/rest/v1/rpc/spike_create_invoice',{p_command:JSON.stringify(command)},token);
                assert.equal(response.status,200,await response.clone().text());
                assert.equal((await response.json()).result_code,'invoice_created');
                sql(`update ledger_private.live_invoices set status='sent' where id=${q(command.invoiceId)}`);
                assert.equal(history(),before,'Live membership must not rewrite earlier paid history');
            }
            await runNative('invoicingHistoricalLiveReplication',sourceProject,originItem);
            if (budgetMCP) {
                const reader=new budgetMCP.SupabaseProjectBudgetReader(new URL(local.API_URL),local.PUBLISHABLE_KEY);
                for (const [projectId,expected] of [[sourceProject,'1100'],[project,'400']]) {
                    const budget=await reader.read({projectId,currency:'USD'},context);
                    assert.equal(budget.overallRecognizedMinorUnits,expected);
                    assert.equal(budget.isCompleteForProjectBudget,false);
                }
                await assert.rejects(reader.read({projectId:sourceProject,currency:'USD'}, {...context,accountId:'foreign'}),
                    error=>error.statusCode===403);
                sql(`update public.spike_account_memberships set financial_access='limited' where account_id=${q(account)} and principal_id=${q(principal)}`);
                await assert.rejects(reader.read({projectId:project,currency:'USD'},context),error=>error.statusCode===403);
                console.log('PASS actual Budget MCP HTTP, native PowerSync/restart parity and foreign/restricted read denial.');
            }
            assert.equal(history(),before);
        }
        if (paidReturnNative) {
            const paidInvoice=key+'-current-invoice', paidPayment=key+'-current-payment', paidLine=key+'-current-line';
            const returnItem=importedPaidReturn ? key+'-imported-item' : item;
            if (importedPaidReturn) {
                const charge=returnItem+'-charge', placement=returnItem+'-project';
                const payment={p_id:paidPayment,p_account_id:account,p_project_id:project,p_client_id:client,
                    p_amount:'100',p_currency:'USD',p_source_account:'synthetic-paid-return',
                    p_source_document:paidPayment,p_source_bytes:'\\x01'};
                const invoice={invoice_id:paidInvoice,invoice_revision:'1',account_id:account,project_id:project,
                    client_id:client,purchase_id:paidPayment,currency:'USD',total_minor_units:'100',lines:[{
                        id:paidLine,line_position:0,source_kind:'item',source_id:charge,item_id:returnItem,
                        source_revision:'1',category_id:category,signed_amount_minor_units:'100',description:'Imported paid chair',
                        source_snapshot_json:JSON.stringify({item:{itemId:returnItem,occurrenceId:charge,
                            price:{basis:{importedInvoiceAmount:{}},amount:{minorUnits:100,currency:'USD'}}}})}]};
                const sources=[{source_document_id:returnItem,source_line_id:paidLine,
                    source_bytes:'\\x02',line_source_bytes:'\\x03'}];
                sql(`begin;
                  insert into public.spike_items(id,account_id,description,created_by_principal_id)
                    values(${q(returnItem)},${q(account)},'Imported paid chair',${q(principal)});
                  insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id,ended_at,ended_by_principal_id)
                    values(${q(returnItem+'-origin')},${q(account)},${q(returnItem)},'business_inventory','2023-01-01',${q(principal)},'2024-01-01',${q(principal)});
                  insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
                    values(${q(placement)},${q(account)},${q(returnItem)},'project',${q(project)},'2024-01-01',${q(principal)});
                  select ledger_private.import_client_payment(${q(paidPayment)},${q(account)},${q(project)},${q(client)},100,'USD','synthetic-paid-return',${q(paidPayment)},decode('01','hex'));
                  select ledger_private.import_invoice_sources_with_placements(${q(JSON.stringify(invoice))}::jsonb,
                    ${q(JSON.stringify(sources))}::jsonb,${q(JSON.stringify(payment))}::jsonb,'synthetic-paid-return',
                    ${q(paidInvoice)},decode('04','hex'),${q(JSON.stringify([{line_id:paidLine,placement_id:placement}]))}::jsonb,
                    ${q(principal)},decode('05','hex'));
                  commit;`);
            } else {
            const snapshot=JSON.stringify({item:{itemId:item,occurrenceId:item+'-charge',
                price:{basis:{projectPrice:{}},amount:{minorUnits:100,currency:'USD'}}}});
            sql(`begin;
              select ledger_private.import_client_payment(${q(paidPayment)},${q(account)},${q(project)},${q(client)},100,'USD','synthetic-paid-return',${q(paidPayment)},decode('01','hex'));
              insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
                values(${q(paidInvoice)},${q(account)},${q(project)},${q(client)},${q(paidPayment)},1,'USD',100);
              insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
                values(${q(paidLine)},${q(account)},${q(paidInvoice)},0,'USD','item',${q(item+'-charge')},${q(item)},1,${q(category)},100,'Paid chair',${q(snapshot)}::jsonb);
              update ledger_private.collected_invoices set sealed=true where id=${q(paidInvoice)};
              commit;`);
            }
            const importedContents=sql(`select ledger_private.read_collected_invoice(${q(account)},${q(paidInvoice)})`);
            await runNative('paidReturnLiveReplication',project,returnItem);
            assert.equal(sql(`select ledger_private.read_collected_invoice(${q(account)},${q(paidInvoice)})`),importedContents,
                'Returned Item retains exact frozen Invoice and payment membership');
            assert.equal(sql(`select count(*) from ledger_private.paid_item_return_credits where account_id=${q(account)} and item_id=${q(returnItem)}`),'1');
            assert.equal(sql(`select count(*) from public.spike_item_placements where account_id=${q(account)} and item_id=${q(returnItem)} and scope_kind='business_inventory' and ended_at is null`),'1');
            assert.equal(sql(`select signed_amount_minor_units from ledger_private.collected_invoice_lines where id=${q(paidLine)}`),'100');
            assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'3','Return creates no cash Transaction');
            assert.equal(history(),before,'Prior paid history remains unchanged');
            const {SupabaseProjectInvoicingItemsReader}=await import('../LedgerTargetMCP/src/projectInvoicingItemsRead.ts');
            const invoicingReader=new SupabaseProjectInvoicingItemsReader(new URL(local.API_URL),local.PUBLISHABLE_KEY);
            const invoicing=await invoicingReader.read({projectId:project},context);
            const returnedRows=invoicing.rows.filter(row=>row.itemId===returnItem);
            assert.equal(returnedRows.length,2,'MCP preserves both original paid charge and credit');
            assert.deepEqual(returnedRows.map(row=>[row.polarity,row.amountMinorUnits,row.availability]),
                [['charge','100','paid'],['credit','-100','available']],'MCP matches actual native Invoicing read');
            assert.equal(returnedRows[0].invoiceId,paidInvoice);
            assert.equal(returnedRows[1].invoiceId,null);
            await assert.rejects(invoicingReader.read({projectId:project},{...context,accountId:'foreign'}),
                error=>error.statusCode===403);
            sql(`update public.spike_account_memberships set financial_access='limited' where account_id=${q(account)} and principal_id=${q(principal)}`);
            await assert.rejects(invoicingReader.read({projectId:project},context),error=>error.statusCode===403);
            sql(`update public.spike_account_memberships set financial_access='full' where account_id=${q(account)} and principal_id=${q(principal)}`);
            console.log('PASS offline native paid return: one credit, one Inventory placement, unchanged paid line and no cash event.');
        }
        console.log(JSON.stringify({mcpMixedOriginSale:true,items:3,charges:3,totalMinorUnits:400,
            staleBatchAtomic:true,replay:true,sourcePurchaseReceiptAndHistoryUnchanged:true,frozenInvoiceAndPaymentUnchanged:true,newTransactions:0}));
    } else if(profileRead) {
        const ports=JSON.parse(docker(['inspect','--format','{{json .NetworkSettings.Ports}}','ledger_powersync_local']));
        assert.deepEqual(ports['8080/tcp'],[{HostIp:'127.0.0.1',HostPort:'5590'}]);
        sql(`insert into public.spike_account_business_profiles(id,account_id) values(${q(account)},${q(account)})`);
        const profileURL=local.API_URL+'/rest/v1/spike_account_business_profiles?account_id=eq.'+encodeURIComponent(account);
        const profileHeaders={apikey:local.PUBLISHABLE_KEY,Authorization:'Bearer '+token};
        let logoURL;
        if (profileLogo) {
            const hash=createHash('sha256').update(profileLogoBytes).digest('hex');
            for (const owner of [account,account+'-foreign']) {
                const attachment=owner+'-logo', path=`accounts/${owner}/attachments/${attachment}/${hash}`;
                if (owner!==account) sql(`insert into public.spike_accounts(id,display_name) values(${q(owner)},'Foreign synthetic profile');
                    insert into public.spike_account_business_profiles(id,account_id) values(${q(owner)},${q(owner)})`);
                const upload=await fetch(local.API_URL+'/storage/v1/object/ledger-attachments/'+path,{
                    method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),
                    headers:{apikey:local.SERVICE_ROLE_KEY,Authorization:'Bearer '+local.SERVICE_ROLE_KEY,'Content-Type':'image/png'},body:profileLogoBytes});
                assert.equal(upload.status,200,'Synthetic logo fixture upload');
                profileStorageFixtures.push(path);
                sql(`update public.spike_account_business_profiles set logo_attachment_id=${q(attachment)},
                    logo_content_sha256=${q(hash)},logo_byte_count=${profileLogoBytes.length},logo_media_type='image/png',
                    logo_storage_path=${q(path)} where account_id=${q(owner)}`);
                const url=local.API_URL+'/storage/v1/object/authenticated/ledger-attachments/'+path;
                const response=await fetch(url,{headers:profileHeaders,redirect:'error',signal:AbortSignal.timeout(10000)});
                if(owner===account) {
                    logoURL=url; assert.equal(response.status,200);
                    assert.deepEqual(Buffer.from(await response.arrayBuffer()),profileLogoBytes);
                } else assert.ok(response.status>=400 && response.status<500,'Foreign Account logo must be denied, not fail with a server error');
            }
            const anonymousLogo=await fetch(logoURL,{headers:{apikey:local.PUBLISHABLE_KEY},redirect:'error',signal:AbortSignal.timeout(10000)});
            assert.ok(anonymousLogo.status>=400 && anonymousLogo.status<500,'Anonymous logo must be denied, not fail with a server error');
        }
        const allowed=await fetch(profileURL,{headers:profileHeaders});
        assert.equal(allowed.status,200);
        assert.equal((await allowed.json()).length,1);
        const anonymous=await fetch(profileURL,{headers:{apikey:local.PUBLISHABLE_KEY}});
        assert.equal(anonymous.status,401);
        const mutation=await fetch(profileURL,{method:'PATCH',headers:{...profileHeaders,'Content-Type':'application/json'},body:JSON.stringify({revision:2})});
        assert.equal(mutation.status,403);
        await runNative('accountProfileLiveReplication');
        sql(`update public.spike_account_memberships set state='removed' where account_id=${q(account)} and principal_id=${q(principal)}`);
        const removed=await fetch(profileURL,{headers:profileHeaders});
        assert.equal(removed.status,200);
        assert.deepEqual(await removed.json(),[]);
        if (logoURL) {
            const removedLogo=await fetch(logoURL,{headers:profileHeaders,redirect:'error',signal:AbortSignal.timeout(10000)});
            assert.ok(removedLogo.status>=400 && removedLogo.status<500,'Removed member must be denied with the same JWT, not fail with a server error');
        }
        assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'0');
        assert.equal(sql(`select revision from public.spike_account_business_profiles where account_id=${q(account)}`),'1');
        console.log('PASS actual Account profile sync and offline restart without profile or financial mutation');
    } else if(process.argv.includes('--native')) {
        const ports=JSON.parse(docker(['inspect','--format','{{json .NetworkSettings.Ports}}','ledger_powersync_local']));
        assert.deepEqual(ports['8080/tcp'],[{HostIp:'127.0.0.1',HostPort:'5590'}]);
        await runNative('inventorySaleLiveReplication');
        const resold=process.argv.includes('--native-resale');
        assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)}`),String(returnScale+(resold?1:0)));
        assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)} and item_id=${q(item)} and amount_minor_units=9223372036854775807`),resold?'2':'1');
        assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'0');
        if(process.argv.includes('--native-return')) {
            assert.equal(sql(`select count(*) from ledger_private.uninvoiced_item_returns where account_id=${q(account)}`),'1');
            assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)} and withdrawn_at is null`),String(returnScale-1+(resold?1:0)));
            assert.equal(sql(`select count(*) from public.spike_item_placements where account_id=${q(account)} and ended_at is null and scope_kind='business_inventory'`),resold?'0':'1');
        }
        if(process.argv.includes('--native-resale-other-project')) {
            assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)}
                and project_id=${q(key+'-native-project')} and withdrawn_at is null`),'1');
            assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)}
                and project_id=${q(project)} and withdrawn_at is null`),'0');
        }
        console.log(JSON.stringify({nativeLiveSale:true,nativeLiveReturn:process.argv.includes('--native-return'),nativeLiveResale:resold,charges:returnScale+(resold?1:0),salePayments:0,exactInt64:true}));
    } else {
    const reviewEndpoint='/rest/v1/rpc/spike_read_inventory_sale_review';
    const reviewBody={p_account_id:account,p_item_ids:[item]};
    assert.ok([401,403].includes((await call(reviewEndpoint,reviewBody)).status));
    const reviewResponse=await call(reviewEndpoint,reviewBody,token);
    assert.equal(reviewResponse.status,200);
    const expectedReview={accountId:account,principalId:principal,items:[{
        itemId:item,placementId:key+'-old',priceRevision:'0',projectPrice:{state:'absent'},purchaseCost:{state:'absent'}}]};
    assert.deepEqual(await reviewResponse.json(),expectedReview);
    if(mcp) assert.deepEqual(await mcp.inventorySaleReviewTool({itemIds:[item]},context,service),expectedReview);
    const command={operationId:key,accountId:account,actorPrincipalId:principal,projectId:project,
        contractVersion:'inventory-sale-v1',createdAtMs:'1788523200000',currency:'USD',items:[{
            itemId:item,placementId:key+'-old',priceRevision:'0',reviewedPriceMinorUnits:'9223372036854775807',
            newPlacementId:key+'-new',occurrenceId:key+'-charge'}]};
    const input={operationUUID:randomUUID(),clientCreatedAtMilliseconds:Number(command.createdAtMs),
        payload:{projectId:project,currency:command.currency,items:command.items}};
    const raw=mcp ? mcp.makeInventorySaleRequest(input,context).commandJSON : JSON.stringify(command);
    const body={p_command:raw}, endpoint='/rest/v1/rpc/spike_sell_inventory_items';
    const unauthenticated=await call(endpoint,body);
    assert.ok([401,403].includes(unauthenticated.status),'Anonymous sale must be denied');
    if(mcp) assert.equal((await mcp.inventorySaleTool(input,context,service)).phase,'applied');
    const response=await call(endpoint,body,token);
    assert.equal(response.status,200,'Authenticated HTTP sale failed: '+response.status);
    const applied=await response.json();
    assert.equal(applied.phase,'applied');
    assert.equal(applied.command_fingerprint,createHash('sha256').update(raw).digest('hex'));
    const retry=await call(endpoint,body,token);
    assert.equal(retry.status,200); assert.deepEqual(await retry.json(),applied);
    assert.equal(sql(`select amount_minor_units::text from ledger_private.item_charge_occurrences where id=${q(key+'-charge')}`),'9223372036854775807');
    assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'0');
    let returnInput, returnService;
    let priceEditBody;
    if(process.argv.includes('--price-edit')) {
        const invoiceCommand={operationId:key+'-invoice-op',accountId:account,actorPrincipalId:principal,
            projectId:project,clientId:client,invoiceId:key+'-invoice',contractVersion:'invoice-create-v1',
            createdAtMs:'1788523200000',name:'Price edit Invoice',notes:'',sources:[{kind:'item',sourceId:key+'-charge',
                expectedRevision:'1',amountMinorUnits:'9223372036854775807',currency:'USD'}]};
        const invoiceResponse=await call('/rest/v1/rpc/spike_create_invoice',{p_command:JSON.stringify(invoiceCommand)},token);
        assert.equal(invoiceResponse.status,200); assert.equal((await invoiceResponse.json()).phase,'applied');
        const service=new priceTransport.SupabaseInventorySaleService(new URL(local.API_URL),local.PUBLISHABLE_KEY);
        const priceContext={accountId:account,principalId:principal,accessToken:token};
        const reviewed=await priceMCP.itemPriceEditReviewTool({projectId:project,itemId:item},priceContext,service);
        assert.equal(reviewed.currentPrice.amountMinorUnits,'9223372036854775807');
        assert.equal(reviewed.chargeRevision,'1');
        const priceInput={operationUUID:randomUUID(),clientCreatedAtMilliseconds:1788523200000,
            payload:{projectId:project,itemId:item,placementId:reviewed.placementId,occurrenceId:reviewed.occurrenceId,
                expectedPriceRevision:reviewed.priceRevision,expectedChargeRevision:reviewed.chargeRevision,
                requestedPriceMinorUnits:'12346',reviewedPriceMinorUnits:'12346',currency:'USD'}};
        const priceRequest=priceMCP.makeItemPriceEditRequest(priceInput,priceContext);
        priceEditBody={p_command:priceRequest.commandJSON};
        const path='/rest/v1/rpc/spike_edit_uncollected_item_price';
        assert.ok([401,403].includes((await call(path,priceEditBody)).status));
        const edited=await call(path,priceEditBody,token);
        assert.equal(edited.status,200); const receipt=await edited.json(); assert.equal(receipt.phase,'applied');
        assert.equal(receipt.command_fingerprint,createHash('sha256').update(priceEditBody.p_command).digest('hex'));
        const replay=await call(path,priceEditBody,token); assert.equal(replay.status,200);
        assert.deepEqual(await replay.json(),receipt);
        assert.equal((await priceMCP.itemPriceEditTool(priceInput,priceContext,service)).phase,'applied');
        const refreshed=await priceMCP.itemPriceEditReviewTool({projectId:project,itemId:item},priceContext,service);
        assert.equal(refreshed.currentPrice.amountMinorUnits,'12346');
        assert.equal(refreshed.chargeRevision,'2');
        const invoice=await call('/rest/v1/rpc/spike_read_live_invoice',
            {p_account_id:account,p_project_id:project,p_invoice_id:key+'-invoice'},token);
        assert.equal(invoice.status,200); assert.equal((await invoice.json()).totalMinorUnits,'12346');
        assert.equal(sql(`select revision||':'||amount_minor_units from ledger_private.item_charge_occurrences where id=${q(key+'-charge')}`),'2:12346');
        assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'0');
        console.log('PASS actual HTTP price edit: live Invoice readback, exact receipt/replay, no payment');
        sql(`begin;
              insert into public.spike_items(id,account_id,description,created_by_principal_id)
                values(${q(item+'-inventory')},${q(account)},'Synthetic Inventory price',${q(principal)});
              insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
                values(${q(item+'-inventory-placement')},${q(account)},${q(item+'-inventory')},'business_inventory','2026-01-01',${q(principal)});
              insert into ledger_private.item_project_prices(account_id,item_id,amount_minor_units,currency,updated_at,updated_by_principal_id)
                values(${q(account)},${q(item+'-inventory')},100,'USD',now(),${q(principal)});
              commit;`);
        const inventoryReview = await priceMCP.itemPriceEditReviewTool({projectId:null,itemId:item+'-inventory'},priceContext,service);
        assert.equal(inventoryReview.currentPrice.amountMinorUnits,'100');
        assert.equal(inventoryReview.currency,'USD');
        assert.equal(inventoryReview.occurrenceId,null);
        assert.equal(inventoryReview.chargeRevision,null);
        assert.equal(inventoryReview.purchaseCost.state,'absent');
        console.log('PASS actual MCP Inventory price review through authenticated shared endpoint');
        if(process.argv.includes('--native-price-edit')) {
            await runNative('itemPriceLiveReplication');
            assert.equal(sql(`select revision||':'||coalesce(amount_minor_units::text,'cleared') from ledger_private.item_project_prices
              where account_id=${q(account)} and item_id=${q(item+'-inventory')}`),'2:cleared');
            assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)} and item_id=${q(item+'-inventory')}`),'0');
            const clearedReview=await priceMCP.itemPriceEditReviewTool({projectId:null,itemId:item+'-inventory'},priceContext,service);
            assert.equal(clearedReview.currentPrice,null);
            assert.equal(clearedReview.priceRevision,'2');
            assert.equal(clearedReview.currency,'USD');
            const afterNative=await service.reviewItemPriceEdit({projectId:project,itemId:item},priceContext);
            assert.equal(afterNative.currentPrice.amountMinorUnits,'12347');
            assert.equal(afterNative.chargeRevision,'3');
            const invoiceAfterNative=await call('/rest/v1/rpc/spike_read_live_invoice',
                {p_account_id:account,p_project_id:project,p_invoice_id:key+'-invoice'},token);
            assert.equal(invoiceAfterNative.status,200);
            assert.equal((await invoiceAfterNative.json()).totalMinorUnits,'12347');
            assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'0');
        }
    }
    if(returnMCP) {
        returnService=new returnMCP.SupabaseUninvoicedReturnService(new URL(local.API_URL),local.PUBLISHABLE_KEY);
        const reviewInput={projectId:project,itemIds:[item]};
        const reviewed=await returnService.review(reviewInput,context);
        assert.deepEqual(reviewed,{accountId:account,principalId:principal,projectId:project,items:[{
            itemId:item,placementId:key+'-new',chargeId:key+'-charge',revision:'1'}]});
        returnInput={operationUUID:randomUUID(),clientCreatedAtMilliseconds:1788523200000,
            payload:{projectId:project,items:reviewed.items.map(row=>({itemId:row.itemId,placementId:row.placementId,
                chargeId:row.chargeId,expectedChargeRevision:row.revision,inventoryPlacementId:key+'-returned',returnOccurrenceId:key+'-return-fact'}))}};
        const returnBody={p_command:returnMCP.makeUninvoicedReturnRequest(returnInput,context).commandJSON};
        assert.ok([401,403].includes((await call('/rest/v1/rpc/spike_return_uninvoiced_items',returnBody)).status));
        const returned=await returnMCP.uninvoicedReturnTool(returnInput,context,returnService);
        assert.equal(returned.phase,'applied');
        assert.deepEqual(await returnMCP.uninvoicedReturnTool(returnInput,context,returnService),returned);
        assert.equal(sql(`select count(*) from public.spike_item_placements where account_id=${q(account)} and ended_at is null and scope_kind='business_inventory'`),'1');
        assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)} and withdrawn_at is null`),'0');
        assert.equal(sql(`select amount_minor_units::text||':'||revision::text from ledger_private.item_charge_occurrences where id=${q(key+'-charge')}`),'9223372036854775807:2');
        assert.equal(sql(`select count(*) from ledger_private.uninvoiced_item_returns where account_id=${q(account)} and charge_id=${q(key+'-charge')}`),'1');
        assert.equal(sql(`select count(*) from public.spike_item_placements origin
          join public.spike_item_placements sale on sale.account_id=origin.account_id and sale.item_id=origin.item_id and sale.started_at=origin.ended_at
          join public.spike_item_placements returned on returned.account_id=sale.account_id and returned.item_id=sale.item_id and returned.started_at=sale.ended_at
          join ledger_private.uninvoiced_item_returns fact on fact.account_id=returned.account_id and fact.item_id=returned.item_id and fact.inventory_placement_id=returned.id
          where origin.id=${q(key+'-old')} and origin.start_evidence='import_observation' and origin.started_at='2026-01-01'
            and sale.id=${q(key+'-new')} and sale.start_evidence='recorded_move'
            and returned.id=${q(key+'-returned')} and returned.ended_at is null
            and fact.charge_id=${q(key+'-charge')}`),'1','Imported Inventory observation remains linked through actual sale and return');
        assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'0');
        await assert.rejects(returnService.review(reviewInput,context),error=>error.statusCode===403);
        const changed=structuredClone(returnInput); changed.payload.items[0].returnOccurrenceId+='-changed';
        await assert.rejects(returnMCP.uninvoicedReturnTool(changed,context,returnService),error=>error.statusCode===409);
        if(process.argv.includes('--resale')) {
            const destination=process.argv.includes('--resale-other-project') ? key+'-destination' : project;
            if(destination!==project) sql(`begin;
                insert into public.spike_clients(id,account_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
                  values(${q(key+'-other-client')},${q(account)},'Other synthetic Client',now(),now(),1,1,${q(principal)});
                insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
                  values(${q(destination)},${q(account)},${q(key+'-other-client')},'Other synthetic Project',now(),now(),1,1,${q(principal)});
                commit;`);
            const prior=sql(`select jsonb_build_object('charge',to_jsonb(c),'return',to_jsonb(r))
                from ledger_private.item_charge_occurrences c join ledger_private.uninvoiced_item_returns r
                  on r.account_id=c.account_id and r.charge_id=c.id where c.id=${q(key+'-charge')}`);
            const resaleReview=await mcp.inventorySaleReviewTool({itemIds:[item]},context,service);
            assert.equal(resaleReview.items[0].placementId,key+'-returned');
            assert.equal(resaleReview.items[0].projectPrice.state,'known');
            const resale={operationUUID:randomUUID(),clientCreatedAtMilliseconds:1788523200000,
                payload:{projectId:destination,currency:'USD',items:[{itemId:item,placementId:key+'-returned',
                    priceRevision:resaleReview.items[0].priceRevision,reviewedPriceMinorUnits:resaleReview.items[0].projectPrice.amountMinorUnits,
                    newPlacementId:key+'-resold',occurrenceId:key+'-resale-charge'}]}};
            const resold=await mcp.inventorySaleTool(resale,context,service);
            assert.equal(resold.phase,'applied');
            assert.deepEqual(await mcp.inventorySaleTool(resale,context,service),resold);
            assert.equal(sql(`select jsonb_build_object('charge',to_jsonb(c),'return',to_jsonb(r))
                from ledger_private.item_charge_occurrences c join ledger_private.uninvoiced_item_returns r
                  on r.account_id=c.account_id and r.charge_id=c.id where c.id=${q(key+'-charge')}`),prior);
            assert.equal(sql(`select count(*) from public.spike_items where account_id=${q(account)}`),'1');
            assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)}
                and id=${q(key+'-resale-charge')} and item_id=${q(item)} and project_id=${q(destination)}
                and category_id=${q(category)} and amount_minor_units=9223372036854775807 and withdrawn_at is null`),'1');
            assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'0');
            assert.equal(sql(`select count(*) from public.spike_item_placements where account_id=${q(account)}
                and id=${q(key+'-resold')} and item_id=${q(item)} and project_id=${q(destination)} and ended_at is null`),'1');
            if(destination!==project) assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences
                where account_id=${q(account)} and project_id=${q(project)} and withdrawn_at is null`),'0');
            console.log(`PASS same-Item resale (${destination===project ? 'same Project' : 'different Client/Project'}): fresh charge/placement, reviewed current price, exact replay, prior charge/return unchanged`);
        }
        if(process.argv.includes('--return-withdrawal')) {
            const controller=new AbortController(), deadline=setTimeout(()=>controller.abort(),20000);
            let historyBucket, checkpointBuckets=new Set(), stage='download', purged=false, pending='';
            try {
                const response=await fetch('http://127.0.0.1:5590/sync/stream',{
                    method:'POST',signal:controller.signal,headers:{Authorization:'Bearer '+token,
                        'Content-Type':'application/json',Accept:'application/x-ndjson'},
                    body:JSON.stringify({buckets:[],raw_data:true,client_id:'return-withdrawal-'+randomUUID(),
                        streams:{include_defaults:false,subscriptions:[{stream:'physical_account_items',override_priority:null,
                            parameters:{account_id:account}}]}})});
                assert.equal(response.status,200); assert.ok(response.body);
                const reader=response.body.pipeThrough(new TextDecoderStream()).getReader();
                try {
                    while(!purged) {
                        const chunk=await reader.read(); if(chunk.done) break;
                        pending+=chunk.value; const lines=pending.split('\n'); pending=lines.pop();
                        for(const line of lines) {
                            if(!line.trim()) continue;
                            const message=JSON.parse(line); assert.ok(!message.error);
                            if(message.checkpoint) {
                                for(const stream of message.checkpoint.streams??[]) assert.deepEqual(stream.errors,[]);
                                checkpointBuckets=new Set(message.checkpoint.buckets.map(b=>b.bucket));
                            }
                            if(message.checkpoint_diff) {
                                for(const bucket of message.checkpoint_diff.removed_buckets??[]) checkpointBuckets.delete(bucket);
                                for(const bucket of message.checkpoint_diff.updated_buckets??[]) checkpointBuckets.add(bucket.bucket);
                            }
                            for(const row of message.data?.data??[]) if(row.op==='PUT' && row.object_type==='item_return_history'
                                && row.object_id===key+'-return-fact') historyBucket=message.data.bucket;
                            if(message.checkpoint_complete && historyBucket) {
                                if(stage==='download' && checkpointBuckets.has(historyBucket)) {
                                    sql(`update public.spike_budget_categories set kind='fee' where account_id=${q(account)} and id=${q(category)}`);
                                    stage='withdraw';
                                } else if(stage==='withdraw' && !checkpointBuckets.has(historyBucket)) purged=true;
                            }
                        }
                    }
                } finally { await reader.cancel().catch(()=>{}); }
                assert.ok(purged,'Category restriction must remove the previously downloaded history bucket at a completed checkpoint');
                console.log(JSON.stringify({returnHistoryNetworkWithdrawal:true}));
            } finally { clearTimeout(deadline); controller.abort(); }
        }
    }
    sql(`update public.spike_account_memberships set state='removed' where account_id=${q(account)} and principal_id=${q(principal)}`);
    const removed=await call(endpoint,body,token);
    assert.equal(removed.status,403,'Removed member must not replay a former result');
    assert.equal((await call(reviewEndpoint,reviewBody,token)).status,403,'Removed member must not read a sale review');
    if(priceEditBody) assert.equal((await call('/rest/v1/rpc/spike_edit_uncollected_item_price',priceEditBody,token)).status,403);
    if(mcp) {
        await assert.rejects(mcp.inventorySaleTool(input,context,service),error=>error.statusCode===403);
        await assert.rejects(mcp.inventorySaleReviewTool({itemIds:[item]},context,service),error=>error.statusCode===403);
    }
    if(returnMCP) {
        await assert.rejects(returnMCP.uninvoicedReturnTool(returnInput,context,returnService),error=>error.statusCode===403);
        await assert.rejects(returnService.review({projectId:project,itemIds:[item]},context),error=>error.statusCode===403);
    }
    console.log(JSON.stringify({mcp:!!mcp,authenticatedSale:true,exactInt64:true,replay:true,anonymousDenied:true,removedMemberDenied:true,
        mcpReturn:!!returnMCP,returnReadback:!!returnMCP,syntheticAccount:account}));
    }
} catch (error) {
    // Preserve native test diagnostics even if fixture cleanup subsequently fails.
    // Do not dump exec options/environment, which contain temporary credentials.
    if (typeof error?.stdout === 'string') console.error(error.stdout);
    console.error('Local integration failure:', error?.code ?? error?.name, error?.signal ?? '');
    throw error;
} finally {
    sql(`update public.spike_account_memberships set state='removed' where account_id=${q(account)} and principal_id=${q(principal)}`);
    await call('/auth/v1/logout?scope=local',{},token).catch(() => {
        console.error('Local fixture logout transport failed; membership has been removed.');
    });
    if (profileStorageFixtures.length) {
        const cleanup=await fetch(local.API_URL+'/storage/v1/object/ledger-attachments',{
            method:'DELETE',redirect:'error',signal:AbortSignal.timeout(10000),
            headers:{apikey:local.SERVICE_ROLE_KEY,Authorization:'Bearer '+local.SERVICE_ROLE_KEY,'Content-Type':'application/json'},
            body:JSON.stringify({prefixes:profileStorageFixtures})});
        assert.equal(cleanup.status,200,'Delete only this run\'s synthetic logo objects');
    }
}
