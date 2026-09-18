begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_budget_categories(id,account_id,display_name,kind,presentation_order,created_at_ms,updated_at_ms)
values('source-second-category','account-primary','Second source category','itemized',99,1,1);
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('source-project','account-primary','client-existing','Source',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
select 'source-item-'||v,'account-primary',v,'principal-owner' from unnest(array['a','b']) v;
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id,ended_at,ended_by_principal_id)
select 'source-old-'||v,'account-primary','source-item-'||v,'project','source-project','2024-01-01','principal-owner','2025-01-01','principal-owner'
from unnest(array['a','b']) v;
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
select 'source-inventory-'||v,'account-primary','source-item-'||v,'business_inventory','2025-01-01','principal-owner'
from unnest(array['a','b']) v;
insert into ledger_private.inventory_source_entries(id,account_id,item_id,inventory_placement_id,source_placement_id,source_project_id,
 source_category_id,amount_minor_units,currency,created_at,created_by_principal_id)
select 'source-entry-'||v,'account-primary','source-item-'||v,'source-inventory-'||v,'source-old-'||v,'source-project',
 case when v='a' then 'category-furnishings' else 'source-second-category' end,
 case when v='a' then 9007199254740993 else 321 end,'USD','2025-01-01','principal-owner'
from unnest(array['a','b']) v;
create function pg_temp.source_command(op text) returns text language sql as $$
select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
 'projectId','source-project','contractVersion','return-inventory-to-source-v1','createdAtMs','1788523200000',
 'items',(select jsonb_agg(jsonb_build_object('itemId','source-item-'||v,'placementId','source-inventory-'||v,
 'inventoryEntryId','source-entry-'||v,'projectPlacementId','source-new-'||v,'occurrenceId','source-charge-'||v) order by v)
 from unnest(array['a','b']) v))::text $$;
create temp table cash_before as select count(*) n from public.spike_transactions;
select throws_ok($$update ledger_private.inventory_source_entries set amount_minor_units=1$$,'55000',null,'Entry basis immutable');
select throws_ok($$delete from ledger_private.inventory_source_entries$$,'55000',null,'Entry history retained');
select throws_ok($$truncate ledger_private.inventory_source_entries cascade$$,'55000',null,'Entry truncate prohibited');
select ok(not has_table_privilege('authenticated','ledger_private.inventory_source_entries','INSERT'),'No client-authored basis');
select ok(not has_table_privilege('service_role','ledger_private.inventory_source_entries','INSERT'),'No service API basis writer');
savepoint independent_sale;
update public.spike_accounts set furnishings_category_id='category-furnishings' where id='account-primary';
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('mason','account-primary','client-existing','Mason',now(),now(),1,1,'principal-owner');
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
select is((public.spike_sell_inventory_items(jsonb_build_object('operationId','source-independent-sale','accountId','account-primary',
 'actorPrincipalId','principal-owner','projectId','mason','contractVersion','inventory-sale-v1','createdAtMs','1788523200000',
 'currency','USD','items',jsonb_build_array(jsonb_build_object('itemId','source-item-a','placementId','source-inventory-a',
 'priceRevision','0','reviewedPriceMinorUnits','777','newPlacementId','mason-placement','occurrenceId','mason-charge')))::text)).phase,
 'applied','Kristen source provenance does not block ordinary Sell to Mason');
select is((select amount_minor_units from ledger_private.item_charge_occurrences where id='mason-charge'),777::bigint,'Sell uses independent new price, not frozen return basis');
select is((select amount_minor_units from ledger_private.inventory_source_entries where id='source-entry-a'),9007199254740993::bigint,'Sell preserves immutable source entry');
select is((select count(*) from ledger_private.inventory_source_returns where account_id='account-primary'),0::bigint,'Sell creates no source return fact');
rollback to independent_sale;
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
set local role authenticated;
select is(public.spike_read_inventory_source_return_review('account-primary',array['source-item-a','source-item-b'])->'items'->0->>'amountMinorUnits',
 '9007199254740993','Review transports exact frozen Int64 basis');
select throws_ok($$select public.spike_read_inventory_source_return_review('account-other',array['source-item-a'])$$,'42501',null,'Foreign Account denied');
select throws_ok($$select public.spike_read_inventory_source_return_review('account-primary',array['source-item-a','source-item-a'])$$,'22023',null,'Duplicate selection denied');
select is((public.spike_return_inventory_to_source(jsonb_set(pg_temp.source_command('source-stale')::jsonb,
 '{items,1,inventoryEntryId}','"missing"')::text)).error_code,'source_return_entry_unavailable','Stale second entry rejects atomically');
reset role;
select is((select count(*) from public.spike_item_placements where id like 'source-inventory-%' and ended_at is null),2::bigint,'No partial movement');
select is((select count(*) from ledger_private.inventory_source_returns where account_id='account-primary'),0::bigint,'No partial occurrence');
savepoint unauthorized_destination;
update public.spike_projects set lifecycle='archived' where id='source-project';
select is((public.spike_return_inventory_to_source(pg_temp.source_command('source-archived'))).error_code,
 'source_return_destination_unavailable','Archived source cannot be restored');
rollback to unauthorized_destination;
savepoint hidden_basis;
update public.spike_budget_categories set kind='fee' where account_id='account-primary' and id='category-furnishings';
update public.spike_account_memberships set financial_access='none' where account_id='account-primary' and principal_id='principal-owner';
select is((public.spike_return_inventory_to_source(pg_temp.source_command('source-hidden'))).error_code,
 'source_return_entry_unavailable','Hidden category basis is unavailable to restricted member');
select throws_ok($$select public.spike_read_inventory_source_return_review('account-primary',array['source-item-a'])$$,'42501',null,'Review does not leak hidden amount');
rollback to hidden_basis;
set local role authenticated;
select is((public.spike_return_inventory_to_source(pg_temp.source_command('source-apply'))).phase,'applied','Authenticated exact source return');
select is((public.spike_return_inventory_to_source(pg_temp.source_command('source-apply'))).phase,'applied','Identical retry returns original result');
select throws_ok($$select public.spike_return_inventory_to_source(pg_temp.source_command('source-apply')||' ')$$,'23505',null,'Changed persisted bytes cannot reuse identity');
select is((public.spike_return_inventory_to_source(pg_temp.source_command('source-second'))).error_code,'source_return_placement_stale','Second identity cannot duplicate return');
select throws_ok($$select public.spike_read_inventory_source_return_review('account-primary',array['source-item-a'])$$,'42501',null,'Consumed entry no longer eligible');
reset role;
select is((select count(*) from ledger_private.inventory_source_returns where account_id='account-primary'),2::bigint,'Exactly one return per entry');
select is((select amount_minor_units from ledger_private.item_charge_occurrences where id='source-charge-a'),9007199254740993::bigint,'Exact frozen basis restored');
select is((select amount_minor_units from ledger_private.item_charge_occurrences where id='source-charge-b'),321::bigint,'Each Item retains own amount');
select is((select category_id from ledger_private.item_charge_occurrences where id='source-charge-b'),'source-second-category','Bulk restores each distinct frozen category');
select is((select count(*) from ledger_private.item_charge_occurrences where id like 'source-charge-%' and price_basis='inventory_entry' and withdrawn_at is null),2::bigint,'Positive unpaid charge facts use explicit source-entry basis');
select is((select count(*) from public.spike_transactions),(select n from cash_before),'No cash Transaction manufactured');
select is((select count(*) from ledger_private.item_project_prices where item_id like 'source-item-%'),0::bigint,'No repricing or mutable price fallback');
select is(public.spike_read_project_budget('account-primary','source-project','USD')->>'overallUnpaidMinorUnits','9007199254741314','Restored amounts increase unpaid budget exactly once');
select is(jsonb_array_length(public.spike_read_project_invoicing_items('account-primary','source-project')->'rows'),2,'Both returned charges available in Invoicing');
select is((select count(*) from public.spike_item_placements where id like 'source-new-%' and project_id='source-project' and ended_at is null),2::bigint,'Source placement restored');
select * from finish();
rollback;
