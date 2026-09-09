begin;
set local search_path = public, extensions;
select no_plan();

insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('link-project','account-primary','client-existing','Link',now(),now(),1,1,'principal-owner'),
  ('link-other-project','account-primary','client-existing','Other',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('link-item','account-primary','Chair','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
values ('link-placement','account-primary','link-item','project','link-project','2026-01-01','principal-owner');
insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency)
values ('link-payment','account-primary','link-project','client-existing',500,'USD'),
  ('link-other-payment','account-primary','link-other-project','client-existing',700,'USD');
create temporary table link_cash_before as select count(*) as count,sum(amount_minor_units) as amount from public.spike_transactions;

create function pg_temp.connect_item(p_id text, p_payment text default 'link-payment',
  p_account text default 'account-primary', p_project text default 'link-project',
  p_item text default 'link-item', p_client text default 'client-existing',
  p_start timestamptz default '2026-01-02') returns void language sql as $$
  insert into ledger_private.item_client_payment_connections(id,account_id,project_id,client_id,
    item_id,placement_id,transaction_id,started_at,started_by_principal_id)
  values(p_id,p_account,p_project,p_client,p_item,'link-placement',p_payment,p_start,'principal-owner')
$$;
-- Exercise foreign keys before installing the overlapping valid interval;
-- otherwise the exclusion index could mask the intended FK error.
select throws_ok($$select pg_temp.connect_item('foreign-project','link-other-payment')$$,'23503',null,'Rejects payment from another Project');
select throws_ok($$select pg_temp.connect_item('wrong-placement','link-other-payment','account-primary','link-other-project')$$,'23503',null,'Cannot relabel placement to payment Project');
select throws_ok($$select pg_temp.connect_item('foreign-account','link-payment','account-other')$$,'23503',null,'Rejects foreign Account');
select throws_ok($$select pg_temp.connect_item('wrong-item','link-payment','account-primary','link-project','other-item')$$,'23503',null,'Rejects different physical Item');
select throws_ok($$select pg_temp.connect_item('wrong-client','link-payment','account-primary','link-project','link-item','other-client')$$,'23503',null,'Rejects different Client');
select lives_ok($$select pg_temp.connect_item('connection')$$,'Links exact physical placement to real Client Purchase');
select throws_ok($$select pg_temp.connect_item('overlap')$$,'23P01',null,'Rejects overlapping duplicate connection');
select throws_ok($$update ledger_private.item_client_payment_connections set transaction_id='link-other-payment' where id='connection'$$,'55000',null,'Cannot rewrite linked payment');
select throws_ok($$delete from ledger_private.item_client_payment_connections where id='connection'$$,'55000',null,'Cannot delete relationship history');
select throws_ok('truncate ledger_private.item_client_payment_connections','55000',null,'Cannot truncate relationship history');
select throws_ok($$update ledger_private.item_client_payment_connections set ended_at='2026-01-01',ended_by_principal_id='principal-owner' where id='connection'$$,'23514',null,'Closure must be later than the connection start');
select throws_ok($$update ledger_private.item_client_payment_connections set ended_at='2026-02-01' where id='connection'$$,'23514',null,'Closure requires actor evidence');
select throws_ok($$update ledger_private.item_client_payment_connections set ended_at='infinity',ended_by_principal_id='principal-owner' where id='connection'$$,'23514',null,'Closure timestamp must be finite');
select lives_ok($$update ledger_private.item_client_payment_connections set ended_at='2026-02-01',ended_by_principal_id='principal-owner' where id='connection'$$,'Closes old relationship without erasing it');
select throws_ok($$update ledger_private.item_client_payment_connections set ended_at=null,ended_by_principal_id=null where id='connection'$$,'55000',null,'Cannot reopen a closed relationship');
select lives_ok($$select pg_temp.connect_item('later-connection','link-payment','account-primary','link-project','link-item','client-existing','2026-02-01')$$,'Adjacent new relationship preserves prior interval');
select is((select count(*) from ledger_private.item_client_payment_connections where placement_id='link-placement'),2::bigint,'Both relationship records retained');
select is((select count(*) from public.spike_transactions),(select count from link_cash_before),'Link does not create another payment');
select is((select sum(amount_minor_units) from public.spike_transactions),(select amount from link_cash_before),'Link does not change money');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='ledger_private.item_client_payment_connections'::regclass),'RLS enabled and forced');
select ok(not has_table_privilege(role_name,'ledger_private.item_client_payment_connections','SELECT,INSERT,UPDATE,DELETE'),
  role_name || ' gains no whole-table read or write authority') from unnest(array['anon','authenticated','service_role']) role_name;
select * from finish();
rollback;
