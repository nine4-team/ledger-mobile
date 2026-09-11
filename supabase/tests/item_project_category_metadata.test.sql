begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('category-project','account-primary','client-existing','Category',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('category-item','account-primary','Chair','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
values ('category-placement','account-primary','category-item','project','category-project','2026-01-01','principal-owner');
select throws_ok($$insert into spike_item_project_categories(id,account_id,project_id,item_id,category_id)
 values ('category-placement','account-primary','missing','category-item','category-furnishings')$$,
 '23503',null,'Rejects wrong Project relationship');
select throws_ok($$insert into spike_item_project_categories(id,account_id,project_id,item_id,category_id)
 values ('category-placement','account-other','category-project','category-item','category-furnishings')$$,
 '23503',null,'Rejects foreign Account/category');
insert into spike_item_project_categories(id,account_id,project_id,item_id,category_id)
 values ('category-placement','account-primary','category-project','category-item','category-furnishings');
select throws_ok($$update spike_item_project_categories set category_id='category-design-fee' where id='category-placement'$$,
 '55000',null,'Corrections require next revision');
select throws_ok('delete from spike_item_project_categories','55000',null,'Retained category facts cannot be deleted');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select category_id from spike_item_project_categories where id='category-placement'),
 'category-furnishings','Ordinary metadata visible to active limited member');
select throws_ok($$update spike_item_project_categories set revision=2 where id='category-placement'$$,
 '42501',null,'No category writer granted');
reset role;
update spike_budget_categories set lifecycle='archived' where id='category-furnishings';
set local role authenticated;
select is((select count(*) from spike_item_project_categories where id='category-placement'),1::bigint,
 'Archived category remains resolvable without Project allocation evidence');
reset role;
update spike_budget_categories set visibility_class='company_financial' where id='category-furnishings';
set local role authenticated;
select is((select count(*) from spike_item_project_categories where id='category-placement'),0::bigint,
 'Hidden category identity is denied along with its label');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from spike_item_project_categories where id='category-placement'),1::bigint,
 'Full financial member can resolve hidden category');
reset role;
update spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select is((select count(*) from spike_item_project_categories where id='category-placement'),0::bigint,
 'Same JWT loses metadata after membership removal');
reset role;
update spike_item_placements set ended_at='2026-02-01',ended_by_principal_id='principal-owner' where id='category-placement';
select throws_ok($$update spike_item_project_categories set revision=2 where id='category-placement'$$,
 '55000',null,'Ended placement attribution cannot be rewritten');
select is((select count(*) from spike_item_project_categories where id='category-placement'),1::bigint,
 'Historical attribution remains stored after departure');
select * from finish();
rollback;
