begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
 values('assign-project','account-primary','client-existing','Assignment QA',now(),now(),1,1,'principal-owner');
insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
 select 'assign-space-'||v,'account-primary','project','assign-project',v,'active' from unnest(array['a','b','c']) v;
insert into public.spike_items(id,account_id,description,created_by_principal_id)
 select 'assign-item-'||v,'account-primary',v,'principal-owner' from unnest(array['a','b']) v;
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at,started_by_principal_id)
 select 'assign-placement-'||v,'account-primary','assign-item-'||v,'project','assign-project','assign-space-'||v,'2026-01-01','principal-owner'
 from unnest(array['a','b']) v;
create function pg_temp.assignment(op text, revision text default '1', destination text default 'assign-space-c') returns text language sql as $$
 select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
   'contractVersion','item-space-v1','createdAtMs','1788523200000','scopeKind','project','projectId','assign-project',
   'destinationSpaceId',destination,'expectedSpaceRevision',case when destination is not null then '1' end,
   'items',(select jsonb_agg(jsonb_build_object('itemId','assign-item-'||v,'expectedRevision',revision,
      'currentSpaceId',case when destination is null then 'assign-space-'||v end) order by v)
      from unnest(array['a','b']) v))::text;
$$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((ledger_private.set_item_spaces(pg_temp.assignment('assign-bulk'))).phase,'applied','Bulk assignment applies');
select is((select count(*) from public.spike_item_placements where item_id in ('assign-item-a','assign-item-b') and space_id='assign-space-c'),2::bigint,'Both Items move to chosen Space');
select is((select sync_current_item_count from public.spike_spaces where id='assign-space-c'),2::bigint,'Bulk destination count is exact');
select is((select sum(sync_current_item_count) from public.spike_spaces where id in ('assign-space-a','assign-space-b')),0::numeric,'Both old Spaces are empty');
select is((ledger_private.set_item_spaces(pg_temp.assignment('assign-bulk'))).phase,'applied','Exact retry returns original success');
select is((select count(*) from ledger_private.item_space_changes where item_id in ('assign-item-a','assign-item-b')),2::bigint,'Retry adds no changes');
select throws_ok($$select ledger_private.set_item_spaces(pg_temp.assignment('assign-bulk','2'))$$,'23505',null,'Changed retry cannot reuse identity');
select is((ledger_private.set_item_spaces(pg_temp.assignment('assign-stale','1','assign-space-a'))).error_code,'space_item_stale','Reject stale placement token');
select is((select count(*) from public.spike_item_placements where item_id in ('assign-item-a','assign-item-b') and space_id='assign-space-c'),2::bigint,'Rejected batch does not partially move Items');
select is((ledger_private.set_item_spaces(jsonb_set(pg_temp.assignment('assign-partial','2','assign-space-a')::jsonb,'{items,1,expectedRevision}','"1"')::text)).phase,'rejected','Second stale Item rolls back first mutation');
select is((select revision from public.item_placement_versions where id='assign-item-a'),2::bigint,'Partial failure rolls back version');
select is((select count(*) from ledger_private.item_space_changes where item_id='assign-item-a'),1::bigint,'Partial failure rolls back history');
select is((ledger_private.set_item_spaces(pg_temp.assignment('clear-wrong-space','2',null))).error_code,'space_item_stale','Clear validates exact old Space');
-- Restore different current Spaces through the handler, then clear atomically.
select is((ledger_private.set_item_spaces(jsonb_set(pg_temp.assignment('assign-a','2','assign-space-a')::jsonb,'{items}',
  '[{"itemId":"assign-item-a","expectedRevision":"2","currentSpaceId":null}]')::text)).phase,'applied','Single Item assignment supported');
select is((ledger_private.set_item_spaces(jsonb_set(pg_temp.assignment('assign-b','2','assign-space-b')::jsonb,'{items}',
  '[{"itemId":"assign-item-b","expectedRevision":"2","currentSpaceId":null}]')::text)).phase,'applied','Second Item can choose different Space');
select is((ledger_private.set_item_spaces(pg_temp.assignment('clear-both','3',null))).phase,'applied','Clear permits different old Spaces in same scope');
select is((select count(*) from public.spike_item_placements where item_id in ('assign-item-a','assign-item-b') and space_id is null and ended_at is null),2::bigint,'Clear preserves both open custody intervals');
select is((ledger_private.set_item_spaces(pg_temp.assignment('clear-both','3',null))).phase,'applied','Clear is retry-safe');
select is((select count(*) from ledger_private.item_space_changes where item_id in ('assign-item-a','assign-item-b')),6::bigint,'Exactly three retained Space changes per Item');
update public.spike_spaces set lifecycle='archived',revision=revision+1 where id='assign-space-c';
select is((ledger_private.set_item_spaces(pg_temp.assignment('archived-destination','4'))).error_code,'space_destination_unavailable','Archived destination rejected');
select is((ledger_private.set_item_spaces(jsonb_set(pg_temp.assignment('stale-destination','4','assign-space-a')::jsonb,'{expectedSpaceRevision}','"999"')::text)).error_code,'space_destination_stale','Exact destination revision required');
select throws_ok($$select ledger_private.set_item_spaces(jsonb_set(pg_temp.assignment('duplicate')::jsonb,'{items,1,itemId}','"assign-item-a"')::text)$$,'22023',null,'Duplicate physical Item rejected');
select throws_ok($$select ledger_private.set_item_spaces(jsonb_set(pg_temp.assignment('actor')::jsonb,'{actorPrincipalId}','"principal-restricted"')::text)$$,'42501',null,'Forged actor rejected');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.set_item_spaces(pg_temp.assignment('anonymous'))$$,'42501',null,'Missing authentication rejected');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select throws_ok($$select ledger_private.set_item_spaces(jsonb_set(pg_temp.assignment('foreign')::jsonb,'{actorPrincipalId}','"principal-other"')::text)$$,'42501',null,'Foreign actor cannot mutate Account');
select ok(not has_function_privilege('authenticated','ledger_private.set_item_spaces(text)','EXECUTE'),'Unfinished integration is not exposed to app');
select * from finish();
rollback;
