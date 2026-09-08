begin;
set local search_path = public, extensions;
select no_plan();
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('read-chair','account-primary','Visible physical chair','principal-owner'),
  ('other-chair','account-other','Other Account','principal-other');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
values ('read-placement','account-primary','read-chair','business_inventory','2026-01-01','principal-owner'),
  ('other-placement','account-other','other-chair','business_inventory','2026-01-01','principal-other');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.spike_items where id='read-chair'),1::bigint,'Owner reads own physical Item');
select is((select count(id) from public.spike_item_placements where id='read-placement'),1::bigint,'Owner reads own placement');
select is((select count(*) from public.spike_items where account_id='account-other'),0::bigint,'Owner cannot read foreign Items');
select is((select count(id) from public.spike_item_placements where account_id='account-other'),0::bigint,'Owner cannot read foreign history');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select description from public.spike_items where id='read-chair'),'Visible physical chair','Employee with no financial access reads physical description');
select is((select item_id from public.spike_item_placements where id='read-placement'),'read-chair','Employee reads physical placement');
select throws_ok($$update public.spike_items set description='changed',revision=2 where id='read-chair'$$,'42501',null,'Employee cannot edit Items');
select throws_ok($$delete from public.spike_item_placements where id='read-placement'$$,'42501',null,'Employee cannot delete physical history');
select throws_ok('select * from public.spike_transactions','42501',null,'Physical read grants do not expose payment facts');
select throws_ok('select * from ledger_private.current_item_placements','42501',null,'Private operator query is not exposed');
reset role;
update public.spike_account_memberships set state='removed'
where account_id='account-primary' and principal_id=(select id from public.spike_principals where auth_user_id='10000000-0000-0000-0000-000000000002');
set local role authenticated;
select is((select count(*) from public.spike_items),0::bigint,'Removal denies subsequent reads with unchanged JWT');
select is((select count(id) from public.spike_item_placements),0::bigint,'Removal also denies placement reads');
reset role;
set local role anon;
select throws_ok('select id from public.spike_items','42501',null,'Anonymous Item read denied');
select throws_ok('select id from public.spike_item_placements','42501',null,'Anonymous placement read denied');
reset role;
set local role service_role;
select throws_ok('select id from public.spike_items','42501',null,'Service role is not granted Item access');
select throws_ok('select id from public.spike_item_placements','42501',null,'Service role is not granted placement access');
reset role;
-- A future financial column must not inherit physical read privileges.
alter table public.spike_items add column test_private_amount bigint;
alter table public.spike_item_placements add column test_private_amount bigint;
set local role authenticated;
select throws_ok('select test_private_amount from public.spike_items','42501',null,'New columns require explicit reviewed grants');
select throws_ok('select test_private_amount from public.spike_item_placements','42501',null,'New placement columns require explicit reviewed grants');
reset role;
select * from finish();
rollback;
