begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('report-read-project','account-primary','client-existing','Report property',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,name,description,market_value_minor_units,market_value_currency,created_by_principal_id)
values ('report-read-exact','account-primary','Exact','',9007199254740993,'USD','principal-owner'),
 ('report-read-unknown','account-primary',null,'Fallback description',null,null,'principal-owner');
insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
values ('report-read-room','account-primary','project','report-read-project','Old room','archived'),
 ('report-read-unused','account-primary','project','report-read-project','Unused old room','archived');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at,started_by_principal_id)
values ('report-read-p1','account-primary','report-read-exact','project','report-read-project','report-read-room','2026-09-01','principal-owner'),
 ('report-read-p2','account-primary','report-read-unknown','project','report-read-project',null,'2026-09-01','principal-owner');
select ok(not p.prosecdef and p.provolatile='s','Invoker with one stable statement snapshot')
 from pg_proc p where p.oid='public.spike_read_client_summary_physical_report(text,text)'::regprocedure;
insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency)
values ('report-payment-a','account-primary','report-read-project','client-existing',100,'USD'),
 ('report-payment-b','account-primary','report-read-project','client-existing',200,'USD');
insert into ledger_private.item_client_payment_connections(id,account_id,project_id,client_id,item_id,
 placement_id,transaction_id,started_at,started_by_principal_id)
values ('report-link-a','account-primary','report-read-project','client-existing','report-read-exact',
 'report-read-p1','report-payment-a','2026-09-02','principal-owner'),
 ('report-link-b','account-primary','report-read-project','client-existing','report-read-exact',
 'report-read-p1','report-payment-b','2026-09-02','principal-owner');

insert into spike_item_project_categories(id,account_id,project_id,item_id,category_id)
values ('report-read-p1','account-primary','report-read-project','report-read-exact','category-furnishings');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>>'{client,clientId}',
 'client-existing','Exact Project Client included');
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>>'{client,kind}',
 'known','Readable Client is known');
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>>'{items,0,category,known,categoryId}',
 'category-furnishings','Physical category comes from exact placement metadata');
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>'{items,1,category}',
 '{"unavailable":{}}'::jsonb,'Missing category is explicit, not uncategorized');
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>>'{items,0,accounting,resolution}',
 'accountedFor','Actual current Client Purchase evidence qualifies Item');
select is(jsonb_array_length(spike_read_client_summary_physical_report('account-primary','report-read-project')#>'{items,0,accounting,evidence,clientPaidPurchases}'),
 2,'Both Purchase links preserved without duplicating physical Item');
select is(jsonb_array_length(spike_read_client_summary_physical_report('account-primary','report-read-project')->'items'),
 2,'Each physical Item appears once');
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>'{items,1,accounting}',
 'null'::jsonb,'Missing accounting remains unknown');
select ok(not (spike_read_client_summary_physical_report('account-primary','report-read-project')->'items'->0 ? 'marketValueMinorUnits'),
 'No financial amount in physical report');
select ok(not (spike_read_client_summary_physical_report('account-primary','report-read-project') ? 'currency'),
 'Physical report has no currency prerequisite');
select is(jsonb_array_length(spike_read_client_summary_physical_report('account-primary','report-read-project')->'spaces'),
 1,'Referenced archived Space retained, unused archive excluded');
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>>'{provenance,visibilityScopeID}',
 encode(digest('["account-primary","principal-owner","report-read-project","client-summary-physical-v1"]','sha256'),'hex'),
 'Exact native Client Summary scope profile');
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>>'{provenance,authorityVersion}',
 'client-summary-physical-v1','Client physical authority profile');
select throws_ok($$select spike_read_client_summary_physical_report('account-other','report-read-project')$$,
 '42501','account_not_authorized','Foreign Account denied');
select throws_ok($$select spike_read_client_summary_physical_report('account-primary','missing')$$,
 '42501','client_summary_physical_project_unavailable','Missing Project is not empty');
reset role;
update spike_budget_categories set lifecycle='archived',display_name='Renamed furnishings' where id='category-furnishings';
set local role authenticated;
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>>'{items,0,category,known,name}',
 'Renamed furnishings','Archived category rename remains readable');
reset role;
update spike_budget_categories set display_name=U&'\200B\0085' where id='category-furnishings';
set local role authenticated;
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>'{items,0,category}',
 '{"unavailable":{}}'::jsonb,'Unicode whitespace-only imported category matches native unavailable state');
reset role;
update spike_budget_categories set display_name='Renamed furnishings' where id='category-furnishings';
update spike_budget_categories set visibility_class='company_financial' where id='category-furnishings';
update spike_account_memberships set financial_access='limited'
 where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>'{items,0,category}',
 '{"unavailable":{}}'::jsonb,'Same JWT downgrade hides category identity and label');
select is(spike_read_client_summary_physical_report('account-primary','report-read-project')#>'{items,0,accounting}',
 'null'::jsonb,'Same JWT downgrade hides Purchase links');
reset role;
update spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select throws_ok($$select spike_read_client_summary_physical_report('account-primary','report-read-project')$$,
 '42501','account_not_authorized','Same JWT removed membership denied immediately');
reset role;
select ok(not has_function_privilege('anon','public.spike_read_client_summary_physical_report(text,text)','EXECUTE'),
 'Anonymous execution not granted');
select ok(not has_function_privilege('service_role','public.spike_read_client_summary_physical_report(text,text)','EXECUTE'),
 'No privileged-service fallback granted');
select * from finish();
rollback;
