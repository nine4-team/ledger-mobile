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
insert into public.spike_items(id,account_id,description,created_by_principal_id)
  values('imported-paid-item','account-primary','Current Item name','principal-owner');
select ledger_private.import_client_payment('item-import-payment','account-primary','expense-import-project','client-existing',
  50,'USD','source-account','item-payment-source','\x07ff');
create function pg_temp.imported_item_evidence(with_evidence boolean, original_invoice text default 'item-source-invoice')
returns void language plpgsql as $$
begin
  perform ledger_private.store_collected_invoice(pg_temp.invoice_record()||jsonb_build_object(
    'invoice_id','item-import-invoice','purchase_id','item-import-payment','total_minor_units','50',
    'lines',jsonb_build_array(jsonb_build_object('id','item-import-line','line_position',0,'source_kind','item',
      'source_id','item-import-occurrence','item_id','imported-paid-item','source_revision','1',
      'category_id','historical-category','signed_amount_minor_units','50','description','Historical Item',
      'source_snapshot_json','{"item":{"itemId":"imported-paid-item","occurrenceId":"item-import-occurrence","price":{"basis":{"importedInvoiceAmount":{}},"amount":{"minorUnits":50,"currency":"USD"}}}}'))));
  if with_evidence then
    insert into ledger_private.imported_expense_invoice_sources values
      ('item-import-invoice','source-account','item-source-invoice','\x08ff','{}');
    insert into ledger_private.imported_item_invoice_sources values
      ('item-import-line','item-import-invoice','source-account',original_invoice,'original-line','original-item','\x09ff','\x0aff');
  end if;
  set constraints all immediate;
end;
$$;
select throws_ok('select pg_temp.imported_item_evidence(false)','23514',
  'Imported Item amount requires exact retained Invoice-line evidence','Imported amount without original evidence rejected');
select throws_ok($$select pg_temp.imported_item_evidence(true,'wrong-invoice')$$,'23514',
  'Imported Item amount requires exact retained Invoice-line evidence','Evidence for another original Invoice rejected');
select is((select count(*) from ledger_private.collected_invoices where id='item-import-invoice'),0::bigint,
  'Rejected Item evidence rolls back frozen Invoice');
select lives_ok('select pg_temp.imported_item_evidence(true)','Exact original paid Item evidence accepted');
set constraints all deferred;
select is((select count(*) from public.spike_item_placements where item_id='imported-paid-item'),0::bigint,
  'Paid Item import does not invent physical placement');
select is((select count(*) from ledger_private.item_charge_occurrences where item_id='imported-paid-item'),0::bigint,
  'Paid Item import does not create new unpaid demand');
select ok(not has_table_privilege(r,'ledger_private.imported_item_invoice_sources','SELECT,INSERT,UPDATE,DELETE'),
  r||' cannot manufacture imported Item evidence') from unnest(array['anon','authenticated','service_role']) r;
select ledger_private.import_client_payment('mixed-payment','account-primary','expense-import-project','client-existing',
  150,'USD','source-account','mixed-payment-source','\x02ff');
create function pg_temp.mixed_invoice() returns jsonb language sql as $$
  select pg_temp.invoice_record() || jsonb_build_object('invoice_id','mixed-invoice','purchase_id','mixed-payment',
    'total_minor_units','150','lines',jsonb_build_array(
      jsonb_build_object('id','mixed-fee-line','line_position',0,'source_kind','fee_installment','source_id','mixed-fee',
        'item_id',null,'source_revision','1','category_id','category-design-fee','signed_amount_minor_units','50',
        'description','Historical Fee','source_snapshot_json','{"feeInstallment":{"installmentId":"mixed-fee"}}'),
      (pg_temp.invoice_record()->'lines'->0)||jsonb_build_object('id','mixed-expense-line','line_position',1,
        'source_id','mixed-expense','signed_amount_minor_units','100',
        'source_snapshot_json','{"expense":{"expenseId":"mixed-expense"}}')))
$$;
create function pg_temp.mixed_sources() returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('source_document_id','mixed-fee-source','source_project_id','source-project',
    'source_bytes','\x03ff','record',jsonb_build_object('id','mixed-fee','account_id','account-primary',
      'project_id','expense-import-project','category_id','category-design-fee','label','Current Fee',
      'amount_minor_units','50','currency','USD','revision','1','created_at',null,'created_by_principal_id',null)),
    (pg_temp.expense_record()->0)||jsonb_build_object('source_document_id','mixed-expense-source',
      'record',(pg_temp.expense_record()->0->'record')||jsonb_build_object('id','mixed-expense','final_amount_minor_units','100')))
$$;
create function pg_temp.run_mixed(s jsonb default pg_temp.mixed_sources(), b bytea default '\x04ff') returns jsonb language sql as $$
  select ledger_private.import_invoice_sources(pg_temp.mixed_invoice(),s,
    pg_temp.payment_record()||jsonb_build_object('p_id','mixed-payment','p_amount','150',
      'p_source_document','mixed-payment-source','p_source_bytes','\x02ff'),'source-account','mixed-source-invoice',b)
$$;
select throws_ok($$select pg_temp.run_mixed(jsonb_set(pg_temp.mixed_sources(),'{1,record,account_id}','"account-other"'))$$,
  '22023',null,'Invalid second source rejects complete mixed import');
select is((select count(*) from ledger_private.fee_installments where id='mixed-fee'),0::bigint,
  'Earlier Fee insertion rolls back when Expense fails');
select throws_ok($$select pg_temp.run_mixed(b=>'\x')$$,'23514',null,'Late Invoice evidence failure rejects mixed import');
select is((select count(*) from ledger_private.expenses where id='mixed-expense'),0::bigint,
  'Late failure leaves no new Expense demand');
select is((select count(*) from ledger_private.collected_invoices where id='mixed-invoice'),0::bigint,
  'Late failure leaves no frozen Invoice');
select lives_ok('select pg_temp.run_mixed()','Complete Fee and Expense import succeeds');
select lives_ok('set constraints all immediate','Mixed source provenance satisfies deferred metadata guards');
set constraints all deferred;
select lives_ok('select pg_temp.run_mixed()','Exact mixed retry succeeds');
select throws_ok($$select pg_temp.run_mixed(jsonb_set(pg_temp.mixed_sources(),'{0,record,label}','"Changed"'))$$,
  '22000','Invoice import conflicts with retained evidence','Changed mixed retry is rejected');
select is((select count(*) from ledger_private.collected_invoice_lines where invoice_id='mixed-invoice'),2::bigint,
  'Mixed retry preserves exactly two lines');
select is((select sum(signed_amount_minor_units) from ledger_private.collected_invoice_lines where invoice_id='mixed-invoice'),
  150::numeric,'Mixed frozen amounts reconcile to the original payment');
select is((select source_project_id from ledger_private.imported_fee_sources where fee_id='mixed-fee'),
  'source-project','Fee provenance retains nested source Project');
select ledger_private.import_client_payment('duplicate-mixed-payment','account-primary','expense-import-project','client-existing',
  150,'USD','source-account','duplicate-payment-source','\x05ff');
create function pg_temp.duplicate_mixed_source() returns jsonb language plpgsql as $$
declare i jsonb:=pg_temp.mixed_invoice(); s jsonb:=pg_temp.mixed_sources();
begin
  i:=i||jsonb_build_object('invoice_id','duplicate-mixed-invoice','purchase_id','duplicate-mixed-payment');
  i:=jsonb_set(i,'{lines,0}',(i->'lines'->0)||jsonb_build_object('id','duplicate-fee-line','source_id','duplicate-fee',
    'source_snapshot_json','{"feeInstallment":{"installmentId":"duplicate-fee"}}'));
  i:=jsonb_set(i,'{lines,1}',(i->'lines'->1)||jsonb_build_object('id','duplicate-expense-line','source_id','duplicate-expense',
    'source_snapshot_json','{"expense":{"expenseId":"duplicate-expense"}}'));
  s:=jsonb_set(s,'{0,record,id}','"duplicate-fee"');
  s:=jsonb_set(s,'{1,record,id}','"duplicate-expense"');
  return ledger_private.import_invoice_sources(i,s,pg_temp.payment_record()||jsonb_build_object(
    'p_id','duplicate-mixed-payment','p_amount','150','p_source_document','duplicate-payment-source','p_source_bytes','\x05ff'),
    'source-account','duplicate-source-invoice','\x06ff');
end;
$$;
select throws_ok('select pg_temp.duplicate_mixed_source()','23505',null,
  'Original Fee cannot be reimported under a new target identity and payment');
select is((select count(*) from ledger_private.fee_installments where id='duplicate-fee'),0::bigint,
  'Duplicate source rejects new Fee atomically');
select is((select count(*) from ledger_private.expenses where id='duplicate-expense'),0::bigint,
  'Duplicate Fee source also rolls back the accompanying Expense');
select is((select count(*) from ledger_private.collected_invoices where id='duplicate-mixed-invoice'),0::bigint,
  'Duplicate source leaves no second paid Invoice');
select ok(not has_function_privilege(r,'ledger_private.import_invoice_sources(jsonb,jsonb,jsonb,text,text,bytea)','EXECUTE'),
  r||' cannot invoke operator mixed import') from unnest(array['anon','authenticated','service_role']) r;
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
create function pg_temp.unrelated_fee_evidence() returns void language plpgsql as $$
begin
  insert into ledger_private.fee_installments(id,account_id,project_id,category_id,label,amount_minor_units,currency)
    values('unrelated-fee','account-primary','expense-import-project','category-design-fee','Fee',50,'USD');
  insert into ledger_private.imported_fee_sources values
    ('unrelated-fee','expense-import-invoice','source-account','source-project','source-fee','\x00ff');
  set constraints all immediate;
end;
$$;
select throws_ok('select pg_temp.unrelated_fee_evidence()',
  '23514','Unknown Fee creation metadata requires retained import evidence',
  'Unrelated paid Invoice cannot justify unknown Fee metadata');
select is((select count(*) from ledger_private.fee_installments where id='unrelated-fee'),0::bigint,
  'Rejected evidence rolls back Fee insertion');
select is((select count(*) from ledger_private.imported_fee_sources where fee_id='unrelated-fee'),0::bigint,
  'Rejected evidence rolls back provenance insertion');
select ledger_private.import_client_payment('fee-import-payment','account-primary','expense-import-project','client-existing',
  50,'USD','source-account','source-fee-payment','\x01ff');
insert into ledger_private.fee_installments(id,account_id,project_id,category_id,label,amount_minor_units,currency)
  values('fee-import-source','account-primary','expense-import-project','category-design-fee','Fee',50,'USD');
select ledger_private.store_collected_invoice(jsonb_build_object(
  'invoice_id','fee-import-invoice','invoice_revision','1','account_id','account-primary',
  'project_id','expense-import-project','client_id','client-existing','purchase_id','fee-import-payment',
  'currency','USD','total_minor_units','50','lines',jsonb_build_array(jsonb_build_object(
    'id','fee-import-line','line_position',0,'source_kind','fee_installment','source_id','fee-import-source',
    'item_id',null,'source_revision','1','category_id','category-design-fee','signed_amount_minor_units','50',
    'description','Historical Fee','source_snapshot_json','{"feeInstallment":{"installmentId":"fee-import-source"}}'))));
insert into ledger_private.imported_expense_invoice_sources values
  ('fee-import-invoice','source-account','source-fee-invoice','\x01ff','{}');
insert into ledger_private.imported_fee_sources values
  ('fee-import-source','fee-import-invoice','source-account','source-project','source-fee','\x00ff');
select lives_ok('set constraints all immediate','Matching frozen Fee and retained evidence permit unknown creator/time');
set constraints all deferred;
select throws_ok($$update ledger_private.imported_fee_sources set source_bytes='\x01' where fee_id='fee-import-source'$$,
  '55000','Imported Invoice evidence is immutable','Fee provenance cannot be rewritten');
select throws_ok($$delete from ledger_private.imported_fee_sources where fee_id='fee-import-source'$$,
  '55000','Imported Invoice evidence is immutable','Fee provenance cannot be deleted');
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
set constraints all deferred;
select ledger_private.import_client_payment('item-mixed-payment','account-primary','expense-import-project','client-existing',
  200,'USD','source-account','item-mixed-payment-source','\x0bff');
create function pg_temp.item_mixed_import(source_line text default 'paid-item-line', item_id text default 'imported-paid-item')
returns jsonb language plpgsql as $$
declare
  i jsonb:=replace(pg_temp.mixed_invoice()::text,'mixed-','item-mixed-')::jsonb;
  s jsonb:=replace(pg_temp.mixed_sources()::text,'mixed-','item-mixed-')::jsonb;
begin
  i:=i||jsonb_build_object('total_minor_units','200','lines',(i->'lines')||jsonb_build_array(jsonb_build_object(
    'id','item-mixed-item-line','line_position',2,'source_kind','item','source_id','item-mixed-occurrence',
    'item_id',item_id,'source_revision','1','category_id','historical-category','signed_amount_minor_units','50',
    'description','Historical chair','source_snapshot_json',jsonb_build_object('item',jsonb_build_object(
      'itemId',item_id,'occurrenceId','item-mixed-occurrence','price',jsonb_build_object(
        'basis',jsonb_build_object('importedInvoiceAmount','{}'::jsonb),
        'amount',jsonb_build_object('minorUnits',50,'currency','USD'))))::text)));
  s:=s||jsonb_build_array(jsonb_build_object('source_document_id','original-item','source_line_id',source_line,
    'source_bytes','\x09ff','line_source_bytes','\x0aff'));
  return ledger_private.import_invoice_sources(i,s,pg_temp.payment_record()||jsonb_build_object(
    'p_id','item-mixed-payment','p_amount','200','p_source_document','item-mixed-payment-source','p_source_bytes','\x0bff'),
    'source-account','item-mixed-source-invoice','\x0cff');
end;
$$;
select throws_ok($$select pg_temp.item_mixed_import(item_id=>'missing-item')$$,'22023',null,
  'Missing physical Item rejects a mixed import after earlier Fee and Expense processing');
select is((select count(*) from ledger_private.expenses where id='item-mixed-expense'),0::bigint,
  'Invalid Item rolls back earlier Expense');
select is((select count(*) from ledger_private.fee_installments where id='item-mixed-fee'),0::bigint,
  'Invalid Item rolls back earlier Fee');
select throws_ok($$select pg_temp.item_mixed_import(source_line=>'bad/line')$$,'23514',null,
  'Late Item evidence constraint rejects entire import');
select is((select count(*) from ledger_private.collected_invoices where id='item-mixed-invoice'),0::bigint,
  'Late evidence failure rolls back frozen Invoice');
select lives_ok('select pg_temp.item_mixed_import()','Complete Item Expense Fee import succeeds');
set constraints all immediate;
set constraints all deferred;
select lives_ok('select pg_temp.item_mixed_import()','Exact Item mixed import replay succeeds');
select throws_ok($$select pg_temp.item_mixed_import(source_line=>'changed')$$,'22000',null,
  'Changed source evidence cannot replay a paid Item import');
select is((select count(*) from ledger_private.collected_invoice_lines where invoice_id='item-mixed-invoice'),3::bigint,
  'Replay retains exactly three ordered sources');
select is((ledger_private.read_collected_invoice('account-primary','item-mixed-invoice')->'lines'->2->>'signed_amount_minor_units'),
  '50','Persisted Item reader returns original billed amount');
select is((select item_source_bytes from ledger_private.imported_item_invoice_sources where line_id='item-mixed-item-line'),
  '\x09ff'::bytea,'Original Item bytes retained');
select is((select description from public.spike_items where id='imported-paid-item'),'Current Item name',
  'Historical import does not rewrite current physical Item');
select is((select count(*) from ledger_private.item_charge_occurrences where item_id='imported-paid-item'),0::bigint,
  'Historical import creates no billable charge');
select * from finish();
rollback;
