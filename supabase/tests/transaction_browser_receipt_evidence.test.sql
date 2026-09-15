begin;
select no_plan();
insert into public.spike_transactions(id,account_id,scope_kind,origin,type,amount_minor_units,currency,category_id,non_item_receipt_lines)
values ('browser-receipt','account-primary','business_inventory','vendor_payment','purchase',301,'USD','category-system',
  '[{"id":"tax","description":"Tax","amountMinorUnits":"1","effect":"increase"}]');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('browser-linked','account-primary','Current Item','principal-owner'),
  ('browser-returned','account-primary','Historical Item','principal-owner');
insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values ('browser-link','account-primary','browser-receipt','browser-linked','USD',100,'linked'),
  ('browser-return','account-primary','browser-receipt','browser-returned','USD',null,'returned');
select ok(not has_table_privilege('anon','ledger_private.transaction_receipt_display','SELECT'),'anonymous cannot read receipt view');
select ok(not has_table_privilege('service_role','ledger_private.transaction_receipt_display','SELECT'),'receipt view adds no privileged API bypass');
select ok((select 'security_invoker=true'=any(reloptions) from pg_class where oid='ledger_private.transaction_receipt_display'::regclass),'receipt view preserves invoker RLS');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is(public.spike_read_transaction_detail('account-primary','browser-receipt')->'receipt',
  public.spike_read_transaction_receipt('account-primary','browser-receipt'),'detail and dedicated audit share identical evidence');
select is((select row->'receipt' from jsonb_array_elements(public.spike_read_transaction_list('account-primary','business_inventory')->'transactions') row
  where row->>'transactionId'='browser-receipt'),public.spike_read_transaction_receipt('account-primary','browser-receipt'),'list and audit share evidence');
select is(jsonb_array_length(public.spike_read_transaction_detail('account-primary','browser-receipt')->'receipt'->'items'),2,'history is retained alongside linked Item');
select is(public.spike_read_transaction_detail('account-primary','browser-receipt')->'receipt'->'items'->1->'amountMinorUnits','null'::jsonb,'missing historical amount is not zero');
select is(public.spike_read_transaction_detail('account-primary','browser-receipt')->'receipt'->'items'->1->>'name','Historical Item','authorized historical label preserved');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select is((select count(*) from ledger_private.transaction_receipt_display where id='browser-receipt'),0::bigint,'view cannot bypass Account boundary');
select throws_ok($$select public.spike_read_transaction_detail('account-primary','browser-receipt')$$,'42501','account_not_authorized','detail retains tenant gate');
select * from finish();
rollback;
