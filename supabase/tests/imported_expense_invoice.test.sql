begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('expense-import-project','account-primary','client-existing','Expense import',now(),now(),1,1,'principal-owner');
select ledger_private.import_client_payment('expense-import-payment','account-primary','expense-import-project','client-existing',
  9007199254740993,'USD','source-account','source-payment','\x007b7dff');
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
values('expense-import-receipt','account-primary',repeat('a',64),12,'application/pdf',
  'accounts/account-primary/attachments/expense-import-receipt/'||repeat('a',64));
create function pg_temp.invoice_record() returns jsonb language sql as $$
  select jsonb_build_object('invoice_id','expense-import-invoice','invoice_revision','1','account_id','account-primary',
    'project_id','expense-import-project','client_id','client-existing','purchase_id','expense-import-payment',
    'currency','USD','total_minor_units','9007199254740993','lines',jsonb_build_array(jsonb_build_object(
      'id','expense-import-line','line_position',0,'source_kind','expense','source_id','expense-import-source',
      'item_id',null,'source_revision','1','category_id','historical-category','signed_amount_minor_units','9007199254740993',
      'description','Historical description','source_snapshot_json','{"expense":{"expenseId":"expense-import-source"}}')))
$$;
create function pg_temp.expense_record() returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('source_document_id','source-expense','source_bytes','\x00ff',
    'receipt_attachment_ids',jsonb_build_array('expense-import-receipt'),
    'record',jsonb_build_object('id','expense-import-source','account_id','account-primary','project_id','expense-import-project',
      'category_id','category-system','vendor','Current vendor','expense_date','2024-02-29',
      'final_amount_minor_units','9007199254740993','currency','USD','notes','Original notes','revision','1',
      'created_at',null,'created_by_principal_id',null)))
$$;
create function pg_temp.payment_record() returns jsonb language sql as $$
  select jsonb_build_object('p_id','expense-import-payment','p_account_id','account-primary','p_project_id','expense-import-project',
    'p_client_id','client-existing','p_amount','9007199254740993','p_currency','USD','p_source_account','source-account',
    'p_source_document','source-payment','p_source_bytes','\x007b7dff')
$$;
create function pg_temp.run_import(i jsonb default pg_temp.invoice_record(), e jsonb default pg_temp.expense_record(),
  p jsonb default pg_temp.payment_record(), b bytea default '\x01ff') returns jsonb language sql as $$
  select ledger_private.import_expense_invoice(i,e,p,'source-account','source-invoice',b)
$$;
select throws_ok($$select pg_temp.run_import(p=>jsonb_set(pg_temp.payment_record(),'{p_source_bytes}','"\\x00"'))$$,
  '22000',null,'Wrong payment evidence rejected before any Expense');
select throws_ok($$select pg_temp.run_import(e=>'[]')$$,'22023',null,'Partial source mapping rejected');
select throws_ok($$select pg_temp.run_import(e=>jsonb_set(pg_temp.expense_record(),'{0,receipt_attachment_ids}','["missing-object"]'))$$,
  '23503',null,'Missing verified receipt rolls back import');
select throws_ok($$select pg_temp.run_import(b=>'\x')$$,'23514',null,'Late evidence failure rolls back complete import');
select is((select count(*) from ledger_private.expenses where id='expense-import-source'),0::bigint,'No unpaid Expense left by late failure');
select is((select count(*) from ledger_private.collected_invoices where id='expense-import-invoice'),0::bigint,'No frozen Invoice left by late failure');
select throws_ok($$select pg_temp.run_import(e=>jsonb_set(pg_temp.expense_record(),'{0,record,account_id}','"account-other"'))$$,
  '22023',null,'Cross-Account Expense refused');
select throws_ok($$select pg_temp.run_import(i=>jsonb_set(pg_temp.invoice_record(),'{lines,0,source_snapshot_json}','"{}"'))$$,
  '22023',null,'Typed source cannot disagree with Expense link');
select lives_ok('select pg_temp.run_import()','Expense and paid Invoice import together');
select lives_ok('select pg_temp.run_import()','Exact retry succeeds without duplication');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((ledger_private.edit_expense(jsonb_build_object('operationId','edit-collected-expense',
  'accountId','account-primary','actorPrincipalId','principal-owner','projectId','expense-import-project',
  'expenseId','expense-import-source','contractVersion','expense-edit-v1','createdAtMs','123000',
  'vendor','Changed','date','2024-02-29','amountMinorUnits','1','currency','USD','categoryId','category-system',
  'notes','Changed','receiptLines','[]'::jsonb,'receiptAttachmentIds',jsonb_build_array('expense-import-receipt'),
  'expectedRevision','1')::text)).error_code,'expense_collected','Handler durably rejects collected Expense edits');
select throws_ok($$update ledger_private.expenses set notes='changed' where id='expense-import-source'$$,
  '23514','Collected Expense is immutable','Collected Expense notes cannot rewrite paid source');
select throws_ok($$update ledger_private.expenses set final_amount_minor_units=1 where id='expense-import-source'$$,
  '23514','Collected Expense is immutable','Collected Expense amount is locked');
select throws_ok($$delete from ledger_private.expense_receipt_attachments where expense_id='expense-import-source'$$,
  '23514','Collected Expense is immutable','Collected receipt relationship cannot be removed');
select throws_ok($$insert into ledger_private.expense_receipt_lines(account_id,expense_id,id,position,description,magnitude_minor_units,currency,effect)
  values('account-primary','expense-import-source','late-line',0,'Late change',1,'USD','increase')$$,
  '23514','Collected Expense is immutable','Collected receipt details cannot be appended');
select lives_ok('set constraints all immediate','Imported unknown creation metadata has durable source evidence');
set constraints all deferred;
select ok((select created_at is null and created_by_principal_id is null from ledger_private.expenses where id='expense-import-source'),
  'Missing legacy creation metadata stays unknown');
create function pg_temp.unattributed_native_expense() returns void language plpgsql as $$
begin
  insert into ledger_private.expenses(id,account_id,project_id,category_id,vendor,expense_date,final_amount_minor_units,currency,notes,revision)
  values('unattributed-native','account-primary','expense-import-project','category-system','Vendor','2024-01-01',1,'USD','',1);
  set constraints all immediate;
end;
$$;
select throws_ok('select pg_temp.unattributed_native_expense()','23514',null,'Native Expense cannot omit author/time without import evidence');
select is((select count(*) from ledger_private.expenses where id='expense-import-source'),1::bigint,'One physical Expense source');
select is((select attachment_id from ledger_private.expense_receipt_attachments where expense_id='expense-import-source'),
  'expense-import-receipt','Verified receipt reference imported atomically with paid source');
select is((select count(*) from public.spike_transactions where id='expense-import-payment'),1::bigint,'Original payment reused');
select is((select final_amount_minor_units from ledger_private.expenses where id='expense-import-source'),9007199254740993::bigint,'Exact money preserved');
select is((select category_id from ledger_private.collected_invoice_lines where id='expense-import-line'),'historical-category','Paid category not rewritten from current source');
select is((select invoice_bytes from ledger_private.imported_expense_invoice_sources where invoice_id='expense-import-invoice'),'\x01ff'::bytea,'Full binary Invoice envelope retained');
select is((select import_payload->'expenses'->0->>'source_bytes' from ledger_private.imported_expense_invoice_sources where invoice_id='expense-import-invoice'),'\x00ff','Expense envelope retained');
select throws_ok($$select pg_temp.run_import(b=>'\x02ff')$$,'22000',null,'Changed Invoice bytes refuse retry');
select throws_ok($$select pg_temp.run_import(e=>jsonb_set(pg_temp.expense_record(),'{0,record,vendor}','"Changed"'))$$,'22000',null,'Changed Expense refuses retry');
select throws_ok($$delete from ledger_private.imported_expense_invoice_sources where invoice_id='expense-import-invoice'$$,'55000',null,'Import evidence cannot be deleted');
select ledger_private.import_client_payment('expense-import-payment-2','account-primary','expense-import-project','client-existing',
  9007199254740993,'USD','source-account','source-payment-2','\x02');
create function pg_temp.duplicate_source_import() returns jsonb language plpgsql as $$
declare i jsonb:=pg_temp.invoice_record(); e jsonb:=pg_temp.expense_record(); p jsonb:=pg_temp.payment_record();
begin
  i:=i||'{"invoice_id":"expense-import-invoice-2","purchase_id":"expense-import-payment-2"}';
  i:=jsonb_set(i,'{lines,0,id}','"expense-import-line-2"');
  i:=jsonb_set(i,'{lines,0,source_id}','"expense-import-source-2"');
  i:=jsonb_set(i,'{lines,0,source_snapshot_json}',to_jsonb('{"expense":{"expenseId":"expense-import-source-2"}}'::text));
  e:=jsonb_set(e,'{0,record,id}','"expense-import-source-2"');
  p:=p||jsonb_build_object('p_id','expense-import-payment-2','p_source_document','source-payment-2','p_source_bytes','\x02');
  return ledger_private.import_expense_invoice(i,e,p,'source-account','source-invoice-2','\x02');
end;
$$;
select throws_ok('select pg_temp.duplicate_source_import()','23505',null,'Source cost cannot be billed again under another target identity');
select is((select count(*) from ledger_private.expenses where id='expense-import-source-2'),0::bigint,'Duplicate source rolls back second Expense');
select is((select count(*) from ledger_private.collected_invoices where id='expense-import-invoice-2'),0::bigint,'Duplicate source rolls back second Invoice');
select ok(not has_function_privilege(r,'ledger_private.import_expense_invoice(jsonb,jsonb,jsonb,text,text,bytea)','EXECUTE'),r||' cannot call operator import')
  from unnest(array['anon','authenticated','service_role']) r;
select ok(not has_table_privilege(r,'ledger_private.imported_expense_invoice_sources','SELECT,INSERT,UPDATE,DELETE'),r||' cannot access import evidence')
  from unnest(array['anon','authenticated','service_role']) r;
select ok(not has_table_privilege(r,'ledger_private.imported_expense_sources','SELECT,INSERT,UPDATE,DELETE'),r||' cannot change source identities')
  from unnest(array['anon','authenticated','service_role']) r;
select ok(not prosecdef,'Importer uses invoker rights') from pg_proc
  where oid='ledger_private.import_expense_invoice(jsonb,jsonb,jsonb,text,text,bytea)'::regprocedure;
set constraints all immediate;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select is(public.spike_read_collected_invoice('account-primary','expense-import-project','expense-import-invoice')->>'total_minor_units',
  '9007199254740993','Direct Invoice read preserves exact amount without Expense selection');
select throws_ok($$select public.spike_begin_expense_attachment_upload('paid-new-receipt','account-primary',
  'expense-import-project','expense-import-source',repeat('d',64),12,'application/pdf','Paid.pdf')$$,
  '42501','expense_upload_unavailable','Collected Expense cannot reserve a new receipt');
select is(public.spike_read_collected_invoice('account-primary','expense-import-project','expense-import-invoice'),
  public.spike_read_expense_invoice('account-primary','expense-import-project','expense-import-source')->'invoice',
  'Direct and Expense paths return the identical frozen Invoice');
select throws_ok($$select public.spike_read_collected_invoice('account-other','expense-import-project','expense-import-invoice')$$,
  '42501',null,'Direct Invoice read denies foreign Account');
select throws_ok($$select public.spike_read_collected_invoice('account-primary','other-project','expense-import-invoice')$$,
  '42501',null,'Direct Invoice read binds exact Project');
select throws_ok($$select public.spike_read_collected_invoice('account-primary','expense-import-project','missing')$$,
  '42501',null,'Missing Invoice does not disclose existence');
select is(public.spike_read_expense_invoice('account-primary','expense-import-project','expense-import-source')#>>'{invoice,total_minor_units}',
  '9007199254740993','Authorized paid read returns exact full Invoice');
select is(public.spike_read_expense_invoice('account-primary','expense-import-project','expense-import-source')#>>'{invoice,lines,0,description}',
  'Historical description','Paid read retains historical line wording');
select throws_ok($$select public.spike_read_expense_invoice('account-other','expense-import-project','expense-import-source')$$,
  '42501',null,'Foreign Account cannot read paid Expense');
reset role;
update public.spike_account_memberships set financial_access='none' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select throws_ok($$select public.spike_read_collected_invoice('account-primary','expense-import-project','expense-import-invoice')$$,
  '42501',null,'Direct Invoice read denies financial withdrawal');
select throws_ok($$select public.spike_read_expense_invoice('account-primary','expense-import-project','expense-import-source')$$,
  '42501',null,'Revoked financial access cannot read paid Expense');
reset role;
select ok(not has_function_privilege(r,'public.spike_read_expense_invoice(text,text,text)','EXECUTE'),r||' cannot invoke paid read')
  from unnest(array['anon','service_role']) r;
-- No privileged public entry point or anonymous/service invocation.
select ok(not has_function_privilege(r,'public.spike_read_collected_invoice(text,text,text)','EXECUTE'),r||' cannot invoke direct Invoice read')
  from unnest(array['anon','service_role']) r;
select ok(not prosecdef,'Public Invoice wrapper uses invoker rights') from pg_proc
  where oid='public.spike_read_collected_invoice(text,text,text)'::regprocedure;
select * from finish();
rollback;
