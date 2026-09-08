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
 from pg_proc p where p.oid='public.spike_read_property_management_report(text,text,text)'::regprocedure;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>>'{provenance,principalId}',
 'principal-restricted','Principal derived from auth mapping, not auth UUID or caller argument');
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>>'{items,0,marketValueMinorUnits}',
 '9007199254740993','Exact amount transported as decimal string');
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>>'{items,1,name}',
 'Fallback description','Display fallback matches native');
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>'{items,1,marketValueMinorUnits}',
 'null'::jsonb,'Unknown value remains explicit null');
select is(jsonb_array_length(spike_read_property_management_report('account-primary','report-read-project','USD')->'spaces'),
 1,'Referenced archived parent included, unused archive excluded');
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>>'{provenance,visibilityScopeID}',
 encode(digest('["account-primary","principal-restricted","report-read-project","physical-property-report-v1"]','sha256'),'hex'),
 'Native compact scope fingerprint matches');
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>'{provenance,source}',
 '{"kind":"authoritative"}'::jsonb,'Online provenance has no fake download checkpoint');
select throws_ok($$select spike_read_property_management_report('account-other','report-read-project','USD')$$,
 '42501','account_not_authorized','Cross-Account read denied');
select throws_ok($$select spike_read_property_management_report('account-primary','missing','USD')$$,
 '42501','property_report_project_unavailable','Missing Project not represented as empty report');
select throws_ok($$select spike_read_property_management_report('account-primary','report-read-project','CAD')$$,
 '22023','property_report_mixed_currency','No relabeling or conversion of known amounts');
select throws_ok($$select spike_read_property_management_report('account-primary','report-read-project','usd')$$,
 '22023','property_report_invalid_currency','Invalid units denied');
reset role;
update spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select throws_ok($$select spike_read_property_management_report('account-primary','report-read-project','USD')$$,
 '42501','account_not_authorized','Same JWT denied immediately after membership removal');
reset role;
set local role anon;
select throws_ok($$select spike_read_property_management_report('account-primary','report-read-project','USD')$$,
 '42501',null,'Anonymous cannot execute report RPC');
reset role;
set local role service_role;
select throws_ok($$select spike_read_property_management_report('account-primary','report-read-project','USD')$$,
 '42501',null,'Service role not granted report RPC');
reset role;
select * from finish();
rollback;
