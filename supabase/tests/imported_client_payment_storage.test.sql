begin;
set local search_path = public, extensions;
select plan(30);
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('project-import-payment','account-primary','client-existing','Import payment fixture',now(),now(),1,1,'principal-owner');

create function pg_temp.import_payment(p_id text default 'import-payment', p_amount bigint default 9007199254740993,
  p_bytes bytea default decode('007b7dff','hex'), p_account text default 'account-primary',
  p_client text default 'client-existing', p_currency text default 'USD') returns text
language sql as $$
  select ledger_private.import_client_payment(p_id,p_account,'project-import-payment',p_client,
    p_amount,p_currency,'source-account','source-payment',p_bytes)
$$;

select lives_ok('select pg_temp.import_payment()', 'Store imported payment and immutable source atomically');
select is((select amount_minor_units from public.spike_transactions where id='import-payment'),9007199254740993::bigint,'Integer cents remain exact');
select is((select source_bytes from ledger_private.imported_transaction_sources where transaction_id='import-payment'),decode('007b7dff','hex'),'Source bytes survive NUL and non-UTF8 without JSON coercion');
select is((select source_sha256 from ledger_private.imported_transaction_sources where transaction_id='import-payment'),encode(digest(decode('007b7dff','hex'),'sha256'),'hex'),'Evidence digest derives from stored bytes');
select lives_ok('select pg_temp.import_payment()', 'Identical retry succeeds');
select is((select count(*) from public.spike_transactions where id='import-payment'),1::bigint,'Retry does not duplicate money');
select throws_ok('select pg_temp.import_payment(p_amount => 1)','22000',null,'Changed amount conflicts');
select throws_ok('select pg_temp.import_payment(p_bytes => decode(''00'',''hex''))','22000',null,'Changed source bytes conflict');
select throws_ok('select pg_temp.import_payment(p_id => ''conflicting-import'')','22000',null,'One source cannot create two payments');
select is((select count(*) from public.spike_transactions where id='conflicting-import'),0::bigint,'Source conflict leaves no orphan target');
select throws_ok('select pg_temp.import_payment(p_id => ''foreign-import'',p_account => ''account-other'')','23503',null,'Cross-Account Project binding denied');
select throws_ok('update public.spike_transactions set amount_minor_units=1 where id=''import-payment''','55000',null,'Imported money is immutable');
select throws_ok('delete from ledger_private.imported_transaction_sources where transaction_id=''import-payment''','55000',null,'Source evidence cannot be deleted');
select throws_ok('select pg_temp.import_payment(p_id => ''bad-currency'',p_currency => ''usd'')','23514',null,'Currency must be explicit canonical code');
select throws_ok('select pg_temp.import_payment(p_id => ''bad-amount'',p_amount => -1)','23514',null,'No negative payment reinterpretation');
select throws_ok('select pg_temp.import_payment(p_id => ''bad-client'',p_client => ''wrong-client'')','23503',null,'Client must own exact Project');

set local role anon;
select throws_ok($$select ledger_private.import_client_payment('x','a','p','c',1,'USD','s','d','\x00'::bytea)$$,'42501',null,'Anonymous callers cannot invoke import');
reset role;
set local role authenticated;
select throws_ok('select * from public.spike_transactions','42501',null,'Financial read access remains closed pending policy');
reset role;
set local role service_role;
select throws_ok($$select ledger_private.import_client_payment('x','a','p','c',1,'USD','s','d','\x00'::bytea)$$,'42501',null,'Service API role cannot invoke operator import');
reset role;
select throws_ok('truncate ledger_private.imported_transaction_sources','55000',null,'Source truncation is forbidden');
select throws_ok('truncate public.spike_transactions cascade','55000',null,'Payment truncation is forbidden');
select ok((select bool_and(not has_table_privilege(r, 'public.spike_transactions','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
  and not has_table_privilege(r, 'ledger_private.imported_transaction_sources','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'))
  from unnest(array['anon','authenticated','service_role']) r),'All API roles lack direct table grants');
select ok((select bool_and(not has_function_privilege(r,
  'ledger_private.import_client_payment(text,text,text,text,bigint,text,text,text,bytea)','EXECUTE'))
  from unnest(array['anon','authenticated','service_role']) r),'No API role inherits import execution');
select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class
  where oid in ('public.spike_transactions'::regclass,'ledger_private.imported_transaction_sources'::regclass)),
  'Both relations enforce RLS as defense in depth');
select throws_ok('delete from public.spike_transactions where id=''import-payment''','55000',null,'Imported target cannot be deleted');
select throws_ok('update ledger_private.imported_transaction_sources set source_bytes=''\x00''::bytea where transaction_id=''import-payment''','55000',null,'Source bytes cannot be rewritten');
select throws_ok('select pg_temp.import_payment(p_id => ''empty-evidence'',p_bytes => ''\x''::bytea)','23514',null,'Empty evidence rejected');
select throws_ok('select pg_temp.import_payment(p_id => ''oversize-evidence'',p_bytes => decode(repeat(''00'',4194305),''hex''))','23514',null,'Oversize evidence rejected');
select is((select type || '/' || role || '/' || origin from public.spike_transactions where id='import-payment'),
  'purchase/standalone/firebase_client_payment','Retry preserves exact classification');
select ok((select not prosecdef and proconfig @> array['search_path=""'] from pg_proc
  where oid='ledger_private.import_client_payment(text,text,text,text,bigint,text,text,text,bytea)'::regprocedure),
  'Importer retains invoker rights and empty search path');
select * from finish();
rollback;
