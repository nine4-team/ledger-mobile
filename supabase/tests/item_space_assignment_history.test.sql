begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
 values('space-change-project','account-primary','client-existing','Space assignment QA',now(),now(),1,1,'principal-owner');
insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
 select 'space-change-'||v,'account-primary','project','space-change-project',v,'active'
 from unnest(array['a','b']) v;
insert into public.spike_items(id,account_id,description,created_by_principal_id)
 values('space-change-item','account-primary','Same physical Item','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at,started_by_principal_id)
 values('space-change-placement','account-primary','space-change-item','project','space-change-project','space-change-a','2026-01-01','principal-owner');
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,created_by_principal_id)
 values('space-change-charge','account-primary','space-change-project','space-change-item','space-change-placement','category-furnishings',12500,'USD','principal-owner');
create temp table original_charge as select * from ledger_private.item_charge_occurrences where id='space-change-charge';
select is((select revision from public.item_placement_versions where id='space-change-item'),1::bigint,'First placement has its own token');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select lives_ok($$update public.spike_item_placements set space_id='space-change-b' where id='space-change-placement'$$,'Change Space without replacing Project placement');
select is((select revision from public.item_placement_versions where id='space-change-item'),2::bigint,'Space change advances placement token');
select is((select revision from public.spike_items where id='space-change-item'),1::bigint,'Descriptive revision remains independent');
select is((select count(*) from public.spike_item_placements where item_id='space-change-item'),1::bigint,'No invented custody or billing cycle');
select results_eq('select * from ledger_private.item_charge_occurrences where id=''space-change-charge''','select * from original_charge','Original charge and placement link unchanged');
select is((select sync_current_item_count from public.spike_spaces where id='space-change-a'),0::bigint,'Old Space count decremented');
select is((select sync_current_item_count from public.spike_spaces where id='space-change-b'),1::bigint,'New Space count incremented');
select is((select from_space_id||'>'||to_space_id from ledger_private.item_space_changes where item_id='space-change-item'),'space-change-a>space-change-b','Preserve old and new Space');
select is((select changed_by_principal_id from ledger_private.item_space_changes where item_id='space-change-item'),'principal-owner','Preserve authenticated actor');
select throws_ok($$delete from ledger_private.item_space_changes where item_id='space-change-item'$$,'55000',null,'Cannot delete Space change history');
select lives_ok($$update public.spike_item_placements set space_id=null where id='space-change-placement'$$,'Clear Space without ending Project placement');
select is((select sync_current_item_count from public.spike_spaces where id='space-change-b'),0::bigint,'Clearing updates Space count');
select is((select revision from public.item_placement_versions where id='space-change-item'),3::bigint,'Clear advances token');
select is((select count(*) from ledger_private.item_space_changes where item_id='space-change-item'),2::bigint,'Clear retains previous Space assignment');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$update public.spike_item_placements set space_id='space-change-a' where id='space-change-placement'$$,'42501',null,'Space edit cannot fabricate actor');
select is((select revision from public.item_placement_versions where id='space-change-item'),3::bigint,'Rejected change rolls back token');
select lives_ok($$update public.spike_item_placements set ended_at='2026-09-17',ended_by_principal_id='principal-owner' where id='space-change-placement'$$,'Existing movement/import close remains supported');
select is((select revision from public.item_placement_versions where id='space-change-item'),4::bigint,'Movement invalidates old Space intent');
select throws_ok($$update public.spike_item_placements set space_id='space-change-a' where id='space-change-placement'$$,'55000',null,'Closed placement Space remains immutable');
select ok(not has_table_privilege('authenticated','public.item_placement_versions','UPDATE'),'App cannot set concurrency token');
select ok(not has_table_privilege('authenticated','ledger_private.item_space_changes','INSERT'),'App cannot forge Space history');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
select is((select count(*) from public.item_placement_versions where id='space-change-item'),1::bigint,'Physical token readable without financial access');
reset role;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
set local role authenticated;
select is((select count(*) from public.item_placement_versions where id='space-change-item'),0::bigint,'Foreign Account cannot read token');
reset role;
select * from finish();
rollback;
