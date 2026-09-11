begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('report-fields-project','account-primary','client-existing','Report property',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,name,description,sku,market_value_minor_units,market_value_currency,created_by_principal_id)
values ('report-unknown','account-primary',null,'Description is not a name',null,null,null,'principal-owner'),
 ('report-zero','account-primary','Chair','Upholstered','SKU-Z',0,'USD','principal-owner'),
 ('report-exact','account-primary','Table','Wood','SKU-E',9007199254740993,'USD','principal-owner'),
 ('report-foreign','account-other','Foreign item','Other Account',null,1,'USD','principal-other'),
 ('report-signed','account-primary','Signed source','Preserved evidence',null,-1,'USD','principal-owner');
insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
values ('report-archived-room','account-primary','project','report-fields-project','Archived room','archived'),
 ('report-unused-room','account-primary','project','report-fields-project','Unoccupied archived room','archived');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at,started_by_principal_id)
values ('report-room-placement','account-primary','report-zero','project','report-fields-project','report-archived-room','2026-09-01','principal-owner');
select is((select name from public.spike_items where id='report-unknown'),null::text,'Unknown name is not synthesized from description');
select is((select property_address from public.spike_projects where id='report-fields-project'),null::text,'Absent source address remains unknown');
select throws_ok($$update public.spike_items set market_value_minor_units=1,revision=2 where id='report-unknown'$$,'23514',null,'Known amount requires currency');
select throws_ok($$update public.spike_items set market_value_currency='USD',revision=2 where id='report-unknown'$$,'23514',null,'Currency alone does not invent an amount');
select throws_ok($$update public.spike_items set market_value_minor_units=1,market_value_currency='usd',revision=2 where id='report-unknown'$$,'23514',null,'Malformed currency rejected');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select market_value_minor_units from public.spike_items where id='report-unknown'),null::bigint,'Restricted member sees unknown valuation as NULL');
select is((select market_value_minor_units from public.spike_items where id='report-zero'),0::bigint,'Known zero survives distinctly');
select is((select market_value_minor_units::text from public.spike_items where id='report-exact'),'9007199254740993','Large integer valuation remains exact');
select is((select market_value_minor_units from public.spike_items where id='report-signed'),-1::bigint,'Signed source valuation is preserved, not silently discarded');
select is((select display_name from public.spike_spaces where id='report-archived-room'),'Archived room','Current Item retains readable archived Space parent');
select is((select count(id) from public.spike_spaces where id='report-unused-room'),0::bigint,'Unreferenced archived Space remains hidden');
select is((select name || ':' || description || ':' || sku from public.spike_items where id='report-zero'),'Chair:Upholstered:SKU-Z','Name, description and SKU are distinct report facts');
select is((select count(id) from public.spike_items where id='report-foreign'),0::bigint,'Cross-Account valuation remains denied');
select is((select count(id) from public.spike_projects where id='report-fields-project'),1::bigint,'Member can read report Project');
select throws_ok($$update public.spike_items set name='Changed',revision=2 where id='report-zero'$$,'42501',null,'Report fields grant no Item mutation');
select throws_ok($$update public.spike_projects set property_address='Invented' where id='report-fields-project'$$,'42501',null,'Report field grants no Project mutation');
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select is((select count(id) from public.spike_items where id like 'report-%'),0::bigint,'Same JWT cannot read after membership removal');
select is((select count(id) from public.spike_projects where id='report-fields-project'),0::bigint,'Project report header also denied after removal');
reset role;
set local role anon;
select throws_ok('select name,sku,market_value_minor_units from public.spike_items','42501',null,'Anonymous report Item reads denied');
reset role;
set local role service_role;
select throws_ok('select name,sku,market_value_minor_units from public.spike_items','42501',null,'Service-role Item reads remain ungranted');
reset role;
select * from finish();
rollback;
