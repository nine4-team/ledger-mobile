-- Physical Item identity, not authentication identity.
begin;
set local search_path = public, extensions;
select no_plan();
create temporary table cash_before as select count(*) as total from public.spike_transactions;

insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('placement-project-a','account-primary','client-existing','Placement A',now(),now(),1,1,'principal-owner'),
  ('placement-project-b','account-primary','client-existing','Placement B',now(),now(),1,1,'principal-owner');
insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name)
values ('placement-space-a','account-primary','project','placement-project-a','Room'),
  ('placement-space-inventory','account-primary','business_inventory',null,'Warehouse');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('chair','account-primary','One physical chair','principal-owner');

create function pg_temp.place(p_id text,p_start timestamptz,p_end timestamptz default null,
  p_project text default null,p_space text default null,p_account text default 'account-primary')
returns void language sql as $$
  insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,
    started_at,ended_at,started_by_principal_id,ended_by_principal_id)
  values(p_id,p_account,'chair',case when p_project is null then 'business_inventory' else 'project' end,
    p_project,p_space,p_start,p_end,'principal-owner',case when p_end is not null then 'principal-owner' end)
$$;

select lives_ok($$select pg_temp.place('inventory-first','2026-01-01',null,null,'placement-space-inventory')$$,'Initial inventory placement');
select is((select scope_kind from ledger_private.current_item_placements where item_id='chair'),'business_inventory','Current query reads inventory');
select throws_ok($$select pg_temp.place('overlap','2026-01-02')$$,'23P01',null,'Second active placement rejected');
select throws_ok($$select pg_temp.place('foreign','2025-01-01','2025-02-01',null,null,'account-other')$$,'23503',null,'Foreign Account cannot use Item identity');

-- A transaction failure must restore the closed interval too. This test helper
-- is not a public move command: actor policy and billing effects remain gated.
create function pg_temp.move(p_id text,p_at timestamptz,p_project text,p_space text default null)
returns void language plpgsql as $$
begin
  perform 1 from public.spike_items where id='chair' for update;
  update public.spike_item_placements set ended_at=p_at,ended_by_principal_id='principal-owner'
    where item_id='chair' and ended_at is null;
  perform pg_temp.place(p_id,p_at,null,p_project,p_space);
end;
$$;
select throws_ok($$select pg_temp.move('wrong-space','2026-02-01','placement-project-b','placement-space-a')$$,
  '23503',null,'Wrong Project Space rejected');
select is((select placement_id from ledger_private.current_item_placements where item_id='chair'),'inventory-first','Failed move rolls back closure');
select throws_ok($$select pg_temp.move('wrong-inventory-space','2026-02-01',null,'placement-space-a')$$,
  '23503',null,'Project Space cannot be assigned to Inventory');
select throws_ok($$select pg_temp.move('wrong-project-space','2026-02-01','placement-project-a','placement-space-inventory')$$,
  '23503',null,'Inventory Space cannot be assigned to Project');

select lives_ok($$select pg_temp.move('project-first','2026-02-01','placement-project-a','placement-space-a')$$,'Inventory to Project preserves first interval');
select lives_ok($$select pg_temp.move('inventory-return','2026-03-01',null)$$,'Physical return closes Project interval');
select lives_ok($$select pg_temp.move('project-resale','2026-04-01','placement-project-b')$$,'Resale creates a new interval for same Item');
select is((select count(*) from public.spike_items where id='chair'),1::bigint,'All cycles keep one physical Item');
select is((select project_id from ledger_private.current_item_placements where item_id='chair'),'placement-project-b','Current query sees only latest Project');
select is((select array_agg(id order by started_at,id) from public.spike_item_placements where item_id='chair'),
  array['inventory-first','project-first','inventory-return','project-resale'],'All prior placements remain ordered and queryable');
select is((select space_id from public.spike_item_placements where id='project-first'),'placement-space-a','Prior Room identity survives moves');
select is((select count(*) from public.spike_transactions),(select total from cash_before),'Placement creates no fictional payment');

select throws_ok($$update public.spike_item_placements set project_id='placement-project-b' where id='project-first'$$,'55000',null,'Cannot rewrite prior location');
select throws_ok($$update public.spike_item_placements set ended_at=null,ended_by_principal_id=null where id='project-first'$$,'55000',null,'Cannot reopen old cycle');
select throws_ok($$update public.spike_item_placements set space_id='placement-space-a' where id='project-resale'$$,'55000',null,'Active location is not mutable in place');
select throws_ok($$delete from public.spike_item_placements where id='project-first'$$,'55000',null,'Cannot delete history');
select throws_ok('truncate public.spike_item_placements','55000',null,'Cannot truncate history');
select throws_ok($$select pg_temp.place('overlap-past','2026-02-15','2026-02-20')$$,'23P01',null,'Ended historical overlap rejected');
select throws_ok($$select pg_temp.place('empty-interval','2025-01-01','2025-01-01')$$,'23514',null,'Zero length interval rejected');
select throws_ok($$select pg_temp.place('infinite-start','-infinity','2025-01-01')$$,'23514',null,'Infinite history bound rejected');
select throws_ok($$update public.spike_items set id='different-chair',revision=2 where id='chair'$$,'55000',null,'Physical identity cannot change');
select throws_ok($$update public.spike_items set description='New label' where id='chair'$$,'40001',null,'Details update must advance revision');
select lives_ok($$update public.spike_items set description='Renamed chair',revision=2 where id='chair'$$,'Descriptive edit leaves location history intact');
select throws_ok($$delete from public.spike_items where id='chair'$$,'23503',null,'Item deletion cannot orphan placement evidence');
select throws_ok($$delete from public.spike_spaces where id='placement-space-a'$$,'23503',null,'Historical Space identity cannot be deleted');

select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class
  where oid in ('public.spike_items'::regclass,'public.spike_item_placements'::regclass)),'Both tables force RLS');
select ok((select bool_and(not has_table_privilege(r,t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'))
  from unnest(array['anon','authenticated','service_role']) r
  cross join unnest(array['public.spike_items','public.spike_item_placements','ledger_private.current_item_placements']) t),'No unapproved API grants');
select ok((select reloptions @> array['security_invoker=true'] from pg_class
  where oid='ledger_private.current_item_placements'::regclass),'Current query does not bypass caller rights');
set local role authenticated;
select throws_ok('select * from public.spike_items','42501',null,'Authenticated direct Item read remains denied');
select throws_ok('select * from public.spike_item_placements','42501',null,'Authenticated history read remains denied');
reset role;
select * from finish();
rollback;
