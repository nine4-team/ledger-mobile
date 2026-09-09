begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_items(id,account_id,description,source,current_source,created_by_principal_id)
values ('origin-vendor','account-primary','Moved',' Original vendor ','Design Inventory','principal-owner'),
 ('origin-blank','account-primary','Explicit blank','Vendor','','principal-owner'),
 ('origin-unknown','account-primary','Unknown',null,null,'principal-owner'),
 ('origin-foreign','account-other','Foreign','Secret vendor','Secret origin','principal-other');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select source from public.spike_items where id='origin-vendor'),' Original vendor ','Original vendor preserves exact bytes');
select is((select current_source from public.spike_items where id='origin-vendor'),'Design Inventory','Immediate origin is distinct from original vendor');
select is((select current_source from public.spike_items where id='origin-blank'),'','Explicit blank does not become null or vendor');
select is((select source from public.spike_items where id='origin-unknown'),null::text,'Missing vendor remains unknown');
select is((select current_source from public.spike_items where id='origin-unknown'),null::text,'Missing immediate origin remains unknown');
select is((select count(id) from public.spike_items where id='origin-foreign'),0::bigint,'Foreign Account sources remain denied');
select throws_ok($$update public.spike_items set source='Changed',revision=2 where id='origin-vendor'$$,
 '42501',null,'Source read does not grant editing');
select throws_ok($$update public.spike_items set current_source='Changed',revision=2 where id='origin-vendor'$$,
 '42501',null,'Immediate origin read does not grant movement');
reset role;
update public.spike_account_memberships set state='removed'
 where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select is((select count(id) from public.spike_items where id like 'origin-%'),0::bigint,'Same JWT loses source evidence after removal');
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
select is((select count(id) from public.spike_items where id like 'origin-%'),0::bigint,'No subject cannot read source evidence');
reset role;
set local role anon;
select throws_ok('select source,current_source from public.spike_items','42501',null,'Anonymous source read remains ungranted');
reset role;
select * from finish();
rollback;
