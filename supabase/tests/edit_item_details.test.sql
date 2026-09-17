begin;
set local search_path=public,extensions;
select no_plan();
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
insert into public.spike_items(id,account_id,description,name,sku,notes,workflow_status,bookmark,created_by_principal_id)
values('details-a','account-primary','Fallback',null,'old','  Raw notes  ','legacy-state',null,'principal-owner'),
 ('details-b','account-primary','Second',null,null,null,null,null,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('details-other','account-other','Other Account Item','principal-other');
create function pg_temp.details_command(op text, fields jsonb, selections jsonb default '[{"itemId":"details-a","expectedRevision":"1"}]')
returns text language sql as $$
 select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
 'contractVersion','item-details-edit-v1','createdAtMs','1000','items',selections,'changes',fields)::text;
$$;
select is((ledger_private.edit_item_details(pg_temp.details_command('details-edit','{"sku":null,"bookmark":false}'))).phase,'applied','Explicit clear/false apply');
select is((select name from spike_items where id='details-a'),null::text,'Omitted legacy name stays absent');
select is((select description from spike_items where id='details-a'),'Fallback','Fallback evidence unchanged');
select is((select notes from spike_items where id='details-a'),'  Raw notes  ','Omitted notes preserved exactly');
select is((select workflow_status from spike_items where id='details-a'),'legacy-state','Unknown status preserved');
select is((select sku from spike_items where id='details-a'),null::text,'SKU explicitly cleared');
select is((select bookmark from spike_items where id='details-a'),false,'False is not omission');
select is((ledger_private.edit_item_details(pg_temp.details_command('details-edit','{"sku":null,"bookmark":false}'))).phase,'applied','Identical retry accepted');
select is((select revision from spike_items where id='details-a'),2::bigint,'Replay does not increment twice');
select is((ledger_private.edit_item_details(pg_temp.details_command('details-stale','{"name":"wrong"}'))).error_code,'item_edit_stale','Stale revision rejected');
select is((ledger_private.edit_item_details(pg_temp.details_command('details-bulk','{"status":"returned"}',
 '[{"itemId":"details-a","expectedRevision":"2"},{"itemId":"details-b","expectedRevision":"9"}]'))).error_code,'item_edit_stale','Bulk stale member rejects batch');
select is((select workflow_status from spike_items where id='details-a'),'legacy-state','Earlier bulk update rolled back');
select is((select revision from spike_items where id='details-a'),2::bigint,'Rollback preserves revision');
select throws_ok($$select ledger_private.edit_item_details(pg_temp.details_command('details-money','{"amount":100}'))$$,
 '22023','Invalid Item edit command','Financial fields forbidden');
select throws_ok($$select ledger_private.edit_item_details(pg_temp.details_command('details-empty','{}'))$$,
 '22023','Invalid Item edit command','Empty patch forbidden');
select throws_ok($$select ledger_private.edit_item_details(pg_temp.details_command('details-edit','{"name":"changed retry"}'))$$,
 '23505','Operation identity conflict','An accepted operation cannot be reused for different changes');
select throws_ok($$select ledger_private.edit_item_details(
 (pg_temp.details_command('details-actor','{"name":"wrong"}')::jsonb || '{"actorPrincipalId":"principal-other"}'::jsonb)::text)$$,
 '42501','Authenticated actor required','Claimed actor cannot replace authenticated principal');
select throws_ok($$select ledger_private.edit_item_details(
 (pg_temp.details_command('details-account','{"name":"wrong"}')::jsonb || '{"accountId":"details-inaccessible-account"}'::jsonb)::text)$$,
 '42501','Item edit access required','Account without active membership is denied');
select is((ledger_private.edit_item_details(pg_temp.details_command('details-missing','{"name":"wrong"}',
 '[{"itemId":"details-inaccessible-item","expectedRevision":"1"}]'))).error_code,
 'item_edit_unavailable','Missing or out-of-scope Item cannot be edited');
select is((ledger_private.edit_item_details(pg_temp.details_command('details-cross-tenant','{"name":"wrong"}',
 '[{"itemId":"details-other","expectedRevision":"1"}]'))).error_code,
 'item_edit_unavailable','Existing second-tenant Item is unavailable through authorized Account');
select is((select revision from spike_items where id='details-other'),1::bigint,'Second-tenant Item remains untouched');
update spike_account_memberships set state='removed'
 where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select ledger_private.edit_item_details(pg_temp.details_command('details-edit','{"sku":null,"bookmark":false}'))$$,
 '42501','Item edit access required','Revoked member cannot replay a previously accepted operation');
select is((select revision from spike_items where id='details-a'),2::bigint,'Denied attempts leave Item unchanged');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.edit_item_details(pg_temp.details_command('details-anon','{"name":"wrong"}'))$$,
 '42501','Authenticated actor required','Anonymous actor denied');
select ok(has_function_privilege('authenticated','public.spike_edit_item_details(text)','execute'),'Authenticated endpoint available');
select ok(not has_function_privilege('anon','public.spike_edit_item_details(text)','execute'),'Anonymous endpoint denied');
select ok(not has_function_privilege('service_role','public.spike_edit_item_details(text)','execute'),'Service role is not an app writer');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
update spike_account_memberships set state='active',financial_access='none'
 where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select is((public.spike_edit_item_details(pg_temp.details_command('details-endpoint','{"notes":"Member edit"}',
 '[{"itemId":"details-b","expectedRevision":"1"}]'))).phase,'applied','Non-financial member uses actual endpoint');
reset role;
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('details-market','account-primary','Market estimate','principal-owner');
create function pg_temp.market_command(op text, fields jsonb, revision text default '1')
returns text language sql as $$
 select (pg_temp.details_command(op,fields,jsonb_build_array(jsonb_build_object(
   'itemId','details-market','expectedRevision',revision)))::jsonb
   || jsonb_build_object('contractVersion','item-details-edit-v2'))::text;
$$;
set local role authenticated;
select is((public.spike_edit_item_details(pg_temp.market_command('market-set',
 '{"marketValue":{"minorUnits":"9007199254740993","currency":"USD"}}'))).phase,'applied','Market estimate member edit applies exactly');
select is((public.spike_edit_item_details(pg_temp.market_command('market-set',
 '{"marketValue":{"minorUnits":"9007199254740993","currency":"USD"}}'))).contract_version,'item-details-edit-v2','V2 retry preserves receipt version');
reset role;
select is((select market_value_minor_units from spike_items where id='details-market'),9007199254740993::bigint,'Market amount does not round');
select is((select revision from spike_items where id='details-market'),2::bigint,'V2 replay applies once');
select is((ledger_private.edit_item_details(pg_temp.market_command('market-stale','{"marketValue":null}'))).error_code,'item_edit_stale','Stale clear rejected');
select is((ledger_private.edit_item_details(pg_temp.market_command('market-zero','{"marketValue":{"minorUnits":"0","currency":"USD"}}','2'))).phase,'applied','Zero is a value');
select is((select market_value_minor_units from spike_items where id='details-market'),0::bigint,'Zero persisted');
select is((ledger_private.edit_item_details(pg_temp.market_command('market-clear','{"marketValue":null}','3'))).phase,'applied','Explicit clear applies');
select ok((select market_value_minor_units is null and market_value_currency is null from spike_items where id='details-market'),'Clear removes amount and currency together');
select throws_ok(format('select ledger_private.edit_item_details(%L)',pg_temp.market_command('market-negative',
 '{"marketValue":{"minorUnits":"-1","currency":"USD"}}','4')),'22023','Invalid market value','Negative new estimate refused');
select throws_ok(format('select ledger_private.edit_item_details(%L)',pg_temp.market_command('market-overflow',
 '{"marketValue":{"minorUnits":"9223372036854775808","currency":"USD"}}','4')),'22023','Invalid market value','Overflow refused');
select throws_ok(format('select ledger_private.edit_item_details(%L)',pg_temp.market_command('market-missing-currency',
 '{"marketValue":{"minorUnits":"1"}}','4')),'22023','Invalid market value','Incomplete money refused');
select * from finish();
rollback;
