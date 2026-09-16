import assert from 'node:assert/strict';
import {randomUUID, createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
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
assert.ok(!process.argv.includes('--native-invoice-create') || process.argv.includes('--native-live-invoice'),
    '--native-invoice-create requires --native-live-invoice');
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
if (process.argv.includes('--native-expense') || process.argv.includes('--native-expense-edit') || process.argv.includes('--native-live-invoice') || process.argv.includes('--native-fee-create')) {
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
const expenseMCP=process.argv.includes('--expense-mcp') ? await import('../LedgerTargetMCP/src/expenseCreation.ts') : null;
const invoiceCreationMCP=process.argv.includes('--invoice-mcp') ? await import('../LedgerTargetMCP/src/invoiceCreation.ts') : null;
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
      insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
        values(${q(key+'-old')},${q(account)},${q(item)},'business_inventory','2026-01-01',${q(principal)});
      commit; notify pgrst,'reload schema';`);
    const runNative = (test, selectedProject=project, selectedItem=item) => {
        const output=execFileSync('swift',['test','--package-path','LedgeriOS','--no-parallel','--filter',
            test==='actualLocalExpense' ? `SupabaseTransactionAttachmentUploadTests/${test}` : `AccountWorkspacePendingWorkRuntimeTests/${test}`],{encoding:'utf8',timeout:120000,
            env:{...process.env,LEDGER_SALE_LOCAL_ACCOUNT:account,LEDGER_SALE_LOCAL_PRINCIPAL:principal,
                LEDGER_SALE_LOCAL_ITEM:selectedItem,LEDGER_SALE_LOCAL_PROJECT:selectedProject,LEDGER_SALE_LOCAL_KEY:local.PUBLISHABLE_KEY,
                LEDGER_SALE_LOCAL_DESTINATION_PROJECT:project,
                LEDGER_SALE_LOCAL_CLIENT:client,
                ...(process.argv.includes('--native-invoice-create')?{LEDGER_INVOICE_LOCAL_CREATE:'1'}:{}),
                ...(process.argv.includes('--native-fee-create')?{LEDGER_FEE_LOCAL_CREATE:'1',LEDGER_FEE_LOCAL_CATEGORY:key+'-fee-category'}:{}),
                ...(process.argv.includes('--expense-paid')?{LEDGER_EXPENSE_LOCAL_PAID:'1'}:{}),
                ...(process.argv.includes('--native-live-invoice')?{LEDGER_LIVE_INVOICE_LOCAL:'1'}:{}),
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
            runNative('actualLocalExpense',project,expense);
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
          vendor:'Original vendor',date:'2024-02-29',amountMinorUnits:'9223372036854775807',currency:'USD',
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
        if((process.argv.includes('--native-live-invoice') || invoiceCreationMCP) && !process.argv.includes('--native-invoice-create')) {
            assert.ok(!process.argv.includes('--expense-paid') && !process.argv.includes('--expense-edit') && !process.argv.includes('--native-expense'),
                'Live Invoice replication requires the uncollected revision1 Expense fixture');
            const command = {operationId:key+'-invoice-op',accountId:account,actorPrincipalId:principal,
                projectId:project,clientId:client,invoiceId:key+'-invoice',contractVersion:'invoice-create-v1',
                createdAtMs:'1788523200000',name:'Live sync Invoice',notes:'External delivery',
                sources:[{kind:'expense',sourceId:expense,expectedRevision:'1',amountMinorUnits:intent.amountMinorUnits,currency:intent.currency}]};
            const createBody = {p_command:JSON.stringify(command)};
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
            assert.ok([401,403].includes((await call('/rest/v1/rpc/spike_create_invoice',createBody)).status));
            const response = await call('/rest/v1/rpc/spike_read_live_invoice',
                {p_account_id:account,p_project_id:project,p_invoice_id:key+'-invoice'},token);
            assert.equal(response.status,200);
            assert.equal((await response.json()).totalMinorUnits,intent.amountMinorUnits);
        }
        if(process.argv.includes('--native-fee-create')) {
            sql(`insert into public.spike_budget_categories(id,account_id,display_name,kind,presentation_order,created_at_ms,updated_at_ms)
              values(${q(key+'-fee-category')},${q(account)},'Design Fee','fee',2,1,1);
              insert into public.spike_project_category_allocations(id,account_id,project_id,category_id,allocation_minor_units,allocation_currency,
                created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
              values(${q(key+'-fee-cap')},${q(account)},${q(project)},${q(key+'-fee-category')},12345,'USD',now(),now(),1,1,${q(principal)});`);
        }
        if(process.argv.includes('--native-expense') || process.argv.includes('--native-expense-edit') || process.argv.includes('--native-live-invoice') || process.argv.includes('--native-fee-create')) {
            assert.ok(!(process.argv.includes('--native-expense-edit') && (process.argv.includes('--expense-edit') || process.argv.includes('--expense-paid') || process.argv.includes('--native-expense'))),
                'Native edit uses its own uncollected revision1 fixture');
            runNative('expenseLiveReplication',project,expense);
        }
        if(process.argv.includes('--native-invoice-create')) {
            assert.equal(sql(`select count(*) from ledger_private.live_invoices where account_id=${q(account)}`),'1');
            assert.equal(sql(`select count(*) from public.spike_operation_results where account_id=${q(account)} and command_type='create_invoice' and phase='applied'`),'1');
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
        console.log(JSON.stringify({authenticatedExpense:true,nativeFeeCreation:process.argv.includes('--native-fee-create'),invoiceCreationMCP:!!invoiceCreationMCP,exactInt64:true,replay:true,changedReplayDenied:true,
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
              1,${q(category)},900,'Previous collected sale','{}');
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
            runNative('invoicingHistoricalLiveReplication',sourceProject,originItem);
            assert.equal(history(),before);
        }
        console.log(JSON.stringify({mcpMixedOriginSale:true,items:3,charges:3,totalMinorUnits:400,
            staleBatchAtomic:true,replay:true,sourcePurchaseReceiptAndHistoryUnchanged:true,frozenInvoiceAndPaymentUnchanged:true,newTransactions:0}));
    } else if(process.argv.includes('--native')) {
        const ports=JSON.parse(docker(['inspect','--format','{{json .NetworkSettings.Ports}}','ledger_powersync_local']));
        assert.deepEqual(ports['8080/tcp'],[{HostIp:'127.0.0.1',HostPort:'5590'}]);
        runNative('inventorySaleLiveReplication');
        assert.equal(sql(`select count(*) from ledger_private.item_charge_occurrences where account_id=${q(account)}`),'1');
        assert.equal(sql(`select amount_minor_units::text from ledger_private.item_charge_occurrences where account_id=${q(account)}`),'9223372036854775807');
        assert.equal(sql(`select count(*) from public.spike_transactions where account_id=${q(account)}`),'0');
        console.log(JSON.stringify({nativeLiveSale:true,charges:1,salePayments:0,exactInt64:true}));
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
    sql(`update public.spike_account_memberships set state='removed' where account_id=${q(account)} and principal_id=${q(principal)}`);
    const removed=await call(endpoint,body,token);
    assert.equal(removed.status,403,'Removed member must not replay a former result');
    assert.equal((await call(reviewEndpoint,reviewBody,token)).status,403,'Removed member must not read a sale review');
    if(mcp) {
        await assert.rejects(mcp.inventorySaleTool(input,context,service),error=>error.statusCode===403);
        await assert.rejects(mcp.inventorySaleReviewTool({itemIds:[item]},context,service),error=>error.statusCode===403);
    }
    console.log(JSON.stringify({mcp:!!mcp,authenticatedSale:true,exactInt64:true,replay:true,anonymousDenied:true,removedMemberDenied:true,syntheticAccount:account}));
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
}
