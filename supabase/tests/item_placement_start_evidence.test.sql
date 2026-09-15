begin;
set local search_path=public,extensions;
select no_plan();
select ok(has_column_privilege('authenticated','public.spike_item_placements','start_evidence','SELECT'),'Members can read start evidence under existing RLS');
select ok(not has_column_privilege('anon','public.spike_item_placements','start_evidence','SELECT'),'Anonymous cannot read start evidence');
select ok(not has_column_privilege('authenticated','public.spike_item_placements','start_evidence','UPDATE'),'Clients cannot rewrite start evidence');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('start-evidence-item','account-primary','Observed Item','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id,start_evidence)
values('start-evidence-placement','account-primary','start-evidence-item','business_inventory','2026-01-01','principal-owner','import_observation');
select is((select start_evidence from public.spike_item_placements where id='start-evidence-placement'),'import_observation','Import observation survives storage');
select throws_ok($$update public.spike_item_placements set start_evidence='recorded_move',ended_at='2026-02-01',ended_by_principal_id='principal-owner' where id='start-evidence-placement'$$,
  '55000','Placement start evidence is immutable','Closing cannot rewrite an observation as a known move');
select lives_ok($$update public.spike_item_placements set ended_at='2026-02-01',ended_by_principal_id='principal-owner' where id='start-evidence-placement'$$,'Observation interval can close on a later actual move');
select is((select start_evidence from public.spike_item_placements where id='start-evidence-placement'),'import_observation','Closed observation keeps its meaning');
select * from finish();
rollback;
