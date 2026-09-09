begin;
set local search_path=public,extensions;
select no_plan();

insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,
  created_at_ms,updated_at_ms,created_by_principal_id)
values ('aps-project','account-primary','client-existing','Parent read',now(),now(),1,1,'principal-owner');
insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
values
 ('aps-inventory','account-primary','business_inventory',null,'Archived inventory','archived'),
 ('aps-project-space','account-primary','project','aps-project','Archived project','archived'),
 ('aps-unused','account-primary','business_inventory',null,'Unreferenced archive','archived'),
 ('aps-ended','account-primary','business_inventory',null,'Former location','archived'),
 ('aps-active','account-primary','business_inventory',null,'Empty active location','active'),
 ('aps-foreign','account-other','business_inventory',null,'Foreign archive','archived');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('aps-item-inventory','account-primary','Inventory','principal-owner'),
 ('aps-item-project','account-primary','Project','principal-owner'),
 ('aps-item-ended','account-primary','Moved','principal-owner'),
 ('aps-spare','account-primary','Unplaced','principal-owner'),
 ('aps-item-foreign','account-other','Foreign','principal-other');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,
 started_at,started_by_principal_id,ended_at,ended_by_principal_id)
values
 ('aps-p-inventory','account-primary','aps-item-inventory','business_inventory',null,'aps-inventory',
  '2026-01-01','principal-owner',null,null),
 ('aps-p-project','account-primary','aps-item-project','project','aps-project','aps-project-space',
  '2026-01-01','principal-owner',null,null),
 ('aps-p-ended','account-primary','aps-item-ended','business_inventory',null,'aps-ended',
  '2026-01-01','principal-owner','2026-01-02','principal-owner'),
 ('aps-p-foreign','account-other','aps-item-foreign','business_inventory',null,'aps-foreign',
  '2026-01-01','principal-other',null,null);

select throws_ok($$insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,
 started_at,started_by_principal_id) values ('aps-wrong-scope','account-primary','aps-spare','project',
 'aps-project','aps-inventory','2026-01-01','principal-owner')$$,'23503',null,
 'Exact parent FK rejects Project placement pointing at Inventory Space');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select display_name from public.spike_spaces where id='aps-inventory'),'Archived inventory',
 'Active limited member reads exact current archived Inventory parent with NULL Project');
select is((select display_name from public.spike_spaces where id='aps-project-space'),'Archived project',
 'Existing current archived Project parent remains readable');
select is((select count(*) from public.spike_spaces where id='aps-unused'),0::bigint,
 'Unreferenced archive remains hidden');
select is((select count(*) from public.spike_spaces where id='aps-ended'),0::bigint,
 'Ended-only parent remains hidden');
select is((select count(*) from public.spike_spaces where id='aps-foreign'),0::bigint,
 'Current parent in another Account remains hidden');
select results_eq($$select id from public.spike_spaces where account_id='account-primary'
 and scope_kind='business_inventory' and project_id is null and lifecycle='active' and id like 'aps-%' order by id$$,
 $$values ('aps-active'::text)$$,
 'Existing active-only directory shape includes empty active Space, not archived parents');
select throws_ok($$update public.spike_spaces set display_name='Changed' where id='aps-inventory'$$,
 '42501',null,'Readable archived parent does not gain UPDATE');
select throws_ok($$delete from public.spike_spaces where id='aps-inventory'$$,
 '42501',null,'Readable archived parent does not gain DELETE');
select throws_ok($$insert into public.spike_spaces(id,account_id,scope_kind,display_name)
 values ('aps-new','account-primary','business_inventory','Unauthorized')$$,
 '42501',null,'Parent read does not grant INSERT');

select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select is((select count(*) from public.spike_spaces where id in ('aps-inventory','aps-project-space')),0::bigint,
 'Foreign principal cannot read primary Account parents');
select is((select count(*) from public.spike_spaces where id='aps-foreign'),1::bigint,
 'Foreign principal still reads its own exact current parent');
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
select is((select count(*) from public.spike_spaces where id like 'aps-%'),0::bigint,
 'Authenticated role without subject has no parent visibility');
reset role;

-- Same JWT loses parent visibility immediately when its membership is removed.
update public.spike_account_memberships set state='removed'
 where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.spike_spaces where id like 'aps-%'),0::bigint,
 'Removed membership cannot read retained parent rows');
reset role;
set local role anon;
select throws_ok('select id from public.spike_spaces','42501',null,'Anonymous parent reads remain ungranted');
reset role;

-- Removing the only current reference hides the parent without deleting history.
update public.spike_item_placements set ended_at='2026-01-03',ended_by_principal_id='principal-owner'
 where id='aps-p-inventory';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.spike_spaces where id='aps-inventory'),0::bigint,
 'Parent disappears when its last current placement ends');
select is((select count(*) from public.spike_spaces where id='aps-project-space'),1::bigint,
 'Unchanged Project parent remains visible to full member');
reset role;
select * from finish();
rollback;
