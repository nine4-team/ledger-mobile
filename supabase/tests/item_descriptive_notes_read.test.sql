begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_items(id,account_id,description,notes,created_by_principal_id)
values ('detail-notes','account-primary','Chair',E'  First line\nSecond line  ','principal-owner'),
 ('detail-empty','account-primary','Blank','','principal-owner'),
 ('detail-unknown','account-primary','Unknown',null,'principal-owner'),
 ('detail-foreign','account-other','Foreign','Secret','principal-other');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select notes from public.spike_items where id='detail-notes'),E'  First line\nSecond line  ','Member reads exact multiline descriptive evidence');
select is((select notes from public.spike_items where id='detail-empty'),'','Empty stays empty');
select is((select notes from public.spike_items where id='detail-unknown'),null::text,'Unknown stays null');
select is((select count(id) from public.spike_items where id='detail-foreign'),0::bigint,'Foreign Account notes denied');
select throws_ok($$update public.spike_items set notes='Changed',revision=2 where id='detail-notes'$$,'42501',null,'Read does not authorize notes edits');
select throws_ok($$insert into public.spike_items(id,account_id,notes) values('detail-write','account-primary','Denied')$$,'42501',null,'Read does not authorize Item creation');
select throws_ok($$delete from public.spike_items where id='detail-notes'$$,'42501',null,'Read does not authorize removal');
reset role;
update public.spike_account_memberships set state='removed'
 where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select is((select count(id) from public.spike_items where id like 'detail-%'),0::bigint,'Same JWT loses notes after membership removal');
select set_config('request.jwt.claims','{"role":"authenticated","user_metadata":{"account_id":"account-primary"}}',true);
select is((select count(id) from public.spike_items where id like 'detail-%'),0::bigint,'User metadata cannot authorize notes');
reset role;
set local role anon;
select throws_ok('select notes from public.spike_items','42501',null,'Anonymous notes read ungranted');
reset role;
select * from finish();
rollback;
