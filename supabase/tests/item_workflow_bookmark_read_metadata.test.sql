begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_items(id,account_id,description,workflow_status,bookmark,created_by_principal_id)
values ('metadata-unknown','account-primary','Unknown',null,null,'principal-owner'),
 ('metadata-legacy','account-primary','Legacy','  legacy sold  ',true,'principal-owner'),
 ('metadata-false','account-primary','Explicit','purchased',false,'principal-owner'),
 ('metadata-foreign','account-other','Other','returned',true,'principal-other');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select workflow_status from public.spike_items where id='metadata-legacy'),'  legacy sold  ',
 'Limited member reads unchanged legacy status bytes without accounting inference');
select is((select bookmark from public.spike_items where id='metadata-legacy'),true,'True bookmark remains true');
select is((select bookmark from public.spike_items where id='metadata-false'),false,'Explicit false remains false');
select is((select bookmark from public.spike_items where id='metadata-unknown'),null::boolean,'Missing bookmark remains null');
select is((select workflow_status from public.spike_items where id='metadata-unknown'),null::text,'Missing status remains null');
select is((select count(id) from public.spike_items where id='metadata-foreign'),0::bigint,'Foreign Account metadata denied');
select throws_ok($$update public.spike_items set bookmark=false,revision=2 where id='metadata-legacy'$$,
 '42501',null,'Bookmark read adds no writer authority');
select throws_ok($$update public.spike_items set workflow_status='returned',revision=2 where id='metadata-false'$$,
 '42501',null,'Status read adds no writer authority');
select throws_ok($$delete from public.spike_items where id='metadata-false'$$,'42501',null,'No delete grant');
reset role;
update public.spike_account_memberships set state='removed'
 where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select is((select count(id) from public.spike_items where id like 'metadata-%'),0::bigint,'Same JWT loses metadata after removal');
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
select is((select count(id) from public.spike_items where id like 'metadata-%'),0::bigint,'No subject cannot read metadata');
reset role;
set local role anon;
select throws_ok('select workflow_status,bookmark from public.spike_items','42501',null,'Anonymous metadata read ungranted');
reset role;
select * from finish();
rollback;
