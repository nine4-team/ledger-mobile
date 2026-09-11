begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('purchase-read-project','account-primary','client-existing','Purchase read',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('purchase-read-item','account-primary','Item','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
values ('purchase-read-placement','account-primary','purchase-read-item','project','purchase-read-project','2026-09-01','principal-owner');
insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency)
values ('purchase-read-linked','account-primary','purchase-read-project','client-existing',9007199254740993,'USD'),
 ('purchase-read-unlinked','account-primary','purchase-read-project','client-existing',1,'USD');
insert into ledger_private.item_client_payment_connections(id,account_id,project_id,client_id,item_id,placement_id,transaction_id,started_at,started_by_principal_id)
values ('purchase-read-link','account-primary','purchase-read-project','client-existing','purchase-read-item','purchase-read-placement','purchase-read-linked','2026-09-02','principal-owner');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.spike_transactions where id like 'purchase-read-%'),1::bigint,'Full member reads only current Item-linked Purchase');
select is((select amount_minor_units::text from public.spike_transactions where id='purchase-read-linked'),'9007199254740993','Exact cents survive canonical read');
select is((select type||'/'||role||'/'||origin from public.spike_transactions where id='purchase-read-linked'),'purchase/standalone/firebase_client_payment','Canonical classification and origin preserved');
select throws_ok($$update public.spike_transactions set amount_minor_units=1 where id='purchase-read-linked'$$,'42501',null,'Read grant adds no update authority');
select throws_ok($$delete from public.spike_transactions where id='purchase-read-linked'$$,'42501',null,'Read grant adds no delete authority');
select throws_ok('select * from ledger_private.imported_transaction_sources','42501',null,'Source bytes remain private');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.spike_transactions),0::bigint,'Limited member cannot read Purchase money');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select is((select count(*) from public.spike_transactions where id like 'purchase-read-%'),0::bigint,'Other Account member cannot read Purchase');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000099","role":"authenticated"}',true);
select is((select count(*) from public.spike_transactions),0::bigint,'Unknown principal cannot read Purchases');
reset role;
update public.spike_account_memberships set financial_access='limited' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.spike_transactions),0::bigint,'Same JWT loses read on same-count financial downgrade');
reset role;
update public.spike_account_memberships set financial_access='full' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select is((select count(*) from public.spike_transactions where id='purchase-read-linked'),1::bigint,'Restored full member reads existing connection again');
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select is((select count(*) from public.spike_transactions),0::bigint,'Same JWT loses active linked Purchase after membership removal');
reset role;
update public.spike_account_memberships set state='active' where account_id='account-primary' and principal_id='principal-owner';
update public.spike_item_placements set ended_at='2026-09-03',ended_by_principal_id='principal-owner' where id='purchase-read-placement';
set local role authenticated;
select is((select count(*) from public.spike_transactions),0::bigint,'Ended placement revokes Purchase even with active link');
reset role;
set local role anon;
select throws_ok('select id from public.spike_transactions','42501',null,'Anonymous Purchase access ungranted');
reset role;
set local role service_role;
select throws_ok('select id from public.spike_transactions','42501',null,'Service API Purchase access ungranted');
reset role;
select ok((select bool_and(not has_table_privilege(r,'public.spike_transactions','INSERT,UPDATE,DELETE,TRUNCATE'))
 from unnest(array['anon','authenticated','service_role']) r),'All API payment writes remain ungranted');
select throws_ok($$update public.spike_transactions set amount_minor_units=1 where id='purchase-read-linked'$$,'55000',null,'Imported payment immutability survives read policy');
alter table public.spike_transactions add column test_private_amount bigint;
set local role authenticated;
select throws_ok('select test_private_amount from public.spike_transactions','42501',null,'New payment columns do not inherit reviewed read grants');
reset role;
select * from finish();
rollback;
