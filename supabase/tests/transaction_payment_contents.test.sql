begin;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('contents-project','account-primary','client-existing','Payment contents',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('contents-direct','account-primary','Direct paid Item','principal-owner'),
 ('contents-invoiced','account-primary','Invoice paid Item','principal-owner');
select ledger_private.import_client_payment('contents-payment','account-primary','contents-project','client-existing',125,'USD','contents-fixture','payment','\x01'::bytea);
select ledger_private.import_client_payment('contents-empty','account-primary','contents-project','client-existing',100,'USD','contents-fixture','empty','\x02'::bytea);
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id,ended_at,ended_by_principal_id)
values ('contents-placement','account-primary','contents-direct','project','contents-project','2026-09-01','principal-owner','2026-09-03','principal-owner');
insert into ledger_private.item_client_payment_connections(id,account_id,project_id,client_id,item_id,placement_id,transaction_id,started_at,started_by_principal_id,ended_at,ended_by_principal_id)
values ('contents-link','account-primary','contents-project','client-existing','contents-direct','contents-placement','contents-payment','2026-09-01','principal-owner','2026-09-02','principal-owner');
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
values ('contents-invoice','account-primary','contents-project','client-existing','contents-payment',1,'USD',125);
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
values ('contents-line','account-primary','contents-invoice',0,'USD','item','contents-occurrence','contents-invoiced',1,'category-furnishings',125,'Frozen Item description',
 '{"item":{"itemId":"contents-invoiced","occurrenceId":"contents-occurrence","price":{"basis":{"projectPrice":{}},"amount":{"minorUnits":125,"currency":"USD"}}}}');
update ledger_private.collected_invoices set sealed=true where id='contents-invoice';
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('contents-other-project','account-primary','client-existing','Other Project',now(),now(),1,1,'principal-owner');
insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
values ('contents-other-space','account-primary','project','contents-other-project','Elsewhere','active');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at,started_by_principal_id)
values ('contents-current-placement','account-primary','contents-direct','project','contents-other-project','contents-other-space','2026-09-04','principal-owner');
update public.spike_items set name='Renamed chair',revision=revision+1 where id='contents-invoiced';
set constraints all immediate;
select ok(not has_table_privilege('anon','ledger_private.transaction_payment_contents','SELECT'),'anonymous has no payment contents grant');
select ok(not has_function_privilege('anon','ledger_private.read_collected_invoice(text,text)','EXECUTE'),'anonymous cannot bypass payment view through frozen loader');
select ok(not has_table_privilege('authenticated','ledger_private.item_client_payment_connections','INSERT,UPDATE,DELETE'),'no Item payment writer granted');
select ok(not has_table_privilege('authenticated','ledger_private.collected_invoice_lines','INSERT,UPDATE,DELETE'),'no Invoice line writer granted');
select ok((select reloptions @> array['security_invoker=true'] from pg_class where oid='ledger_private.transaction_payment_contents'::regclass),'contents view retains invoker RLS');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select payload->'connections'->0->>'itemId' from ledger_private.transaction_payment_contents where id='contents-payment'),'contents-direct','closed connection survives departed placement');
select is((select jsonb_array_length(payload->'connections') from ledger_private.transaction_payment_contents where id='contents-payment'),1,'historical connection appears once');
select ok((select payload->'connections'->0->>'endedAt' is not null from ledger_private.transaction_payment_contents where id='contents-payment'),'closure evidence is retained');
select is((select payload->'invoice'->'lines'->0->>'item_id' from ledger_private.transaction_payment_contents where id='contents-payment'),'contents-invoiced','frozen Item with no current placement remains attached');
select is((select payload->'invoice'->'lines'->0->>'description' from ledger_private.transaction_payment_contents where id='contents-payment'),'Frozen Item description','payment returns frozen text, not mutable Item text');
select is((select payload->'invoice'->>'total_minor_units' from ledger_private.transaction_payment_contents where id='contents-payment'),'125','exact Invoice amount retained separately');
select is((select payload->>'principalId' from ledger_private.transaction_payment_contents where id='contents-payment'),'principal-owner','caller identity bound by server');
select is((select jsonb_array_length(payload->'items') from ledger_private.transaction_payment_contents where id='contents-payment'),2,'one metadata row per retained physical Item');
select is((select payload->'items'->0->>'currentSpaceName' from ledger_private.transaction_payment_contents where id='contents-payment'),'Elsewhere','current location can be outside the payment Project');
select is((select payload->'items'->1->>'name' from ledger_private.transaction_payment_contents where id='contents-payment'),'Renamed chair','current name does not overwrite frozen description');
select is((select payload->'connections' from ledger_private.transaction_payment_contents where id='contents-empty'),'[]'::jsonb,'standalone payment has known empty connections');
select is((select payload->'invoice' from ledger_private.transaction_payment_contents where id='contents-empty'),'null'::jsonb,'standalone payment does not invent an Invoice');
select is(public.spike_read_transaction_detail('account-primary','contents-payment')->'paymentContents',
 (select payload from ledger_private.transaction_payment_contents where id='contents-payment'),
 'public detail composes the same authorized closed links and frozen Invoice');
select is((select row->'paymentContents' from jsonb_array_elements(
 public.spike_read_transaction_list('account-primary','project','contents-project')->'transactions') row
 where row->>'transactionId'='contents-payment'),
 (select payload from ledger_private.transaction_payment_contents where id='contents-payment'),
 'public browser composes identical payment history without a per-card request');
select is(public.spike_read_transaction_detail('account-primary','contents-payment')->'receipt',
 'null'::jsonb,'client payment history is not reclassified as a vendor receipt');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*) from ledger_private.transaction_payment_contents where account_id='account-primary'),0::bigint,'restricted financial reader cannot see payment history');
select throws_ok($$select public.spike_read_transaction_detail('account-primary','contents-payment')$$,
 '42501','transaction_not_available','restricted reader cannot reach payment history through public detail');
select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from ledger_private.transaction_payment_contents where account_id='account-primary'),0::bigint,'foreign principal cannot see payment history');
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from ledger_private.transaction_payment_contents where account_id='account-primary'),0::bigint,'same JWT loses payment history after removal');
select throws_ok($$select public.spike_read_transaction_detail('account-primary','contents-payment')$$,
 '42501','account_not_authorized','same JWT loses public payment detail after removal');
select is((select count(*) from ledger_private.item_client_payment_connections where account_id='account-primary'),0::bigint,'direct historical links also withdraw after removal');
select * from finish();
rollback;
