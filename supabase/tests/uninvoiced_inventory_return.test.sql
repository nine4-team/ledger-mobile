begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('return-project','account-primary','client-existing','Return QA',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
select 'return-item-'||v,'account-primary',v,'principal-owner' from unnest(array['a','b']) v;
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id,ended_at,ended_by_principal_id)
select 'return-original-'||v,'account-primary','return-item-'||v,'business_inventory','2024-01-01','principal-owner','2025-01-01','principal-owner'
from unnest(array['a','b']) v;
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
select 'return-project-'||v,'account-primary','return-item-'||v,'project','return-project','2025-01-01','principal-owner'
from unnest(array['a','b']) v;
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
 amount_minor_units,currency,created_at,created_by_principal_id)
select 'return-charge-'||v,'account-primary','return-project','return-item-'||v,'return-project-'||v,'category-furnishings',
 12345,'USD','2025-01-01','principal-owner' from unnest(array['a','b']) v;
create function pg_temp.return_command(op text, revision text default '1') returns text language sql as $$
 select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
 'projectId','return-project','contractVersion','return-uninvoiced-items-v1','createdAtMs','1788523200000',
 'items',(select jsonb_agg(jsonb_build_object('itemId','return-item-'||v,'placementId','return-project-'||v,
   'chargeId','return-charge-'||v,'expectedChargeRevision',case when v='b' then revision else '1' end,
   'inventoryPlacementId','return-inventory-'||v,'returnOccurrenceId','return-occurrence-'||v) order by v)
   from unnest(array['a','b']) v))::text
$$;
create temp table before_transactions as select count(*) n from public.spike_transactions;
select is((select count(*) from ledger_private.item_return_reviews where account_id='account-primary' and project_id='return-project'
 and not withdrawn and not has_live_invoice and not has_collected_invoice),2::bigint,'New charge derives open return evidence');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select is(public.spike_read_uninvoiced_return_review('account-primary','return-project',array['return-item-a','return-item-b']),
 '{"accountId":"account-primary","principalId":"principal-owner","projectId":"return-project","items":[{"itemId":"return-item-a","placementId":"return-project-a","chargeId":"return-charge-a","revision":"1"},{"itemId":"return-item-b","placementId":"return-project-b","chargeId":"return-charge-b","revision":"1"}]}'::jsonb,
 'Authenticated review returns exact selection references without amounts');
select throws_ok($$select public.spike_read_uninvoiced_return_review('account-primary','other-project',array['return-item-a'])$$,'42501',null,'Review cannot cross Project scope');
select throws_ok($$select public.spike_read_uninvoiced_return_review('account-primary','return-project',array['return-item-a','return-item-a'])$$,'22023',null,'Review rejects duplicate selection');
reset role;
select is((ledger_private.return_uninvoiced_items(pg_temp.return_command('return-stale','2'))).error_code,
 'return_charge_stale','Stale second charge rejects whole return');
select is((select count(*) from public.spike_item_placements where id in ('return-project-a','return-project-b') and ended_at is null),2::bigint,'No partial physical movement');
select is((select count(*) from ledger_private.item_charge_occurrences where id in ('return-charge-a','return-charge-b') and withdrawn_at is null),2::bigint,'No partial withdrawal');
savepoint origin_case;
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('return-item-c','account-primary','No predecessor','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
values('return-project-c','account-primary','return-item-c','project','return-project','2025-01-01','principal-owner');
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
 amount_minor_units,currency,created_at,created_by_principal_id)
values('return-charge-c','account-primary','return-project','return-item-c','return-project-c','category-furnishings',
 12345,'USD','2025-01-01','principal-owner');
select is((ledger_private.return_uninvoiced_items(replace(pg_temp.return_command('return-origin'),'-b"','-c"'))).error_code,
 'return_origin_unproven','Missing Inventory predecessor rejects rather than inventing sale provenance');
select is((select count(*) from ledger_private.uninvoiced_item_returns where account_id='account-primary'),0::bigint,'Missing provenance rolls back the earlier Item too');
rollback to origin_case;
savepoint imported_observation_case;
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('return-item-observed','account-primary','Imported custody observation','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id,ended_at,ended_by_principal_id)
values('return-original-observed','account-primary','return-item-observed','business_inventory','2024-01-01','principal-owner','2025-01-01','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id,start_evidence)
values('return-project-observed','account-primary','return-item-observed','project','return-project','2025-01-01','principal-owner','import_observation');
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
 amount_minor_units,currency,created_at,created_by_principal_id)
values('return-charge-observed','account-primary','return-project','return-item-observed','return-project-observed',
 'category-furnishings',12345,'USD','2025-01-01','principal-owner');
select throws_ok($$select public.spike_read_uninvoiced_return_review('account-primary','return-project',array['return-item-observed'])$$,
 '42501',null,'Imported observation is not eligible even with adjacent Inventory timestamps');
select is((ledger_private.return_uninvoiced_items(replace(pg_temp.return_command('return-observation'),'-b"','-observed"'))).error_code,
 'return_origin_unproven','Imported observation cannot be promoted into recorded sale provenance');
select is((select count(*) from ledger_private.uninvoiced_item_returns where account_id='account-primary'),0::bigint,
 'Mixed recorded and observed selection creates no partial return');
select is((select count(*) from public.spike_item_placements where id in ('return-project-a','return-project-observed')
 and ended_at is null),2::bigint,'Both current placements survive rejected imported-observation return');
select is((select count(*) from ledger_private.item_charge_occurrences where id in ('return-charge-a','return-charge-observed')
 and withdrawn_at is null and revision=1),2::bigint,'Both original charges survive without revision or withdrawal');
rollback to imported_observation_case;
select is((ledger_private.return_uninvoiced_items(jsonb_set(pg_temp.return_command('return-placement')::jsonb,
 '{items,1,placementId}','"return-original-b"')::text)).error_code,
 'return_placement_stale','Historical placement cannot stand in for current placement');
select is((ledger_private.return_uninvoiced_items(jsonb_set(pg_temp.return_command('return-collision')::jsonb,
 '{items,1,inventoryPlacementId}','"return-inventory-a"')::text)).error_code,
 'return_integrity_conflict','Colliding successor identities reject the whole batch');
select is((select count(*) from ledger_private.uninvoiced_item_returns where account_id='account-primary'),0::bigint,'Identity conflict leaves no partial return');
savepoint paid_case;
select ledger_private.import_client_payment('return-payment','account-primary','return-project','client-existing',
 12345,'USD','synthetic-return','return-paid','\x01'::bytea);
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
values('return-paid','account-primary','return-project','client-existing','return-payment',1,'USD',12345);
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
 source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
values('return-paid-line','account-primary','return-paid',0,'USD','item','return-charge-b','return-item-b',1,
 'category-furnishings',12345,'Paid Item','{}');
update ledger_private.collected_invoices set sealed=true where id='return-paid';
select ok((select has_collected_invoice from ledger_private.item_return_reviews where id='return-charge-b'),'Collection updates derived marker atomically');
select throws_ok($$select public.spike_read_uninvoiced_return_review('account-primary','return-project',array['return-item-a','return-item-b'])$$,'42501',null,'Review refuses entire selection containing a paid charge');
select is((ledger_private.return_uninvoiced_items(pg_temp.return_command('return-collected'))).error_code,
 'return_charge_collected','Collected source is rejected even without a live membership');
select is((select count(*) from ledger_private.uninvoiced_item_returns where account_id='account-primary'),0::bigint,'Collected selection does not partially return unpaid Item');
rollback to paid_case;
insert into ledger_private.live_invoices(id,account_id,project_id,name,created_at,created_by_principal_id)
values ('return-live','account-primary','return-project','Live',now(),'principal-owner');
insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
values ('account-primary','return-live','item','return-charge-b',0);
select ok((select has_live_invoice from ledger_private.item_return_reviews where id='return-charge-b'),'Invoice membership updates derived marker');
savepoint truncate_review_case;
truncate ledger_private.live_invoice_memberships;
select ok((select not has_live_invoice from ledger_private.item_return_reviews where id='return-charge-b'),'Administrative truncation cannot leave a stale derived marker');
rollback to truncate_review_case;
select throws_ok($$select public.spike_read_uninvoiced_return_review('account-primary','return-project',array['return-item-b'])$$,'42501',null,'Review refuses live Invoice membership');
select is((ledger_private.return_uninvoiced_items(pg_temp.return_command('return-invoiced'))).error_code,
 'return_charge_invoiced','Live Invoice membership blocks this command');
select is((select count(*) from ledger_private.uninvoiced_item_returns where account_id='account-primary'),0::bigint,'Failed batch retains no return facts');
update ledger_private.live_invoice_memberships set released_at=clock_timestamp() where invoice_id='return-live';
select ok((select not has_live_invoice and not has_collected_invoice from ledger_private.item_return_reviews where id='return-charge-b'),'Release and rolled-back collection leave no stale marker');
savepoint limited_member_case;
update public.spike_account_memberships set role='employee',financial_access='none'
where account_id='account-primary' and principal_id='principal-owner';
select is(jsonb_array_length(public.spike_read_uninvoiced_return_review('account-primary','return-project',array['return-item-a'])->'items'),1,'Ordinary-category review does not require financial access');
savepoint hidden_category_case;
update public.spike_budget_categories set kind='fee' where account_id='account-primary' and id='category-furnishings';
set local role authenticated;
select throws_ok($$select public.spike_read_uninvoiced_return_review('account-primary','return-project',array['return-item-a'])$$,'42501',null,'Hidden category does not leak return references');
select is((public.spike_return_uninvoiced_items(pg_temp.return_command('return-hidden'))).error_code,
 'return_charge_unavailable','Writer also denies hidden-category return');
reset role;
rollback to hidden_category_case;
savepoint removed_review_case;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select throws_ok($$select public.spike_read_uninvoiced_return_review('account-primary','return-project',array['return-item-a'])$$,'42501',null,'Removed member cannot review otherwise eligible Items');
reset role;
rollback to removed_review_case;
set local role authenticated;
select throws_ok($$select public.spike_read_uninvoiced_return_review('account-foreign','return-project',array['return-item-a'])$$,'42501',null,'Foreign Account review denied');
reset role;
select is((ledger_private.return_uninvoiced_items(pg_temp.return_command('return-member'))).phase,
 'applied','Active member can return ordinary-category Items without full financial access');
rollback to limited_member_case;
set local role authenticated;
select is((public.spike_return_uninvoiced_items(pg_temp.return_command('return-success'))).phase,'applied','Authenticated endpoint returns uninvoiced selection');
reset role;
select is((ledger_private.return_uninvoiced_items(pg_temp.return_command('return-success'))).phase,'applied','Exact replay is stable');
select throws_ok($$select ledger_private.return_uninvoiced_items(pg_temp.return_command('return-success','2'))$$,'23505',null,'Changed replay is rejected');
select is((select count(*) from ledger_private.uninvoiced_item_returns where account_id='account-primary'),2::bigint,'One retained return per charge');
select is((select count(*) from public.spike_item_placements where id in ('return-inventory-a','return-inventory-b') and scope_kind='business_inventory' and ended_at is null),2::bigint,'Items now in Inventory');
select is((select count(*) from public.spike_item_placements where id in ('return-project-a','return-project-b') and ended_at is not null),2::bigint,'Original Project placement history retained');
select is((select sum(amount_minor_units)::bigint from ledger_private.item_charge_occurrences where project_id='return-project' and withdrawn_at is null),null::bigint,'No remaining active charge');
select is((select count(*) from ledger_private.item_charge_occurrences where project_id='return-project' and withdrawn_at is not null and revision=2 and amount_minor_units=12345),2::bigint,'Withdrawal preserves original amount and advances revision');
select is((select count(*) from public.spike_transactions),(select n from before_transactions),'No payment or refund created');
select is((select count(*) from ledger_private.item_return_reviews where account_id='account-primary' and project_id='return-project' and withdrawn and revision=2),2::bigint,'Return withdraws derived eligibility without changing money');
select is((select count(*) from ledger_private.item_return_reviews p
 join ledger_private.uninvoiced_item_returns r on r.id=p.return_occurrence_id and r.account_id=p.account_id
 where p.account_id='account-primary' and p.project_id='return-project'
   and r.charge_id=p.id and r.item_id=p.item_id and r.inventory_placement_id=p.inventory_placement_id),
 2::bigint,'Derived history links exact return, original charge, same Item and successor placement');
select ok(not has_table_privilege('authenticated','ledger_private.item_return_reviews','SELECT,INSERT,UPDATE,DELETE'),'Clients have no direct derived-table privileges');
select throws_ok($$select public.spike_read_uninvoiced_return_review('account-primary','return-project',array['return-item-a'])$$,'42501',null,'Returned charge no longer reviewable');
select throws_ok($$delete from ledger_private.uninvoiced_item_returns where id='return-occurrence-a'$$,'55000',null,'Return history immutable');
select ok(has_function_privilege('authenticated','public.spike_return_uninvoiced_items(text)','EXECUTE'),'Authenticated role can invoke narrow endpoint');
select ok(not has_function_privilege('anon','public.spike_return_uninvoiced_items(text)','EXECUTE'),'Anonymous role has no endpoint grant');
select ok(not has_function_privilege('service_role','public.spike_return_uninvoiced_items(text)','EXECUTE'),'No service-role bypass endpoint');
select ok(not has_table_privilege('authenticated','ledger_private.uninvoiced_item_returns','SELECT'),'No direct history access');
savepoint removed_member_case;
update public.spike_account_memberships set state='removed'
where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select ledger_private.return_uninvoiced_items(pg_temp.return_command('return-success'))$$,
 '42501',null,'Removed member cannot replay an earlier accepted operation');
rollback to removed_member_case;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select throws_ok($$select ledger_private.return_uninvoiced_items(pg_temp.return_command('return-foreign'))$$,'42501',null,'Foreign actor cannot impersonate owner');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select public.spike_read_uninvoiced_return_review('account-primary','return-project',array['return-item-a'])$$,'42501',null,'Anonymous review denied');
select throws_ok($$select ledger_private.return_uninvoiced_items(pg_temp.return_command('return-anon'))$$,'42501',null,'Anonymous caller denied');
select * from finish();
rollback;
