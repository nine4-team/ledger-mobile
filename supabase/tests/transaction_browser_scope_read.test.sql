begin;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('browser-project','account-primary','client-existing','Browser',now(),now(),1,1,'principal-owner');
select ledger_private.import_client_payment('browser-payment','account-primary','browser-project','client-existing',
  9007199254740993,'USD','browser-fixture','source-one','\x01'::bytea);
insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency,origin,category_id)
values ('browser-vendor','account-primary','browser-project','client-existing',100,'USD','vendor_payment','category-system');
insert into public.spike_transactions(id,account_id,scope_kind,amount_minor_units,currency,origin,category_id)
values ('browser-inventory','account-primary','business_inventory',200,'USD','vendor_payment','category-system');
create temp table browser_before as select jsonb_agg(to_jsonb(t) order by id) as payload from public.spike_transactions t;
select ok(not has_table_privilege('anon','ledger_private.transaction_display','SELECT'),'private display view not granted to anonymous');
select ok(not has_table_privilege('service_role','ledger_private.transaction_display','SELECT'),'no service-role display bypass');
select ok((select 'security_invoker=true'=any(reloptions) from pg_class where oid='ledger_private.transaction_display'::regclass),'view preserves invoker RLS');
select ok(not has_function_privilege('anon','public.spike_read_transaction_list(text,text,text)','EXECUTE'),'list requires authenticated caller');
set local role authenticated;
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select public.spike_read_transaction_list('account-primary','business_inventory')$$,
  '28000','authentication required','missing identity denied');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select throws_ok($$select public.spike_read_transaction_list('account-primary','project','browser-project')$$,
  '42501','account_not_authorized','foreign Account denied');
select is((select count(*) from ledger_private.transaction_display where id like 'browser-%'),0::bigint,'view cannot bypass tenant RLS');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is(jsonb_array_length(public.spike_read_transaction_list('account-primary','project','browser-project')->'transactions'),1,'restricted member sees only ordinary vendor Transaction');
select is(public.spike_read_transaction_list('account-primary','project','browser-project')->'transactions'->0->>'transactionId','browser-vendor','hidden payment does not leak in list');
select throws_ok($$select public.spike_read_transaction_detail('account-primary','browser-payment')$$,
  '42501','transaction_not_available','unclassified imported money remains full-only');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(jsonb_array_length(public.spike_read_transaction_list('account-primary','project','browser-project')->'transactions'),2,'full member sees standalone payment without requiring an Item link');
select is(public.spike_read_transaction_list('account-primary','project','browser-project')->>'clientId','client-existing','Project scope Client resolved from canonical Project');
select is(public.spike_read_transaction_list('account-primary','project','browser-project')->>'coverage','partial','existing origins do not imply whole implementation completeness');
select is(public.spike_read_transaction_list('account-primary','project','browser-project')->'transactions'->0,
  public.spike_read_transaction_detail('account-primary','browser-payment'),'list and detail use identical authorized display projection');
select is(public.spike_read_transaction_detail('account-primary','browser-payment')->>'amountMinorUnits','9007199254740993','full history preserves exact money');
select is(public.spike_read_transaction_detail('account-primary','browser-payment')->'category','null'::jsonb,'no invented vendor category on client payment');
select is((select count(*) from jsonb_array_elements(public.spike_read_transaction_list('account-primary','business_inventory')->'transactions') t
 where t->>'transactionId' in ('browser-payment','browser-vendor')),0::bigint,'Inventory does not contain Project Transactions');
select is((select count(*) from jsonb_array_elements(public.spike_read_transaction_list('account-primary','business_inventory')->'transactions') t
 where t->>'transactionId'='browser-inventory'),1::bigint,'Inventory includes its own Transaction');
select throws_ok($$select public.spike_read_transaction_list('account-primary','business_inventory','browser-project')$$,
  '22023','transaction_scope_invalid','Inventory cannot use a synthetic Project');
select throws_ok($$select public.spike_read_transaction_list('account-primary','project',null)$$,
  '22023','transaction_scope_invalid','Project scope requires a Project');
select throws_ok($$select public.spike_read_transaction_list('account-primary',null)$$,
  '22023','transaction_scope_invalid','missing scope rejected');
select throws_ok($$select public.spike_read_transaction_list('account-primary','project','missing')$$,
  '42501','transaction_scope_not_available','missing Project is not complete empty data');
select throws_ok($$update public.spike_transactions set amount_minor_units=1 where id='browser-payment'$$,
  '42501',null,'expanded reads do not add mutation permission');
reset role;
select is((select jsonb_agg(to_jsonb(t) order by id) from public.spike_transactions t),(select payload from browser_before),'all reads preserve exact stored facts');
update public.spike_account_memberships set financial_access='none' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select is(jsonb_array_length(public.spike_read_transaction_list('account-primary','project','browser-project')->'transactions'),1,'same JWT loses payment read after access reduction');
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select throws_ok($$select public.spike_read_transaction_list('account-primary','project','browser-project')$$,
  '42501','account_not_authorized','membership removal revokes list');
reset role;
select * from finish();
rollback;
