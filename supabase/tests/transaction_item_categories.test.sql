begin;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('tx-cat-project','account-primary','client-existing','Categories',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
select id,'account-primary',id,'principal-owner' from unnest(array['tx-cat-a','tx-cat-b','tx-cat-c','tx-cat-d']) id;
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
select id||'-placement','account-primary',id,'project','tx-cat-project','2026-09-01','principal-owner'
from unnest(array['tx-cat-a','tx-cat-b','tx-cat-c','tx-cat-d']) id;
insert into public.spike_item_project_categories(id,account_id,project_id,item_id,category_id)
select id||'-placement','account-primary','tx-cat-project',id,'category-furnishings'
from unnest(array['tx-cat-a','tx-cat-b','tx-cat-c']) id;
update public.spike_item_placements set ended_at='2026-09-02',ended_by_principal_id='principal-owner' where item_id='tx-cat-c';
insert into public.spike_transactions(id,account_id,project_id,client_id,scope_kind,origin,type,amount_minor_units,currency,category_id)
values ('tx-cat-vendor','account-primary','tx-cat-project','client-existing','project','vendor_payment','purchase',400,'USD','category-system');
insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
select id||'-receipt','account-primary','tx-cat-vendor',id,'USD',100,case when id='tx-cat-b' then 'sold' else 'linked' end
from unnest(array['tx-cat-a','tx-cat-b','tx-cat-c','tx-cat-d']) id;
insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency)
values ('tx-cat-payment','account-primary','tx-cat-project','client-existing',400,'USD'),
 ('tx-cat-empty','account-primary','tx-cat-project','client-existing',100,'USD');
insert into ledger_private.item_client_payment_connections(id,account_id,project_id,client_id,item_id,placement_id,transaction_id,started_at,started_by_principal_id)
values ('tx-cat-connection','account-primary','tx-cat-project','client-existing','tx-cat-a','tx-cat-a-placement','tx-cat-payment','2026-09-01','principal-owner');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(public.spike_read_transaction_detail('account-primary','tx-cat-vendor')->'currentItemCategories',
 '[{"itemId":"tx-cat-a","placementId":"tx-cat-a-placement","categoryId":"category-furnishings"},{"itemId":"tx-cat-d","placementId":"tx-cat-d-placement","categoryId":null}]'::jsonb,
 'Only currently attached Project Items; missing attribution is explicit, not Transaction category');
select is(public.spike_read_transaction_detail('account-primary','tx-cat-payment')->'currentItemCategories',
 '[{"itemId":"tx-cat-a","placementId":"tx-cat-a-placement","categoryId":"category-furnishings"}]'::jsonb,
 'Client payment uses current canonical connection, not vendor receipt');
select is(public.spike_read_transaction_detail('account-primary','tx-cat-empty')->'currentItemCategories','[]'::jsonb,'No linked Items is known empty');
select is(jsonb_array_length(public.spike_read_transaction_detail('account-primary','tx-cat-vendor')->'receipt'->'items'),4,'Historical receipt membership is preserved');
reset role;
update public.spike_budget_categories set lifecycle='archived' where id='category-furnishings';
set local role authenticated;
select is(public.spike_read_transaction_detail('account-primary','tx-cat-payment')#>>'{currentItemCategories,0,categoryId}',
 'category-furnishings','Archived attribution remains readable');
reset role;
update public.spike_budget_categories set kind='fee' where id='category-furnishings';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is(public.spike_read_transaction_detail('account-primary','tx-cat-vendor')#>'{currentItemCategories,0,categoryId}',
 'null'::jsonb,'Restricted reader cannot learn hidden category ID through visible receipt');
select is((select count(*) from ledger_private.transaction_current_item_categories where id='tx-cat-payment'),0::bigint,'Payment relationships remain full-only');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select is((select count(*) from ledger_private.transaction_current_item_categories where id like 'tx-cat-%'),0::bigint,'Foreign Account cannot read relationship projection');
reset role;
update ledger_private.item_client_payment_connections set ended_at='2026-09-03',ended_by_principal_id='principal-owner' where id='tx-cat-connection';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(public.spike_read_transaction_detail('account-primary','tx-cat-payment')->'currentItemCategories','[]'::jsonb,'Ended connection leaves payment intact without current attribution');
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select is((select count(*) from ledger_private.transaction_current_item_categories where id like 'tx-cat-%'),0::bigint,'Same token loses projection on removal');
reset role;
set local role anon;
select throws_ok('select * from ledger_private.transaction_current_item_categories','42501',null,'Anonymous projection access ungranted');
reset role;
set local role service_role;
select throws_ok('select * from ledger_private.transaction_current_item_categories','42501',null,'Service API projection access ungranted');
reset role;
select ok(not has_table_privilege('authenticated','ledger_private.transaction_current_item_categories','INSERT,UPDATE,DELETE'), 'No new writer grants');
select * from finish();
rollback;
