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
insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency)
values ('report-payment-a','account-primary','report-read-project','client-existing',100,'USD'),
 ('report-payment-b','account-primary','report-read-project','client-existing',200,'USD');
insert into ledger_private.item_client_payment_connections(id,account_id,project_id,client_id,item_id,
 placement_id,transaction_id,started_at,started_by_principal_id)
values ('report-link-a','account-primary','report-read-project','client-existing','report-read-exact',
 'report-read-p1','report-payment-a','2026-09-02','principal-owner'),
 ('report-link-b','account-primary','report-read-project','client-existing','report-read-exact',
 'report-read-p1','report-payment-b','2026-09-02','principal-owner');
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
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>'{items,0,accounting}',
 'null'::jsonb,'Restricted member receives no payment relationship evidence');
select is((select count(id) from ledger_private.item_client_payment_connections where account_id='account-primary'),0::bigint,
 'RLS also denies direct restricted relationship reads');
select throws_ok($$select spike_read_property_management_report('account-other','report-read-project','USD')$$,
 '42501','account_not_authorized','Cross-Account read denied');
select throws_ok($$select spike_read_property_management_report('account-primary','missing','USD')$$,
 '42501','property_report_project_unavailable','Missing Project not represented as empty report');
select throws_ok($$select spike_read_property_management_report('account-primary','report-read-project','CAD')$$,
 '22023','property_report_mixed_currency','No relabeling or conversion of known amounts');
select throws_ok($$select spike_read_property_management_report('account-primary','report-read-project','usd')$$,
 '22023','property_report_invalid_currency','Invalid units denied');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>>'{items,0,accounting,resolution}',
 'accountedFor','Full-access current Client payment qualifies exact Item');
select is(jsonb_array_length(spike_read_property_management_report('account-primary','report-read-project','USD')#>'{items,0,accounting,evidence,clientPaidPurchases}'),
 2,'Two payment relationships remain one physical Item with both facts');
select is(jsonb_array_length(spike_read_property_management_report('account-primary','report-read-project','USD')->'items'),
 2,'Multiple payments do not duplicate physical report rows');
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>>'{items,0,accounting,evidence,clientPaidPurchases,0,classification,scope,clientId}',
 'client-existing','Exact Project Client classification is present');
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>'{items,0,accounting,relationshipAbsenceIsAuthoritative}',
 'false'::jsonb,'Positive evidence does not claim complete relationship discovery');
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>'{items,1,accounting}',
 'null'::jsonb,'Unlinked Item remains unknown, not silently Unaccounted For');
select throws_ok('select started_by_principal_id from ledger_private.item_client_payment_connections',
 '42501',null,'Read grant does not expose relationship actor history');
select throws_ok('delete from ledger_private.item_client_payment_connections',
 '42501',null,'Full member gains no relationship write authority');
reset role;
update spike_account_memberships set financial_access='limited'
 where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>'{items,0,accounting}',
 'null'::jsonb,'Same JWT loses relationship evidence immediately on financial downgrade');
reset role;
update spike_account_memberships set financial_access='full'
 where account_id='account-primary' and principal_id='principal-owner';
update ledger_private.item_client_payment_connections set ended_at='2026-09-03',ended_by_principal_id='principal-owner'
 where id in ('report-link-a','report-link-b');
set local role authenticated;
select is((select count(id) from ledger_private.item_client_payment_connections where account_id='account-primary'),0::bigint,
 'Closed relationship history is retained but excluded from current read policy');
select is(spike_read_property_management_report('account-primary','report-read-project','USD')#>'{items,0,accounting}',
 'null'::jsonb,'Closed links cannot keep an Item eligible');
reset role;
insert into ledger_private.item_client_payment_connections(id,account_id,project_id,client_id,item_id,
 placement_id,transaction_id,started_at,started_by_principal_id)
values ('report-link-departed','account-primary','report-read-project','client-existing','report-read-unknown',
 'report-read-p2','report-payment-a','2026-09-02','principal-owner');
update public.spike_item_placements set ended_at='2026-09-03',ended_by_principal_id='principal-owner'
 where id='report-read-p2';
set local role authenticated;
select is((select count(id) from ledger_private.item_client_payment_connections where account_id='account-primary'),0::bigint,
 'Open link on a departed placement is not current read evidence');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
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
